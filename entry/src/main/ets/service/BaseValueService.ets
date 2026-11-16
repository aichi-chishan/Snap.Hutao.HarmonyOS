/**
 * BaseValueService.ets
 * 基础数值曲线计算（对齐 Windows BaseValueInfoConverter 公式）：
 *   值(level, promoted) = InitValue × GrowCurveMap[level][growCurveType] + PromoteMap[promoteLevel].AddProperties[fightProperty]
 * 数据：rawfile/metadata/{WeaponCurve,WeaponPromote,AvatarCurve,AvatarPromote,MonsterCurve}.json
 */
import { GameDataService } from './GameDataService';
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

  /** 角色品质 → 最大等级（4/5 星 100；对齐 Windows Avatar.GetMaxLevel，6.x 起上限 100） */
  static avatarMaxLevel(quality: number): number {
    return quality >= 4 ? 100 : 70;
  }

  /** 战斗属性中文名（1 生命/4 攻击/7 防御 + 突破属性） */
  static fightPropName(t: number): string {
    switch (t) {
      case 1: return '生命值';
      case 3: return '生命值';
      case 4: return '攻击力';
      case 6: return '攻击力';
      case 7: return '防御力';
      case 9: return '防御力';
      case 20: return '暴击率';
      case 22: return '暴击伤害';
      case 23: return '元素充能效率';
      case 26: return '治疗加成';
      case 27: return '受治疗加成';
      case 28: return '元素精通';
      case 30: return '物理伤害加成';
      case 40: return '火元素伤害加成';
      case 41: return '雷元素伤害加成';
      case 42: return '水元素伤害加成';
      case 43: return '草元素伤害加成';
      case 44: return '风元素伤害加成';
      case 45: return '岩元素伤害加成';
      case 46: return '冰元素伤害加成';
      default: return '';
    }
  }

  /** 百分比型战斗属性集合（值按 ×100 显示） */
  private static isPercentProp(t: number): boolean {
    return [3, 6, 9, 20, 22, 23, 26, 27, 30].includes(t) || (t >= 40 && t <= 46);
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
    const raw = JSON.parse(await GameDataService.readMetadataFile('MonsterCurve.json')) as Object[];
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
    const raw = JSON.parse(await GameDataService.readMetadataFile('AvatarCurve.json')) as Object[];
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
    const raw = JSON.parse(await GameDataService.readMetadataFile('AvatarPromote.json')) as Object[];
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

  /** 三星及以上武器最高 90 级，其余最高 70 级。 */
  static weaponMaxLevel(rankLevel: number): number {
    return rankLevel >= 3 ? 90 : 70;
  }

  /** 突破等级（对齐 Windows GetPromoteLevel） */
  static promoteLevel(level: number, maxLevel: number, promoted: boolean): number {
    if (maxLevel <= 70 && level === 70) { return 4; }
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

  /** 计算已载入的武器攻击力与副属性。 */
  static async weaponBaseValues(growCurves: Curve3[], promoteId: number, maxLevel: number,
    level: number, promoted: boolean): Promise<WeaponBaseValues> {
    const curves: Curves = await BaseValueService.getWeaponCurves();
    const promotes: Promotes = await BaseValueService.getWeaponPromotes();
    const pLevel: number = BaseValueService.promoteLevel(level, maxLevel, promoted);
    const curveLevel: Map<number, number> | undefined = curves.get(level);
    const added: Map<number, number> | undefined = promotes.get(promoteId)?.get(pLevel);
    const result: WeaponBaseValues = new WeaponBaseValues();
    for (const curve of growCurves) {
      const value: number = curve.i * (curveLevel?.get(curve.v) ?? 0) + (added?.get(curve.t) ?? 0);
      if (curve.t === 4) {
        result.attack = Math.round(value);
      } else {
        result.secondary = `${BaseValueService.fightPropName(curve.t)} ${BaseValueService.fightPropText(curve.t, value)}`;
      }
    }
    return result;
  }

  private static async getWeaponCurves(): Promise<Curves> {
    if (BaseValueService.weaponCurves !== undefined) {
      return BaseValueService.weaponCurves;
    }
    const raw = JSON.parse(await GameDataService.readMetadataFile('WeaponCurve.json')) as Object[];
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
    const raw = JSON.parse(await GameDataService.readMetadataFile('WeaponPromote.json')) as Object[];
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
export class WeaponBaseValues {
  attack: number = 0;
  secondary: string = '';
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
  maxLevel: number = 100;
}

/** 单条曲线 */
export class Curve3 {
  i: number = 0;
  t: number = 0;
  v: number = 0;
}
