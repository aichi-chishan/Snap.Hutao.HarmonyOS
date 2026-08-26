/**
 * DailyNoteRepo.ets
 * daily_notes 表 CRUD：按 user+uid 查询/upsert，阈值字段（树脂/洞天宝钱）与通知开关位读写。
 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { DailyNote, Expedition } from '../../model/DailyNote';
import { Logger } from '../../common/Logger';

const TAG: string = 'DailyNoteRepo';

/** DB 行包装：便笺数据 + 阈值 + 开关位 */
export class DailyNoteRecord {
  note: DailyNote = new DailyNote();
  resinNotifyThreshold: number = 120;
  homeCoinNotifyThreshold: number = 1800;
  /** 位：0=树脂 1=派遣 2=每日 3=参变仪 4=洞天宝钱 */
  notifyFlags: number = 31;
}

export class DailyNoteRepo {
  /** upsert（存在则更新数据+刷新时间，保留阈值/开关） */
  static async upsert(userId: number, uid: string, note: DailyNote): Promise<void> {
    const existing: DailyNoteRecord | undefined = await DailyNoteRepo.get(userId, uid);
    const flags: number = existing !== undefined ? existing.notifyFlags : 31;
    const resinTh: number = existing !== undefined ? existing.resinNotifyThreshold : 120;
    const homeTh: number = existing !== undefined ? existing.homeCoinNotifyThreshold : 1800;
    const values: relationalStore.ValuesBucket = {
      'user_id': userId,
      'uid': uid,
      'current_resin': note.currentResin,
      'max_resin': note.maxResin,
      'resin_recovery_time': note.resinRecoveryTime,
      'finished_task_num': note.finishedTaskNum,
      'total_task_num': note.totalTaskNum,
      'is_extra_task_reward_received': note.isExtraTaskRewardReceived ? 1 : 0,
      'remain_resin_discount_num': note.remainResinDiscountNum,
      'limit_resin_discount_num': note.resinDiscountNumLimit,
      'current_home_coin': note.currentHomeCoin,
      'max_home_coin': note.maxHomeCoin,
      'home_coin_recovery_time': note.homeCoinRecoveryTime,
      'current_expedition_num': note.currentExpeditionNum,
      'max_expedition_num': note.maxExpeditionNum,
      'expeditions_json': JSON.stringify(note.expeditions),
      'transformer_json': JSON.stringify(note.transformer),
      'archon_json': '',
      'resin_notify_threshold': resinTh,
      'home_coin_notify_threshold': homeTh,
      'notify_flags': flags,
      'refresh_time': Date.now(),
    };
    // 查询是否已存在
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('daily_notes');
    pred.equalTo('user_id', userId);
    pred.equalTo('uid', uid);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let hasRow: boolean = false;
    try {
      hasRow = rs.goToFirstRow();
    } finally {
      rs.close();
    }
    if (hasRow) {
      const up: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('daily_notes');
      up.equalTo('user_id', userId);
      up.equalTo('uid', uid);
      await RelationalStoreHelper.update('daily_notes', values, up);
    } else {
      await RelationalStoreHelper.insert('daily_notes', values);
    }
    Logger.info(TAG, `upsert dailynote user=${userId} uid=${uid}`);
  }

  static async get(userId: number, uid: string): Promise<DailyNoteRecord | undefined> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('daily_notes');
    pred.equalTo('user_id', userId);
    pred.equalTo('uid', uid);
    pred.limitAs(1);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let rec: DailyNoteRecord | undefined = undefined;
    try {
      if (rs.goToFirstRow()) {
        rec = DailyNoteRepo.rowToRecord(rs);
      }
    } finally {
      rs.close();
    }
    return rec;
  }

  static async getByUid(uid: string): Promise<DailyNoteRecord | undefined> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('daily_notes');
    pred.equalTo('uid', uid);
    pred.limitAs(1);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let rec: DailyNoteRecord | undefined = undefined;
    try {
      if (rs.goToFirstRow()) {
        rec = DailyNoteRepo.rowToRecord(rs);
      }
    } finally {
      rs.close();
    }
    return rec;
  }

  private static rowToRecord(rs: relationalStore.ResultSet): DailyNoteRecord {
    const rec: DailyNoteRecord = new DailyNoteRecord();
    const note: DailyNote = new DailyNote();
    note.currentResin = rs.getLong(rs.getColumnIndex('current_resin'));
    note.maxResin = rs.getLong(rs.getColumnIndex('max_resin'));
    note.resinRecoveryTime = rs.getString(rs.getColumnIndex('resin_recovery_time'));
    note.finishedTaskNum = rs.getLong(rs.getColumnIndex('finished_task_num'));
    note.totalTaskNum = rs.getLong(rs.getColumnIndex('total_task_num'));
    note.isExtraTaskRewardReceived = rs.getLong(rs.getColumnIndex('is_extra_task_reward_received')) === 1;
    note.remainResinDiscountNum = rs.getLong(rs.getColumnIndex('remain_resin_discount_num'));
    note.resinDiscountNumLimit = rs.getLong(rs.getColumnIndex('limit_resin_discount_num'));
    note.currentHomeCoin = rs.getLong(rs.getColumnIndex('current_home_coin'));
    note.maxHomeCoin = rs.getLong(rs.getColumnIndex('max_home_coin'));
    note.homeCoinRecoveryTime = rs.getString(rs.getColumnIndex('home_coin_recovery_time'));
    note.currentExpeditionNum = rs.getLong(rs.getColumnIndex('current_expedition_num'));
    note.maxExpeditionNum = rs.getLong(rs.getColumnIndex('max_expedition_num'));
    note.refreshTime = rs.getLong(rs.getColumnIndex('refresh_time'));
    // JSON 反序列化
    const expJson: string = rs.getString(rs.getColumnIndex('expeditions_json'));
    if (expJson.length > 0) {
      try {
        const arr = JSON.parse(expJson) as Array<Object>;
        for (let i = 0; i < arr.length; i++) {
          const e = arr[i] as Record<string, Object>;
          const exp: Expedition = new Expedition();
          exp.avatarSideIcon = String(e['avatarSideIcon'] ?? '');
          exp.status = String(e['status'] ?? '');
          exp.remainedTime = String(e['remainedTime'] ?? '');
          note.expeditions.push(exp);
        }
      } catch (e) {
        Logger.warn(TAG, 'expeditions json parse fail');
      }
    }
    const trJson: string = rs.getString(rs.getColumnIndex('transformer_json'));
    if (trJson.length > 0) {
      try {
        const t = JSON.parse(trJson) as Record<string, Object>;
        note.transformer.day = Number(t['day'] ?? 0);
        note.transformer.hour = Number(t['hour'] ?? 0);
        note.transformer.minute = Number(t['minute'] ?? 0);
        note.transformer.second = Number(t['second'] ?? 0);
        note.transformer.reached = t['reached'] === true;
      } catch (e) {
        Logger.warn(TAG, 'transformer json parse fail');
      }
    }
    rec.note = note;
    rec.resinNotifyThreshold = rs.getLong(rs.getColumnIndex('resin_notify_threshold'));
    rec.homeCoinNotifyThreshold = rs.getLong(rs.getColumnIndex('home_coin_notify_threshold'));
    rec.notifyFlags = rs.getLong(rs.getColumnIndex('notify_flags'));
    return rec;
  }

  static async updateThresholds(userId: number, uid: string,
    resinTh: number, homeTh: number, flags: number): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'resin_notify_threshold': resinTh,
      'home_coin_notify_threshold': homeTh,
      'notify_flags': flags,
    };
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('daily_notes');
    pred.equalTo('user_id', userId);
    pred.equalTo('uid', uid);
    await RelationalStoreHelper.update('daily_notes', values, pred);
  }
}
