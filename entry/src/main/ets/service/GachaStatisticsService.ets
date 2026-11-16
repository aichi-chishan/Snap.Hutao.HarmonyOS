import { GachaItem } from '../model/GachaItem';
import { GachaType } from '../model/GachaType';
import { FiveStarDetail, PoolStatistics, WishSummaryItem } from '../model/GachaStatistics';
import { UigfService } from './UigfService';
import { GachaEventMeta } from './WikiMetaService';

export class GachaStatisticsService {
  /** 输入为按祈愿 ID 升序排列的同一查询池记录。 */
  static buildPool(items: GachaItem[], gachaType: number, events: GachaEventMeta[], timezone: number): PoolStatistics {
    const pool: PoolStatistics = new PoolStatistics();
    pool.gachaType = gachaType;
    pool.typeName = GachaType.nameOf(gachaType);
    pool.totalCount = items.length;
    if (items.length === 0) { return pool; }
    pool.startDate = GachaStatisticsService.date(items[0].time);
    pool.endDate = GachaStatisticsService.date(items[items.length - 1].time);
    const queryType: number = GachaType.queryTypeOf(gachaType);
    const summarizePurple: boolean = GachaType.isBeyond(queryType);
    const summarizeBlue: boolean = queryType === GachaType.UGC_STANDARD;
    let featuredCycle: number = 0;
    let featuredSpans: number = 0;
    let featuredCount: number = 0;
    for (const item of items) {
      pool.sinceLastFive++;
      pool.sinceLastFour++;
      pool.sinceLastThree++;
      featuredCycle++;
      if (item.rankType === 3) {
        if (summarizeBlue) { pool.summaryItems.push(new WishSummaryItem(item, pool.sinceLastThree)); }
        pool.threeStarCount++;
        pool.sinceLastThree = 0;
      }
      if (item.rankType === 4) {
        if (summarizePurple) { pool.summaryItems.push(new WishSummaryItem(item, pool.sinceLastFour)); }
        pool.fourStarCount++;
        pool.sinceLastFour = 0;
      }
      if (item.rankType !== 5) { continue; }

      const span: number = pool.sinceLastFive;
      pool.fiveStarCount++;
      pool.lastFiveName = item.name;
      pool.lastFiveTime = item.time;
      pool.maxOrangePull = Math.max(pool.maxOrangePull, span);
      pool.minOrangePull = pool.minOrangePull === 0 ? span : Math.min(pool.minOrangePull, span);
      pool.sinceLastFive = 0;

      const featured: boolean | undefined = GachaStatisticsService.featured(item, events, timezone);
      const detail: FiveStarDetail = new FiveStarDetail(item, span);
      detail.isUp = featured === true;
      detail.upKnown = featured !== undefined;
      if (featured === true) {
        detail.totalCyclePull = featuredCycle;
        featuredSpans += featuredCycle;
        featuredCount++;
        featuredCycle = 0;
        const previous: FiveStarDetail | undefined = pool.fiveDetails[pool.fiveDetails.length - 1];
        detail.isGuarantee = queryType === GachaType.AVATAR_EVENT && previous?.upKnown === true && !previous.isUp;
      }
      pool.fiveDetails.push(detail);
      pool.summaryItems.push(detail);
      const copy: GachaItem = new GachaItem();
      copy.name = item.name;
      copy.time = item.time;
      copy.rankType = 5;
      pool.fiveHistory.push(copy);
    }
    if (pool.fiveStarCount > 0) { pool.averageOrangePull = (items.length - pool.sinceLastFive) / pool.fiveStarCount; }
    if (featuredCount > 0) { pool.averageUpOrangePull = featuredSpans / featuredCount; }
    if (pool.fourStarCount > 0) { pool.averagePurplePull = (items.length - pool.sinceLastFour) / pool.fourStarCount; }
    pool.fiveDetails.reverse();
    pool.fiveHistory.reverse();
    pool.summaryItems.reverse();
    return pool;
  }

  private static date(time: string): string {
    return time.length < 10 ? time : time.substring(0, 10).replace(/-/g, '.');
  }

  private static featured(item: GachaItem, events: GachaEventMeta[], timezone: number): boolean | undefined {
    if (item.itemId <= 0) { return undefined; }
    let timestamp: number;
    try {
      timestamp = Date.parse(UigfService.normalizeTime(item.time, timezone, 0).replace(' ', 'T') + 'Z');
    } catch (_) {
      return undefined;
    }
    for (const event of events) {
      if (event.type === item.gachaType && timestamp >= event.from && timestamp <= event.to) {
        return event.upOrange.includes(item.itemId);
      }
    }
    return undefined;
  }
}
