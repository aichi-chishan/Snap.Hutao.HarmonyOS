import { CultivationDraft } from '../model/CultivationDraft';
import { CultivationService } from '../service/CultivationService';
import { CultivationPreparedEntry, CultivationSaveReport } from '../data/repo/CultivationRepo';
import { UserService } from '../service/UserService';
/**
 * CultivationViewModel.ets
 * 养成计划页状态容器：候选角色清单（来自角色接口）、目标等级输入、批量计算、结果展示；
 * 持久化计划（项目/条目/材料勾选，对齐 Windows CultivateProject/Entry/Item）。
 */
import { CharacterListItem } from '../model/CharacterData';
import { OfflineCultivationService } from '../service/OfflineCultivationService';
import { WikiMetaService, WikiAvatarMeta } from '../service/WikiMetaService';
import { CharacterService } from '../service/CharacterService';
import { CalculateService, CalAvatarDelta, CalSkillDelta, CalWeaponDelta } from '../service/CalculateService';
import { CalBatchResult, CalItem } from '../model/Calculate';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { CultivationRepo, CultivateProject, CultivateEntry } from '../data/repo/CultivationRepo';
import { ResinStatisticsService, ResinStatisticsResult, ResinDropDistribution } from '../service/ResinStatisticsService';
import { InventoryRepo } from '../data/repo/InventoryRepo';
import { InventoryService } from '../service/InventoryService';
import { Logger } from '../common/Logger';

const TAG: string = 'CultivationViewModel';
/** 树脂统计世界等级偏好键（对齐 Windows SettingKeys.ResinStatisticsSelectedDropDistribution） */
const KEY_RESIN_WORLD_LEVEL: string = 'cultivation_resin_world_level';

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
  required: number = 0;
  current: number = 0;
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
  inventoryRows: InventoryMaterialView[] = [];
  private computedDeltas: CalAvatarDelta[] = [];
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

  /** 加载计划：项目列表（无项目时自动建默认项目）+ 当前项目条目 */
  async loadPlan(): Promise<void> {
    try {
      let projects: CultivateProject[] = await CultivationRepo.getProjects();
      if (projects.length === 0) {
        await CultivationRepo.createProject('默认计划');
        projects = await CultivationRepo.getProjects();
      }
      this.projects = projects;
      let current: number = this.currentProjectId || PreferencesStore.getNumber('cultivation.current_project_id', 0);
      if (current <= 0 || !CultivationViewModel.containsProject(projects, current)) {
        current = projects[0].id;
      }
      this.currentProjectId = current;
      PreferencesStore.setNumber('cultivation.current_project_id', current);
      await this.reloadEntries();
    } catch (e) {
      this.message = `读取计划失败：${(e as Error).message}`;
      Logger.warn(TAG, this.message);
    }
  }

  private static containsProject(projects: CultivateProject[], id: number): boolean {
    for (const p of projects) {
      if (p.id === id) {
        return true;
      }
    }
    return false;
  }

  /** 重读当前项目条目（并联动刷新树脂统计） */
  async reloadEntries(): Promise<void> {
    if (this.currentProjectId <= 0) {
      this.planEntries = [];
      this.resinStats = undefined;
      return;
    }
    const projectId: number = this.currentProjectId;
    const entries: CultivateEntry[] = await CultivationRepo.getEntries(projectId);
    if (projectId !== this.currentProjectId) { return; }
    this.planEntries = entries;
    await this.reloadInventory();
    await this.refreshResinStats();
  }

  /** 树脂统计：聚合当前项目未完成材料 → 折算树脂/脆弱树脂/天数（对齐 Windows ResinStatistics） */
  async refreshResinStats(): Promise<void> {
    try {
      const dist: ResinDropDistribution = ResinStatisticsService.distributionOf(this.resinWorldLevel);
      const inventory: Map<number, number> = await InventoryRepo.getInventory(this.currentProjectId);
      this.resinStats = await ResinStatisticsService.compute(this.planEntries, dist, inventory);
    } catch (e) {
      Logger.warn(TAG, `resin stats fail ${(e as Error).message}`);
      this.resinStats = undefined;
    }
  }

  async reloadInventory(): Promise<void> {
    const counts: Map<number, number> = await InventoryRepo.getInventory(this.currentProjectId);
    const rows: Map<number, InventoryMaterialView> = new Map<number, InventoryMaterialView>();
    const materials = await WikiMetaService.getMaterials();
    for (const entry of this.planEntries) {
      for (const item of entry.items) {
        let row: InventoryMaterialView | undefined = rows.get(item.itemId);
        if (row === undefined) {
          row = new InventoryMaterialView();
          row.itemId = item.itemId;
          row.name = item.name;
          rows.set(item.itemId, row);
        }
        if (!item.finished) {
          row.required += item.count;
        }
      }
    }
    for (const id of counts.keys()) {
      let row: InventoryMaterialView | undefined = rows.get(id);
      if (row === undefined) {
        row = new InventoryMaterialView();
        row.itemId = id;
        row.name = materials.get(id)?.n ?? `材料 ${id}`;
        rows.set(id, row);
      }
    }
    for (const row of rows.values()) {
      row.current = counts.get(row.itemId) ?? 0;
    }
    this.inventoryRows = Array.from(rows.values());
  }

  async setInventoryCount(itemId: number, count: number): Promise<void> {
    try {
      await InventoryRepo.setCount(this.currentProjectId, itemId, count);
      await this.reloadInventory();
      await this.refreshResinStats();
      this.message = '已更新库存';
    } catch (e) {
      this.message = (e as Error).message;
    }
  }

  async importInventoryText(text: string): Promise<void> {
    try {
      await InventoryService.importInventory(this.currentProjectId, text);
      await this.reloadInventory();
      await this.refreshResinStats();
      this.message = '已合并导入库存';
    } catch (e) {
      this.message = (e as Error).message;
    }
  }

  async syncInventory(): Promise<void> {
    if (this.planBusy) { return; }
    const projectId: number = this.currentProjectId;
    const revision: number = this.revision;
    const accountId: number = UserService.getInstance().getCurrentUser()?.id ?? 0;
    const uid: string = this.loadedUid;
    this.planBusy = true;
    try {
      const drafts: CultivationDraft[] = this.planEntries.filter((entry: CultivateEntry): boolean => entry.inputJson.length > 0)
        .map((entry: CultivateEntry): CultivationDraft => CultivationDraft.decode(entry.inputJson));
      const deltas: CalAvatarDelta[] = CultivationService.calculatorInputs(drafts, uid);
      const result: CalBatchResult = await CalculateService.getInstance().batchCompute(deltas);
      if (revision !== this.revision || projectId !== this.currentProjectId
        || accountId !== (UserService.getInstance().getCurrentUser()?.id ?? 0)) { return; }
      const count: number = await InventoryService.syncFromCalculator(projectId, result);
      if (projectId !== this.currentProjectId) { return; }
      await this.reloadInventory(); await this.refreshResinStats();
      this.message = `已同步 ${count} 种计划材料库存（并非完整背包）`;
    } catch (e) { if (revision === this.revision) { this.message = (e as Error).message; } }
    finally { this.planBusy = false; }
  }

  /** 切换树脂统计世界等级（持久化 + 重算，对齐 Windows SelectedDropDistribution） */
  async setResinWorldLevel(worldLevel: number): Promise<void> {
    if (worldLevel === this.resinWorldLevel) {
      return;
    }
    this.resinWorldLevel = worldLevel;
    try {
      PreferencesStore.setNumber(KEY_RESIN_WORLD_LEVEL, worldLevel);
    } catch (e) {
      Logger.warn(TAG, `save resin world level fail ${(e as Error).message}`);
    }
    await this.refreshResinStats();
  }

  selectProject(id: number): void {
    if (this.currentProjectId === id) {
      return;
    }
    this.currentProjectId = id;
    PreferencesStore.setNumber('cultivation.current_project_id', id);
    this.reloadEntries().catch(() => {
    });
  }

  async createProject(name: string): Promise<void> {
    if (this.planBusy || name.trim().length === 0) {
      return;
    }
    this.planBusy = true;
    try {
      const p: CultivateProject = await CultivationRepo.createProject(name.trim());
      this.projects = await CultivationRepo.getProjects();
      this.currentProjectId = p.id;
      PreferencesStore.setNumber('cultivation.current_project_id', p.id);
      await this.reloadEntries();
    } finally {
      this.planBusy = false;
    }
  }

  /** 删除当前项目（项目数 >1 时允许；删后切到第一个项目） */
  async deleteCurrentProject(): Promise<void> {
    if (this.planBusy || this.projects.length <= 1 || this.currentProjectId <= 0) {
      return;
    }
    this.planBusy = true;
    try {
      await CultivationRepo.deleteProject(this.currentProjectId);
      this.projects = await CultivationRepo.getProjects();
      this.currentProjectId = this.projects.length > 0 ? this.projects[0].id : 0;
      PreferencesStore.setNumber('cultivation.current_project_id', this.currentProjectId);
      await this.reloadEntries();
    } finally {
      this.planBusy = false;
    }
  }

  /**
   * 把本次计算结果保存到当前项目（每个已选角色一条目；items[i] 与 deltas 顺序一一对应）。
   * 结果不存在/未选角色时置 message 提示。
   */
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

  /** 删除单个培养条目 */
  async removeEntry(entry: CultivateEntry): Promise<void> {
    if (this.planBusy) {
      return;
    }
    this.planBusy = true;
    try {
      await CultivationRepo.removeEntry(entry.id);
      await this.reloadEntries();
    } finally {
      this.planBusy = false;
    }
  }

  /** 切换材料勾选状态 */
  async togglePlanItem(entry: CultivateEntry, itemId: number): Promise<void> {
    try {
      for (const it of entry.items) {
        if (it.id === itemId) {
          await CultivationRepo.toggleItem(itemId, !it.finished);
          break;
        }
      }
      await this.reloadEntries();
    } catch (e) {
      Logger.warn(TAG, `toggleItem fail ${(e as Error).message}`);
    }
  }
}
