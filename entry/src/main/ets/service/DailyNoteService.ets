/**
 * DailyNoteService.ets
 * 便笺拉取（DS Gen2/X4 + Cookie + 1034 重试）；缓存刷新时间；阈值判定与本地通知；自动刷新定时器。
 * 注：AppStorage 为 ArkUI 全局对象，无需 import。
 */
import { formProvider, formBindingData, formInfo } from '@kit.FormKit';
import { User } from '../model/User';
import { UserRepo } from '../data/repo/UserRepo';
import { UserGameRole } from '../model/UserGameRole';
import { BackgroundTaskRepo } from '../data/repo/BackgroundTaskRepo';
import { AppContextProvider } from '../common/AppContext';
import { HoyolabEndpoints } from '../common/HoyolabEndpoints';
import { ServerTime } from '../common/ServerTime';
import { DailyNoteReminderService } from './DailyNoteReminderService';
import { UserService } from './UserService';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { ApiResponse } from '../model/ApiResponse';
import { DailyNoteWebhookClient } from '../data/network/DailyNoteWebhookClient';
import { DailyNoteRepo, DailyNoteRecord } from '../data/repo/DailyNoteRepo';
import { NotificationHelper } from '../data/local/NotificationHelper';
import { FormSnapshot, FormSnapshotOwner } from '../data/local/FormSnapshot';
import { DailyNote } from '../model/DailyNote';
import { DAILY_NOTE_PATH } from '../data/network/CardVerifyApi';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { RegionUtil, RetCodes } from '../common/Constants';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { Logger } from '../common/Logger';
import { BackgroundTaskGuard, BackgroundTaskKind, BackgroundTaskPolicy, BackgroundTaskResult } from '../model/BackgroundTask';

const TAG: string = 'DailyNoteService';

/** 需要人机验证（极验）的错误：携带 gt/challenge 供跳转验证页 */
export class NeedGeetestError extends Error {
  gt: string = '';
  challenge: string = '';

  constructor(gt: string, challenge: string) {
    super('风控拦截：需要人机验证');
    this.name = 'NeedGeetestError';
    this.gt = gt;
    this.challenge = challenge;
  }
}

/** 通知 ID 常量（固定，跨账号复用） */
export class NotifyIds {
  static readonly RESIN: number = 10001;
  static readonly EXPEDITION: number = 10002;
  static readonly DAILY_TASK: number = 10003;
  static readonly TRANSFORMER: number = 10004;
  static readonly HOME_COIN: number = 10005;
}

/** 通知开关位 */
export class NotifyFlags {
  static readonly RESIN: number = 1 << 0;
  static readonly EXPEDITION: number = 1 << 1;
  static readonly DAILY_TASK: number = 1 << 2;
  static readonly TRANSFORMER: number = 1 << 3;
  static readonly HOME_COIN: number = 1 << 4;
  static readonly ALL: number = 31;
}

/** AppStorage 键：便笺数据版本戳（服务层每次成功刷新后自增；便笺页/主页订阅后重读本地缓存） */
export const KEY_NOTE_VERSION: string = 'dailyNoteVersion';
/** AppStorage 键：最近一次后台刷新失败原因（供页面提示；成功刷新后清空） */
export const KEY_NOTE_ERROR: string = 'dailyNoteLastError';

class ForegroundNotePresentationGuard implements BackgroundTaskGuard {
  private user: User;
  private uid: string;
  private revision: number;
  constructor(user: User, uid: string, revision: number) { this.user = user; this.uid = uid; this.revision = revision; }
  async isActive(): Promise<boolean> {
    return UserService.getInstance().sessionRevision() === this.revision &&
      !UserService.getInstance().isSessionTransitionPending() && UserService.getInstance().getCurrentUser() === this.user &&
      PreferencesStore.getCurrentUid() === this.uid && PreferencesStore.getBackupJournal().length === 0;
  }
}

export class DailyNoteService {
  private static instance: DailyNoteService = new DailyNoteService();
  private timer: number = -1;
  private timerRunning: boolean = false;
  /** 当前定时器间隔（分钟）：同间隔重复 start 不重启计时 */
  private intervalMin: number = 0;
  /** 在途刷新标记（重入保护：手动/自动/卡片刷新共用） */
  private refreshing: boolean = false;

  static getInstance(): DailyNoteService {
    return DailyNoteService.instance;
  }

  static readonly WEBHOOK_KEY: string = 'dailynote.webhook_url';

  static webhookUrl(): string {
    return PreferencesStore.getString(DailyNoteService.WEBHOOK_KEY, '');
  }

  static setWebhookUrl(value: string): void {
    const target: string = value.trim();
    if (target.length > 0 && !/^https?:\/\/[^\s@/]+(?:[/?#][^\s]*)?$/.test(target)) {
      throw new Error('请输入有效的 HTTP 或 HTTPS 地址');
    }
    PreferencesStore.setString(DailyNoteService.WEBHOOK_KEY, target);
  }

  /** 手动/自动刷新便笺（重入保护：同一时刻仅一次在途请求）。
   * @param challenge 可选：极验通过后从 verifyVerification 换得的 challenge（重放头）
   */
  async refresh(uid: string, challenge?: string, interactive: boolean = true): Promise<DailyNote> {
    if (this.refreshing) {
      throw new Error('正在刷新中，请稍候');
    }
    this.refreshing = true;
    try {
      return await this.doRefresh(uid, challenge, interactive);
    } finally {
      this.refreshing = false;
    }
  }

  /** Native deferred work: explicit owner, one request, no token exchange, verification, permission or webhook path. */
  async refreshBackground(user: User, uid: string, region: string, guard: BackgroundTaskGuard): Promise<BackgroundTaskResult> {
    if (!BackgroundTaskPolicy.owns(user, uid, region) || user.cookieToken.length === 0 || user.gameRecordCookie().length === 0) {
      return BackgroundTaskResult.of('login_required', '请在应用内补齐登录凭据后重新排队');
    }
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    const extra: Record<string, string> = {};
    const response: ApiResponse = await HoyolabClient.fetchDailyNote(uid, region, user.gameRecordCookie(), extra);
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    const blocked: BackgroundTaskResult | undefined = BackgroundTaskPolicy.resultForResponse(response);
    if (blocked !== undefined) { return blocked; }
    if (response.data === undefined) { return BackgroundTaskResult.of('retry', '便笺响应为空，等待下次调度'); }
    const note: DailyNote = DailyNote.fromJson(response.data);
    note.refreshTime = Date.now();
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    await DailyNoteRepo.upsert(user.id, uid, note, (): Promise<boolean> => guard.isActive());
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    DailyNoteService.bumpVersion();
    // Native work refreshes the current binding's form snapshot. Notifications/reminders are
    // deliberately left to their already-authorized foreground flow; no permission UI can run here.
    await this.updateCardSnapshot(note, user.displayName, user.id, uid, guard, true);
    return BackgroundTaskResult.of('success', '后台便笺已刷新', BackgroundTaskPolicy.day(region));
  }

  /**
   * 追踪列表刷新（对齐 Windows 多 UID 追踪）：顺序刷新当前账号下全部被追踪 UID
   * （不含当前 UID——它已由常规刷新覆盖），单个失败不影响其余。
   */
  async refreshTrackedList(): Promise<number> {
    if (this.refreshing) {
      return 0;
    }
    this.refreshing = true;
    let ok: number = 0;
    try {
      const users: User[] = await UserRepo.getAllUsers();
      const current = UserService.getInstance().getCurrentUser();
      const currentUid: string = PreferencesStore.getCurrentUid();
      for (const user of users) {
        if (!user.hasCookie()) { continue; }
        const uids: string[] = PreferencesStore.getTrackedUids(user.id);
        for (const uid of uids) {
          if (current !== undefined && user.id === current.id && uid === currentUid) { continue; }
          try {
            // 后台不切换全局账号，不弹出另一个账号的验证窗口。
            await this.doRefresh(uid, undefined, false, user);
            ok++;
          } catch (e) {
            Logger.warn(TAG, `tracked refresh failed uid=${uid}: ${(e as Error).message}`);
          }
        }
      }
    } finally {
      this.refreshing = false;
    }
    return ok;
  }

  /** 实际刷新流程：网络拉取 → 落库 → 广播版本戳 → 卡片快照 → 阈值通知 */
  private async doRefresh(uid: string, challenge?: string, interactive: boolean = true, account?: User): Promise<DailyNote> {
    const revision: number = UserService.getInstance().sessionRevision();
    const user: User | undefined = account ?? UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    // 若缺 cookie_token/ltoken（旧账号），先用 SToken 补齐再拉取
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      if (!interactive) { throw new Error('请打开应用补齐登录凭据'); }
      await UserService.getInstance().completeTokenChainPublic(user);
    }
    const region: string = RegionUtil.regionOfUid(uid);
    const cookie: string = user.gameRecordCookie();
    if (cookie.length === 0) {
      throw new Error('账号缺少 cookie_token，请重新登录');
    }

    // 降低风控概率：请求前随机 600~1200ms 抖动
    await DailyNoteService.delay(600 + Math.floor(Math.random() * 600));

    // 重放头（风控验证后）
    const extra: Record<string, string> = {};
    if (challenge !== undefined && challenge.length > 0) {
      extra['x-rpc-challenge'] = challenge;
    }

    // 拉取
    let resp: ApiResponse = await HoyolabClient.fetchDailyNote(uid, region, cookie, extra);
    if (resp.isRiskControl()) {
      if (!interactive || HoyolabEndpoints.isOverseaRegion(region)) {
        throw new Error('请打开应用完成人机验证');
      }
      // 1034：自动弹统一验证窗，成功后带 challenge 服务内重放一次
      const replayChallenge: string = await RiskVerifier.tryResolveRisk(resp, cookie, DAILY_NOTE_PATH);
      if (replayChallenge.length === 0) {
        throw new Error('人机验证未完成或被取消，请稍后再试');
      }
      extra['x-rpc-challenge'] = replayChallenge;
      resp = await HoyolabClient.fetchDailyNote(uid, region, cookie, extra);
    }
    // Cookie 鉴权失效（-100/10001）：强制换新凭证后重试一次（对齐 Windows CookieToken 刷新）
    if (!resp.success && UserService.isCookieAuthError(resp)) {
      if (!interactive) { throw new Error('请打开应用重新登录'); }
      resp = await UserService.retryWithRefreshedCookie(user, (): Promise<ApiResponse> => {
        const retryExtra: Record<string, string> = {};
        for (const k of Object.keys(extra)) {
          retryExtra[k] = extra[k];
        }
        return HoyolabClient.fetchDailyNote(uid, region, user.gameRecordCookie(), retryExtra);
      });
    }
    if (!resp.success || resp.data === undefined) {
      if (resp.retcode === RetCodes.RISK_CONTROL) {
        throw new Error('被风控拦截，请稍后再试');
      }
      throw new Error(resp.userFriendlyMessage());
    }

    const note: DailyNote = DailyNote.fromJson(resp.data);
    note.refreshTime = Date.now();
    const prev: DailyNoteRecord | undefined = await DailyNoteRepo.get(user.id, uid);
    await DailyNoteRepo.upsert(user.id, uid, note);

    // 广播：本地缓存已更新（服务层自动刷新 / 桌面卡片刷新 / 页面手动刷新都会走到这里），
    // 便笺页与主页便笺卡订阅该版本戳后重读本地缓存，避免界面数值停滞。
    DailyNoteService.bumpVersion();
    DailyNoteService.clearError();

    // 验证通过后清掉暂存的 challenge
    if (challenge !== undefined && challenge.length > 0) {
      AppStorage.setOrCreate<string>('dailyNoteChallenge', '');
    }

    // 写卡片快照 + 主动更新全部桌面卡片
    // 默认桌面卡绑定当前 UID；刷新追踪 UID 不能覆盖当前账号的卡片。
    const currentUser = UserService.getInstance().getCurrentUser();
    if (currentUser !== undefined && user.id === currentUser.id && uid === PreferencesStore.getCurrentUid()) {
      await this.updateCardSnapshot(note, user.displayName, user.id, uid,
        new ForegroundNotePresentationGuard(user, uid, revision));
    }

    await this.evalAndNotify(user.id, uid, note, prev);
    try {
      await DailyNoteReminderService.sync(user.id, uid, note, prev);
    } catch (e) {
      AppStorage.setOrCreate<string>(DailyNoteReminderService.ERROR_KEY, (e as Error).message);
      Logger.warn(TAG, `agent reminder failed: ${(e as Error).message}`);
    }
    const webhook: string = DailyNoteService.webhookUrl();
    if (webhook.length > 0 && note.rawJson.length > 0) {
      try {
        await DailyNoteWebhookClient.send(webhook, uid, note.rawJson);
      } catch (e) {
        // 网络转发失败不能抹掉已成功更新的本地便笺。
        Logger.warn(TAG, `webhook failed: ${(e as Error).message}`);
      }
    }
    Logger.info(TAG, `refresh ok uid=${uid} resin=${note.currentResin}/${note.maxResin}`);
    return note;
  }

  /** 刷新成功后更新桌面卡片快照并主动推送 formProvider */
  private async updateCardSnapshot(note: DailyNote, nickname: string, userId: number, uid: string,
    guard: BackgroundTaskGuard, strict: boolean = false): Promise<void> {
    try {
      let expText: string = '派遣 --';
      if (note.maxExpeditionNum > 0) {
        const done: number = note.finishedExpeditionCount();
        expText = `派遣 ${done}/${note.maxExpeditionNum}`;
      }
      const daily: string = note.totalTaskNum > 0
        ? `每日 ${note.finishedTaskNum}/${note.totalTaskNum}${note.isExtraTaskRewardReceived ? ' ✔' : ''}`
        : '每日 --';
      const homeCoin: string = note.maxHomeCoin > 0 ? `洞天宝钱 ${note.currentHomeCoin}/${note.maxHomeCoin}` : '';
      const resinRecovery: string = note.resinRecoveryText();
      await BackgroundTaskRepo.init(AppContextProvider.getAppContext());
      const epoch: number = (await BackgroundTaskRepo.get(BackgroundTaskKind.DAILY_NOTE)).epoch;
      if (!await guard.isActive()) { return; }
      FormSnapshot.save(`${note.currentResin}`, `${note.maxResin}`, expText, daily, homeCoin, nickname,
        note.refreshTime, resinRecovery, userId, uid, epoch);
      if (!await guard.isActive()) {
        const owner: FormSnapshotOwner = FormSnapshot.owner();
        if (owner.userId === userId && owner.uid === uid && owner.epoch === epoch) { FormSnapshot.clear(); }
        return;
      }
      await this.pushAllCards(guard);
    } catch (e) {
      if (strict) { throw new Error('卡片缓存更新未完成'); }
      Logger.warn(TAG, 'card snapshot update failed');
    }
  }

  /** Local/session-transition hook: failure to clear durable snapshot is not swallowed. */
  async clearCardSnapshot(): Promise<void> {
    FormSnapshot.clear();
    await this.pushAllCards(undefined, true);
  }

  /** Cached-only widget updates must validate the owner and operational epoch before displaying any data. */
  async cardDataForCurrentOwner(): Promise<Record<string, string>> {
    const empty: Record<string, string> = FormSnapshot.empty();
    try {
      if (UserService.getInstance().isSessionTransitionPending() || PreferencesStore.getBackupJournal().length > 0) { return empty; }
      const owner: FormSnapshotOwner = FormSnapshot.owner();
      if (owner.userId <= 0 || owner.uid.length === 0 || owner.epoch < 0) { return empty; }
      if ((await BackgroundTaskRepo.get(BackgroundTaskKind.DAILY_NOTE)).epoch !== owner.epoch ||
        await UserRepo.getSelectedUserId() !== owner.userId) { return empty; }
      const user: User | undefined = await UserRepo.getUserById(owner.userId);
      const role: UserGameRole | undefined = await UserRepo.getDefaultRole(owner.userId);
      if (user === undefined || role === undefined || role.gameUid !== owner.uid ||
        !BackgroundTaskPolicy.owns(user, owner.uid, role.region)) { return empty; }
      const currentOwner: FormSnapshotOwner = FormSnapshot.owner();
      if (currentOwner.userId !== owner.userId || currentOwner.uid !== owner.uid || currentOwner.epoch !== owner.epoch ||
        (await BackgroundTaskRepo.get(BackgroundTaskKind.DAILY_NOTE)).epoch !== owner.epoch ||
        await UserRepo.getSelectedUserId() !== owner.userId || UserService.getInstance().isSessionTransitionPending() ||
        PreferencesStore.getBackupJournal().length > 0) { return empty; }
      return FormSnapshot.load();
    } catch (e) { return empty; }
  }

  /** Recheck after platform await so an in-flight old update is corrected after logout/reset. */
  async publishCard(formId: string, tip: string = '', guard?: BackgroundTaskGuard): Promise<void> {
    if (guard !== undefined && !await guard.isActive()) { return; }
    const data: Record<string, string> = await this.cardDataForCurrentOwner();
    if (guard !== undefined && !await guard.isActive()) { return; }
    data['tipText'] = tip;
    await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
    const latest: Record<string, string> = await this.cardDataForCurrentOwner();
    latest['tipText'] = guard !== undefined && !await guard.isActive() ? '' : tip;
    if (JSON.stringify(latest) !== JSON.stringify(data)) {
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(latest));
    }
  }

  private async pushAllCards(guard?: BackgroundTaskGuard, strict: boolean = false): Promise<void> {
    try {
      const forms: Array<formInfo.RunningFormInfo> = await formProvider.getPublishedRunningFormInfos();
      for (const form of forms) {
        if (guard !== undefined && !await guard.isActive()) { return; }
        if (form.formId.length > 0) { await this.publishCard(form.formId, '', guard); }
      }
    } catch (e) {
      if (strict) { throw new Error('桌面卡片清理未完成，请重试'); }
      Logger.warn(TAG, 'card update unavailable');
    }
  }

  /** 阈值判定 → 本地通知（边沿触发：仅当本次达标且上次未达标） */
  async evalAndNotify(userId: number, uid: string, note: DailyNote, prev: DailyNoteRecord | undefined): Promise<void> {
    if (!NotificationHelper.isEnabled()) {
      return;
    }
    const flags: number = prev !== undefined ? prev.notifyFlags : NotifyFlags.ALL;
    const resinTh: number = prev !== undefined ? prev.resinNotifyThreshold : 120;
    const homeTh: number = prev !== undefined ? prev.homeCoinNotifyThreshold : 1800;
    const prevNote: DailyNote | undefined = prev !== undefined ? prev.note : undefined;

    const hasRec = prev !== undefined && prevNote !== undefined;

    // 树脂
    if ((flags & NotifyFlags.RESIN) !== 0 && note.resinReached(resinTh)) {
      const wasMet: boolean = hasRec && prevNote.resinReached(resinTh);
      if (!wasMet) {
        await NotificationHelper.publish(`UID ${uid} · 树脂已达标`,
          `当前树脂 ${note.currentResin}/${note.maxResin}，已达阈值 ${resinTh}`, DailyNoteService.notificationId(uid, NotifyIds.RESIN));
      }
    }
    // 派遣全部完成
    if ((flags & NotifyFlags.EXPEDITION) !== 0) {
      const allDone: boolean = note.allExpeditionsFinished();
      if (allDone) {
        const wasDone: boolean = hasRec && prevNote.allExpeditionsFinished();
        if (!wasDone) {
          await NotificationHelper.publish(`UID ${uid} · 派遣已完成`, '所有派遣任务已完成', DailyNoteService.notificationId(uid, NotifyIds.EXPEDITION));
        }
      }
    }
    // 每日委托全部完成
    if ((flags & NotifyFlags.DAILY_TASK) !== 0) {
      // Windows 提醒条件是每日奖励未领取，包括尚未完成委托；服务器新日重新提醒。
      if (!note.isExtraTaskRewardReceived) {
        const region: string = RegionUtil.regionOfUid(uid);
        const sameDay: boolean = hasRec && prevNote.refreshTime > 0 &&
          ServerTime.date(region, prevNote.refreshTime) === ServerTime.date(region, note.refreshTime);
        const wasPending: boolean = hasRec && sameDay && !prevNote.isExtraTaskRewardReceived;
        if (!wasPending) {
          await NotificationHelper.publish(`UID ${uid} · 每日委托奖励未领取`, note.extraTaskRewardDescription(),
            DailyNoteService.notificationId(uid, NotifyIds.DAILY_TASK));
        }
      }
    }
    // 参变仪就绪
    if ((flags & NotifyFlags.TRANSFORMER) !== 0 && note.transformer.isReady()) {
      const wasReady: boolean = hasRec && prevNote.transformer.isReady();
      if (!wasReady) {
        await NotificationHelper.publish(`UID ${uid} · 参变仪就绪`, '参量质变仪已可使用', DailyNoteService.notificationId(uid, NotifyIds.TRANSFORMER));
      }
    }
    // 洞天宝钱
    if ((flags & NotifyFlags.HOME_COIN) !== 0 && note.homeCoinReached(homeTh)) {
      const wasMet: boolean = hasRec && prevNote.homeCoinReached(homeTh);
      if (!wasMet) {
        await NotificationHelper.publish(`UID ${uid} · 洞天宝钱已达标`,
          `当前宝钱 ${note.currentHomeCoin}/${note.maxHomeCoin}，已达阈值 ${homeTh}`, DailyNoteService.notificationId(uid, NotifyIds.HOME_COIN));
      }
    }
  }

  private static notificationId(uid: string, kind: number): number {
    let hash: number = 0;
    for (let i: number = 0; i < uid.length; i++) {
      hash = (hash * 31 + uid.charCodeAt(i)) % 200000000;
    }
    return hash * 10 + (kind - NotifyIds.RESIN);
  }

  /** 启动自动刷新（intervalMin 分钟）。已在运行且间隔未变时不重启，避免每次进页把计时清零 */
  startAutoRefresh(intervalMin: number): void {
    if (intervalMin <= 0) {
      this.stopAutoRefresh();
      return;
    }
    if (this.timerRunning && this.intervalMin === intervalMin) {
      return;
    }
    this.stopAutoRefresh();
    this.intervalMin = intervalMin;
    this.timer = setInterval(() => {
      this.tickAutoRefresh();
    }, intervalMin * 60 * 1000);
    this.timerRunning = true;
    Logger.info(TAG, `auto refresh started every ${intervalMin}min`);
  }

  stopAutoRefresh(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.timerRunning = false;
  }

  isTimerRunning(): boolean {
    return this.timerRunning;
  }

  /** 应用启动/回前台：按偏好同步定时器，并在缓存过期时后台补一次（对齐 Windows 启动即刷新便笺） */
  async bootstrapAutoRefresh(): Promise<void> {
    if (!PreferencesStore.isReady()) {
      return;
    }
    if (!PreferencesStore.getAutoRefreshEnabled()) {
      this.stopAutoRefresh();
      return;
    }
    const intervalMin: number = PreferencesStore.getRefreshIntervalMinutes();
    this.startAutoRefresh(intervalMin);
    await this.refreshIfStale(intervalMin);
  }

  /** 缓存超过 intervalMin 分钟（或从未刷新）时后台补一次；失败只记录不抛出 */
  private async refreshIfStale(intervalMin: number): Promise<void> {
    if (this.refreshing) {
      return;
    }
    const uid: string = AppStorage.get<string>('currentUid') ?? '';
    if (uid.length === 0) {
      return;
    }
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      return;
    }
    try {
      const rec: DailyNoteRecord | undefined = await DailyNoteRepo.get(user.id, uid);
      const ageMs: number = rec !== undefined && rec.note.refreshTime > 0
        ? Date.now() - rec.note.refreshTime : Number.MAX_SAFE_INTEGER;
      if (ageMs < intervalMin * 60 * 1000) {
        return;
      }
      await this.refresh(uid);
      Logger.info(TAG, 'stale refresh done');
    } catch (e) {
      DailyNoteService.publishError((e as Error).message);
      Logger.warn(TAG, `stale refresh fail ${(e as Error).message}`);
    }
  }

  private async tickAutoRefresh(): Promise<void> {
    const isLoggedIn: boolean = AppStorage.get<boolean>('isLoggedIn') ?? false;
    if (!isLoggedIn) {
      return;
    }
    const uid: string = AppStorage.get<string>('currentUid') ?? '';
    if (uid.length === 0) {
      return;
    }
    try {
      await this.refresh(uid);
      Logger.info(TAG, 'auto refresh done');
    } catch (e) {
      // 失败原因写入 AppStorage，便笺页顶部提示（此前只进日志，用户无感知）
      DailyNoteService.publishError((e as Error).message);
      Logger.warn(TAG, `auto refresh fail ${(e as Error).message}`);
    }
    // 追踪列表随自动刷新一起轮询（单个失败静默）
    await this.refreshTrackedList();
  }

  /** 自增数据版本戳：AppStorage 全局广播（页面/主页订阅后重读本地缓存） */
  private static bumpVersion(): void {
    const v: number = AppStorage.get<number>(KEY_NOTE_VERSION) ?? 0;
    AppStorage.setOrCreate<number>(KEY_NOTE_VERSION, v + 1);
  }

  /** 记录最近一次刷新失败原因（页面提示用） */
  private static publishError(msg: string): void {
    AppStorage.setOrCreate<string>(KEY_NOTE_ERROR, msg);
  }

  /** 清空失败原因（刷新成功） */
  private static clearError(): void {
    AppStorage.setOrCreate<string>(KEY_NOTE_ERROR, '');
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
