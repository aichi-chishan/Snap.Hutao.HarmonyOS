/**
 * RelationalStoreHelper.ets
 * relationalStore(SQLite) 封装：建库 snap_hutao.db + 全部表结构 + 版本升级预留 + 通用 CRUD 工具。
 * 注意：RdbStore 实例不跨线程，所有查询走异步方法，调用侧在 UI/Service 线程执行。
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../../common/Logger';

const TAG: string = 'DB';

export class RelationalStoreHelper {
  static readonly DB_NAME: string = 'snap_hutao.db';
  private static rdbStore: relationalStore.RdbStore | undefined = undefined;

  /** 初始化数据库（应用启动时调用一次） */
  static async init(context: common.Context): Promise<void> {
    if (RelationalStoreHelper.rdbStore !== undefined) {
      return;
    }
    const storeConfig: relationalStore.StoreConfig = {
      name: RelationalStoreHelper.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, storeConfig);
    RelationalStoreHelper.rdbStore = store;
    await RelationalStoreHelper.createTables(store);
    Logger.info(TAG, 'database initialized');
  }

  /** 是否已完成初始化（Form 卡片进程可能早于 EntryAbility 启动，调用前需判断） */
  static isReady(): boolean {
    return RelationalStoreHelper.rdbStore !== undefined;
  }

  static getStore(): relationalStore.RdbStore {
    if (RelationalStoreHelper.rdbStore === undefined) {
      throw new Error('database not initialized');
    }
    return RelationalStoreHelper.rdbStore;
  }

  static async executeSql(sql: string): Promise<void> {
    await RelationalStoreHelper.getStore().executeSql(sql);
  }

  private static async createTables(store: relationalStore.RdbStore): Promise<void> {
    const statements: string[] = [
      `CREATE TABLE IF NOT EXISTS user_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mid TEXT,
        aid TEXT,
        is_oversea INTEGER DEFAULT 0,
        cookie_account_token TEXT,
        cookie_ltoken_ltuid TEXT,
        cookie_stoken_stuid TEXT,
        display_nickname TEXT,
        avatar TEXT,
        is_selected INTEGER DEFAULT 0,
        created_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS user_game_roles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        game_uid TEXT,
        region TEXT,
        nickname TEXT,
        level INTEGER,
        is_default INTEGER DEFAULT 0,
        is_chosen INTEGER DEFAULT 0
      )`,
      `CREATE TABLE IF NOT EXISTS gacha_archives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT UNIQUE,
        is_selected INTEGER DEFAULT 0
      )`,
      `CREATE TABLE IF NOT EXISTS gacha_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        archive_id INTEGER,
        gacha_type INTEGER,
        item_id INTEGER,
        count INTEGER DEFAULT 1,
        time TEXT,
        name TEXT,
        item_type TEXT,
        rank_type INTEGER,
        gacha_id TEXT
      )`,
      `CREATE INDEX IF NOT EXISTS idx_gacha_items_archive_type ON gacha_items (archive_id, gacha_type)`,
      `CREATE TABLE IF NOT EXISTS abyss_history (
        schedule_id INTEGER PRIMARY KEY,
        start_time INTEGER,
        end_time INTEGER,
        total_star INTEGER,
        raw_json TEXT,
        record_time INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS daily_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        uid TEXT,
        current_resin INTEGER DEFAULT 0,
        max_resin INTEGER DEFAULT 0,
        resin_recovery_time TEXT,
        finished_task_num INTEGER DEFAULT 0,
        total_task_num INTEGER DEFAULT 0,
        is_extra_task_reward_received INTEGER DEFAULT 0,
        remain_resin_discount_num INTEGER DEFAULT 0,
        limit_resin_discount_num INTEGER DEFAULT 0,
        current_home_coin INTEGER DEFAULT 0,
        max_home_coin INTEGER DEFAULT 0,
        home_coin_recovery_time TEXT,
        current_expedition_num INTEGER DEFAULT 0,
        max_expedition_num INTEGER DEFAULT 0,
        expeditions_json TEXT,
        transformer_json TEXT,
        archon_json TEXT,
        resin_notify_threshold INTEGER DEFAULT 120,
        home_coin_notify_threshold INTEGER DEFAULT 1800,
        notify_flags INTEGER DEFAULT 31,
        refresh_time INTEGER DEFAULT 0
      )`,
      `CREATE INDEX IF NOT EXISTS idx_daily_notes_user_uid ON daily_notes (user_id, uid)`,
      `CREATE TABLE IF NOT EXISTS sign_in_info (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        act_id TEXT,
        month TEXT,
        signed_days INTEGER DEFAULT 0,
        rewards_json TEXT,
        updated_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS act_calendar_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uid TEXT,
        type TEXT,
        name TEXT,
        start_time INTEGER,
        end_time INTEGER,
        extra_json TEXT
      )`,
      `CREATE TABLE IF NOT EXISTS announcements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT,
        title TEXT,
        time INTEGER,
        url TEXT,
        content_json TEXT,
        updated_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS achievement_archives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        is_selected INTEGER DEFAULT 0,
        created_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS achievement_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        archive_id INTEGER,
        ach_id INTEGER,
        current INTEGER DEFAULT 1,
        timestamp INTEGER DEFAULT 0
      )`,
      `CREATE INDEX IF NOT EXISTS idx_achievement_entries_archive ON achievement_entries (archive_id)`,
    ];
    for (let i = 0; i < statements.length; i++) {
      await store.executeSql(statements[i]);
    }
    // 迁移：gacha_items 增加 schedule_id（千星奇域 + UIGF v4.2 导出需要；已存在时忽略报错）
    try {
      await store.executeSql('ALTER TABLE gacha_items ADD COLUMN schedule_id INTEGER DEFAULT 0');
    } catch (e) {
      // 列已存在
    }
    // 历史数据清理：删除空 uid 祈愿归档（曾因未登录时装载误建，覆盖默认 UID 逻辑）
    try {
      await store.executeSql(
        `DELETE FROM gacha_items WHERE archive_id IN (SELECT id FROM gacha_archives WHERE uid = '')`);
      await store.executeSql(`DELETE FROM gacha_archives WHERE uid = ''`);
    } catch (e) {
      Logger.warn(TAG, 'cleanup empty gacha archives skip');
    }
    // 版本升级预留：空实现挂载点，后续结构变更在此按版本迁移。
    await RelationalStoreHelper.upgradeIfNeeded(store);
    Logger.info(TAG, 'tables ready');
  }

  /** 版本升级预留：当前为 1，无迁移逻辑 */
  private static async upgradeIfNeeded(store: relationalStore.RdbStore): Promise<void> {
    try {
      const v: number = store.version;
      if (v < 1) {
        store.version = 1;
      }
    } catch (e) {
      Logger.warn(TAG, 'skip version check');
    }
  }

  /** 插入一行，返回自增主键 */
  static async insert(table: string, values: relationalStore.ValuesBucket): Promise<number> {
    return RelationalStoreHelper.getStore().insert(table, values);
  }

  /** 批量插入（无 upsert，遵循环），返回受影响行数 */
  static async batchInsert(table: string, values: Array<relationalStore.ValuesBucket>): Promise<number> {
    return RelationalStoreHelper.getStore().batchInsert(table, values);
  }

  /** 更新，返回受影响行数 */
  static async update(table: string, values: relationalStore.ValuesBucket,
    predicates: relationalStore.RdbPredicates): Promise<number> {
    return RelationalStoreHelper.getStore().update(values, predicates);
  }

  /** 删除，返回受影响行数 */
  static async delete(table: string, predicates: relationalStore.RdbPredicates): Promise<number> {
    return RelationalStoreHelper.getStore().delete(predicates);
  }

  /** 查询，返回结果集（调用方负责 close） */
  static async query(predicates: relationalStore.RdbPredicates): Promise<relationalStore.ResultSet> {
    return RelationalStoreHelper.getStore().query(predicates);
  }
}
