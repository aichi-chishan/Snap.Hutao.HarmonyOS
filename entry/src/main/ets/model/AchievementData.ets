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
  /** 官方 IsDailyQuest 或社区明确 commissions 标签；不从标题/描述猜测。 */
  isDailyQuest: boolean = false;
  dailyQuestKnown: boolean = false;
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

/** 档案内成就记录（保留未完成进度，不能用是否有记录判断完成） */
export class AchievementRecord {
  archiveId: number = 0;
  achId: number = 0;
  /** 实际进度，如 30/40 的 30；0 也可能是已完成但进度未知 */
  current: number = 0;
  /** UIAF: 0=无效、1=未完成、2=已完成、3=奖励已领取 */
  status: number = 1;
  /** 完成时间戳（秒） */
  timestamp: number = 0;

  static isDone(record: AchievementRecord | undefined): boolean {
    return record !== undefined && record.status >= 2;
  }
}

/** 对齐 Windows ImportStrategy：Lazy 保留已有项；Aggressive 更新同 ID；Overwrite 替换全部。 */
export enum UiafImportStrategy {
  Lazy = 0,
  Aggressive = 1,
  Overwrite = 2,
}

export class UiafItem {
  id: number = 0;
  timestamp: number = 0;
  current: number = 0;
  status: number = 1;
}

export class UiafInfo {
  export_app: string = '';
  export_app_version: string = '';
  export_timestamp: number = 0;
  uiaf_version: string = 'v1.1';
}

export class UiafExportRoot {
  info: UiafInfo = new UiafInfo();
  list: UiafItem[] = [];
}

/** 无平台依赖的 UIAF 编解码，完整验证后才允许写入数据库。 */
export class UiafCodec {
  private static object(value: Object, label: string): Record<string, Object> {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error(`${label} 必须是对象`);
    }
    return value as Record<string, Object>;
  }

  private static integer(value: Object, label: string, min: number, max: number): number {
    if (typeof value !== 'number' || !Number.isSafeInteger(value as number)
      || (value as number) < min || (value as number) > max) {
      throw new Error(`${label} 必须是 ${min} 到 ${max} 之间的整数`);
    }
    return value as number;
  }

  static parse(text: string, archiveId: number): AchievementRecord[] {
    const root: Record<string, Object> = UiafCodec.object(JSON.parse(text) as Object, 'UIAF');
    const info: Record<string, Object> = UiafCodec.object(root['info'], 'info');
    if (info['uiaf_version'] !== 'v1.1') {
      throw new Error('仅支持 UIAF v1.1，请先转换文件版本');
    }
    if (typeof info['export_app'] !== 'string') {
      throw new Error('info.export_app 必须是字符串');
    }
    if (info['export_app_version'] !== undefined && typeof info['export_app_version'] !== 'string') {
      throw new Error('info.export_app_version 必须是字符串');
    }
    if (info['export_timestamp'] !== undefined) {
      UiafCodec.integer(info['export_timestamp'], 'info.export_timestamp', 0, 253402300799);
    }
    if (!Array.isArray(root['list'])) {
      throw new Error('list 必须是数组');
    }
    const rawList: Object[] = root['list'] as Object[];
    const records: AchievementRecord[] = [];
    const ids: Set<number> = new Set<number>();
    for (let i: number = 0; i < rawList.length; i++) {
      const label: string = `list[${i}]`;
      const item: Record<string, Object> = UiafCodec.object(rawList[i], label);
      const record: AchievementRecord = new AchievementRecord();
      record.archiveId = archiveId;
      record.achId = UiafCodec.integer(item['id'], `${label}.id`, 1, 4294967295);
      record.current = UiafCodec.integer(item['current'], `${label}.current`, 0, 4294967295);
      record.status = UiafCodec.integer(item['status'], `${label}.status`, 0, 3);
      // 保留秒级值及未知时间哨兵；毫秒时间不再猜测性转换，避免改写原始数据。
      record.timestamp = UiafCodec.integer(item['timestamp'], `${label}.timestamp`, -62135596800, 253402300799);
      if (ids.has(record.achId)) {
        throw new Error(`文件包含重复成就 ID：${record.achId}`);
      }
      ids.add(record.achId);
      records.push(record);
    }
    return records;
  }

  static merge(existing: Map<number, AchievementRecord>, incoming: AchievementRecord[],
    strategy: UiafImportStrategy = UiafImportStrategy.Lazy): AchievementRecord[] {
    if (strategy !== UiafImportStrategy.Lazy && strategy !== UiafImportStrategy.Aggressive
      && strategy !== UiafImportStrategy.Overwrite) {
      throw new Error('未知导入策略');
    }
    const merged: Map<number, AchievementRecord> = strategy === UiafImportStrategy.Overwrite
      ? new Map<number, AchievementRecord>() : new Map<number, AchievementRecord>(existing);
    for (const record of incoming) {
      if (strategy !== UiafImportStrategy.Lazy || !merged.has(record.achId)) {
        merged.set(record.achId, record);
      }
    }
    return Array.from(merged.values()).sort((a: AchievementRecord, b: AchievementRecord) => a.achId - b.achId);
  }

  static export(records: AchievementRecord[], appVersion: string, timestamp: number): string {
    const root: UiafExportRoot = new UiafExportRoot();
    root.info.export_app = 'Snap.Hutao.HarmonyOS';
    root.info.export_app_version = appVersion;
    root.info.export_timestamp = timestamp;
    const sorted: AchievementRecord[] = records.slice().sort((a: AchievementRecord, b: AchievementRecord) => a.achId - b.achId);
    for (const record of sorted) {
      const item: UiafItem = new UiafItem();
      item.id = record.achId;
      item.current = record.current;
      item.status = record.status;
      item.timestamp = record.timestamp;
      root.list.push(item);
    }
    return JSON.stringify(root, null, 2);
  }
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
