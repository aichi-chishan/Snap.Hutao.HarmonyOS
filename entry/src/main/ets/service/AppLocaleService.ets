import { i18n } from '@kit.LocalizationKit';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { LocalePolicy } from '../model/LocalePolicy';

/** Uses API9+ language lookup, no system-language changes or new permissions. */
export class AppLocaleService {
  static readonly KEY: string = 'app.help_locale';
  static preference(): string {
    try { return LocalePolicy.preference(PreferencesStore.getString(AppLocaleService.KEY, 'system')); }
    catch (_) { return 'system'; }
  }
  static requested(): string {
    const preference: string = AppLocaleService.preference();
    if (preference !== 'system') { return preference; }
    try { return i18n.System.getSystemLanguage(); } catch (_) { return 'en'; }
  }
  static current(): string { return LocalePolicy.resourceLocale(AppLocaleService.requested()); }
  static usingFallback(): boolean { return !LocalePolicy.supported(AppLocaleService.requested()); }
  static select(value: string): boolean {
    if (LocalePolicy.preference(value) !== value || !PreferencesStore.isReady()) { return false; }
    try {
      PreferencesStore.setString(AppLocaleService.KEY, value);
      const version: number = AppStorage.get<number>('helpLocaleVersion') ?? 0;
      AppStorage.setOrCreate('helpLocaleVersion', version + 1);
      return true;
    } catch (_) { return false; }
  }
}
