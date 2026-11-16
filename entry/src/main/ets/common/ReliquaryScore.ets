/**
 * ReliquaryScore.ets
 * 圣遗物评分（对齐 Windows ReliquaryScoreCalculator 完整算法）：
 *  - 推荐词条权重 1.0（固定生命/攻击/防御权重 0.5）
 *  - 充能：非推荐时按能量类型（SPECIAL_ENERGY_NONE → 0.2/1.0；其他 → 1.0、有暴伤 0）
 *  - 暴击率 ×2.0、暴击伤害 ×1.0、元素精通 ×0.33、充能 ×1.1979、
 *    HP%/ATK% ×1.33、DEF% ×1.06、ATK 固定 ×0.398×0.5、HP 固定 ×0.026×0.66、DEF 固定 ×0.335×0.66
 *  - isCritEffective（Windows AvatarIds.IsCritEffective，最新新增）：
 *    仅珊瑚宫心海（天赋降低自身暴击率，无法暴击）双爆无效，其余角色双爆强制有效
 */
import { CharacterDetail, Reliquary, RelicProperty } from '../model/CharacterData';

/** 珊瑚宫心海（双爆无效特例） */
const KOKOMI_ID: number = 10000054;

export class ReliquaryScore {
  // Special energy types in the Windows avatar metadata: Mavuika and Skirk.
  private static readonly SPECIAL_ENERGY_AVATARS: number[] = [10000106, 10000114];
  private static readonly PROPERTY_IDS: number[] = [20, 22, 6, 23, 28, 3, 9, 2, 5, 8];
  private static readonly PROPERTY_NAMES: string[] = [
    'FIGHT_PROP_CRITICAL', 'FIGHT_PROP_CRITICAL_HURT', 'FIGHT_PROP_ATTACK_PERCENT',
    'FIGHT_PROP_CHARGE_EFFICIENCY', 'FIGHT_PROP_ELEMENT_MASTERY', 'FIGHT_PROP_HP_PERCENT',
    'FIGHT_PROP_DEFENSE_PERCENT', 'FIGHT_PROP_HP', 'FIGHT_PROP_ATTACK', 'FIGHT_PROP_DEFENSE'
  ];

  static forCharacter(reliquary: Reliquary, detail: CharacterDetail, weights?: number[]): number {
    if (weights !== undefined) { return ReliquaryScore.profileScore(reliquary.subProperties, weights); }
    const energyType: string = ReliquaryScore.SPECIAL_ENERGY_AVATARS.includes(detail.id)
      ? 'SPECIAL_ENERGY' : detail.recommend.energyType;
    return ReliquaryScore.calculate(reliquary.subProperties, detail.recommend.subProperties,
      energyType, ReliquaryScore.isCritEffective(detail.id));
  }

  static totalForCharacter(detail: CharacterDetail, weights?: number[]): number {
    return detail.reliquaries.reduce((sum: number, reliquary: Reliquary): number =>
      sum + ReliquaryScore.forCharacter(reliquary, detail, weights), 0);
  }

  /** Windows Calculate，保留原始精度，展示时再取一位小数。 */
  static calculate(subProps: RelicProperty[], recommended: string[], energyType: string,
    isCritEffective: boolean = true): number {
    const propertyNames: string[] = recommended.map((property: string): string => ReliquaryScore.propertyName(property));
    const hasCritHurt: boolean = isCritEffective || propertyNames.includes('FIGHT_PROP_CRITICAL_HURT');
    let total: number = 0;
    for (const sp of subProps) {
      const prop: string = ReliquaryScore.propertyName(sp.propertyType);
      const weight: number = ReliquaryScore.weight(prop, propertyNames, hasCritHurt, energyType, isCritEffective);
      if (weight <= 0) {
        continue;
      }
      const value: number = ReliquaryScore.parseValue(sp.value);
      total += ReliquaryScore.scoreStat(prop, value, weight);
    }
    return total;
  }

  /** 权重（Windows GetWeight；isCritEffective 时双爆权重强制 1.0） */
  private static weight(prop: string, recommended: string[], hasCritHurt: boolean, energyType: string,
    isCritEffective: boolean): number {
    const isRecommended: boolean = recommended.indexOf(prop) >= 0;
    if (isCritEffective
      && (prop === 'FIGHT_PROP_CRITICAL' || prop === 'FIGHT_PROP_CRITICAL_HURT')) {
      // 非心海角色双爆强制有效：避免米游社推荐副属性缺失双爆时评分失真
      return 1.0;
    }
    if (prop === 'FIGHT_PROP_CHARGE_EFFICIENCY' && !isRecommended) {
      // 充能非推荐：按能量类型特判
      if (energyType !== 'SPECIAL_ENERGY_NONE' && energyType.length > 0 && energyType !== 'NONE' && energyType !== '0') {
        return hasCritHurt ? 0 : 1.0;
      }
      return hasCritHurt ? 0.2 : 1.0;
    }
    if (!isRecommended) {
      return 0;
    }
    let weight: number = 1.0;
    if (prop === 'FIGHT_PROP_HP' ||
      prop === 'FIGHT_PROP_ATTACK' ||
      prop === 'FIGHT_PROP_DEFENSE') {
      weight *= 0.5;
    }
    return weight;
  }

  /** 单条词条分值（Windows ScoreStat） */
  private static scoreStat(prop: string, value: number, weight: number): number {
    switch (prop) {
      case 'FIGHT_PROP_CRITICAL':
        return value * 2.0 * weight;
      case 'FIGHT_PROP_CRITICAL_HURT':
        return value * 1.0 * weight;
      case 'FIGHT_PROP_ELEMENT_MASTERY':
        return value * 0.33 * weight;
      case 'FIGHT_PROP_CHARGE_EFFICIENCY':
        return value * 1.1979 * weight;
      case 'FIGHT_PROP_HP_PERCENT':
        return value * 1.33 * weight;
      case 'FIGHT_PROP_ATTACK_PERCENT':
        return value * 1.33 * weight;
      case 'FIGHT_PROP_DEFENSE_PERCENT':
        return value * 1.06 * weight;
      case 'FIGHT_PROP_ATTACK':
        return value * 0.398 * 0.5 * weight;
      case 'FIGHT_PROP_HP':
        return value * 0.026 * 0.66 * weight;
      case 'FIGHT_PROP_DEFENSE':
        return value * 0.335 * 0.66 * weight;
      default:
        return 0;
    }
  }

  /** 单独计算双暴分。 */
  static doubleCritScore(r: Reliquary, isCritEffective: boolean = true): number {
    if (!isCritEffective) {
      return 0;
    }
    let crit: number = 0;
    let critHurt: number = 0;
    for (const sp of r.subProperties) {
      const prop: string = ReliquaryScore.propertyName(sp.propertyType);
      if (prop === 'FIGHT_PROP_CRITICAL') {
        crit += ReliquaryScore.parseValue(sp.value);
      } else if (prop === 'FIGHT_PROP_CRITICAL_HURT') {
        critHurt += ReliquaryScore.parseValue(sp.value);
      }
    }
    return Math.round((crit * 2 + critHurt) * 10) / 10;
  }

  /**
   * Windows CalculateWithWeights。角色接口的百分比词条已使用百分点数。
   */
  static profileScore(subProps: RelicProperty[], weights: number[]): number {
    let total: number = 0;
    for (const sp of subProps) {
      const prop: string = ReliquaryScore.propertyName(sp.propertyType);
      const slot: number = ReliquaryScore.PROPERTY_NAMES.indexOf(prop);
      const weight: number = weights[slot] ?? 0;
      if (weight > 0) { total += ReliquaryScore.scoreStat(prop, ReliquaryScore.parseValue(sp.value), weight); }
    }
    return total;
  }

  private static propertyName(prop: string): string {
    const index: number = ReliquaryScore.PROPERTY_IDS.indexOf(Number(prop));
    return index >= 0 ? ReliquaryScore.PROPERTY_NAMES[index] : prop;
  }

  /** 角色双爆是否有效（Windows AvatarIds.IsCritEffective：仅心海无效） */
  static isCritEffective(avatarId: number): boolean {
    return avatarId !== KOKOMI_ID;
  }

  static parseValue(v: string): number {
    const n: number = Number.parseFloat(v.replace('%', ''));
    return Number.isNaN(n) ? 0 : n;
  }
}
