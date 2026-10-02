/**
 * AchievementRepo.ets
 * achievement_archives / achievement_entries 表 CRUD：多档案管理、完整成就记录读写、原子替换。
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

  /** 读某档案全部成就记录（含未完成进度） */
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
        r.status = rs.getLong(rs.getColumnIndex('status'));
        r.timestamp = rs.getLong(rs.getColumnIndex('timestamp'));
        map.set(r.achId, r);
      }
    } finally {
      rs.close();
    }
    return map;
  }

  /** 手动勾选只更新完成状态及时间，保留原始进度（对齐 Windows AchievementView）。 */
  static async setRecord(archiveId: number, achId: number, done: boolean, timestampSec: number): Promise<void> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_entries');
    pred.equalTo('archive_id', archiveId);
    pred.and();
    pred.equalTo('ach_id', achId);
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    const state: relationalStore.ValuesBucket = {
      'status': done ? 3 : 0,
      'timestamp': done ? timestampSec : 0,
    };
    if (store.updateSync(state, pred) > 0 || !done) {
      return;
    }
    const values: relationalStore.ValuesBucket = {
      'archive_id': archiveId,
      'ach_id': achId,
      'current': 0,
      'status': 3,
      'timestamp': timestampSec,
    };
    store.insertSync('achievement_entries', values);
  }

  /** 批量替换导入（UIAF：合并策略由调用方算好，此处全量覆盖该档案记录） */
  static async replaceRecords(archiveId: number, records: AchievementRecord[]): Promise<number> {
    const delPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('achievement_entries');
    delPred.equalTo('archive_id', archiveId);
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    let inserted: number = 0;
    const CHUNK: number = 500;
    // API 12 起的同步写入避免事务中 await 让其他业务写入交错；导入失败完整回滚。
    store.beginTransaction();
    try {
      store.deleteSync(delPred);
      for (let i: number = 0; i < records.length; i += CHUNK) {
        const end: number = Math.min(i + CHUNK, records.length);
        const batch: Array<relationalStore.ValuesBucket> = [];
        for (let j: number = i; j < end; j++) {
          batch.push({
            'archive_id': archiveId,
            'ach_id': records[j].achId,
            'current': records[j].current,
            'status': records[j].status,
            'timestamp': records[j].timestamp,
          });
        }
        const count: number = store.batchInsertSync('achievement_entries', batch);
        if (count !== batch.length) {
          throw new Error('成就写入不完整，导入已回滚');
        }
        inserted += count;
      }
      store.commit();
    } catch (e) {
      store.rollBack();
      throw new Error(e instanceof Error ? e.message : '成就导入失败，已回滚');
    }
    return inserted;
  }
}
