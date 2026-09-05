/**
 * SpiralAbyssRepo.ets
 * 深渊期数历史本地库（对齐 Windows SpiralAbyssEntry：按 schedule_id 累积，可回看往期）。
 * 明细以 API 原始 JSON 存档（raw_json），回看时 SpiralAbyssData.fromJson 完整重建。
 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { Logger } from '../../common/Logger';

const TAG: string = 'SpiralAbyssRepo';

/** 期数历史条目（列表摘要） */
export class AbyssHistoryEntry {
  scheduleId: number = 0;
  startTime: number = 0;
  endTime: number = 0;
  totalStar: number = 0;
  recordTime: number = 0;
}

export class SpiralAbyssRepo {
  /** 保存/刷新某期存档（UPSERT） */
  static async saveHistory(scheduleId: number, startTime: number, endTime: number,
    totalStar: number, rawJson: string): Promise<void> {
    if (scheduleId <= 0 || rawJson.length === 0) {
      return;
    }
    const values: relationalStore.ValuesBucket = {
      'schedule_id': scheduleId,
      'start_time': startTime,
      'end_time': endTime,
      'total_star': totalStar,
      'raw_json': rawJson,
      'record_time': Date.now(),
    };
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('abyss_history');
    pred.equalTo('schedule_id', scheduleId);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let exists: boolean = false;
    try {
      exists = rs.goToFirstRow();
    } finally {
      rs.close();
    }
    if (exists) {
      await RelationalStoreHelper.update('abyss_history', values, pred);
    } else {
      await RelationalStoreHelper.insert('abyss_history', values);
    }
    Logger.info(TAG, `history saved schedule=${scheduleId} star=${totalStar}`);
  }

  /** 期数列表（新期在前） */
  static async listHistory(): Promise<AbyssHistoryEntry[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('abyss_history');
    pred.orderByDesc('schedule_id');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const out: AbyssHistoryEntry[] = [];
    try {
      while (rs.goToNextRow()) {
        const e: AbyssHistoryEntry = new AbyssHistoryEntry();
        e.scheduleId = rs.getLong(rs.getColumnIndex('schedule_id'));
        e.startTime = rs.getLong(rs.getColumnIndex('start_time'));
        e.endTime = rs.getLong(rs.getColumnIndex('end_time'));
        e.totalStar = rs.getLong(rs.getColumnIndex('total_star'));
        e.recordTime = rs.getLong(rs.getColumnIndex('record_time'));
        out.push(e);
      }
    } finally {
      rs.close();
    }
    return out;
  }

  /** 取某期原始 JSON（无则返回空串） */
  static async getRawJson(scheduleId: number): Promise<string> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('abyss_history');
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
