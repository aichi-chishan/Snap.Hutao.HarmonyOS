/**
 * AchievementService.ets
 * 成就系统业务层（对齐 Windows AchievementService/AchievementStatisticsService，无云依赖）：
 * - 元数据：本地 rawfile achievement_zh.json（paimon-moe 社区数据集，73 分类 / 1500+ 成就）
 * - 多档案管理、完成记录、UIAF v1.1 导入导出（合并策略：双方皆完成保留原时间戳）
 */
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../common/AppContext';
import { AchievementRepo } from '../data/repo/AchievementRepo';
import {
  AchievementArchive,
  AchievementCategory,
  AchievementEntry,
  AchievementRecord,
  AchievementStats,
  CategoryStats,
} from '../model/AchievementData';
import { Logger } from '../common/Logger';
import { GameDataService, GameDataDomain } from './GameDataService';
import { AppConstants } from '../common/Constants';

const TAG: string = 'AchievementService';
const UIAF_VERSION: string = 'v1.1';

/** UIAF 导入结果 */
export class UiafImportResult {
  fileCount: number = 0;
  mergedDone: number = 0;
  ok: boolean = false;
  message: string = '';
}

/** UIAF v1.1 导出结构（对齐 Windows UIAF/UIAFItem 模型） */
class UiafItem {
  id: number = 0;
  timestamp: number = 0;
  current: number = 1;
  /** 3 = REWARD_TAKEN */
  status: number = 3;
}

class UiafInfo {
  export_app: string = '';
  export_app_version: string = '';
  export_timestamp: number = 0;
  uiaf_version: string = '';
}

class UiafRoot {
  info: UiafInfo = new UiafInfo();
  list: UiafItem[] = [];
}

export class AchievementService {
  private static categories: AchievementCategory[] | undefined = undefined;
  private static idIndex: Map<number, AchievementEntry> = new Map();

  /** 分类图标池（rawfile/icons/AchievementIcon 已有文件；paimon 分类按序循环映射） */
  private static readonly CATEGORY_ICONS: string[] = [
    'UI_AchievementIcon_A001', 'UI_AchievementIcon_A003', 'UI_AchievementIcon_A004',
    'UI_AchievementIcon_A005', 'UI_AchievementIcon_A006', 'UI_AchievementIcon_A008',
    'UI_AchievementIcon_A012', 'UI_AchievementIcon_A013', 'UI_AchievementIcon_A016',
    'UI_AchievementIcon_A019', 'UI_AchievementIcon_A023', 'UI_AchievementIcon_A025',
    'UI_AchievementIcon_A026', 'UI_AchievementIcon_A027', 'UI_AchievementIcon_B002',
    'UI_AchievementIcon_B005', 'UI_AchievementIcon_O001',
  ];

  /** 分类 id → 图标名（未命中回退通用徽章） */
  static categoryIcon(catId: number): string {
    if (catId < 0) {
      return '';
    }
    return AchievementService.CATEGORY_ICONS[catId % AchievementService.CATEGORY_ICONS.length];
  }

  /** 确保存在默认档案（首次进入成就页时创建并选中） */
  static async ensureDefaultArchive(): Promise<AchievementArchive[]> {
    let archives: AchievementArchive[] = await AchievementRepo.getAllArchives();
    if (archives.length === 0) {
      const created: AchievementArchive = await AchievementRepo.createArchive('默认档案');
      await AchievementRepo.selectArchive(created.id);
      created.isSelected = true;
      archives = [created];
    }
    return archives;
  }

  /** 元数据分类列表（官方包优先 → 远端 paimon 遗留 → rawfile paimon 兜底；进程内缓存一次） */
  static async getCategories(): Promise<AchievementCategory[]> {
    if (AchievementService.categories !== undefined) {
      return AchievementService.categories;
    }
    // 1) 官方元数据（rawfile/metadata，对齐 Snap.Metadata：1844 条 > paimon-moe 社区集 1548 条）
    try {
      const rm = AppContextProvider.getResourceManager();
      const achRaw: Uint8Array = await rm.getRawFileContent('metadata/Achievement.json');
      const goalRaw: Uint8Array = await rm.getRawFileContent('metadata/AchievementGoal.json');
      AchievementService.parseOfficialMetadata(
        util.TextDecoder.create('utf-8').decodeToString(achRaw),
        util.TextDecoder.create('utf-8').decodeToString(goalRaw));
      if ((AchievementService.idIndex?.size ?? 0) > 0) {
        return AchievementService.categories ?? [];
      }
      AchievementService.categories = undefined;
    } catch (e) {
      Logger.warn(TAG, `official achievement meta fail: ${JSON.stringify(e)}`);
    }
    // 2) 远端更新版（GitHub 数据源，paimon 遗留格式；官方包缺失时兜底）
    try {
      const remoteText: string = await GameDataService.getInstance().readText(GameDataDomain.Achievement);
      if (remoteText.length > 0) {
        AchievementService.parseMetadata(remoteText);
        return AchievementService.categories ?? [];
      }
    } catch (e) {
      Logger.warn(TAG, `remote achievement meta fail: ${JSON.stringify(e)}`);
    }
    // 3) rawfile 内置 paimon 版（最后兜底）
    try {
      const rm = AppContextProvider.getResourceManager();
      const raw: Uint8Array = await rm.getRawFileContent('achievement_zh.json');
      const text: string = util.TextDecoder.create('utf-8').decodeToString(raw);
      AchievementService.parseMetadata(text);
    } catch (e) {
      Logger.warn(TAG, `load metadata fail: ${JSON.stringify(e)}`);
      AchievementService.categories = [];
    }
    return AchievementService.categories ?? [];
  }

  /**
   * 解析官方元数据（对齐 Snap.Metadata Achievement.json + AchievementGoal.json）：
   * 分类=Goal（含官方图标名），条目按 Goal 归类、PreviousId 链聚合多阶段组（如"动物园大亨"三阶段）。
   */
  private static parseOfficialMetadata(achText: string, goalText: string): void {
    const goals: Record<string, Object>[] = JSON.parse(goalText) as Record<string, Object>[];
    const achs: Record<string, Object>[] = JSON.parse(achText) as Record<string, Object>[];
    // 分类（按 Order 排序）
    const catById: Map<number, AchievementCategory> = new Map<number, AchievementCategory>();
    const sortedGoals: Record<string, Object>[] = goals.slice().sort((a: Record<string, Object>, b: Record<string, Object>) => {
      return Number(a['Order'] ?? 0) - Number(b['Order'] ?? 0);
    });
    for (const g of sortedGoals) {
      const cat: AchievementCategory = new AchievementCategory();
      cat.id = Number(g['Id'] ?? 0);
      cat.name = (g['Name'] as string) ?? '';
      cat.icon = (g['Icon'] as string) ?? '';
      catById.set(cat.id, cat);
    }
    // 条目：Goal 归类 + PreviousId 链聚合（0=组首）
    const entryById: Map<number, AchievementEntry> = new Map<number, AchievementEntry>();
    for (const a of achs) {
      const entry: AchievementEntry = new AchievementEntry();
      entry.id = Number(a['Id'] ?? 0);
      entry.name = (a['Title'] as string) ?? '';
      entry.desc = (a['Description'] as string) ?? '';
      entry.reward = Number(a['Reward'] ?? 0);
      entry.ver = (a['Version'] as string) ?? '';
      entry.previousId = Number(a['PreviousId'] ?? 0);
      entry.goalId = Number(a['Goal'] ?? 0);
      entry.order = Number(a['Order'] ?? 0);
      entryById.set(entry.id, entry);
    }
    for (const entry of entryById.values()) {
      const cat: AchievementCategory | undefined = catById.get(entry.goalId);
      if (cat === undefined) {
        continue;
      }
      const prev: AchievementEntry | undefined = entry.previousId > 0
        ? entryById.get(entry.previousId)
        : undefined;
      if (prev !== undefined) {
        entry.groupKey = prev.groupKey;
        entry.stageIndex = prev.stageIndex + 1;
        entry.groupOrder = prev.groupOrder;
      } else {
        entry.groupKey = `${entry.goalId}_${entry.id}`;
        entry.stageIndex = 0;
        entry.groupOrder = entry.order;
      }
      cat.entries.push(entry);
    }
    const list: AchievementCategory[] = [];
    const index: Map<number, AchievementEntry> = new Map<number, AchievementEntry>();
    catById.forEach((cat: AchievementCategory) => {
      // 组间按组首 Order，组内按阶段序
      cat.entries.sort((a: AchievementEntry, b: AchievementEntry) => {
        if (a.groupOrder !== b.groupOrder) {
          return a.groupOrder - b.groupOrder;
        }
        if (a.groupKey !== b.groupKey) {
          return a.order - b.order;
        }
        return a.stageIndex - b.stageIndex;
      });
      list.push(cat);
      for (const e of cat.entries) {
        if (e.id > 0) {
          index.set(e.id, e);
        }
      }
    });
    AchievementService.categories = list;
    AchievementService.idIndex = index;
    Logger.info(TAG, `official metadata loaded: ${list.length} categories, ${index.size} entries`);
  }

  /** 解析元数据 JSON：{ "<分类id>": { name, achievements: [ 单对象 | 对象数组(多阶段) ] } } */
  private static parseMetadata(text: string): void {
    const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    const list: AchievementCategory[] = [];
    const index: Map<number, AchievementEntry> = new Map();
    const keys: string[] = Object.keys(root).sort((a: string, b: string) => Number(a) - Number(b));
    for (const key of keys) {
      const catObj: Record<string, Object> = root[key] as Record<string, Object>;
      const cat: AchievementCategory = new AchievementCategory();
      cat.id = Number(key);
      cat.name = (catObj['name'] as string) ?? '';
      cat.icon = AchievementService.categoryIcon(cat.id);
      const rawEntries: Object[] = (catObj['achievements'] as Object[]) ?? [];
      let groupSeq: number = 0;
      for (const raw of rawEntries) {
        // 元素可为单对象（含 id 键）或数组（多阶段组，元素才含 id）
        const probe: Record<string, Object> = raw as Record<string, Object>;
        const stages: Record<string, Object>[] = probe['id'] !== undefined
          ? [probe]
          : raw as Record<string, Object>[];
        const groupKey: string = `${cat.id}_${groupSeq}`;
        groupSeq += 1;
        let stageIdx: number = 0;
        for (const st of stages) {
          const entry: AchievementEntry = new AchievementEntry();
          entry.id = Number(st['id'] ?? 0);
          entry.name = (st['name'] as string) ?? '';
          entry.desc = (st['desc'] as string) ?? '';
          entry.reward = Number(st['reward'] ?? 0);
          entry.ver = (st['ver'] as string) ?? '';
          entry.groupKey = groupKey;
          entry.stageIndex = stageIdx;
          stageIdx += 1;
          cat.entries.push(entry);
          if (entry.id > 0) {
            index.set(entry.id, entry);
          }
        }
      }
      list.push(cat);
    }
    AchievementService.categories = list;
    AchievementService.idIndex = index;
    Logger.info(TAG, `metadata loaded: ${list.length} categories, ${index.size} entries`);
  }

  /** 完成度统计（总览） */
  static async getOverallStats(archiveId: number): Promise<AchievementStats> {
    const cats: AchievementCategory[] = await AchievementService.getCategories();
    const records: Map<number, AchievementRecord> = await AchievementRepo.getRecords(archiveId);
    const stats: AchievementStats = new AchievementStats();
    for (const cat of cats) {
      for (const e of cat.entries) {
        stats.total += 1;
        stats.primogemsTotal += e.reward;
        if (records.has(e.id)) {
          stats.done += 1;
          stats.primogemsEarned += e.reward;
        }
      }
    }
    return stats;
  }

  /** 分类维度统计 */
  static async getCategoryStats(archiveId: number): Promise<CategoryStats[]> {
    const cats: AchievementCategory[] = await AchievementService.getCategories();
    const records: Map<number, AchievementRecord> = await AchievementRepo.getRecords(archiveId);
    const list: CategoryStats[] = [];
    for (const cat of cats) {
      const cs: CategoryStats = new CategoryStats();
      cs.category = cat;
      for (const e of cat.entries) {
        cs.stats.total += 1;
        cs.stats.primogemsTotal += e.reward;
        if (records.has(e.id)) {
          cs.stats.done += 1;
          cs.stats.primogemsEarned += e.reward;
        }
      }
      list.push(cs);
    }
    return list;
  }

  /** 手动切换完成状态 */
  static async toggle(archiveId: number, achId: number): Promise<boolean> {
    const records: Map<number, AchievementRecord> = await AchievementRepo.getRecords(archiveId);
    const done: boolean = !records.has(achId);
    await AchievementRepo.setRecord(archiveId, achId, done, Math.floor(Date.now() / 1000));
    return done;
  }

  /** UIAF v1.1 导出（JSON 字符串） */
  static async exportUiaf(archiveId: number): Promise<string> {
    const records: Map<number, AchievementRecord> = await AchievementRepo.getRecords(archiveId);
    const list: UiafItem[] = [];
    const ids: number[] = Array.from(records.keys()).sort((a: number, b: number) => a - b);
    for (const id of ids) {
      const r: AchievementRecord | undefined = records.get(id);
      const item: UiafItem = new UiafItem();
      item.id = id;
      item.timestamp = r !== undefined ? r.timestamp : 0;
      item.current = 1;
      item.status = 3;
      list.push(item);
    }
    const info: UiafInfo = new UiafInfo();
    info.export_app = 'Snap.Hutao.HarmonyOS';
    info.export_app_version = AppConstants.APP_VERSION;
    info.export_timestamp = Math.floor(Date.now() / 1000);
    info.uiaf_version = UIAF_VERSION;
    const root: UiafRoot = new UiafRoot();
    root.info = info;
    root.list = list;
    Logger.info(TAG, `export uiaf: ${list.length} entries`);
    return JSON.stringify(root, null, 2);
  }

  /** UIAF v1.1 导入（合并策略：并集；完成优先；同完成保留原时间戳） */
  static async importUiaf(archiveId: number, text: string): Promise<UiafImportResult> {
    const result: UiafImportResult = new UiafImportResult();
    let root: Record<string, Object>;
    try {
      root = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      result.message = 'JSON 解析失败';
      return result;
    }
    const rawList: Object[] = (root['list'] as Object[]) ?? [];
    if (rawList.length === 0) {
      result.message = '文件中没有成就记录（list 为空）';
      return result;
    }
    const existing: Map<number, AchievementRecord> = await AchievementRepo.getRecords(archiveId);
    const merged: Map<number, AchievementRecord> = new Map(existing);
    let fileCount: number = 0;
    for (const rawItem of rawList) {
      const item: Record<string, Object> = rawItem as Record<string, Object>;
      const id: number = Number(item['id'] ?? 0);
      if (id <= 0) {
        continue;
      }
      fileCount += 1;
      const status: number = Number(item['status'] ?? 0);
      const current: number = Number(item['current'] ?? 0);
      // status: 2=FINISHED 3=REWARD_TAKEN（对齐 Windows AchievementStatus）
      const done: boolean = status >= 2 || current >= 1;
      if (!done) {
        continue;
      }
      let ts: number = Number(item['timestamp'] ?? 0);
      if (ts > 1e12) {
        ts = Math.floor(ts / 1000);
      }
      const prev: AchievementRecord | undefined = merged.get(id);
      const rec: AchievementRecord = new AchievementRecord();
      rec.archiveId = archiveId;
      rec.achId = id;
      rec.current = 1;
      rec.timestamp = prev !== undefined && prev.timestamp > 0 ? prev.timestamp : ts;
      merged.set(id, rec);
    }
    const records: AchievementRecord[] = Array.from(merged.values());
    await AchievementRepo.replaceRecords(archiveId, records);
    result.ok = true;
    result.fileCount = fileCount;
    result.mergedDone = records.length;
    result.message = `导入成功：${records.length} 项完成`;
    Logger.info(TAG, `import uiaf: file=${fileCount} mergedDone=${records.length}`);
    return result;
  }
}
