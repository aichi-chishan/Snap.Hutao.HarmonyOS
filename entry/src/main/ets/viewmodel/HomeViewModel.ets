/**
 * HomeViewModel.ets
 * 主页仪表盘数据聚合：祈愿统计（本地缓存）/ 实时便笺（本地缓存）/ 签到信息 / 活动日历 / 公告预览。
 * 各数据源独立加载，互不阻塞；失败只标记对应状态，不拖垮整个主页。
 */
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaArchive } from '../model/GachaArchive';
import { GachaHomeStatService, HomePoolSummary } from '../service/GachaHomeStatService';
import { GachaItem } from '../model/GachaItem';
import { DailyNote } from '../model/DailyNote';
import { DailyNoteService, DailyNoteTrackedEntry, DailyNoteRefreshSummary } from '../service/DailyNoteService';
import { SignInInfo } from '../model/SignInInfo';
import { SignInService } from '../service/SignInService';
import { CalendarEntryOrder, CalendarService } from '../service/CalendarService';
import { ActCalendarEntry } from '../model/ActCalendarEntry';
import { AnnouncementGroup } from '../model/Announcement';
import { AnnouncementContext } from '../model/RegionalContent';
import { User } from '../model/User';
import { AnnouncementService } from '../service/AnnouncementService';
import { UserService } from '../service/UserService';
import { Logger } from '../common/Logger';

const TAG: string = 'HomeViewModel';

/** 周期挑战进度摘要（深境螺旋/幻想真境剧诗/幽境危战） */
export class HomeChallengeSummary {
  /** 深境螺旋：12-3 */
  abyssFloor: string = '';
  /** 深境螺旋：36/36 */
  abyssStar: number = 0;
  abyssMaxStar: number = 0;
  /** 幻想真境剧诗：奖章数 */
  roleCombatMedals: number = 0;
  roleCombatMaxRound: number = 0;
  /** 幽境危战：最佳难度文案 */
  hardChallengeBest: string = '';
  hardChallengeSecond: number = 0;
  loaded: boolean = false;
  message: string = '';

  /** 拷贝构造（供页面 @State 快照；@Observed 深属性不触发容器重建） */
  static of(src: HomeChallengeSummary): HomeChallengeSummary {
    const c: HomeChallengeSummary = new HomeChallengeSummary();
    c.abyssFloor = src.abyssFloor;
    c.abyssStar = src.abyssStar;
    c.abyssMaxStar = src.abyssMaxStar;
    c.roleCombatMedals = src.roleCombatMedals;
    c.roleCombatMaxRound = src.roleCombatMaxRound;
    c.hardChallengeBest = src.hardChallengeBest;
    c.hardChallengeSecond = src.hardChallengeSecond;
    c.loaded = src.loaded;
    c.message = src.message;
    return c;
  }
}

export class HomeNoteEntry {
  userId: number = 0;
  uid: string = '';
  note: DailyNote | undefined = undefined;
  resinThreshold: number = 120;
  homeCoinThreshold: number = 1800;
}

@Observed
export class HomeViewModel {
  /** 祈愿池摘要（有数据的池） */
  gachaPools: HomePoolSummary[] = [];
  gachaTotal: number = 0;
  gachaUid: string = '';
  gachaLoaded: boolean = false;

  /** 所有已存账号的追踪便笺，与完整便笺页使用同一份本地追踪列表。 */
  noteEntries: HomeNoteEntry[] = [];
  noteLoaded: boolean = false;
  noteRefreshing: boolean = false;
  private noteLoadRevision: number = 0;

  /** 签到 */
  signInfo: SignInInfo | undefined = undefined;
  signLoaded: boolean = false;

  /** 首页活动与卡池使用完整响应，预告筛选由首页展示层处理。 */
  acts: ActCalendarEntry[] = [];
  actsLoaded: boolean = false;

  /** 首页按官方分类展示各组的完整列表。 */
  announcementGroups: AnnouncementGroup[] = [];
  announcementsLoaded: boolean = false;

  /** 当前 UID（登录态的） */
  currentUid: string = '';

  /** 是否加载中（任一数据源） */
  loading: boolean = false;
  private loadGeneration: number = 0;
  private ownerUser: User | undefined = undefined;

  /** Session changes invalidate old reads. Reload only after the account transition settles. */
  watchSession(onCommitted: () => void): () => void {
    const users: UserService = UserService.getInstance();
    let watching: boolean = true;
    const unsubscribe: () => void = users.addSessionRevisionListener((): void => {
      if (!watching) { return; }
      this.invalidate();
      if (!users.isSessionTransitionPending()) { onCommitted(); }
    });
    return (): void => {
      watching = false;
      unsubscribe();
    };
  }

  invalidate(): void { this.loadGeneration++; }

  /**
   * 页面可见/登录态变化时调用：聚合加载全部数据源。
   */
  async load(uid: string): Promise<boolean> {
    const users: UserService = UserService.getInstance();
    if (users.isSessionTransitionPending()) { return false; }
    const generation: number = ++this.loadGeneration;
    const owner: User | undefined = users.getCurrentUser();
    // 同一账号返回首页时保留已展示的数据；换账号或角色则立即清空。
    if (this.ownerUser !== owner || this.currentUid !== uid) {
      this.ownerUser = owner;
      this.currentUid = uid;
      this.gachaPools = [];
      this.gachaUid = '';
      this.gachaTotal = 0;
      this.noteEntries = [];
      this.signInfo = undefined;
      this.acts = [];
      this.gachaLoaded = false;
      this.noteLoaded = false;
      this.signLoaded = false;
      this.actsLoaded = false;
      this.announcementGroups = [];
      this.announcementsLoaded = false;
    }
    this.loading = true;
    const tasks: Promise<void>[] = [
      this.loadGacha(uid, generation),
      this.loadNote(generation),
      this.loadSignIn(uid, generation),
      this.loadActs(uid, generation),
      this.loadAnnouncements(uid, generation),
    ];
    try {
      await Promise.all(tasks);
    } catch (e) {
      Logger.warn(TAG, `aggregate load fail: ${(e as Error).message}`);
    }
    if (generation !== this.loadGeneration) { return false; }
    this.loading = false;
    return true;
  }

  /** 刷新全部（下拉/手动） */
  async refresh(uid: string): Promise<void> {
    await this.load(uid);
  }

  /** 祈愿刷新后回主页：仅重读祈愿统计（轻量，不触发网络） */
  async reloadGacha(uid: string): Promise<void> {
    await this.loadGacha(uid, this.loadGeneration);
  }

  /** 祈愿统计：本地缓存直接算（不触发网络拉取，主页展示缓存） */
  private async loadGacha(uid: string, generation: number): Promise<void> {
    try {
      const archives: GachaArchive[] = (await GachaRepo.getAllArchives()).filter((archive: GachaArchive): boolean =>
        archive.id > 0 && /^[1-9][0-9]{8,9}$/.test(archive.uid));
      if (generation !== this.loadGeneration) { return; }
      const archive: GachaArchive | undefined = archives.find((item: GachaArchive): boolean => item.uid === uid)
        ?? archives.find((item: GachaArchive): boolean => item.isSelected) ?? archives[0];
      const records: GachaItem[] = archive === undefined ? [] : await GachaRepo.getItemsByArchive(archive.id);
      if (generation !== this.loadGeneration) { return; }
      const pools: HomePoolSummary[] = GachaHomeStatService.summarize(records);
      this.gachaPools = pools;
      this.gachaTotal = pools.reduce((total: number, pool: HomePoolSummary): number => total + pool.totalCount, 0);
      this.gachaUid = archive?.uid ?? '';
      this.gachaLoaded = true;
    } catch (e) {
      if (generation !== this.loadGeneration) { return; }
      Logger.warn(TAG, `loadGacha fail: ${(e as Error).message}`);
      this.gachaLoaded = true;
    }
  }

  /** 便笺刷新后重读本地缓存（服务层自动刷新/桌面卡片刷新触发，不重复拉网络） */
  async reloadNote(uid: string): Promise<void> {
    if (uid !== this.currentUid) { return; }
    await this.loadNote(this.loadGeneration);
  }

  /** 对齐 Windows：首页刷新全部追踪角色，账号归属和交互验证由服务统一控制。 */
  async refreshNotes(): Promise<string> {
    if (this.noteRefreshing || this.noteEntries.length === 0) { return ''; }
    const generation: number = this.loadGeneration;
    const users: UserService = UserService.getInstance();
    const revision: number = users.sessionRevision();
    this.noteRefreshing = true;
    try {
      const summary: DailyNoteRefreshSummary = await DailyNoteService.getInstance().refreshTrackedList();
      if (generation !== this.loadGeneration || users.sessionRevision() !== revision) { return ''; }
      await this.reloadNote(this.currentUid);
      if (generation !== this.loadGeneration || users.sessionRevision() !== revision) { return ''; }
      if (summary.total === 0) { return summary.firstError; }
      const message: string = `已刷新 ${summary.succeeded}/${summary.total} 个 UID 的便笺`;
      return summary.firstError.length > 0 ? `${message}：${summary.firstError}` : message;
    } catch (e) {
      if (generation !== this.loadGeneration || users.sessionRevision() !== revision) { return ''; }
      if (e instanceof Error) { throw e; }
      throw new Error('便笺刷新失败，请稍后重试');
    } finally {
      this.noteRefreshing = false;
    }
  }

  private async loadNote(generation: number): Promise<void> {
    const revision: number = ++this.noteLoadRevision;
    try {
      const tracked: DailyNoteTrackedEntry[] = await DailyNoteService.getInstance().trackedEntries();
      if (generation !== this.loadGeneration || revision !== this.noteLoadRevision) { return; }
      const entries: HomeNoteEntry[] = [];
      for (const item of tracked) {
        const entry: HomeNoteEntry = new HomeNoteEntry();
        entry.userId = item.userId;
        entry.uid = item.uid;
        entry.note = item.record?.note;
        entry.resinThreshold = item.record?.resinNotifyThreshold ?? entry.resinThreshold;
        entry.homeCoinThreshold = item.record?.homeCoinNotifyThreshold ?? entry.homeCoinThreshold;
        entries.push(entry);
      }
      this.noteEntries = entries;
      this.noteLoaded = true;
    } catch (e) {
      if (generation !== this.loadGeneration || revision !== this.noteLoadRevision) { return; }
      Logger.warn(TAG, `loadNote fail: ${(e as Error).message}`);
      this.noteLoaded = true;
    }
  }

  /** 签到：网络（luna） */
  private async loadSignIn(uid: string, generation: number): Promise<void> {
    try {
      if (uid.length > 0) {
        const info: SignInInfo = await SignInService.getInstance().fetchInfo(uid);
        if (generation !== this.loadGeneration) { return; }
        this.signInfo = info;
      } else {
        this.signInfo = undefined;
      }
      this.signLoaded = true;
    } catch (e) {
      if (generation !== this.loadGeneration) { return; }
      Logger.warn(TAG, `loadSignIn fail: ${(e as Error).message}`);
      this.signLoaded = true;
    }
  }

  /** 首页活动日历沿用原响应顺序，保留未公布时间的预告。 */
  private async loadActs(uid: string, generation: number): Promise<void> {
    try {
      if (uid.length > 0) {
        const current: () => boolean = (): boolean => generation === this.loadGeneration;
        const all: ActCalendarEntry[] = await CalendarService.getInstance().fetchCalendar(uid, current, CalendarEntryOrder.Home);
        if (!current()) { return; }
        this.acts = all;
      }
      this.actsLoaded = true;
    } catch (e) {
      if (generation !== this.loadGeneration) { return; }
      Logger.warn(TAG, `loadActs fail: ${(e as Error).message}`);
      this.actsLoaded = true;
    }
  }

  /** Windows 首页公告页签按响应第 2、第 1、第 3 组排列。 */
  private async loadAnnouncements(uid: string, generation: number): Promise<void> {
    try {
      const context: AnnouncementContext = AnnouncementContext.forUid(uid);
      const groups: AnnouncementGroup[] = await AnnouncementService.getInstance()
        .fetchGroups(context.region, context.level, context.language);
      if (generation !== this.loadGeneration) { return; }
      this.announcementGroups = groups.length > 1 ? [groups[1], groups[0]].concat(groups.slice(2)) : groups;
      this.announcementsLoaded = true;
    } catch (e) {
      Logger.warn(TAG, `loadAnnouncements fail: ${(e as Error).message}`);
      if (generation !== this.loadGeneration) { return; }
      this.announcementsLoaded = true;
    }
  }
}
