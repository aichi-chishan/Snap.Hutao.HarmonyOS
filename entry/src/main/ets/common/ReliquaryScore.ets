/**
 * ReliquaryScore.ets
 * 圣遗物评分（对齐 Windows ReliquaryScoreCalculator 完整算法）：
 *  - 推荐词条权重 1.0（生命/攻击/防御% 降 0.5；固定值另乘系数）
 *  - 充能：非推荐时按能量类型（SPECIAL_ENERGY_NONE → 0.2/1.0；其他 → 1.0、有暴伤 0）
 *  - 暴击率 ×2.0、暴击伤害 ×1.0、元素精通 ×0.33、充能 ×1.1979、
 *    HP%/ATK% ×1.33、DEF% ×1.06、ATK 固定 ×0.398×0.5、HP 固定 ×0.026×0.66、DEF 固定 ×0.335×0.66
 *  - 无推荐词条时回退"双爆分"（crit×2 + critHurt×1）
 *  - isCritEffective（Windows AvatarIds.IsCritEffective，最新新增）：
 *    仅珊瑚宫心海（天赋降低自身暴击率，无法暴击）双爆无效，其余角色双爆强制有效
 */
import { Reliquary, RelicProperty } from '../model/CharacterData';

/** 珊瑚宫心海（双爆无效特例） */
const KOKOMI_ID: number = 10000002;

export class ReliquaryScore {
  /** 完整评分（Windows Calculate 等价物，分值 ×10 取 1 位小数为展示惯例由调用方处理） */
  static calculate(subProps: RelicProperty[], recommended: string[], energyType: string,
    isCritEffective: boolean = true): number {
    const hasCritHurt: boolean = isCritEffective
      || recommended.indexOf('FIGHT_PROP_CRITICAL_HURT') >= 0;
    let total: number = 0;
    for (const sp of subProps) {
      const weight: number = ReliquaryScore.weight(sp.propertyType, recommended, hasCritHurt, energyType,
        isCritEffective);
      if (weight <= 0) {
        continue;
      }
      const value: number = ReliquaryScore.parseValue(sp.value);
      total += ReliquaryScore.scoreStat(sp.propertyType, value, weight);
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
      if (energyType !== 'SPECIAL_ENERGY_NONE' && energyType.length > 0 && energyType !== 'NONE') {
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

  /** 双爆分（无推荐词条兜底；心海双爆无效 → 0 分） */
  static doubleCritScore(r: Reliquary, isCritEffective: boolean = true): number {
    if (!isCritEffective) {
      return 0;
    }
    let crit: number = 0;
    let critHurt: number = 0;
    for (const sp of r.subProperties) {
      if (sp.propertyType === 'FIGHT_PROP_CRITICAL') {
        crit += ReliquaryScore.parseValue(sp.value);
      } else if (sp.propertyType === 'FIGHT_PROP_CRITICAL_HURT') {
        critHurt += ReliquaryScore.parseValue(sp.value);
      }
    }
    return Math.round((crit * 2 + critHurt) * 10) / 10;
  }

  /** 角色双爆是否有效（Windows AvatarIds.IsCritEffective：仅心海无效） */
  static isCritEffective(avatarId: number): boolean {
    return avatarId !== KOKOMI_ID;
  }

  /** 等级评价（双爆分口径） */
  static grade(score: number): string {
    if (score >= 50) {
      return '毕业典藏';
    }
    if (score >= 35) {
      return '极品';
    }
    if (score >= 20) {
      return '优秀';
    }
    if (score >= 10) {
      return '良好';
    }
    return '过渡';
  }

  static parseValue(v: string): number {
    const n: number = Number.parseFloat(v.replace('%', ''));
    return Number.isNaN(n) ? 0 : n;
  }
}
