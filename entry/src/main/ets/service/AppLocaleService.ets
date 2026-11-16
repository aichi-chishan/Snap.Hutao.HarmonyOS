import { i18n } from '@kit.LocalizationKit';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { LocalePolicy } from '../model/LocalePolicy';

class AppLocaleState {
  preference: string;
  requested: string;
  locale: string;
  apiLanguage: string;
  fallback: boolean;
  followsSystem: boolean;

  constructor(preference: string, requested: string, followsSystem: boolean) {
    this.preference = preference;
    this.requested = requested;
    this.locale = LocalePolicy.resourceLocale(requested);
    this.apiLanguage = LocalePolicy.apiLanguageCode(requested);
    this.fallback = !LocalePolicy.supported(requested);
    this.followsSystem = followsSystem;
  }
}

/** One effective-language snapshot shared by native resources, metadata and API requests. */
export class AppLocaleService {
  static readonly KEY: string = 'app.help_locale';
  private static initialized: boolean = false;
  private static cached: AppLocaleState | undefined = undefined;

  /** Call after PreferencesStore is ready and before mounting the application's pages. */
  static initialize(): void {
    if (AppLocaleService.initialized) { return; }
    if (!PreferencesStore.isReady()) {
      AppLocaleService.cached = AppLocaleService.cached ?? AppLocaleService.nativeState('system');
      return;
    }
    const preference: string = AppLocaleService.readPreference();
    if (preference === 'system') {
      AppLocaleService.cached = new AppLocaleState(preference, AppLocaleService.systemLocale(), true);
    } else {
      const native: AppLocaleState = AppLocaleService.nativeState(preference);
      try {
        AppLocaleService.applyNativeLanguage(preference);
        AppLocaleService.cached = new AppLocaleState(preference, preference, false);
      } catch (_) { AppLocaleService.cached = native; }
    }
    AppLocaleService.initialized = true;
  }

  private static state(): AppLocaleState {
    if (AppLocaleService.cached === undefined) { AppLocaleService.initialize(); }
    return AppLocaleService.cached as AppLocaleState;
  }

  private static readPreference(): string {
    try { return LocalePolicy.preference(PreferencesStore.getString(AppLocaleService.KEY, 'system')); }
    catch (_) { return 'system'; }
  }

  private static systemLocale(fallback: string = 'en'): string {
    try { return i18n.System.getSystemLocaleInstance().toString(); } catch (_) {}
    try { return i18n.System.getSystemLanguage(); } catch (_) { return fallback; }
  }

  private static nativeState(preference: string): AppLocaleState {
    try {
      const language: string = i18n.System.getAppPreferredLanguage();
      if (language !== '' && language !== 'default') { return new AppLocaleState(preference, language, false); }
    } catch (_) {}
    return new AppLocaleState(preference, AppLocaleService.systemLocale(), true);
  }

  static preference(): string { return AppLocaleService.state().preference; }
  static requested(): string { return AppLocaleService.state().requested; }
  static current(): string { return AppLocaleService.state().locale; }
  static usingFallback(): boolean { return AppLocaleService.state().fallback; }
  static apiLanguageCode(): string { return AppLocaleService.state().apiLanguage; }
  static restartRequired(): boolean {
    const state: AppLocaleState = AppLocaleService.state();
    return state.preference === 'system' && !state.followsSystem;
  }

  /** The native `default` reset applies on cold start; retain the active language until then. */
  private static acceptPreference(preference: string, previous: AppLocaleState): void {
    AppLocaleService.cached = preference === 'system'
      ? new AppLocaleState(preference, previous.followsSystem ? AppLocaleService.systemLocale(previous.requested) : previous.requested,
        previous.followsSystem)
      : new AppLocaleState(preference, preference, false);
    AppLocaleService.initialized = true;
    AppLocaleService.publishChange();
  }

  /** Re-read only after the backup transaction has committed its preferences. */
  static applyCurrentPreference(): boolean {
    if (!PreferencesStore.isReady()) { return false; }
    const preference: string = AppLocaleService.readPreference();
    const previous: AppLocaleState = AppLocaleService.cached ?? AppLocaleService.nativeState(preference);
    try {
      AppLocaleService.applyNativeLanguage(preference);
      AppLocaleService.acceptPreference(preference, previous);
      return true;
    } catch (_) {
      AppLocaleService.cached = new AppLocaleState(preference, previous.requested, previous.followsSystem);
      AppLocaleService.initialized = true;
      return false;
    }
  }

  static select(value: string): boolean {
    if (LocalePolicy.preference(value) !== value || !PreferencesStore.isReady()) { return false; }
    AppLocaleService.initialize();
    const previous: AppLocaleState = AppLocaleService.state();
    // Persist first: a failed preference write must not leave native resources on another language.
    try { PreferencesStore.setString(AppLocaleService.KEY, value); } catch (_) { return false; }
    try {
      AppLocaleService.applyNativeLanguage(value);
    } catch (_) {
      try { PreferencesStore.setString(AppLocaleService.KEY, previous.preference); } catch (_) {}
      return false;
    }
    AppLocaleService.acceptPreference(value, previous);
    return true;
  }

  /** A configuration notification rechecks the full culture tag; ordinary lookups never call native APIs. */
  static onConfigurationUpdate(language?: string): boolean {
    const previous: AppLocaleState | undefined = AppLocaleService.cached;
    if (previous === undefined || !previous.followsSystem || language === undefined || language.length === 0) { return false; }
    const next: AppLocaleState = new AppLocaleState(previous.preference, AppLocaleService.systemLocale(language), true);
    AppLocaleService.cached = next;
    const previousTag: string = previous.requested.replace(/_/g, '-').toLowerCase();
    const nextTag: string = next.requested.replace(/_/g, '-').toLowerCase();
    if (nextTag === previousTag && next.locale === previous.locale && next.fallback === previous.fallback) { return false; }
    AppLocaleService.publishChange();
    return true;
  }

  private static applyNativeLanguage(value: string): void {
    i18n.System.setAppPreferredLanguage(value === 'system' ? 'default' : value);
  }

  private static publishChange(): void {
    const version: number = AppStorage.get<number>('helpLocaleVersion') ?? 0;
    AppStorage.setOrCreate<number>('helpLocaleVersion', version + 1);
  }
}
