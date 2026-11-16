import { GachaItem } from '../model/GachaItem';
import { GachaItemCount } from '../model/GachaStatistics';
import { GachaType } from '../model/GachaType';
import { WikiAvatarMeta, WikiWeaponMeta, GachaEventMeta } from './WikiMetaService';

export class GachaCollection {
  avatars: GachaItemCount[] = [];
  weapons: GachaItemCount[] = [];
}

/** 对齐 Windows GachaStatisticsItemCounter / WeaponIds；仅统计记录条数，不把 count 当抽数。 */
export class GachaCollectionService {
  private static readonly BLUE_WEAPONS: number[] =
    [11301, 11302, 11306, 12301, 12302, 12305, 13303, 14301, 14302, 14304, 15301, 15302, 15304];
  private static readonly PURPLE_WEAPONS: number[] =
    [11401, 11402, 11403, 11405, 12401, 12402, 12403, 12405, 13401, 13407,
      14401, 14402, 14403, 14409, 15401, 15402, 15403, 15405, 15434];

  static count(items: GachaItem[], avatars: WikiAvatarMeta[], weapons: WikiWeaponMeta[],
    events: GachaEventMeta[], showUnobtained: boolean): GachaCollection {
    const catalog: Map<number, GachaItemCount> = new Map<number, GachaItemCount>();
    const names: Map<string, GachaItemCount> = new Map<string, GachaItemCount>();
    const counts: Map<string, GachaItemCount> = new Map<string, GachaItemCount>();
    const purple: Set<number> = new Set<number>(GachaCollectionService.PURPLE_WEAPONS);
    for (const event of events) {
      if (event.type === GachaType.WEAPON_EVENT) {
        for (const id of event.upPurple) { purple.add(id); }
      }
    }
    for (const avatar of avatars) {
      const entry: GachaItemCount = GachaCollectionService.entry(avatar.id, avatar.name, avatar.icon,
        '角色', avatar.quality);
      catalog.set(avatar.id, entry);
      names.set(`角色:${avatar.name}`, entry);
      if (avatar.canonicalName && !names.has(`角色:${avatar.canonicalName}`)) {
        names.set(`角色:${avatar.canonicalName}`, entry);
      }
      if (showUnobtained && (avatar.quality === 4 || avatar.quality === 5)) {
        counts.set(String(avatar.id), entry);
      }
    }
    for (const weapon of weapons) {
      const entry: GachaItemCount = GachaCollectionService.entry(weapon.id, weapon.name, weapon.icon,
        '武器', weapon.rankLevel);
      catalog.set(weapon.id, entry);
      names.set(`武器:${weapon.name}`, entry);
      if (weapon.canonicalName && !names.has(`武器:${weapon.canonicalName}`)) {
        names.set(`武器:${weapon.canonicalName}`, entry);
      }
      if (showUnobtained && (weapon.rankLevel === 5 ||
        (weapon.rankLevel === 4 && purple.has(weapon.id)) ||
        (weapon.rankLevel === 3 && GachaCollectionService.BLUE_WEAPONS.includes(weapon.id)))) {
        counts.set(String(weapon.id), entry);
      }
    }
    for (const item of items) {
      if (GachaType.isBeyond(item.gachaType)) { continue; }
      const type: string = item.itemId >= 10000000 || item.itemType === '角色' || item.itemType === 'Character'
        ? '角色' : '武器';
      const meta: GachaItemCount | undefined = catalog.get(item.itemId) ?? names.get(`${type}:${item.name}`);
      const key: string = meta !== undefined ? String(meta.itemId) : item.itemId > 0
        ? String(item.itemId) : `${type}:${item.rankType}:${item.name}`;
      let entry: GachaItemCount | undefined = counts.get(key);
      if (entry === undefined) {
        entry = meta ?? GachaCollectionService.entry(item.itemId, item.name, '', type, item.rankType);
        counts.set(key, entry);
      }
      entry.count++;
    }
    const result: GachaCollection = new GachaCollection();
    counts.forEach((entry: GachaItemCount): void => {
      if (entry.itemType === '角色' && (entry.rankType === 4 || entry.rankType === 5)) {
        result.avatars.push(entry);
      } else if (entry.itemType === '武器' && entry.rankType >= 3 && entry.rankType <= 5) {
        result.weapons.push(entry);
      }
    });
    // Windows 每个星级内按获取数量降序；同数保留原始顺序。
    const compare: (a: GachaItemCount, b: GachaItemCount) => number = (a: GachaItemCount, b: GachaItemCount): number =>
      b.rankType - a.rankType || b.count - a.count;
    result.avatars.sort(compare);
    result.weapons.sort(compare);
    return result;
  }

  private static entry(id: number, name: string, icon: string, type: string, rank: number): GachaItemCount {
    const entry: GachaItemCount = new GachaItemCount();
    entry.itemId = id; entry.name = name; entry.icon = icon; entry.itemType = type; entry.rankType = rank;
    return entry;
  }
}
