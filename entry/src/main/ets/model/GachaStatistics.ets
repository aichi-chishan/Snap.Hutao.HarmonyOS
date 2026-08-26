/**
 * GachaStatistics.ets
 * 分池统计：总抽数、各池数量、出金历史、垫数/水位、五星平均抽数、最非/最欧、每角色用抽数。
 */
import { GachaItem } from './GachaItem';

/** 单个五星角色的抽取统计 */
export class FiveStarDetail {
  name: string = '';
  time: string = '';
  /** 本次出金用了多少抽（自上次五星以来） */
  lastPull: number = 0;
  /** 是否为 UP 角色（占位：角色事件池前 N 名视为 UP，简化处理） */
  isUp: boolean = false;
  /** 角色/武器（图标分类用） */
  itemType: string = '';
}

export class PoolStatistics {
  gachaType: number = 0;
  typeName: string = '';
  totalCount: number = 0;
  fiveStarCount: number = 0;
  fourStarCount: number = 0;
  /** 距上次出金的垫数 */
  sinceLastFive: number = 0;
  /** 距上个四星的垫数 */
  sinceLastFour: number = 0;
  lastFiveName: string = '';
  lastFiveTime: string = '';
  /** 池最早记录日期（yyyy.MM.dd，空表示无记录） */
  startDate: string = '';
  /** 池最新记录日期（yyyy.MM.dd，空表示无记录） */
  endDate: string = '';

  /** 五星平均抽数（总抽数 / 五星数）；无五星为 0 */
  averageOrangePull: number = 0;
  /** 最非（最大出金间隔抽数） */
  maxOrangePull: number = 0;
  /** 最欧（最小出金间隔抽数） */
  minOrangePull: number = 0;
  /** 四星平均抽数 */
  averagePurplePull: number = 0;

  /** 出金历史（倒序）：每条内含 lastPull 每角色用抽数 */
  fiveHistory: GachaItem[] = [];

  /** 五星明细（含每角色抽数/UP 标记） */
  fiveDetails: FiveStarDetail[] = [];

  toString(): string {
    return `pool=${this.typeName} total=${this.totalCount} 5star=${this.fiveStarCount} ` +
      `4star=${this.fourStarCount} since5=${this.sinceLastFive} since4=${this.sinceLastFour} ` +
      `avg5=${this.averageOrangePull} min=${this.minOrangePull} max=${this.maxOrangePull}`;
  }
}

export class GachaStatistics {
  uid: string = '';
  archiveId: number = 0;
  totalPulls: number = 0;
  pools: PoolStatistics[] = [];
}
