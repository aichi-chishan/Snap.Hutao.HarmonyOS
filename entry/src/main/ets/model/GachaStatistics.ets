/**
 * GachaStatistics.ets
 * 分池统计：总抽数、各池数量、出金历史、垫数/水位、五星平均抽数、最非/最欧、每角色用抽数。
 */
import { GachaItem } from './GachaItem';

/** 统计卡的一条抽取记录，间隔从上次同星级开始计算。 */
export class WishSummaryItem {
  gachaId: string;
  itemId: number;
  name: string;
  time: string;
  itemType: string;
  rankType: number;
  lastPull: number;
  isUp: boolean = false;
  upKnown: boolean = false;
  isGuarantee: boolean = false;

  constructor(item: GachaItem, lastPull: number) {
    this.gachaId = item.gachaId;
    this.itemId = item.itemId;
    this.name = item.name;
    this.time = item.time;
    this.itemType = item.itemType;
    this.rankType = item.rankType;
    this.lastPull = lastPull;
  }
}

export class FiveStarDetail extends WishSummaryItem {
  totalCyclePull: number = 0;
}

export class PoolStatistics {
  gachaType: number = 0;
  typeName: string = '';
  totalCount: number = 0;
  fiveStarCount: number = 0;
  fourStarCount: number = 0;
  threeStarCount: number = 0;
  get otherStarCount(): number { return this.totalCount - this.fiveStarCount - this.fourStarCount - this.threeStarCount; }
  /** 本地记录中距上次五星的抽数。 */
  sinceLastFive: number = 0;
  /** 本地记录中距上次四星的抽数。 */
  sinceLastFour: number = 0;
  sinceLastThree: number = 0;
  lastFiveName: string = '';
  lastFiveTime: string = '';
  /** 池最早记录日期（yyyy.MM.dd，空表示无记录） */
  startDate: string = '';
  /** 池最新记录日期（yyyy.MM.dd，空表示无记录） */
  endDate: string = '';

  /** 完整五星间隔的平均抽数。 */
  averageOrangePull: number = 0;
  /** 完整 UP 五星间隔的平均抽数。 */
  averageUpOrangePull: number = 0;
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

  /** 五星及卡池模板需要的四星、三星记录，最新记录在前。 */
  summaryItems: WishSummaryItem[] = [];

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
  avatars: GachaItemCount[] = [];
  weapons: GachaItemCount[] = [];
}

/** 当前归档全部常规池的物品计数，不受当前查看的池影响。 */
export class GachaItemCount {
  itemId: number = 0;
  name: string = '';
  icon: string = '';
  itemType: string = '';
  rankType: number = 0;
  count: number = 0;
}
