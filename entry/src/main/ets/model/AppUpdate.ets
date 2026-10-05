/** Pure public-release policy. A version comparison is never an installation or signature verdict. */
export enum UpdateChannel { Stable = 'stable', Preview = 'preview' }
export enum UpdateStatus {
  Idle = 'idle', Checking = 'checking', Newer = 'newer', Equal = 'equal', LocalNewer = 'local-newer',
  Unknown = 'unknown', NoRelease = 'no-release', NoChannelRelease = 'no-channel-release',
  NetworkError = 'network-error', Unavailable = 'unavailable', RateLimited = 'rate-limited',
  InvalidResponse = 'invalid-response', Cancelled = 'cancelled'
}
export class AppVersion {
  core: string[] = [];
  prerelease: string[] = [];
}
export class UpdateClient {
  versionName: string = '';
  versionCode: number = 0;
  bundleName: string = '';
  api: number = 0;
}
export class ReleaseManifest {
  versionCode: number = 0;
  minimumApi: number = 0;
}
export class AppRelease {
  tag: string = '';
  name: string = '';
  notes: string = '';
  url: string = '';
  prerelease: boolean = false;
  harmonyAssetCount: number = 0;
  manifest: ReleaseManifest | undefined = undefined;
  manifestState: string = 'missing';
}
export class UpdateCatalog {
  releases: AppRelease[] = [];
  drafts: number = 0;
  invalid: number = 0;
  complete: boolean = true;
}
export class AppUpdateResult {
  status: UpdateStatus = UpdateStatus.Idle;
  release: AppRelease | undefined = undefined;
  checkedAt: number = 0;
  complete: boolean = true;
  unknownVersions: number = 0;
  /** unknown / requires-newer-api / api-requirement-met. Never claims overall compatibility. */
  apiState: string = 'unknown';
  metadataConflict: boolean = false;
  /** No configured, authenticated Harmony distribution exists; always false. */
  installable: boolean = false;
}
export class AppUpdatePolicy {
  static readonly REPOSITORY: string = 'aichi-chishan/Snap.Hutao.HarmonyOS';
  static readonly RELEASES_URL: string = 'https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/releases';
  static readonly API_ROOT: string = 'https://api.github.com/repos/aichi-chishan/Snap.Hutao.HarmonyOS/releases';
  static readonly BUNDLE_NAME: string = 'com.example.snaphutaoharmonyos';
  static readonly PAGE_SIZE: number = 100;
  static readonly MAX_PAGES: number = 3;

  static parseVersion(input: string): AppVersion | undefined {
    if (input.length === 0 || input.length > 160 || input !== input.trim()) { return undefined; }
    const match: RegExpMatchArray | null = input.match(/^[vV]?((?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){0,3})(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/);
    if (match === null) { return undefined; }
    const version: AppVersion = new AppVersion();
    version.core = match[1].split('.');
    version.prerelease = match[2] === undefined ? [] : match[2].split('.');
    if (version.prerelease.some((part: string) => /^[0-9]+$/.test(part) && part.length > 1 && part[0] === '0')) { return undefined; }
    return version;
  }
  private static numeric(a: string, b: string): number {
    return a.length === b.length ? (a === b ? 0 : a > b ? 1 : -1) : a.length > b.length ? 1 : -1;
  }
  /** Numeric components are compared as decimal strings, avoiding floating-point overflow. */
  static compare(a: string, b: string): number | undefined {
    const left: AppVersion | undefined = AppUpdatePolicy.parseVersion(a);
    const right: AppVersion | undefined = AppUpdatePolicy.parseVersion(b);
    if (left === undefined || right === undefined) { return undefined; }
    for (let i: number = 0; i < Math.max(left.core.length, right.core.length); i++) {
      const value: number = AppUpdatePolicy.numeric(left.core[i] === undefined ? '0' : left.core[i], right.core[i] === undefined ? '0' : right.core[i]);
      if (value !== 0) { return value; }
    }
    if (left.prerelease.length === 0 || right.prerelease.length === 0) {
      return left.prerelease.length === right.prerelease.length ? 0 : left.prerelease.length === 0 ? 1 : -1;
    }
    for (let i: number = 0; i < Math.max(left.prerelease.length, right.prerelease.length); i++) {
      const l: string | undefined = left.prerelease[i];
      const r: string | undefined = right.prerelease[i];
      if (l === undefined || r === undefined) { return l === undefined ? -1 : 1; }
      if (l === r) { continue; }
      const ln: boolean = /^[0-9]+$/.test(l);
      const rn: boolean = /^[0-9]+$/.test(r);
      return ln && rn ? AppUpdatePolicy.numeric(l, r) : ln !== rn ? (ln ? -1 : 1) : l > r ? 1 : -1;
    }
    return 0;
  }
  static requestUrl(page: number): string {
    return Number.isInteger(page) && page >= 1 && page <= AppUpdatePolicy.MAX_PAGES
      ? `${AppUpdatePolicy.API_ROOT}?per_page=100&page=${page}` : '';
  }
  static allowsRequest(url: string): boolean {
    for (let page: number = 1; page <= AppUpdatePolicy.MAX_PAGES; page++) {
      if (url === AppUpdatePolicy.requestUrl(page)) { return true; }
    }
    return false;
  }
  static releaseUrl(tag: string): string {
    return tag.length > 0 && tag.length <= 160 && !/[\s\x00-\x1f\x7f]/.test(tag)
      ? `${AppUpdatePolicy.RELEASES_URL}/tag/${encodeURIComponent(tag)}` : '';
  }
  static allowsDetails(url: string, tag: string): boolean {
    return url.length > 0 && url === AppUpdatePolicy.releaseUrl(tag);
  }
  private static record(value: Object | undefined): Record<string, Object> | undefined {
    return value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)
      ? value as Record<string, Object> : undefined;
  }
  private static text(record: Record<string, Object>, key: string, limit: number): string {
    const value: Object | undefined = record[key];
    return typeof value === 'string' ? (value as string).slice(0, limit) : '';
  }
  /** Optional source-authenticated JSON metadata in a release body, NOT a package-signature trust root. */
  private static manifest(body: string, release: AppRelease): void {
    const marker: string = '<!-- hutao-harmony-update:v1';
    const first: number = body.indexOf(marker);
    if (first < 0) { return; }
    release.manifestState = 'invalid';
    if (first !== body.lastIndexOf(marker)) { return; }
    const end: number = body.indexOf('-->', first + marker.length);
    if (end < 0 || end - first > 8192) { return; }
    try {
      const data: Record<string, Object> | undefined = AppUpdatePolicy.record(JSON.parse(body.slice(first + marker.length, end)) as Object);
      if (data === undefined || data['schema'] !== 1 || data['bundleName'] !== AppUpdatePolicy.BUNDLE_NAME ||
        data['tagName'] !== release.tag || typeof data['versionName'] !== 'string' ||
        AppUpdatePolicy.compare(data['versionName'] as string, release.tag) !== 0 ||
        data['channel'] !== (release.prerelease ? UpdateChannel.Preview : UpdateChannel.Stable)) { return; }
      const code: Object | undefined = data['versionCode'];
      const api: Object | undefined = data['minimumApi'];
      if (typeof code !== 'number' || !Number.isSafeInteger(code) || (code as number) < 1 ||
        typeof api !== 'number' || !Number.isSafeInteger(api) || (api as number) < 1 || (api as number) > 10000) { return; }
      const manifest: ReleaseManifest = new ReleaseManifest();
      manifest.versionCode = code as number; manifest.minimumApi = api as number;
      release.manifest = manifest; release.manifestState = 'project-metadata';
    } catch (_) { /* Invalid metadata never grants compatibility, installation or API eligibility. */ }
  }
  static parsePage(body: string): UpdateCatalog | undefined {
    if (body.length > 2 * 1024 * 1024) { return undefined; }
    let parsed: Object;
    try { parsed = JSON.parse(body) as Object; } catch (_) { return undefined; }
    if (!Array.isArray(parsed) || parsed.length > AppUpdatePolicy.PAGE_SIZE) { return undefined; }
    const catalog: UpdateCatalog = new UpdateCatalog();
    catalog.complete = parsed.length < AppUpdatePolicy.PAGE_SIZE;
    for (const value of parsed as Object[]) {
      const row: Record<string, Object> | undefined = AppUpdatePolicy.record(value);
      if (row === undefined || typeof row['draft'] !== 'boolean') { catalog.invalid++; continue; }
      if (row['draft'] === true) { catalog.drafts++; continue; }
      if (typeof row['prerelease'] !== 'boolean' || typeof row['tag_name'] !== 'string' ||
        (row['tag_name'] as string).length > 160) { catalog.invalid++; continue; }
      const release: AppRelease = new AppRelease();
      release.tag = AppUpdatePolicy.text(row, 'tag_name', 160);
      release.url = AppUpdatePolicy.text(row, 'html_url', 2048);
      if (!AppUpdatePolicy.allowsDetails(release.url, release.tag)) { catalog.invalid++; continue; }
      release.name = AppUpdatePolicy.text(row, 'name', 160) || release.tag;
      const version: AppVersion | undefined = AppUpdatePolicy.parseVersion(release.tag);
      release.prerelease = row['prerelease'] === true || (version !== undefined && version.prerelease.length > 0);
      const bodyText: string = AppUpdatePolicy.text(row, 'body', 100000);
      AppUpdatePolicy.manifest(bodyText, release);
      release.notes = bodyText.replace(/<!-- hutao-harmony-update:v1[\s\S]*?-->/g, '').slice(0, 8000);
      const assets: Object | undefined = row['assets'];
      if (Array.isArray(assets)) {
        for (const item of (assets as Object[]).slice(0, 100)) {
          const asset: Record<string, Object> | undefined = AppUpdatePolicy.record(item);
          if (asset === undefined) { continue; }
          const name: string = AppUpdatePolicy.text(asset, 'name', 200);
          const url: string = AppUpdatePolicy.text(asset, 'browser_download_url', 2048);
          if (/^[A-Za-z0-9][A-Za-z0-9_.-]{0,180}\.(hap|app)$/i.test(name) &&
            url === `${AppUpdatePolicy.RELEASES_URL}/download/${encodeURIComponent(release.tag)}/${encodeURIComponent(name)}` &&
            typeof asset['size'] === 'number' && Number.isSafeInteger(asset['size']) && (asset['size'] as number) > 0) { release.harmonyAssetCount++; }
        }
      }
      catalog.releases.push(release);
    }
    return catalog;
  }
  static evaluate(catalog: UpdateCatalog, client: UpdateClient, channel: UpdateChannel): AppUpdateResult {
    const result: AppUpdateResult = new AppUpdateResult();
    result.complete = catalog.complete; result.unknownVersions = catalog.invalid;
    let selected: AppRelease | undefined = undefined;
    let candidates: number = 0;
    for (const release of catalog.releases) {
      if (channel === UpdateChannel.Stable && release.prerelease) { continue; }
      candidates++;
      if (AppUpdatePolicy.parseVersion(release.tag) === undefined) { result.unknownVersions++; continue; }
      const relation: number | undefined = selected === undefined ? 1 : AppUpdatePolicy.compare(release.tag, selected.tag);
      if (selected === undefined || relation === 1 || (relation === 0 && release.manifest !== undefined &&
        (selected.manifest === undefined || release.manifest.versionCode > selected.manifest.versionCode))) { selected = release; }
    }
    if (selected === undefined) {
      result.status = result.unknownVersions > 0 || !catalog.complete ? UpdateStatus.Unknown : candidates > 0
        ? UpdateStatus.Unknown : catalog.releases.length > 0 ? UpdateStatus.NoChannelRelease : UpdateStatus.NoRelease;
      return result;
    }
    result.release = selected;
    let comparison: number | undefined = AppUpdatePolicy.compare(selected.tag, client.versionName);
    if (selected.manifest !== undefined && client.bundleName === AppUpdatePolicy.BUNDLE_NAME) {
      if (Number.isSafeInteger(client.api) && client.api > 0) {
        result.apiState = client.api < selected.manifest.minimumApi ? 'requires-newer-api' : 'api-requirement-met';
      }
      if (Number.isSafeInteger(client.versionCode) && client.versionCode > 0) {
        const byCode: number = selected.manifest.versionCode === client.versionCode ? 0 : selected.manifest.versionCode > client.versionCode ? 1 : -1;
        // Different core/prerelease direction cannot be reconciled by silently trusting an arbitrary code.
        if (comparison !== undefined && comparison !== 0 && comparison !== byCode) {
          result.metadataConflict = true; comparison = undefined;
        } else { comparison = byCode; }
      }
    }
    result.status = comparison === undefined ? UpdateStatus.Unknown : comparison > 0 ? UpdateStatus.Newer
      : !catalog.complete || result.unknownVersions > 0 ? UpdateStatus.Unknown
      : comparison === 0 ? UpdateStatus.Equal : UpdateStatus.LocalNewer;
    return result;
  }
}
