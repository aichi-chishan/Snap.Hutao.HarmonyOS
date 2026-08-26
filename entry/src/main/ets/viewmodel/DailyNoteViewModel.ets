/**
 * DailyNoteViewModel.ets
 * 实时便笺页状态容器：数据状态、手动刷新命令、阈值设置、自动刷新开关、上次刷新时间。
 */
import { DailyNote } from '../model/DailyNote';
import { DailyNoteService, NotifyFlags, NeedGeetestError } from '../service/DailyNoteService';
import { DailyNoteRepo, DailyNoteRecord } from '../data/repo/DailyNoteRepo';
import { UserService } from '../service/UserService';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { Logger } from '../common/Logger';

const TAG: string = 'DailyNoteViewModel';

@Observed
export class DailyNoteViewModel {
  currentUid: string = '';
  note: DailyNote | undefined = undefined;
  resinThreshold: number = 120;
  homeThreshold: number = 1800;
  notifyFlags: number = NotifyFlags.ALL;
  isRefreshing: boolean = false;
  isAutoRunning: boolean = false;
  message: string = '';
  loaded: boolean = false;
  lastRefreshAt: number = 0;
  /** 需要人机验证（极验）：gt/challenge 供跳转验证页 */
  needGeetest: boolean = false;
  geetestGt: string = '';
  geetestChallenge: string = '';

  /** 从本地缓存装载 */
  async load(uid: string): Promise<void> {
    this.currentUid = uid;
    const user = UserService.getInstance().getCurrentUser();
    if (user !== undefined && uid.length > 0) {
      const rec: DailyNoteRecord | undefined = await DailyNoteRepo.get(user.id, uid);
      if (rec !== undefined) {
        this.note = rec.note;
        this.resinThreshold = rec.resinNotifyThreshold;
        this.homeThreshold = rec.homeCoinNotifyThreshold;
        this.notifyFlags = rec.notifyFlags;
        this.lastRefreshAt = rec.note.refreshTime;
      }
    }
    this.isAutoRunning = DailyNoteService.getInstance().isTimerRunning();
    this.loaded = true;
  }

  /** 手动刷新（可携带风控验证后 challenge 重放） */
  async refresh(uid: string, challenge?: string): Promise<boolean> {
    if (this.isRefreshing) {
      return false;
    }
    this.currentUid = uid;
    this.isRefreshing = true;
    this.needGeetest = false;
    try {
      const note: DailyNote = await DailyNoteService.getInstance().refresh(uid, challenge);
      this.note = note;
      this.lastRefreshAt = Date.now();
      // 重新读阈值（可能被服务端缓存后新增行）
      await this.load(uid);
      return true;
    } catch (e) {
      const err: Error = e as Error;
      if (err.name === 'NeedGeetestError') {
        const need: NeedGeetestError = err as NeedGeetestError;
        this.needGeetest = true;
        this.geetestGt = need.gt;
        this.geetestChallenge = need.challenge;
        this.message = '当前账号触发风控，需要完成人机验证';
      } else {
        this.message = err.message;
      }
      Logger.warn(TAG, `refresh fail ${this.message}`);
      return false;
    } finally {
      this.isRefreshing = false;
    }
  }

  /** 树脂阈值 */
  async setResinThreshold(th: number): Promise<void> {
    this.resinThreshold = th;
    await this.saveThresholds();
  }

  /** 洞天宝钱阈值 */
  async setHomeThreshold(th: number): Promise<void> {
    this.homeThreshold = th;
    await this.saveThresholds();
  }

  /** 开关位切换 */
  async toggleFlag(flag: number): Promise<void> {
    this.notifyFlags = this.notifyFlags ^ flag;
    await this.saveThresholds();
  }

  private async saveThresholds(): Promise<void> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || this.currentUid.length === 0) {
      return;
    }
    await DailyNoteRepo.updateThresholds(user.id, this.currentUid,
      this.resinThreshold, this.homeThreshold, this.notifyFlags);
  }

  /** 根据偏好启动/停止自动刷新 */
  syncAutoRefresh(): void {
    const enabled: boolean = PreferencesStore.getAutoRefreshEnabled();
    if (enabled) {
      DailyNoteService.getInstance().startAutoRefresh(PreferencesStore.getRefreshIntervalMinutes());
      this.isAutoRunning = true;
    } else {
      DailyNoteService.getInstance().stopAutoRefresh();
      this.isAutoRunning = false;
    }
  }
}
