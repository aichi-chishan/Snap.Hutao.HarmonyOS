import { BackpackArchive, BackpackFilter, BackpackImport, BackpackItem, BackpackManualInput } from '../model/BackpackData';
import { BackpackCatalog } from '../model/BackpackCatalog';
import { BackpackService } from '../service/BackpackService';
import { CultivateProject } from '../data/repo/CultivationRepo';

@Observed
export class BackpackViewModel {
  archives: BackpackArchive[] = [];
  projects: CultivateProject[] = [];
  currentId: number = 0;
  allItems: BackpackItem[] = [];
  items: BackpackItem[] = [];
  loading: boolean = false;
  message: string = '';
  filter: BackpackFilter = new BackpackFilter();
  private generation: number = 0;
  private active: boolean = true;

  activate(): void { this.active = true; }
  invalidate(): void { this.active = false; this.generation++; this.loading = false; }

  async load(preferredId: number = 0): Promise<void> {
    if (!this.active) { return; }
    const generation: number = ++this.generation;
    this.loading = true;
    this.message = '';
    try {
      const archives: BackpackArchive[] = await BackpackService.getArchives();
      const projects: CultivateProject[] = await BackpackService.getProjects();
      const selected: BackpackArchive | undefined = archives.find((archive: BackpackArchive): boolean => archive.id === preferredId) ??
        archives.find((archive: BackpackArchive): boolean => archive.isSelected) ?? archives[0];
      const items: BackpackItem[] = selected === undefined ? [] : await BackpackService.getItems(selected.id);
      if (generation !== this.generation) { return; }
      this.archives = archives;
      this.projects = projects;
      this.currentId = selected?.id ?? 0;
      this.allItems = items;
      this.applyFilter();
    } catch (e) {
      if (generation === this.generation) { this.message = (e as Error).message; }
    } finally { if (generation === this.generation) { this.loading = false; } }
  }

  currentArchive(): BackpackArchive | undefined {
    return this.archives.find((archive: BackpackArchive): boolean => archive.id === this.currentId);
  }

  applyFilter(): void { this.items = BackpackCatalog.filter(this.allItems, this.filter); }
  async select(id: number): Promise<void> { await BackpackService.selectArchive(id); await this.load(id); }
  async create(name: string, uid: string): Promise<void> { await this.load(await BackpackService.createArchive(name, uid)); }
  async remove(id: number): Promise<void> { await BackpackService.deleteArchive(id); await this.load(); }
  async prepare(text: string): Promise<BackpackImport> {
    const archive: BackpackArchive | undefined = this.currentArchive();
    const generation: number = this.generation;
    if (archive === undefined || !this.active) { throw new Error('请先选择背包档案'); }
    const prepared: BackpackImport = await BackpackService.prepareImport(text);
    if (!this.active || generation !== this.generation || archive.id !== this.currentId) {
      throw new Error('档案选择已改变，请重新导入');
    }
    prepared.targetArchiveId = archive.id;
    prepared.targetUid = archive.uid;
    prepared.targetUpdatedAt = archive.updatedAt;
    return prepared;
  }
  async importSnapshot(id: number, prepared: BackpackImport): Promise<void> {
    await BackpackService.importSnapshot(id, prepared);
    await this.load(id);
  }
  async addManual(input: BackpackManualInput): Promise<void> {
    const id: number = this.currentId;
    await BackpackService.addManual(id, input);
    await this.load(id);
  }
  exportArchive(id: number): Promise<string> { return BackpackService.exportArchive(id); }
  syncMaterials(id: number, projectId: number, replace: boolean): Promise<number> {
    return BackpackService.syncMaterials(id, projectId, replace);
  }
  async categorize(instanceId: string, category: number): Promise<void> {
    const id: number = this.currentId;
    await BackpackService.categorize(id, instanceId, category);
    await this.load(id);
  }
  async updateCount(instanceId: string, count: string): Promise<void> {
    const id: number = this.currentId;
    await BackpackService.updateCount(id, instanceId, count);
    await this.load(id);
  }
  async removeItem(instanceId: string): Promise<void> {
    const id: number = this.currentId;
    await BackpackService.removeItem(id, instanceId);
    await this.load(id);
  }
}
