/** Scoring/presets adapted from Snap.Hutao.Remastered@3f0d1f3 (MIT, Copyright (c) DGP Studio).
 * Source identities and exact semantics: docs/BACKPACK_SCORING_2026-10-05.md.
 */
import { ReliquaryAffixReference } from './ReliquaryAffixReference';

/** Pure config values. This score is independent of a character's recommended-stat score. */
export class BackpackScoreProfile {
  id: string = '';
  name: string = '默认';
  preset: number = 0;
  algorithm: number = 1;
  /** Crit, crit damage, ATK%, ER, EM, HP%, DEF%. */
  weights: number[] = [1, 1, 0.2, 0.2, 0.2, 0, 0];

  static readonly PRESETS: string[] = ['默认', '攻击收益', '生命收益', '防御收益', '精通收益', '自定义'];
  static readonly LABELS: string[] = ['暴击率', '暴击伤害', '攻击力%', '元素充能效率', '元素精通', '生命值%', '防御力%'];
  static readonly PROPERTIES: number[] = [20, 22, 6, 23, 28, 3, 9];

  static create(preset: number): BackpackScoreProfile {
    const profile: BackpackScoreProfile = new BackpackScoreProfile();
    profile.preset = preset;
    profile.name = BackpackScoreProfile.PRESETS[preset] ?? '自定义';
    if (preset >= 1 && preset <= 4) {
      profile.weights = [1, 1, 0, 0, 0, 0, 0];
      const slots: number[] = [2, 5, 6, 4];
      profile.weights[slots[preset - 1]] = 1;
    }
    return profile;
  }

  static clone(source: BackpackScoreProfile): BackpackScoreProfile {
    const profile: BackpackScoreProfile = new BackpackScoreProfile();
    profile.id = source.id;
    profile.name = source.name;
    profile.preset = source.preset;
    profile.algorithm = source.algorithm;
    profile.weights = source.weights.slice();
    return profile;
  }

  static validate(profile: BackpackScoreProfile): void {
    if (profile === null || typeof profile !== 'object' || typeof profile.id !== 'string' ||
      profile.id.length > 100 || typeof profile.name !== 'string' || profile.name.trim().length === 0 ||
      profile.name.length > 80 || profile.algorithm !== 1 || !Number.isInteger(profile.preset) ||
      profile.preset < 0 || profile.preset > 5 || !Array.isArray(profile.weights) || profile.weights.length !== 7 ||
      profile.weights.some((weight: number): boolean => typeof weight !== 'number' || !Number.isFinite(weight) || weight < 0 || weight > 1)) {
      throw new Error('评分配置无效：名称须为 1–80 字，七项权重须为 0–1');
    }
  }
}

export class BackpackSubStat {
  property: number = 0;
  rawValue: number = 0;
  rolls: number = 0;
}

export class BackpackScoreResult {
  available: boolean = false;
  value: number = 0;
  profileName: string = '';
  reason: string = '';
  unknownIds: number[] = [];
  stats: BackpackSubStat[] = [];
}

export class BackpackScoreSettings {
  version: number = 1;
  revision: number = 0;
  activeId: string = '';
  profiles: BackpackScoreProfile[] = [];
  /** Not persisted: preserves a bad source rather than silently overwriting it. */
  warning: string = '';
}

/** Captured when opening the editor, invalidated by archive changes, reloads or another save. */
export class BackpackScoreEdit {
  archiveId: number = 0;
  generation: number = 0;
  settingsRevision: number = 0;
  profile: BackpackScoreProfile = new BackpackScoreProfile();
}

export class BackpackScoring {
  private static affixes: Map<number, number[]> = new Map<number, number[]>();

  static calculate(appendIds: number[], profile: BackpackScoreProfile): BackpackScoreResult {
    BackpackScoreProfile.validate(profile);
    if (BackpackScoring.affixes.size === 0) {
      for (const row of ReliquaryAffixReference.rows) { BackpackScoring.affixes.set(row[0], row); }
    }
    const result: BackpackScoreResult = new BackpackScoreResult();
    result.profileName = profile.name;
    if (appendIds.length === 0) {
      result.reason = '未提供副词条记录';
      return result;
    }
    const merged: Map<number, BackpackSubStat> = new Map<number, BackpackSubStat>();
    for (const id of appendIds) {
      const reference: number[] | undefined = BackpackScoring.affixes.get(id);
      if (reference === undefined) { result.unknownIds.push(id); continue; }
      let stat: BackpackSubStat | undefined = merged.get(reference[1]);
      if (stat === undefined) {
        stat = new BackpackSubStat(); stat.property = reference[1]; merged.set(stat.property, stat);
      }
      stat.rawValue += reference[2];
      stat.rolls++;
    }
    result.stats = Array.from(merged.values());
    if (result.unknownIds.length > 0) {
      result.reason = `未识别副词条：${result.unknownIds.join('、')}`;
      return result;
    }
    for (const stat of result.stats) {
      const slot: number = BackpackScoreProfile.PROPERTIES.indexOf(stat.property);
      if (slot < 0) { continue; } // Known flat and non-configurable properties have zero weight in Windows.
      const factors: number[] = [2, 1, 1.33, 1.1979, 0.33, 1.33, 1.06];
      const normalized: number = stat.property === 28 ? stat.rawValue : stat.rawValue * 100;
      result.value += normalized * factors[slot] * profile.weights[slot];
    }
    result.available = true;
    return result;
  }

  static label(result: BackpackScoreResult): string {
    return result.available ? `${result.value.toFixed(1)} 分 · ${result.profileName}` : `评分不可用 · ${result.reason}`;
  }

  static statLabel(stat: BackpackSubStat): string {
    const slot: number = BackpackScoreProfile.PROPERTIES.indexOf(stat.property);
    let name: string = slot >= 0 ? BackpackScoreProfile.LABELS[slot] : `属性 ${stat.property}`;
    if (stat.property === 2) { name = '生命值'; }
    if (stat.property === 5) { name = '攻击力'; }
    if (stat.property === 8) { name = '防御力'; }
    const percentage: boolean = slot >= 0 && stat.property !== 28;
    const value: string = percentage ? `${(stat.rawValue * 100).toFixed(1)}%` : stat.rawValue.toFixed(1);
    return `${name} ${value} · 强化 ${Math.max(0, stat.rolls - 1)} 次`;
  }
}
