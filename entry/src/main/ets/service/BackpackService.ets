import { BackpackArchive, BackpackCategory, BackpackImport, BackpackItem, BackpackManualInput } from '../model/BackpackData';
import { BackpackCatalog } from '../model/BackpackCatalog';
import { BackpackRepo } from '../data/repo/BackpackRepo';
import { CultivateProject, CultivationRepo } from '../data/repo/CultivationRepo';
import { UIIFService } from './UIIFService';
import { AppContextProvider } from '../common/AppContext';
import { util } from '@kit.ArkTS';
import { WikiMetaService, WikiWeaponMeta } from './WikiMetaService';

class BackpackReference {
  ids: number[] = [];
  kind: string = '';
  name: string = '';
  icon: string = '';
  rank: number = 0;
  type: number = 0;
}

/** Offline consumption only. No injection, game process, online inventory or account dependency. */
export class BackpackService {
  private static references: Map<string, BackpackReference> | undefined = undefined;

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
    const weapons: Map<number, WikiWeaponMeta> = new Map<number, WikiWeaponMeta>();
    for (const weapon of await WikiMetaService.getWeapons()) { weapons.set(weapon.id, weapon); }
    for (const item of items) {
      item.name = `${BackpackCatalog.CATEGORY_NAMES[item.category]} #${item.itemId}`;
      if (item.kind === 'weapon') {
        const weapon: WikiWeaponMeta | undefined = weapons.get(item.itemId);
        if (weapon !== undefined) { item.name = weapon.name; item.icon = weapon.icon; item.rarity = weapon.rankLevel; item.iconCategory = 'EquipIcon'; }
      } else {
        const reference: BackpackReference | undefined = references.get(`${item.kind}:${item.itemId}`);
        if (reference !== undefined) {
          item.name = reference.name; item.icon = reference.icon; item.rarity = reference.rank;
          item.iconCategory = item.kind === 'reliquary' ? 'RelicIcon' : 'ItemIcon';
        }
      }
    }
    return items;
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
    const archive: BackpackArchive = await BackpackRepo.getArchive(id);
    const items: BackpackItem[] = await BackpackRepo.getItems(id);
    UIIFService.validateSnapshot(archive.uid, archive.documentJson, items);
    return UIIFService.export(archive.documentJson, items);
  }
  static syncMaterials(id: number, projectId: number, replace: boolean): Promise<number> {
    return BackpackRepo.syncMaterials(id, projectId, replace);
  }
  static categorize(id: number, instanceId: string, category: number): Promise<void> {
    return BackpackRepo.categorize(id, instanceId, category);
  }
  static updateCount(id: number, instanceId: string, count: string): Promise<void> { return BackpackRepo.updateCount(id, instanceId, count); }
  static removeItem(id: number, instanceId: string): Promise<void> { return BackpackRepo.removeItem(id, instanceId); }
}
