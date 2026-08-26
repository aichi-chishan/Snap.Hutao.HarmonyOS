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
import { CardVerifyApi, GtChallenge, DAILY_NOTE_PATH } from '../data/network/CardVerifyApi';
import { RegionUtil, RetCodes } from '../common/Constants';
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

export class DailyNoteService {
  private static instance: DailyNoteService = new DailyNoteService();
  private timer: number = -1;
  private timerRunning: boolean = false;

  static getInstance(): DailyNoteService {
    return DailyNoteService.instance;
  }

  /** 手动/自动刷新便笺。
   * @param challenge 可选：极验通过后从 verifyVerification 换得的 challenge（重放头）
   */
  async refresh(uid: string, challenge?: string): Promise<DailyNote> {
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
      // 1034 → 注册极验，引导用户完成人机验证
      const gtChallenge: GtChallenge = await CardVerifyApi.createVerification(cookie, DAILY_NOTE_PATH);
      if (gtChallenge.gt.length > 0 && gtChallenge.challenge.length > 0) {
        throw new NeedGeetestError(gtChallenge.gt, gtChallenge.challenge);
      }
      throw new Error('被风控拦截，且未能发起人机验证，请稍后再试');
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

  /** 启动自动刷新（intervalMin 分钟） */
  startAutoRefresh(intervalMin: number): void {
    this.stopAutoRefresh();
    if (intervalMin <= 0) {
      return;
    }
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
      Logger.warn(TAG, `auto refresh fail ${(e as Error).message}`);
    }
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
