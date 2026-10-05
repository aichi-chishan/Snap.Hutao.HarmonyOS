/**
 * CultivationRepo.ets
 * cultivate_projects / cultivate_entries / cultivate_items 表 CRUD：
 * 养成计划多项目管理、计算结果落库为条目、材料勾选状态（对齐 Windows CultivateProject/Entry/Item）。
 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { CalItem } from '../../model/Calculate';
import { CultivationDraft } from '../../model/CultivationDraft';
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
  inputJson: string = '';

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

export class CultivationPreparedEntry {
  draft: CultivationDraft = new CultivationDraft();
  items: CalItem[] = [];
}

export class CultivationSaveReport {
  added: number = 0;
  updated: number = 0;
  skipped: number = 0;
  details: string[] = [];
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
        e.inputJson = rs.getString(rs.getColumnIndex('input_json'));
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
    // 先合并到新对象，避免重复保存时改写原始计算结果；同步事务防止半条计划。
    const merged: Map<string, CalItem> = new Map<string, CalItem>();
    for (const it of items) {
      if (it.num <= 0) {
        continue;
      }
      const key: string = it.id > 0 ? String(it.id) : it.name;
      let target: CalItem | undefined = merged.get(key);
      if (target === undefined) {
        target = new CalItem();
        target.id = it.id;
        target.name = it.name;
        target.icon = it.icon;
        merged.set(key, target);
      }
      target.num += it.num;
    }
    if (merged.size === 0) {
      throw new Error('没有需要培养的材料；未创建空计划条目');
    }
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      const entryId: number = store.insertSync('cultivate_entries', entryValues);
      if (entryId <= 0) { throw new Error('条目写入未完成，已撤销本次保存'); }
      const rows: relationalStore.ValuesBucket[] = [];
      for (const it of merged.values()) {
        const values: relationalStore.ValuesBucket = {
          'entry_id': entryId,
          'item_id': it.id,
          'name': it.name,
          'icon': it.icon,
          'count': it.num,
          'finished': 0
        };
        rows.push(values);
      }
      const inserted: number = store.batchInsertSync('cultivate_items', rows);
      if (inserted !== rows.length) {
        throw new Error('材料写入不完整，已撤销本次保存');
      }
      store.commit();
      return entryId;
    } catch (e) {
      store.rollBack();
      throw new Error(e instanceof Error ? e.message : '保存养成计划失败');
    }
  }

  /** All input/result pairs commit together. Skip/overwrite is explicit; failed batches write nothing. */
  static async saveDrafts(projectId: number, prepared: CultivationPreparedEntry[],
    overwrite: boolean): Promise<CultivationSaveReport> {
    if (prepared.length === 0) { throw new Error('没有可保存的培养目标'); }
    const encoded: string[] = prepared.map((entry: CultivationPreparedEntry): string => CultivationDraft.encode(entry.draft));
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    const report: CultivationSaveReport = new CultivationSaveReport();
    store.beginTransaction();
    try {
      let targetProject: number = projectId;
      if (targetProject === 0) {
        targetProject = store.insertSync('cultivate_projects', { 'name': '默认养成计划', 'created_at': Date.now() });
        if (targetProject <= 0) { throw new Error('项目写入未完成，已撤销本次保存'); }
      }
      const projectPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_projects');
      projectPred.equalTo('id', targetProject);
      const projectRows: relationalStore.ResultSet = store.querySync(projectPred);
      let exists: boolean = false;
      try { exists = projectRows.goToFirstRow(); } finally { projectRows.close(); }
      if (!exists) { throw new Error('计划已被删除，请重新选择项目'); }
      for (let index: number = 0; index < prepared.length; index++) {
        const entry: CultivationPreparedEntry = prepared[index];
        const draft: CultivationDraft = entry.draft;
        const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_entries');
        pred.equalTo('project_id', targetProject);
        if (draft.entryId > 0) { pred.equalTo('id', draft.entryId); }
        else { pred.equalTo('avatar_id', draft.itemId); }
        const existing: relationalStore.ResultSet = store.querySync(pred);
        let entryId: number = 0;
        let input: string = '';
        try {
          if (existing.goToFirstRow()) {
            entryId = existing.getLong(existing.getColumnIndex('id'));
            input = existing.getString(existing.getColumnIndex('input_json'));
          }
        } finally { existing.close(); }
        if (draft.entryId > 0 && (entryId !== draft.entryId || input !== draft.expectedInput)) {
          throw new Error(`${draft.name} 的计划已变更，请关闭编辑后重新打开`);
        }
        if (entryId > 0 && draft.entryId === 0 && !overwrite) {
          report.skipped++; report.details.push(`${draft.name}：已存在，跳过`); continue;
        }
        const merged: Map<number, CalItem> = new Map<number, CalItem>();
        for (const item of entry.items) {
          if (!Number.isSafeInteger(item.id) || item.id <= 0 || !Number.isSafeInteger(item.num) || item.num < 0) {
            throw new Error(`${draft.name} 的材料结果无效，已撤销本次保存`);
          }
          if (item.num === 0) { continue; }
          const value: CalItem = merged.get(item.id) ?? new CalItem();
          value.id = item.id; value.name = item.name; value.icon = item.icon; value.num += item.num;
          if (!Number.isSafeInteger(value.num)) { throw new Error('材料数量超出安全范围，已撤销本次保存'); }
          merged.set(item.id, value);
        }
        if (merged.size === 0 && entryId === 0) {
          report.skipped++; report.details.push(`${draft.name}：已达目标，无新增材料`); continue;
        }
        const finished: Map<number, number> = new Map<number, number>();
        if (entryId > 0) {
          const itemPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_items');
          itemPred.equalTo('entry_id', entryId);
          const rows: relationalStore.ResultSet = store.querySync(itemPred);
          let itemCount: number = 0;
          try {
            while (rows.goToNextRow()) {
              itemCount++;
              if (rows.getLong(rows.getColumnIndex('finished')) === 1) {
                finished.set(rows.getLong(rows.getColumnIndex('item_id')), rows.getLong(rows.getColumnIndex('count')));
              }
            }
          } finally { rows.close(); }
          if (store.deleteSync(itemPred) !== itemCount) { throw new Error('旧材料更新未完成，已撤销本次保存'); }
        }
        const values: relationalStore.ValuesBucket = {
          'project_id': targetProject, 'avatar_id': draft.itemId, 'name': draft.name, 'icon': draft.icon,
          'level': draft.current, 'target_level': draft.target, 'input_json': encoded[index]
        };
        if (entryId > 0) {
          const updatePred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_entries');
          updatePred.equalTo('id', entryId);
          if (store.updateSync(values, updatePred) !== 1) { throw new Error('计划更新未完成'); }
          report.updated++; report.details.push(`${draft.name}：已更新`);
        } else {
          values['created_at'] = Date.now();
          entryId = store.insertSync('cultivate_entries', values);
          if (entryId <= 0) { throw new Error('条目写入未完成，已撤销本次保存'); }
          report.added++; report.details.push(`${draft.name}：已新增`);
        }
        for (const item of merged.values()) {
          const itemRowId: number = store.insertSync('cultivate_items', {
            'entry_id': entryId, 'item_id': item.id, 'name': item.name, 'icon': item.icon,
            'count': item.num, 'finished': finished.get(item.id) === item.num ? 1 : 0
          });
          if (itemRowId <= 0) { throw new Error('材料写入未完成，已撤销本次保存'); }
        }
      }
      store.commit();
      return report;
    } catch (e) {
      store.rollBack();
      throw new Error(e instanceof Error ? e.message : '保存失败，原计划保持不变');
    }
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
