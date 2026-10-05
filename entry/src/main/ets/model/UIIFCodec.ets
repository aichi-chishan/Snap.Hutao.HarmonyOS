import { BackpackCategory, BackpackImport, BackpackItem, BackpackManualInput } from './BackpackData';

/**
 * Keep raw JSON values, including unknown extension numbers, losslessly. Parsing a ulong
 * with JSON.parse and re-stringifying it would silently destroy its final digits.
 * Syntax is checked first; the bounded structural walk also rejects duplicate keys.
 */
export class BackpackJson {
  static fields(text: string): Map<string, string> {
    const raw: string = text.trim();
    if (raw[0] !== '{' || raw[raw.length - 1] !== '}') { throw new Error('应为 JSON 对象'); }
    const result: Map<string, string> = new Map<string, string>();
    let pos: number = 1;
    while (pos < raw.length - 1) {
      while (/\s/.test(raw[pos])) { pos++; }
      if (raw[pos] === '}') { break; }
      const keyEnd: number = BackpackJson.stringEnd(raw, pos);
      const key: string = JSON.parse(raw.substring(pos, keyEnd)) as string;
      if (result.has(key)) { throw new Error(`JSON 字段重复：${key}`); }
      pos = keyEnd;
      while (/\s/.test(raw[pos])) { pos++; }
      if (raw[pos++] !== ':') { throw new Error('JSON 字段缺少冒号'); }
      const end: number = BackpackJson.valueEnd(raw, pos);
      result.set(key, raw.substring(pos, end).trim());
      pos = end;
      if (raw[pos] === ',') { pos++; }
    }
    return result;
  }

  static elements(text: string): string[] {
    const raw: string = text.trim();
    if (raw[0] !== '[' || raw[raw.length - 1] !== ']') { throw new Error('应为 JSON 数组'); }
    const result: string[] = [];
    let pos: number = 1;
    while (pos < raw.length - 1) {
      while (/\s/.test(raw[pos])) { pos++; }
      if (raw[pos] === ']') { break; }
      const end: number = BackpackJson.valueEnd(raw, pos);
      result.push(raw.substring(pos, end).trim());
      pos = end;
      if (raw[pos] === ',') { pos++; }
    }
    return result;
  }

  static object(fields: Map<string, string>): string {
    const pairs: string[] = [];
    fields.forEach((value: string, key: string) => pairs.push(`${JSON.stringify(key)}:${value}`));
    return `{${pairs.join(',')}}`;
  }

  static validate(text: string, depth: number = 0): void {
    if (depth > 64) { throw new Error('JSON 嵌套超过 64 层'); }
    if (depth === 0) { JSON.parse(text); }
    const raw: string = text.trim();
    if (raw[0] === '{') {
      BackpackJson.fields(raw).forEach((value: string) => BackpackJson.validate(value, depth + 1));
    } else if (raw[0] === '[') {
      for (const value of BackpackJson.elements(raw)) { BackpackJson.validate(value, depth + 1); }
    }
  }

  private static stringEnd(text: string, start: number): number {
    if (text[start] !== '"') { throw new Error('JSON 字段名应为字符串'); }
    let pos: number = start + 1;
    while (pos < text.length) {
      if (text[pos] === '\\') { pos += 2; continue; }
      if (text[pos++] === '"') { return pos; }
    }
    throw new Error('JSON 字符串未结束');
  }

  private static valueEnd(text: string, start: number): number {
    let depth: number = 0;
    for (let pos: number = start; pos < text.length; pos++) {
      const char: string = text[pos];
      if (char === '"') { pos = BackpackJson.stringEnd(text, pos) - 1; continue; }
      if (char === '{' || char === '[') { depth++; }
      if (char === '}' || char === ']') {
        if (depth === 0) { return pos; }
        depth--;
      }
      if (char === ',' && depth === 0) { return pos; }
    }
    throw new Error('JSON 数据未结束');
  }
}

export class UIIFCodec {
  static readonly MAX_FILE_BYTES: number = 16 * 1024 * 1024;
  static readonly MAX_ITEMS: number = 50000;

  private static withinByteLimit(text: string): boolean {
    let bytes: number = 0;
    for (let i: number = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if (code < 128) { bytes++; }
      else if (code < 2048) { bytes += 2; }
      else if (code >= 55296 && code <= 56319 && i + 1 < text.length &&
        text.charCodeAt(i + 1) >= 56320 && text.charCodeAt(i + 1) <= 57343) { bytes += 4; i++; }
      else { bytes += 3; }
      if (bytes > UIIFCodec.MAX_FILE_BYTES) { return false; }
    }
    return true;
  }

  static validateUid(uid: string): void {
    if (!/^[1-9]\d{8,9}$/.test(uid)) { throw new Error('UID 必须为 9 或 10 位数字'); }
  }

  private static uint(raw: string | undefined, label: string, min: number = 0,
    max: number = 4294967295): number {
    if (raw === undefined) { throw new Error(`${label} 必须为整数`); }
    const digits: string = raw[0] === '"' ? JSON.parse(raw) as string : raw;
    if (typeof digits !== 'string' || !/^\d+$/.test(digits)) { throw new Error(`${label} 必须为整数`); }
    const value: number = Number(digits);
    if (!Number.isSafeInteger(value) || value < min || value > max) {
      throw new Error(`${label} 超出范围 ${min}–${max}`);
    }
    return value;
  }

  private static optionalString(fields: Map<string, string>, key: string): string {
    const raw: string | undefined = fields.get(key);
    if (raw === undefined || raw === 'null') { return ''; }
    const value: Object = JSON.parse(raw) as Object;
    if (typeof value !== 'string') { throw new Error(`${key} 必须为字符串`); }
    return value as string;
  }

  /** Unknown GUID extensions are accepted only losslessly, never Number(ulong). */
  private static guid(raw: string | undefined): string {
    if (raw === undefined || raw === 'null') { return ''; }
    const value: string = raw[0] === '"' ? JSON.parse(raw) as string : raw;
    if (typeof value !== 'string' || !/^[1-9]\d{0,19}$/.test(value) ||
      (value.length === 20 && value > '18446744073709551615')) {
      throw new Error('扩展 guid 必须为非零 uint64 十进制数或字符串');
    }
    return value;
  }

  private static flag(fields: Map<string, string>, key: string): boolean | undefined {
    const raw: string | undefined = fields.get(key);
    if (raw === undefined || raw === 'null') { return undefined; }
    if (raw !== 'true' && raw !== 'false') { throw new Error(`${key} 必须为布尔值`); }
    return raw === 'true';
  }

  static parseItem(raw: string, index: number = 0): BackpackItem {
    const fields: Map<string, string> = BackpackJson.fields(raw);
    const item: BackpackItem = new BackpackItem();
    item.rawJson = raw;
    item.itemId = UIIFCodec.uint(fields.get('itemId'), 'itemId', 1);
    item.guid = UIIFCodec.guid(fields.get('guid'));
    item.instanceId = item.guid.length > 0 ? `guid:${item.guid}` : `local:${index + 1}`;
    item.isLocked = UIIFCodec.flag(fields, 'isLocked');
    item.isMarked = UIIFCodec.flag(fields, 'isMarked');
    let variants: number = 0;
    for (const kind of ['material', 'equip', 'furniture']) {
      if (fields.has(kind) && fields.get(kind) !== 'null') { variants++; item.kind = kind; }
    }
    if (variants !== 1) { throw new Error('每项必须且只能包含 material、equip、furniture 中的一种'); }
    const detail: Map<string, string> = BackpackJson.fields(fields.get(item.kind)!);
    if (item.kind === 'material' || item.kind === 'furniture') {
      item.count = UIIFCodec.uint(detail.get('count'), 'count');
      item.category = item.kind === 'furniture' ? BackpackCategory.Furniture : BackpackCategory.Unknown;
    } else {
      const weapon: string | undefined = detail.get('weapon');
      const reliquary: string | undefined = detail.get('reliquary');
      const hasWeapon: boolean = weapon !== undefined && weapon !== 'null';
      const hasReliquary: boolean = reliquary !== undefined && reliquary !== 'null';
      if (hasWeapon === hasReliquary) { throw new Error('equip 必须且只能包含 weapon、reliquary 中的一种'); }
      const equip: Map<string, string> = BackpackJson.fields(hasWeapon ? weapon! : reliquary!);
      item.level = UIIFCodec.uint(equip.get('level'), 'level', 1);
      if (hasWeapon) {
        item.kind = 'weapon';
        item.category = BackpackCategory.Weapon;
        item.promoteLevel = UIIFCodec.uint(equip.get('promoteLevel'), 'promoteLevel');
        const affixes: string | undefined = equip.get('affixMap');
        if (affixes !== undefined && affixes !== 'null') {
          BackpackJson.fields(affixes).forEach((value: string, key: string) => {
            item.affixMap.set(UIIFCodec.uint(key, 'affixMap 属性 ID', 1), UIIFCodec.uint(value, 'affixMap 等级'));
          });
        }
      } else {
        item.kind = 'reliquary';
        item.category = BackpackCategory.Reliquary;
        item.mainPropId = UIIFCodec.uint(equip.get('mainPropId'), 'mainPropId', 1);
        const append: string | undefined = equip.get('appendPropIdList');
        if (append === undefined) { throw new Error('缺少 appendPropIdList'); }
        item.appendPropIds = BackpackJson.elements(append).map((value: string): number => UIIFCodec.uint(value, '副词条 ID', 1));
      }
      const equipLock: boolean | undefined = UIIFCodec.flag(detail, 'isLocked');
      const equipMark: boolean | undefined = UIIFCodec.flag(detail, 'isMarked');
      if (item.isLocked !== undefined && equipLock !== undefined && item.isLocked !== equipLock) {
        throw new Error('物品与装备的 isLocked 扩展冲突');
      }
      if (item.isMarked !== undefined && equipMark !== undefined && item.isMarked !== equipMark) {
        throw new Error('物品与装备的 isMarked 扩展冲突');
      }
      item.isLocked = item.isLocked ?? equipLock;
      item.isMarked = item.isMarked ?? equipMark;
    }
    return item;
  }

  static parse(text: string): BackpackImport {
    if (text.length === 0 || text.length > UIIFCodec.MAX_FILE_BYTES || !UIIFCodec.withinByteLimit(text)) {
      throw new Error('UIIF 文件为空或超过 16 MiB');
    }
    BackpackJson.validate(text);
    const fields: Map<string, string> = BackpackJson.fields(text);
    const infoRaw: string | undefined = fields.get('info');
    if (infoRaw === undefined) { throw new Error('缺少 UIIF info'); }
    const info: Map<string, string> = BackpackJson.fields(infoRaw);
    if (UIIFCodec.optionalString(info, 'uiif_version') !== 'v1.0') { throw new Error('仅支持 UIIF v1.0'); }
    UIIFCodec.optionalString(info, 'export_app_version');
    if (info.has('export_timestamp') && info.get('export_timestamp') !== 'null') {
      const raw: string = info.get('export_timestamp')!;
      const stamp: string = raw[0] === '"' ? JSON.parse(raw) as string : raw;
      const magnitude: string = stamp.startsWith('-') ? stamp.substring(1) : stamp;
      const limit: string = stamp.startsWith('-') ? '9223372036854775808' : '9223372036854775807';
      if (!/^-?\d+$/.test(stamp) || magnitude.length > 19 || (magnitude.length === 19 && magnitude > limit)) {
        throw new Error('export_timestamp 必须为 Int64 秒时间戳');
      }
    }
    const list: string | undefined = fields.get('list');
    if (list === undefined) { throw new Error('缺少 UIIF list'); }
    const entries: string[] = BackpackJson.elements(list);
    if (entries.length > UIIFCodec.MAX_ITEMS) { throw new Error('背包条目超过 50000 项'); }
    const result: BackpackImport = new BackpackImport();
    result.source = UIIFCodec.optionalString(info, 'export_app') || 'UIIF 文件';
    result.uid = UIIFCodec.optionalString(info, 'uid') || UIIFCodec.optionalString(fields, 'uid');
    const rootUid: string = UIIFCodec.optionalString(fields, 'uid');
    if (result.uid.length > 0) { UIIFCodec.validateUid(result.uid); }
    if (rootUid.length > 0 && result.uid !== rootUid) { throw new Error('文件中的 UID 扩展冲突'); }
    const guids: Set<string> = new Set<string>();
    const stackables: Set<string> = new Set<string>();
    for (let i: number = 0; i < entries.length; i++) {
      let item: BackpackItem;
      try { item = UIIFCodec.parseItem(entries[i], i); }
      catch (e) { throw new Error(`第 ${i + 1} 项：${(e as Error).message}`); }
      if (item.guid.length > 0) {
        if (guids.has(item.guid)) { throw new Error(`重复实例 guid：${item.guid}`); }
        guids.add(item.guid);
      }
      if (item.kind === 'material' || item.kind === 'furniture') {
        const key: string = `${item.kind}:${item.itemId}`;
        if (stackables.has(key)) { throw new Error(`重复堆叠物品：${key}，请先核对数量`); }
        stackables.add(key);
      }
      if (item.kind === 'weapon') { result.weaponCount++; }
      if (item.kind === 'reliquary') { result.reliquaryCount++; }
      if (item.kind === 'material') { result.materialCount++; }
      if (item.kind === 'furniture') { result.furnitureCount++; }
      result.items.push(item);
    }
    fields.set('list', '[]');
    result.documentJson = BackpackJson.object(fields);
    return result;
  }

  static export(documentJson: string, items: BackpackItem[]): string {
    const fields: Map<string, string> = BackpackJson.fields(documentJson);
    fields.set('list', `[${items.map((item: BackpackItem): string => item.rawJson).join(',')}]`);
    const text: string = BackpackJson.object(fields);
    UIIFCodec.parse(text);
    return text;
  }

  static validCategory(kind: string, category: number): boolean {
    if (!Number.isInteger(category)) { return false; }
    if (kind === 'weapon') { return category === BackpackCategory.Weapon; }
    if (kind === 'reliquary') { return category === BackpackCategory.Reliquary; }
    if (kind === 'furniture') { return category === BackpackCategory.Furniture; }
    return kind === 'material' && ((category >= 2 && category <= 7) || category === BackpackCategory.Unknown);
  }

  static validateSnapshot(uid: string, documentJson: string, items: BackpackItem[]): void {
    UIIFCodec.validateUid(uid);
    const header: BackpackImport = UIIFCodec.parse(documentJson);
    if (header.items.length !== 0) { throw new Error('档案头不能包含重复的物品列表'); }
    const parsed: BackpackImport = UIIFCodec.parse(UIIFCodec.export(documentJson, items));
    if (parsed.uid.length > 0 && parsed.uid !== uid) { throw new Error('UIIF UID 与目标档案不一致'); }
    const identities: Set<string> = new Set<string>();
    for (let i: number = 0; i < items.length; i++) {
      const item: BackpackItem = items[i];
      const raw: BackpackItem = parsed.items[i];
      if (item.instanceId.length === 0 || item.instanceId.length > 160 || identities.has(item.instanceId) ||
        item.itemId !== raw.itemId || item.kind !== raw.kind || !UIIFCodec.validCategory(item.kind, item.category) ||
        (raw.guid.length > 0 && item.instanceId !== `guid:${raw.guid}`)) {
        throw new Error('物品身份、类型或分类与原始数据不一致');
      }
      identities.add(item.instanceId);
    }
  }

  /** Explicitly entered fields only; no invented artifact substats, lock state, names or GUIDs. */
  static manual(input: BackpackManualInput): BackpackItem {
    const id: number = UIIFCodec.uint(input.itemId.trim(), '物品 ID', 1);
    let raw: string = '';
    if (input.kind === 'material' || input.kind === 'furniture') {
      const count: number = UIIFCodec.uint(input.count.trim(), '数量');
      raw = `{"itemId":${id},"${input.kind}":{"count":${count}}}`;
    } else if (input.kind === 'weapon') {
      const level: number = UIIFCodec.uint(input.level.trim(), '等级', 1);
      const promote: number = UIIFCodec.uint(input.promoteLevel.trim(), '突破等级');
      let affix: string = '{}';
      if (input.affixId.trim().length > 0) {
        const affixId: number = UIIFCodec.uint(input.affixId.trim(), '精炼词条 ID', 1);
        const rank: number = UIIFCodec.uint(input.affixLevel.trim(), '精炼索引');
        affix = `{"${affixId}":${rank}}`;
      }
      raw = `{"itemId":${id},"equip":{"weapon":{"level":${level},"promoteLevel":${promote},"affixMap":${affix}}}}`;
    } else if (input.kind === 'reliquary') {
      const level: number = UIIFCodec.uint(input.level.trim(), 'UIIF 原始等级', 1);
      const main: number = UIIFCodec.uint(input.mainPropId.trim(), '主词条 ID', 1);
      const append: number[] = input.appendPropIds.trim().length === 0 ? [] :
        input.appendPropIds.trim().split(/[，,\s]+/).map((value: string): number => UIIFCodec.uint(value, '副词条 ID', 1));
      raw = `{"itemId":${id},"equip":{"reliquary":{"level":${level},"mainPropId":${main},"appendPropIdList":[${append.join(',')}]}}}`;
    } else { throw new Error('不支持的物品类型'); }
    const item: BackpackItem = UIIFCodec.parseItem(raw);
    if (item.kind === 'material' && input.category >= 2 && input.category <= 7) { item.category = input.category; }
    return item;
  }

  static changeCount(item: BackpackItem, text: string): BackpackItem {
    if (item.kind !== 'material' && item.kind !== 'furniture') { throw new Error('只有材料或摆设可修改数量'); }
    const count: number = UIIFCodec.uint(text.trim(), '数量');
    const fields: Map<string, string> = BackpackJson.fields(item.rawJson);
    const detail: Map<string, string> = BackpackJson.fields(fields.get(item.kind)!);
    detail.set('count', String(count));
    fields.set(item.kind, BackpackJson.object(detail));
    const changed: BackpackItem = UIIFCodec.parseItem(BackpackJson.object(fields));
    changed.instanceId = item.instanceId;
    changed.archiveId = item.archiveId;
    changed.category = item.category;
    return changed;
  }
}
