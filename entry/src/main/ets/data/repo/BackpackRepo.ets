import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { BackpackArchive, BackpackItem, BackpackImport } from '../../model/BackpackData';
import { UIIFCodec as UIIFService } from '../../model/UIIFCodec';

/** A whole snapshot is validated before a write. All mutating transactions are synchronous. */
export class BackpackRepo {
  private static id(id: number): void {
    if (!Number.isSafeInteger(id) || id < 1) { throw new Error('请选择背包档案'); }
  }

  private static archivePredicate(id: number): relationalStore.RdbPredicates {
    BackpackRepo.id(id);
    return new relationalStore.RdbPredicates('backpack_archives').equalTo('id', id);
  }

  private static itemPredicate(id: number): relationalStore.RdbPredicates {
    BackpackRepo.id(id);
    return new relationalStore.RdbPredicates('backpack_items').equalTo('archive_id', id);
  }

  private static readArchives(rs: relationalStore.ResultSet): BackpackArchive[] {
    const archives: BackpackArchive[] = [];
    try {
      while (rs.goToNextRow()) {
        const archive: BackpackArchive = new BackpackArchive();
        archive.id = rs.getLong(rs.getColumnIndex('id'));
        archive.name = rs.getString(rs.getColumnIndex('name'));
        archive.uid = rs.getString(rs.getColumnIndex('uid'));
        archive.isSelected = rs.getLong(rs.getColumnIndex('is_selected')) === 1;
        archive.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
        archive.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
        archive.source = rs.getString(rs.getColumnIndex('source'));
        archive.documentJson = rs.getString(rs.getColumnIndex('document_json'));
        archives.push(archive);
      }
    } finally { rs.close(); }
    return archives;
  }

  private static archiveSync(id: number): BackpackArchive {
    const rows: BackpackArchive[] = BackpackRepo.readArchives(
      RelationalStoreHelper.getStore().querySync(BackpackRepo.archivePredicate(id)));
    if (rows.length !== 1) { throw new Error('背包档案已被删除，请重新选择'); }
    return rows[0];
  }

  static async getArchives(): Promise<BackpackArchive[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('backpack_archives');
    pred.orderByAsc('id');
    return BackpackRepo.readArchives(await RelationalStoreHelper.query(pred));
  }

  static async getArchive(id: number): Promise<BackpackArchive> { return BackpackRepo.archiveSync(id); }

  static async createArchive(name: string, uid: string): Promise<number> {
    UIIFService.validateUid(uid);
    if (name.trim().length === 0 || name.trim().length > 80) { throw new Error('档案名称需为 1–80 个字符'); }
    const created: BackpackArchive = new BackpackArchive();
    const values: relationalStore.ValuesBucket = {
      'name': name.trim(), 'uid': uid, 'is_selected': 1, 'created_at': Date.now(),
      'updated_at': Date.now(), 'source': '手动档案', 'document_json': created.documentJson,
    };
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      const clear: relationalStore.ValuesBucket = { 'is_selected': 0 };
      store.updateSync(clear, new relationalStore.RdbPredicates('backpack_archives'));
      const id: number = store.insertSync('backpack_archives', values);
      if (id < 1) { throw new Error('创建档案失败'); }
      store.commit();
      return id;
    } catch (e) { store.rollBack(); throw new Error((e as Error).message); }
  }

  static async selectArchive(id: number): Promise<void> {
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      BackpackRepo.archiveSync(id);
      const clear: relationalStore.ValuesBucket = { 'is_selected': 0 };
      const chosen: relationalStore.ValuesBucket = { 'is_selected': 1 };
      store.updateSync(clear, new relationalStore.RdbPredicates('backpack_archives'));
      if (store.updateSync(chosen, BackpackRepo.archivePredicate(id)) !== 1) { throw new Error('选择档案失败'); }
      store.commit();
    } catch (e) { store.rollBack(); throw new Error((e as Error).message); }
  }

  static async deleteArchive(id: number): Promise<void> {
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      BackpackRepo.archiveSync(id);
      store.deleteSync(BackpackRepo.itemPredicate(id));
      store.deleteSync(BackpackRepo.archivePredicate(id));
      store.commit();
    } catch (e) { store.rollBack(); throw new Error((e as Error).message); }
  }

  private static readItems(rs: relationalStore.ResultSet): BackpackItem[] {
    const items: BackpackItem[] = [];
    try {
      while (rs.goToNextRow()) {
        const item: BackpackItem = UIIFService.parseItem(rs.getString(rs.getColumnIndex('raw_json')), items.length);
        item.archiveId = rs.getLong(rs.getColumnIndex('archive_id'));
        item.instanceId = rs.getString(rs.getColumnIndex('instance_id'));
        item.category = rs.getLong(rs.getColumnIndex('category'));
        if (item.itemId !== rs.getLong(rs.getColumnIndex('item_id')) ||
          item.kind !== rs.getString(rs.getColumnIndex('kind')) || !UIIFService.validCategory(item.kind, item.category)) {
          throw new Error('背包记录与原始数据不一致');
        }
        items.push(item);
      }
    } finally { rs.close(); }
    return items;
  }

  static async getItems(id: number): Promise<BackpackItem[]> {
    BackpackRepo.archiveSync(id);
    return BackpackRepo.readItems(await RelationalStoreHelper.query(BackpackRepo.itemPredicate(id)));
  }

  private static writeSnapshot(id: number, documentJson: string, items: BackpackItem[], source: string): void {
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    const rows: relationalStore.ValuesBucket[] = items.map((item: BackpackItem): relationalStore.ValuesBucket => {
      const row: relationalStore.ValuesBucket = {
        'archive_id': id, 'instance_id': item.instanceId, 'item_id': item.itemId,
        'kind': item.kind, 'category': item.category, 'raw_json': item.rawJson,
      };
      return row;
    });
    store.deleteSync(BackpackRepo.itemPredicate(id));
    for (let i: number = 0; i < rows.length; i += 500) {
      const chunk: relationalStore.ValuesBucket[] = rows.slice(i, i + 500);
      if (store.batchInsertSync('backpack_items', chunk) !== chunk.length) { throw new Error('背包写入不完整'); }
    }
    const values: relationalStore.ValuesBucket = {
      'document_json': documentJson, 'updated_at': Date.now(), 'source': source.substring(0, 200),
    };
    if (store.updateSync(values, BackpackRepo.archivePredicate(id)) !== 1) { throw new Error('背包档案已改变'); }
  }

  static async replaceSnapshot(id: number, prepared: BackpackImport): Promise<void> {
    const archive: BackpackArchive = BackpackRepo.archiveSync(id);
    if (prepared.targetArchiveId !== 0 && (prepared.targetArchiveId !== id || prepared.targetUid !== archive.uid ||
      prepared.targetUpdatedAt !== archive.updatedAt)) {
      throw new Error('目标档案已更改，请重新选择文件并确认导入');
    }
    UIIFService.validateSnapshot(archive.uid, prepared.documentJson, prepared.items);
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      BackpackRepo.writeSnapshot(id, prepared.documentJson, prepared.items, prepared.source);
      store.commit();
    } catch (e) { store.rollBack(); throw new Error((e as Error).message); }
  }

  static async addManual(id: number, item: BackpackItem): Promise<void> {
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      const archive: BackpackArchive = BackpackRepo.archiveSync(id);
      const items: BackpackItem[] = BackpackRepo.readItems(store.querySync(BackpackRepo.itemPredicate(id)));
      let serial: number = 1;
      const used: Set<string> = new Set<string>(items.map((entry: BackpackItem): string => entry.instanceId));
      while (used.has(`manual:${serial}`)) { serial++; }
      item.instanceId = `manual:${serial}`;
      items.push(item);
      UIIFService.validateSnapshot(archive.uid, archive.documentJson, items);
      BackpackRepo.writeSnapshot(id, archive.documentJson, items, '手动编辑');
      store.commit();
    } catch (e) { store.rollBack(); throw new Error((e as Error).message); }
  }

  static async categorize(id: number, instanceId: string, category: number): Promise<void> {
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      const archive: BackpackArchive = BackpackRepo.archiveSync(id);
      const items: BackpackItem[] = BackpackRepo.readItems(store.querySync(BackpackRepo.itemPredicate(id)));
      const item: BackpackItem | undefined = items.find((entry: BackpackItem): boolean => entry.instanceId === instanceId);
      if (item === undefined || !UIIFService.validCategory(item.kind, category)) { throw new Error('物品分类无效'); }
      item.category = category;
      UIIFService.validateSnapshot(archive.uid, archive.documentJson, items);
      BackpackRepo.writeSnapshot(id, archive.documentJson, items, archive.source);
      store.commit();
    } catch (e) { store.rollBack(); throw new Error((e as Error).message); }
  }

  private static editItem(id: number, instanceId: string, count: string | undefined): void {
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      const archive: BackpackArchive = BackpackRepo.archiveSync(id);
      const items: BackpackItem[] = BackpackRepo.readItems(store.querySync(BackpackRepo.itemPredicate(id)));
      const index: number = items.findIndex((item: BackpackItem): boolean => item.instanceId === instanceId);
      if (index < 0) { throw new Error('此物品已被删除或替换，请重新选择'); }
      if (count === undefined) { items.splice(index, 1); }
      else { items[index] = UIIFService.changeCount(items[index], count); }
      UIIFService.validateSnapshot(archive.uid, archive.documentJson, items);
      BackpackRepo.writeSnapshot(id, archive.documentJson, items, '手动编辑');
      store.commit();
    } catch (e) { store.rollBack(); throw new Error((e as Error).message); }
  }

  static async updateCount(id: number, instanceId: string, count: string): Promise<void> { BackpackRepo.editItem(id, instanceId, count); }
  static async removeItem(id: number, instanceId: string): Promise<void> { BackpackRepo.editItem(id, instanceId, undefined); }

  /** Read the chosen archive and project within one transaction; no login/account inference. */
  static async syncMaterials(id: number, projectId: number, replace: boolean): Promise<number> {
    BackpackRepo.id(projectId);
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      BackpackRepo.archiveSync(id);
      const project: relationalStore.ResultSet = store.querySync(
        new relationalStore.RdbPredicates('cultivate_projects').equalTo('id', projectId));
      try { if (!project.goToFirstRow()) { throw new Error('养成项目已删除'); } }
      finally { project.close(); }
      const items: BackpackItem[] = BackpackRepo.readItems(store.querySync(BackpackRepo.itemPredicate(id)));
      const inventory: Map<number, number> = new Map<number, number>();
      const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_inventory').equalTo('project_id', projectId);
      if (!replace) {
        const current: relationalStore.ResultSet = store.querySync(pred);
        try {
          while (current.goToNextRow()) {
            inventory.set(current.getLong(current.getColumnIndex('item_id')), current.getLong(current.getColumnIndex('count')));
          }
        } finally { current.close(); }
      }
      let count: number = 0;
      for (const item of items) {
        if (item.kind === 'material') { inventory.set(item.itemId, item.count); count++; }
      }
      const rows: relationalStore.ValuesBucket[] = [];
      inventory.forEach((value: number, itemId: number) => {
        const row: relationalStore.ValuesBucket = { 'project_id': projectId, 'item_id': itemId, 'count': value };
        rows.push(row);
      });
      store.deleteSync(pred);
      for (let i: number = 0; i < rows.length; i += 500) {
        const chunk: relationalStore.ValuesBucket[] = rows.slice(i, i + 500);
        if (store.batchInsertSync('cultivate_inventory', chunk) !== chunk.length) { throw new Error('材料快照写入不完整'); }
      }
      store.commit();
      return count;
    } catch (e) { store.rollBack(); throw new Error((e as Error).message); }
  }
}
