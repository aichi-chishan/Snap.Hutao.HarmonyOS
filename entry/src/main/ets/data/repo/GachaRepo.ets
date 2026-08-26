/**
 * GachaRepo.ets
 * gacha_archives / gacha_items 表 CRUD：按 uid 归档、批量插入、去重查询、统计聚合查询。
 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { GachaArchive } from '../../model/GachaArchive';
import { GachaItem } from '../../model/GachaItem';
import { Logger } from '../../common/Logger';

const TAG: string = 'GachaRepo';

export class GachaRepo {
  // ================= 归档 =================

  /** 获取或创建归档（uid 唯一） */
  static async getOrCreateArchive(uid: string): Promise<GachaArchive> {
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
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
    pred.equalTo('archive_id', archiveId);
    pred.equalTo('gacha_type', gachaType);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const ids: string[] = [];
    try {
      while (rs.goToNextRow()) {
        ids.push(rs.getString(rs.getColumnIndex('gacha_id')));
      }
    } finally {
      rs.close();
    }
    return ids;
  }

  /** 批量插入（Lazy 合并时仅插入不存在的游标；调用方已去重） */
  static async insertItems(items: GachaItem[]): Promise<number> {
    if (items.length === 0) {
      return 0;
    }
    let inserted: number = 0;
    const CHUNK: number = 500;
    for (let i = 0; i < items.length; i += CHUNK) {
      const end: number = Math.min(i + CHUNK, items.length);
      const batch: Array<relationalStore.ValuesBucket> = [];
      for (let j = i; j < end; j++) {
        const it: GachaItem = items[j];
        const values: relationalStore.ValuesBucket = {
          'archive_id': it.archiveId,
          'gacha_type': it.gachaType,
          'item_id': it.itemId,
          'count': it.count,
          'time': it.time,
          'name': it.name,
          'item_type': it.itemType,
          'rank_type': it.rankType,
          'gacha_id': it.gachaId,
        };
        batch.push(values);
      }
      const affected: number = await RelationalStoreHelper.batchInsert('gacha_items', batch);
      inserted += affected;
    }
    return inserted;
  }

  /** 分页查询某池明细（倒序） */
  static async getItems(archiveId: number, gachaType: number, limit: number, offset: number): Promise<GachaItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
    pred.equalTo('archive_id', archiveId);
    pred.equalTo('gacha_type', gachaType);
    pred.orderByDesc('time');
    pred.limitAs(limit);
    if (offset > 0) {
      pred.offsetAs(offset);
    }
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    return GachaRepo.readItems(rs);
  }

  /** 某归档某池全部明细（统计聚合用，量可控） */
  static async getItemsByType(archiveId: number, gachaType: number): Promise<GachaItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
    pred.equalTo('archive_id', archiveId);
    pred.equalTo('gacha_type', gachaType);
    pred.orderByAsc('time');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    return GachaRepo.readItems(rs);
  }

  static async getItemsByArchive(archiveId: number): Promise<GachaItem[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
    pred.equalTo('archive_id', archiveId);
    pred.orderByAsc('time');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    return GachaRepo.readItems(rs);
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
        list.push(it);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  /** 统计某归档总抽数与各池数量 */
  static async countAll(archiveId: number): Promise<number> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
    pred.equalTo('archive_id', archiveId);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let count: number = 0;
    try {
      while (rs.goToNextRow()) {
        count += rs.getLong(rs.getColumnIndex('count'));
      }
    } finally {
      rs.close();
    }
    return count;
  }

  static async countByType(archiveId: number, gachaType: number): Promise<number> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('gacha_items');
    pred.equalTo('archive_id', archiveId);
    pred.equalTo('gacha_type', gachaType);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let count: number = 0;
    try {
      while (rs.goToNextRow()) {
        count += rs.getLong(rs.getColumnIndex('count'));
      }
    } finally {
      rs.close();
    }
    return count;
  }
}
