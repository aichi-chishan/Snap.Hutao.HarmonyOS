/** Trusted immutable Git tree + bounded cohort contract. Local receipts are not publisher signatures. */
export class ItemType {
  static readonly Text: string = 'text';
  static readonly Icon: string = 'icon';
  static readonly Image: string = 'image';
}
export class GameDataItem {
  type: string = '';
  path: string = '';
  url: string = '';
  version: number = 0;
  size: number = 0;
  sha256: string = '';
}
export class GameDataManifest {
  schema: number = 1;
  channel: string = '';
  channelVersion: string = '';
  sourceRevision: string = '';
  upstreamSha: string = '';
  items: GameDataItem[] = [];
}
export class GameDataSource {
  ref: string = '';
  file: string = 'manifest-hutao.json';
}

export class GameDataManifestPolicy {
  static readonly REPOSITORY: string = 'aichi-chishan/snap-hutao-data';
  static readonly RAW_ROOT: string = 'https://raw.githubusercontent.com/aichi-chishan/snap-hutao-data/';
  static readonly MAX_MANIFEST_BYTES: number = 4 * 1024 * 1024;
  static readonly MAX_FILE_BYTES: number = 8 * 1024 * 1024;
  static readonly MAX_SNAPSHOT_BYTES: number = 512 * 1024 * 1024;
  static readonly METADATA: string[] = ['Achievement.json', 'AchievementGoal.json', 'AvatarCurve.json',
    'AvatarPromote.json', 'avatar_meta.json', 'GachaEvent.json', 'material_meta.json', 'MonsterCurve.json',
    'monster_meta.json', 'NameCard.json', 'RoleCombatSchedule.json', 'TowerFloor.json', 'TowerLevel.json',
    'TowerSchedule.json', 'WeaponCurve.json', 'WeaponPromote.json', 'weapon_meta.json'];

  static parseJson(text: string): Object {
    return JSON.parse(text.charCodeAt(0) === 0xFEFF ? text.substring(1) : text) as Object;
  }
  static object(value: Object | undefined, label: string): Record<string, Object> {
    if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error(`${label} 必须是对象`);
    }
    return value as Record<string, Object>;
  }
  static array(value: Object | undefined, label: string): Object[] {
    if (!Array.isArray(value)) { throw new Error(`${label} 必须是数组`); }
    return value as Object[];
  }
  static text(value: Object | undefined, label: string): string {
    if (typeof value !== 'string') { throw new Error(`${label} 必须是文本`); }
    return value as string;
  }
  static integer(value: Object | undefined, label: string, minimum: number = 0): number {
    if (typeof value !== 'number' || !Number.isSafeInteger(value) || (value as number) < minimum) {
      throw new Error(`${label} 必须是有效整数`);
    }
    return value as number;
  }
  static isRevision(value: string): boolean { return value.length === 40 && /^[0-9a-f]{40}$/.test(value); }
  static validId(id: string): boolean { return id.trim() === id && /^[0-9a-f]{40}-[0-9]{1,16}-[0-9a-f]{8}$/.test(id); }

  static source(url: string): GameDataSource {
    if (/\s/.test(url) || !url.startsWith(GameDataManifestPolicy.RAW_ROOT)) { throw new Error('数据源必须来自可信 HTTPS 数据仓库'); }
    const rest: string = url.substring(GameDataManifestPolicy.RAW_ROOT.length);
    const parts: string[] = rest.split('/');
    if (parts.length !== 2 || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/.test(parts[0]) ||
      parts[0] === '.' || parts[0] === '..' || parts[1] !== 'manifest-hutao.json') {
      throw new Error('数据源地址格式无效');
    }
    const source: GameDataSource = new GameDataSource(); source.ref = parts[0]; return source;
  }

  static validatePath(path: string, type: string): void {
    if (/[\s\\%?#]/.test(path)) { throw new Error('文件路径包含不安全字符'); }
    if (type === ItemType.Text) {
      if (!GameDataManifestPolicy.METADATA.some((name: string): boolean => path === `metadata/${name}`)) {
        throw new Error('清单包含未知元数据路径');
      }
    } else if (type === ItemType.Icon) {
      if (!/^icons\/[A-Za-z0-9_]+\/[A-Za-z0-9_][A-Za-z0-9_.-]*\.png$/.test(path)) {
        throw new Error('图标路径无效');
      }
    } else { throw new Error('清单条目类型无效'); }
    if (path.length > 240 || path.split('/').some((part: string): boolean => part === '.' || part === '..')) {
      throw new Error('文件路径超出安全范围');
    }
  }

  static parse(text: string, source: GameDataSource, revision: string): GameDataManifest {
    if (!GameDataManifestPolicy.isRevision(revision) || text.length > GameDataManifestPolicy.MAX_MANIFEST_BYTES) {
      throw new Error('清单版本或大小无效');
    }
    const raw: Record<string, Object> = GameDataManifestPolicy.object(GameDataManifestPolicy.parseJson(text), 'manifest');
    const result: GameDataManifest = new GameDataManifest();
    result.schema = raw['schema'] === undefined ? 1 : GameDataManifestPolicy.integer(raw['schema'], 'schema', 1);
    result.channel = GameDataManifestPolicy.text(raw['channel'], 'channel');
    result.channelVersion = GameDataManifestPolicy.text(raw['channelVersion'], 'channelVersion');
    result.sourceRevision = revision;
    if (![1, 2].includes(result.schema) || result.channel !== 'hutao-cn' ||
      (result.channelVersion.trim() !== result.channelVersion || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(result.channelVersion))) { throw new Error('清单版本或频道无效'); }
    if (raw['sourceRevision'] !== undefined && raw['sourceRevision'] !== revision) { throw new Error('清单源码版本不一致'); }
    if (raw['upstreamSha'] !== undefined) { result.upstreamSha = GameDataManifestPolicy.text(raw['upstreamSha'], 'upstreamSha'); }
    if ((result.schema === 2 && !GameDataManifestPolicy.isRevision(result.upstreamSha)) ||
      (result.upstreamSha !== '' && !GameDataManifestPolicy.isRevision(result.upstreamSha))) { throw new Error('上游版本无效'); }
    const items: Object[] = GameDataManifestPolicy.array(raw['items'], 'items');
    if (items.length < GameDataManifestPolicy.METADATA.length || items.length > 10000) { throw new Error('清单文件数量无效'); }
    const paths: Set<string> = new Set<string>();
    let bytes: number = 0;
    for (const value of items) {
      const entry: Record<string, Object> = GameDataManifestPolicy.object(value, 'item');
      const item: GameDataItem = new GameDataItem();
      item.type = GameDataManifestPolicy.text(entry['type'], 'type');
      if (item.type === ItemType.Image) { item.type = ItemType.Icon; }
      item.path = GameDataManifestPolicy.text(entry['path'], 'path');
      item.version = GameDataManifestPolicy.integer(entry['version'], 'version');
      GameDataManifestPolicy.validatePath(item.path, item.type);
      if (paths.has(item.path.toLowerCase())) { throw new Error('清单路径重复'); }
      paths.add(item.path.toLowerCase());
      const url: string = GameDataManifestPolicy.text(entry['url'], 'url');
      if (!url.startsWith(GameDataManifestPolicy.RAW_ROOT)) { throw new Error('文件 URL 不属于可信仓库'); }
      const suffix: string = url.substring(GameDataManifestPolicy.RAW_ROOT.length);
      const slash: number = suffix.indexOf('/');
      const ref: string = slash < 0 ? '' : suffix.substring(0, slash);
      if (![source.ref, revision, 'main'].includes(ref) || suffix.substring(slash + 1) !== item.path) {
        throw new Error('文件 URL 与固定清单不一致');
      }
      item.url = `${GameDataManifestPolicy.RAW_ROOT}${revision}/${item.path}`;
      const hasSize: boolean = entry['size'] !== undefined;
      const hasHash: boolean = entry['sha256'] !== undefined;
      // Persisted v1 receipts have positive size/hash, never an invented publisher signature.
      if (hasSize || hasHash || result.schema === 2) {
        item.size = GameDataManifestPolicy.integer(entry['size'], 'size', 1);
        item.sha256 = GameDataManifestPolicy.text(entry['sha256'], 'sha256');
        if (item.size > GameDataManifestPolicy.MAX_FILE_BYTES || item.sha256.length !== 64 || !/^[0-9a-f]{64}$/.test(item.sha256)) {
          throw new Error('文件大小或摘要无效');
        }
        bytes += item.size;
      }
      result.items.push(item);
    }
    if (bytes > GameDataManifestPolicy.MAX_SNAPSHOT_BYTES || GameDataManifestPolicy.METADATA.some(
      (name: string): boolean => !paths.has(`metadata/${name}`.toLowerCase()))) { throw new Error('清单缺少完整元数据或容量超限'); }
    return result;
  }

  static validateBytes(item: GameDataItem, bytes: Uint8Array, digest: string): void {
    if (bytes.length < 1 || bytes.length > GameDataManifestPolicy.MAX_FILE_BYTES ||
      (item.size > 0 && item.size !== bytes.length) || (item.sha256 !== '' && item.sha256 !== digest)) {
      throw new Error('文件长度或 SHA256 校验失败');
    }
    if (item.type === ItemType.Icon) { GameDataManifestPolicy.validatePng(bytes); }
  }

  private static crcTable: number[] = [];
  private static u32(bytes: Uint8Array, at: number): number {
    return bytes[at] * 0x1000000 + bytes[at + 1] * 0x10000 + bytes[at + 2] * 0x100 + bytes[at + 3];
  }
  private static crc32(bytes: Uint8Array, first: number, end: number): number {
    if (GameDataManifestPolicy.crcTable.length === 0) {
      for (let index: number = 0; index < 256; index++) {
        let value: number = index;
        for (let bit: number = 0; bit < 8; bit++) { value = (value & 1) !== 0 ? 0xEDB88320 ^ (value >>> 1) : value >>> 1; }
        GameDataManifestPolicy.crcTable.push(value >>> 0);
      }
    }
    let value: number = 0xFFFFFFFF;
    for (let index: number = first; index < end; index++) { value = GameDataManifestPolicy.crcTable[(value ^ bytes[index]) & 255] ^ (value >>> 8); }
    return (value ^ 0xFFFFFFFF) >>> 0;
  }
  /** Bounded PNG structure and CRC checks, not full decompression or image-renderer acceptance. */
  private static validatePng(bytes: Uint8Array): void {
    const signature: number[] = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 57 || signature.some((value: number, index: number): boolean => bytes[index] !== value)) { throw new Error('PNG 文件头无效'); }
    let at: number = 8; let chunks: number = 0; let data: number = 0; let color: number = -1;
    let palette: boolean = false; let endedData: boolean = false;
    while (at + 12 <= bytes.length) {
      const size: number = GameDataManifestPolicy.u32(bytes, at);
      if (size > bytes.length - at - 12 || ++chunks > 100000) { throw new Error('PNG 数据块越界'); }
      const type: string = String.fromCharCode(bytes[at + 4], bytes[at + 5], bytes[at + 6], bytes[at + 7]);
      if (!/^[A-Za-z]{4}$/.test(type) ||
        GameDataManifestPolicy.crc32(bytes, at + 4, at + 8 + size) !== GameDataManifestPolicy.u32(bytes, at + 8 + size)) {
        throw new Error('PNG 数据块校验失败');
      }
      if (chunks === 1) {
        if (type !== 'IHDR' || size !== 13) { throw new Error('PNG 缺少有效 IHDR'); }
        const width: number = GameDataManifestPolicy.u32(bytes, at + 8);
        const height: number = GameDataManifestPolicy.u32(bytes, at + 12);
        const depth: number = bytes[at + 16]; color = bytes[at + 17];
        const depths: number[] = color === 0 ? [1, 2, 4, 8, 16] : color === 3 ? [1, 2, 4, 8] : [8, 16];
        if (width < 1 || height < 1 || width > 8192 || height > 8192 || width * height > 16 * 1024 * 1024 ||
          ![0, 2, 3, 4, 6].includes(color) || !depths.includes(depth) || bytes[at + 18] !== 0 || bytes[at + 19] !== 0 || bytes[at + 20] > 1) {
          throw new Error('PNG 尺寸或颜色格式无效');
        }
      } else if (type === 'IHDR') { throw new Error('PNG IHDR 重复'); }
      else if (type === 'PLTE') {
        if (palette || data > 0 || [0, 4].includes(color) || size < 3 || size > 768 || size % 3 !== 0) { throw new Error('PNG 调色板无效'); }
        palette = true;
      } else if (type === 'IDAT') {
        if (endedData || (color === 3 && !palette)) { throw new Error('PNG 像素块顺序无效'); }
        data += size;
      } else if (type === 'IEND') {
        if (size !== 0 || data === 0 || at + 12 !== bytes.length) { throw new Error('PNG 结束块无效'); }
        return;
      } else {
        if (type.charCodeAt(0) < 97) { throw new Error('PNG 包含未知关键块'); }
        if (data > 0) { endedData = true; }
      }
      at += size + 12;
    }
    throw new Error('PNG 文件未完整结束');
  }

  private static rows(metadata: Map<string, string>, name: string): Record<string, Object>[] {
    const text: string | undefined = metadata.get(`metadata/${name}`);
    if (text === undefined) { throw new Error('快照缺少元数据'); }
    const rows: Object[] = GameDataManifestPolicy.array(GameDataManifestPolicy.parseJson(text), name);
    if (rows.length < 1 || rows.length > 200000) { throw new Error('元数据记录数量无效'); }
    return rows.map((row: Object): Record<string, Object> => GameDataManifestPolicy.object(row, name));
  }
  private static ids(rows: Record<string, Object>[], key: string, unique: boolean = true, minimum: number = 1): Set<number> {
    const ids: Set<number> = new Set<number>();
    for (const row of rows) {
      const id: number = GameDataManifestPolicy.integer(row[key], key, minimum);
      if (unique && ids.has(id)) { throw new Error('元数据 ID 重复'); }
      ids.add(id);
    }
    return ids;
  }
  private static references(value: Object | undefined, ids: Set<number>, label: string): void {
    for (const raw of GameDataManifestPolicy.array(value, label)) {
      if (!ids.has(GameDataManifestPolicy.integer(raw, label, 1))) { throw new Error(`${label} 引用不存在`); }
    }
  }

  /** Cohort structural/reference checks; not a complete formal model of game rules. */
  static validateModels(metadata: Map<string, string>): void {
    const materialText: string | undefined = metadata.get('metadata/material_meta.json');
    if (materialText === undefined) { throw new Error('缺少材料数据'); }
    const materials: Record<string, Object> = GameDataManifestPolicy.object(GameDataManifestPolicy.parseJson(materialText), 'materials');
    const materialIds: Set<number> = new Set<number>();
    for (const key of Object.keys(materials)) {
      if (!/^[1-9][0-9]*$/.test(key)) { throw new Error('材料 ID 无效'); }
      materialIds.add(GameDataManifestPolicy.integer(Number(key), 'material id', 1));
      const material: Record<string, Object> = GameDataManifestPolicy.object(materials[key], 'material');
      GameDataManifestPolicy.text(material['n'], 'material name'); GameDataManifestPolicy.text(material['i'], 'material icon');
    }
    if (materialIds.size < 1 || materialIds.size > 200000) { throw new Error('材料数据数量无效'); }
    const avatars: Record<string, Object>[] = GameDataManifestPolicy.rows(metadata, 'avatar_meta.json');
    const avatarIds: Set<number> = GameDataManifestPolicy.ids(avatars, 'id');
    const weapons: Record<string, Object>[] = GameDataManifestPolicy.rows(metadata, 'weapon_meta.json');
    const weaponIds: Set<number> = GameDataManifestPolicy.ids(weapons, 'id');
    const monsters: Record<string, Object>[] = GameDataManifestPolicy.rows(metadata, 'monster_meta.json');
    for (const row of monsters) {
      const id: number = GameDataManifestPolicy.integer(row['id'], 'monster id');
      const describe: number = GameDataManifestPolicy.integer(row['describeId'], 'describeId');
      if (id === 0 && describe === 0) { throw new Error('怪物身份无效'); }
    }
    for (const row of avatars.concat(weapons).concat(monsters)) {
      GameDataManifestPolicy.text(row['name'], 'name'); GameDataManifestPolicy.text(row['icon'], 'icon');
    }
    for (const row of avatars.concat(weapons)) {
      if (row['cultivationItems'] !== undefined) { GameDataManifestPolicy.references(row['cultivationItems'], materialIds, '材料'); }
    }
    for (const row of avatars) {
      for (const field of ['skills', 'talents']) {
        for (const raw of GameDataManifestPolicy.array(row[field], field)) {
          const skill: Record<string, Object> = GameDataManifestPolicy.object(raw, field);
          GameDataManifestPolicy.text(skill['n'], 'skill name'); GameDataManifestPolicy.text(skill['d'], 'skill text');
          GameDataManifestPolicy.text(skill['i'], 'skill icon');
        }
      }
    }
    for (const name of ['AvatarCurve.json', 'WeaponCurve.json', 'MonsterCurve.json']) {
      const rows: Record<string, Object>[] = GameDataManifestPolicy.rows(metadata, name); GameDataManifestPolicy.ids(rows, 'Level');
      for (const row of rows) {
        const curves: Object[] = GameDataManifestPolicy.array(row['Curves'], 'Curves');
        if (curves.length < 1) { throw new Error('曲线数据为空'); }
        for (const raw of curves) {
          const curve: Record<string, Object> = GameDataManifestPolicy.object(raw, 'curve');
          GameDataManifestPolicy.integer(curve['Type'], 'curve Type', 1);
          if (typeof curve['Value'] !== 'number' || !Number.isFinite(curve['Value'] as number)) { throw new Error('曲线数值无效'); }
        }
      }
    }
    for (const name of ['AvatarPromote.json', 'WeaponPromote.json']) {
      for (const row of GameDataManifestPolicy.rows(metadata, name)) {
        GameDataManifestPolicy.integer(row['Id'], 'promote Id', 1); GameDataManifestPolicy.integer(row['Level'], 'promote Level');
        for (const raw of GameDataManifestPolicy.array(row['AddProperties'], 'AddProperties')) {
          const property: Record<string, Object> = GameDataManifestPolicy.object(raw, 'property');
          GameDataManifestPolicy.integer(property['Type'], 'property Type', 1);
          if (typeof property['Value'] !== 'number' || !Number.isFinite(property['Value'] as number)) { throw new Error('突破数值无效'); }
        }
      }
    }
    const goals: Set<number> = GameDataManifestPolicy.ids(GameDataManifestPolicy.rows(metadata, 'AchievementGoal.json'), 'Id', true, 0);
    const achievements: Record<string, Object>[] = GameDataManifestPolicy.rows(metadata, 'Achievement.json');
    const achievementIds: Set<number> = GameDataManifestPolicy.ids(achievements, 'Id');
    for (const row of achievements) {
      if (!goals.has(GameDataManifestPolicy.integer(row['Goal'], 'Goal'))) { throw new Error('成就目标不存在'); }
      const previous: number = GameDataManifestPolicy.integer(row['PreviousId'], 'PreviousId');
      if (previous > 0 && !achievementIds.has(previous)) { throw new Error('成就前置不存在'); }
    }
    const floors: Set<number> = GameDataManifestPolicy.ids(GameDataManifestPolicy.rows(metadata, 'TowerFloor.json'), 'Id');
    for (const row of GameDataManifestPolicy.rows(metadata, 'TowerSchedule.json')) {
      GameDataManifestPolicy.integer(row['Id'], 'schedule Id', 1); GameDataManifestPolicy.references(row['FloorIds'], floors, '深渊楼层');
    }
    GameDataManifestPolicy.ids(GameDataManifestPolicy.rows(metadata, 'TowerLevel.json'), 'Id');
    for (const row of GameDataManifestPolicy.rows(metadata, 'GachaEvent.json')) {
      const type: number = GameDataManifestPolicy.integer(row['Type'], 'gacha Type', 1);
      const targets: Set<number> = type === 302 ? weaponIds : avatarIds;
      // Mixed lower-rarity pools may include weapons; both target identity sets remain bounded.
      const all: Set<number> = new Set<number>(); for (const id of targets) { all.add(id); } for (const id of weaponIds) { all.add(id); }
      GameDataManifestPolicy.references(row['UpOrangeList'], all, '卡池金色物品');
      GameDataManifestPolicy.references(row['UpPurpleList'], all, '卡池紫色物品');
    }
    for (const row of GameDataManifestPolicy.rows(metadata, 'RoleCombatSchedule.json')) {
      GameDataManifestPolicy.references(row['SpecialAvatars'], avatarIds, '剧诗角色');
      GameDataManifestPolicy.references(row['InitialAvatars'], avatarIds, '剧诗初始角色');
    }
    for (const row of GameDataManifestPolicy.rows(metadata, 'NameCard.json')) {
      GameDataManifestPolicy.text(row['Name'], 'namecard Name'); GameDataManifestPolicy.text(row['Picture'], 'namecard Picture');
    }
  }
}
