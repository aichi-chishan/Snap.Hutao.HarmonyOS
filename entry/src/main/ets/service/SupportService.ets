import { common, bundleManager } from '@kit.AbilityKit';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { AppContextProvider } from '../common/AppContext';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { CommonOutcomeId } from '../model/CommonOutcome';
import { DiagnosticEnvironment, DiagnosticPolicy, DiagnosticPreview } from '../model/DiagnosticPolicy';

/** Explicit user actions only: an issue page and a minimal, account-free diagnostic summary. */
export class SupportService {
  static async openIssues(): Promise<void> {
    const context: common.UIAbilityContext = AppContextProvider.getAppContext() as common.UIAbilityContext;
    await context.openLink('https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/issues/new/choose');
  }

  /** Explicit preview action only. Opening Help must never call this or inspect the environment. */
  static async previewDiagnostics(feature: string, outcome: CommonOutcomeId,
    includeEnvironment: boolean = false): Promise<DiagnosticPreview> {
    const preview: DiagnosticPreview = new DiagnosticPreview();
    preview.feature = feature; preview.outcome = outcome; preview.generatedAt = Date.now();
    if (includeEnvironment) {
      const environment: DiagnosticEnvironment = new DiagnosticEnvironment();
      try {
        const app: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
        environment.appVersion = app.versionName;
      } catch (_) { /* Unavailable optional data stays explicitly unknown. */ }
      try { environment.api = deviceInfo.sdkApiVersion; environment.deviceType = deviceInfo.deviceType; } catch (_) { /* optional */ }
      try { environment.theme = PreferencesStore.getThemeMode(); } catch (_) { /* optional */ }
      preview.environment = environment;
    }
    return DiagnosticPolicy.sanitize(preview);
  }

  /** Copy a detached and re-sanitized preview, never caller-provided raw text. No upload or clipboard read. */
  static async copyDiagnosticPreview(preview: DiagnosticPreview): Promise<void> {
    const text: string = DiagnosticPolicy.serialize(preview);
    await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
  }

  /** Compatibility for the existing explicit Settings action; new UI should preview before calling copy. */
  static async copyDiagnostics(): Promise<void> {
    await SupportService.copyDiagnosticPreview(await SupportService.previewDiagnostics('privacy', CommonOutcomeId.None, true));
  }
}
