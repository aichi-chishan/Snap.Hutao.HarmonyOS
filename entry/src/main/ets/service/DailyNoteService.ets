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
/** AppStorage 键：最近一次自动刷新失败原因（供页面提示；成功刷新后清空） */
export const KEY_NOTE_ERROR: string = 'dailyNoteLastError';

export class DailyNoteTrackedEntry {
  userId: number = 0;
  uid: string = '';
  nickname: string = '';
  region: string = '';
  level: number = 0;
  record: DailyNoteRecord | undefined = undefined;
}

export class DailyNoteRefreshSummary {
  total: number = 0;
  succeeded: number = 0;
  firstError: string = '';
}

class TrackedNoteOwnerGuard implements BackgroundTaskGuard {
  private user: User;
  private uid: string;
  private region: string;
  private active?: () => boolean;
  constructor(user: User, uid: string, active?: () => boolean) {
    this.user = user; this.uid = uid; this.region = RegionUtil.regionOfUid(uid); this.active = active;
  }

  async isActive(): Promise<boolean> {
    if (this.active?.() === false || PreferencesStore.getBackupJournal().length > 0) { return false; }
    const saved: User | undefined = await UserRepo.getUserById(this.user.id);
    return this.active?.() !== false && saved !== undefined &&
      BackgroundTaskPolicy.identity(saved) === BackgroundTaskPolicy.identity(this.user) &&
      BackgroundTaskPolicy.owns(saved, this.uid, this.region) && PreferencesStore.getBackupJournal().length === 0 &&
      PreferencesStore.getTrackedUids(saved.id).includes(this.uid);
  }
}

class ForegroundNotePresentationGuard implements BackgroundTaskGuard {
  private user: User;
  private uid: string;
  private revision: number;
  private owner?: BackgroundTaskGuard;
  constructor(user: User, uid: string, revision: number, owner?: BackgroundTaskGuard) {
    this.user = user; this.uid = uid; this.revision = revision; this.owner = owner;
  }
  async isActive(): Promise<boolean> {
    if (this.owner !== undefined && !await this.owner.isActive()) { return false; }
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
  /** 手动/自动/卡片刷新共用的结算信号；失败也会结算，便于回前台等待旧请求退出。 */
  private refreshInFlight: Promise<void> | undefined = undefined;
  private foreground: boolean = false;
  private autoRevision: number = 0;
  private bootstrapRevision: number = -1;
  private autoRunRevision: number = -1;
  private autoRun: Promise<void> | undefined = undefined;

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
    if (this.refreshInFlight !== undefined) {
      throw new Error('正在刷新中，请稍候');
    }
    return this.runRefresh<DailyNote>((): Promise<DailyNote> => this.doRefresh(uid, challenge, interactive));
  }

  private async runRefresh<T>(work: () => Promise<T>): Promise<T> {
    const operation: Promise<T> = Promise.resolve().then<T>(work);
    const settled: Promise<void> = operation.then<void, void>((): void => {}, (): void => {});
    this.refreshInFlight = settled;
    try {
      return await operation;
    } finally {
      if (this.refreshInFlight === settled) { this.refreshInFlight = undefined; }
    }
  }

  /** Refresh an explicit owner from saved credentials. Scheduled tracked refresh can run its configured side effects. */
  async refreshBackground(user: User, uid: string, region: string, guard: BackgroundTaskGuard,
    trackedEffects: boolean = false): Promise<BackgroundTaskResult> {
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
    const prev: DailyNoteRecord | undefined = trackedEffects ? await DailyNoteRepo.get(user.id, uid) : undefined;
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    await DailyNoteRepo.upsert(user.id, uid, note, (): Promise<boolean> => guard.isActive());
    if (!await guard.isActive()) { return BackgroundTaskResult.of('cancelled', '任务已停止'); }
    DailyNoteService.bumpVersion();
    if (await UserRepo.getSelectedUserId() === user.id && (await UserRepo.getDefaultRole(user.id))?.gameUid === uid) {
      await this.updateCardSnapshot(note, user.displayName, user.id, uid, guard, true);
    }
    if (trackedEffects) {
      await this.evalAndNotify(user.id, uid, note, prev, guard);
      await this.forwardWebhook(uid, note, guard);
    }
    return BackgroundTaskResult.of('success', '后台便笺已刷新', BackgroundTaskPolicy.day(region));
  }

  /** Local tracking records across saved accounts, including roles with no cached snapshot yet. */
  async trackedEntries(): Promise<DailyNoteTrackedEntry[]> {
    const entries: DailyNoteTrackedEntry[] = [];
    for (const user of await UserRepo.getAllUsers()) {
      const tracked: string[] = PreferencesStore.getTrackedUids(user.id);
      for (const role of BackgroundTaskPolicy.mainlandRoles(user)) {
        if (!tracked.includes(role.gameUid)) { continue; }
        const entry: DailyNoteTrackedEntry = new DailyNoteTrackedEntry();
        entry.userId = user.id;
        entry.uid = role.gameUid;
        entry.nickname = role.nickname;
        entry.region = role.region;
        entry.level = role.level;
        entry.record = await DailyNoteRepo.get(user.id, role.gameUid);
        entries.push(entry);
      }
    }
    return entries;
  }

  async refreshTrackedEntry(userId: number, uid: string): Promise<DailyNote> {
    if (this.refreshInFlight !== undefined) { throw new Error('正在刷新中，请稍候'); }
    return this.runRefresh<DailyNote>(async (): Promise<DailyNote> => {
      const user: User | undefined = await UserRepo.getUserById(userId);
      if (user === undefined) { throw new Error('该账号已移除'); }
      return await this.refreshOwnedEntry(user, uid, true);
    });
  }

  /** 手动强刷全部追踪；自动调用传入过期时间与本批有效性检查。 */
  async refreshTrackedList(interactive: boolean = true, staleAfterMs: number = 0,
    active?: () => boolean): Promise<DailyNoteRefreshSummary> {
    const summary: DailyNoteRefreshSummary = new DailyNoteRefreshSummary();
    if (this.refreshInFlight !== undefined) { summary.firstError = '正在刷新中，请稍候'; return summary; }
    return this.runRefresh<DailyNoteRefreshSummary>(async (): Promise<DailyNoteRefreshSummary> => {
      const users: User[] = await UserRepo.getAllUsers();
      for (const user of users) {
        for (const role of BackgroundTaskPolicy.mainlandRoles(user)) {
          if (active?.() === false) { return summary; }
          const uid: string = role.gameUid;
          if (!PreferencesStore.getTrackedUids(user.id).includes(uid)) { continue; }
          try {
            if (staleAfterMs > 0) {
              const cached: DailyNoteRecord | undefined = await DailyNoteRepo.get(user.id, uid);
              if (active?.() === false) { return summary; }
              if (cached !== undefined && cached.note.refreshTime > 0 &&
                Date.now() - cached.note.refreshTime < staleAfterMs) { continue; }
            }
            summary.total++;
            await this.refreshOwnedEntry(user, uid, interactive, active);
            summary.succeeded++;
          } catch (e) {
            if (active?.() === false) { return summary; }
            if (summary.firstError.length === 0) { summary.firstError = (e as Error).message; }
          }
        }
      }
      return summary;
    });
  }

  private async refreshOwnedEntry(user: User, uid: string, allowInteractive: boolean,
    active?: () => boolean): Promise<DailyNote> {
    const guard: TrackedNoteOwnerGuard = new TrackedNoteOwnerGuard(user, uid, active);
    await this.assertTrackedActive(guard);
    const selected: User | undefined = UserService.getInstance().getCurrentUser();
    if (selected !== undefined && selected.id === user.id &&
      BackgroundTaskPolicy.identity(selected) === BackgroundTaskPolicy.identity(user) && PreferencesStore.getCurrentUid() === uid) {
      return this.doRefresh(uid, undefined, allowInteractive, selected, guard);
    }
    return this.doRefresh(uid, undefined, false, user, guard);
  }

  private async assertTrackedActive(guard?: BackgroundTaskGuard): Promise<void> {
    if (guard !== undefined && !await guard.isActive()) { throw new Error('该角色已停止追踪或账号已变化'); }
  }

  /** 实际刷新流程：网络拉取 → 落库 → 广播版本戳 → 卡片快照 → 阈值通知 */
  private async doRefresh(uid: string, challenge?: string, interactive: boolean = true, account?: User,
    guard?: BackgroundTaskGuard): Promise<DailyNote> {
    const revision: number = UserService.getInstance().sessionRevision();
    const user: User | undefined = account ?? UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    const presentation: ForegroundNotePresentationGuard = new ForegroundNotePresentationGuard(user, uid, revision, guard);
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
    await this.assertTrackedActive(guard);

    // 重放头（风控验证后）
    const extra: Record<string, string> = {};
    if (challenge !== undefined && challenge.length > 0) {
      extra['x-rpc-challenge'] = challenge;
    }

    // 拉取
    let resp: ApiResponse = await HoyolabClient.fetchDailyNote(uid, region, cookie, extra);
    if (resp.isRiskControl()) {
      if (!interactive || HoyolabEndpoints.isOverseaRegion(region) || (guard !== undefined && !await presentation.isActive())) {
        throw new Error('请打开应用完成人机验证');
      }
      // 1034：自动弹统一验证窗，成功后带 challenge 服务内重放一次
      const replayChallenge: string = await RiskVerifier.tryResolveRisk(resp, cookie, DAILY_NOTE_PATH);
      if (replayChallenge.length === 0) {
        throw new Error('人机验证未完成或被取消，请稍后再试');
      }
      await this.assertTrackedActive(guard);
      extra['x-rpc-challenge'] = replayChallenge;
      if (guard !== undefined && !await presentation.isActive()) { throw new Error('当前角色已切换'); }
      resp = await HoyolabClient.fetchDailyNote(uid, region, cookie, extra);
    }
    // Cookie 鉴权失效（-100/10001）：强制换新凭证后重试一次（对齐 Windows CookieToken 刷新）
    if (!resp.success && UserService.isCookieAuthError(resp)) {
      if (!interactive || (guard !== undefined && !await presentation.isActive())) { throw new Error('请打开应用重新登录'); }
      resp = await UserService.retryWithRefreshedCookie(user, async (): Promise<ApiResponse> => {
        await this.assertTrackedActive(guard);
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
    await this.assertTrackedActive(guard);
    await DailyNoteRepo.upsert(user.id, uid, note, guard === undefined ? undefined : (): Promise<boolean> => guard.isActive());
    await this.assertTrackedActive(guard);

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
        presentation);
    }

    await this.evalAndNotify(user.id, uid, note, prev, guard);
    await this.assertTrackedActive(guard);
    try {
      await DailyNoteReminderService.sync(user.id, uid, note, prev);
    } catch (e) {
      if (guard === undefined || await guard.isActive()) {
        AppStorage.setOrCreate<string>(DailyNoteReminderService.ERROR_KEY, (e as Error).message);
        Logger.warn(TAG, `agent reminder failed: ${(e as Error).message}`);
      }
    }
    await this.forwardWebhook(uid, note, guard);
    Logger.info(TAG, `refresh ok uid=${uid} resin=${note.currentResin}/${note.maxResin}`);
    // 派遣头像排查：接口可能返回哈希文件名（本地/CND 无对应图标，UI 改走接口 URL）
    for (const expedition of note.expeditions) {
      if (expedition.iconName().length === 0) {
        Logger.info(TAG, `expedition icon unmapped: ${expedition.avatarSideIcon}`);
      }
    }
    return note;
  }

  private async forwardWebhook(uid: string, note: DailyNote, guard?: BackgroundTaskGuard): Promise<void> {
    const webhook: string = DailyNoteService.webhookUrl();
    if (webhook.length === 0 || note.rawJson.length === 0 || (guard !== undefined && !await guard.isActive())) { return; }
    try { await DailyNoteWebhookClient.send(webhook, uid, note.rawJson); }
    catch (e) { Logger.warn(TAG, 'webhook delivery failed'); }
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
  async evalAndNotify(userId: number, uid: string, note: DailyNote, prev: DailyNoteRecord | undefined,
    guard?: BackgroundTaskGuard): Promise<void> {
    if (!NotificationHelper.isEnabled()) {
      return;
    }
    const publish = async (title: string, text: string, id: number): Promise<void> => {
      if (guard === undefined || await guard.isActive()) { await NotificationHelper.publish(title, text, id); }
    };
    const flags: number = prev !== undefined ? prev.notifyFlags : NotifyFlags.ALL;
    const resinTh: number = prev !== undefined ? prev.resinNotifyThreshold : 120;
    const homeTh: number = prev !== undefined ? prev.homeCoinNotifyThreshold : 1800;
    const prevNote: DailyNote | undefined = prev !== undefined ? prev.note : undefined;

    const hasRec = prev !== undefined && prevNote !== undefined;

    // 树脂
    if ((flags & NotifyFlags.RESIN) !== 0 && note.resinReached(resinTh)) {
      const wasMet: boolean = hasRec && prevNote.resinReached(resinTh);
      if (!wasMet) {
        await publish(`UID ${uid} · 树脂已达标`,
          `当前树脂 ${note.currentResin}/${note.maxResin}，已达阈值 ${resinTh}`, DailyNoteService.notificationId(uid, NotifyIds.RESIN));
      }
    }
    // 派遣全部完成
    if ((flags & NotifyFlags.EXPEDITION) !== 0) {
      const allDone: boolean = note.allExpeditionsFinished();
      if (allDone) {
        const wasDone: boolean = hasRec && prevNote.allExpeditionsFinished();
        if (!wasDone) {
          await publish(`UID ${uid} · 派遣已完成`, '所有派遣任务已完成', DailyNoteService.notificationId(uid, NotifyIds.EXPEDITION));
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
          await publish(`UID ${uid} · 每日委托奖励未领取`, note.extraTaskRewardDescription(),
            DailyNoteService.notificationId(uid, NotifyIds.DAILY_TASK));
        }
      }
    }
    // 参变仪就绪
    if ((flags & NotifyFlags.TRANSFORMER) !== 0 && note.transformer.isReady()) {
      const wasReady: boolean = hasRec && prevNote.transformer.isReady();
      if (!wasReady) {
        await publish(`UID ${uid} · 参变仪就绪`, '参量质变仪已可使用', DailyNoteService.notificationId(uid, NotifyIds.TRANSFORMER));
      }
    }
    // 洞天宝钱
    if ((flags & NotifyFlags.HOME_COIN) !== 0 && note.homeCoinReached(homeTh)) {
      const wasMet: boolean = hasRec && prevNote.homeCoinReached(homeTh);
      if (!wasMet) {
        await publish(`UID ${uid} · 洞天宝钱已达标`,
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

  /** Ability 生命周期只控制前台轮询；OS 显式后台任务使用独立的 refreshBackground。 */
  setForeground(foreground: boolean): void {
    if (this.foreground === foreground) { return; }
    this.foreground = foreground;
    if (!foreground) { this.stopAutoRefresh(); }
  }

  /** 同间隔重复 start 不重置计时；用户选项和前台状态同时允许时才开表。 */
  startAutoRefresh(intervalMin: number): void {
    if (!this.foreground || !PreferencesStore.isReady() || !PreferencesStore.getAutoRefreshEnabled() || intervalMin <= 0) {
      this.stopAutoRefresh();
      return;
    }
    if (this.timerRunning && this.intervalMin === intervalMin) {
      return;
    }
    this.stopAutoRefresh();
    this.intervalMin = intervalMin;
    const revision: number = this.autoRevision;
    this.timer = setInterval((): void => {
      this.tickAutoRefresh(revision);
    }, intervalMin * 60 * 1000);
    this.timerRunning = true;
    Logger.info(TAG, `auto refresh started every ${intervalMin}min`);
  }

  stopAutoRefresh(): void {
    this.autoRevision++;
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.timerRunning = false;
  }

  isTimerRunning(): boolean {
    return this.timerRunning;
  }

  /** 本次进入前台补扫一次；初始化和 onForeground 重复调用时合并同一批工作。 */
  async bootstrapAutoRefresh(): Promise<void> {
    if (!PreferencesStore.isReady()) {
      return;
    }
    if (!this.foreground || !PreferencesStore.getAutoRefreshEnabled()) {
      this.stopAutoRefresh();
      return;
    }
    const intervalMin: number = PreferencesStore.getRefreshIntervalMinutes();
    this.startAutoRefresh(intervalMin);
    if (this.bootstrapRevision !== this.autoRevision || this.autoRun !== undefined) {
      await this.tickAutoRefresh(this.autoRevision);
    }
  }

  private canAutoRefresh(revision: number): boolean {
    return revision === this.autoRevision && this.foreground && this.timerRunning && PreferencesStore.isReady() &&
      PreferencesStore.getAutoRefreshEnabled() && PreferencesStore.getBackupJournal().length === 0 &&
      !UserService.getInstance().isSessionTransitionPending();
  }

  private async tickAutoRefresh(revision: number): Promise<void> {
    if (!this.canAutoRefresh(revision)) { return; }
    if (this.autoRun !== undefined) {
      const sameRun: boolean = this.autoRunRevision === revision;
      const pendingRun: Promise<void> = this.autoRun;
      await pendingRun;
      // 回前台的新批次等待旧请求退出；同一批的重复触发只等待，不重新请求失败项。
      if (!sameRun) { await this.tickAutoRefresh(revision); }
      return;
    }
    this.autoRunRevision = revision;
    const running: Promise<void> = this.refreshStaleTracked(revision, this.intervalMin * 60 * 1000);
    this.autoRun = running;
    try {
      await running;
    } finally {
      if (this.autoRun === running) { this.autoRun = undefined; }
    }
  }

  private async refreshStaleTracked(revision: number, staleAfterMs: number): Promise<void> {
    while (this.refreshInFlight !== undefined) {
      const pendingRefresh: Promise<void> = this.refreshInFlight;
      await pendingRefresh;
      if (!this.canAutoRefresh(revision)) { return; }
    }
    if (!this.canAutoRefresh(revision)) { return; }
    // 开表不等于已补扫：账号/备份门控解除后的 bootstrap 仍可补上本次前台工作。
    this.bootstrapRevision = revision;
    const sessionRevision: number = UserService.getInstance().sessionRevision();
    const active: () => boolean = (): boolean => this.canAutoRefresh(revision) &&
      UserService.getInstance().sessionRevision() === sessionRevision;
    try {
      const summary: DailyNoteRefreshSummary = await this.refreshTrackedList(false, staleAfterMs, active);
      if (!active()) { return; }
      if (summary.firstError.length > 0) { DailyNoteService.publishError(summary.firstError); }
      else if (summary.succeeded > 0) { DailyNoteService.clearError(); }
    } catch (e) {
      if (active()) {
        DailyNoteService.publishError((e as Error).message);
        Logger.warn(TAG, `auto refresh fail ${(e as Error).message}`);
      }
    }
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
