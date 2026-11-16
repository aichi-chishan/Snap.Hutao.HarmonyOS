/**
 * GachaRepo.ets
 * gacha_archives / gacha_items 表 CRUD：按 uid 归档、批量插入、去重查询、统计聚合查询。
 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { GachaArchive } from '../../model/GachaArchive';
import { GachaItem } from '../../model/GachaItem';
import { GachaType } from '../../model/GachaType';
import { Logger } from '../../common/Logger';

const TAG: string = 'GachaRepo';

export class GachaRepo {
  // ================= 归档 =================

  /** 获取或创建归档（uid 唯一） */
  static async getOrCreateArchive(uid: string): Promise<GachaArchive> {
    if (!/^[1-9][0-9]{8,9}$/.test(uid)) {
      throw new Error('无效的祈愿 UID');
    }
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_archives');
    pred.equalTo('uid', uid);
    pred.limitAs(1);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let archive: GachaArchive | undefined = undefined;
    try {
      if (rs.goToFirstRow()) {
        archive = new GachaArchive();
        archive.id = rs.getLong(rs.getColumnIndex('id'));
        archive.uid = rs.getString(rs.getColumnIndex('uid'));
        archive.isSelected = rs.getLong(rs.getColumnIndex('is_selected')) === 1;
      }
    } finally {
      rs.close();
    }
    if (archive !== undefined) {
      return archive;
    }
    const values: relationalStore.ValuesBucket = { 'uid': uid, 'is_selected': 0 };
    const id: number = await RelationalStoreHelper.insert('gacha_archives', values);
    const created: GachaArchive = new GachaArchive();
    created.id = id;
    created.uid = uid;
    created.isSelected = false;
    Logger.info(TAG, `created archive for uid=${uid}`);
    return created;
  }

  static async getAllArchives(): Promise<GachaArchive[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_archives');
    pred.orderByAsc('id');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const list: GachaArchive[] = [];
    try {
      while (rs.goToNextRow()) {
        const a: GachaArchive = new GachaArchive();
        a.id = rs.getLong(rs.getColumnIndex('id'));
        a.uid = rs.getString(rs.getColumnIndex('uid'));
        a.isSelected = rs.getLong(rs.getColumnIndex('is_selected')) === 1;
        list.push(a);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  static async selectArchive(id: number): Promise<void> {
    const clearValues: relationalStore.ValuesBucket = { 'is_selected': 0 };
    const clearPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_archives');
    await RelationalStoreHelper.update('gacha_archives', clearValues, clearPred);
    const values: relationalStore.ValuesBucket = { 'is_selected': 1 };
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_archives');
    pred.equalTo('id', id);
    await RelationalStoreHelper.update('gacha_archives', values, pred);
  }

  static async deleteArchive(id: number): Promise<void> {
    // 删除明细
    const itemPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
    itemPred.equalTo('archive_id', id);
    await RelationalStoreHelper.delete('gacha_items', itemPred);
    // 删除归档
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_archives');
    pred.equalTo('id', id);
    await RelationalStoreHelper.delete('gacha_archives', pred);
    Logger.info(TAG, `deleted archive ${id}`);
  }

  /** 删除某 uid 的整套归档（清空祈愿） */
  static async deleteArchiveByUid(uid: string): Promise<void> {
    const archives: GachaArchive[] = await GachaRepo.getAllArchives();
    for (let i = 0; i < archives.length; i++) {
      if (archives[i].uid === uid) {
        await GachaRepo.deleteArchive(archives[i].id);
      }
    }
  }

  // ================= 明细 =================

  /** 某归档某池全部游标 id（去重用） */
  static async getAllGachaIds(archiveId: number, gachaType: number): Promise<string[]> {
    return (await GachaRepo.getItemsByType(archiveId, gachaType))
      .map((item: GachaItem): string => item.gachaId);
  }

  /** 增量写入在事务内再次核对逻辑身份，重试和别名池查询都不会重复插入。 */
  static async insertItems(items: GachaItem[]): Promise<number> {
    if (items.length === 0) { return 0; }
    const grouped: Map<number, GachaItem[]> = new Map<number, GachaItem[]>();
    for (const item of items) {
      if (item.archiveId <= 0) { throw new Error('祈愿记录缺少归档'); }
      const group: GachaItem[] = grouped.get(item.archiveId) ?? [];
      group.push(item);
      grouped.set(item.archiveId, group);
    }
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    let inserted: number = 0;
    store.beginTransaction();
    try {
      for (const archiveId of grouped.keys()) {
        const uid: string = GachaRepo.archiveUidSync(store, archiveId);
        inserted += GachaRepo.insertNewRecords(store, archiveId, uid, grouped.get(archiveId) ?? [], true);
      }
      store.commit();
      return inserted;
    } catch (e) {
      store.rollBack();
      throw new Error(e instanceof Error ? e.message : '保存祈愿记录失败');
    }
  }

  /** 全文件预检后，一次同步事务提交全部所选 UID；不在事务中 await，也不修改输入记录。 */
  static async importArchives(pending: Map<string, GachaItem[]>, fillGaps: boolean = false): Promise<number> {
    if (pending.size === 0) { throw new Error('请至少选择一个 UID'); }
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    let inserted: number = 0;
    store.beginTransaction();
    try {
      for (const uid of pending.keys()) {
        if (!/^[1-9][0-9]{8,9}$/.test(uid)) { throw new Error('无效的祈愿 UID'); }
        const archivePred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_archives');
        archivePred.equalTo('uid', uid);
        const archiveRs: relationalStore.ResultSet = store.querySync(archivePred);
        let archiveId: number = 0;
        try {
          if (archiveRs.goToFirstRow()) { archiveId = archiveRs.getLong(archiveRs.getColumnIndex('id')); }
        } finally { archiveRs.close(); }
        if (archiveId <= 0) {
          const values: relationalStore.ValuesBucket = { 'uid': uid, 'is_selected': 0 };
          archiveId = store.insertSync('gacha_archives', values);
          if (archiveId <= 0) { throw new Error('创建祈愿档案失败'); }
        }
        inserted += GachaRepo.insertNewRecords(store, archiveId, uid, pending.get(uid) ?? [], fillGaps);
      }
      store.commit();
      return inserted;
    } catch (e) {
      store.rollBack();
      throw new Error(e instanceof Error ? e.message : '导入祈愿记录失败，全部变更已回滚');
    }
  }

  private static archiveUidSync(store: relationalStore.RdbStore, archiveId: number): string {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_archives');
    pred.equalTo('id', archiveId);
    const rs: relationalStore.ResultSet = store.querySync(pred);
    try {
      if (!rs.goToFirstRow()) { throw new Error('祈愿归档不存在'); }
      return rs.getString(rs.getColumnIndex('uid'));
    } finally { rs.close(); }
  }

  private static insertNewRecords(store: relationalStore.RdbStore, archiveId: number, uid: string,
    items: GachaItem[], fillGaps: boolean): number {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
    pred.equalTo('archive_id', archiveId);
    pred.orderByAsc('id');
    const known: Map<string, GachaItem> = GachaItem.recordIndex(GachaRepo.readItems(store.querySync(pred)), `UID ${uid}`);
    const oldestByPool: Map<number, string> = new Map<number, string>();
    for (const item of known.values()) {
      const pool: number = GachaType.queryTypeOf(item.gachaType);
      const oldest: string | undefined = oldestByPool.get(pool);
      if (oldest === undefined || GachaItem.compareIds(item.gachaId, oldest) < 0) { oldestByPool.set(pool, item.gachaId); }
    }
    const batch: relationalStore.ValuesBucket[] = [];
    let inserted: number = 0;
    for (const item of GachaItem.logicalRecords(items, `UID ${uid}`)) {
      if (item.uid.length > 0 && item.uid !== uid) { throw new Error('祈愿记录 UID 与归档不一致'); }
      const key: string = GachaItem.recordKey(item);
      const previous: GachaItem | undefined = known.get(key);
      if (previous !== undefined) {
        known.set(key, GachaItem.mergeRecord(previous, item, `UID ${uid}`));
        continue;
      }
      if (!fillGaps && GachaItem.compareIds(item.gachaId,
        oldestByPool.get(GachaType.queryTypeOf(item.gachaType)) ?? GachaItem.MAX_SIGNED_ID) >= 0) { continue; }
      const values: relationalStore.ValuesBucket = GachaRepo.valuesOf(item);
      values['archive_id'] = archiveId;
      batch.push(values);
      known.set(key, item);
      if (batch.length === 500) {
        if (store.batchInsertSync('gacha_items', batch) !== batch.length) { throw new Error('祈愿记录未完整写入'); }
        inserted += batch.length;
        batch.length = 0;
      }
    }
    if (batch.length > 0) {
      if (store.batchInsertSync('gacha_items', batch) !== batch.length) { throw new Error('祈愿记录未完整写入'); }
      inserted += batch.length;
    }
    return inserted;
  }

  /** 全量刷新仅替换服务器实际返回窗口，较早的本地历史保留。 */
  static async replaceFetchedWindow(items: GachaItem[], queryType: number): Promise<number> {
    if (items.length === 0) {
      return 0;
    }
    const archiveId: number = items[0].archiveId;
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      const uid: string = GachaRepo.archiveUidSync(store, archiveId);
      const ordered: GachaItem[] = GachaRepo.sortByCursor(GachaItem.logicalRecords(items, `UID ${uid}`), false);
      const oldest: string = ordered[0].gachaId;
      const itemPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
      itemPred.equalTo('archive_id', archiveId);
      itemPred.orderByAsc('id');
      const raw: GachaItem[] = GachaRepo.readItems(store.querySync(itemPred));
      const known: Map<string, GachaItem> = GachaItem.recordIndex(raw, `UID ${uid}`);
      for (const item of ordered) {
        if (item.archiveId !== archiveId || (item.uid.length > 0 && item.uid !== uid) ||
          GachaType.queryTypeOf(item.gachaType) !== queryType) { throw new Error('全量刷新记录与归档或卡池不一致'); }
        const previous: GachaItem | undefined = known.get(GachaItem.recordKey(item));
        if (previous !== undefined) { GachaItem.mergeRecord(previous, item, `UID ${uid}`); }
      }
      // 用户主动全量刷新保留上游 Aggressive 替换语义，但冲突必须在删除前显式拒绝。
      const replaceIds: number[] = raw.filter((item: GachaItem): boolean =>
        GachaType.queryTypeOf(item.gachaType) === queryType && GachaItem.compareIds(item.gachaId, oldest) >= 0)
        .map((item: GachaItem): number => item.id);
      for (let index: number = 0; index < replaceIds.length; index += 500) {
        const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
        pred.equalTo('archive_id', archiveId);
        pred.in('id', replaceIds.slice(index, index + 500));
        store.deleteSync(pred);
      }
      for (let index: number = 0; index < ordered.length; index += 500) {
        const rows: relationalStore.ValuesBucket[] = ordered.slice(index, index + 500)
          .map((item: GachaItem): relationalStore.ValuesBucket => GachaRepo.valuesOf(item));
        if (store.batchInsertSync('gacha_items', rows) !== rows.length) {
          throw new Error('祈愿记录未完整写入');
        }
      }
      store.commit();
      return ordered.length;
    } catch (e) {
      store.rollBack();
      throw new Error(e instanceof Error ? e.message : '保存祈愿记录失败');
    }
  }

  private static valuesOf(it: GachaItem): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      'archive_id': it.archiveId, 'gacha_type': it.gachaType, 'item_id': it.itemId,
      'count': it.count, 'time': it.time, 'name': it.name, 'item_type': it.itemType,
      'rank_type': it.rankType, 'gacha_id': it.gachaId, 'schedule_id': it.scheduleId
    };
    return values;
  }

  /** 分页查询某池明细（倒序） */
  static async getItems(archiveId: number, gachaType: number, limit: number, offset: number): Promise<GachaItem[]> {
    if (!Number.isSafeInteger(limit) || limit < 0 || !Number.isSafeInteger(offset) || offset < 0) {
      throw new Error('无效的祈愿分页范围');
    }
    const items: GachaItem[] = (await GachaRepo.getItemsByType(archiveId, gachaType)).reverse();
    return items.slice(offset, offset + limit);
  }

  /** 某归档某池全部明细（统计聚合用，量可控） */
  static async getItemsByType(archiveId: number, gachaType: number): Promise<GachaItem[]> {
    const types: number[] = GachaType.storedTypes(gachaType);
    return (await GachaRepo.getItemsByArchive(archiveId))
      .filter((item: GachaItem): boolean => types.includes(item.gachaType));
  }

  static async getItemsByArchive(archiveId: number): Promise<GachaItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
    pred.equalTo('archive_id', archiveId);
    // 固定按原始行顺序选展示文本，投影后再按精确游标排序。
    pred.orderByAsc('id');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    return GachaRepo.sortByCursor(GachaItem.logicalRecords(GachaRepo.readItems(rs), `归档 ${archiveId}`), false);
  }

  /** 游标为64位十进制字符串；不转换为number，避免同秒十连乱序及精度损失。 */
  private static sortByCursor(items: GachaItem[], descending: boolean): GachaItem[] {
    return items.sort((a: GachaItem, b: GachaItem): number => {
      const order: number = GachaItem.compareIds(a.gachaId, b.gachaId);
      const stable: number = order || (GachaType.isBeyond(a.gachaType) ? 1 : 0) - (GachaType.isBeyond(b.gachaType) ? 1 : 0);
      return descending ? -stable : stable;
    });
  }

  private static readItems(rs: relationalStore.ResultSet): GachaItem[] {
    const list: GachaItem[] = [];
    try {
      while (rs.goToNextRow()) {
        const it: GachaItem = new GachaItem();
        it.id = rs.getLong(rs.getColumnIndex('id'));
        it.archiveId = rs.getLong(rs.getColumnIndex('archive_id'));
        it.gachaType = rs.getLong(rs.getColumnIndex('gacha_type'));
        it.itemId = rs.getLong(rs.getColumnIndex('item_id'));
        it.count = rs.getLong(rs.getColumnIndex('count'));
        it.time = rs.getString(rs.getColumnIndex('time'));
        it.name = rs.getString(rs.getColumnIndex('name'));
        it.itemType = rs.getString(rs.getColumnIndex('item_type'));
        it.rankType = rs.getLong(rs.getColumnIndex('rank_type'));
        it.gachaId = rs.getString(rs.getColumnIndex('gacha_id'));
        it.scheduleId = rs.getLong(rs.getColumnIndex('schedule_id'));
        list.push(it);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  /** 统计某归档总抽数与各池数量 */
  static async countAll(archiveId: number): Promise<number> {
    return (await GachaRepo.getItemsByArchive(archiveId)).length;
  }

  static async countByType(archiveId: number, gachaType: number): Promise<number> {
    return (await GachaRepo.getItemsByType(archiveId, gachaType)).length;
  }
}
