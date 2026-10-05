import { RegionUtil } from '../common/Constants';

/** Public announcement browsing is explicit and does not require an account. */
export class AnnouncementContext {
  region: string = 'cn_gf01';
  language: string = 'zh-cn';
  level: number = 55;

  static readonly REGIONS: string[] = ['cn_gf01', 'cn_qd01', 'os_usa', 'os_euro', 'os_asia', 'os_cht'];
  static readonly REGION_NAMES: string[] = ['国服 · 天空岛', '国服 · 世界树', '美服', '欧服', '亚服', '港澳台服'];
  static readonly LANGUAGES: string[] = ['zh-cn', 'zh-tw', 'en-us', 'ja-jp', 'ko-kr', 'de-de', 'es-es', 'fr-fr', 'id-id', 'pt-pt', 'ru-ru', 'th-th', 'vi-vn', 'tr-tr', 'it-it'];
  static readonly LANGUAGE_NAMES: string[] = ['简体中文', '繁體中文', 'English', '日本語', '한국어', 'Deutsch', 'Español', 'Français', 'Bahasa Indonesia', 'Português', 'Русский', 'ไทย', 'Tiếng Việt', 'Türkçe', 'Italiano'];

  static create(region: string, language: string = 'zh-cn', level: number = 55): AnnouncementContext {
    if (!AnnouncementContext.REGIONS.includes(region) || !AnnouncementContext.LANGUAGES.includes(language) ||
      !Number.isSafeInteger(level) || level < 1 || level > 60) { throw new Error('公告区服、语言或等级参数无效'); }
    const context: AnnouncementContext = new AnnouncementContext();
    context.region = region; context.language = language; context.level = level;
    return context;
  }

  static forUid(uid: string): AnnouncementContext {
    return AnnouncementContext.create(RegionUtil.isValidUid(uid) ? RegionUtil.regionOfUid(uid) : 'cn_gf01');
  }

  key(): string { return `${this.region}|${this.language}|${this.level}`; }
  label(): string {
    return `${AnnouncementContext.REGION_NAMES[AnnouncementContext.REGIONS.indexOf(this.region)]} · ${AnnouncementContext.LANGUAGE_NAMES[AnnouncementContext.LANGUAGES.indexOf(this.language)]}`;
  }
}
