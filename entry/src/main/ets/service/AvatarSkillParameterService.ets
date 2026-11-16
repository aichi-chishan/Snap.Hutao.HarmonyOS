import { Logger } from '../common/Logger';
import { AvatarSkillParameterRow, AvatarSkillParameterSeries, AvatarWikiSkill, AvatarWikiSkillCatalog } from '../model/AvatarWikiSkill';
import { AppLocaleService } from './AppLocaleService';
import { GameDataService } from './GameDataService';

/** Reads the parameter values formatted from the pinned Windows metadata. */
export class AvatarSkillParameterService {
  private static locale: string = '';
  private static catalog: Promise<Record<string, AvatarWikiSkill[]>> | undefined = undefined;

  static async forAvatar(avatarId: number): Promise<AvatarWikiSkill[]> {
    const locale: string = AppLocaleService.current();
    const pendingCatalog: Promise<Record<string, AvatarWikiSkill[]>> = AvatarSkillParameterService.catalogFor(locale);
    const catalog: Record<string, AvatarWikiSkill[]> = await pendingCatalog;
    return catalog[String(avatarId)] ?? [];
  }

  private static catalogFor(locale: string): Promise<Record<string, AvatarWikiSkill[]>> {
    if (AvatarSkillParameterService.catalog !== undefined && AvatarSkillParameterService.locale === locale) {
      return AvatarSkillParameterService.catalog;
    }
    AvatarSkillParameterService.locale = locale;
    const loading: Promise<Record<string, AvatarWikiSkill[]>> = AvatarSkillParameterService.readCatalog(locale);
    AvatarSkillParameterService.catalog = loading;
    return loading;
  }

  static rows(skill: AvatarWikiSkill, level: number): AvatarSkillParameterRow[] {
    const index: number = skill.levels.indexOf(level);
    if (index < 0) { return []; }
    return skill.parameterSeries.map((series: AvatarSkillParameterSeries): AvatarSkillParameterRow =>
      new AvatarSkillParameterRow(series.label, series.values[series.values.length === 1 ? 0 : index], series.isSpecial));
  }

  private static async readCatalog(locale: string): Promise<Record<string, AvatarWikiSkill[]>> {
    try {
      const text: string = await GameDataService.readMetadataFile(AvatarWikiSkillCatalog.fileName(locale));
      return AvatarWikiSkillCatalog.parse(text, locale);
    } catch (error) {
      Logger.warn('AvatarSkillParameters', `Unable to read ${locale}: ${(error as Error).message}`);
      return {};
    }
  }
}
