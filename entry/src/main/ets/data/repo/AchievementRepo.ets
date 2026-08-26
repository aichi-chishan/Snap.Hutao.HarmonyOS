/**
 * AchievementRepo.ets
 * achievement_archives / achievement_entries 表 CRUD：多档案管理、完成记录读写、批量替换。
 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { AchievementArchive, AchievementRecord } from '../../model/AchievementData';
import { Logger } from '../../common/Logger';

const TAG: string = 'AchievementRepo';

export class AchievementRepo {
  // ================= 档案 =================

  static async getAllArchives(): Promise<AchievementArchive[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_archives');
    pred.orderByAsc('id');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const list: AchievementArchive[] = [];
    try {
      while (rs.goToNextRow()) {
        const a: AchievementArchive = new AchievementArchive();
        a.id = rs.getLong(rs.getColumnIndex('id'));
        a.name = rs.getString(rs.getColumnIndex('name'));
        a.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
        a.isSelected = rs.getLong(rs.getColumnIndex('is_selected')) === 1;
        list.push(a);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  static async createArchive(name: string): Promise<AchievementArchive> {
    const values: relationalStore.ValuesBucket = {
      'name': name,
      'is_selected': 0,
      'created_at': Date.now(),
    };
    const id: number = await RelationalStoreHelper.insert('achievement_archives', values);
    const created: AchievementArchive = new AchievementArchive();
    created.id = id;
    created.name = name;
    created.createdAt = Date.now();
    Logger.info(TAG, `created archive ${id}:${name}`);
    return created;
  }

  static async selectArchive(id: number): Promise<void> {
    const clearValues: relationalStore.ValuesBucket = { 'is_selected': 0 };
    await RelationalStoreHelper.update('achievement_archives', clearValues,
      new relationalStore.RdbPredicates('achievement_archives'));
    const values: relationalStore.ValuesBucket = { 'is_selected': 1 };
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_archives');
    pred.equalTo('id', id);
    await RelationalStoreHelper.update('achievement_archives', values, pred);
  }

  static async deleteArchive(id: number): Promise<void> {
    const entryPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_entries');
    entryPred.equalTo('archive_id', id);
    await RelationalStoreHelper.delete('achievement_entries', entryPred);
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_archives');
    pred.equalTo('id', id);
    await RelationalStoreHelper.delete('achievement_archives', pred);
    Logger.info(TAG, `deleted archive ${id}`);
  }

  // ================= 完成记录 =================

  /** 读某档案全部完成记录 */
  static async getRecords(archiveId: number): Promise<Map<number, AchievementRecord>> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_entries');
    pred.equalTo('archive_id', archiveId);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const map: Map<number, AchievementRecord> = new Map();
    try {
      while (rs.goToNextRow()) {
        const r: AchievementRecord = new AchievementRecord();
        r.archiveId = archiveId;
        r.achId = rs.getLong(rs.getColumnIndex('ach_id'));
        r.current = rs.getLong(rs.getColumnIndex('current'));
        r.timestamp = rs.getLong(rs.getColumnIndex('timestamp'));
        map.set(r.achId, r);
      }
    } finally {
      rs.close();
    }
    return map;
  }

  /** 置位/取消一条（取消=删除行） */
  static async setRecord(archiveId: number, achId: number, done: boolean, timestampSec: number): Promise<void> {
    if (!done) {
      const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_entries');
      pred.equalTo('archive_id', archiveId);
      pred.and();
      pred.equalTo('ach_id', achId);
      await RelationalStoreHelper.delete('achievement_entries', pred);
      return;
    }
    // upsert：先删后插（量小，逻辑简单可靠）
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_entries');
    pred.equalTo('archive_id', archiveId);
    pred.and();
    pred.equalTo('ach_id', achId);
    await RelationalStoreHelper.delete('achievement_entries', pred);
    const values: relationalStore.ValuesBucket = {
      'archive_id': archiveId,
      'ach_id': achId,
      'current': 1,
      'timestamp': timestampSec,
    };
    await RelationalStoreHelper.insert('achievement_entries', values);
  }

  /** 批量替换导入（UIAF：合并策略由调用方算好，此处全量覆盖该档案记录） */
  static async replaceRecords(archiveId: number, records: AchievementRecord[]): Promise<number> {
    const delPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_entries');
    delPred.equalTo('archive_id', archiveId);
    await RelationalStoreHelper.delete('achievement_entries', delPred);
    let inserted: number = 0;
    const CHUNK: number = 500;
    for (let i = 0; i < records.length; i += CHUNK) {
      const end: number = Math.min(i + CHUNK, records.length);
      const batch: Array<relationalStore.ValuesBucket> = [];
      for (let j = i; j < end; j++) {
        batch.push({
          'archive_id': archiveId,
          'ach_id': records[j].achId,
          'current': records[j].current,
          'timestamp': records[j].timestamp,
        });
      }
      inserted += await RelationalStoreHelper.batchInsert('achievement_entries', batch);
    }
    return inserted;
  }
}
