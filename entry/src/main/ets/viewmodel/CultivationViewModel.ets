import { CultivationDraft } from '../model/CultivationDraft';
import { CultivationProgressUpdate, CultivationService } from '../service/CultivationService';
import { CultivationPreparedEntry, CultivationSaveReport } from '../data/repo/CultivationRepo';
import { UserService } from '../service/UserService';
/**
 * CultivationViewModel.ets
 * 养成计划页状态容器：候选角色清单（来自角色接口）、目标等级输入、批量计算、结果展示；
 * 持久化计划（项目/条目/材料勾选，对齐 Windows CultivateProject/Entry/Item）。
 */
import { CharacterListItem } from '../model/CharacterData';
import { OfflineCultivationService } from '../service/OfflineCultivationService';
import { GachaEventMeta, MetaMaterial, WikiMetaService, WikiAvatarMeta, WikiWeaponMeta } from '../service/WikiMetaService';
import { CharacterService } from '../service/CharacterService';
import { CalculateService, CalculateInventoryCatalog, CalAvatarDelta } from '../service/CalculateService';
import { CalBatchResult } from '../model/Calculate';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { CultivationRepo, CultivateProject, CultivateEntry, CultivateEntryItem } from '../data/repo/CultivationRepo';
import { ResinStatisticsService, ResinStatisticsResult, ResinDropDistribution } from '../service/ResinStatisticsService';
import { InventoryRepo } from '../data/repo/InventoryRepo';
import { InventoryService } from '../service/InventoryService';
import { BackpackService } from '../service/BackpackService';
import { BackpackArchive } from '../model/BackpackData';
import { Logger } from '../common/Logger';
import { GameCalendarRules } from '../service/GameCalendarRules';
import { InventoryMaterialReference } from '../model/InventoryMaterialReference';
import { CultivationFilterKind, CultivationFilterToken } from '../model/CultivationFilterToken';

const TAG: string = 'CultivationViewModel';
/** 树脂统计世界等级偏好键（对齐 Windows SettingKeys.ResinStatisticsSelectedDropDistribution） */
const KEY_RESIN_WORLD_LEVEL: string = 'cultivation_resin_world_level';
const KEY_CURRENT_PROJECT: string = 'cultivation.current_project_id';

/** 养成候选角色 */
export class CultivateTarget {
  avatarId: number = 0;
  name: string = '';
  element: string = '';
  rarity: number = 0;
  level: number = 0;
  promoteLevel: number = 0;
  /** 官方头像 URL */
  icon: string = '';
  /** 目标等级（可编辑） */
  targetLevel: number = 90;
  /** 目标突破 */
  targetPromote: number = 6;
  /** 武器 id（当前武器） */
  weaponId: number = 0;
  weaponLevel: number = 0;
  weaponPromoteLevel: number = 0;
  selected: boolean = false;
  targetSkillLevel: number = 10;
  targetWeaponLevel: number = 90;
  offline: boolean = false;
}

export class InventoryMaterialView {
  itemId: number = 0;
  name: string = '';
  icon: string = '';
  planned: number = 0;
  required: number = 0;
  current: number = 0;
  shortfall: number = 0;
  known: boolean = false;
  availableToday: boolean = false;
}

@Observed
export class CultivationViewModel {
  /** 候选（全部角色） */
  targets: CultivateTarget[] = [];
  /** 已选角色 */
  selectedCount: number = 0;
  loading: boolean = false;
  computing: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 计算结果 */
  result: CalBatchResult | undefined = undefined;
  /** 养成计划：项目列表 / 当前项目 / 条目（含材料勾选） */
  projects: CultivateProject[] = [];
  currentProjectId: number = 0;
  planEntries: CultivateEntry[] = [];
  /** 计划写操作进行中（防连点） */
  planBusy: boolean = false;
  planLoading: boolean = false;
  planMessage: string = '';
  materialLabelVersion: number = 0;
  inventoryRows: InventoryMaterialView[] = [];
  private entryRequest: number = 0;
  private projectListRequest: number = 0;
  private bannerEvents: GachaEventMeta[] = [];
  private avatarMetadata: Map<number, WikiAvatarMeta> = new Map<number, WikiAvatarMeta>();
  private weaponMetadata: Map<number, WikiWeaponMeta> = new Map<number, WikiWeaponMeta>();
  private materialNames: Map<number, string> = new Map<number, string>();
  private prepared: CultivationPreparedEntry[] = [];
  private revision: number = 0;
  private loadedUid: string = '';

  invalidate(): void { this.revision++; this.loading = false; this.computing = false; this.result = undefined; this.prepared = []; }

  /** 树脂换算统计（当前项目聚合；对齐 Windows ResinStatistics） */
  resinStats: ResinStatisticsResult | undefined = undefined;
  /** 树脂统计世界等级（持久化，默认 9 对齐 Windows；偏好未就绪时回退默认） */
  resinWorldLevel: number = CultivationViewModel.loadResinWorldLevel();

  private static loadResinWorldLevel(): number {
    try {
      const lv: number = PreferencesStore.getNumber(KEY_RESIN_WORLD_LEVEL, 9);
      return lv >= 5 && lv <= 9 ? lv : 9;
    } catch (e) {
      return 9;
    }
  }

  async load(uid: string): Promise<void> {
    const changed: boolean = this.loadedUid !== uid;
    const previous: CultivateTarget[] = changed ? [] : this.targets;
    this.invalidate(); this.loadedUid = uid;
    const revision: number = this.revision;
    const account: number = UserService.getInstance().getCurrentUser()?.id ?? 0;
    this.loading = true; this.message = '';
    if (changed) { this.targets = []; this.selectedCount = 0; }
    try {
      const list: CultivateTarget[] = [];
      if (uid.length === 0) {
        const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
        for (const avatar of avatars) {
          if (avatar.cultivationItems.length < 6) { continue; }
          const target: CultivateTarget = new CultivateTarget();
          target.avatarId = avatar.id; target.name = avatar.name; target.icon = avatar.icon;
          target.level = 1; target.offline = true; target.rarity = avatar.quality;
          list.push(target);
        }
      } else {
        const details: CharacterListItem[] = await CharacterService.getInstance().fetchList(uid);
        if (details.some((detail: CharacterListItem): boolean => detail.id <= 0 || detail.level < 1)) { throw new Error('角色数据不完整，已保留上次列表'); }
        for (const detail of details) {
          const target: CultivateTarget = new CultivateTarget();
          target.avatarId = detail.id; target.name = detail.name; target.icon = detail.icon;
          target.level = detail.level; target.element = detail.element; target.rarity = detail.rarity;
          target.weaponId = detail.weapon.id; target.weaponLevel = detail.weapon.level;
          list.push(target);
        }
        this.applyTargetNames(list, await WikiMetaService.getAvatars());
      }
      if (revision !== this.revision || account !== (UserService.getInstance().getCurrentUser()?.id ?? 0)) { return; }
      const saved: string = PreferencesStore.getString(`cultivation.selection.${uid || 'offline'}`, '');
      let savedTargets: CultivateTarget[] = [];
      try { savedTargets = saved.length > 0 ? JSON.parse(saved) as CultivateTarget[] : []; } catch (e) { savedTargets = []; }
      for (const target of list) {
        const old: CultivateTarget | undefined = previous.find((value: CultivateTarget): boolean => value.avatarId === target.avatarId)
          ?? savedTargets.find((value: CultivateTarget): boolean => value.avatarId === target.avatarId);
        if (old !== undefined) {
          target.selected = old.selected === true;
          if (Number.isInteger(old.targetLevel) && old.targetLevel >= 1 && old.targetLevel <= 100) { target.targetLevel = old.targetLevel; }
          if (Number.isInteger(old.targetSkillLevel) && old.targetSkillLevel >= 1 && old.targetSkillLevel <= 10) { target.targetSkillLevel = old.targetSkillLevel; }
          if (Number.isInteger(old.targetWeaponLevel) && old.targetWeaponLevel >= 1 && old.targetWeaponLevel <= 90) { target.targetWeaponLevel = old.targetWeaponLevel; }
        }
      }
      this.targets = list; this.updateSelected();
      if (uid.length === 0) { this.message = '离线计划可正常使用；当前进度可手动编辑，登录后可重新同步'; }
    } catch (e) { if (revision === this.revision) { this.message = (e as Error).message; } }
    finally { if (revision === this.revision) { this.loading = false; this.loaded = true; } }
  }

  private applyTargetNames(targets: CultivateTarget[], avatars: WikiAvatarMeta[]): void {
    const names: Map<number, string> = new Map<number, string>();
    for (const avatar of avatars) { names.set(avatar.id, avatar.name); }
    for (const target of targets) { target.name = names.get(target.avatarId) ?? target.name; }
  }

  async refreshDisplay(): Promise<void> {
    const revision: number = this.revision;
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    if (revision !== this.revision) { return; }
    this.applyTargetNames(this.targets, avatars);
    this.targets = this.targets.slice();
    await this.loadPlan();
  }

  toggle(index: number): void {
    if (index >= 0 && index < this.targets.length) {
      // 整体重赋值触发 @State 刷新（元素属性就地变更不会驱动 UI，圆点/勾选无反馈的根因）
      this.result = undefined;
      this.targets[index].selected = !this.targets[index].selected;
      this.targets = this.targets.slice();
      this.updateSelected();
      this.persistSelection();
    }
  }

  /** 选择与目标等级持久化（JSON 落偏好文件，进入页面恢复） */
  persistSelection(): void {
    PreferencesStore.setString(`cultivation.selection.${this.loadedUid || 'offline'}`, JSON.stringify(this.targets.filter((target: CultivateTarget): boolean => target.selected)));
  }

  setTargetLevel(index: number, level: number): void {
    if (index >= 0 && index < this.targets.length) {
      this.result = undefined;
      this.targets[index].targetLevel = Math.max(this.targets[index].level, Math.min(100, level));
      this.targets = this.targets.slice();
      this.persistSelection();
    }
  }

  updateSelected(): void {
    let count: number = 0;
    for (let i = 0; i < this.targets.length; i++) {
      if (this.targets[i].selected) {
        count++;
      }
    }
    this.selectedCount = count;
  }

  /** Compatibility calculation path; saved inputs are identical to the reviewed result snapshot. */
  async compute(uid: string): Promise<void> {
    if (this.computing) { return; }
    const revision: number = this.revision;
    this.computing = true; this.result = undefined; this.prepared = [];
    try {
      const selected: CultivateTarget[] = this.targets.filter((target: CultivateTarget): boolean => target.selected);
      if (selected.length === 0) { throw new Error('请先选择角色'); }
      let drafts: CultivationDraft[] = [];
      if (uid.length > 0) {
        const characters: CharacterListItem[] = await CharacterService.getInstance().fetchList(uid);
        const chosen: CharacterListItem[] = characters.filter((item: CharacterListItem): boolean => selected.some((target: CultivateTarget): boolean => target.avatarId === item.id));
        if (chosen.length !== selected.length) { throw new Error('角色同步不完整'); }
        drafts = await CultivationService.fromCharacters(uid, chosen);
      } else {
        for (const target of selected) { drafts.push(await CultivationService.offlineAvatar(target.avatarId)); }
      }
      for (const draft of drafts) {
        const target: CultivateTarget | undefined = selected.find((item: CultivateTarget): boolean => item.avatarId === draft.itemId);
        if (target !== undefined) {
          draft.target = target.targetLevel; draft.targetPromote = CultivationDraft.promoteFor(draft.target);
          for (const skill of draft.skills) { skill.target = target.targetSkillLevel; }
        }
      }
      const prepared: CultivationPreparedEntry[] = await CultivationService.calculate(drafts);
      if (revision !== this.revision) { return; }
      this.prepared = prepared;
      this.message = '已完成计算，请在目标编辑器确认保存';
    } catch (e) { if (revision === this.revision) { this.message = (e as Error).message; } }
    finally { if (revision === this.revision) { this.computing = false; } }
  }

  setSkillTarget(level: number): void {
    for (const target of this.targets) {
      if (target.selected) {
        target.targetSkillLevel = level;
      }
    }
    this.targets = this.targets.slice();
    this.result = undefined;
  }

  setWeaponTarget(level: number): void {
    for (const target of this.targets) {
      if (target.selected) {
        target.targetWeaponLevel = level;
      }
    }
    this.targets = this.targets.slice();
    this.result = undefined;
  }

  /** 元素 → element_attr_id（米游社计算 API 约定）：火1 水2 雷4 草6 冰7 风8 岩9 */
  static elementAttrIdOf(element: string): number {
    switch (element) {
      case 'Pyro':
        return 1;
      case 'Hydro':
        return 2;
      case 'Electro':
        return 4;
      case 'Dendro':
        return 6;
      case 'Cryo':
        return 7;
      case 'Anemo':
        return 8;
      case 'Geo':
        return 9;
      default:
        return 0;
    }
  }

  // ================= 持久化计划 =================

  async loadPlan(): Promise<void> {
    if (this.planBusy) { return; }
    const request: number = ++this.projectListRequest;
    try {
      const projects: CultivateProject[] = await CultivationRepo.getProjects();
      if (request !== this.projectListRequest || this.planBusy) { return; }
      this.projects = projects;
      const preferred: number = this.currentProjectId || PreferencesStore.getNumber(KEY_CURRENT_PROJECT, 0);
      const current: number = projects.some((project: CultivateProject): boolean => project.id === preferred)
        ? preferred : (projects[0]?.id ?? 0);
      this.setActiveProject(current);
      await this.reloadEntries();
    } catch (e) { this.planMessage = `读取计划失败：${(e as Error).message}`; }
  }

  private setActiveProject(id: number): void {
    if (this.currentProjectId !== id) {
      this.currentProjectId = id;
      this.planEntries = [];
      this.inventoryRows = [];
      this.materialNames = new Map<number, string>();
      this.resinStats = undefined;
      this.planMessage = '';
    }
    if (PreferencesStore.getNumber(KEY_CURRENT_PROJECT, 0) !== id) {
      PreferencesStore.setNumber(KEY_CURRENT_PROJECT, id);
      const version: number = AppStorage.get<number>('calendarSettingsVersion') ?? 0;
      AppStorage.setOrCreate<number>('calendarSettingsVersion', version + 1);
    }
  }

  currentProjectOffset(): number {
    const current: CultivateProject | undefined = this.projects.find((project: CultivateProject): boolean => project.id === this.currentProjectId);
    return current?.serverTimeZoneOffset ?? GameCalendarRules.DEFAULT_OFFSET_HOURS;
  }

  isTodayItem(itemId: number): boolean {
    const offset: number = this.currentProjectOffset();
    const now: number = Date.now();
    const weekday: number = new Date(now + (offset - 4) * 3600000).getUTCDay();
    return ResinStatisticsService.isItemOfToday(itemId, weekday)
      || (ResinStatisticsService.dayPairOf(itemId) !== 0 && GameCalendarRules.allMaterialsOpen(now, this.bannerEvents, offset));
  }

  async reloadEntries(): Promise<void> {
    const request: number = ++this.entryRequest;
    const projectId: number = this.currentProjectId;
    this.planLoading = projectId > 0;
    if (projectId <= 0) { return; }
    try {
      const entries: CultivateEntry[] = await CultivationRepo.getEntries(projectId);
      const counts: Map<number, number> = await InventoryRepo.getInventory(projectId);
      const dist: ResinDropDistribution = ResinStatisticsService.distributionOf(this.resinWorldLevel);
      const stats: ResinStatisticsResult = await ResinStatisticsService.compute(entries, dist, counts);
      const materials: Map<number, MetaMaterial> = await WikiMetaService.getMaterials();
      const catalog: Map<number, MetaMaterial> = await BackpackService.cultivationMaterialMetadata()
        .catch((): Map<number, MetaMaterial> => new Map<number, MetaMaterial>());
      const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
      const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
      const events: GachaEventMeta[] = await WikiMetaService.getGachaEvents().catch((): GachaEventMeta[] => []);
      if (request !== this.entryRequest || projectId !== this.currentProjectId) { return; }

      this.bannerEvents = events;
      this.avatarMetadata = new Map<number, WikiAvatarMeta>();
      this.weaponMetadata = new Map<number, WikiWeaponMeta>();
      for (const avatar of avatars) { this.avatarMetadata.set(avatar.id, avatar); }
      for (const weapon of weapons) { this.weaponMetadata.set(weapon.id, weapon); }
      const rows: Map<number, InventoryMaterialView> = new Map<number, InventoryMaterialView>();
      const ids: Set<number> = new Set<number>(InventoryMaterialReference.itemIds());
      for (const id of counts.keys()) { ids.add(id); }
      for (const id of ids) {
        const row: InventoryMaterialView = new InventoryMaterialView();
        const meta: MetaMaterial | undefined = materials.get(id) ?? catalog.get(id);
        row.itemId = id;
        row.name = meta?.n ?? `材料 ${id}`;
        row.icon = meta?.i ?? '';
        rows.set(id, row);
      }
      for (const entry of entries) {
        for (const item of entry.items) {
          let row: InventoryMaterialView | undefined = rows.get(item.itemId);
          if (row === undefined) {
            row = new InventoryMaterialView();
            row.itemId = item.itemId; row.name = item.name; row.icon = item.icon;
            rows.set(item.itemId, row);
          }
          row.planned += item.count;
          if (!item.finished) { row.required += item.count; }
        }
      }
      for (const row of rows.values()) {
        row.known = counts.has(row.itemId);
        row.current = counts.get(row.itemId) ?? 0;
        row.shortfall = stats.materialShortfalls.get(row.itemId) ?? 0;
        row.availableToday = this.isTodayItem(row.itemId);
      }
      const names: Map<number, string> = new Map<number, string>();
      for (const row of rows.values()) { names.set(row.itemId, row.name); }
      this.materialNames = names;
      this.planEntries = entries;
      this.inventoryRows = Array.from(rows.values());
      this.resinStats = stats;
      this.materialLabelVersion = AppStorage.get<number>('helpLocaleVersion') ?? 0;
    } finally { if (request === this.entryRequest) { this.planLoading = false; } }
  }

  entryName(entry: CultivateEntry): string {
    return this.avatarMetadata.get(entry.avatarId)?.name ?? this.weaponMetadata.get(entry.avatarId)?.name ?? entry.name;
  }

  materialName(item: CultivateEntryItem): string { return this.materialNames.get(item.itemId) ?? item.name; }

  private static filterValues(tokens: CultivationFilterToken[], kind: CultivationFilterKind): string[] {
    const options: string[] = CultivationFilterToken.options(kind);
    return tokens.filter((token: CultivationFilterToken): boolean => token.kind === kind &&
      (kind === CultivationFilterKind.Name ? token.value.length > 0 : options.includes(token.value)))
      .map((token: CultivationFilterToken): string => token.value);
  }

  filteredEntries(tokens: CultivationFilterToken[]): CultivateEntry[] {
    if (tokens.length === 0) { return this.planEntries; }
    const names: string[] = CultivationViewModel.filterValues(tokens, CultivationFilterKind.Name)
      .map((name: string): string => name.toLocaleLowerCase());
    const targets: string[] = CultivationViewModel.filterValues(tokens, CultivationFilterKind.Target);
    const qualities: string[] = CultivationViewModel.filterValues(tokens, CultivationFilterKind.Quality);
    const weaponTypes: string[] = CultivationViewModel.filterValues(tokens, CultivationFilterKind.Weapon);
    const elements: string[] = CultivationViewModel.filterValues(tokens, CultivationFilterKind.Element);
    const hasSharedGroup: boolean = names.length > 0 || targets.length > 0 || qualities.length > 0 || weaponTypes.length > 0;

    return this.planEntries.filter((entry: CultivateEntry): boolean => {
      const isAvatar: boolean = entry.avatarId >= 10000000;
      // Windows ignores the element group for a weapon, but an entry must match at least one applicable group.
      const checkElement: boolean = isAvatar && elements.length > 0;
      if (!hasSharedGroup && !checkElement) { return false; }
      const avatar: WikiAvatarMeta | undefined = this.avatarMetadata.get(entry.avatarId);
      const weapon: WikiWeaponMeta | undefined = this.weaponMetadata.get(entry.avatarId);
      if (targets.length > 0 && !targets.includes(isAvatar ? '1' : '2')) { return false; }
      if (qualities.length > 0 && !qualities.includes(String(avatar?.quality ?? weapon?.rankLevel ?? 0))) { return false; }
      if (weaponTypes.length > 0 && !weaponTypes.includes(String(avatar?.weapon ?? weapon?.weaponType ?? 0))) { return false; }
      if (checkElement && !elements.includes(avatar?.vision ?? '')) { return false; }
      if (names.length === 0) { return true; }
      const savedName: string = entry.name.toLocaleLowerCase();
      const displayName: string = this.entryName(entry).toLocaleLowerCase();
      const id: string = String(entry.avatarId);
      return names.some((name: string): boolean => savedName.includes(name) || displayName.includes(name) || id.includes(name));
    });
  }

  private async writePlan(projectId: number, action: () => Promise<string>): Promise<string> {
    if (projectId <= 0 || projectId !== this.currentProjectId) { return '养成项目已切换，请重新操作'; }
    if (this.planBusy || this.planLoading) { return '养成项目正在更新，请稍候'; }
    this.planBusy = true;
    try {
      this.planMessage = await action();
      try { await this.reloadEntries(); }
      catch (e) { this.planMessage += `，列表刷新失败：${(e as Error).message}`; }
    } catch (e) { this.planMessage = (e as Error).message; }
    finally { this.planBusy = false; }
    return this.planMessage;
  }

  async setInventoryCount(projectId: number, itemId: number, count: number): Promise<string> {
    return this.writePlan(projectId, async (): Promise<string> => {
      await InventoryRepo.setCount(projectId, itemId, count);
      return '已更新库存';
    });
  }

  getBackpackArchives(): Promise<BackpackArchive[]> { return BackpackService.getArchives(); }

  async clearInventory(projectId: number): Promise<string> {
    return this.writePlan(projectId, async (): Promise<string> => {
      await InventoryService.clear(projectId);
      return '已清空项目库存';
    });
  }

  async syncBackpackInventory(archiveId: number, projectId: number): Promise<string> {
    return this.writePlan(projectId, async (): Promise<string> => {
      const count: number = await BackpackService.syncMaterials(archiveId, projectId, true);
      return `已从背包同步 ${count} 种养成材料`;
    });
  }

  async importInventoryText(projectId: number, text: string): Promise<string> {
    return this.writePlan(projectId, async (): Promise<string> => {
      const count: number = await InventoryService.importInventory(projectId, text);
      return `已合并导入 ${count} 种材料`;
    });
  }

  private requireAccount(revision: number, accountId: number): void {
    if (revision !== this.revision || accountId !== (UserService.getInstance().getCurrentUser()?.id ?? 0)) {
      throw new Error('账号已切换，请重新同步');
    }
  }

  async syncInventory(): Promise<string> {
    const uid: string = this.loadedUid;
    const projectId: number = this.currentProjectId;
    const revision: number = this.revision;
    const accountId: number = UserService.getInstance().getCurrentUser()?.id ?? 0;
    return this.writePlan(projectId, async (): Promise<string> => {
      if (uid.length === 0) { throw new Error('请先登录并选择游戏 UID'); }
      const calculator: CalculateService = CalculateService.getInstance();
      const catalog: CalculateInventoryCatalog = await calculator.fetchInventoryCatalog();
      const deltas: CalAvatarDelta[] = await CultivationService.inventoryCalculatorInputs(catalog);
      this.requireAccount(revision, accountId);
      const result: CalBatchResult = await calculator.batchCompute(deltas, uid);
      this.requireAccount(revision, accountId);
      const count: number = await InventoryService.syncFromCalculator(projectId, result);
      return `已同步计算器返回的 ${count} 种材料库存`;
    });
  }

  async syncProjectProgress(): Promise<string> {
    const projectId: number = this.currentProjectId;
    const revision: number = this.revision;
    const accountId: number = UserService.getInstance().getCurrentUser()?.id ?? 0;
    return this.writePlan(projectId, async (): Promise<string> => {
      const update: CultivationProgressUpdate = await CultivationService.prepareProjectProgress(this.loadedUid, this.planEntries);
      this.requireAccount(revision, accountId);
      if (update.entries.length === 0) { return `没有可更新的角色进度，跳过 ${update.skipped} 项`; }
      const report: CultivationSaveReport = await CultivationService.save(projectId, update.entries, true);
      return `已同步 ${report.updated} 个角色目标的当前进度，跳过 ${update.skipped} 项`;
    });
  }

  async setResinWorldLevel(worldLevel: number): Promise<void> {
    if (worldLevel === this.resinWorldLevel || this.planBusy) { return; }
    this.resinWorldLevel = worldLevel;
    try {
      PreferencesStore.setNumber(KEY_RESIN_WORLD_LEVEL, worldLevel);
      await this.reloadEntries();
    } catch (e) { this.planMessage = `刷新树脂统计失败：${(e as Error).message}`; }
  }

  async selectProject(id: number): Promise<void> {
    if (this.planBusy || id === this.currentProjectId) { return; }
    try {
      this.setActiveProject(id);
      await this.reloadEntries();
    } catch (e) { this.planMessage = `读取计划失败：${(e as Error).message}`; }
  }

  async createProject(name: string, serverTimeZoneOffset: number): Promise<boolean> {
    if (this.planBusy || this.planLoading) { return false; }
    this.planBusy = true;
    this.projectListRequest++;
    try {
      const project: CultivateProject = await CultivationRepo.createProject(name, serverTimeZoneOffset);
      this.projects = this.projects.concat([project]);
      this.setActiveProject(project.id);
      this.planMessage = `已创建「${project.name}」`;
      try { await this.reloadEntries(); } catch (e) { this.planMessage += `，列表刷新失败：${(e as Error).message}`; }
      return true;
    } catch (e) { this.planMessage = (e as Error).message; return false; }
    finally { this.planBusy = false; }
  }

  async deleteCurrentProject(projectId: number): Promise<string> {
    return this.writePlan(projectId, async (): Promise<string> => {
      this.projectListRequest++;
      await CultivationRepo.deleteProject(projectId);
      this.projects = this.projects.filter((project: CultivateProject): boolean => project.id !== projectId);
      this.setActiveProject(this.projects[0]?.id ?? 0);
      return '已删除养成项目';
    });
  }

  /** The legacy calculation path still commits the exact reviewed inputs. */
  async saveResultToPlan(): Promise<boolean> {
    if (this.planBusy || this.prepared.length === 0) { this.message = '请先计算并确认目标'; return false; }
    this.planBusy = true;
    try {
      const report: CultivationSaveReport = await CultivationService.save(this.currentProjectId, this.prepared, false);
      this.prepared = []; this.result = undefined;
      await this.reloadEntries();
      this.message = `新增 ${report.added} · 更新 ${report.updated} · 跳过 ${report.skipped}`;
      return true;
    } catch (e) { this.message = `保存失败：${(e as Error).message}`; return false; }
    finally { this.planBusy = false; }
  }

  async removeEntry(entry: CultivateEntry): Promise<string> {
    return this.writePlan(entry.projectId, async (): Promise<string> => {
      await CultivationRepo.removeEntry(entry.id);
      return '已移除培养目标';
    });
  }

  async togglePlanItem(entry: CultivateEntry, itemId: number): Promise<string> {
    return this.writePlan(entry.projectId, async (): Promise<string> => {
      const item: CultivateEntryItem | undefined = entry.items.find((value: CultivateEntryItem): boolean => value.id === itemId);
      if (item === undefined) { throw new Error('材料条目已变更'); }
      await CultivationRepo.toggleItem(itemId, !item.finished);
      return item.finished ? '已取消备齐标记' : '已标记为备齐';
    });
  }
}
