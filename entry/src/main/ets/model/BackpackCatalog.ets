import { BackpackCategory, BackpackFilter, BackpackFilterKind, BackpackItem, BackpackSortRule } from './BackpackData';

/** Pinned Windows category rules; unmatched IDs remain explicitly unclassified. */
export class BackpackCatalog {
  static readonly CATEGORY_NAMES: string[] = ['武器', '圣遗物', '养成道具', '食物', '材料', '小道具', '任务', '贵重道具', '摆设', '未分类'];
  static readonly RELIC_SLOTS: string[] = ['全部部位', '生之花', '死之羽', '时之沙', '空之杯', '理之冠'];
  static readonly WEAPON_TYPES: number[] = [0, 1, 11, 13, 10, 12];
  static readonly SORT_LABELS: Record<string, string> = {
    'id': '物品 ID', 'name': '名称', 'rarity': '品质', 'count': '数量', 'level': '等级',
    'refinement': '精炼', 'weaponType': '武器类型', 'lock': '锁定状态', 'score': '评分',
    'equipType': '圣遗物部位', 'set': '套装', 'mark': '标记状态',
  };

  static sortKeys(category: number): string[] {
    if (category === BackpackCategory.Weapon) { return ['rarity', 'level', 'refinement', 'weaponType', 'name', 'lock', 'count', 'id']; }
    if (category === BackpackCategory.Reliquary) { return ['score', 'level', 'rarity', 'equipType', 'set', 'lock', 'mark', 'id']; }
    return ['rarity', 'name', 'count', 'id'];
  }

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
    const choices: Map<BackpackFilterKind, Set<number>> = new Map<BackpackFilterKind, Set<number>>();
    for (const choice of filter.choices) {
      const values: Set<number> = choices.get(choice.kind) ?? new Set<number>();
      values.add(choice.code);
      choices.set(choice.kind, values);
    }
    const result: BackpackItem[] = items.filter((item: BackpackItem): boolean => {
      return (filter.category < 0 || filter.category === item.category) && (!filter.lockedOnly || item.isLocked === true)
        && BackpackCatalog.matchesChoices(item, choices)
        && (keyword.length === 0 || `${item.name} ${item.setName} ${item.itemId} ${item.guid} ${item.instanceId}`.toLocaleLowerCase().includes(keyword));
    });
    const legacy: boolean = filter.sortRules.length === 0;
    const sort: string = filter.sort === 'score-ascending' ? 'score' : filter.sort;
    const rules: BackpackSortRule[] = legacy
      ? [new BackpackSortRule(sort, filter.sort !== 'score-ascending' && sort !== 'name' && sort !== 'id')]
      : filter.sortRules;
    result.sort((left: BackpackItem, right: BackpackItem): number => {
      for (const rule of rules) {
        const difference: number = BackpackCatalog.compare(left, right, rule);
        if (difference !== 0) { return difference; }
      }
      if (legacy && sort === 'score' && left.level !== right.level) { return right.level - left.level; }
      if (left.itemId !== right.itemId) { return left.itemId - right.itemId; }
      return left.instanceId.localeCompare(right.instanceId);
    });
    return result;
  }

  /** Windows combines selections within the same filter with OR and across filters with AND. */
  private static matchesChoices(item: BackpackItem, choices: Map<BackpackFilterKind, Set<number>>): boolean {
    for (const kind of choices.keys()) {
      if (choices.get(kind)?.has(BackpackCatalog.filterValue(item, kind)) !== true) { return false; }
    }
    return true;
  }

  private static statusValue(actual: boolean | undefined): number {
    return actual === undefined ? 2 : Number(actual);
  }

  private static filterValue(item: BackpackItem, kind: BackpackFilterKind): number {
    switch (kind) {
      case BackpackFilterKind.Rarity: return item.rarity;
      case BackpackFilterKind.WeaponType: return item.weaponType;
      case BackpackFilterKind.EquipType: return item.equipType;
      case BackpackFilterKind.Set: return item.setId;
      case BackpackFilterKind.FoodType: return item.foodType;
      case BackpackFilterKind.FoodQuality: return item.foodQuality;
      case BackpackFilterKind.Lock: return BackpackCatalog.statusValue(item.isLocked);
      case BackpackFilterKind.Mark: return BackpackCatalog.statusValue(item.isMarked);
      case BackpackFilterKind.Equipped:
        return item.equippedAvatarId === undefined ? 2 : Number(item.equippedAvatarId > 0);
      case BackpackFilterKind.Purchased:
        return item.purchasedAppendPropIds === undefined ? 2 : Number(item.purchasedAppendPropIds.length > 0);
      default: return -1;
    }
  }

  private static compare(left: BackpackItem, right: BackpackItem, rule: BackpackSortRule): number {
    if (rule.key === 'name' || rule.key === 'set') {
      const a: string = rule.key === 'name' ? left.name : left.setName;
      const b: string = rule.key === 'name' ? right.name : right.setName;
      if ((a.length === 0) !== (b.length === 0)) { return a.length === 0 ? 1 : -1; }
      return rule.descending ? b.localeCompare(a) : a.localeCompare(b);
    }
    const a: number | undefined = BackpackCatalog.sortValue(left, rule.key);
    const b: number | undefined = BackpackCatalog.sortValue(right, rule.key);
    if (a === undefined) { return b === undefined ? 0 : 1; }
    if (b === undefined) { return -1; }
    return rule.descending ? b - a : a - b;
  }

  private static sortValue(item: BackpackItem, key: string): number | undefined {
    switch (key) {
      case 'score': return item.score.available ? item.score.value : undefined;
      case 'level': return item.level;
      case 'count': return item.count;
      case 'rarity': return item.rarity > 0 ? item.rarity : undefined;
      case 'refinement': {
        let rank: number = 0;
        for (const index of item.affixMap.values()) { rank = Math.max(rank, index + 1); }
        return rank > 0 ? rank : undefined;
      }
      case 'weaponType': return item.weaponType > 0 ? item.weaponType : undefined;
      case 'equipType': return item.equipType > 0 ? item.equipType : undefined;
      case 'lock': return item.isLocked === undefined ? undefined : Number(item.isLocked);
      case 'mark': return item.isMarked === undefined ? undefined : Number(item.isMarked);
      default: return item.itemId;
    }
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
