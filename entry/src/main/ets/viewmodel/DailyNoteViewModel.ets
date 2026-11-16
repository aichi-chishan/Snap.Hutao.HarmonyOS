/**
 * DailyNoteViewModel.ets
 * 实时便笺页状态容器：数据状态、手动刷新命令、阈值设置、自动刷新开关、上次刷新时间。
 */
import { DailyNote, ArchonQuestChapter, DailyNoteChapterMetadata } from '../model/DailyNote';
import { DailyNoteService, DailyNoteTrackedEntry, DailyNoteRefreshSummary, NotifyFlags, NeedGeetestError,
  KEY_NOTE_VERSION } from '../service/DailyNoteService';
import { DailyNoteRepo, DailyNoteRecord } from '../data/repo/DailyNoteRepo';
import { UserRepo } from '../data/repo/UserRepo';
import { User } from '../model/User';
import { BackgroundTaskPolicy } from '../model/BackgroundTask';
import { RegionUtil } from '../common/Constants';
import { DailyNoteReminderService } from '../service/DailyNoteReminderService';
import { UserService } from '../service/UserService';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { Logger } from '../common/Logger';
import { LocalizedGameDataService } from '../service/LocalizedGameDataService';

const TAG: string = 'DailyNoteViewModel';

/** 追踪卡条目（每 UID 一张卡：uid + 昵称 + 快照；对齐 Windows DailyNoteEntries） */
export class NoteCardEntry {
  userId: number = 0;
  uid: string = '';
  nickname: string = '';
  region: string = '';
  level: number = 0;
  isCurrent: boolean = false;
  tracked: boolean = false;
  note: DailyNote | undefined = undefined;
  /** -1 表示未知章节；只有元数据中的真实索引才可作为进度。 */
  archonProgress: number = -1;
  archonTotal: number = 0;
  archonChapterText: string = '';
}

/** 兼容旧版本保存在 prefs 的魔神任务列表。 */
function archonKey(userId: number, uid: string): string {
  return `dailynote.archon.${userId}.${uid}`;
}

@Observed
export class DailyNoteViewModel {
  currentUid: string = '';
  private currentUserId: number = 0;
  private loadVersion: number = 0;
  private trackedVersion: number = 0;
  private chapters: DailyNoteChapterMetadata[] = [];
  private settingsVersion: number = 0;
  private settingsUserId: number = 0;
  private settingsSave: Promise<void> = Promise.resolve();
  note: DailyNote | undefined = undefined;
  resinThreshold: number = 120;
  homeThreshold: number = 1800;
  notifyFlags: number = NotifyFlags.ALL;
  /** 每 UID 通知设置（半窗编辑态：目标 UID + 阈值/开关位） */
  settingsUid: string = '';
  settingsResinThreshold: number = 120;
  settingsHomeThreshold: number = 1800;
  settingsResinMax: number = 0;
  settingsHomeMax: number = 0;
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
  trackedEntries: DailyNoteTrackedEntry[] = [];
  trackedBusy: boolean = false;

  /** 从本地缓存装载 */
  async load(uid: string): Promise<void> {
    const version: number = ++this.loadVersion;
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    const userId: number = user?.id ?? 0;
    if (this.currentUid !== uid || this.currentUserId !== userId) {
      this.note = undefined;
      this.lastRefreshAt = 0;
    }
    this.currentUid = uid;
    this.currentUserId = userId;
    if (user !== undefined && uid.length > 0) {
      const rec: DailyNoteRecord | undefined = await DailyNoteRepo.get(user.id, uid);
      if (version !== this.loadVersion || UserService.getInstance().getCurrentUser()?.id !== userId) { return; }
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
    if (version === this.loadVersion) { this.loaded = true; }
  }

  /** 仅为没有原始 JSON 和章节列的旧记录补齐 prefs 中保存的任务信息。 */
  private attachArchonFromPrefs(userId: number, uid: string, note: DailyNote): void {
    if (note.rawJson.length > 0 || note.hasArchonQuestProgress) {
      return;
    }
    const raw: string = PreferencesStore.getString(archonKey(userId, uid), '');
    if (raw.length > 0) {
      note.archonQuests = DailyNote.archonListFromJson(raw);
      note.hasArchonQuestProgress = note.archonQuests.length > 0;
    }
  }

  /** 追踪列表快照（本地缓存，不联网；对齐 Windows 追踪列表展示） */
  async loadTracked(): Promise<void> {
    const version: number = ++this.trackedVersion;
    const locale: string = LocalizedGameDataService.current();
    const entries: DailyNoteTrackedEntry[] = await DailyNoteService.getInstance().trackedEntries();
    let chapters: DailyNoteChapterMetadata[] = [];
    try {
      chapters = DailyNoteChapterMetadata.fromJson(await LocalizedGameDataService.readJson('Chapter.json', locale));
    } catch (e) {
      Logger.warn(TAG, `AQ metadata unavailable: ${(e as Error).message}`);
    }
    if (version !== this.trackedVersion || locale !== LocalizedGameDataService.current()) { return; }
    for (const entry of entries) {
      if (entry.record !== undefined) { this.attachArchonFromPrefs(entry.userId, entry.uid, entry.record.note); }
    }
    this.chapters = chapters;
    this.trackedEntries = entries;
  }

  /** 追踪当前 UID（已存在则跳过） */
  async trackCurrent(): Promise<boolean> {
    if (this.isRefreshing) { this.message = '便笺正在刷新，请稍后添加'; return false; }
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    const uid: string = PreferencesStore.getCurrentUid();
    if (user === undefined || uid !== this.currentUid || !BackgroundTaskPolicy.owns(user, uid, RegionUtil.regionOfUid(uid))) {
      this.message = '请先绑定 UID';
      return false;
    }
    const uids: string[] = PreferencesStore.getTrackedUids(user.id);
    if (uids.includes(uid)) {
      this.message = '当前 UID 已在追踪列表';
      return false;
    }
    this.message = '';
    // Windows 添加便笺时先请求当前数据；请求失败仍保留追踪条目供后续刷新。
    await this.refresh(uid);
    if (UserService.getInstance().getCurrentUser() !== user || PreferencesStore.getCurrentUid() !== uid) {
      this.message = '当前账号或角色已切换';
      return false;
    }
    uids.push(uid);
    PreferencesStore.setTrackedUids(user.id, uids);
    DailyNoteViewModel.notifyHome();
    await this.loadTracked();
    return true;
  }

  /** 移除追踪 */
  async untrack(userId: number, uid: string): Promise<void> {
    const uids: string[] = PreferencesStore.getTrackedUids(userId);
    const next: string[] = uids.filter((v: string): boolean => v !== uid);
    PreferencesStore.setTrackedUids(userId, next);
    DailyNoteViewModel.notifyHome();
    await this.loadTracked();
    try {
      await DailyNoteReminderService.cancelUid(userId, uid);
    } catch (e) {
      AppStorage.setOrCreate<string>(DailyNoteReminderService.ERROR_KEY, (e as Error).message);
    }
  }

  /** 刷新追踪列表（顺序联网拉取全部被追踪 UID） */
  async refreshTracked(): Promise<DailyNoteRefreshSummary> {
    if (this.trackedBusy) {
      const result: DailyNoteRefreshSummary = new DailyNoteRefreshSummary();
      result.firstError = '正在刷新中，请稍候';
      return result;
    }
    this.trackedBusy = true;
    try {
      const result: DailyNoteRefreshSummary = await DailyNoteService.getInstance().refreshTrackedList();
      await this.load(PreferencesStore.getCurrentUid());
      return result;
    } finally {
      this.trackedBusy = false;
    }
  }

  /** 服务层刷新成功（自动刷新定时器 / 桌面卡片手动刷新）后重读本地缓存，保持界面数值同步 */
  async reloadFromCache(uid: string): Promise<void> {
    await this.load(uid);
  }

  /** 只展示追踪条目，当前角色用最新快照；移除追踪后卡片立即消失。 */
  buildCardEntries(): NoteCardEntry[] {
    const entries: NoteCardEntry[] = [];
    const currentNote: DailyNote | undefined = this.note;
    const currentTracked: DailyNoteTrackedEntry | undefined = this.trackedEntries.find((item: DailyNoteTrackedEntry): boolean =>
      item.userId === this.currentUserId && item.uid === this.currentUid);
    if (currentTracked !== undefined && this.currentUserId > 0 && this.currentUid.length > 0 && currentNote !== undefined) {
      const cur: NoteCardEntry = new NoteCardEntry();
      cur.userId = this.currentUserId;
      cur.uid = this.currentUid;
      cur.nickname = currentTracked.nickname;
      cur.region = currentTracked.region;
      cur.level = currentTracked.level;
      cur.isCurrent = true;
      cur.tracked = true;
      cur.note = currentNote;
      this.applyArchonProgress(cur);
      entries.push(cur);
    }
    for (const t of this.trackedEntries) {
      if (t.userId === this.currentUserId && t.uid === this.currentUid && currentNote !== undefined) {
        continue; // 当前 UID 卡已用最新数据展示
      }
      const e: NoteCardEntry = new NoteCardEntry();
      e.userId = t.userId;
      e.uid = t.uid;
      e.isCurrent = t.userId === this.currentUserId && t.uid === this.currentUid;
      e.tracked = true;
      e.nickname = t.nickname;
      e.region = t.region;
      e.level = t.level;
      e.note = t.record?.note;
      this.applyArchonProgress(e);
      entries.push(e);
    }
    return entries;
  }

  /** 对齐 Windows DailyNoteArchonQuestView：首条章节在 AQ 原序中的索引 / AQ 总数。 */
  private applyArchonProgress(entry: NoteCardEntry): void {
    const note: DailyNote | undefined = entry.note;
    if (note === undefined || !note.hasArchonQuestProgress || this.chapters.length === 0) { return; }
    entry.archonTotal = this.chapters.length;
    const current: ArchonQuestChapter | undefined = note.archonQuests[0];
    if (current === undefined) {
      entry.archonProgress = this.chapters.length;
      return;
    }
    const index: number = this.chapters.findIndex((chapter: DailyNoteChapterMetadata): boolean => chapter.id === current.id);
    entry.archonProgress = index;
    if (index < 0) { return; }
    const chapter: DailyNoteChapterMetadata = this.chapters[index];
    const numberText: string = chapter.numberText || current.chapterNum;
    const title: string = chapter.title || current.chapterTitle;
    entry.archonChapterText = `${numberText} ${title}`.trim();
  }

  /** 打开某 UID 的通知设置（读取现有阈值/开关位；无记录用默认值） */
  async openUidSettings(userId: number, uid: string): Promise<boolean> {
    const version: number = ++this.settingsVersion;
    const rec: DailyNoteRecord | undefined = await DailyNoteRepo.get(userId, uid);
    if (version !== this.settingsVersion || rec === undefined) { return false; }
    this.settingsUserId = userId;
    this.settingsUid = uid;
    this.settingsResinMax = Math.max(0, Math.floor(rec.note.maxResin));
    this.settingsHomeMax = Math.max(0, Math.floor(rec.note.maxHomeCoin));
    this.settingsResinThreshold = Math.min(this.settingsResinMax, Math.max(0, rec.resinNotifyThreshold));
    this.settingsHomeThreshold = Math.min(this.settingsHomeMax, Math.max(0, rec.homeCoinNotifyThreshold));
    this.settingsNotifyFlags = rec.notifyFlags;
    return true;
  }

  /** 保存某 UID 的通知设置 */
  private saveUidSettings(): Promise<void> {
    const userId: number = this.settingsUserId;
    const uid: string = this.settingsUid;
    const resin: number = this.settingsResinThreshold;
    const home: number = this.settingsHomeThreshold;
    const flags: number = this.settingsNotifyFlags;
    const work: Promise<void> = this.settingsSave.then(async (): Promise<void> => {
      const user: User | undefined = await UserRepo.getUserById(userId);
      if (user === undefined || !BackgroundTaskPolicy.owns(user, uid, RegionUtil.regionOfUid(uid)) ||
        PreferencesStore.getBackupJournal().length > 0) { throw new Error('该角色已不可用'); }
      await DailyNoteRepo.updateThresholds(userId, uid, resin, home, flags);
      DailyNoteViewModel.notifyHome();
      await this.rescheduleReminders(userId, uid);
      if (userId === this.currentUserId && uid === this.currentUid) {
        this.resinThreshold = resin;
        this.homeThreshold = home;
        this.notifyFlags = flags;
      }
    });
    this.settingsSave = work.catch(() => {});
    return work;
  }

  private static notifyHome(): void {
    AppStorage.setOrCreate<number>(KEY_NOTE_VERSION, (AppStorage.get<number>(KEY_NOTE_VERSION) ?? 0) + 1);
  }

  private async rescheduleReminders(userId: number, uid: string): Promise<void> {
    const record: DailyNoteRecord | undefined = await DailyNoteRepo.get(userId, uid);
    if (record === undefined) { return; }
    try {
      await DailyNoteReminderService.sync(userId, uid, record.note, record);
    } catch (e) {
      AppStorage.setOrCreate<string>(DailyNoteReminderService.ERROR_KEY, (e as Error).message);
    }
  }

  /** 每 UID 树脂阈值 */
  async setUidResinThreshold(th: number): Promise<void> {
    if (!Number.isInteger(th) || th < 0 || th > this.settingsResinMax || th === this.settingsResinThreshold) { return; }
    this.settingsResinThreshold = th;
    await this.saveUidSettings();
  }

  /** 每 UID 宝钱阈值 */
  async setUidHomeThreshold(th: number): Promise<void> {
    if (!Number.isInteger(th) || th < 0 || th > this.settingsHomeMax || th === this.settingsHomeThreshold) { return; }
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
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    try {
      const note: DailyNote = await DailyNoteService.getInstance().refresh(uid, challenge);
      if (user === undefined || UserService.getInstance().getCurrentUser() !== user || PreferencesStore.getCurrentUid() !== uid) {
        return false;
      }
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
