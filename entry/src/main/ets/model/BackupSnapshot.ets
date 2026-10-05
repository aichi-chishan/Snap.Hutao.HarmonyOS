/** Portable, explicitly versioned database snapshot. No device identity or signing material. */
import { BackpackItem } from './BackpackData';
import { UIIFCodec } from './UIIFCodec';

export type BackupCell = string | number | null;

export class BackupTable {
  name: string = '';
  rows: Record<string, BackupCell>[] = [];
}

export class BackupCredential {
  userId: number = 0;
  cookie: string = '';
}

export class BackupSnapshot {
  app: string = 'snaphutao-harmonyos-backup';
  version: number = 2;
  schemaVersion: number = 0;
  exportedAt: number = 0;
  tables: BackupTable[] = [];
  credentials: BackupCredential[] = [];
  preferences: Record<string, string | number | boolean> = {};
}

/** Recovery journal contains only portable preferences and local record IDs, never credentials. */
export class BackupRecovery {
  marker: string = '';
  oldPreferences: Record<string, string | number | boolean> = {};
  nextPreferences: Record<string, string | number | boolean> = {};
  oldUsers: number[] = [];
  newUsers: number[] = [];
}

export class BackupSnapshotValidator {
  /** Transport bound only: draft versions/domain values are decoded when opened for editing. */
  static readonly MAX_CULTIVATION_INPUT_LENGTH: number = 64 * 1024;

  static readonly TABLES: string[] = [
    'user_accounts', 'user_game_roles', 'gacha_archives', 'gacha_items',
    'achievement_archives', 'achievement_entries', 'cultivate_projects',
    'cultivate_entries', 'cultivate_items', 'cultivate_inventory', 'daily_notes', 'sign_in_info',
    'act_calendar_entries', 'announcements', 'abyss_history',
    'role_combat_history', 'hard_challenge_history', 'challenge_records',
    'backpack_archives', 'backpack_items',
  ];

  /** Old snapshots have no Backpack section and must never replace the local archives. */
  static tablesForSchema(schemaVersion: number): string[] {
    return BackupSnapshotValidator.TABLES.filter((name: string): boolean =>
      schemaVersion >= 7 || (name !== 'backpack_archives' && name !== 'backpack_items'));
  }

  private static integer(value: BackupCell, min: number, max: number = Number.MAX_SAFE_INTEGER): boolean {
    return typeof value === 'number' && Number.isSafeInteger(value) && value >= min && value <= max;
  }

  private static text(value: BackupCell, max: number, required: boolean = true): boolean {
    return typeof value === 'string' && value.length <= max && (!required || value.trim().length > 0);
  }

  private static jsonObject(value: BackupCell): boolean {
    if (!BackupSnapshotValidator.text(value, 16 * 1024 * 1024)) { return false; }
    try {
      const parsed: Object = JSON.parse(value as string) as Object;
      return parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed);
    } catch (e) { return false; }
  }

  private static validateBackpack(snapshot: BackupSnapshot): void {
    const archives: Set<number> = new Set<number>();
    const archiveItems: Map<number, BackpackItem[]> = new Map<number, BackpackItem[]>();
    const instances: Set<string> = new Set<string>();
    let selected: number = 0;
    for (const table of snapshot.tables) {
      if (table.name !== 'backpack_archives') { continue; }
      for (const row of table.rows) {
        if (!BackupSnapshotValidator.integer(row['id'], 1) || archives.has(row['id'] as number) ||
          !BackupSnapshotValidator.text(row['name'], 80) ||
          typeof row['uid'] !== 'string' || !/^[1-9]\d{8,9}$/.test(row['uid'] as string) ||
          !BackupSnapshotValidator.integer(row['is_selected'], 0, 1) ||
          !BackupSnapshotValidator.integer(row['created_at'], 0) ||
          !BackupSnapshotValidator.integer(row['updated_at'], 0) ||
          !BackupSnapshotValidator.text(row['source'], 200, false) ||
          !BackupSnapshotValidator.jsonObject(row['document_json'])) {
          throw new Error('背包存档字段无效或标识重复');
        }
        archives.add(row['id'] as number);
        archiveItems.set(row['id'] as number, []);
        selected += row['is_selected'] as number;
      }
    }
    if (selected > 1) { throw new Error('背包存档只能选择一个'); }
    for (const table of snapshot.tables) {
      if (table.name !== 'backpack_items') { continue; }
      for (const row of table.rows) {
        if (!BackupSnapshotValidator.integer(row['archive_id'], 1) || !archives.has(row['archive_id'] as number) ||
          !BackupSnapshotValidator.text(row['instance_id'], 160) ||
          !BackupSnapshotValidator.integer(row['item_id'], 1, 4294967295) ||
          typeof row['kind'] !== 'string' || ['weapon', 'reliquary', 'material', 'furniture'].indexOf(row['kind'] as string) < 0 ||
          !BackupSnapshotValidator.integer(row['category'], 0, 9) ||
          !BackupSnapshotValidator.jsonObject(row['raw_json'])) {
          throw new Error('背包条目字段或存档归属无效');
        }
        const key: string = `${row['archive_id']}:${row['instance_id']}`;
        if (instances.has(key)) { throw new Error('背包条目标识重复'); }
        instances.add(key);
        const item: BackpackItem = new BackpackItem();
        item.archiveId = row['archive_id'] as number;
        item.instanceId = row['instance_id'] as string;
        item.itemId = row['item_id'] as number;
        item.kind = row['kind'] as string;
        item.category = row['category'] as number;
        item.rawJson = row['raw_json'] as string;
        archiveItems.get(item.archiveId)!.push(item);
      }
    }
    for (const table of snapshot.tables) {
      if (table.name !== 'backpack_archives') { continue; }
      for (const row of table.rows) {
        // The same lossless codec is used by repository writes: validates the document
        // UID, raw payloads, categories, duplicate GUIDs and duplicate stackable IDs.
        UIIFCodec.validateSnapshot(row['uid'] as string, row['document_json'] as string,
          archiveItems.get(row['id'] as number)!);
      }
    }
  }

  static portableKey(key: string): boolean {
    if (/device|cookie|token|secret|password|authkey|formId|form_id/i.test(key)) {
      return false;
    }
    return /^(app\.|theme\.|home\.|dailynote\.|signin\.|gacha\.|cultivation\.|risk\.|game\.|launcher\.|data\.|resource\.|wallpaper\.)/.test(key);
  }

  static validate(snapshot: BackupSnapshot): void {
    if (snapshot === null || typeof snapshot !== 'object' ||
      snapshot.app !== 'snaphutao-harmonyos-backup' || snapshot.version !== 2) {
      throw new Error('不支持的备份格式或版本');
    }
    if (!Number.isSafeInteger(snapshot.schemaVersion) || snapshot.schemaVersion < 1 ||
      !Array.isArray(snapshot.tables) || !Array.isArray(snapshot.credentials) ||
      snapshot.preferences === null || typeof snapshot.preferences !== 'object' || Array.isArray(snapshot.preferences)) {
      throw new Error('备份结构不完整');
    }
    const allowed: string[] = BackupSnapshotValidator.tablesForSchema(snapshot.schemaVersion);
    const seen: Set<string> = new Set<string>();
    const users: Set<number> = new Set<number>();
    for (const table of snapshot.tables) {
      if (table === null || allowed.indexOf(table.name) < 0 ||
        seen.has(table.name) || !Array.isArray(table.rows)) {
        throw new Error('备份含未知、重复或损坏的数据表');
      }
      seen.add(table.name);
      for (const row of table.rows) {
        if (row === null || typeof row !== 'object' || Array.isArray(row) || Object.keys(row).length === 0) {
          throw new Error('备份含无效数据行');
        }
        for (const column of Object.keys(row)) {
          const value: BackupCell = row[column];
          if (!/^[a-z][a-z0-9_]*$/.test(column) ||
            (value !== null && typeof value !== 'string' && typeof value !== 'number') ||
            (typeof value === 'number' && !Number.isFinite(value))) {
            throw new Error('备份含无效字段');
          }
        }
        if (table.name === 'cultivate_entries') {
          if (snapshot.schemaVersion >= 8) {
            // Preserve opaque text including unknown versions; NUL is rejected before native string APIs.
            if (!BackupSnapshotValidator.text(row['input_json'],
              BackupSnapshotValidator.MAX_CULTIVATION_INPUT_LENGTH, false) ||
              (row['input_json'] as string).indexOf('\u0000') >= 0) {
              throw new Error('养成输入字段无效或过长');
            }
          } else if (Object.keys(row).indexOf('input_json') >= 0) {
            throw new Error('旧版备份不支持养成输入字段');
          }
        }
        if (table.name === 'user_accounts') {
          const id: number = Number(row['id']);
          if (!Number.isSafeInteger(id) || id < 1 || users.has(id)) {
            throw new Error('备份账号标识无效或重复');
          }
          users.add(id);
        }
      }
    }
    for (const required of allowed) {
      if (!seen.has(required)) {
        throw new Error(`备份缺少数据表 ${required}`);
      }
    }
    if (snapshot.schemaVersion >= 7) { BackupSnapshotValidator.validateBackpack(snapshot); }
    const credentials: Set<number> = new Set<number>();
    for (const credential of snapshot.credentials) {
      if (credential === null || !users.has(credential.userId) || credentials.has(credential.userId) ||
        typeof credential.cookie !== 'string') {
        throw new Error('备份凭据与账号不匹配');
      }
      credentials.add(credential.userId);
    }
    if (credentials.size !== users.size) {
      throw new Error('备份缺少账号凭据段');
    }
    for (const key of Object.keys(snapshot.preferences)) {
      const value: string | number | boolean = snapshot.preferences[key];
      if (!BackupSnapshotValidator.portableKey(key) ||
        (typeof value !== 'string' && typeof value !== 'number' && typeof value !== 'boolean') ||
        (typeof value === 'number' && !Number.isFinite(value))) {
        throw new Error('备份包含不可迁移的设置');
      }
    }
  }
}
