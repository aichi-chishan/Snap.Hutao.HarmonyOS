import { BackupSnapshot, BackupTable, BackupCredential, BackupCell, BackupSnapshotValidator } from './BackupSnapshot';

/** v1 conversion is pure: malformed legacy files are rejected before any database write. */
export class LegacyBackup {
  private static object(value: Object): Record<string, Object> {
    if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('旧版备份结构损坏');
    }
    return value as Record<string, Object>;
  }

  private static list(value: Object): Object[] {
    if (!Array.isArray(value)) {
      throw new Error('旧版备份缺少数据列表');
    }
    return value as Object[];
  }

  private static str(obj: Record<string, Object>, key: string): string {
    if (typeof obj[key] !== 'string') {
      throw new Error(`旧版备份字段 ${key} 无效`);
    }
    return obj[key] as string;
  }

  private static num(obj: Record<string, Object>, key: string): number {
    if (typeof obj[key] !== 'number' || !Number.isFinite(obj[key] as number)) {
      throw new Error(`旧版备份字段 ${key} 无效`);
    }
    return obj[key] as number;
  }

  private static selected(obj: Record<string, Object>, key: string): number {
    if (typeof obj[key] !== 'boolean') {
      throw new Error(`旧版备份字段 ${key} 无效`);
    }
    return obj[key] ? 1 : 0;
  }

  static convert(value: Object, schemaVersion: number): BackupSnapshot {
    const root: Record<string, Object> = LegacyBackup.object(value);
    if (root['app'] !== 'snaphutao-harmonyos-backup' || root['version'] !== 1) {
      throw new Error('不支持的备份版本');
    }
    const out: BackupSnapshot = new BackupSnapshot();
    out.schemaVersion = schemaVersion;
    const tables: Map<string, BackupTable> = new Map<string, BackupTable>();
    for (const name of BackupSnapshotValidator.TABLES) {
      const table: BackupTable = new BackupTable();
      table.name = name;
      tables.set(name, table);
      out.tables.push(table);
    }
    let userId: number = 0;
    let roleId: number = 0;
    for (const raw of LegacyBackup.list(root['users'])) {
      const user: Record<string, Object> = LegacyBackup.object(raw);
      userId++;
      const row: Record<string, BackupCell> = {
        'id': userId, 'mid': LegacyBackup.str(user, 'mid'), 'aid': LegacyBackup.str(user, 'aid'),
        'is_oversea': user['isOversea'] === true ? 1 : 0,
        'display_nickname': LegacyBackup.str(user, 'displayName'), 'avatar': LegacyBackup.str(user, 'avatar'),
        'created_at': LegacyBackup.num(user, 'createdAt'), 'is_selected': LegacyBackup.selected(user, 'isSelected'),
        'cookie_account_token': '', 'cookie_ltoken_ltuid': '', 'cookie_stoken_stuid': '',
      };
      tables.get('user_accounts')!.rows.push(row);
      const credential: BackupCredential = new BackupCredential();
      credential.userId = userId;
      credential.cookie = LegacyBackup.str(user, 'cookie');
      out.credentials.push(credential);
      for (const rawRole of LegacyBackup.list(user['roles'])) {
        const role: Record<string, Object> = LegacyBackup.object(rawRole);
        const roleRow: Record<string, BackupCell> = {
          'id': ++roleId, 'user_id': userId, 'game_uid': LegacyBackup.str(role, 'gameUid'),
          'region': LegacyBackup.str(role, 'region'), 'nickname': LegacyBackup.str(role, 'nickname'),
          'level': LegacyBackup.num(role, 'level'), 'is_default': LegacyBackup.selected(role, 'isDefault'),
          'is_chosen': LegacyBackup.selected(role, 'isChosen'),
        };
        tables.get('user_game_roles')!.rows.push(roleRow);
      }
    }
    let archiveId: number = 0;
    let itemId: number = 0;
    for (const raw of LegacyBackup.list(root['gacha'])) {
      const archive: Record<string, Object> = LegacyBackup.object(raw);
      const uid: string = LegacyBackup.str(archive, 'uid');
      if (!/^\d{9,10}$/.test(uid)) {
        throw new Error('旧版祈愿备份UID无效');
      }
      tables.get('gacha_archives')!.rows.push({ 'id': ++archiveId, 'uid': uid, 'is_selected': 0 });
      for (const rawItem of LegacyBackup.list(archive['items'])) {
        const item: Record<string, Object> = LegacyBackup.object(rawItem);
        const row: Record<string, BackupCell> = {
          'id': ++itemId, 'archive_id': archiveId, 'gacha_id': LegacyBackup.str(item, 'gachaId'),
          'gacha_type': LegacyBackup.num(item, 'gachaType'), 'item_id': LegacyBackup.num(item, 'itemId'),
          'count': LegacyBackup.num(item, 'count'), 'time': LegacyBackup.str(item, 'time'),
          'name': LegacyBackup.str(item, 'name'), 'item_type': LegacyBackup.str(item, 'itemType'),
          'rank_type': LegacyBackup.num(item, 'rankType'), 'schedule_id': LegacyBackup.num(item, 'scheduleId'),
        };
        tables.get('gacha_items')!.rows.push(row);
      }
    }
    archiveId = 0;
    itemId = 0;
    for (const raw of LegacyBackup.list(root['achievements'])) {
      const archive: Record<string, Object> = LegacyBackup.object(raw);
      tables.get('achievement_archives')!.rows.push({
        'id': ++archiveId, 'name': LegacyBackup.str(archive, 'name'), 'created_at': Date.now(),
        'is_selected': LegacyBackup.selected(archive, 'isSelected'),
      });
      for (const rawItem of LegacyBackup.list(archive['records'])) {
        const item: Record<string, Object> = LegacyBackup.object(rawItem);
        tables.get('achievement_entries')!.rows.push({
          'id': ++itemId, 'archive_id': archiveId, 'ach_id': LegacyBackup.num(item, 'achId'),
          'current': LegacyBackup.num(item, 'current'), 'timestamp': LegacyBackup.num(item, 'timestamp'), 'status': 3,
        });
      }
    }
    const prefs: Record<string, Object> = LegacyBackup.object(root['prefs']);
    const mappings: Record<string, string> = {
      'themeMode': 'theme.mode', 'refreshInterval': 'dailynote.refresh_interval_minutes',
      'autoRefresh': 'dailynote.auto_refresh_enabled', 'ambientStrength': 'app.ambient_strength',
      'dailyBgEnabled': 'app.daily_bg_enabled', 'bgImageType': 'app.bg_image_type',
      'bgFolderPath': 'app.bg_folder_path', 'geetestUrl': 'risk.geetest_custom_composite_url',
      'currentUid': 'app.current_uid',
    };
    for (const key of Object.keys(mappings)) {
      const v: Object = prefs[key];
      if (typeof v !== 'string' && typeof v !== 'number' && typeof v !== 'boolean') {
        throw new Error('旧版备份设置损坏');
      }
      out.preferences[mappings[key]] = v as string | number | boolean;
    }
    BackupSnapshotValidator.validate(out);
    return out;
  }
}
