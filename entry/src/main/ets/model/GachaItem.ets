/**
 * GachaItem.ets
 * 单条抽卡记录（含归档字段），提供服务端 JSON → 实体映射。
 */
import { GachaType } from './GachaType';

export class GachaItem {
  static readonly MAX_SIGNED_ID: string = '9223372036854775807';

  id: number = 0;
  archiveId: number = 0;
  /** 仅接口传输使用；落库归属以响应UID校验，不信任页面当前账号。 */
  uid: string = '';
  gachaType: number = 0;
  itemId: number = 0;
  count: number = 1;
  /** 服务端时间 'yyyy-MM-dd HH:mm:ss' */
  time: string = '';
  name: string = '';
  itemType: string = '';
  rankType: number = 0;
  /** 卡池期次（UIGF v4.2 导出用） */
  scheduleId: number = 0;
  /** 服务端游标 id（去重/end_id） */
  gachaId: string = '';

  /** 十进制游标可以超出 JS 安全整数范围。 */
  static compareIds(left: string, right: string): number {
    const a: string = GachaItem.decimalId(left);
    const b: string = GachaItem.decimalId(right);
    if (a.length !== b.length) { return a.length - b.length; }
    return a < b ? -1 : (a > b ? 1 : 0);
  }

  static decimalId(id: string): string { return id.replace(/^0+/, '') || '0'; }

  /** 仅在同一 UID 内使用；普通祈愿与颂愿的 ID 属于两个独立命名空间。 */
  static recordKey(item: GachaItem): string {
    if (!/^[0-9]+$/.test(item.gachaId) || !(GachaType.isValid(item.gachaType) || item.gachaType === 400)) {
      throw new Error(`祈愿记录包含无效卡池或 ID（数据库行 ${item.id}）`);
    }
    return `${GachaType.isBeyond(item.gachaType) ? 'b' : 's'}:${GachaItem.decimalId(item.gachaId)}`;
  }

  /** 单 UID 的稳定读投影。复制并补齐历史缺字段，原始 SQLite 行和输入均不修改。 */
  static recordIndex(items: GachaItem[], context: string = ''): Map<string, GachaItem> {
    const records: Map<string, GachaItem> = new Map<string, GachaItem>();
    for (const item of items) {
      const key: string = GachaItem.recordKey(item);
      const previous: GachaItem | undefined = records.get(key);
      records.set(key, previous === undefined ? GachaItem.copyRecord(item)
        : GachaItem.mergeRecord(previous, item, context));
    }
    return records;
  }

  static logicalRecords(items: GachaItem[], context: string = ''): GachaItem[] {
    return Array.from(GachaItem.recordIndex(items, context).values());
  }

  /** 名称/类型是可本地化的展示字段；只有已知相同物品 ID 时才能确认展示别名。 */
  static mergeRecord(left: GachaItem, right: GachaItem, context: string = ''): GachaItem {
    const conflicts: string[] = [];
    if (left.gachaType !== right.gachaType) { conflicts.push('原始卡池'); }
    if (left.itemId > 0 && right.itemId > 0 && left.itemId !== right.itemId) { conflicts.push('物品 ID'); }
    if (left.count > 0 && right.count > 0 && left.count !== right.count) { conflicts.push('数量'); }
    if (left.rankType > 0 && right.rankType > 0 && left.rankType !== right.rankType) { conflicts.push('星级'); }
    if (left.scheduleId > 0 && right.scheduleId > 0 && left.scheduleId !== right.scheduleId) { conflicts.push('期次'); }
    if (left.time.length > 0 && right.time.length > 0 && left.time !== right.time) { conflicts.push('时间'); }
    if (left.uid.length > 0 && right.uid.length > 0 && left.uid !== right.uid) { conflicts.push('UID'); }
    if (left.archiveId > 0 && right.archiveId > 0 && left.archiveId !== right.archiveId) { conflicts.push('归档'); }
    const sameItem: boolean = left.itemId > 0 && left.itemId === right.itemId;
    if (!sameItem && left.name.length > 0 && right.name.length > 0 && left.name !== right.name) {
      conflicts.push('缺少物品 ID 的名称');
    }
    if (conflicts.length > 0) {
      const scope: string = context || (left.uid.length > 0 ? `UID ${left.uid}` : `归档 ${left.archiveId}`);
      throw new Error(`祈愿记录冲突（${scope}，${GachaType.isBeyond(left.gachaType) ? '颂愿' : '普通'} ID ` +
        `${GachaItem.decimalId(left.gachaId)}，数据库行 ${left.id}/${right.id}）：${conflicts.join('、')}；原始记录已保留`);
    }
    const result: GachaItem = GachaItem.copyRecord(left);
    if (result.uid.length === 0) { result.uid = right.uid; }
    if (result.itemId <= 0) { result.itemId = right.itemId; }
    if (result.count <= 0) { result.count = right.count; }
    if (result.rankType <= 0) { result.rankType = right.rankType; }
    if (result.scheduleId <= 0) { result.scheduleId = right.scheduleId; }
    if (result.time.length === 0) { result.time = right.time; }
    if (result.name.length === 0) { result.name = right.name; }
    if (result.itemType.length === 0) { result.itemType = right.itemType; }
    return result;
  }

  private static copyRecord(item: GachaItem): GachaItem {
    const copy: GachaItem = new GachaItem();
    copy.id = item.id;
    copy.archiveId = item.archiveId;
    copy.uid = item.uid;
    copy.gachaId = GachaItem.decimalId(item.gachaId);
    copy.gachaType = item.gachaType;
    copy.itemId = item.itemId;
    copy.count = item.count;
    copy.time = item.time;
    copy.name = item.name;
    copy.itemType = item.itemType;
    copy.rankType = item.rankType;
    copy.scheduleId = item.scheduleId;
    return copy;
  }

  /** 从 getGachaLog/getBeyondGachaLog 列表项解析（颂愿池 gacha_type 键为 op_gacha_type） */
  static fromServer(obj: Object, isBeyond: boolean = false): GachaItem {
    const item = obj as Record<string, Object>;
    const gachaItem: GachaItem = new GachaItem();
    gachaItem.gachaId = String(item['id'] ?? '');
    gachaItem.uid = String(item['uid'] ?? '');
    if (isBeyond) {
      gachaItem.gachaType = Number(item['op_gacha_type'] ?? 0);
    } else {
      gachaItem.gachaType = Number(item['gacha_type'] ?? 0);
    }
    gachaItem.itemId = Number(item['item_id'] ?? 0);
    gachaItem.count = Number(item['count'] ?? 1);
    gachaItem.time = String(item['time'] ?? '');
    gachaItem.name = String((isBeyond ? item['item_name'] : item['name']) ?? item['name'] ?? '');
    gachaItem.itemType = String(item['item_type'] ?? '');
    gachaItem.rankType = Number(item['rank_type'] ?? 0);
    gachaItem.scheduleId = Number(item['schedule_id'] ?? 0);
    return gachaItem;
  }

  /** 星级文案（★） */
  rankStars(): string {
    let s: string = '';
    for (let i = 0; i < this.rankType; i++) {
      s += '★';
    }
    return s;
  }
}
