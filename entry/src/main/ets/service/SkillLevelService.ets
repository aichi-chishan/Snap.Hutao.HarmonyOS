/** Skill identity and base/display level semantics, independent of response array order. */
import { CharacterDetail, AvatarSkill, Constellation } from '../model/CharacterData';
import { AvatarSkillCatalog, AvatarSkillProfile, AvatarSkillReference, AvatarConstellationReference } from '../model/AvatarSkillReference';
import { MetaSkill } from './WikiMetaService';

export class ResolvedAvatarSkill {
  skillId: number = 0;
  groupId: number = 0;
  kind: string = '';
  name: string = '';
  icon: string = '';
  /** -1 means unavailable or inconsistent, never a zero-level talent. */
  baseLevel: number = -1;
  extraLevel: number = -1;
  displayLevel: number = -1;
}

export class SkillLevelService {
  /** The pinned source contains no depot IDs. Explicit unverified depots remain unknown. */
  static referenceSkills(avatarId: number, skillDepotId: number = 0): AvatarSkillReference[] {
    const profile: AvatarSkillProfile | undefined = SkillLevelService.profile(avatarId, skillDepotId);
    return profile === undefined ? [] : profile.skills.slice();
  }

  static resolve(detail: CharacterDetail): ResolvedAvatarSkill[] {
    const profile: AvatarSkillProfile | undefined = SkillLevelService.profile(detail.id, detail.skillDepotId);
    if (profile === undefined) {
      return [];
    }
    const result: ResolvedAvatarSkill[] = [];
    for (const reference of profile.skills) {
      const resolved: ResolvedAvatarSkill = new ResolvedAvatarSkill();
      resolved.skillId = reference.skillId;
      resolved.groupId = reference.groupId;
      resolved.kind = reference.kind;
      resolved.name = reference.name;
      resolved.icon = reference.icon;
      const matches: AvatarSkill[] = detail.skills.filter((skill: AvatarSkill): boolean => skill.skillId === reference.skillId);
      if (matches.length === 1 && Number.isInteger(matches[0].level) && matches[0].level >= 1 && matches[0].level <= 15) {
        // character/detail reports total displayed level, including known constellation/passive bonuses.
        resolved.displayLevel = matches[0].level;
      }
      resolved.extraLevel = SkillLevelService.extraLevel(detail, profile, reference.kind);
      if (resolved.displayLevel >= 1 && resolved.extraLevel >= 0) {
        const base: number = resolved.displayLevel - resolved.extraLevel;
        if (base >= 1 && base <= 10) {
          resolved.baseLevel = base;
        }
      }
      result.push(resolved);
    }
    return result;
  }

  /** Presentation metadata has no IDs: require exact name+icon within the verified avatar profile. */
  static forMetaSkill(detail: CharacterDetail, meta: MetaSkill): ResolvedAvatarSkill | undefined {
    return SkillLevelService.resolve(detail).find((skill: ResolvedAvatarSkill): boolean =>
      skill.name === meta.n && skill.icon === meta.i);
  }

  /** Old compact metadata mislabels prefixed non-upgradable jump/sprint entries by position. */
  static kindOfMetaSkill(detail: CharacterDetail, meta: MetaSkill): string {
    const skill: ResolvedAvatarSkill | undefined = SkillLevelService.forMetaSkill(detail, meta);
    if (skill !== undefined) {
      return skill.kind;
    }
    return SkillLevelService.referenceSkills(detail.id, detail.skillDepotId).length > 0 && meta.k !== 'P' ? 'X' : meta.k;
  }

  static formatSkill(skill: ResolvedAvatarSkill): string {
    if (skill.displayLevel < 1) {
      return '等级未知';
    }
    if (skill.baseLevel < 1 || skill.extraLevel < 0) {
      return `Lv.${skill.displayLevel}（基础/加成未知）`;
    }
    return skill.extraLevel > 0 ? `Lv.${skill.baseLevel}+${skill.extraLevel}` : `Lv.${skill.baseLevel}`;
  }

  static formatDetail(detail: CharacterDetail): string {
    const skills: ResolvedAvatarSkill[] = SkillLevelService.resolve(detail);
    if (skills.length === 0) {
      return '天赋映射未知';
    }
    return skills.map((skill: ResolvedAvatarSkill): string =>
      `${skill.kind} ${SkillLevelService.formatSkill(skill)}`).join(', ');
  }

  private static profile(avatarId: number, skillDepotId: number): AvatarSkillProfile | undefined {
    if (skillDepotId !== 0) {
      return undefined;
    }
    return AvatarSkillCatalog.profiles.find((profile: AvatarSkillProfile): boolean => profile.avatarId === avatarId);
  }

  private static extraLevel(detail: CharacterDetail, profile: AvatarSkillProfile, kind: string): number {
    let extra: number = kind === 'A' ? profile.normalAttackExtra : 0;
    for (let index: number = 0; index < profile.constellations.length; index++) {
      const reference: AvatarConstellationReference = profile.constellations[index];
      if (reference.kind !== kind || reference.extraLevel === 0) {
        continue;
      }
      const state: number = SkillLevelService.constellationState(detail, profile, index);
      if (state < 0) {
        return -1;
      }
      if (state === 1) {
        extra += reference.extraLevel;
      }
    }
    return extra;
  }

  private static constellationState(detail: CharacterDetail, profile: AvatarSkillProfile, index: number): number {
    const count: number = detail.activedConstellationNum;
    const countKnown: boolean = Number.isInteger(count) && count >= 0 && count <= profile.constellations.length;
    const seen: Set<number> = new Set<number>();
    let firstInactive: number = profile.constellations.length;
    let lastActive: number = -1;
    for (const cell of detail.constellations) {
      const rank: number = profile.constellations.findIndex((reference: AvatarConstellationReference): boolean => reference.id === cell.id);
      if (rank < 0 || seen.has(cell.id) || (countKnown && cell.activationKnown && cell.isActived !== (rank < count))) {
        return -1;
      }
      seen.add(cell.id);
      if (cell.activationKnown) {
        if (cell.isActived) {
          lastActive = Math.max(lastActive, rank);
        } else {
          firstInactive = Math.min(firstInactive, rank);
        }
      }
    }
    if (lastActive > firstInactive) {
      return -1;
    }
    if (countKnown) {
      return index < count ? 1 : 0;
    }
    const cell: Constellation | undefined = detail.constellations.find((item: Constellation): boolean =>
      item.id === profile.constellations[index].id);
    return cell !== undefined && cell.activationKnown ? (cell.isActived ? 1 : 0) : -1;
  }
}
