/**
 * AccountInsights.ets
 * 账号洞察（对齐 Windows Service/AccountInsights/InsightModels）：
 * 把祈愿/颂愿/深境螺旋/幻想真境剧诗/幽境危战的历史数据聚合成逐期序列，
 * 供图表展示与 AI 分析（匿名 JSON，不含 UID 与个人标识）。
 */

export enum InsightDirection {
  Neutral = 0,
  HigherIsBetter = 1,
  LowerIsBetter = 2
}

/** 单个数据点：period=期间标签（yyyy-MM / yyyy-MM-dd / 池名），value=数值 */
export class InsightPoint {
  period: string = '';
  value: number = 0;

  constructor(period: string, value: number) {
    this.period = period;
    this.value = value;
  }
}

/** 一条序列（时间序列或分类分布） */
export class InsightSeries {
  title: string = '';
  metric: string = '';
  unit: string = '';
  points: InsightPoint[] = [];
  direction: InsightDirection = InsightDirection.Neutral;
  isTimeSeries: boolean = true;
  /** 幽境危战按难度分系列时的难度等级 */
  difficulty: number | null = null;

  constructor(title: string, metric: string, unit: string, points: InsightPoint[],
    direction: InsightDirection, isTimeSeries: boolean = true, difficulty: number | null = null) {
    this.title = title;
    this.metric = metric;
    this.unit = unit;
    this.points = points;
    this.direction = direction;
    this.isTimeSeries = isTimeSeries;
    this.difficulty = difficulty;
  }
}

/** 聚合结果（失败的数据源显式列出，不静默吞掉） */
export class InsightBundle {
  series: InsightSeries[] = [];
  failedSources: string[] = [];
}

/** 序列摘要（对齐 Windows CreateAnonymousJson 的 summary 块） */
export class InsightSeriesSummary {
  recordedPeriodCount: number = 0;
  latest: number | null = null;
  minimum: number | null = null;
  maximum: number | null = null;
  average: number | null = null;
  latestChangeFromPrevious: number | null = null;
}
