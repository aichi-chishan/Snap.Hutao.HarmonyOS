/** Automatic sign-in is always noninteractive. Manual SignInService retains foreground verification. */
import { UserService } from './UserService';
import { UserRepo } from '../data/repo/UserRepo';
import { BackgroundTaskRepo } from '../data/repo/BackgroundTaskRepo';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { AppContextProvider } from '../common/AppContext';
import { RegionUtil, RetCodes } from '../common/Constants';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { ApiResponse } from '../model/ApiResponse';
import { User } from '../model/User';
import { SignInInfo } from '../model/SignInInfo';
import { BackgroundTaskGuard, BackgroundTaskKind, BackgroundTaskPolicy, BackgroundTaskResult,
  BackgroundOperation, BackgroundTaskState } from '../model/BackgroundTask';

class ForegroundSignInGuard implements BackgroundTaskGuard {
  private user: User;
  private uid: string;
  private region: string;
  private epoch: number;
  private revision: number;
  private deadline: number = Date.now() + BackgroundTaskPolicy.BUDGET_MS;
  constructor(user: User, uid: string, region: string, epoch: number, revision: number) {
    this.user = user; this.uid = uid; this.region = region; this.epoch = epoch;
    this.revision = revision;
  }
  async isActive(): Promise<boolean> {
    if (PreferencesStore.getBackupJournal().length > 0 || UserService.getInstance().sessionRevision() !== this.revision ||
      !PreferencesStore.getAutoSignInEnabled() || Date.now() >= this.deadline ||
      UserService.getInstance().getCurrentUser() !== this.user || PreferencesStore.getCurrentUid() !== this.uid) { return false; }
    if ((await BackgroundTaskRepo.get(BackgroundTaskKind.SIGN_IN)).epoch !== this.epoch) { return false; }
    const saved: User | undefined = await UserRepo.getUserById(this.user.id);
    return saved !== undefined && BackgroundTaskPolicy.identity(saved) === BackgroundTaskPolicy.identity(this.user) &&
      BackgroundTaskPolicy.owns(saved, this.uid, this.region) && UserService.getInstance().getCurrentUser() === this.user &&
      PreferencesStore.getAutoSignInEnabled() && PreferencesStore.getCurrentUid() === this.uid &&
      UserService.getInstance().sessionRevision() === this.revision && PreferencesStore.getBackupJournal().length === 0;
  }
}

export class AutoSignInService {
  private static instance: AutoSignInService = new AutoSignInService();
  static getInstance(): AutoSignInService { return AutoSignInService.instance; }

  async bootstrapAutoSignIn(): Promise<void> {
    if (!PreferencesStore.getAutoSignInEnabled()) { return; }
    await this.runOnce(PreferencesStore.getCurrentUid());
  }

  /** Foreground bootstrap shares the durable per-account/UID lease with native work. */
  async runOnce(uid: string): Promise<void> {
    const revision: number = UserService.getInstance().sessionRevision();
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    const region: string = RegionUtil.regionOfUid(uid);
    if (!PreferencesStore.getAutoSignInEnabled() || user === undefined || !user.hasCookie() ||
      uid !== PreferencesStore.getCurrentUid() || !BackgroundTaskPolicy.owns(user, uid, region)) { return; }
    try {
      await BackgroundTaskRepo.init(AppContextProvider.getAppContext());
      const epoch: number = (await BackgroundTaskRepo.get(BackgroundTaskKind.SIGN_IN)).epoch;
      await this.runBackground(user, uid, region, new ForegroundSignInGuard(user, uid, region, epoch, revision));
    } catch (e) {
      // No UI, token exchange, permission request, credential or UID logging from automatic work.
    }
  }

  /** Explicit settings action; clears only this owner's current server-day block, never opens auth UI. */
  async retryCurrent(): Promise<BackgroundTaskResult> {
    if (!PreferencesStore.getAutoSignInEnabled()) {
      return BackgroundTaskResult.of('disabled', '请先开启启动自动签到');
    }
    const revision: number = UserService.getInstance().sessionRevision();
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    const uid: string = PreferencesStore.getCurrentUid();
    const region: string = RegionUtil.regionOfUid(uid);
    if (user === undefined || !BackgroundTaskPolicy.owns(user, uid, region)) {
      return BackgroundTaskResult.of('login_required', '请先登录并选择属于此账号的 UID');
    }
    try {
      await BackgroundTaskRepo.init(AppContextProvider.getAppContext());
      const epoch: number = (await BackgroundTaskRepo.get(BackgroundTaskKind.SIGN_IN)).epoch;
      const guard: ForegroundSignInGuard = new ForegroundSignInGuard(user, uid, region, epoch, revision);
      if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '账号或数据状态已变化，请稍后重试'); }
      const state: BackgroundTaskState = new BackgroundTaskState();
      state.kind = BackgroundTaskKind.SIGN_IN; state.userId = user.id; state.uid = uid; state.region = region;
      await BackgroundTaskRepo.clearBlocked(state);
      return await this.runBackground(user, uid, region, guard);
    } catch (e) { return BackgroundTaskResult.of('blocked', '自动签到暂不可用，请检查本地数据或登录状态'); }
  }

  /** Bound to an explicit owner. A failed/uncertain POST is checked with GET before another POST. */
  async runBackground(user: User, uid: string, region: string, guard: BackgroundTaskGuard): Promise<BackgroundTaskResult> {
    const day: string = BackgroundTaskPolicy.day(region);
    const op: BackgroundOperation = await BackgroundTaskRepo.operation(BackgroundTaskKind.SIGN_IN, user.id, uid, region);
    if (!BackgroundTaskPolicy.due(op, day, Date.now(), true)) {
      if (op.completedDay === day) { return BackgroundTaskResult.of('already_signed', '今日已签到', day); }
      if (op.day === day && (op.status === 'captcha' || op.status === 'login_required' || op.status === 'manual')) {
        return BackgroundTaskResult.of(op.status, '需要手动处理，请在应用内处理后重新排队');
      }
      return BackgroundTaskResult.of('cooldown', '已有任务在执行或仍在冷却，等待下次调度');
    }
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止或账号选择已变化'); }
    const token: string = `${Date.now()}-${Math.random()}`;
    if (!await BackgroundTaskRepo.claimOperation(op, day, token, Date.now())) {
      return BackgroundTaskResult.of('cooldown', '已有签到任务在执行，等待下次调度');
    }
    let result: BackgroundTaskResult = BackgroundTaskResult.of('retry', '签到未完成，等待下次调度');
    try {
      result = await this.signOwned(user, uid, region, guard);
      if (!await guard.isActive()) { result = BackgroundTaskResult.of('cancelled', '任务已停止，未提交本地成功状态'); }
    } catch (e) {
      result = BackgroundTaskResult.of('retry', '网络或安全凭据暂不可用，等待下次调度');
    }
    await BackgroundTaskRepo.finishOperation(op, token, result, 30);
    return result;
  }

  private async signOwned(user: User, uid: string, region: string, guard: BackgroundTaskGuard): Promise<BackgroundTaskResult> {
    if (!BackgroundTaskPolicy.owns(user, uid, region) || user.cookieToken.length === 0 || user.gameRecordCookie().length === 0) {
      return BackgroundTaskResult.of('login_required', '请在应用内补齐登录凭据后重新排队');
    }
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    const beforeDay: string = BackgroundTaskPolicy.day(region);
    const response: ApiResponse = await HoyolabClient.fetchSignInfo(uid, region, user.gameRecordCookie());
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    const blocked: BackgroundTaskResult | undefined = BackgroundTaskPolicy.resultForResponse(response);
    if (blocked !== undefined) { return blocked; }
    if (response.data === undefined) { return BackgroundTaskResult.of('retry', '未取得签到状态，稍后再试'); }
    const data: Record<string, Object> = response.data as Record<string, Object>;
    const signedFlag: Object = data['is_sign'];
    if (signedFlag !== true && signedFlag !== false && signedFlag !== 0 && signedFlag !== 1 &&
      signedFlag !== 'true' && signedFlag !== 'false') {
      return BackgroundTaskResult.of('retry', '签到状态格式异常，本次未提交签到');
    }
    const info: SignInInfo = SignInInfo.fromInfo(response.data);
    const day: string = /^\d{4}-\d{2}-\d{2}$/.test(info.serverDate) ? `${region}:${info.serverDate}` : beforeDay;
    if (day !== beforeDay || BackgroundTaskPolicy.day(region) !== beforeDay) {
      return BackgroundTaskResult.of('manual', '设备日期与服务器日期不一致，请检查系统时间后重新排队');
    }
    if (info.signedToday) { return BackgroundTaskResult.of('already_signed', '今日已签到', day); }
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    const signed: ApiResponse = await HoyolabClient.signIn(uid, region, user.gameRecordCookie());
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    const signBlocked: BackgroundTaskResult | undefined = BackgroundTaskPolicy.resultForResponse(signed);
    if (signBlocked !== undefined) { return signBlocked; }
    if (signed.retcode === RetCodes.ALREADY_SIGNED) { return BackgroundTaskResult.of('already_signed', '今日已签到', day); }
    if (BackgroundTaskPolicy.day(region) !== beforeDay) {
      return BackgroundTaskResult.of('retry', '跨日请求已结束，下次调度会先查询服务器签到状态');
    }
    return BackgroundTaskResult.of('success', '后台签到成功', day);
  }
}
