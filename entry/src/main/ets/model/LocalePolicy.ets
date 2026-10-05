/** Help and integrated app-owned common messages only; other UI and game text retain their source language. */
export class LocalePolicy {
  private static readonly LOCALES: string[] = ['zh-Hans', 'zh-Hant', 'en', 'de', 'es', 'fr', 'id', 'it', 'ja', 'ko', 'pt', 'ru', 'th', 'tr', 'vi'];
  private static readonly NAMES: string[] = ['简体中文', '繁體中文', 'English', 'Deutsch', 'Español', 'Français', 'Bahasa Indonesia', 'Italiano', '日本語', '한국어', 'Português', 'Русский', 'ไทย', 'Türkçe', 'Tiếng Việt'];
  static locales(): string[] { return LocalePolicy.LOCALES.slice(); }
  static preference(value: string): string {
    return value === 'system' || LocalePolicy.LOCALES.includes(value) ? value : 'system';
  }
  /** Exact saved choices; region/script variants are resolved only for requested resource languages. */
  private static resolve(value: string): string {
    const tag: string = value.trim().replace(/_/g, '-').toLowerCase();
    if (tag.length > 80 || !/^[a-z]{2,3}(?:-[a-z0-9]{1,8})*$/.test(tag)) { return ''; }
    const parts: string[] = tag.split('-');
    const language: string = parts[0];
    if (language === 'zh') {
      const script: string = parts.length > 1 && /^[a-z]{4}$/.test(parts[1]) ? parts[1] : '';
      if (script === 'hant') { return 'zh-Hant'; }
      if (script === 'hans') { return 'zh-Hans'; }
      if (script.length > 0) { return ''; }
      const region: string = parts.length > 1 ? parts[1] : '';
      return region === 'tw' || region === 'hk' || region === 'mo' ? 'zh-Hant' : 'zh-Hans';
    }
    return LocalePolicy.LOCALES.includes(language) ? language : '';
  }
  static resourceLocale(value: string): string { return LocalePolicy.resolve(value) || 'en'; }
  static supported(value: string): boolean { return LocalePolicy.resolve(value).length > 0; }
  static index(value: string): number { return LocalePolicy.LOCALES.indexOf(LocalePolicy.resourceLocale(value)); }
  static nativeName(value: string): string { return LocalePolicy.NAMES[LocalePolicy.index(value)]; }
}
