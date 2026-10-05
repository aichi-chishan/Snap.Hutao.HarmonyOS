import { GachaEventMeta, WikiAvatarMeta, WikiWeaponMeta, WikiMetaService } from './WikiMetaService';
import { WishHistoryCategory, WishHistoryItem, WishHistoryOccurrence, WishHistoryPool,
  WishHistorySnapshot } from '../model/WishHistory';

/** Read-only, local metadata projection; no account, network or personal archive dependency. */
export class WishHistoryService {
  static readonly DAY_MS: number = 86400000;
  // Pinned Remastered 3f0d1f3: AvatarIds.StandardWishIds / WeaponIds.OrangeStandardWishIds.
  private static readonly STANDARD_AVATARS: number[] = [10000003, 10000016, 10000041, 10000042,
    10000035, 10000069, 10000079, 10000109, 10000006, 10000021, 10000015, 10000062];
  private static readonly STANDARD_ORANGE_WEAPONS: number[] = [11501, 11502, 12501, 12502,
    13502, 13505, 14501, 14502, 15501, 15502, 15515, 15518];

  static async load(now: number = Date.now()): Promise<WishHistorySnapshot> {
    const events: GachaEventMeta[] = await WikiMetaService.getGachaEvents();
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    return WishHistoryService.build(events, avatars, weapons, now);
  }

  static build(events: GachaEventMeta[], avatars: WikiAvatarMeta[], weapons: WikiWeaponMeta[],
    now: number): WishHistorySnapshot {
    const result: WishHistorySnapshot = new WishHistorySnapshot();
    result.asOf = now;
    result.sourceEventCount = events.length;
    result.metadataAvailable = events.length > 0;
    if (!WishHistoryService.validTime(now)) { throw new Error('无法读取当前时间'); }
    const avatarMap: Map<number, WikiAvatarMeta> = new Map();
    const weaponMap: Map<number, WikiWeaponMeta> = new Map();
    for (const avatar of avatars) { avatarMap.set(avatar.id, avatar); }
    for (const weapon of weapons) { weaponMap.set(weapon.id, weapon); }
    const sorted: GachaEventMeta[] = [];
    for (const event of events) {
      if (!WishHistoryService.validTime(event.from) || !WishHistoryService.validTime(event.to)
        || event.to <= event.from) {
        result.ignoredInvalidEvents++;
        continue;
      }
      if (event.from > now) { result.ignoredFutureEvents++; continue; }
      sorted.push(event);
      result.earliestFrom = result.earliestFrom === 0 ? event.from : Math.min(result.earliestFrom, event.from);
      result.latestTo = Math.max(result.latestTo, event.to);
    }
    // Read newest first, matching Windows; deterministic ties do not depend on the input order.
    sorted.sort((a: GachaEventMeta, b: GachaEventMeta): number => b.from - a.from || b.to - a.to
      || a.type - b.type || a.order - b.order || WishHistoryService.compareText(a.name, b.name));
    result.startedEventCount = sorted.length;
    const items: Map<number, WishHistoryItem> = new Map();
    for (const event of sorted) {
      WishHistoryService.track(event, event.upOrange, true, items, avatarMap, weaponMap, result);
      WishHistoryService.track(event, event.upPurple, false, items, avatarMap, weaponMap, result);
    }
    items.forEach((item: WishHistoryItem): void => {
      if (!item.known) { result.unknownItemCount++; }
      result.items.push(item);
    });
    // Longest since the last UP END first, with a stable numeric identity tie-breaker.
    result.items.sort((a: WishHistoryItem, b: WishHistoryItem): number => a.lastTime - b.lastTime || a.id - b.id);
    return result;
  }

  private static track(event: GachaEventMeta, ids: number[], orange: boolean,
    items: Map<number, WishHistoryItem>, avatars: Map<number, WikiAvatarMeta>,
    weapons: Map<number, WikiWeaponMeta>, result: WishHistorySnapshot): void {
    for (const id of ids) {
      const avatar: boolean = Number.isInteger(id) && id >= 10000000 && id <= 99999999;
      const weapon: boolean = Number.isInteger(id) && id >= 10000 && id <= 99999;
      if (!avatar && !weapon) { result.ignoredItemIds++; continue; }
      if (avatar && WishHistoryService.STANDARD_AVATARS.indexOf(id) >= 0) { continue; }
      if (weapon && orange && WishHistoryService.STANDARD_ORANGE_WEAPONS.indexOf(id) >= 0) { continue; }
      let item: WishHistoryItem | undefined = items.get(id);
      if (item === undefined) {
        item = new WishHistoryItem();
        item.id = id;
        item.name = `#${id}`;
        item.iconCategory = avatar ? 'AvatarIcon' : 'EquipIcon';
        item.category = avatar
          ? (orange ? WishHistoryCategory.FiveStarAvatar : WishHistoryCategory.FourStarAvatar)
          : (orange ? WishHistoryCategory.FiveStarWeapon : WishHistoryCategory.FourStarWeapon);
        const avatarMeta: WikiAvatarMeta | undefined = avatars.get(id);
        const weaponMeta: WikiWeaponMeta | undefined = weapons.get(id);
        if (avatar && avatarMeta !== undefined) {
          item.name = avatarMeta.name.trim().length > 0 ? avatarMeta.name : `#${id}`;
          item.icon = avatarMeta.icon;
          item.known = true;
        } else if (weapon && weaponMeta !== undefined) {
          item.name = weaponMeta.name.trim().length > 0 ? weaponMeta.name : `#${id}`;
          item.icon = weaponMeta.icon;
          item.known = true;
        }
        item.lastTime = event.to;
        items.set(id, item);
      }
      let occurrence: WishHistoryOccurrence | undefined = item.histories.find((history: WishHistoryOccurrence): boolean =>
        history.from === event.from && history.to === event.to);
      if (occurrence === undefined) {
        occurrence = new WishHistoryOccurrence();
        occurrence.from = event.from;
        occurrence.to = event.to;
        item.histories.push(occurrence);
      }
      // Duplicate IDs/metadata rows must not duplicate pool details either.
      const existing: WishHistoryPool | undefined = occurrence.pools.find((pool: WishHistoryPool): boolean =>
        pool.type === event.type && pool.name === event.name && pool.version === event.version && pool.order === event.order);
      if (existing === undefined) {
        const pool: WishHistoryPool = new WishHistoryPool();
        pool.type = event.type;
        pool.name = event.name;
        pool.version = event.version;
        pool.order = event.order;
        occurrence.pools.push(pool);
      }
    }
  }

  static filter(items: WishHistoryItem[], category: WishHistoryCategory, keyword: string): WishHistoryItem[] {
    const query: string = keyword.trim().toLocaleLowerCase();
    return items.filter((item: WishHistoryItem): boolean => item.category === category
      && (query.length === 0 || item.name.toLocaleLowerCase().indexOf(query) >= 0 || `#${item.id}`.indexOf(query) >= 0));
  }

  static ongoing(item: WishHistoryItem, now: number): boolean {
    return item.histories.some((history: WishHistoryOccurrence): boolean => history.from <= now && now < history.to);
  }

  static countdown(item: WishHistoryItem, now: number): string {
    if (!WishHistoryService.validTime(now) || item.lastTime <= 0) { return '时间不可用'; }
    if (WishHistoryService.ongoing(item, now)) {
      // Overlapping pools need the end of the active occurrence, even if a later-started
      // shorter occurrence has already ended. Histories still retain Windows LastTime.
      let activeTo: number = 0;
      for (const history of item.histories) {
        if (history.from <= now && now < history.to) { activeTo = Math.max(activeTo, history.to); }
      }
      const days: number = Math.floor((activeTo - now) / WishHistoryService.DAY_MS);
      return days > 0 ? `正在 UP · 剩余 ${days} 天` : '正在 UP · 剩余不足 1 天';
    }
    const days: number = Math.max(0, Math.floor((now - item.lastTime) / WishHistoryService.DAY_MS));
    return days > 0 ? `距上次 UP 结束 ${days} 天` : '上次 UP 结束不足 1 天';
  }

  /** GachaEvent dates are CN metadata; do not let the device time zone shift the displayed day. */
  static dateText(ms: number): string {
    if (!WishHistoryService.validTime(ms)) { return '--'; }
    const date: Date = new Date(ms + 8 * 3600000);
    return `${date.getUTCFullYear()}-${WishHistoryService.pad(date.getUTCMonth() + 1)}-${WishHistoryService.pad(date.getUTCDate())}`;
  }

  static periodText(pool: WishHistoryPool): string {
    const order: string = pool.order === 1 ? '上半' : (pool.order === 2 ? '下半' : `第 ${pool.order} 期`);
    return `${pool.version.length > 0 ? pool.version : '版本未知'} · ${order}`;
  }

  static poolTypeText(type: number): string {
    if (type === 301) { return '角色活动祈愿'; }
    if (type === 400) { return '角色活动祈愿-2'; }
    if (type === 302) { return '武器活动祈愿'; }
    if (type === 500) { return '集录祈愿'; }
    return `祈愿类型 ${type}`;
  }

  private static validTime(ms: number): boolean { return Number.isFinite(ms) && ms > 0 && ms <= 8640000000000000 - 8 * 3600000; }
  private static pad(value: number): string { return value < 10 ? `0${value}` : `${value}`; }
  private static compareText(a: string, b: string): number { return a < b ? -1 : (a > b ? 1 : 0); }
}
