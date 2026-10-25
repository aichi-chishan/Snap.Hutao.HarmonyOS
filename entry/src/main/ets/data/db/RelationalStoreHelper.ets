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
  private static initializing: Promise<void> | undefined = undefined;

  /** 初始化数据库（应用启动时调用一次） */
  static async init(context: common.Context): Promise<void> {
    if (RelationalStoreHelper.rdbStore !== undefined) {
      return;
    }
    if (RelationalStoreHelper.initializing === undefined) {
      RelationalStoreHelper.initializing = RelationalStoreHelper.open(context);
    }
    const pending: Promise<void> = RelationalStoreHelper.initializing;
    try { await pending; }
    finally {
      if (RelationalStoreHelper.initializing === pending) { RelationalStoreHelper.initializing = undefined; }
    }
  }

  private static async open(context: common.Context): Promise<void> {
    const storeConfig: relationalStore.StoreConfig = {
      name: RelationalStoreHelper.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };
    Logger.info(TAG, 'opening rdb store');
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, storeConfig);
    Logger.info(TAG, 'rdb store opened');
    await RelationalStoreHelper.createTables(store);
    Logger.info(TAG, 'createTables done');
    RelationalStoreHelper.rdbStore = store;
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
        status INTEGER NOT NULL DEFAULT 3,
        timestamp INTEGER DEFAULT 0
      )`,
      `CREATE INDEX IF NOT EXISTS idx_achievement_entries_archive ON achievement_entries (archive_id)`,
    ];
    for (let i = 0; i < statements.length; i++) {
      await store.executeSql(statements[i]);
    }
    // 有序版本迁移（新增结构/数据修复：DB_VERSION+1，并在 MIGRATIONS 末尾追加迁移）
    await RelationalStoreHelper.migrate(store);
    Logger.info(TAG, 'tables ready');
  }

  /** 解析 "ALTER TABLE <t> ADD COLUMN <c> ..."；非该形态返回空数组 */
  private static parseAlterAddColumn(step: string): string[] {
    const prefix: string = 'ALTER TABLE ';
    const middle: string = ' ADD COLUMN ';
    if (!step.startsWith(prefix)) {
      return [];
    }
    const rest: string = step.substring(prefix.length);
    const mid: number = rest.indexOf(middle);
    if (mid <= 0) {
      return [];
    }
    const table: string = rest.substring(0, mid).trim();
    const column: string = rest.substring(mid + middle.length).trim().split(' ')[0];
    if (table.length === 0 || column.length === 0) {
      return [];
    }
    return [table, column];
  }

  /** 表是否已存在指定列（PRAGMA table_info；ALTER 前预检，避免依赖错误路径）。
   *  任何查询异常都返回 false 回退为直接执行语句（与旧行为一致）。 */
  private static async hasColumn(store: relationalStore.RdbStore, table: string, column: string): Promise<boolean> {
    try {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(table)) {
        return false;
      }
      const rs: relationalStore.ResultSet = await store.querySql(`PRAGMA table_info(${table})`);
      try {
        const nameIndex: number = rs.getColumnIndex('name');
        while (rs.goToNextRow()) {
          if (rs.getString(nameIndex) === column) {
            return true;
          }
        }
        return false;
      } finally {
        rs.close();
      }
    } catch (e) {
      Logger.warn(TAG, `hasColumn ${table}.${column} probe fail: ${(e as Error).message}`);
      return false;
    }
  }

  /** 迁移语句超时兜底：个别运行时（API26 模拟器 rdb）在事务内出错的 executeSql 永不结算，
   *  超时显式报错回滚，保证应用能启动并暴露真实原因，而不是无限“数据库未初始化”。
   *  环境（如宿主测试 VM）未提供 setTimeout 时不启用超时，直接透传原 Promise。 */
  private static withTimeout<T>(task: Promise<T>, ms: number, label: string): Promise<T> {
    if (typeof setTimeout !== 'function') {
      return task;
    }
    return new Promise<T>((resolve, reject): void => {
      const timerId: number = setTimeout((): void => {
        reject(new Error(`数据库语句超时（${ms / 1000}s）：${label}`));
      }, ms);
      task.then((value: T): void => {
        clearTimeout(timerId);
        resolve(value);
      }, (reason: Error): void => {
        clearTimeout(timerId);
        reject(reason);
      });
    });
  }

  /** 当前数据库结构版本（每次结构变更 +1，并在 MIGRATIONS 末尾追加对应迁移） */
  private static readonly DB_VERSION: number = 8;

  /**
   * 有序迁移列表：MIGRATIONS[i] 把版本 i+1 升到 i+2。
   * 仅允许已存在列的 ALTER 重试；其他错误回滚，版本与 DDL 在同一事务提交。
   */
  private static readonly MIGRATIONS: string[][] = [
    [
      // v1 → v2：gacha_items 增加 schedule_id（千星奇域 + UIGF v4.2 导出需要）
      'ALTER TABLE gacha_items ADD COLUMN schedule_id INTEGER DEFAULT 0',
    ],
    [
      // v2 → v3：历史数据清理——删除空 uid 祈愿归档（曾因未登录时装载误建，覆盖默认 UID 逻辑）
      `DELETE FROM gacha_items WHERE archive_id IN (SELECT id FROM gacha_archives WHERE uid = '')`,
      `DELETE FROM gacha_archives WHERE uid = ''`,
    ],
    [
      // v3 → v4：养成计划持久化（项目/条目/材料勾选，对齐 Windows CultivateProject/Entry/Item）
      `CREATE TABLE IF NOT EXISTS cultivate_projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS cultivate_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        avatar_id INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT '',
        level INTEGER NOT NULL DEFAULT 0,
        target_level INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS cultivate_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT '',
        count INTEGER NOT NULL DEFAULT 0,
        finished INTEGER NOT NULL DEFAULT 0
      )`,
    ],
    [
      // v4 → v5：剧诗/幽境危战期数历史持久化（列与 abyss_history 同款，按 schedule_id UPSERT；
      // raw_json 存 API 原始 JSON，回看时模型 fromJson 完整重建）
      `CREATE TABLE IF NOT EXISTS role_combat_history (
        schedule_id INTEGER PRIMARY KEY,
        start_time INTEGER,
        end_time INTEGER,
        raw_json TEXT,
        record_time INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS hard_challenge_history (
        schedule_id INTEGER PRIMARY KEY,
        start_time INTEGER,
        end_time INTEGER,
        raw_json TEXT,
        record_time INTEGER
      )`,
    ],
    [
      // v5 → v6：新记录按玩法、UID、区服、期数隔离。旧表无身份，保留原样供显式恢复。
      `CREATE TABLE IF NOT EXISTS challenge_records (
        kind TEXT NOT NULL,
        uid TEXT NOT NULL,
        region TEXT NOT NULL,
        schedule_id INTEGER NOT NULL,
        start_time INTEGER NOT NULL DEFAULT 0,
        end_time INTEGER NOT NULL DEFAULT 0,
        total_star INTEGER NOT NULL DEFAULT 0,
        raw_json TEXT NOT NULL,
        record_time INTEGER NOT NULL,
        PRIMARY KEY (kind, uid, region, schedule_id)
      )`,
      `CREATE TABLE IF NOT EXISTS backup_recovery (
        id INTEGER PRIMARY KEY CHECK(id=1),
        marker TEXT NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS cultivate_inventory (
        project_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        count INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (project_id, item_id)
      )`,
      'ALTER TABLE achievement_entries ADD COLUMN status INTEGER NOT NULL DEFAULT 3',
      'ALTER TABLE daily_notes ADD COLUMN raw_json TEXT NOT NULL DEFAULT \'\'',
    ],
    [
      // v6 → v7：本地背包存档/UIIF 导入；不读取游戏进程或账户凭据。
      `CREATE TABLE IF NOT EXISTS backpack_archives (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        uid TEXT NOT NULL,
        is_selected INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT '',
        document_json TEXT NOT NULL
      )`,
      `CREATE TABLE IF NOT EXISTS backpack_items (
        archive_id INTEGER NOT NULL,
        instance_id TEXT NOT NULL,
        item_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        category INTEGER NOT NULL DEFAULT 9,
        raw_json TEXT NOT NULL,
        PRIMARY KEY (archive_id, instance_id),
        FOREIGN KEY (archive_id) REFERENCES backpack_archives(id) ON DELETE CASCADE
      )`,
    ],
    [
      // v7 → v8：保留养成编辑输入；旧计划为空，编辑时显式重新确认，不推断历史进度。
      "ALTER TABLE cultivate_entries ADD COLUMN input_json TEXT NOT NULL DEFAULT ''",
    ],
  ];

  /** 版本驱动的迁移执行器 */
  private static async migrate(store: relationalStore.RdbStore): Promise<void> {
    let v: number = 1;
    try {
      v = store.version;
    } catch (e) {
      Logger.warn(TAG, 'read db version fail, assume 1');
    }
    if (v < 1) {
      v = 1;
    }
    Logger.info(TAG, `migrate from v${v} to v${RelationalStoreHelper.DB_VERSION}`);
    while (v < RelationalStoreHelper.DB_VERSION) {
      const steps: string[] = RelationalStoreHelper.MIGRATIONS[v - 1] ?? [];
      Logger.info(TAG, `migrate v${v}->v${v + 1} steps=${steps.length}`);
      store.beginTransaction();
      try {
        for (let i = 0; i < steps.length; i++) {
          const step: string = steps[i];
          // ALTER 前预检列存在性（新库建表已含新增列时直接跳过）：
          // 部分 rdb 运行时在事务内出错的 executeSql 永不结算，不能依赖 duplicate column 报错路径。
          const alter: string[] = RelationalStoreHelper.parseAlterAddColumn(step);
          if (alter.length === 2) {
            const already: boolean = await RelationalStoreHelper.hasColumn(store, alter[0], alter[1]);
            if (already) {
              Logger.info(TAG, `migrate v${v}->v${v + 1} skip: ${alter[0]}.${alter[1]} already exists`);
              continue;
            }
          }
          try {
            await RelationalStoreHelper.withTimeout(store.executeSql(step), 8000,
              `v${v}->v${v + 1} step ${i + 1}: ${step.substring(0, 48)}`);
          } catch (e) {
            // 预检不可用（如宿主测试环境）时，允许 ALTER 报 duplicate column（列已存在=目标状态）
            const message: string = (e as Error).message.toLowerCase();
            if (alter.length !== 2 || !message.includes('duplicate column')) {
              throw new Error((e as Error).message);
            }
            Logger.warn(TAG, `migrate v${v}->v${v + 1} tolerate duplicate column: ${alter[0]}.${alter[1]}`);
          }
        }
        store.version = v + 1;
        store.commit();
        v += 1;
      } catch (e) {
        store.rollBack();
        throw new Error(`数据库升级 v${v} 失败：${(e as Error).message}`);
      }
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
