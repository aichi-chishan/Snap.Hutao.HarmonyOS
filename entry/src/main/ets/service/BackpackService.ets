import { BackpackArchive, BackpackArchiveSnapshot, BackpackCategory, BackpackImport, BackpackItem, BackpackManualInput } from '../model/BackpackData';
import { BackpackCatalog } from '../model/BackpackCatalog';
import { BackpackRepo } from '../data/repo/BackpackRepo';
import { CultivateProject, CultivationRepo } from '../data/repo/CultivationRepo';
import { UIIFService } from './UIIFService';
import { AppContextProvider } from '../common/AppContext';
import { util } from '@kit.ArkTS';
import { BackpackScoring, BackpackScoreProfile } from '../model/BackpackScore';
import { BackpackScoreService } from './BackpackScoreService';
import { MetaMaterial, WikiAvatarMeta, WikiMetaService, WikiWeaponMeta } from './WikiMetaService';
import { InventoryMaterialReference } from '../model/InventoryMaterialReference';
import { LocalizedGameDataService } from './LocalizedGameDataService';
import { BaseValueService } from './BaseValueService';

class BackpackReference {
  ids: number[] = [];
  kind: string = '';
  name: string = '';
  icon: string = '';
  rank: number = 0;
  type: number = 0;
}

class BackpackRelicFilterMeta {
  equipType: number = 0;
  setId: number = 0;
  setName: string = '';
}

class BackpackFoodFilterMeta {
  type: number = 0;
  quality: number = -1;
}

class BackpackFilterMetadata {
  reliquaries: Record<string, BackpackRelicFilterMeta> = {};
  food: Record<string, BackpackFoodFilterMeta> = {};
}

/** Offline consumption only. No injection, game process, online inventory or account dependency. */
export class BackpackService {
  private static references: Map<string, BackpackReference> | undefined = undefined;
  private static filterMetadata: BackpackFilterMetadata | undefined = undefined;

  /** Fixed application reference data, deliberately outside the exact 17-file update cohort. */
  private static async catalog(): Promise<Map<string, BackpackReference>> {
    if (BackpackService.references !== undefined) { return BackpackService.references; }
    const bytes: Uint8Array = await AppContextProvider.getResourceManager().getRawFileContent('backpack/reference.json');
    const rows: BackpackReference[] = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as BackpackReference[];
    const references: Map<string, BackpackReference> = new Map<string, BackpackReference>();
    if (!Array.isArray(rows)) { throw new Error('背包参考元数据无效'); }
    for (const row of rows) {
      if (row === null || !Array.isArray(row.ids) || typeof row.name !== 'string' || typeof row.icon !== 'string' ||
        !Number.isSafeInteger(row.type) || !Number.isSafeInteger(row.rank) || !['material', 'reliquary', 'furniture'].includes(row.kind)) {
        throw new Error('背包参考元数据无效');
      }
      for (const id of row.ids) {
        const key: string = `${row.kind}:${id}`;
        if (!Number.isSafeInteger(id) || id <= 0 || references.has(key)) { throw new Error('背包参考物品 ID 无效'); }
        references.set(key, row);
      }
    }
    BackpackService.references = references;
    return references;
  }

  static getArchives(): Promise<BackpackArchive[]> { return BackpackRepo.getArchives(); }
  static createArchive(name: string, uid: string): Promise<number> { return BackpackRepo.createArchive(name, uid); }
  static selectArchive(id: number): Promise<void> { return BackpackRepo.selectArchive(id); }
  static deleteArchive(id: number): Promise<void> { return BackpackRepo.deleteArchive(id); }
  static getProjects(): Promise<CultivateProject[]> { return CultivationRepo.getProjects(); }

  static async cultivationMaterialMetadata(): Promise<Map<number, MetaMaterial>> {
    const references: Map<string, BackpackReference> = await BackpackService.catalog();
    const names: Map<number, string> = await LocalizedGameDataService.names('material_meta.json');
    const materials: Map<number, MetaMaterial> = new Map<number, MetaMaterial>();
    for (const id of InventoryMaterialReference.itemIds()) {
      const reference: BackpackReference | undefined = references.get(`material:${id}`);
      if (reference === undefined) { continue; }
      const material: MetaMaterial = new MetaMaterial();
      material.n = names.get(id) ?? reference.name;
      material.canonicalName = reference.name;
      material.i = reference.icon; material.r = reference.rank;
      materials.set(id, material);
    }
    return materials;
  }

  private static async classify(items: BackpackItem[]): Promise<void> {
    const references: Map<string, BackpackReference> = await BackpackService.catalog();
    for (const item of items) {
      if (item.kind === 'material' && item.category === BackpackCategory.Unknown) {
        item.category = BackpackCatalog.category(item.itemId, references.get(`material:${item.itemId}`)?.type);
      }
    }
  }

  static async getItems(id: number): Promise<BackpackItem[]> {
    const items: BackpackItem[] = await BackpackRepo.getItems(id);
    await BackpackService.classify(items);
    const references: Map<string, BackpackReference> = await BackpackService.catalog();
    const filters: BackpackFilterMetadata = await BackpackService.getFilterMetadata();
    const locale: string = LocalizedGameDataService.current();
    const materialNames: Map<number, string> = await LocalizedGameDataService.names('material_meta.json', locale);
    const relicNames: Map<number, string> = await LocalizedGameDataService.names('Reliquary.json', locale);
    const setNames: Map<number, string> = await LocalizedGameDataService.names('ReliquarySet.json', locale);
    const furnitureNames: Map<number, string> = await LocalizedGameDataService.names('Furniture.json', locale);
    const weapons: Map<number, WikiWeaponMeta> = new Map<number, WikiWeaponMeta>();
    for (const weapon of await WikiMetaService.getWeapons()) { weapons.set(weapon.id, weapon); }
    if (items.some((item: BackpackItem): boolean => (item.equippedAvatarId ?? 0) > 0)) {
      await WikiMetaService.getAvatars();
    }
    const profile: BackpackScoreProfile = BackpackScoreService.active(BackpackScoreService.load());
    for (const item of items) {
      if (item.kind === 'reliquary') { item.score = BackpackScoring.calculate(item.appendPropIds, profile); }
      item.name = `${BackpackCatalog.CATEGORY_NAMES[item.category]} #${item.itemId}`;
      if (item.kind === 'weapon') {
        const weapon: WikiWeaponMeta | undefined = weapons.get(item.itemId);
        if (weapon !== undefined) {
          item.name = weapon.name; item.icon = weapon.icon; item.rarity = weapon.rankLevel; item.iconCategory = 'EquipIcon';
          item.weaponType = weapon.weaponType;
        }
      } else {
        const reference: BackpackReference | undefined = references.get(`${item.kind}:${item.itemId}`);
        if (reference !== undefined) {
          item.name = reference.name; item.icon = reference.icon; item.rarity = reference.rank;
          item.iconCategory = item.kind === 'reliquary' ? 'RelicIcon' : 'ItemIcon';
        }
        if (item.kind === 'reliquary') {
          const relic: BackpackRelicFilterMeta | undefined = filters.reliquaries[item.icon];
          item.name = relicNames.get(item.itemId) ?? item.name;
          if (relic !== undefined) {
            item.equipType = relic.equipType; item.setId = relic.setId;
            item.setName = setNames.get(relic.setId) ?? relic.setName;
          }
        } else if (item.kind === 'furniture') {
          item.name = furnitureNames.get(item.itemId) ?? item.name;
        } else {
          item.name = materialNames.get(item.itemId) ?? item.name;
          if (item.category === BackpackCategory.Food) {
            const food: BackpackFoodFilterMeta | undefined = filters.food[String(item.itemId)];
            if (food !== undefined) { item.foodType = food.type; item.foodQuality = food.quality; }
          }
        }
      }
    }
    return items;
  }

  static equippedAvatar(avatarId: number): WikiAvatarMeta | undefined {
    return WikiMetaService.avatarOf(avatarId);
  }

  static purchasedStatNames(ids: number[]): string[] {
    const labels: string[] = [];
    // Purchased affixes use FightProperty values directly. Only rolled substats use affix IDs.
    for (const id of ids) {
      const property: number = id === 2 ? 1 : (id === 5 ? 4 : (id === 8 ? 7 : id));
      const name: string = BaseValueService.fightPropName(property) || `未知属性 #${id}`;
      if (!labels.includes(name)) { labels.push(name); }
    }
    return labels;
  }

  private static async getFilterMetadata(): Promise<BackpackFilterMetadata> {
    if (BackpackService.filterMetadata !== undefined) { return BackpackService.filterMetadata; }
    const bytes: Uint8Array = await AppContextProvider.getResourceManager().getRawFileContent('backpack/filters.json');
    const data: BackpackFilterMetadata = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as BackpackFilterMetadata;
    BackpackService.filterMetadata = data;
    return data;
  }

  static async prepareImport(text: string): Promise<BackpackImport> {
    const parsed: BackpackImport = UIIFService.parse(text);
    await BackpackService.classify(parsed.items);
    return parsed;
  }

  static importSnapshot(id: number, parsed: BackpackImport): Promise<void> { return BackpackRepo.replaceSnapshot(id, parsed); }
  static async addManual(id: number, input: BackpackManualInput): Promise<void> {
    const item: BackpackItem = UIIFService.manual(input);
    await BackpackService.classify([item]);
    await BackpackRepo.addManual(id, item);
  }
  static async exportArchive(id: number): Promise<string> {
    const snapshot: BackpackArchiveSnapshot = BackpackRepo.readSnapshot(id);
    const archive: BackpackArchive = snapshot.archive;
    const items: BackpackItem[] = snapshot.items;
    UIIFService.validateSnapshot(archive.uid, archive.documentJson, items);
    return UIIFService.export(archive.documentJson, items);
  }
  static syncMaterials(id: number, projectId: number, replace: boolean): Promise<number> {
    return BackpackRepo.syncMaterials(id, projectId, replace);
  }
  static categorize(id: number, instanceId: string, category: number, expectedRawJson?: string): Promise<void> {
    return BackpackRepo.categorize(id, instanceId, category, expectedRawJson);
  }
  static updateCount(id: number, instanceId: string, count: string, expectedRawJson?: string): Promise<void> {
    return BackpackRepo.updateCount(id, instanceId, count, expectedRawJson);
  }
  static removeItem(id: number, instanceId: string, expectedRawJson?: string): Promise<void> {
    return BackpackRepo.removeItem(id, instanceId, expectedRawJson);
  }
}
