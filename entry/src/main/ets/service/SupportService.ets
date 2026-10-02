import { common, bundleManager } from '@kit.AbilityKit';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { AppContextProvider } from '../common/AppContext';
import { PreferencesStore } from '../data/prefs/PreferencesStore';

/** Explicit user actions only: an issue page and a minimal, account-free diagnostic summary. */
export class SupportService {
  static async openIssues(): Promise<void> {
    const context: common.UIAbilityContext = AppContextProvider.getAppContext() as common.UIAbilityContext;
    await context.openLink('https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/issues/new/choose');
  }

  static async copyDiagnostics(): Promise<void> {
    const app = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    const lines: string[] = [
      `Snap.Hutao.HarmonyOS ${app.versionName} (${app.versionCode})`,
      `System: ${deviceInfo.osFullName}`,
      `API: ${deviceInfo.sdkApiVersion}`,
      `Device type: ${deviceInfo.deviceType}`,
      `Theme: ${PreferencesStore.getThemeMode()}`,
      'Problem description:',
      'Steps to reproduce:',
      'Expected result:',
      'Actual result:',
    ];
    await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n')));
  }
}
