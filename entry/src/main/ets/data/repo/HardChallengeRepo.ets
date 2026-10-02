/**
 * HardChallengeRepo.ets
 * 幽境危战期数历史本地库（对齐 Windows HardChallengeEntry：按 UID/区服/schedule_id 累积，可回看往期）。
 * 期数键取响应 data[].schedule.schedule_id；明细以 API 内层 data 原始 JSON 存档（raw_json），
 * 回看时 HardChallengeRoot.fromJson 完整重建。
 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { Logger } from '../../common/Logger';

const TAG: string = 'HardChallengeRepo';

/** 期数历史条目（列表摘要） */
export class HardChallengeHistoryEntry {
  uid: string = '';
  region: string = '';
  scheduleId: number = 0;
  startTime: number = 0;
  endTime: number = 0;
  recordTime: number = 0;
}

export class HardChallengeRepo {
  /** 保存/刷新某期存档（UPSERT） */
  static async saveHistory(uid: string, region: string, scheduleId: number, startTime: number, endTime: number,
    rawJson: string): Promise<void> {
    if (uid.length === 0 || region.length === 0 || scheduleId <= 0 || rawJson.length === 0) {
      return;
    }
    const values: relationalStore.ValuesBucket = {
      'kind': 'hard_challenge',
      'uid': uid,
      'region': region,
      'schedule_id': scheduleId,
      'start_time': startTime,
      'end_time': endTime,
      'raw_json': rawJson,
      'record_time': Date.now(),
    };
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('challenge_records');
    pred.equalTo('kind', 'hard_challenge');
    pred.equalTo('uid', uid);
    pred.equalTo('region', region);
    pred.equalTo('schedule_id', scheduleId);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let exists: boolean = false;
    try {
      exists = rs.goToFirstRow();
    } finally {
      rs.close();
    }
    if (exists) {
      await RelationalStoreHelper.update('challenge_records', values, pred);
    } else {
      const inserted: Promise<number> = RelationalStoreHelper.getStore().insert('challenge_records', values,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      await inserted;
    }
    Logger.info(TAG, `history saved schedule=${scheduleId}`);
  }

  /** 期数列表（新期在前） */
  static async listHistory(uid: string, region: string): Promise<HardChallengeHistoryEntry[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('challenge_records');
    pred.equalTo('kind', 'hard_challenge');
    pred.equalTo('uid', uid);
    pred.equalTo('region', region);
    pred.orderByDesc('schedule_id');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const out: HardChallengeHistoryEntry[] = [];
    try {
      while (rs.goToNextRow()) {
        const e: HardChallengeHistoryEntry = new HardChallengeHistoryEntry();
        e.uid = rs.getString(rs.getColumnIndex('uid'));
        e.region = rs.getString(rs.getColumnIndex('region'));
        e.scheduleId = rs.getLong(rs.getColumnIndex('schedule_id'));
        e.startTime = rs.getLong(rs.getColumnIndex('start_time'));
        e.endTime = rs.getLong(rs.getColumnIndex('end_time'));
        e.recordTime = rs.getLong(rs.getColumnIndex('record_time'));
        out.push(e);
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 取某期原始 JSON（无则返回空串） */
  static async getRawJson(uid: string, region: string, scheduleId: number): Promise<string> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('challenge_records');
    pred.equalTo('kind', 'hard_challenge');
    pred.equalTo('uid', uid);
    pred.equalTo('region', region);
    pred.equalTo('schedule_id', scheduleId);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let raw: string = '';
    try {
      if (rs.goToFirstRow()) {
        raw = rs.getString(rs.getColumnIndex('raw_json'));
      }
    } finally {
      rs.close();
    }
    return raw;
  }
}
