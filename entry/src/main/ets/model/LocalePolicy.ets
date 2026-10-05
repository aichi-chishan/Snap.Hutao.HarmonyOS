/** Help and app-owned common messages only. Game data and the remaining UI keep their source text. */
export class LocalePolicy {
  private static readonly LOCALES: string[] = ['zh-Hans', 'zh-Hant', 'en'];
  static locales(): string[] { return LocalePolicy.LOCALES.slice(); }
  static preference(value: string): string {
    return value === 'system' || LocalePolicy.LOCALES.includes(value) ? value : 'system';
  }
  static resourceLocale(value: string): string {
    const tag: string = value.trim().slice(0, 80).replace(/_/g, '-').toLowerCase();
    if (/^zh(?:-|$)/.test(tag)) {
      const parts: string[] = tag.split('-');
      if (parts.includes('hant')) { return 'zh-Hant'; }
      if (parts.includes('hans')) { return 'zh-Hans'; }
      return parts.includes('tw') || parts.includes('hk') || parts.includes('mo') ? 'zh-Hant' : 'zh-Hans';
    }
    return 'en';
  }
  static supported(value: string): boolean { return /^(zh|en)(?:[-_]|$)/i.test(value.trim()); }
}
