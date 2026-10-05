/** Pinned Windows + official server DTOs: docs/CHALLENGE_CLOUD_PROTOCOL_2026-10-05.md. */
export class ChallengeCloudAvatar {
  AvatarId: number = 0;
  WeaponId: number = 0;
  ReliquarySetIds: number[] = [];
  ActivedConstellationNumber: number = 0;
}
export class ChallengeCloudRank { AvatarId: number = 0; Value: number = 0; }
export class ChallengeCloudBattle { Index: number = 0; Avatars: number[] = []; }
export class ChallengeCloudLevel { Index: number = 0; Star: number = 0; Battles: ChallengeCloudBattle[] = []; }
export class ChallengeCloudFloor { Index: number = 0; Star: number = 0; Levels: ChallengeCloudLevel[] = []; }
export class ChallengeCloudAbyss {
  ScheduleId: number = 0;
  TotalBattleTimes: number = 0;
  TotalWinTimes: number = 0;
  Damage: ChallengeCloudRank | null = null;
  TakeDamage: ChallengeCloudRank | null = null;
  Floors: ChallengeCloudFloor[] = [];
}
export class ChallengeCloudAbyssRecord {
  Uid: string = '';
  Identity: string = 'Snap Hutao';
  ReservedUserName: string | null = null;
  SpiralAbyss: ChallengeCloudAbyss = new ChallengeCloudAbyss();
  Avatars: ChallengeCloudAvatar[] = [];
}
export class ChallengeCloudRoleRecord {
  Version: number = 1;
  Uid: string = '';
  Identity: string = 'Snap Hutao';
  BackupAvatars: number[] = [];
  ScheduleId: number = 0;
}
export class ChallengeCloudPreview {
  id: number = 0;
  kind: string = '';
  uid: string = '';
  region: string = '';
  scheduleId: number = 0;
  content: string = '';
  body: string = '';
  digest: string = '';
  preparedAt: number = 0;
  expiresAt: number = 0;
  endpoint: string = '';
  passport: string = '';
  duplicate: boolean = false;
}
export class ChallengeCloudReceipt {
  userId: number = 0;
  uid: string = '';
  region: string = '';
  kind: string = '';
  scheduleId: number = 0;
  digest: string = '';
  uploadedAt: number = 0;
  retcode: number = 0;
}
export class ChallengeCloudResult {
  message: string = '';
  receiptSaved: boolean = false;
  receipt: ChallengeCloudReceipt | undefined = undefined;
}

/** Strict raw-data boundary. Missing fields never become invented zeroes or empty equipment. */
export class ChallengeCloudSchema {
  static object(value: Object | undefined | null, label: string): Record<string, Object> {
    if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error(`${label}不完整，请重新采集`);
    }
    return value as Record<string, Object>;
  }
  static array(value: Object | undefined | null, label: string, max: number = 1000): Object[] {
    if (!Array.isArray(value) || value.length > max) { throw new Error(`${label}不完整或超出限制`); }
    return value as Object[];
  }
  static integer(value: Object | undefined | null, label: string, min: number = 0, max: number = 2147483647): number {
    if ((typeof value !== 'number' && typeof value !== 'string') || !/^\d+$/.test(String(value))) {
      throw new Error(`${label}缺失或无效`);
    }
    const number: number = Number(value);
    if (!Number.isSafeInteger(number) || number < min || number > max) { throw new Error(`${label}超出范围`); }
    return number;
  }
  static avatarId(value: Object | undefined | null): number { return ChallengeCloudSchema.integer(value, '角色 ID', 10000000, 99999999); }
  static identity(raw: Record<string, Object>, uid: string, region: string): void {
    for (const key of ['uid', 'role_id', 'game_uid']) {
      if (raw[key] !== undefined && String(raw[key]) !== uid) { throw new Error('响应 UID 与所选账号不一致，已拒绝采集'); }
    }
    if (raw['server'] !== undefined && raw['server'] !== region) { throw new Error('响应区服与所选账号不一致'); }
  }
  static player(raw: Object, uid: string, region: string): void {
    const root: Record<string, Object> = ChallengeCloudSchema.object(raw, '玩家信息');
    ChallengeCloudSchema.identity(root, uid, region);
    const role: Record<string, Object> = ChallengeCloudSchema.object(root['role'], '玩家角色信息');
    ChallengeCloudSchema.identity(role, uid, region);
    // GameRecord BasicRoleInfo.region is a localized display name, not a server code.
    if (typeof role['nickname'] !== 'string' || String(role['nickname']).length === 0) { throw new Error('玩家昵称未返回'); }
    ChallengeCloudSchema.integer(role['level'], '冒险等阶', 1, 60);
  }
  static characterIds(raw: Object, uid: string, region: string): number[] {
    const root: Record<string, Object> = ChallengeCloudSchema.object(raw, '角色列表'); ChallengeCloudSchema.identity(root, uid, region);
    const ids: number[] = ChallengeCloudSchema.array(root['list'], '角色列表', 300).map((item: Object): number =>
      ChallengeCloudSchema.avatarId(ChallengeCloudSchema.object(item, '角色')['id']));
    if (ids.length <= 8 || new Set<number>(ids).size !== ids.length) { throw new Error('角色列表不完整或包含重复角色'); }
    if (root['total'] !== undefined && ChallengeCloudSchema.integer(root['total'], '角色总数') !== ids.length) { throw new Error('角色列表只返回了部分数据'); }
    return ids;
  }
  static avatars(raw: Object, expectedIds: number[], uid: string, region: string): ChallengeCloudAvatar[] {
    const root: Record<string, Object> = ChallengeCloudSchema.object(raw, '角色详情'); ChallengeCloudSchema.identity(root, uid, region);
    const out: ChallengeCloudAvatar[] = [];
    for (const item of ChallengeCloudSchema.array(root['list'], '角色详情', 300)) {
      const detail: Record<string, Object> = ChallengeCloudSchema.object(item, '角色详情');
      const base: Record<string, Object> = ChallengeCloudSchema.object(detail['base'], '角色基础资料');
      const avatar: ChallengeCloudAvatar = new ChallengeCloudAvatar();
      avatar.AvatarId = ChallengeCloudSchema.avatarId(base['id']);
      avatar.ActivedConstellationNumber = ChallengeCloudSchema.integer(base['actived_constellation_num'], '命座', 0, 6);
      avatar.WeaponId = ChallengeCloudSchema.integer(ChallengeCloudSchema.object(detail['weapon'], '武器')['id'], '武器 ID', 10000, 99999);
      for (const relic of ChallengeCloudSchema.array(detail['relics'], '圣遗物列表', 5)) {
        const set: Record<string, Object> = ChallengeCloudSchema.object(ChallengeCloudSchema.object(relic, '圣遗物')['set'], '圣遗物套装');
        avatar.ReliquarySetIds.push(ChallengeCloudSchema.integer(set['id'], '圣遗物套装 ID', 1000000, 9999999));
      }
      avatar.ReliquarySetIds.sort((a: number, b: number): number => a - b);
      out.push(avatar);
    }
    const owned: Set<number> = new Set<number>(out.map((a: ChallengeCloudAvatar): number => a.AvatarId));
    if (out.length !== expectedIds.length || owned.size !== out.length || expectedIds.some((id: number): boolean => !owned.has(id))) {
      throw new Error('角色详情采集不完整，未提交任何战绩');
    }
    const travelers: number = (owned.has(10000005) ? 1 : 0) + (owned.has(10000007) ? 1 : 0);
    if (travelers !== 1 || ![10000006, 10000015, 10000021].every((id: number): boolean => owned.has(id)) ||
      out.every((a: ChallengeCloudAvatar): boolean => a.ReliquarySetIds.length === 0)) {
      throw new Error('角色或圣遗物数据不满足服务器完整性规则');
    }
    return out.sort((a: ChallengeCloudAvatar, b: ChallengeCloudAvatar): number => a.AvatarId - b.AvatarId);
  }
  static rank(raw: Object | undefined, required: boolean, owned: Set<number>): ChallengeCloudRank | null {
    const list: Object[] = ChallengeCloudSchema.array(raw, '伤害统计', 1);
    if (list.length === 0) {
      if (required) { throw new Error('没有可上传的深渊伤害战绩'); }
      return null;
    }
    const item: Record<string, Object> = ChallengeCloudSchema.object(list[0], '伤害统计');
    const rank: ChallengeCloudRank = new ChallengeCloudRank();
    rank.AvatarId = ChallengeCloudSchema.avatarId(item['avatar_id']); rank.Value = ChallengeCloudSchema.integer(item['value'], '伤害数值');
    if (!owned.has(rank.AvatarId)) { throw new Error('统计角色不在完整持有列表中'); }
    return rank;
  }
  static abyss(uid: string, region: string, expectedSchedule: number, raw: Object,
    avatars: ChallengeCloudAvatar[], userName: string | null): ChallengeCloudAbyssRecord {
    const source: Record<string, Object> = ChallengeCloudSchema.object(raw, '深渊战绩'); ChallengeCloudSchema.identity(source, uid, region);
    if (source['is_unlock'] !== true) { throw new Error('没有可上传的深渊战绩'); }
    const record: ChallengeCloudAbyssRecord = new ChallengeCloudAbyssRecord();
    record.Uid = uid; record.ReservedUserName = userName; record.Avatars = avatars;
    const abyss: ChallengeCloudAbyss = record.SpiralAbyss;
    abyss.ScheduleId = ChallengeCloudSchema.integer(source['schedule_id'], '深渊期次', 1);
    if (abyss.ScheduleId !== expectedSchedule) { throw new Error('期次已变化或所选期不是当期，请刷新后重新预览'); }
    abyss.TotalBattleTimes = ChallengeCloudSchema.integer(source['total_battle_times'], '挑战次数', 1);
    abyss.TotalWinTimes = ChallengeCloudSchema.integer(source['total_win_times'], '胜利次数', 1, abyss.TotalBattleTimes);
    const owned: Set<number> = new Set<number>(avatars.map((a: ChallengeCloudAvatar): number => a.AvatarId));
    abyss.Damage = ChallengeCloudSchema.rank(source['damage_rank'], true, owned); abyss.TakeDamage = ChallengeCloudSchema.rank(source['take_damage_rank'], false, owned);
    const floors: Set<number> = new Set<number>();
    for (const floorRaw of ChallengeCloudSchema.array(source['floors'], '楼层列表', 100)) {
      const f: Record<string, Object> = ChallengeCloudSchema.object(floorRaw, '楼层');
      const floor: ChallengeCloudFloor = new ChallengeCloudFloor();
      floor.Index = ChallengeCloudSchema.integer(f['index'], '楼层', 1, 100); floor.Star = ChallengeCloudSchema.integer(f['star'], '楼层星数', 0, 9);
      if (floors.has(floor.Index)) { throw new Error('深渊楼层重复'); } floors.add(floor.Index);
      const levels: Set<number> = new Set<number>();
      for (const levelRaw of ChallengeCloudSchema.array(f['levels'], '间目列表', 3)) {
        const l: Record<string, Object> = ChallengeCloudSchema.object(levelRaw, '间目'); const level: ChallengeCloudLevel = new ChallengeCloudLevel();
        level.Index = ChallengeCloudSchema.integer(l['index'], '间目', 1, 3); level.Star = ChallengeCloudSchema.integer(l['star'], '间目星数', 0, 3);
        if (levels.has(level.Index)) { throw new Error('深渊间目重复'); } levels.add(level.Index);
        const used: Set<number> = new Set<number>(); const halves: Set<number> = new Set<number>();
        for (const battleRaw of ChallengeCloudSchema.array(l['battles'], '上下半场', 2)) {
          const b: Record<string, Object> = ChallengeCloudSchema.object(battleRaw, '半场'); const battle: ChallengeCloudBattle = new ChallengeCloudBattle();
          battle.Index = ChallengeCloudSchema.integer(b['index'], '半场序号', 1, 2);
          if (halves.has(battle.Index)) { throw new Error('半场序号重复'); } halves.add(battle.Index);
          for (const avatarRaw of ChallengeCloudSchema.array(b['avatars'], '出战角色', 4)) {
            const id: number = ChallengeCloudSchema.avatarId(ChallengeCloudSchema.object(avatarRaw, '出战角色')['id']);
            if (used.has(id) || !owned.has(id)) { throw new Error('出战角色重复或角色详情缺失'); }
            used.add(id); battle.Avatars.push(id);
          }
          if (battle.Avatars.length === 0) { throw new Error('半场出战角色为空'); }
          battle.Avatars.sort((a: number, b: number): number => a - b); level.Battles.push(battle);
        }
        if (floor.Index >= 9 && level.Battles.length !== 2) { throw new Error('深渊上下半场不完整，未提交'); }
        level.Battles.sort((a: ChallengeCloudBattle, b: ChallengeCloudBattle): number => a.Index - b.Index);
        floor.Levels.push(level);
      }
      floor.Levels.sort((a: ChallengeCloudLevel, b: ChallengeCloudLevel): number => a.Index - b.Index); abyss.Floors.push(floor);
    }
    if (!abyss.Floors.some((f: ChallengeCloudFloor): boolean => f.Levels.length > 0)) { throw new Error('没有可上传的深渊战绩'); }
    abyss.Floors.sort((a: ChallengeCloudFloor, b: ChallengeCloudFloor): number => a.Index - b.Index);
    return record;
  }
  static roleCombat(uid: string, region: string, expectedSchedule: number, raw: Object): ChallengeCloudRoleRecord {
    const root: Record<string, Object> = ChallengeCloudSchema.object(raw, '剧诗战绩'); ChallengeCloudSchema.identity(root, uid, region);
    const data: Object[] = ChallengeCloudSchema.array(root['data'], '剧诗档期', 24);
    if (root['is_unlock'] !== true || data.length === 0) { throw new Error('没有可上传的剧诗战绩'); }
    // Same as pinned Windows: only the current (first) API period is uploadable.
    const item: Record<string, Object> = ChallengeCloudSchema.object(data[0], '当期剧诗');
    if (item['has_data'] !== true || item['has_detail_data'] === false) { throw new Error('当期剧诗暂无完整战绩'); }
    const record: ChallengeCloudRoleRecord = new ChallengeCloudRoleRecord(); record.Uid = uid;
    record.ScheduleId = ChallengeCloudSchema.integer(ChallengeCloudSchema.object(item['schedule'], '剧诗期次')['schedule_id'], '剧诗期次', 1);
    if (record.ScheduleId !== expectedSchedule) { throw new Error('期次已变化或所选期不是当期，请刷新后重新预览'); }
    for (const avatar of ChallengeCloudSchema.array(ChallengeCloudSchema.object(item['detail'], '剧诗详情')['backup_avatars'], '候补角色', 300)) {
      record.BackupAvatars.push(ChallengeCloudSchema.avatarId(ChallengeCloudSchema.object(avatar, '候补角色')['avatar_id']));
    }
    if (record.BackupAvatars.length < 8 || new Set<number>(record.BackupAvatars).size !== record.BackupAvatars.length) {
      throw new Error('剧诗候补角色不满足服务器规则（至少 8 位且不得重复）');
    }
    record.BackupAvatars.sort((a: number, b: number): number => a - b); return record;
  }
}
