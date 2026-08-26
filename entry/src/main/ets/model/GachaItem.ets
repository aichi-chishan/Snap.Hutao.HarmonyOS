/**
 * GachaItem.ets
 * 单条抽卡记录（含归档字段），提供服务端 JSON → 实体映射。
 */
export class GachaItem {
  id: number = 0;
  archiveId: number = 0;
  gachaType: number = 0;
  itemId: number = 0;
  count: number = 1;
  /** 服务端时间 'yyyy-MM-dd HH:mm:ss' */
  time: string = '';
  name: string = '';
  itemType: string = '';
  rankType: number = 0;
  /** 服务端游标 id（去重/end_id） */
  gachaId: string = '';

  /** 从 getGachaLog 列表项解析 */
  static fromServer(obj: Object): GachaItem {
    const item = obj as Record<string, Object>;
    const gachaItem: GachaItem = new GachaItem();
    gachaItem.gachaId = String(item['id'] ?? '');
    gachaItem.gachaType = Number(item['gacha_type'] ?? 0);
    gachaItem.itemId = Number(item['item_id'] ?? 0);
    gachaItem.count = Number(item['count'] ?? 1);
    gachaItem.time = String(item['time'] ?? '');
    gachaItem.name = String(item['name'] ?? '');
    gachaItem.itemType = String(item['item_type'] ?? '');
    gachaItem.rankType = Number(item['rank_type'] ?? 0);
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
