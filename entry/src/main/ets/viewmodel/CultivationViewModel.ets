/**
 * CultivationViewModel.ets
 * 养成计划页状态容器：候选角色清单（来自角色接口）、目标等级输入、批量计算、结果展示。
 */
import { CharacterListItem } from '../model/CharacterData';
import { CharacterService } from '../service/CharacterService';
import { CalculateService, CalAvatarDelta, CalSkillDelta, CalWeaponDelta } from '../service/CalculateService';
import { CalBatchResult, CalItem } from '../model/Calculate';

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
    }
  }

  setTargetLevel(index: number, level: number): void {
    if (index >= 0 && index < this.targets.length) {
      this.targets[index].targetLevel = level;
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
}
