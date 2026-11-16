import { http } from '@kit.NetworkKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { AppRelease, AppUpdatePolicy, AppUpdateResult, UpdateCatalog, UpdateChannel, UpdateClient, UpdateStatus } from '../model/AppUpdate';
import { PreferencesStore } from '../data/prefs/PreferencesStore';

/** One caller-owned read-only release check. */
export class AppUpdateRequest {
  private cancelled: boolean = false;
  private handle: http.HttpRequest | undefined = undefined;
  private started: boolean = false;
  cancel(): void {
    this.cancelled = true;
    const handle: http.HttpRequest | undefined = this.handle; this.handle = undefined;
    if (handle !== undefined) { try { handle.destroy(); } catch (_) { /* Already stopped. */ } }
  }
  private result(status: UpdateStatus): AppUpdateResult {
    const result: AppUpdateResult = new AppUpdateResult(); result.status = status; result.checkedAt = Date.now(); return result;
  }
  async run(client: UpdateClient, channel: UpdateChannel): Promise<AppUpdateResult> {
    if (this.cancelled) { return this.result(UpdateStatus.Cancelled); }
    if (this.started) { return this.result(UpdateStatus.Cancelled); }
    this.started = true;
    const catalog: UpdateCatalog = new UpdateCatalog();
    catalog.complete = false;
    try {
      for (let page: number = 1; page <= AppUpdatePolicy.MAX_PAGES; page++) {
        if (this.cancelled) { return this.result(UpdateStatus.Cancelled); }
        const url: string = AppUpdatePolicy.requestUrl(page);
        if (!AppUpdatePolicy.allowsRequest(url)) { return this.result(UpdateStatus.InvalidResponse); }
        const handle: http.HttpRequest = http.createHttp(); this.handle = handle;
        let response: http.HttpResponse;
        try {
          response = await handle.request(url, {
            method: http.RequestMethod.GET,
            header: { 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'Snap.Hutao.HarmonyOS' },
            connectTimeout: 15000, readTimeout: 15000, expectDataType: http.HttpDataType.STRING,
            maxLimit: 2 * 1024 * 1024, maxRedirects: 0, usingCache: false
          });
        } finally {
          if (this.handle === handle) { this.handle = undefined; handle.destroy(); }
        }
        if (this.cancelled) { return this.result(UpdateStatus.Cancelled); }
        if (response.responseCode === 403 || response.responseCode === 429) { return this.result(UpdateStatus.RateLimited); }
        if (response.responseCode === 404) { return this.result(UpdateStatus.Unavailable); }
        if (response.responseCode !== 200 || typeof response.result !== 'string') { return this.result(UpdateStatus.InvalidResponse); }
        const parsed: UpdateCatalog | undefined = AppUpdatePolicy.parsePage(response.result as string);
        if (parsed === undefined) { return this.result(UpdateStatus.InvalidResponse); }
        catalog.releases = catalog.releases.concat(parsed.releases);
        catalog.drafts += parsed.drafts; catalog.invalid += parsed.invalid;
        if (parsed.complete) { catalog.complete = true; break; }
      }
      if (this.cancelled) { return this.result(UpdateStatus.Cancelled); }
      const result: AppUpdateResult = AppUpdatePolicy.evaluate(catalog, client, channel);
      result.checkedAt = Date.now(); return result;
    } catch (_) {
      return this.result(this.cancelled ? UpdateStatus.Cancelled : UpdateStatus.NetworkError);
    }
  }
}
export class AppUpdateService {
  private static readonly SKIPPED_KEY: string = 'app.update.skipped';
  private static startup?: Promise<AppUpdateResult>;

  static startupCheck(): Promise<AppUpdateResult> {
    if (AppUpdateService.startup === undefined) { AppUpdateService.startup = AppUpdateService.checkStableAtStartup(); }
    return AppUpdateService.startup;
  }

  private static async checkStableAtStartup(): Promise<AppUpdateResult> {
    const request: AppUpdateRequest = new AppUpdateRequest();
    let timer: number = -1;
    const deadline: Promise<AppUpdateResult> = new Promise<AppUpdateResult>((resolve) => {
      timer = setTimeout(() => {
        request.cancel();
        const result: AppUpdateResult = new AppUpdateResult();
        result.status = UpdateStatus.Cancelled;
        resolve(result);
      }, 3000);
    });
    try { return await Promise.race<AppUpdateResult>([request.run(AppUpdateService.readClient(), UpdateChannel.Stable), deadline]); }
    finally { clearTimeout(timer); }
  }

  static skippedTag(): string { return PreferencesStore.getString(AppUpdateService.SKIPPED_KEY, ''); }

  static setSkippedTag(tag: string): void {
    PreferencesStore.setString(AppUpdateService.SKIPPED_KEY, tag);
    AppStorage.setOrCreate<string>('appUpdateSkippedTag', tag);
  }

  static releaseForNotice(result: AppUpdateResult): AppRelease | undefined {
    return result.status === UpdateStatus.Newer ? result.release : undefined;
  }

  static readClient(): UpdateClient {
    const client: UpdateClient = new UpdateClient();
    try {
      const bundle: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      client.versionName = bundle.versionName; client.versionCode = bundle.versionCode; client.bundleName = bundle.name;
    } catch (_) { /* Unknown local identity must remain unknown. */ }
    try { client.api = deviceInfo.sdkApiVersion; } catch (_) { /* Unknown API cannot satisfy a minimum. */ }
    return client;
  }
  /** Explicit UI action only. API 12+, no API 26 capability and no installation permission. */
  static async openDetails(context: common.UIAbilityContext, url: string, tag: string): Promise<void> {
    if (!AppUpdatePolicy.allowsDetails(url, tag)) { throw new Error('Untrusted release destination'); }
    await context.openLink(url);
  }
  static async openProjectReleases(context: common.UIAbilityContext): Promise<void> {
    await context.openLink(AppUpdatePolicy.RELEASES_URL);
  }
}
