import { GachaPoolRules } from '../model/GachaPoolRules';
import { HutaoCloudJson } from '../model/HutaoCloud';
import { HutaoCloudService } from './HutaoCloudService';

export class GachaPrediction {
  available: boolean = false;
  poolType: number = 0;
  threshold: number = 0;
  pity: number = 0;
  sampleEvents: number = 0;
  remainingEvents: number = 0;
  retrievedAt: number = 0;
  nextProbability: number = 0;
  predictedRemaining: number = 0;
  predictedProbability: number = 0;
  conditional: number[] = [];
  message: string = '暂无可用经验分布';
}

/** Conditional empirical distribution, matching Windows PullPrediction without inventing theoretical odds. */
export class GachaPredictionService {
  static fromDistribution(type: number, pity: number, raw: Object, retrievedAt: number = 0): GachaPrediction {
    const result: GachaPrediction = new GachaPrediction();
    result.poolType = type;
    result.threshold = GachaPoolRules.fiveStarThreshold(type);
    if (result.threshold === 0) { result.message = '该卡池没有适用的有限五星预测模型'; return result; }
    if (!Number.isSafeInteger(pity) || pity < 0 || raw === null || Array.isArray(raw) || typeof raw !== 'object') {
      result.message = '祈愿垫数或经验分布无效'; return result;
    }
    result.pity = Math.min(pity, result.threshold - 1);
    const values: Object | undefined = HutaoCloudJson.field(raw as Record<string, Object>, 'Distribution');
    if (!Array.isArray(values) || values.length === 0 || values.length > result.threshold) { return result; }
    const counts: number[] = new Array<number>(result.threshold).fill(0);
    const seen: Set<number> = new Set<number>();
    const distribution: Object[] = values as Object[];
    for (const value of distribution) {
      if (value === null || typeof value !== 'object' || Array.isArray(value)) { return result; }
      const row: Record<string, Object> = value as Record<string, Object>;
      const pull: Object | undefined = HutaoCloudJson.field(row, 'Pull');
      const count: Object | undefined = HutaoCloudJson.field(row, 'Count');
      if (typeof pull !== 'number' || typeof count !== 'number' || !Number.isSafeInteger(pull) ||
        !Number.isSafeInteger(count) || pull < 1 || pull > result.threshold || count < 0 || seen.has(pull)) { return result; }
      seen.add(pull);
      counts[pull - 1] = count;
      result.sampleEvents += count;
      if (!Number.isSafeInteger(result.sampleEvents)) { return result; }
    }
    for (let index: number = result.pity; index < counts.length; index++) { result.remainingEvents += counts[index]; }
    if (result.remainingEvents <= 0) { result.message = '当前垫数之后没有可用样本'; return result; }
    let maximum: number = -1;
    for (let index: number = result.pity; index < counts.length; index++) {
      const probability: number = counts[index] / result.remainingEvents;
      result.conditional.push(probability);
      if (probability > maximum) {
        maximum = probability;
        result.predictedRemaining = index - result.pity + 1;
        result.predictedProbability = probability;
      }
    }
    result.nextProbability = result.conditional[0];
    result.retrievedAt = retrievedAt;
    result.available = true;
    result.message = '经验分布估计，不是未来结果保证，也不代表指定 UP 概率';
    return result;
  }

  static within(result: GachaPrediction, pulls: number): number {
    if (!result.available || !Number.isSafeInteger(pulls) || pulls <= 0) { return 0; }
    let sum: number = 0;
    for (let index: number = 0; index < Math.min(pulls, result.conditional.length); index++) { sum += result.conditional[index]; }
    return Math.min(1, Math.max(0, sum));
  }

  static async fetch(type: number, pity: number): Promise<GachaPrediction> {
    const kind: string = GachaPoolRules.distributionKind(type);
    if (kind.length === 0) {
      const empty: Record<string, Object> = {};
      return GachaPredictionService.fromDistribution(type, pity, empty);
    }
    try {
      const raw: Object = await HutaoCloudService.getInstance().statistics(kind);
      return GachaPredictionService.fromDistribution(type, pity, raw, Date.now());
    } catch (_) {
      const result: GachaPrediction = new GachaPrediction();
      result.poolType = type;
      result.message = '经验分布不可用，请检查胡桃云会话或服务状态';
      return result;
    }
  }
}
