import { GachaItem } from '../model/GachaItem';
import { GachaType } from '../model/GachaType';
import { LocalePolicy } from '../model/LocalePolicy';
import { GameDataService } from './GameDataService';
import { LocalizedGameDataService } from './LocalizedGameDataService';
import { WikiMetaService } from './WikiMetaService';

enum GachaItemKind {
  Avatar = 0,
  Weapon = 1,
}

export class GachaItemIdentityService {
  // Windows ModelInterchangeUIGFItemTypeAvatar/Weapon, in LocalePolicy.locales() order.
  private static readonly TYPES: string[][] = [
    ['角色', '武器'], ['角色', '武器'], ['Character', 'Weapon'], ['Rolle', 'Waffe'], ['Personaje', 'Arma'],
    ['Personnage', 'Arme'], ['Karakter', 'Senjata'], ['Ruolo', 'Arma'], ['キャラクター', '武器'],
    ['캐릭터', '무기'], ['Personagem', 'Arma'], ['Персонаж', 'Оружие'], ['ตัวละคร', 'อาวุธ'],
    ['Rol', 'Silah'], ['Nhân vật', 'Vũ khí'],
  ];
  private static readonly indexes: Map<string, Promise<Map<string, number>>> =
    new Map<string, Promise<Map<string, number>>>();
  private static metadataVersion: string = '';

  /** Recover the identity of regular wishes whose original response omitted item_id. */
  static async resolveMissing(items: GachaItem[], sourceLanguage: string = ''): Promise<GachaItem[]> {
    const missing: Map<string, GachaItem[]> = new Map<string, GachaItem[]>();
    for (const item of items) {
      if (item.itemId !== 0 || !GachaType.isStandard(GachaType.queryTypeOf(item.gachaType))) { continue; }
      const rows: GachaItem[] = missing.get(item.itemType) ?? [];
      rows.push(item);
      missing.set(item.itemType, rows);
    }
    if (missing.size === 0) { return items; }
    const version: string = GameDataService.getInstance().remoteVersion();
    if (GachaItemIdentityService.metadataVersion !== version) {
      GachaItemIdentityService.metadataVersion = version;
      GachaItemIdentityService.indexes.clear();
    }
    const locale: string = LocalePolicy.supported(sourceLanguage) ? LocalePolicy.resourceLocale(sourceLanguage) : '';
    for (const type of missing.keys()) {
      const kind: GachaItemKind | undefined = GachaItemIdentityService.kind(type);
      if (kind === undefined) { continue; }
      const aliases: Map<string, number> = await GachaItemIdentityService.index(type, kind, locale);
      for (const item of missing.get(type) ?? []) {
        const id: number | undefined = aliases.get(`${item.rankType}:${item.name}`);
        if (id !== undefined && id > 0) { item.itemId = id; }
      }
    }
    return items;
  }

  private static kind(type: string): GachaItemKind | undefined {
    if (GachaItemIdentityService.TYPES.some((labels: string[]): boolean => labels[GachaItemKind.Avatar] === type)) {
      return GachaItemKind.Avatar;
    }
    if (GachaItemIdentityService.TYPES.some((labels: string[]): boolean => labels[GachaItemKind.Weapon] === type)) {
      return GachaItemKind.Weapon;
    }
    return undefined;
  }

  private static index(type: string, kind: GachaItemKind, locale: string): Promise<Map<string, number>> {
    const key: string = `${kind}:${type}:${locale}`;
    const cached: Promise<Map<string, number>> | undefined = GachaItemIdentityService.indexes.get(key);
    if (cached !== undefined) { return cached; }
    const loading: Promise<Map<string, number>> = GachaItemIdentityService.loadIndex(type, kind, locale).catch(() => {
      if (GachaItemIdentityService.indexes.get(key) === loading) { GachaItemIdentityService.indexes.delete(key); }
      return new Map<string, number>();
    });
    GachaItemIdentityService.indexes.set(key, loading);
    return loading;
  }

  private static async loadIndex(type: string, kind: GachaItemKind, locale: string): Promise<Map<string, number>> {
    const aliases: Map<string, number> = new Map<string, number>();
    const ranks: Map<number, number> = new Map<number, number>();
    if (kind === GachaItemKind.Avatar) {
      for (const item of await WikiMetaService.getAvatars()) {
        ranks.set(item.id, item.quality);
        GachaItemIdentityService.addAlias(aliases, item.canonicalName || item.name, item.quality, item.id);
      }
    } else {
      for (const item of await WikiMetaService.getWeapons()) {
        ranks.set(item.id, item.rankLevel);
        GachaItemIdentityService.addAlias(aliases, item.canonicalName || item.name, item.rankLevel, item.id);
      }
    }
    const locales: string[] = locale.length > 0 ? [locale] : LocalePolicy.locales().filter(
      (_locale: string, index: number): boolean => GachaItemIdentityService.TYPES[index][kind] === type);
    const table: string = kind === GachaItemKind.Avatar ? 'avatar_meta.json' : 'weapon_meta.json';
    for (const language of locales) {
      const names: Map<number, string> = await LocalizedGameDataService.names(table, language);
      names.forEach((name: string, id: number): void => {
        const rank: number | undefined = ranks.get(id);
        if (rank !== undefined) { GachaItemIdentityService.addAlias(aliases, name, rank, id); }
      });
    }
    return aliases;
  }

  private static addAlias(aliases: Map<string, number>, name: string, rank: number, id: number): void {
    if (name.length === 0 || rank < 3 || rank > 5 || !Number.isSafeInteger(id) || id <= 0) { return; }
    const key: string = `${rank}:${name}`;
    const known: number | undefined = aliases.get(key);
    aliases.set(key, known === undefined || known === id ? id : 0);
  }
}
