/**
 * GachaItem.ets
 * 单条抽卡记录（含归档字段），提供服务端 JSON → 实体映射。
 */
export class GachaItem {
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
