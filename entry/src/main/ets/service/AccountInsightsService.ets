/**
 * AccountInsightsService.ets
 * 账号洞察聚合（对齐 Windows AccountInsightsHistoryService）：
 * 祈愿/颂愿（本地祈愿库）+ 深境螺旋（totalStar）+ 幻想真境剧诗（勋章数，解析期数存档）
 * + 幽境危战（按难度分系列的最佳秒数）→ InsightSeries[]；时间序列取最近 12 期。
 * 只读本地库，不发网络请求；AI 分析用匿名 JSON 不含 UID。
 */
import { GachaRepo } from '../data/repo/GachaRepo';
import { SpiralAbyssRepo } from '../data/repo/SpiralAbyssRepo';
import { RoleCombatRepo } from '../data/repo/RoleCombatRepo';
import { HardChallengeRepo } from '../data/repo/HardChallengeRepo';
import { GachaArchive } from '../model/GachaArchive';
import { GachaItem } from '../model/GachaItem';
import { GachaType } from '../model/GachaType';
import { GachaPoolRules } from '../model/GachaPoolRules';
import { FiveStarDetail, PoolStatistics } from '../model/GachaStatistics';
import { RoleCombatRoot } from '../model/RoleCombat';
import { HardChallengeRoot } from '../model/HardChallenge';
import { RegionUtil } from '../common/Constants';
import { WishHistoryService } from './WishHistoryService';
import { GachaStatisticsService } from './GachaStatisticsService';
import { GachaItemIdentityService } from './GachaItemIdentityService';
import { GachaHistoryService, HistoryWishView } from './GachaHistoryService';
import { GachaEventMeta, WikiMetaService } from './WikiMetaService';
import { UigfService } from './UigfService';
import { InsightBanner, InsightBannerObtain, InsightBundle, InsightDirection, InsightPoint, InsightSeries,
  InsightWishObtain, InsightWishPool, InsightWishStatistics } from '../model/AccountInsights';
import { Logger } from '../common/Logger';

const TAG: string = 'AccountInsightsService';

/** 单个数据源内的期次条目（service 内部传递用） */
class ChallengePeriod {
  date: string = '';
  difficulty: number = 0;
  seconds: number = 0;
}

export class AccountInsightsService {
  private static instance: AccountInsightsService = new AccountInsightsService();

  static getInstance(): AccountInsightsService {
    return AccountInsightsService.instance;
  }

  /** 聚合指定 UID 的全部洞察序列（失败的数据源记入 failedSources，不中断其余） */
  async build(uid: string): Promise<InsightBundle> {
    const bundle: InsightBundle = new InsightBundle();
    if (uid.length === 0) {
      return bundle;
    }
    const region: string = RegionUtil.regionOfUid(uid);
    await this.appendWishSeries(uid, bundle);
    await this.appendAbyssSeries(uid, region, bundle);
    await this.appendTheaterSeries(uid, region, bundle);
    await this.appendChallengeSeries(uid, region, bundle);
    return bundle;
  }

  /** 祈愿 + 颂愿：按月（近 12 个月）与按池分布 */
  private async appendWishSeries(uid: string, bundle: InsightBundle): Promise<void> {
    try {
      const archives = await GachaRepo.getAllArchives();
      const archive: GachaArchive | undefined = archives.find((a: GachaArchive): boolean => a.uid === uid);
      if (archive === undefined) {
        return;
      }
      const items: GachaItem[] = await GachaItemIdentityService.resolveMissing(await GachaRepo.getItemsByArchive(archive.id));
      const normal: GachaItem[] = [];
      const beyond: GachaItem[] = [];
      for (const item of items) {
        if (GachaType.isBeyond(item.gachaType)) {
          beyond.push(item);
        } else {
          normal.push(item);
        }
      }
      const monthlyNormal = this.monthlyPoints(normal);
      const monthlyBeyond = this.monthlyPoints(beyond);
      if (monthlyNormal.length > 0 || this.poolPoints(normal).length > 0) {
        bundle.series.push(new InsightSeries('祈愿', '按月', '抽', monthlyNormal, InsightDirection.Neutral));
        bundle.series.push(new InsightSeries('祈愿', '按池', '抽', this.poolPoints(normal),
          InsightDirection.Neutral, false));
      }
      if (monthlyBeyond.length > 0 || this.poolPoints(beyond).length > 0) {
        bundle.series.push(new InsightSeries('颂愿', '按月', '抽', monthlyBeyond, InsightDirection.Neutral));
        bundle.series.push(new InsightSeries('颂愿', '按池', '抽', this.poolPoints(beyond),
          InsightDirection.Neutral, false));
      }
      if (items.length > 0) { await this.appendWishStatistics(items, uid, bundle); }
    } catch (e) {
      Logger.warn(TAG, `wish series fail: ${(e as Error).message}`);
      bundle.failedSources.push('祈愿');
    }
  }

  private async appendWishStatistics(items: GachaItem[], uid: string, bundle: InsightBundle): Promise<void> {
    const events: GachaEventMeta[] = await WikiMetaService.getGachaEvents();
    const timezone: number = UigfService.timezoneOfUid(uid);
    const groups: Map<number, GachaItem[]> = new Map<number, GachaItem[]>();
    for (const item of items) {
      const type: number = GachaType.queryTypeOf(item.gachaType);
      const group: GachaItem[] = groups.get(type) ?? [];
      group.push(item);
      groups.set(type, group);
    }
    const types: number[] = [301, 302, 500, 200, 100, 1000, 2000];
    const names: string[] = ['avatar_event', 'weapon_event', 'chronicled', 'standard', 'novice', 'beyond_standard', 'beyond_event'];
    const computed: InsightWishStatistics = new InsightWishStatistics();
    for (let index: number = 0; index < types.length; index++) {
      const pool: PoolStatistics = GachaStatisticsService.buildPool(groups.get(types[index]) ?? [], types[index], events, timezone);
      computed.pools.push(AccountInsightsService.insightPool(pool, names[index]));
      if (types[index] === GachaType.AVATAR_EVENT) { bundle.featuredChart = AccountInsightsService.featuredChart(pool); }
    }
    bundle.wishStatistics = computed;
    if (events.length === 0) { return; }
    try {
      const banners: HistoryWishView[] = await GachaHistoryService.getInstance().buildFromItems(items, events, timezone);
      for (const entry of banners.slice(0, 24)) {
        const banner: InsightBanner = new InsightBanner();
        banner.from = WishHistoryService.dateText(entry.from);
        banner.to = WishHistoryService.dateText(entry.to);
        for (const feature of entry.orangeUps.slice(0, 6)) {
          const obtain: InsightBannerObtain = new InsightBannerObtain();
          obtain.name = feature.name;
          obtain.recorded_obtain_count = feature.count;
          banner.featured_five_stars.push(obtain);
        }
        computed.recent_banner_featured_characters_and_weapons.push(banner);
      }
    } catch (e) {
      Logger.warn(TAG, `wish banner insights fail: ${(e as Error).message}`);
    }
  }

  private static insightPool(pool: PoolStatistics, name: string): InsightWishPool {
    const result: InsightWishPool = new InsightWishPool();
    result.pool = name;
    result.total_wishes = pool.totalCount;
    result.five_star_count = pool.fiveStarCount;
    result.four_star_count = pool.fourStarCount;
    result.five_star_rate_in_observed_wishes = pool.totalCount > 0 ? pool.fiveStarCount / pool.totalCount : null;
    result.average_wishes_per_five_star = pool.fiveStarCount > 0 ? pool.averageOrangePull : null;
    result.average_wishes_per_featured_five_star = pool.averageUpOrangePull > 0 ? pool.averageUpOrangePull : null;
    result.minimum_wishes_per_five_star = pool.minOrangePull;
    result.maximum_wishes_per_five_star = pool.maxOrangePull;
    result.current_wishes_since_last_five_star = pool.sinceLastFive;
    result.game_guarantee_threshold = GachaPoolRules.fiveStarThreshold(pool.gachaType);
    const shown: number = Math.min(35, pool.fiveDetails.length);
    for (let index: number = 0; index < shown; index++) {
      const detail: FiveStarDetail = pool.fiveDetails[index];
      const obtain: InsightWishObtain = new InsightWishObtain();
      obtain.name = detail.name;
      obtain.date = detail.time.substring(0, 10);
      obtain.pulls_for_this_five_star = detail.lastPull;
      obtain.is_featured = detail.upKnown ? detail.isUp : null;
      const previous: FiveStarDetail | undefined = pool.fiveDetails[index + 1];
      if (detail.upKnown && previous?.upKnown === true) { obtain.is_guaranteed = detail.isUp && !previous.isUp; }
      if (detail.isUp) { obtain.pulls_since_previous_featured = detail.totalCyclePull; }
      result.recorded_five_star_obtains.push(obtain);
    }
    return result;
  }

  private static featuredChart(pool: PoolStatistics): InsightSeries | undefined {
    const counts: Map<string, number> = new Map<string, number>();
    for (const item of pool.fiveDetails) {
      if (item.isUp && item.name.length > 0) { counts.set(item.name, (counts.get(item.name) ?? 0) + 1); }
    }
    if (counts.size === 0) { return undefined; }
    const points: InsightPoint[] = Array.from(counts.keys()).map((name: string): InsightPoint => new InsightPoint(name, counts.get(name) ?? 0));
    points.sort((a: InsightPoint, b: InsightPoint): number => b.value - a.value || a.period.localeCompare(b.period));
    return new InsightSeries('祈愿', '已获得的 UP 五星角色', '抽', points.slice(0, 15), InsightDirection.Neutral, false);
  }

  /** 按月计数（period=yyyy-MM，字典序即时间序，取最近 12 个月） */
  private monthlyPoints(items: GachaItem[]): InsightPoint[] {
    const counts: Map<string, number> = new Map<string, number>();
    for (const item of items) {
      // item.time 为 'yyyy-MM-dd HH:mm:ss'（服务器时间）
      const month: string = item.time.length >= 7 ? item.time.substring(0, 7) : '';
      if (month.length === 0) {
        continue;
      }
      counts.set(month, (counts.get(month) ?? 0) + 1);
    }
    const months: string[] = Array.from(counts.keys()).sort();
    const out: InsightPoint[] = [];
    for (const month of months.slice(-12)) {
      out.push(new InsightPoint(month, counts.get(month) ?? 0));
    }
    return out;
  }

  /** 按池计数（period=池名，按池类型号升序） */
  private poolPoints(items: GachaItem[]): InsightPoint[] {
    const counts: Map<number, number> = new Map<number, number>();
    for (const item of items) {
      counts.set(item.gachaType, (counts.get(item.gachaType) ?? 0) + 1);
    }
    const types: number[] = Array.from(counts.keys()).sort((a: number, b: number): number => a - b);
    const out: InsightPoint[] = [];
    for (const type of types) {
      out.push(new InsightPoint(GachaType.nameOf(type), counts.get(type) ?? 0));
    }
    return out;
  }

  /** 深境螺旋：每期总星（对齐 Windows：按 scheduleId 升序，取最近 12 期） */
  private async appendAbyssSeries(uid: string, region: string, bundle: InsightBundle): Promise<void> {
    try {
      const entries = await SpiralAbyssRepo.listHistory(uid, region);
      const sorted = entries.slice().sort((a, b) => a.scheduleId - b.scheduleId);
      const points: InsightPoint[] = [];
      for (const entry of sorted.slice(-12)) {
        const period: string = entry.startTime > 0
          ? WishHistoryService.dateText(entry.startTime)
          : `第 ${entry.scheduleId} 期`;
        points.push(new InsightPoint(period, entry.totalStar));
      }
      if (points.length > 0) {
        bundle.series.push(new InsightSeries('深境螺旋', '每期星数', '星', points,
          InsightDirection.HigherIsBetter));
      }
    } catch (e) {
      Logger.warn(TAG, `abyss series fail: ${(e as Error).message}`);
      bundle.failedSources.push('深境螺旋');
    }
  }

  /** 幻想真境剧诗：每期勋章数（解析期数存档的原始 JSON） */
  private async appendTheaterSeries(uid: string, region: string, bundle: InsightBundle): Promise<void> {
    try {
      const entries = await RoleCombatRepo.listHistory(uid, region);
      const sorted = entries.slice().sort((a, b) => a.scheduleId - b.scheduleId);
      const points: InsightPoint[] = [];
      for (const entry of sorted.slice(-12)) {
        const raw: string = await RoleCombatRepo.getRawJson(uid, region, entry.scheduleId);
        if (raw.length === 0) {
          continue;
        }
        const item = RoleCombatRoot.dataItemFromJson(JSON.parse(raw));
        if (!item.hasData) {
          continue;
        }
        const period: string = entry.startTime > 0
          ? WishHistoryService.dateText(entry.startTime)
          : `第 ${entry.scheduleId} 期`;
        points.push(new InsightPoint(period, item.stat.medalNumber));
      }
      if (points.length > 0) {
        bundle.series.push(new InsightSeries('幻想真境剧诗', '每期勋章', '枚', points,
          InsightDirection.HigherIsBetter));
      }
    } catch (e) {
      Logger.warn(TAG, `theater series fail: ${(e as Error).message}`);
      bundle.failedSources.push('幻想真境剧诗');
    }
  }

  /** 幽境危战：按最佳成绩难度分系列，每期最快通关秒数（越低越好） */
  private async appendChallengeSeries(uid: string, region: string, bundle: InsightBundle): Promise<void> {
    try {
      const entries = await HardChallengeRepo.listHistory(uid, region);
      const sorted = entries.slice().sort((a, b) => a.scheduleId - b.scheduleId);
      const periods: ChallengePeriod[] = [];
      for (const entry of sorted) {
        const raw: string = await HardChallengeRepo.getRawJson(uid, region, entry.scheduleId);
        if (raw.length === 0) {
          continue;
        }
        const root: HardChallengeRoot = HardChallengeRoot.fromJson(JSON.parse(raw));
        if (!root.data.single.hasData || root.data.single.best.second <= 0) {
          continue;
        }
        const period: ChallengePeriod = new ChallengePeriod();
        period.date = entry.startTime > 0
          ? WishHistoryService.dateText(entry.startTime)
          : `第 ${entry.scheduleId} 期`;
        period.difficulty = root.data.single.best.difficulty;
        period.seconds = root.data.single.best.second;
        periods.push(period);
      }
      const difficulties: number[] = [];
      for (const p of periods) {
        if (difficulties.indexOf(p.difficulty) < 0) {
          difficulties.push(p.difficulty);
        }
      }
      difficulties.sort((a: number, b: number): number => a - b);
      for (const difficulty of difficulties) {
        const points: InsightPoint[] = [];
        for (const p of periods) {
          if (p.difficulty === difficulty) {
            points.push(new InsightPoint(p.date, p.seconds));
          }
        }
        bundle.series.push(new InsightSeries('幽境危战', `最快通关（难度 ${difficulty}）`, '秒',
          points.slice(-12), InsightDirection.LowerIsBetter, true, difficulty));
      }
    } catch (e) {
      Logger.warn(TAG, `challenge series fail: ${(e as Error).message}`);
      bundle.failedSources.push('幽境危战');
    }
  }

  /**
   * AI 分析用匿名 JSON（对齐 Windows CreateAnonymousJson：序列 + 摘要，无 UID/无个人标识）。
   * 手工拼 JSON 字符串以符合 ArkTS 禁匿名对象字面量的约束。
   */
  static anonymousJson(bundle: InsightBundle, includePoints: boolean = true): string {
    const parts: string[] = [];
    for (const series of bundle.series) {
      const pointParts: string[] = [];
      let sum: number = 0;
      let min: number | null = null;
      let max: number | null = null;
      let hasTimeLatest: boolean = false;
      let timeLatest: number = 0;
      let timePrev: number | null = null;
      for (const point of series.points) {
        if (includePoints) { pointParts.push(`{"period":${JSON.stringify(point.period)},"value":${point.value}}`); }
        sum += point.value;
        if (min === null || point.value < min) { min = point.value; }
        if (max === null || point.value > max) { max = point.value; }
        if (series.isTimeSeries) {
          timePrev = hasTimeLatest ? timeLatest : null;
          timeLatest = point.value;
          hasTimeLatest = true;
        }
      }
      const count: number = series.points.length;
      const summary: string = `"summary":{"recorded_period_count":${count},` +
        `"latest":${hasTimeLatest ? timeLatest : 'null'},` +
        `"minimum":${min !== null ? min : 'null'},` +
        `"maximum":${max !== null ? max : 'null'},` +
        `"average":${count > 0 ? Math.round((sum / count) * 100) / 100 : 'null'},` +
        `"latest_change_from_previous":${hasTimeLatest && timePrev !== null ? timeLatest - timePrev : 'null'}}`;
      const direction: string = series.direction === InsightDirection.HigherIsBetter
        ? 'higher_is_better' : series.direction === InsightDirection.LowerIsBetter
          ? 'lower_is_better' : 'neutral';
      parts.push(`{${summary},"difficulty":${series.difficulty !== null ? series.difficulty : 'null'},` +
        `"kind":"${series.isTimeSeries ? 'time_series' : 'category_distribution'}",` +
        `"category":${JSON.stringify(series.title)},"metric":${JSON.stringify(series.metric)},"unit":${JSON.stringify(series.unit)},` +
        `"direction":"${direction}"${includePoints ? `,"periods":[${pointParts.join(',')}]` : ''}}`);
    }
    const wish: string = includePoints && bundle.wishStatistics !== undefined
      ? `,"hu_tao_computed_gacha_statistics":${JSON.stringify(bundle.wishStatistics)}` : '';
    return `{"schema_version":1,"series":[${parts.join(',')}]${wish}}`;
  }
}
