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
import { RoleCombatRoot } from '../model/RoleCombat';
import { HardChallengeRoot } from '../model/HardChallenge';
import { RegionUtil } from '../common/Constants';
import { WishHistoryService } from './WishHistoryService';
import { InsightBundle, InsightDirection, InsightPoint, InsightSeries } from '../model/AccountInsights';
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
      const items: GachaItem[] = await GachaRepo.getItemsByArchive(archive.id);
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
    } catch (e) {
      Logger.warn(TAG, `wish series fail: ${(e as Error).message}`);
      bundle.failedSources.push('祈愿');
    }
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
  static anonymousJson(bundle: InsightBundle): string {
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
        pointParts.push(`{"period":"${point.period}","value":${point.value}}`);
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
        `"category":"${series.title}","metric":"${series.metric}","unit":"${series.unit}",` +
        `"direction":"${direction}","points":[${pointParts.join(',')}]}`);
    }
    return `{"series":[${parts.join(',')}]}`;
  }
}
