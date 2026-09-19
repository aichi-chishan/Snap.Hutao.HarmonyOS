/**
 * CultivationRepo.ets
 * cultivate_projects / cultivate_entries / cultivate_items 表 CRUD：
 * 养成计划多项目管理、计算结果落库为条目、材料勾选状态（对齐 Windows CultivateProject/Entry/Item）。
 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { CalItem } from '../../model/Calculate';
import { Logger } from '../../common/Logger';

const TAG: string = 'CultivationRepo';

/** 养成项目 */
export class CultivateProject {
  id: number = 0;
  name: string = '';
  createdAt: number = 0;
}

/** 条目内单个材料（含勾选状态） */
export class CultivateEntryItem {
  id: number = 0;
  itemId: number = 0;
  name: string = '';
  icon: string = '';
  count: number = 0;
  finished: boolean = false;
}

/** 养成条目（一个角色/一批培养目标 + 其材料清单） */
export class CultivateEntry {
  id: number = 0;
  projectId: number = 0;
  avatarId: number = 0;
  name: string = '';
  icon: string = '';
  level: number = 0;
  targetLevel: number = 0;
  items: CultivateEntryItem[] = [];

  /** 已备齐材料数 */
  finishedCount(): number {
    let n: number = 0;
    for (const it of this.items) {
      if (it.finished) {
        n++;
      }
    }
    return n;
  }
}

export class CultivationRepo {
  // ================= 项目 =================

  static async getProjects(): Promise<CultivateProject[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_projects');
    pred.orderByAsc('id');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const list: CultivateProject[] = [];
    try {
      while (rs.goToNextRow()) {
        const p: CultivateProject = new CultivateProject();
        p.id = rs.getLong(rs.getColumnIndex('id'));
        p.name = rs.getString(rs.getColumnIndex('name'));
        p.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
        list.push(p);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  static async createProject(name: string): Promise<CultivateProject> {
    const values: relationalStore.ValuesBucket = {
      'name': name,
      'created_at': Date.now(),
    };
    const id: number = await RelationalStoreHelper.insert('cultivate_projects', values);
    const p: CultivateProject = new CultivateProject();
    p.id = id;
    p.name = name;
    p.createdAt = Date.now();
    Logger.info(TAG, `created project ${id}:${name}`);
    return p;
  }

  /** 删除项目（级联条目与材料） */
  static async deleteProject(id: number): Promise<void> {
    const entryPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_entries');
    entryPred.equalTo('project_id', id);
    await RelationalStoreHelper.delete('cultivate_entries', entryPred);
    // 条目已删，孤儿材料一并清理
    const orphan: string =
      `DELETE FROM cultivate_items WHERE entry_id NOT IN (SELECT id FROM cultivate_entries)`;
    await RelationalStoreHelper.executeSql(orphan);
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_projects');
    pred.equalTo('id', id);
    await RelationalStoreHelper.delete('cultivate_projects', pred);
  }

  // ================= 条目 =================

  /** 项目内条目（含材料清单） */
  static async getEntries(projectId: number): Promise<CultivateEntry[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_entries');
    pred.equalTo('project_id', projectId);
    pred.orderByDesc('created_at');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const entries: CultivateEntry[] = [];
    try {
      while (rs.goToNextRow()) {
        const e: CultivateEntry = new CultivateEntry();
        e.id = rs.getLong(rs.getColumnIndex('id'));
        e.projectId = rs.getLong(rs.getColumnIndex('project_id'));
        e.avatarId = rs.getLong(rs.getColumnIndex('avatar_id'));
        e.name = rs.getString(rs.getColumnIndex('name'));
        e.icon = rs.getString(rs.getColumnIndex('icon'));
        e.level = rs.getLong(rs.getColumnIndex('level'));
        e.targetLevel = rs.getLong(rs.getColumnIndex('target_level'));
        entries.push(e);
      }
    } finally {
      rs.close();
    }
    // 材料按条目批量取（避免 N+1：一次全量查项目下条目 id 集合内材料）
    const idSet: Set<number> = new Set<number>();
    for (const e of entries) {
      idSet.add(e.id);
    }
    const all: Map<number, CultivateEntryItem[]> = await CultivationRepo.itemsOfEntries(entries);
    for (const e of entries) {
      e.items = all.get(e.id) ?? [];
    }
    return entries;
  }

  private static async itemsOfEntries(entries: CultivateEntry[]): Promise<Map<number, CultivateEntryItem[]>> {
    const map: Map<number, CultivateEntryItem[]> = new Map<number, CultivateEntryItem[]>();
    if (entries.length === 0) {
      return map;
    }
    // 无 IN 查询封装：按条目逐条查询（条目数量通常个位数，可接受）
    for (const e of entries) {
      const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_items');
      pred.equalTo('entry_id', e.id);
      pred.orderByAsc('id');
      const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
      const list: CultivateEntryItem[] = [];
      try {
        while (rs.goToNextRow()) {
          const it: CultivateEntryItem = new CultivateEntryItem();
          it.id = rs.getLong(rs.getColumnIndex('id'));
          it.itemId = rs.getLong(rs.getColumnIndex('item_id'));
          it.name = rs.getString(rs.getColumnIndex('name'));
          it.icon = rs.getString(rs.getColumnIndex('icon'));
          it.count = rs.getLong(rs.getColumnIndex('count'));
          it.finished = rs.getLong(rs.getColumnIndex('finished')) === 1;
          list.push(it);
        }
      } finally {
        rs.close();
      }
      map.set(e.id, list);
    }
    return map;
  }

  /**
   * 新增条目（一次培养目标 + 其材料清单）。
   * 同名材料合并数量（avatar/skill/weapon consume 中会重复出现同类素材）。
   */
  static async addEntry(projectId: number, avatarId: number, name: string, icon: string,
    level: number, targetLevel: number, items: CalItem[]): Promise<number> {
    const entryValues: relationalStore.ValuesBucket = {
      'project_id': projectId,
      'avatar_id': avatarId,
      'name': name,
      'icon': icon,
      'level': level,
      'target_level': targetLevel,
      'created_at': Date.now(),
    };
    const entryId: number = await RelationalStoreHelper.insert('cultivate_entries', entryValues);
    // 同名合并
    const merged: Map<string, CalItem> = new Map<string, CalItem>();
    for (const it of items) {
      const key: string = it.id > 0 ? String(it.id) : it.name;
      const exist: CalItem | undefined = merged.get(key);
      if (exist === undefined) {
        merged.set(key, it);
      } else {
        exist.num += it.num;
      }
    }
    merged.forEach((it: CalItem) => {
      const values: relationalStore.ValuesBucket = {
        'entry_id': entryId,
        'item_id': it.id,
        'name': it.name,
        'icon': it.icon,
        'count': it.num,
        'finished': 0,
      };
      RelationalStoreHelper.insert('cultivate_items', values).catch((e: Error) => {
        Logger.warn(TAG, `insert item fail ${e.message}`);
      });
    });
    Logger.info(TAG, `entry ${entryId} saved with ${merged.size} items`);
    return entryId;
  }

  static async removeEntry(entryId: number): Promise<void> {
    const itemPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_items');
    itemPred.equalTo('entry_id', entryId);
    await RelationalStoreHelper.delete('cultivate_items', itemPred);
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_entries');
    pred.equalTo('id', entryId);
    await RelationalStoreHelper.delete('cultivate_entries', pred);
  }

  /** 材料勾选状态切换 */
  static async toggleItem(itemId: number, finished: boolean): Promise<void> {
    const values: relationalStore.ValuesBucket = { 'finished': finished ? 1 : 0 };
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_items');
    pred.equalTo('id', itemId);
    await RelationalStoreHelper.update('cultivate_items', values, pred);
  }
}
