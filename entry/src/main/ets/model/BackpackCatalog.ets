import { BackpackCategory, BackpackFilter, BackpackItem } from './BackpackData';

/** Pinned Windows category rules; unmatched IDs remain explicitly unclassified. */
export class BackpackCatalog {
  static readonly CATEGORY_NAMES: string[] = ['武器', '圣遗物', '养成道具', '食物', '材料', '小道具', '任务', '贵重道具', '摆设', '未分类'];

  static category(itemId: number, materialType: number | undefined): BackpackCategory {
    if ((itemId >= 201 && itemId <= 207) || (itemId >= 141001 && itemId <= 200000) || itemId === 220007) {
      return BackpackCategory.PreciousItem;
    }
    if (itemId >= 108000 && itemId <= 108999) { return BackpackCategory.Food; }
    if (materialType !== undefined && ((itemId >= 101001 && itemId <= 101500) || (itemId >= 130001 && itemId <= 141000))) {
      return BackpackCategory.Material;
    }
    if (itemId >= 220000 && itemId <= 221000) { return BackpackCategory.Gadget; }
    if (materialType === undefined) { return BackpackCategory.Unknown; }
    if ([14, 11, 20, 6, 7, 13, 72, 73].includes(materialType)) { return BackpackCategory.UpgradeItem; }
    if ([2, 49, 64, 41, 46].includes(materialType)) { return BackpackCategory.Quest; }
    if ([5, 8, 10, 12, 22, 24, 36, 47].includes(materialType)) { return BackpackCategory.PreciousItem; }
    if ([1, 37].includes(materialType)) { return BackpackCategory.Food; }
    if ([21, 33, 32, 18, 36, 53, 28].includes(materialType)) { return BackpackCategory.Gadget; }
    return BackpackCategory.Material;
  }

  static filter(items: BackpackItem[], filter: BackpackFilter): BackpackItem[] {
    const keyword: string = filter.keyword.trim().toLocaleLowerCase();
    const result: BackpackItem[] = items.filter((item: BackpackItem): boolean => {
      return (filter.category < 0 || filter.category === item.category) && (!filter.lockedOnly || item.isLocked === true) &&
        (keyword.length === 0 || `${item.name} ${item.itemId} ${item.guid} ${item.instanceId}`.toLocaleLowerCase().includes(keyword));
    });
    result.sort((left: BackpackItem, right: BackpackItem): number => {
      let diff: number = 0;
      if (filter.sort === 'score') {
        if (left.score.available !== right.score.available) { return left.score.available ? -1 : 1; }
        if (left.score.available) { diff = right.score.value - left.score.value; }
      }
      else if (filter.sort === 'level') { diff = right.level - left.level; }
      else if (filter.sort === 'count') { diff = right.count - left.count; }
      else if (filter.sort === 'rarity') { diff = right.rarity - left.rarity; }
      else if (filter.sort === 'name') { diff = left.name.localeCompare(right.name); }
      if (diff !== 0) { return diff; }
      if (left.itemId !== right.itemId) { return left.itemId - right.itemId; }
      return left.instanceId.localeCompare(right.instanceId);
    });
    return result;
  }

  static detail(item: BackpackItem): string {
    if (item.kind === 'weapon') {
      const ranks: string[] = [];
      item.affixMap.forEach((index: number, id: number) => ranks.push(`${id} → ${index + 1} 阶`));
      return `Lv.${item.level} · 突破 ${item.promoteLevel} · 精炼 ${ranks.length > 0 ? ranks.join('、') : '未提供'}`;
    }
    if (item.kind === 'reliquary') { return `+${item.level - 1} · 主词条 ${item.mainPropId} · ${item.appendPropIds.length} 条副词条记录`; }
    return `数量 ${item.count}`;
  }
}
