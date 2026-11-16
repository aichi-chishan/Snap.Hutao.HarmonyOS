/** The order matches the four sources in Windows SkillDepot.CompositeSkills. */
export enum AvatarWikiSkillKind {
  Skill,
  Energy,
  Special,
  Inherent,
}

export interface AvatarSkillParameterSeries {
  label: string;
  /** A single value is shared by every available level. */
  values: string[];
  isSpecial: boolean;
}

export interface AvatarWikiSkill {
  id: number;
  groupId: number;
  kind: AvatarWikiSkillKind;
  name: string;
  icon: string;
  description: string;
  specialDescription: string;
  levels: number[];
  /** Zero when Windows has no parameter panel for the skill. */
  defaultLevel: number;
  parameterSeries: AvatarSkillParameterSeries[];
}

export class AvatarSkillParameterRow {
  label: string;
  value: string;
  isSpecial: boolean;

  constructor(label: string, value: string, isSpecial: boolean) {
    this.label = label;
    this.value = value;
    this.isSpecial = isSpecial;
  }
}

interface AvatarWikiSkillFile {
  schema: number;
  locale: string;
  avatars: Record<string, AvatarWikiSkill[]>;
}

/** Shared by verified snapshot reads and the bundled lookup. */
export class AvatarWikiSkillCatalog {
  static fileName(locale: string): string { return `avatar_skill_${locale}.json`; }

  static parse(text: string, locale: string): Record<string, AvatarWikiSkill[]> {
    const document: AvatarWikiSkillFile = JSON.parse(text) as AvatarWikiSkillFile;
    if (document === null || document.schema !== 1 || document.locale !== locale ||
      document.avatars === null || typeof document.avatars !== 'object' || Array.isArray(document.avatars)) {
      throw new Error('Invalid avatar skill catalog');
    }
    for (const id of Object.keys(document.avatars)) {
      const skills: AvatarWikiSkill[] = document.avatars[id];
      if (!/^[1-9][0-9]*$/.test(id) || !Array.isArray(skills) || skills.length === 0) {
        throw new Error('Invalid avatar skill list');
      }
      const seen: Set<number> = new Set<number>();
      for (const skill of skills) {
        if (!AvatarWikiSkillCatalog.validSkill(skill) || seen.has(skill.id)) { throw new Error('Invalid avatar skill'); }
        seen.add(skill.id);
      }
    }
    return document.avatars;
  }

  private static validSkill(skill: AvatarWikiSkill): boolean {
    if (skill === null || !Number.isSafeInteger(skill.id) || skill.id <= 0 || !Number.isSafeInteger(skill.groupId) ||
      !Number.isInteger(skill.kind) || skill.kind < AvatarWikiSkillKind.Skill || skill.kind > AvatarWikiSkillKind.Inherent ||
      typeof skill.name !== 'string' || typeof skill.icon !== 'string' || typeof skill.description !== 'string' ||
      typeof skill.specialDescription !== 'string' || !Array.isArray(skill.levels) || !Array.isArray(skill.parameterSeries)) {
      return false;
    }
    const levels: number[] = skill.levels;
    if (levels.length === 0) { return skill.defaultLevel === 0 && skill.parameterSeries.length === 0; }
    if (skill.defaultLevel !== levels[Math.min(9, levels.length - 1)] || skill.parameterSeries.length === 0 ||
      levels.some((level: number, index: number): boolean => !Number.isSafeInteger(level) || level <= 0 ||
        (index > 0 && level <= levels[index - 1]))) { return false; }
    return skill.parameterSeries.every((row: AvatarSkillParameterSeries): boolean =>
      row !== null && typeof row.label === 'string' && typeof row.isSpecial === 'boolean' && Array.isArray(row.values) &&
      (row.values.length === 1 || row.values.length === levels.length) &&
      row.values.every((value: string): boolean => typeof value === 'string'));
  }
}
