/**
 * StatsComputer.ets
 * 祈愿统计聚合的 TaskPool 并发版本（@Concurrent），跨线程传原始字段数组（Sendable 兼容），返回可序列化对象。
 */
import { taskpool } from '@kit.ArkTS';

/**
 * 单池聚合：输入该池全部记录的 rankType/name/time（按时间升序），返回统计摘要。
 * @Concurrent 函数必须自包含，仅使用序列化参数。
 */
@Concurrent
function computePoolSummary(rankTypes: number[], names: string[], times: string[], gachaType: number): Object {
  const total: number = rankTypes.length;
  let fiveStar: number = 0;
  let fourStar: number = 0;
  let sinceLastFive: number = 0;
  let lastFiveName: string = '';
  let lastFiveTime: string = '';
  // five history (name, time, gacha sort key) - 使用扁平数组返回
  const fiveNames: string[] = [];
  const fiveTimes: string[] = [];
  for (let i = 0; i < total; i++) {
    const rank: number = rankTypes[i];
    if (rank === 5) {
      fiveStar++;
      fiveNames.push(names[i]);
      fiveTimes.push(times[i]);
    } else if (rank === 4) {
      fourStar++;
    }
  }
  // 垫数：从最新向旧数到最近一次金
  for (let i = total - 1; i >= 0; i--) {
    if (rankTypes[i] === 5) {
      break;
    }
    sinceLastFive++;
  }
  // 最近出金（name 列表末尾即最新一次出金，因为输入按时间升序）
  if (fiveNames.length > 0) {
    lastFiveName = fiveNames[fiveNames.length - 1];
    lastFiveTime = fiveTimes[fiveTimes.length - 1];
  }
  const result: Record<string, Object> = {
    'gachaType': gachaType,
    'totalCount': total,
    'fiveStarCount': fiveStar,
    'fourStarCount': fourStar,
    'sinceLastFive': sinceLastFive,
    'lastFiveName': lastFiveName,
    'lastFiveTime': lastFiveTime,
    'fiveNames': fiveNames,
    'fiveTimes': fiveTimes,
  };
  return result;
}

export class PoolSummary {
  totalCount: number = 0;
  fiveStarCount: number = 0;
  fourStarCount: number = 0;
  sinceLastFive: number = 0;
  lastFiveName: string = '';
  lastFiveTime: string = '';
  fiveNames: string[] = [];
  fiveTimes: string[] = [];

  static fromResult(obj: Object): PoolSummary {
    const r = obj as Record<string, Object>;
    const s: PoolSummary = new PoolSummary();
    s.totalCount = Number(r['totalCount'] ?? 0);
    s.fiveStarCount = Number(r['fiveStarCount'] ?? 0);
    s.fourStarCount = Number(r['fourStarCount'] ?? 0);
    s.sinceLastFive = Number(r['sinceLastFive'] ?? 0);
    s.lastFiveName = String(r['lastFiveName'] ?? '');
    s.lastFiveTime = String(r['lastFiveTime'] ?? '');
    const fns = r['fiveNames'] as Array<Object>;
    const fts = r['fiveTimes'] as Array<Object>;
    if (fns !== undefined && fns !== null) {
      for (let i = 0; i < fns.length; i++) {
        s.fiveNames.push(String(fns[i]));
      }
    }
    if (fts !== undefined && fts !== null) {
      for (let i = 0; i < fts.length; i++) {
        s.fiveTimes.push(String(fts[i]));
      }
    }
    return s;
  }
}

/** 抛入 TaskPool 执行聚合 */
export async function computePoolSummaryAsync(rankTypes: number[], names: string[],
  times: string[], gachaType: number): Promise<PoolSummary> {
  const obj: Object = await taskpool.execute<[number[], string[], string[], number], Object>(
    computePoolSummary, rankTypes, names, times, gachaType);
  return PoolSummary.fromResult(obj);
}
