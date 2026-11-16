import { BackpackArchive, BackpackFilter, BackpackImport, BackpackItem, BackpackManualInput } from '../model/BackpackData';
import { BackpackCatalog } from '../model/BackpackCatalog';
import { BackpackService } from '../service/BackpackService';
import { CultivateProject } from '../data/repo/CultivationRepo';
import { BackpackScoreEdit, BackpackScoreProfile, BackpackScoreSettings, BackpackScoring } from '../model/BackpackScore';
import { BackpackScoreService } from '../service/BackpackScoreService';
import { WikiAvatarMeta } from '../service/WikiMetaService';

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
  scoreSettings: BackpackScoreSettings = new BackpackScoreSettings();
  private generation: number = 0;
  private displayRequest: number = 0;
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
      this.scoreSettings = BackpackScoreService.load();
      this.recalculateScores();
    } catch (e) {
      if (generation === this.generation) { this.message = (e as Error).message; }
    } finally { if (generation === this.generation) { this.loading = false; } }
  }

  /** Reload labels and keep the current archive, filter and active editor generations. */
  async refreshDisplay(): Promise<boolean> {
    const request: number = ++this.displayRequest;
    const generation: number = this.generation;
    const id: number = this.currentId;
    if (!this.active || id <= 0) { return false; }
    try {
      const items: BackpackItem[] = await BackpackService.getItems(id);
      if (request !== this.displayRequest || generation !== this.generation || id !== this.currentId) { return false; }
      this.allItems = items;
      this.recalculateScores();
      return true;
    } catch (e) { return false; }
  }

  beginScoreEdit(): BackpackScoreEdit {
    if (!this.active || this.loading || this.currentId <= 0) { throw new Error('请先选择背包档案'); }
    this.scoreSettings = BackpackScoreService.load();
    const edit: BackpackScoreEdit = new BackpackScoreEdit();
    edit.archiveId = this.currentId;
    edit.generation = this.generation;
    edit.settingsRevision = this.scoreSettings.revision;
    edit.profile = BackpackScoreService.active(this.scoreSettings);
    return edit;
  }

  saveScore(edit: BackpackScoreEdit, profile: BackpackScoreProfile, deletedIds: string[] = []): void {
    this.verifyScoreOwner(edit);
    this.scoreSettings = BackpackScoreService.save(profile, edit.settingsRevision, deletedIds);
    this.recalculateScores();
  }

  private verifyScoreOwner(edit: BackpackScoreEdit): void {
    if (!this.active || this.loading || edit.archiveId !== this.currentId || edit.generation !== this.generation) {
      throw new Error('背包档案或页面已改变，请重新打开评分设置');
    }
  }

  private recalculateScores(): void {
    const profile: BackpackScoreProfile = BackpackScoreService.active(this.scoreSettings);
    for (const item of this.allItems) {
      if (item.kind === 'reliquary') { item.score = BackpackScoring.calculate(item.appendPropIds, profile); }
    }
    this.allItems = this.allItems.slice();
    this.applyFilter();
  }

  currentArchive(): BackpackArchive | undefined {
    return this.archives.find((archive: BackpackArchive): boolean => archive.id === this.currentId);
  }

  equippedAvatarLabel(avatarId: number | undefined): string {
    if (avatarId === undefined) { return '装备状态未知'; }
    if (avatarId === 0) { return '未装备'; }
    const name: string = BackpackService.equippedAvatar(avatarId)?.name ?? '';
    return `已装备 · ${name || `角色 ID ${avatarId}`}`;
  }

  equippedAvatarIcon(avatarId: number | undefined): string {
    if (avatarId === undefined || avatarId === 0) { return ''; }
    const avatar: WikiAvatarMeta | undefined = BackpackService.equippedAvatar(avatarId);
    return avatar?.sideIcon || avatar?.icon || '';
  }

  purchasedStatNames(ids: number[]): string[] {
    return BackpackService.purchasedStatNames(ids);
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
    prepared.targetCreatedAt = archive.createdAt;
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
  private requireItemArchive(item: BackpackItem): number {
    if (!this.active || this.loading || item.archiveId !== this.currentId) {
      throw new Error('背包档案已改变，请重新选择物品');
    }
    return item.archiveId;
  }
  async categorize(item: BackpackItem, category: number): Promise<void> {
    const id: number = this.requireItemArchive(item);
    await BackpackService.categorize(id, item.instanceId, category, item.rawJson);
    await this.load(id);
  }
  async updateCount(item: BackpackItem, count: string): Promise<void> {
    const id: number = this.requireItemArchive(item);
    await BackpackService.updateCount(id, item.instanceId, count, item.rawJson);
    await this.load(id);
  }
  async removeItem(item: BackpackItem): Promise<void> {
    const id: number = this.requireItemArchive(item);
    await BackpackService.removeItem(id, item.instanceId, item.rawJson);
    await this.load(id);
  }
}
