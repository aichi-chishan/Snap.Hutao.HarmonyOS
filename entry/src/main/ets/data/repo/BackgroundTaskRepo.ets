import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BackgroundTaskKind, BackgroundTaskState, BackgroundTaskPolicy, BackgroundOperation,
  BackgroundTaskResult } from '../../model/BackgroundTask';

/** Separate, versioned device-local operational DB; not part of user-data backup/restore. */
export class BackgroundTaskRepo {
  static readonly DB_NAME: string = 'snap_hutao_background.db';
  private static store: relationalStore.RdbStore | undefined = undefined;
  private static initializing: Promise<void> | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (BackgroundTaskRepo.store !== undefined) { return; }
    if (BackgroundTaskRepo.initializing === undefined) {
      BackgroundTaskRepo.initializing = BackgroundTaskRepo.open(context);
    }
    const pending: Promise<void> = BackgroundTaskRepo.initializing;
    try { await pending; }
    finally { if (BackgroundTaskRepo.initializing === pending) { BackgroundTaskRepo.initializing = undefined; } }
  }

  private static async open(context: common.Context): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: BackgroundTaskRepo.DB_NAME, customDir: 'hutao_background', securityLevel: relationalStore.SecurityLevel.S1,
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    if (store.version > 1) { throw new Error('后台任务状态版本不受支持'); }
    const options: relationalStore.TransactionOptions = { transactionType: relationalStore.TransactionType.IMMEDIATE };
    const tx: relationalStore.Transaction = await store.createTransaction(options);
    try {
      await tx.execute(`CREATE TABLE IF NOT EXISTS background_tasks (
        kind TEXT PRIMARY KEY, enabled INTEGER NOT NULL DEFAULT 0, epoch INTEGER NOT NULL DEFAULT 0,
        user_id INTEGER NOT NULL DEFAULT 0, uid TEXT NOT NULL DEFAULT '', region TEXT NOT NULL DEFAULT '',
        identity TEXT NOT NULL DEFAULT '', interval_minutes INTEGER NOT NULL DEFAULT 30,
        queued INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'disabled',
        message TEXT NOT NULL DEFAULT '未开启后台任务', last_run_at INTEGER NOT NULL DEFAULT 0,
        last_success_at INTEGER NOT NULL DEFAULT 0, lease TEXT NOT NULL DEFAULT '', lease_until INTEGER NOT NULL DEFAULT 0)`);
      await tx.execute(`CREATE TABLE IF NOT EXISTS background_operations (
        kind TEXT NOT NULL, user_id INTEGER NOT NULL, uid TEXT NOT NULL, region TEXT NOT NULL,
        day TEXT NOT NULL DEFAULT '', completed_day TEXT NOT NULL DEFAULT '', retry_at INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT '', lease TEXT NOT NULL DEFAULT '', lease_until INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(kind,user_id,uid,region))`);
      for (const kind of BackgroundTaskPolicy.KINDS) {
        await tx.execute('INSERT OR IGNORE INTO background_tasks(kind) VALUES (?)', [kind]);
      }
      await tx.execute('PRAGMA user_version=1');
      await tx.commit();
      BackgroundTaskRepo.store = store;
    } catch (e) {
      await tx.rollback();
      throw new Error('后台任务状态初始化失败');
    }
  }

  private static db(): relationalStore.RdbStore {
    if (BackgroundTaskRepo.store === undefined) { throw new Error('后台任务状态尚未初始化'); }
    return BackgroundTaskRepo.store;
  }

  static async get(kind: BackgroundTaskKind): Promise<BackgroundTaskState> {
    const rs: relationalStore.ResultSet = await BackgroundTaskRepo.db().querySql(
      'SELECT * FROM background_tasks WHERE kind=?', [kind]);
    const state: BackgroundTaskState = new BackgroundTaskState();
    state.kind = kind;
    try {
      if (!rs.goToFirstRow()) { return state; }
      state.enabled = rs.getLong(rs.getColumnIndex('enabled')) === 1;
      state.epoch = rs.getLong(rs.getColumnIndex('epoch'));
      state.userId = rs.getLong(rs.getColumnIndex('user_id'));
      state.uid = rs.getString(rs.getColumnIndex('uid'));
      state.region = rs.getString(rs.getColumnIndex('region'));
      state.identity = rs.getString(rs.getColumnIndex('identity'));
      state.intervalMinutes = rs.getLong(rs.getColumnIndex('interval_minutes'));
      state.queued = rs.getLong(rs.getColumnIndex('queued')) === 1;
      state.status = rs.getString(rs.getColumnIndex('status'));
      state.message = rs.getString(rs.getColumnIndex('message'));
      state.lastRunAt = rs.getLong(rs.getColumnIndex('last_run_at'));
      state.lastSuccessAt = rs.getLong(rs.getColumnIndex('last_success_at'));
      state.lease = rs.getString(rs.getColumnIndex('lease'));
      state.leaseUntil = rs.getLong(rs.getColumnIndex('lease_until'));
      return state;
    } finally { rs.close(); }
  }

  static async configure(state: BackgroundTaskState): Promise<void> {
    await BackgroundTaskRepo.db().executeSql(`UPDATE background_tasks SET enabled=?, epoch=epoch+1,
      user_id=?,uid=?,region=?,identity=?,interval_minutes=?,queued=0,status=?,message=?,lease='',lease_until=0 WHERE kind=?`,
      [state.enabled ? 1 : 0, state.userId, state.uid, state.region, state.identity, state.intervalMinutes,
        state.enabled ? 'pending' : 'disabled', state.enabled ? '等待注册系统任务' : '未开启后台任务', state.kind]);
  }

  static async scheduling(kind: BackgroundTaskKind, epoch: number, queued: boolean, status: string, message: string): Promise<void> {
    await BackgroundTaskRepo.db().executeSql(
      'UPDATE background_tasks SET queued=?,status=?,message=? WHERE kind=? AND epoch=? AND lease=\'\'',
      [queued ? 1 : 0, status, message, kind, epoch]);
  }

  static async claim(state: BackgroundTaskState, token: string, now: number): Promise<boolean> {
    await BackgroundTaskRepo.db().executeSql(`UPDATE background_tasks SET lease=?,lease_until=?,last_run_at=?,status='running',
      message='正在后台处理' WHERE kind=? AND enabled=1 AND epoch=? AND (lease='' OR lease_until<=? OR lease_until>?)`,
      [token, now + BackgroundTaskPolicy.BUDGET_MS, now, state.kind, state.epoch, now, now + 86400000]);
    const latest: BackgroundTaskState = await BackgroundTaskRepo.get(state.kind);
    return latest.lease === token && latest.epoch === state.epoch;
  }

  static async live(kind: BackgroundTaskKind, epoch: number, token: string): Promise<boolean> {
    const state: BackgroundTaskState = await BackgroundTaskRepo.get(kind);
    return state.enabled && state.epoch === epoch && state.lease === token && state.leaseUntil > Date.now();
  }

  static async finish(state: BackgroundTaskState, token: string, result: BackgroundTaskResult): Promise<void> {
    const success: boolean = result.status === 'success' || result.status === 'already_signed';
    await BackgroundTaskRepo.db().executeSql(`UPDATE background_tasks SET lease='',lease_until=0,status=?,message=?,
      last_success_at=CASE WHEN ?=1 THEN ? ELSE last_success_at END WHERE kind=? AND epoch=? AND lease=?`,
      [result.status, result.message, success ? 1 : 0, Date.now(), state.kind, state.epoch, token]);
  }

  static async fence(kind: BackgroundTaskKind): Promise<void> {
    await BackgroundTaskRepo.db().executeSql(`UPDATE background_tasks SET epoch=epoch+1,queued=0,
      lease='',lease_until=0,status=CASE WHEN enabled=1 THEN 'paused' ELSE 'disabled' END,
      message=CASE WHEN enabled=1 THEN '任务已暂停，等待核对原账号绑定后重新排队' ELSE '未开启后台任务' END WHERE kind=?`, [kind]);
  }

  static async clearOperationLeases(): Promise<void> {
    await BackgroundTaskRepo.db().executeSql("UPDATE background_operations SET lease='',lease_until=0");
  }

  static async clearBindings(): Promise<void> {
    await BackgroundTaskRepo.db().executeSql("UPDATE background_tasks SET user_id=0,uid='',region='',identity='',last_run_at=0,last_success_at=0");
  }

  static async stop(kind: BackgroundTaskKind, message: string): Promise<void> {
    await BackgroundTaskRepo.db().executeSql(`UPDATE background_tasks SET enabled=0,epoch=epoch+1,queued=0,
      lease='',lease_until=0,status='disabled',message=? WHERE kind=?`, [message, kind]);
  }

  static async operation(kind: BackgroundTaskKind, userId: number, uid: string, region: string): Promise<BackgroundOperation> {
    const op: BackgroundOperation = new BackgroundOperation();
    op.kind = kind; op.userId = userId; op.uid = uid; op.region = region;
    const rs: relationalStore.ResultSet = await BackgroundTaskRepo.db().querySql(
      'SELECT * FROM background_operations WHERE kind=? AND user_id=? AND uid=? AND region=?', [kind, userId, uid, region]);
    try {
      if (!rs.goToFirstRow()) { return op; }
      op.day = rs.getString(rs.getColumnIndex('day'));
      op.completedDay = rs.getString(rs.getColumnIndex('completed_day'));
      op.retryAt = rs.getLong(rs.getColumnIndex('retry_at'));
      op.status = rs.getString(rs.getColumnIndex('status'));
      op.lease = rs.getString(rs.getColumnIndex('lease'));
      op.leaseUntil = rs.getLong(rs.getColumnIndex('lease_until'));
      return op;
    } finally { rs.close(); }
  }

  static async claimOperation(op: BackgroundOperation, day: string, token: string, now: number, manual: boolean = false): Promise<boolean> {
    await BackgroundTaskRepo.db().executeSql(
      'INSERT OR IGNORE INTO background_operations(kind,user_id,uid,region) VALUES(?,?,?,?)',
      [op.kind, op.userId, op.uid, op.region]);
    await BackgroundTaskRepo.db().executeSql(`UPDATE background_operations SET day=?,lease=?,lease_until=?,retry_at=?,updated_at=?
      WHERE kind=? AND user_id=? AND uid=? AND region=? AND (lease='' OR lease_until<=? OR lease_until>?)
      AND (status NOT IN ('captcha','login_required','manual') OR day<>? OR ?=1) AND (retry_at<=? OR retry_at>? OR ?=1)
      AND (?=0 OR completed_day<>?)`, [day, token, now + BackgroundTaskPolicy.BUDGET_MS,
      now + BackgroundTaskPolicy.FAILURE_COOLDOWN_MS, now, op.kind, op.userId, op.uid, op.region, now, now + 86400000,
      day, manual ? 1 : 0, now, now + 86400000, manual ? 1 : 0, op.kind === BackgroundTaskKind.SIGN_IN ? 1 : 0, day]);
    const latest: BackgroundOperation = await BackgroundTaskRepo.operation(op.kind, op.userId, op.uid, op.region);
    return latest.lease === token;
  }

  static async finishOperation(op: BackgroundOperation, token: string, result: BackgroundTaskResult, intervalMinutes: number): Promise<void> {
    const success: boolean = result.status === 'success' || result.status === 'already_signed';
    const retryAt: number = Date.now() + (success && op.kind === BackgroundTaskKind.DAILY_NOTE
      ? BackgroundTaskPolicy.interval(intervalMinutes) * 60000 : BackgroundTaskPolicy.FAILURE_COOLDOWN_MS);
    await BackgroundTaskRepo.db().executeSql(`UPDATE background_operations SET lease='',lease_until=0,status=?,
      completed_day=CASE WHEN ?=1 THEN ? ELSE completed_day END,retry_at=?,updated_at=?
      WHERE kind=? AND user_id=? AND uid=? AND region=? AND lease=?`,
      [result.status, success ? 1 : 0, result.day, retryAt, Date.now(), op.kind, op.userId, op.uid, op.region, token]);
    // Operational records cannot grow without bound; no credentials are stored here.
    await BackgroundTaskRepo.db().executeSql(`DELETE FROM background_operations WHERE rowid IN
      (SELECT rowid FROM background_operations WHERE lease='' OR lease_until<=? ORDER BY updated_at DESC LIMIT -1 OFFSET 128)`, [Date.now()]);
  }

  static async clearBlocked(state: BackgroundTaskState): Promise<void> {
    await BackgroundTaskRepo.db().executeSql(`UPDATE background_operations SET status='',retry_at=0,lease='',lease_until=0 WHERE
      kind=? AND user_id=? AND uid=? AND region=? AND day=? AND (lease='' OR lease_until<=? OR lease_until>?)`,
      [state.kind, state.userId, state.uid, state.region, BackgroundTaskPolicy.day(state.region), Date.now(), Date.now() + 86400000]);
  }

  static async clearUser(userId: number): Promise<void> {
    await BackgroundTaskRepo.db().executeSql('DELETE FROM background_operations WHERE user_id=?', [userId]);
    await BackgroundTaskRepo.db().executeSql("UPDATE background_tasks SET user_id=0,uid='',region='',identity='',last_run_at=0,last_success_at=0 WHERE user_id=? AND enabled=0", [userId]);
  }

  static async clearOperations(): Promise<void> {
    await BackgroundTaskRepo.db().executeSql('DELETE FROM background_operations');
  }
}
