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
  wishStatistics?: InsightWishStatistics;
  featuredChart?: InsightSeries;
}

export class InsightWishObtain {
  name: string = '';
  date: string = '';
  pulls_for_this_five_star: number = 0;
  is_featured: boolean | null = null;
  is_guaranteed: boolean | null = null;
  pulls_since_previous_featured: number | null = null;
}

export class InsightWishPool {
  pool: string = '';
  total_wishes: number = 0;
  five_star_count: number = 0;
  four_star_count: number = 0;
  five_star_rate_in_observed_wishes: number | null = null;
  average_wishes_per_five_star: number | null = null;
  average_wishes_per_featured_five_star: number | null = null;
  minimum_wishes_per_five_star: number = 0;
  maximum_wishes_per_five_star: number = 0;
  current_wishes_since_last_five_star: number = 0;
  game_guarantee_threshold: number = 0;
  recorded_five_star_obtains: InsightWishObtain[] = [];
}

export class InsightBannerObtain {
  name: string = '';
  recorded_obtain_count: number = 0;
}

export class InsightBanner {
  from: string = '';
  to: string = '';
  featured_five_stars: InsightBannerObtain[] = [];
}

export class InsightWishStatistics {
  origin: string = 'Snap Hutao local wish statistics';
  scope_note: string = 'Use observed rarity and pity only. Partial imports and absent banner metadata limit conclusions.';
  pools: InsightWishPool[] = [];
  recent_banner_featured_characters_and_weapons: InsightBanner[] = [];
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
