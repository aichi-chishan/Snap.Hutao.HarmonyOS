/** Portable, explicitly versioned database snapshot. No device identity or signing material. */
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
  static readonly TABLES: string[] = [
    'user_accounts', 'user_game_roles', 'gacha_archives', 'gacha_items',
    'achievement_archives', 'achievement_entries', 'cultivate_projects',
    'cultivate_entries', 'cultivate_items', 'cultivate_inventory', 'daily_notes', 'sign_in_info',
    'act_calendar_entries', 'announcements', 'abyss_history',
    'role_combat_history', 'hard_challenge_history', 'challenge_records',
  ];

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
    if (!Number.isInteger(snapshot.schemaVersion) || snapshot.schemaVersion < 1 ||
      !Array.isArray(snapshot.tables) || !Array.isArray(snapshot.credentials) ||
      snapshot.preferences === null || typeof snapshot.preferences !== 'object' || Array.isArray(snapshot.preferences)) {
      throw new Error('备份结构不完整');
    }
    const seen: Set<string> = new Set<string>();
    const users: Set<number> = new Set<number>();
    for (const table of snapshot.tables) {
      if (table === null || BackupSnapshotValidator.TABLES.indexOf(table.name) < 0 ||
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
        if (table.name === 'user_accounts') {
          const id: number = Number(row['id']);
          if (!Number.isSafeInteger(id) || id < 1 || users.has(id)) {
            throw new Error('备份账号标识无效或重复');
          }
          users.add(id);
        }
      }
    }
    for (const required of BackupSnapshotValidator.TABLES) {
      if (!seen.has(required)) {
        throw new Error(`备份缺少数据表 ${required}`);
      }
    }
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
