/**
 * BaseValueService.ets
 * 基础数值曲线计算（对齐 Windows BaseValueInfoConverter 公式）：
 *   值(level, promoted) = InitValue × GrowCurveMap[level][growCurveType] + PromoteMap[promoteLevel].AddProperties[fightProperty]
 * 数据：rawfile/metadata/{WeaponCurve,WeaponPromote,AvatarCurve,AvatarPromote,MonsterCurve}.json
 */
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const TAG: string = 'BaseValueService';

type Curves = Map<number, Map<number, number>>; // level -> (curveType -> 系数)
type Promotes = Map<number, Map<number, Map<number, number>>>; // promoteId -> (promoteLevel -> (fightProp -> 值))

export class BaseValueService {
  private static weaponCurves: Curves | undefined = undefined;
  private static weaponPromotes: Promotes | undefined = undefined;
  private static avatarCurves: Curves | undefined = undefined;
  private static avatarPromotes: Promotes | undefined = undefined;
  private static monsterCurves: Curves | undefined = undefined;

  /** 角色品质 → 最大等级（4/5 星 90；对齐 Windows GetMaxLevelByQuality） */
  static avatarMaxLevel(quality: number): number {
    return quality >= 4 ? 90 : 70;
  }

  /** 战斗属性中文名（1 生命/4 攻击/7 防御 + 突破属性） */
  static fightPropName(t: number): string {
    switch (t) {
      case 1: return '生命值';
      case 4: return '攻击力';
      case 7: return '防御力';
      case 20: return '暴击率';
      case 22: return '暴击伤害';
      case 26: return '元素充能效率';
      case 28: return '治疗加成';
      case 30: return '物理伤害加成';
      case 40: return '风元素伤害加成';
      case 41: return '岩元素伤害加成';
      case 42: return '雷元素伤害加成';
      case 43: return '草元素伤害加成';
      case 44: return '水元素伤害加成';
      case 45: return '火元素伤害加成';
      case 46: return '冰元素伤害加成';
      default: return '';
    }
  }

  /** 百分比型战斗属性集合（值按 ×100 显示） */
  private static isPercentProp(t: number): boolean {
    return t === 20 || t === 22 || t === 26 || t === 28 || t === 30
      || (t >= 40 && t <= 46);
  }

  /** 格式化属性值（百分比型 → "+4.8%"；平面型 → 四舍五入整数） */
  static fightPropText(t: number, v: number): string {
    if (BaseValueService.isPercentProp(t)) {
      return `+${Math.round(v * 1000) / 10}%`;
    }
    return `${Math.round(v)}`;
  }

  /**
   * 角色某等级基础属性（对齐 Windows BaseValueInfoConverter）：
   *   值 = 基础值 × AvatarCurve[v][level] + AvatarPromote[promoteId][pl].AddProperties[t]
   * 同时挑出突破加成属性（AddProperties 中非生命/攻击/防御的最大值项）。
   */
  static async avatarBaseValues(info: AvatarGrowInfo, level: number, promoted: boolean): Promise<AvatarBaseValues> {
    const out: AvatarBaseValues = new AvatarBaseValues();
    out.maxLevel = BaseValueService.avatarMaxLevel(5);
    const curves: Curves = await BaseValueService.getAvatarCurves();
    const promotes: Promotes = await BaseValueService.getAvatarPromotes();
    const pl: number = BaseValueService.promoteLevel(level, out.maxLevel, promoted);
    const curveLevel: Map<number, number> | undefined = curves.get(level);
    const pMap: Map<number, Map<number, number>> | undefined = promotes.get(info.promoteId);
    const pLevelMap: Map<number, number> | undefined = pMap !== undefined ? pMap.get(pl) : undefined;

    for (const g of info.growCurves) {
      const co: number = (curveLevel !== undefined ? curveLevel.get(g.v) : undefined) ?? 0;
      const add: number = (pLevelMap !== undefined ? pLevelMap.get(g.t) : undefined) ?? 0;
      if (g.t === 1) {
        out.hp = Math.round(info.hpBase * co + add);
      } else if (g.t === 4) {
        out.atk = Math.round(info.attackBase * co + add);
      } else if (g.t === 7) {
        out.def = Math.round(info.defenseBase * co + add);
      }
    }
    // 突破加成属性：非 1/4/7 的最大值项（暴击/暴伤/充能/治疗/元素伤等）
    if (pLevelMap !== undefined) {
      pLevelMap.forEach((v: number, t: number) => {
        if (t === 1 || t === 4 || t === 7) {
          return;
        }
        if (v > out.bonusValue) {
          out.bonusType = t;
          out.bonusValue = v;
        }
      });
    }
    return out;
  }

  /**
   * 怪物某等级基础属性（无突破）：值 = 基础值 × MonsterCurve[level][v]
   */
  static async monsterBaseValues(growCurves: Curve3[], hpBase: number, attackBase: number, defenseBase: number,
    level: number): Promise<MonsterBaseValues> {
    const out: MonsterBaseValues = new MonsterBaseValues();
    const curves: Curves = await BaseValueService.getMonsterCurves();
    const curveLevel: Map<number, number> | undefined = curves.get(level);
    for (const g of growCurves) {
      const co: number = (curveLevel !== undefined ? curveLevel.get(g.v) : undefined) ?? 0;
      if (g.t === 1) {
        out.hp = Math.round(hpBase * co);
      } else if (g.t === 4) {
        out.atk = Math.round(attackBase * co);
      } else if (g.t === 7) {
        out.def = Math.round(defenseBase * co);
      }
    }
    return out;
  }

  private static async getMonsterCurves(): Promise<Curves> {
    if (BaseValueService.monsterCurves !== undefined) {
      return BaseValueService.monsterCurves;
    }
    const raw = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(
      await AppContextProvider.getResourceManager().getRawFileContent('metadata/MonsterCurve.json'))) as Object[];
    const map: Curves = new Map();
    for (const levelRow of raw) {
      const ro = levelRow as Record<string, Object>;
      const level = Number(ro['Level'] ?? 0);
      const inner: Map<number, number> = new Map();
      const curvesArr = (ro['Curves'] as Object[]) ?? [];
      for (const c of curvesArr) {
        const co = c as Record<string, Object>;
        inner.set(Number(co['Type'] ?? 0), Number(co['Value'] ?? 0));
      }
      map.set(level, inner);
    }
    BaseValueService.monsterCurves = map;
    Logger.info(TAG, `monsterCurves: ${map.size} levels`);
    return map;
  }

  private static async getAvatarCurves(): Promise<Curves> {
    if (BaseValueService.avatarCurves !== undefined) {
      return BaseValueService.avatarCurves;
    }
    const raw = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(
      await AppContextProvider.getResourceManager().getRawFileContent('metadata/AvatarCurve.json'))) as Object[];
    const map: Curves = new Map();
    for (const levelRow of raw) {
      const ro = levelRow as Record<string, Object>;
      const level = Number(ro['Level'] ?? 0);
      const inner: Map<number, number> = new Map();
      const curvesArr = (ro['Curves'] as Object[]) ?? [];
      for (const c of curvesArr) {
        const co = c as Record<string, Object>;
        inner.set(Number(co['Type'] ?? 0), Number(co['Value'] ?? 0));
      }
      map.set(level, inner);
    }
    BaseValueService.avatarCurves = map;
    Logger.info(TAG, `avatarCurves: ${map.size} levels`);
    return map;
  }

  private static async getAvatarPromotes(): Promise<Promotes> {
    if (BaseValueService.avatarPromotes !== undefined) {
      return BaseValueService.avatarPromotes;
    }
    const raw = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(
      await AppContextProvider.getResourceManager().getRawFileContent('metadata/AvatarPromote.json'))) as Object[];
    const map: Promotes = new Map();
    for (const row of raw) {
      const ro = row as Record<string, Object>;
      const promoteId = Number(ro['Id'] ?? 0);
      const level = Number(ro['Level'] ?? 0);
      let idMap: Map<number, Map<number, number>> | undefined = map.get(promoteId);
      if (idMap === undefined) {
        idMap = new Map();
        map.set(promoteId, idMap);
      }
      const props: Map<number, number> = new Map();
      const adds = (ro['AddProperties'] as Object[]) ?? [];
      for (const add of adds) {
        const ao = add as Record<string, Object>;
        props.set(Number(ao['Type'] ?? 0), Number(ao['Value'] ?? 0));
      }
      idMap.set(level, props);
    }
    BaseValueService.avatarPromotes = map;
    Logger.info(TAG, `avatarPromotes: ${map.size} ids`);
    return map;
  }

  /** 品质 → 最大等级（>=4星90，否则70；对齐 Windows GetMaxLevelByQuality） */
  static weaponMaxLevel(rankLevel: number): number {
    return rankLevel >= 4 ? 90 : 70;
  }

  /** 突破等级（对齐 Windows GetPromoteLevel） */
  static promoteLevel(level: number, maxLevel: number, promoted: boolean): number {
    if (promoted) {
      if (level >= 80) { return 6; }
      if (level >= 70) { return 5; }
      if (level >= 60) { return 4; }
      if (level >= 50) { return 3; }
      if (level >= 40) { return 2; }
      if (level >= 20) { return 1; }
      return 0;
    }
    if (level > 80) { return 6; }
    if (level > 70) { return 5; }
    if (level > 60) { return 4; }
    if (level > 50) { return 3; }
    if (level > 40) { return 2; }
    if (level > 20) { return 1; }
    return 0;
  }

  /** 武器某等级攻击力（value = InitValue × curve[level][growCurveType] + promote[promoteLevel][FIGHT_PROP_BASE_ATTACK]） */
  static async weaponAttack(id: number, level: number, promoted: boolean): Promise<number> {
    const weapon = await BaseValueService.weaponOf(id);
    if (weapon === undefined) {
      return 0;
    }
    const curves: Curves = await BaseValueService.getWeaponCurves();
    const promotes: Promotes = await BaseValueService.getWeaponPromotes();
    const maxLv: number = BaseValueService.weaponMaxLevel(weapon.rankLevel);
    const pLevel: number = BaseValueService.promoteLevel(level, maxLv, promoted);
    let base: number = 0;
    let added: number = 0;
    for (const g of weapon.growCurves) {
      // t: 4=FIGHT_PROP_BASE_ATTACK（攻击）；只算攻击
      if (g.t === 4) {
        const curveLevel: Map<number, number> | undefined = curves.get(level);
        base = g.i * ((curveLevel !== undefined ? curveLevel.get(g.v) : undefined) ?? 0);
      }
    }
    const pMap: Map<number, Map<number, number>> | undefined = promotes.get(weapon.promoteId);
    const pLevelMap: Map<number, number> | undefined = pMap !== undefined ? pMap.get(pLevel) : undefined;
    added = (pLevelMap !== undefined ? pLevelMap.get(4) : undefined) ?? 0;
    return Math.round(base + added);
  }

  private static async weaponOf(id: number): Promise<GrowCurveItem | undefined> {
    const meta = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(
      await AppContextProvider.getResourceManager().getRawFileContent('metadata/weapon_meta.json'))) as Object[];
    for (const raw of meta) {
      const o = raw as Record<string, Object>;
      if (Number(o['id']) === id) {
        const w: GrowCurveItem = { rankLevel: Number(o['rankLevel'] ?? 0), promoteId: Number(o['promoteId'] ?? 0), growCurves: [] };
        const arr = (o['growCurves'] as Object[]) ?? [];
        for (const g of arr) {
          const go = g as Record<string, Object>;
          const c: Curve3 = new Curve3();
          c.i = Number(go['i'] ?? 0);
          c.t = Number(go['t'] ?? 0);
          c.v = Number(go['v'] ?? 0);
          w.growCurves.push(c);
        }
        return w;
      }
    }
    return undefined;
  }

  private static async getWeaponCurves(): Promise<Curves> {
    if (BaseValueService.weaponCurves !== undefined) {
      return BaseValueService.weaponCurves;
    }
    const raw = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(
      await AppContextProvider.getResourceManager().getRawFileContent('metadata/WeaponCurve.json'))) as Object[];
    const map: Curves = new Map();
    for (const levelRow of raw) {
      const ro = levelRow as Record<string, Object>;
      const level = Number(ro['Level'] ?? 0);
      const inner: Map<number, number> = new Map();
      const curvesArr = (ro['Curves'] as Object[]) ?? [];
      for (const c of curvesArr) {
        const co = c as Record<string, Object>;
        inner.set(Number(co['Type'] ?? 0), Number(co['Value'] ?? 0));
      }
      map.set(level, inner);
    }
    BaseValueService.weaponCurves = map;
    Logger.info(TAG, `weaponCurves: ${map.size} levels`);
    return map;
  }

  private static async getWeaponPromotes(): Promise<Promotes> {
    if (BaseValueService.weaponPromotes !== undefined) {
      return BaseValueService.weaponPromotes;
    }
    const raw = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(
      await AppContextProvider.getResourceManager().getRawFileContent('metadata/WeaponPromote.json'))) as Object[];
    const map: Promotes = new Map();
    for (const row of raw) {
      const ro = row as Record<string, Object>;
      const promoteId = Number(ro['Id'] ?? 0);
      const level = Number(ro['Level'] ?? 0);
      let idMap: Map<number, Map<number, number>> | undefined = map.get(promoteId);
      if (idMap === undefined) {
        idMap = new Map();
        map.set(promoteId, idMap);
      }
      const props: Map<number, number> = new Map();
      const adds = (ro['AddProperties'] as Object[]) ?? [];
      for (const add of adds) {
        const ao = add as Record<string, Object>;
        props.set(Number(ao['Type'] ?? 0), Number(ao['Value'] ?? 0));
      }
      idMap.set(level, props);
    }
    BaseValueService.weaponPromotes = map;
    Logger.info(TAG, `weaponPromotes: ${map.size} ids`);
    return map;
  }
}

/** 武器曲线项（供等级滑条计算） */
export class GrowCurveItem {
  rankLevel: number = 0;
  promoteId: number = 0;
  growCurves: Curve3[] = [];
}

/** 角色成长信息（WikiAvatarMeta 传入，避免服务层反向解析 3MB 元数据） */
export class AvatarGrowInfo {
  hpBase: number = 0;
  attackBase: number = 0;
  defenseBase: number = 0;
  promoteId: number = 0;
  growCurves: Curve3[] = [];
}

/** 怪物基础属性计算结果 */
export class MonsterBaseValues {
  hp: number = 0;
  atk: number = 0;
  def: number = 0;
}

/** 角色基础属性计算结果 */
export class AvatarBaseValues {
  hp: number = 0;
  atk: number = 0;
  def: number = 0;
  /** 突破加成属性 id（非生命/攻击/防御；0=无） */
  bonusType: number = 0;
  bonusValue: number = 0;
  maxLevel: number = 90;
}

/** 单条曲线 */
export class Curve3 {
  i: number = 0;
  t: number = 0;
  v: number = 0;
}
