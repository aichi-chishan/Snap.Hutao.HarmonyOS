/** Validate snapshots, stage credentials under new IDs, atomically restore database rows. */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../data/db/RelationalStoreHelper';
import { TokenVault } from '../data/local/TokenVault';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { BackupSnapshot, BackupTable, BackupCredential, BackupCell, BackupSnapshotValidator, BackupRecovery } from '../model/BackupSnapshot';
import { LegacyBackup } from '../model/LegacyBackup';
import { DailyNoteService } from './DailyNoteService';
import { UserService } from './UserService';
import { Logger } from '../common/Logger';

export class BackupResult {
  ok: boolean = false;
  message: string = '';
}

export class BackupService {
  private static instance: BackupService = new BackupService();
  private busy: boolean = false;

  static getInstance(): BackupService { return BackupService.instance; }

  private readTable(name: string, rs: relationalStore.ResultSet): BackupTable {
    const table: BackupTable = new BackupTable();
    table.name = name;
    try {
      while (rs.goToNextRow()) {
        const row: Record<string, BackupCell> = {};
        for (let i: number = 0; i < rs.columnNames.length; i++) {
          const value: relationalStore.ValueType = rs.getValue(i);
          if (value !== null && typeof value !== 'string' && typeof value !== 'number') {
            throw new Error('备份遇到不支持的数据类型');
          }
          row[rs.columnNames[i]] = value as BackupCell;
        }
        if (name === 'user_accounts') {
          row['cookie_account_token'] = '';
          row['cookie_ltoken_ltuid'] = '';
          row['cookie_stoken_stuid'] = '';
        }
        table.rows.push(row);
      }
    } finally { rs.close(); }
    return table;
  }

  private async capture(): Promise<BackupSnapshot> {
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    const snapshot: BackupSnapshot = new BackupSnapshot();
    snapshot.schemaVersion = store.version;
    snapshot.exportedAt = Math.floor(Date.now() / 1000);
    snapshot.preferences = PreferencesStore.exportPortable();
    const transaction: relationalStore.Transaction = await store.createTransaction();
    try {
      for (const name of BackupSnapshotValidator.tablesForSchema(snapshot.schemaVersion)) {
        snapshot.tables.push(this.readTable(name, await transaction.querySql(`SELECT * FROM ${name}`)));
      }
      await transaction.commit();
    } catch (e) { await transaction.rollback(); throw new Error((e as Error).message); }
    for (const row of this.table(snapshot, 'user_accounts').rows) {
      const credential: BackupCredential = new BackupCredential();
      credential.userId = Number(row['id']);
      credential.cookie = await TokenVault.loadCookie(credential.userId, true);
      snapshot.credentials.push(credential);
    }
    BackupSnapshotValidator.validate(snapshot);
    return snapshot;
  }

  async buildBackupJson(): Promise<string> {
    if (this.busy) { throw new Error('备份或还原正在进行'); }
    if (PreferencesStore.getBackupJournal().length > 0) { throw new Error('上次还原需要恢复，请重启应用'); }
    this.busy = true;
    try { return JSON.stringify(await this.capture(), null, 2); }
    finally { this.busy = false; }
  }

  private table(snapshot: BackupSnapshot, name: string): BackupTable {
    for (const table of snapshot.tables) { if (table.name === name) { return table; } }
    throw new Error(`缺少备份数据表 ${name}`);
  }

  private async validateDatabase(snapshot: BackupSnapshot): Promise<void> {
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    if (snapshot.schemaVersion > store.version) { throw new Error('备份来自更新版本，请先更新应用'); }
    for (const table of snapshot.tables) {
      const rs: relationalStore.ResultSet = await store.querySql(`SELECT * FROM ${table.name} LIMIT 0`);
      const columns: string[] = rs.columnNames;
      rs.close();
      for (const row of table.rows) {
        for (const column of Object.keys(row)) {
          if (columns.indexOf(column) < 0) { throw new Error(`备份字段不受支持：${table.name}.${column}`); }
        }
      }
    }
    this.checkReference(snapshot, 'user_game_roles', 'user_id', 'user_accounts');
    this.checkReference(snapshot, 'daily_notes', 'user_id', 'user_accounts');
    this.checkReference(snapshot, 'sign_in_info', 'user_id', 'user_accounts');
    this.checkReference(snapshot, 'gacha_items', 'archive_id', 'gacha_archives');
    this.checkReference(snapshot, 'achievement_entries', 'archive_id', 'achievement_archives');
    this.checkReference(snapshot, 'cultivate_entries', 'project_id', 'cultivate_projects');
    this.checkReference(snapshot, 'cultivate_items', 'entry_id', 'cultivate_entries');
    this.checkReference(snapshot, 'cultivate_inventory', 'project_id', 'cultivate_projects');
    if (snapshot.schemaVersion >= 7) {
      this.checkReference(snapshot, 'backpack_items', 'archive_id', 'backpack_archives');
    }
    for (const row of this.table(snapshot, 'challenge_records').rows) {
      if (!/^\d{9,10}$/.test(String(row['uid'])) ||
        ['cn_gf01', 'cn_qd01', 'os_usa', 'os_euro', 'os_asia', 'os_cht'].indexOf(String(row['region'])) < 0 ||
        ['abyss', 'role_combat', 'hard_challenge'].indexOf(String(row['kind'])) < 0 ||
        !Number.isSafeInteger(row['schedule_id']) || Number(row['schedule_id']) <= 0) {
        throw new Error('挑战历史归属或期数无效');
      }
    }
  }

  private checkReference(snapshot: BackupSnapshot, child: string, key: string, parent: string): void {
    const ids: Set<number> = new Set<number>();
    for (const row of this.table(snapshot, parent).rows) { ids.add(Number(row['id'])); }
    for (const row of this.table(snapshot, child).rows) {
      if (!ids.has(Number(row[key]))) { throw new Error(`备份包含失去归属的数据：${child}`); }
    }
  }

  /** Old vault entries stay intact until commit. Never overwrite credentials at an existing ID. */
  private remapUsers(snapshot: BackupSnapshot, nextId: number): void {
    const ids: Map<number, number> = new Map<number, number>();
    let selected: number = 0;
    for (const row of this.table(snapshot, 'user_accounts').rows) {
      ids.set(Number(row['id']), ++nextId);
      row['id'] = nextId;
      row['cookie_account_token'] = '';
      row['cookie_ltoken_ltuid'] = '';
      row['cookie_stoken_stuid'] = '';
      if (row['is_selected'] === 1 && selected === 0) { selected = nextId; } else { row['is_selected'] = 0; }
    }
    for (const name of ['user_game_roles', 'daily_notes', 'sign_in_info']) {
      for (const row of this.table(snapshot, name).rows) { row['user_id'] = ids.get(Number(row['user_id']))!; }
    }
    for (const credential of snapshot.credentials) { credential.userId = ids.get(credential.userId)!; }
    const prefs: Record<string, string | number | boolean> = {};
    for (const key of Object.keys(snapshot.preferences)) {
      if (key.indexOf('dailynote.tracked_') === 0) {
        const id: number | undefined = ids.get(Number(key.substring('dailynote.tracked_'.length)));
        if (id !== undefined) { prefs[`dailynote.tracked_${id}`] = snapshot.preferences[key]; }
      } else { prefs[key] = snapshot.preferences[key]; }
    }
    prefs[PreferencesStore.KEY_CURRENT_USER_ID] = selected;
    let uid: string = '';
    for (const row of this.table(snapshot, 'user_game_roles').rows) {
      if (row['user_id'] === selected && row['is_default'] === 1) { uid = String(row['game_uid']); }
    }
    prefs[PreferencesStore.KEY_CURRENT_UID] = uid;
    snapshot.preferences = prefs;
  }

  /** Called before restoring any login session after process startup. */
  async recoverInterruptedRestore(): Promise<void> {
    if (this.busy) { return; }
    const text: string = PreferencesStore.getBackupJournal();
    if (text.length === 0) { return; }
    const journal: BackupRecovery = JSON.parse(text) as BackupRecovery;
    if (journal.marker.length === 0 || !Array.isArray(journal.oldUsers) || !Array.isArray(journal.newUsers)) {
      throw new Error('备份恢复日志无效');
    }
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.getStore().querySql(
      'SELECT marker FROM backup_recovery WHERE id=1');
    let committed: boolean = false;
    try { committed = rs.goToFirstRow() && rs.getString(0) === journal.marker; } finally { rs.close(); }
    await PreferencesStore.replacePortable(committed ? journal.nextPreferences : journal.oldPreferences);
    for (const id of (committed ? journal.oldUsers : journal.newUsers)) { await TokenVault.removeCookie(id); }
    await PreferencesStore.saveBackupJournal('');
  }

  async restoreFromText(text: string): Promise<BackupResult> {
    const result: BackupResult = new BackupResult();
    if (this.busy) { result.message = '备份或还原正在进行'; return result; }
    if (PreferencesStore.getBackupJournal().length > 0) { result.message = '上次还原需要恢复，请重启应用'; return result; }
    this.busy = true;
    let transaction: relationalStore.Transaction | undefined = undefined;
    const staged: number[] = [];
    let oldPrefs: Record<string, string | number | boolean> = {};
    let prefsChanged: boolean = false;
    let journalSaved: boolean = false;
    let committed: boolean = false;
    const daily: DailyNoteService = DailyNoteService.getInstance();
    const wasRunning: boolean = daily.isTimerRunning();
    daily.stopAutoRefresh();
    try {
      oldPrefs = PreferencesStore.exportPortable();
      const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
      const parsed: Object = JSON.parse(text) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) { throw new Error('无效备份'); }
      const root: Record<string, Object> = parsed as Record<string, Object>;
      const legacy: boolean = root['version'] === 1;
      const snapshot: BackupSnapshot = legacy ? LegacyBackup.convert(parsed, store.version) : parsed as BackupSnapshot;
      BackupSnapshotValidator.validate(snapshot);
      // v1 never had these sections: importing it must not erase newer cultivation/history data.
      if (legacy) {
        for (const name of ['cultivate_projects', 'cultivate_entries', 'cultivate_items', 'cultivate_inventory', 'abyss_history',
          'role_combat_history', 'hard_challenge_history', 'challenge_records', 'act_calendar_entries', 'announcements']) {
          this.table(snapshot, name).rows = this.readTable(name, await store.querySql(`SELECT * FROM ${name}`)).rows;
        }
      }
      await this.validateDatabase(snapshot);
      transaction = await store.createTransaction({ transactionType: relationalStore.TransactionType.IMMEDIATE });
      const oldUsers: BackupTable = this.readTable('user_accounts', await transaction.querySql('SELECT * FROM user_accounts'));
      const maxRs: relationalStore.ResultSet = await transaction.querySql(
        "SELECT MAX(value) AS max_id FROM (SELECT COALESCE(MAX(id),0) AS value FROM user_accounts UNION ALL SELECT seq AS value FROM sqlite_sequence WHERE name='user_accounts')");
      let nextId: number = 0;
      try { if (maxRs.goToFirstRow()) { nextId = maxRs.getLong(0); } } finally { maxRs.close(); }
      this.remapUsers(snapshot, nextId);
      const journal: BackupRecovery = new BackupRecovery();
      journal.marker = `${Date.now()}-${Math.random()}`;
      journal.oldPreferences = oldPrefs;
      journal.nextPreferences = snapshot.preferences;
      journal.oldUsers = oldUsers.rows.map((row: Record<string, BackupCell>): number => Number(row['id']));
      journal.newUsers = snapshot.credentials.map((credential: BackupCredential): number => credential.userId);
      journalSaved = true;
      await PreferencesStore.saveBackupJournal(JSON.stringify(journal));
      for (const credential of snapshot.credentials) {
        staged.push(credential.userId);
        if (credential.cookie.length > 0) { await TokenVault.saveCookie(credential.userId, credential.cookie); }
      }
      // Child-first deletion and parent-first insertion also work when SQLite foreign keys
      // are enabled. A pre-v7 payload intentionally never touches the Backpack tables.
      const names: string[] = BackupSnapshotValidator.tablesForSchema(snapshot.schemaVersion);
      for (let i: number = names.length - 1; i >= 0; i--) {
        await transaction.delete(new relationalStore.RdbPredicates(names[i]));
      }
      for (const name of names) {
        const table: BackupTable = this.table(snapshot, name);
        for (const row of table.rows) {
          const values: relationalStore.ValuesBucket = {};
          for (const key of Object.keys(row)) { values[key] = row[key]; }
          await transaction.insert(table.name, values);
        }
      }
      await transaction.delete(new relationalStore.RdbPredicates('backup_recovery'));
      await transaction.insert('backup_recovery', { 'id': 1, 'marker': journal.marker });
      prefsChanged = true;
      await PreferencesStore.replacePortable(snapshot.preferences);
      await transaction.commit();
      transaction = undefined;
      committed = true;
      for (const user of oldUsers.rows) { await TokenVault.removeCookie(Number(user['id'])); }
      await PreferencesStore.saveBackupJournal('');
      journalSaved = false;
      await UserService.getInstance().reloadLocalSession();
      AppStorage.setOrCreate<number>('dailyNoteVersion', Date.now());
      result.ok = true;
      result.message = legacy ? '旧版备份已还原；已有养成、挑战历史和背包存档保留，请重启应用' :
        (snapshot.schemaVersion < 7 ? '备份已还原；已有背包存档保留，请重启应用' : '全部本地数据已还原，请重启应用');
    } catch (e) {
      let recovered: boolean = true;
      if (transaction !== undefined) {
        try { await transaction.rollback(); } catch (rollbackError) { recovered = false; }
      }
      if (!committed && recovered) {
        if (prefsChanged) {
          try { await PreferencesStore.replacePortable(oldPrefs); } catch (prefsError) { recovered = false; }
        }
        for (const id of staged) {
          try { await TokenVault.removeCookie(id); } catch (vaultError) { recovered = false; }
        }
      }
      if (journalSaved && recovered) {
        try { await PreferencesStore.saveBackupJournal(''); } catch (journalError) { recovered = false; }
      }
      result.ok = committed;
      result.message = !recovered ? '还原恢复待完成，请重启应用后重试' : (committed ? '数据已还原，请重启应用刷新会话' : `未还原：${(e as Error).message}`);
      Logger.warn('BackupService', committed ? 'post-restore session refresh failed' : 'restore rejected or rolled back');
    } finally {
      this.busy = false;
      if (wasRunning && !committed && PreferencesStore.getBackupJournal().length === 0) {
        daily.startAutoRefresh(PreferencesStore.getRefreshIntervalMinutes());
      }
    }
    return result;
  }
}
