/**
 * CultivationViewModel.ets
 * 养成计划页状态容器：候选角色清单（来自角色接口）、目标等级输入、批量计算、结果展示；
 * 持久化计划（项目/条目/材料勾选，对齐 Windows CultivateProject/Entry/Item）。
 */
import { CharacterListItem } from '../model/CharacterData';
import { CharacterService } from '../service/CharacterService';
import { CalculateService, CalAvatarDelta, CalSkillDelta, CalWeaponDelta } from '../service/CalculateService';
import { CalBatchResult, CalItem } from '../model/Calculate';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { CultivationRepo, CultivateProject, CultivateEntry } from '../data/repo/CultivationRepo';
import { ResinStatisticsService, ResinStatisticsResult, ResinDropDistribution } from '../service/ResinStatisticsService';
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
    if (uid.length === 0) {
      this.message = '请先登录并绑定 UID';
      this.loaded = true;
      return;
    }
    this.loading = true;
    try {
      const details: CharacterListItem[] = await CharacterService.getInstance().fetchList(uid);
      const list: CultivateTarget[] = [];
      for (let i = 0; i < details.length; i++) {
        const d: CharacterListItem = details[i];
        const t: CultivateTarget = new CultivateTarget();
        t.avatarId = d.id;
        t.name = d.name;
        t.element = d.element;
        t.rarity = d.rarity;
        t.level = d.level;
        t.promoteLevel = 0;
        t.icon = d.icon;
        t.weaponId = d.weapon.id;
        t.weaponLevel = d.weapon.level;
        t.weaponPromoteLevel = 0;
        list.push(t);
      }
      // 恢复本地持久化的选择与目标等级（对齐 Windows 养成目标本地保存）
      const saved: string = PreferencesStore.getString('cultivation_selected', '');
      const savedLevels: string = PreferencesStore.getString('cultivation_levels', '');
      if (saved.length > 0) {
        const sel: Set<string> = new Set(JSON.parse(saved) as Array<string>);
        let lvMap: Map<string, number> = new Map();
        if (savedLevels.length > 0) {
          const lvObj = JSON.parse(savedLevels) as Record<string, number>;
          for (const k of Object.keys(lvObj)) {
            lvMap.set(k, Number(lvObj[k]));
          }
        }
        for (let i = 0; i < list.length; i++) {
          const key: string = String(list[i].avatarId);
          if (sel.has(key)) {
            list[i].selected = true;
            if (lvMap.has(key)) {
              list[i].targetLevel = lvMap.get(key) as number;
            }
          }
        }
      }
      this.targets = list;
      this.updateSelected();
    } catch (e) {
      this.message = (e as Error).message;
    } finally {
      this.loading = false;
      this.loaded = true;
    }
  }

  toggle(index: number): void {
    if (index >= 0 && index < this.targets.length) {
      // 整体重赋值触发 @State 刷新（元素属性就地变更不会驱动 UI，圆点/勾选无反馈的根因）
      this.targets[index].selected = !this.targets[index].selected;
      this.targets = this.targets.slice();
      this.updateSelected();
      this.persistSelection();
    }
  }

  /** 选择与目标等级持久化（JSON 落偏好文件，进入页面恢复） */
  persistSelection(): void {
    const sel: string[] = [];
    const lvObj: Record<string, number> = {};
    for (const t of this.targets) {
      if (t.selected) {
        sel.push(String(t.avatarId));
        lvObj[String(t.avatarId)] = t.targetLevel;
      }
    }
    PreferencesStore.setString('cultivation_selected', JSON.stringify(sel));
    PreferencesStore.setString('cultivation_levels', JSON.stringify(lvObj));
  }

  setTargetLevel(index: number, level: number): void {
    if (index >= 0 && index < this.targets.length) {
      this.targets[index].targetLevel = level;
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

  /** 批量计算已选角色 */
  async compute(uid: string): Promise<void> {
    const deltas: CalAvatarDelta[] = [];
    for (let i = 0; i < this.targets.length; i++) {
      const t: CultivateTarget = this.targets[i];
      if (!t.selected) {
        continue;
      }
      const d: CalAvatarDelta = new CalAvatarDelta();
      d.avatarId = t.avatarId;
      d.levelCurrent = t.level;
      d.levelTarget = Math.max(t.level, t.targetLevel);
      d.elementAttrId = CultivationViewModel.elementAttrIdOf(t.element);
      d.avatarPromoteLevel = t.promoteLevel;
      // 技能列表：无元数据时默认角色(含1个技能占位) —— batch_compute 允许空 skill_list
      d.skills = [];
      if (t.weaponId > 0) {
        const w: CalWeaponDelta = new CalWeaponDelta();
        w.id = t.weaponId;
        w.levelCurrent = t.weaponLevel;
        w.levelTarget = Math.max(t.weaponLevel, t.targetLevel);
        w.weaponPromoteLevel = t.weaponPromoteLevel;
        d.weapon = w;
      }
      deltas.push(d);
    }
    if (deltas.length === 0) {
      this.message = '请先勾选要培养的角色';
      return;
    }
    this.computing = true;
    try {
      this.result = await CalculateService.getInstance().batchCompute(deltas);
      this.message = this.result.hasUserInfo ? '' : '（当前账号未同步背包，材料为理论消耗）';
    } catch (e) {
      this.message = (e as Error).message;
    } finally {
      this.computing = false;
    }
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
      let current: number = this.currentProjectId;
      if (current <= 0 || !CultivationViewModel.containsProject(projects, current)) {
        current = projects[0].id;
      }
      this.currentProjectId = current;
      await this.reloadEntries();
    } catch (e) {
      Logger.warn(TAG, `loadPlan fail ${(e as Error).message}`);
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
    this.planEntries = await CultivationRepo.getEntries(this.currentProjectId);
    await this.refreshResinStats();
  }

  /** 树脂统计：聚合当前项目未完成材料 → 折算树脂/脆弱树脂/天数（对齐 Windows ResinStatistics） */
  async refreshResinStats(): Promise<void> {
    try {
      const dist: ResinDropDistribution = ResinStatisticsService.distributionOf(this.resinWorldLevel);
      this.resinStats = await ResinStatisticsService.compute(this.planEntries, dist);
    } catch (e) {
      Logger.warn(TAG, `resin stats fail ${(e as Error).message}`);
      this.resinStats = undefined;
    }
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
    if (this.planBusy) {
      return false;
    }
    if (this.result === undefined) {
      this.message = '请先计算材料';
      return false;
    }
    if (this.currentProjectId <= 0) {
      this.message = '无可用计划项目';
      return false;
    }
    this.planBusy = true;
    try {
      const selected: CultivateTarget[] = [];
      for (const t of this.targets) {
        if (t.selected) {
          selected.push(t);
        }
      }
      if (selected.length === 0) {
        this.message = '请先勾选要培养的角色';
        return false;
      }
      let saved: number = 0;
      for (let i = 0; i < selected.length && i < this.result.items.length; i++) {
        const t: CultivateTarget = selected[i];
        const c = this.result.items[i];
        const items: CalItem[] = [];
        for (const it of c.avatarConsume) {
          items.push(it);
        }
        for (const it of c.avatarSkillConsume) {
          items.push(it);
        }
        for (const it of c.weaponConsume) {
          items.push(it);
        }
        await CultivationRepo.addEntry(this.currentProjectId, t.avatarId, t.name,
          t.icon, t.level, Math.max(t.level, t.targetLevel), items);
        saved++;
      }
      await this.reloadEntries();
      this.message = `已保存 ${saved} 条培养目标到计划`;
      return true;
    } catch (e) {
      this.message = `保存失败：${(e as Error).message}`;
      return false;
    } finally {
      this.planBusy = false;
    }
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
