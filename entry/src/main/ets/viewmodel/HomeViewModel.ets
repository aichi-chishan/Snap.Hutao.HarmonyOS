/**
 * HomeViewModel.ets
 * 主页仪表盘数据聚合：祈愿统计（本地缓存）/ 实时便笺（本地缓存）/ 签到信息 / 活动日历 / 公告预览。
 * 各数据源独立加载，互不阻塞；失败只标记对应状态，不拖垮整个主页。
 */
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaType } from '../model/GachaType';
import { GachaItem } from '../model/GachaItem';
import { DailyNoteRepo, DailyNoteRecord } from '../data/repo/DailyNoteRepo';
import { DailyNote } from '../model/DailyNote';
import { SignInInfo } from '../model/SignInInfo';
import { SignInService } from '../service/SignInService';
import { CalendarService } from '../service/CalendarService';
import { ActCalendarEntry } from '../model/ActCalendarEntry';
import { Announcement } from '../model/Announcement';
import { AnnouncementService } from '../service/AnnouncementService';
import { UserService } from '../service/UserService';
import { SpiralAbyssData } from '../model/SpiralAbyss';
import { SpiralAbyssService } from '../service/SpiralAbyssService';
import { RoleCombatRoot } from '../model/RoleCombat';
import { RoleCombatService } from '../service/RoleCombatService';
import { HardChallengeRoot, HardChallengeDataEntry } from '../model/HardChallenge';
import { HardChallengeService } from '../service/HardChallengeService';
import { Logger } from '../common/Logger';

const TAG: string = 'HomeViewModel';

/** 池摘要卡：祈愿统计主页迷你版（每池：名称/总抽/距保底橙紫） */
export class HomePoolSummary {
  gachaType: number = 0;
  typeName: string = '';
  totalCount: number = 0;
  sinceLastFive: number = 0;
  sinceLastFour: number = 0;
  /** 距上次五星（用于进度条/大数字） */
  fiveStarCount: number = 0;
  fourStarCount: number = 0;
  avgOrangePull: number = 0;
  maxOrangePull: number = 0;
  minOrangePull: number = 0;
  startDate: string = '';
  endDate: string = '';
}

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

@Observed
export class HomeViewModel {
  /** 祈愿池摘要（有数据的池） */
  gachaPools: HomePoolSummary[] = [];
  gachaTotal: number = 0;
  gachaLoaded: boolean = false;

  /** 便笺（当前 UID） */
  note: DailyNote | undefined = undefined;
  noteLoaded: boolean = false;
  noteRefreshTime: string = '';

  /** 签到 */
  signInfo: SignInInfo | undefined = undefined;
  signLoaded: boolean = false;

  /** 活动（取前 N 条进行中/即将开始） */
  acts: ActCalendarEntry[] = [];
  actsLoaded: boolean = false;

  /** 公告预览（前 N 条） */
  announcements: Announcement[] = [];
  announcementsLoaded: boolean = false;

  /** 周期挑战进度（深境螺旋/剧诗/幽境） */
  challenge: HomeChallengeSummary = new HomeChallengeSummary();

  /** 当前 UID（登录态的） */
  currentUid: string = '';

  /** 是否加载中（任一数据源） */
  loading: boolean = false;

  /**
   * 页面可见/登录态变化时调用：聚合加载全部数据源。
   */
  async load(uid: string): Promise<void> {
    this.currentUid = uid;
    this.loading = true;
    const tasks: Promise<void>[] = [
      this.loadGacha(uid),
      this.loadNote(uid),
      this.loadSignIn(uid),
      this.loadActs(uid),
      this.loadAnnouncements(),
      this.loadChallenges(uid),
    ];
    try {
      await Promise.all(tasks);
    } catch (e) {
      Logger.warn(TAG, `aggregate load fail: ${(e as Error).message}`);
    }
    this.loading = false;
  }

  /** 刷新全部（下拉/手动） */
  async refresh(uid: string): Promise<void> {
    await this.load(uid);
  }

  /** 祈愿刷新后回主页：仅重读祈愿统计（轻量，不触发网络） */
  async reloadGacha(uid: string): Promise<void> {
    await this.loadGacha(uid);
  }

  /** 祈愿统计：本地缓存直接算（不触发网络拉取，主页展示缓存） */
  private async loadGacha(uid: string): Promise<void> {
    if (uid.length === 0) {
      // 未登录/未绑定：不创建空归档
      this.gachaLoaded = true;
      return;
    }
    try {
      const stats: HomePoolSummary[] = [];
      let total: number = 0;
      const archiveId: number = await GachaRepo.getOrCreateArchive(uid).then(a => a.id);
      for (let i = 0; i < GachaType.QUERY_ORDER.length; i++) {
        const type: number = GachaType.QUERY_ORDER[i];
        const pool: PoolStatInline = await HomeViewModel.computePool(archiveId, type);
        if (pool.totalCount <= 0) {
          continue;
        }
        const summary: HomePoolSummary = new HomePoolSummary();
        summary.gachaType = type;
        summary.typeName = GachaType.nameOf(type);
        summary.totalCount = pool.totalCount;
        summary.sinceLastFive = pool.sinceLastFive;
        summary.sinceLastFour = pool.sinceLastFour;
        summary.fiveStarCount = pool.fiveStarCount;
        summary.fourStarCount = pool.fourStarCount;
        summary.avgOrangePull = pool.avgOrangePull;
        summary.maxOrangePull = pool.maxOrangePull;
        summary.minOrangePull = pool.minOrangePull;
        summary.startDate = pool.startDate;
        summary.endDate = pool.endDate;
        total += pool.totalCount;
        stats.push(summary);
      }
      this.gachaPools = stats;
      this.gachaTotal = total;
      this.gachaLoaded = true;
    } catch (e) {
      Logger.warn(TAG, `loadGacha fail: ${(e as Error).message}`);
      this.gachaLoaded = true;
    }
  }

  /** 便笺：本地缓存 */
  private async loadNote(uid: string): Promise<void> {
    try {
      const user = UserService.getInstance().getCurrentUser();
      if (user !== undefined && uid.length > 0) {
        const rec: DailyNoteRecord | undefined = await DailyNoteRepo.get(user.id, uid);
        if (rec !== undefined) {
          this.note = rec.note;
          this.noteRefreshTime = HomeViewModel.formatRefreshTime(rec.note.refreshTime);
        }
      }
      this.noteLoaded = true;
    } catch (e) {
      Logger.warn(TAG, `loadNote fail: ${(e as Error).message}`);
      this.noteLoaded = true;
    }
  }

  /** 签到：网络（luna） */
  private async loadSignIn(uid: string): Promise<void> {
    try {
      if (uid.length > 0) {
        this.signInfo = await SignInService.getInstance().fetchInfo(uid);
      }
      this.signLoaded = true;
    } catch (e) {
      Logger.warn(TAG, `loadSignIn fail: ${(e as Error).message}`);
      this.signLoaded = true;
    }
  }

  /** 活动日历：网络（act_calendar），取进行中/开始中前 6 条 */
  private async loadActs(uid: string): Promise<void> {
    try {
      if (uid.length > 0) {
        const all: ActCalendarEntry[] = await CalendarService.getInstance().fetchCalendar(uid);
        const now: number = Date.now();
        const sorted: ActCalendarEntry[] = all
          .filter((a: ActCalendarEntry) => a.endTime > now)
          .sort((a: ActCalendarEntry, b: ActCalendarEntry) => a.startTime - b.startTime);
        this.acts = sorted.length > 6 ? sorted.slice(0, 6) : sorted;
      }
      this.actsLoaded = true;
    } catch (e) {
      Logger.warn(TAG, `loadActs fail: ${(e as Error).message}`);
      this.actsLoaded = true;
    }
  }

  /** 公告预览：网络（getAnnList）前 3 条 */
  private async loadAnnouncements(): Promise<void> {
    try {
      const list: Announcement[] = await AnnouncementService.getInstance().fetchList('cn_gf01', 60);
      this.announcements = list.length > 3 ? list.slice(0, 3) : list;
      this.announcementsLoaded = true;
    } catch (e) {
      Logger.warn(TAG, `loadAnnouncements fail: ${(e as Error).message}`);
      this.announcementsLoaded = true;
    }
  }

  private static formatRefreshTime(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d: Date = new Date(ts);
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
  }

  /** 单池内联统计 */
  private static async computePool(archiveId: number, gachaType: number): Promise<PoolStatInline> {
    const pool: PoolStatInline = new PoolStatInline();
    const items: GachaItem[] = await GachaRepo.getItemsByType(archiveId, gachaType);
    pool.totalCount = items.length;
    // 与 GachaLogViewModel.buildPoolStats 同构：五星/四星计数、垫数、均/最非/最欧
    let fiveStar: number = 0;
    let fourStar: number = 0;
    const fiveSpans: number[] = [];
    let span: number = 0;
    for (let i = 0; i < items.length; i++) {
      if (items[i].rankType === 5) {
        fiveStar++;
        fiveSpans.push(span + 1);
        span = 0;
      } else {
        span++;
        if (items[i].rankType === 4) {
          fourStar++;
        }
      }
    }
    let sinceLastFive: number = 0;
    for (let i = items.length - 1; i >= 0; i--) {
      if (items[i].rankType === 5) {
        break;
      }
      sinceLastFive++;
    }
    let sinceLastFour: number = 0;
    for (let i = items.length - 1; i >= 0; i--) {
      if (items[i].rankType === 4) {
        break;
      }
      sinceLastFour++;
    }
    pool.fiveStarCount = fiveStar;
    pool.fourStarCount = fourStar;
    pool.sinceLastFive = sinceLastFive;
    pool.sinceLastFour = sinceLastFour;
    if (fiveStar > 0) {
      pool.avgOrangePull = Math.round(items.length / fiveStar);
      for (let i = 0; i < fiveSpans.length; i++) {
        if (pool.maxOrangePull === 0 || fiveSpans[i] > pool.maxOrangePull) {
          pool.maxOrangePull = fiveSpans[i];
        }
        if (pool.minOrangePull === 0 || fiveSpans[i] < pool.minOrangePull) {
          pool.minOrangePull = fiveSpans[i];
        }
      }
    }
    pool.startDate = HomeViewModel.formatDate(items.length > 0 ? items[0].time : '');
    pool.endDate = HomeViewModel.formatDate(items.length > 0 ? items[items.length - 1].time : '');
    return pool;
  }

  /** 周期挑战进度：并行拉螺旋/剧诗/幽境（各源独立失败，不阻塞主页） */
  private async loadChallenges(uid: string): Promise<void> {
    if (uid.length === 0) {
      this.challenge.loaded = true;
      return;
    }
    const c: HomeChallengeSummary = this.challenge;
    await Promise.all([
      this.loadAbyss(uid, c),
      this.loadRoleCombat(uid, c),
      this.loadHardChallenge(uid, c),
    ]);
    c.loaded = true;
  }

  private async loadAbyss(uid: string, c: HomeChallengeSummary): Promise<void> {
    try {
      const data: SpiralAbyssData = await SpiralAbyssService.getInstance().fetch(uid, 1);
      if (data !== undefined) {
        c.abyssFloor = data.maxFloor;
        c.abyssStar = data.totalStar;
        c.abyssMaxStar = 36;
      }
    } catch (e) {
      Logger.warn(TAG, `challenge abyss fail: ${(e as Error).message}`);
    }
  }

  private async loadRoleCombat(uid: string, c: HomeChallengeSummary): Promise<void> {
    try {
      const root: RoleCombatRoot = await RoleCombatService.getInstance().fetch(uid);
      if (root !== undefined && root.data.length > 0) {
        c.roleCombatMedals = root.data[0].stat.medalNumber;
        c.roleCombatMaxRound = root.data[0].stat.maxRoundId;
      }
    } catch (e) {
      Logger.warn(TAG, `challenge roleCombat fail: ${(e as Error).message}`);
    }
  }

  private async loadHardChallenge(uid: string, c: HomeChallengeSummary): Promise<void> {
    try {
      const root: HardChallengeRoot = await HardChallengeService.getInstance().fetch(uid);
      if (root !== undefined) {
        const best: HardChallengeDataEntry = root.data.single.hasData ? root.data.single : root.data.mp;
        if (best.hasData) {
          // 最佳难度文案：best.name（本地化难度名）优先；空则用 difficulty/秒数兜底
          c.hardChallengeBest = best.best.name.length > 0 ? best.best.name
            : (best.best.difficulty > 0 ? `难度 ${best.best.difficulty}` : '挑战');
          c.hardChallengeSecond = best.best.second;
        }
      }
    } catch (e) {
      Logger.warn(TAG, `challenge hard fail: ${(e as Error).message}`);
    }
  }

  private static formatDate(time: string): string {
    if (time.length < 10) {
      return time;
    }
    return `${time.substring(0, 4)}.${time.substring(5, 7)}.${time.substring(8, 10)}`;
  }
}

/** 内联单池统计（HomeViewModel 专用） */
class PoolStatInline {
  totalCount: number = 0;
  fiveStarCount: number = 0;
  fourStarCount: number = 0;
  sinceLastFive: number = 0;
  sinceLastFour: number = 0;
  avgOrangePull: number = 0;
  maxOrangePull: number = 0;
  minOrangePull: number = 0;
  startDate: string = '';
  endDate: string = '';
}
