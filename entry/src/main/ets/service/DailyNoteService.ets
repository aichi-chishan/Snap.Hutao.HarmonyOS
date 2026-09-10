/**
 * DailyNoteService.ets
 * 便笺拉取（DS Gen2/X4 + Cookie + 1034 重试）；缓存刷新时间；阈值判定与本地通知；自动刷新定时器。
 * 注：AppStorage 为 ArkUI 全局对象，无需 import。
 */
import { formProvider, formBindingData, formInfo } from '@kit.FormKit';
import { UserService } from './UserService';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { ApiResponse } from '../model/ApiResponse';
import { DailyNoteRepo, DailyNoteRecord } from '../data/repo/DailyNoteRepo';
import { NotificationHelper } from '../data/local/NotificationHelper';
import { FormSnapshot } from '../data/local/FormSnapshot';
import { DailyNote } from '../model/DailyNote';
import { DAILY_NOTE_PATH } from '../data/network/CardVerifyApi';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { RegionUtil, RetCodes } from '../common/Constants';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { Logger } from '../common/Logger';

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

  /** 手动/自动刷新便笺（重入保护：同一时刻仅一次在途请求）。
   * @param challenge 可选：极验通过后从 verifyVerification 换得的 challenge（重放头）
   */
  async refresh(uid: string, challenge?: string): Promise<DailyNote> {
    if (this.refreshing) {
      throw new Error('正在刷新中，请稍候');
    }
    this.refreshing = true;
    try {
      return await this.doRefresh(uid, challenge);
    } finally {
      this.refreshing = false;
    }
  }

  /** 桌面卡片手动刷新：带超时的刷新（命中需 UI 的风控时不无限挂起卡片进程） */
  async refreshForCard(uid: string, timeoutMs: number): Promise<DailyNote> {
    const work: Promise<DailyNote> = this.refresh(uid);
    const limit: Promise<DailyNote> = new Promise<DailyNote>(
      (resolve: (value: DailyNote) => void, reject: (reason: Error) => void) => {
        setTimeout(() => {
          reject(new Error('刷新超时，请打开应用完成人机验证'));
        }, timeoutMs);
      });
    return Promise.race<DailyNote>([work, limit]);
  }

  /** 实际刷新流程：网络拉取 → 落库 → 广播版本戳 → 卡片快照 → 阈值通知 */
  private async doRefresh(uid: string, challenge?: string): Promise<DailyNote> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    // 若缺 cookie_token/ltoken（旧账号），先用 SToken 补齐再拉取
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
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
    await this.updateCardSnapshot(note, user.displayName);

    const prev: DailyNoteRecord | undefined = await DailyNoteRepo.get(user.id, uid);
    await this.evalAndNotify(user.id, uid, note, prev);
    Logger.info(TAG, `refresh ok uid=${uid} resin=${note.currentResin}/${note.maxResin}`);
    return note;
  }

  /** 刷新成功后更新桌面卡片快照并主动推送 formProvider */
  private async updateCardSnapshot(note: DailyNote, nickname: string): Promise<void> {
    try {
      let expText: string = '派遣 --';
      if (note.maxExpeditionNum > 0) {
        const done: number = note.currentExpeditionNum >= note.maxExpeditionNum ? note.maxExpeditionNum : note.currentExpeditionNum;
        expText = `派遣 ${done}/${note.maxExpeditionNum}`;
      }
      const daily: string = note.totalTaskNum > 0
        ? `每日 ${note.finishedTaskNum}/${note.totalTaskNum}${note.isExtraTaskRewardReceived ? ' ✔' : ''}`
        : '每日 --';
      const homeCoin: string = note.maxHomeCoin > 0 ? `洞天宝钱 ${note.currentHomeCoin}/${note.maxHomeCoin}` : '';
      const resinRecovery: string = note.resinRecoveryText();
      FormSnapshot.save(`${note.currentResin}`, `${note.maxResin}`, expText, daily, homeCoin, nickname,
        note.refreshTime, resinRecovery);
      await this.pushAllCards();
    } catch (e) {
      Logger.warn(TAG, `updateCardSnapshot fail ${(e as Error).message}`);
    }
  }

  /** 主动刷新全部本应用桌面卡片 */
  private async pushAllCards(): Promise<void> {
    const bindFormData: formBindingData.FormBindingData = formBindingData.createFormBindingData(FormSnapshot.load());
    try {
      const forms: Array<formInfo.RunningFormInfo> = await formProvider.getPublishedRunningFormInfos();
      for (let i = 0; i < forms.length; i++) {
        const fid: string = forms[i].formId;
        if (fid.length > 0) {
          await formProvider.updateForm(fid, bindFormData);
        }
      }
    } catch (e) {
      Logger.warn(TAG, 'pushAllCards fail (可能未添加卡片)');
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
        await NotificationHelper.publish('树脂已达标',
          `当前树脂 ${note.currentResin}/${note.maxResin}，已达阈值 ${resinTh}`, NotifyIds.RESIN);
      }
    }
    // 派遣全部完成
    if ((flags & NotifyFlags.EXPEDITION) !== 0) {
      const allDone: boolean = note.currentExpeditionNum > 0 &&
        note.currentExpeditionNum >= note.maxExpeditionNum;
      if (allDone) {
        const wasDone: boolean = hasRec && prevNote.currentExpeditionNum > 0 &&
          prevNote.currentExpeditionNum >= prevNote.maxExpeditionNum;
        if (!wasDone) {
          await NotificationHelper.publish('派遣已完成', '所有派遣任务已完成', NotifyIds.EXPEDITION);
        }
      }
    }
    // 每日委托全部完成
    if ((flags & NotifyFlags.DAILY_TASK) !== 0) {
      const allTask: boolean = note.dailyTask.isAllFinished() || (note.totalTaskNum > 0 && note.finishedTaskNum >= note.totalTaskNum);
      if (allTask) {
        const wasAllTask: boolean = hasRec &&
          (prevNote.dailyTask.isAllFinished() || (prevNote.totalTaskNum > 0 && prevNote.finishedTaskNum >= prevNote.totalTaskNum));
        if (!wasAllTask) {
          await NotificationHelper.publish('每日委托完成', `已完成 ${note.finishedTaskNum}/${note.totalTaskNum}`, NotifyIds.DAILY_TASK);
        }
      }
    }
    // 参变仪就绪
    if ((flags & NotifyFlags.TRANSFORMER) !== 0 && note.transformer.isReady()) {
      const wasReady: boolean = hasRec && prevNote.transformer.isReady();
      if (!wasReady) {
        await NotificationHelper.publish('参变仪就绪', '参量质变仪已可使用', NotifyIds.TRANSFORMER);
      }
    }
    // 洞天宝钱
    if ((flags & NotifyFlags.HOME_COIN) !== 0 && note.homeCoinReached(homeTh)) {
      const wasMet: boolean = hasRec && prevNote.homeCoinReached(homeTh);
      if (!wasMet) {
        await NotificationHelper.publish('洞天宝钱已达标',
          `当前宝钱 ${note.currentHomeCoin}/${note.maxHomeCoin}，已达阈值 ${homeTh}`, NotifyIds.HOME_COIN);
      }
    }
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
