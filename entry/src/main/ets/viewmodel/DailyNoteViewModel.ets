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

/** 追踪列表条目（uid + 本地缓存快照；未拉取过则 note 为空） */
export class TrackedNoteEntry {
  uid: string = '';
  note: DailyNote | undefined = undefined;
}

/** 追踪卡条目（每 UID 一张卡：uid + 昵称 + 快照；对齐 Windows DailyNoteEntries） */
export class NoteCardEntry {
  uid: string = '';
  nickname: string = '';
  isCurrent: boolean = false;
  note: DailyNote | undefined = undefined;
}

/** 魔神任务进度 prefs 键（DB 无 archon 列，落在偏好里随缓存补齐） */
function archonKey(userId: number, uid: string): string {
  return `dailynote.archon.${userId}.${uid}`;
}

@Observed
export class DailyNoteViewModel {
  currentUid: string = '';
  note: DailyNote | undefined = undefined;
  /** 当前用户昵称（卡头显示 昵称（UID xxx），对齐 Windows UserGameRole） */
  nickname: string = '';
  resinThreshold: number = 120;
  homeThreshold: number = 1800;
  notifyFlags: number = NotifyFlags.ALL;
  /** 每 UID 通知设置（半窗编辑态：目标 UID + 阈值/开关位） */
  settingsUid: string = '';
  settingsResinThreshold: number = 120;
  settingsHomeThreshold: number = 1800;
  settingsNotifyFlags: number = NotifyFlags.ALL;
  isRefreshing: boolean = false;
  isAutoRunning: boolean = false;
  message: string = '';
  loaded: boolean = false;
  lastRefreshAt: number = 0;
  /** 需要人机验证（极验）：gt/challenge 供跳转验证页 */
  needGeetest: boolean = false;
  geetestGt: string = '';
  geetestChallenge: string = '';
  /** 追踪列表（对齐 Windows 多 UID 追踪：uid + 本地缓存快照） */
  trackedEntries: TrackedNoteEntry[] = [];
  trackedBusy: boolean = false;

  /** 从本地缓存装载 */
  async load(uid: string): Promise<void> {
    this.currentUid = uid;
    const user = UserService.getInstance().getCurrentUser();
    this.nickname = user !== undefined ? user.displayName : '';
    if (user !== undefined && uid.length > 0) {
      const rec: DailyNoteRecord | undefined = await DailyNoteRepo.get(user.id, uid);
      if (rec !== undefined) {
        this.note = rec.note;
        this.resinThreshold = rec.resinNotifyThreshold;
        this.homeThreshold = rec.homeCoinNotifyThreshold;
        this.notifyFlags = rec.notifyFlags;
        this.lastRefreshAt = rec.note.refreshTime;
        this.attachArchonFromPrefs(user.id, uid, rec.note);
      }
    }
    this.isAutoRunning = DailyNoteService.getInstance().isTimerRunning();
    await this.loadTracked();
    this.loaded = true;
  }

  /** DB 表未持久化魔神任务（archon_json 列恒空）：从 prefs 补齐，避免重启后该行误显示「全部完成」 */
  private attachArchonFromPrefs(userId: number, uid: string, note: DailyNote): void {
    if (note.archonQuests.length > 0) {
      return;
    }
    const raw: string = PreferencesStore.getString(archonKey(userId, uid), '');
    if (raw.length > 0) {
      note.archonQuests = DailyNote.archonListFromJson(raw);
    }
  }

  /** 追踪列表快照（本地缓存，不联网；对齐 Windows 追踪列表展示） */
  async loadTracked(): Promise<void> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined) {
      this.trackedEntries = [];
      return;
    }
    const uids: string[] = PreferencesStore.getTrackedUids(user.id);
    const entries: TrackedNoteEntry[] = [];
    for (const uid of uids) {
      const rec: DailyNoteRecord | undefined = await DailyNoteRepo.get(user.id, uid);
      const e: TrackedNoteEntry = new TrackedNoteEntry();
      e.uid = uid;
      e.note = rec !== undefined ? rec.note : undefined;
      entries.push(e);
    }
    this.trackedEntries = entries;
  }

  /** 追踪当前 UID（已存在则跳过） */
  async trackCurrent(): Promise<boolean> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || this.currentUid.length === 0) {
      this.message = '请先绑定 UID';
      return false;
    }
    const uids: string[] = PreferencesStore.getTrackedUids(user.id);
    if (uids.includes(this.currentUid)) {
      return false;
    }
    uids.push(this.currentUid);
    PreferencesStore.setTrackedUids(user.id, uids);
    await this.loadTracked();
    return true;
  }

  /** 移除追踪 */
  async untrack(uid: string): Promise<void> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined) {
      return;
    }
    const uids: string[] = PreferencesStore.getTrackedUids(user.id);
    const next: string[] = uids.filter((v: string): boolean => v !== uid);
    PreferencesStore.setTrackedUids(user.id, next);
    await this.loadTracked();
  }

  /** 刷新追踪列表（顺序联网拉取全部被追踪 UID） */
  async refreshTracked(): Promise<number> {
    if (this.trackedBusy) {
      return 0;
    }
    this.trackedBusy = true;
    try {
      const n: number = await DailyNoteService.getInstance().refreshTrackedList();
      await this.loadTracked();
      return n;
    } finally {
      this.trackedBusy = false;
    }
  }

  /** 服务层刷新成功（自动刷新定时器 / 桌面卡片手动刷新）后重读本地缓存，保持界面数值同步 */
  async reloadFromCache(uid: string): Promise<void> {
    if (uid.length > 0) {
      this.currentUid = uid;
    }
    if (this.currentUid.length === 0) {
      return;
    }
    await this.load(this.currentUid);
  }

  /** 追踪卡聚合：当前 UID（最新数据）在前，其余被追踪 UID 按本地缓存排序（每 UID 一张卡） */
  buildCardEntries(): NoteCardEntry[] {
    const entries: NoteCardEntry[] = [];
    const currentNote: DailyNote | undefined = this.note;
    if (this.currentUid.length > 0 && currentNote !== undefined) {
      const cur: NoteCardEntry = new NoteCardEntry();
      cur.uid = this.currentUid;
      cur.nickname = this.nickname;
      cur.isCurrent = true;
      cur.note = currentNote;
      entries.push(cur);
    }
    for (const t of this.trackedEntries) {
      if (t.uid === this.currentUid && currentNote !== undefined) {
        continue; // 当前 UID 卡已用最新数据展示
      }
      const e: NoteCardEntry = new NoteCardEntry();
      e.uid = t.uid;
      e.isCurrent = t.uid === this.currentUid;
      e.nickname = e.isCurrent ? this.nickname : '';
      e.note = t.note;
      entries.push(e);
    }
    return entries;
  }

  /** 打开某 UID 的通知设置（读取现有阈值/开关位；无记录用默认值） */
  async openUidSettings(uid: string): Promise<void> {
    this.settingsUid = uid;
    const user = UserService.getInstance().getCurrentUser();
    let rec: DailyNoteRecord | undefined = undefined;
    if (user !== undefined) {
      rec = await DailyNoteRepo.get(user.id, uid);
    }
    this.settingsResinThreshold = rec !== undefined ? rec.resinNotifyThreshold : 120;
    this.settingsHomeThreshold = rec !== undefined ? rec.homeCoinNotifyThreshold : 1800;
    this.settingsNotifyFlags = rec !== undefined ? rec.notifyFlags : NotifyFlags.ALL;
  }

  /** 保存某 UID 的通知设置 */
  private async saveUidSettings(): Promise<void> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || this.settingsUid.length === 0) {
      return;
    }
    await DailyNoteRepo.updateThresholds(user.id, this.settingsUid,
      this.settingsResinThreshold, this.settingsHomeThreshold, this.settingsNotifyFlags);
    // 编辑的是当前 UID 时同步内存态，保持页面引用一致
    if (this.settingsUid === this.currentUid) {
      this.resinThreshold = this.settingsResinThreshold;
      this.homeThreshold = this.settingsHomeThreshold;
      this.notifyFlags = this.settingsNotifyFlags;
    }
  }

  /** 每 UID 树脂阈值 */
  async setUidResinThreshold(th: number): Promise<void> {
    this.settingsResinThreshold = th;
    await this.saveUidSettings();
  }

  /** 每 UID 宝钱阈值 */
  async setUidHomeThreshold(th: number): Promise<void> {
    this.settingsHomeThreshold = th;
    await this.saveUidSettings();
  }

  /** 每 UID 开关位切换 */
  async toggleUidFlag(flag: number): Promise<void> {
    this.settingsNotifyFlags = this.settingsNotifyFlags ^ flag;
    await this.saveUidSettings();
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
      // 魔神任务进度落 prefs（DB 无 archon 列；重启后 load() 从 prefs 补齐）
      const user = UserService.getInstance().getCurrentUser();
      if (user !== undefined) {
        PreferencesStore.setString(archonKey(user.id, uid), JSON.stringify(note.archonQuests));
      }
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
