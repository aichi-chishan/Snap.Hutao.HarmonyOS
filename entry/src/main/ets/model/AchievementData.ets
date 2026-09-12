/**
 * AchievementData.ets
 * 成就系统数据模型（对齐 Windows 版成就页 + UIAF v1.1 互通格式）。
 * 元数据：官方 Snap.Metadata（metadata/Achievement.json + AchievementGoal.json，1844 条）；
 * paimon-moe 社区数据集（achievement_zh.json）仅作缺失兜底。
 */

/** 单条成就元数据 */
export class AchievementEntry {
  id: number = 0;
  name: string = '';
  desc: string = '';
  /** 原石奖励 */
  reward: number = 0;
  /** 加入版本 */
  ver: string = '';
  /** 多阶段组标识（同组阶段共享名字，如"动物园大亨"1/30/300 只） */
  groupKey: string = '';
  /** 组内阶段序号（0 起） */
  stageIndex: number = 0;
  /** 官方元数据：前一阶段 id（0=组首，用于 PreviousId 链聚合） */
  previousId: number = 0;
  /** 官方元数据：所属分类 Goal */
  goalId: number = 0;
  /** 官方元数据：条目顺序 */
  order: number = 0;
  /** 组首条目顺序（组间排序用） */
  groupOrder: number = 0;
}

/** 成就分类 */
export class AchievementCategory {
  id: number = 0;
  name: string = '';
  /** 分类图标名（UI_AchievementIcon_*；paimon 分类按顺序映射到已有图标池） */
  icon: string = '';
  entries: AchievementEntry[] = [];
}

/** 成就档案（多存档） */
export class AchievementArchive {
  id: number = 0;
  name: string = '';
  createdAt: number = 0;
  isSelected: boolean = false;
}

/** 档案内完成记录（DB 行） */
export class AchievementRecord {
  archiveId: number = 0;
  achId: number = 0;
  /** 1=已完成 */
  current: number = 1;
  /** 完成时间戳（秒） */
  timestamp: number = 0;
}

/** UIAF v1.1 导出根对象 */
export class UiafExportRoot {
  info: Record<string, Object> = {};
  list: AchievementRecord[] = [];
}

/** 成就完成度统计 */
export class AchievementStats {
  total: number = 0;
  done: number = 0;
  /** 已获原石 */
  primogemsEarned: number = 0;
  /** 全部完成可得原石 */
  primogemsTotal: number = 0;

  percent(): number {
    return this.total > 0 ? Math.round((this.done / this.total) * 1000) / 10 : 0;
  }
}

/** 分类完成度（分类维度统计行） */
export class CategoryStats {
  category: AchievementCategory = new AchievementCategory();
  stats: AchievementStats = new AchievementStats();
}
