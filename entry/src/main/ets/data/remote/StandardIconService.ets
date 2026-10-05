/**
 * Public PNG icon fallback. Returns an absolute sandbox path (callers use fileUri).
 * In-flight requests are coalesced; missing/transient failures are never cached forever.
 */
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { AppContextProvider } from '../../common/AppContext';
import { Logger } from '../../common/Logger';

const TAG: string = 'StandardIconService';
const STATIC_BASE: string = 'https://api.snaphutaorp.org/static/raw/';
const STATIC_REDIRECT_BASE: string = 'https://static.snaphutaorp.org/static/raw/';

export class StandardIconService {
  static readonly MAX_BYTES: number = 8 * 1024 * 1024;
  private static readonly MIN_BYTES: number = 45;
  private static readonly PNG_SIGNATURE: number[] = [137, 80, 78, 71, 13, 10, 26, 10];
  private static pending: Map<string, Promise<string>> = new Map<string, Promise<string>>();

  private static validSegment(value: string): boolean {
    return value.length > 0 && value.length <= 251 && /^[A-Za-z0-9_-]+$/.test(value);
  }

  static localPath(category: string, name: string): string {
    if (!StandardIconService.validSegment(category) || !StandardIconService.validSegment(name)) { return ''; }
    return `${AppContextProvider.getCacheDir()}/remote/${category}/${name}.png`;
  }

  /** Preserve existing local aliases; only IconElement uses the upstream intrinsic names. */
  private static sourceName(category: string, name: string): string {
    if (category !== 'IconElement') { return name; }
    switch (name) {
      case 'UI_Icon_Element_Anemo': return 'UI_Icon_Element_Wind';
      case 'UI_Icon_Element_Cryo': return 'UI_Icon_Element_Ice';
      case 'UI_Icon_Element_Dendro': return 'UI_Icon_Element_Grass';
      case 'UI_Icon_Element_Electro': return 'UI_Icon_Element_Electric';
      case 'UI_Icon_Element_Geo': return 'UI_Icon_Element_Rock';
      case 'UI_Icon_Element_Hydro': return 'UI_Icon_Element_Water';
      case 'UI_Icon_Element_Pyro': return 'UI_Icon_Element_Fire';
      default: return name;
    }
  }

  /** One active request per destination, released on both success and failure. */
  static async ensure(category: string, name: string): Promise<string> {
    if (!StandardIconService.validSegment(category) || !StandardIconService.validSegment(name)) { return ''; }
    let destination: string = '';
    try { destination = StandardIconService.localPath(category, name); }
    catch (_) { return ''; }
    const existing: Promise<string> | undefined = StandardIconService.pending.get(destination);
    if (existing !== undefined) { return existing; }
    const task: Promise<string> = StandardIconService.materialize(category, name, destination).catch((): string => {
      Logger.warn(TAG, 'icon unavailable; a later request can retry');
      return '';
    });
    StandardIconService.pending.set(destination, task);
    try { return await task; }
    finally {
      if (StandardIconService.pending.get(destination) === task) { StandardIconService.pending.delete(destination); }
    }
  }

  private static requireDirectory(directory: string): void {
    const stat: fileIo.Stat = fileIo.lstatSync(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink()) { throw new Error('Unsafe icon cache directory'); }
  }

  private static ensureDirectory(directory: string): void {
    try { fileIo.mkdirSync(directory); }
    catch (_) { StandardIconService.requireDirectory(directory); }
    StandardIconService.requireDirectory(directory);
  }

  private static prepareDirectory(category: string): string {
    const root: string = AppContextProvider.getCacheDir();
    StandardIconService.requireDirectory(root);
    StandardIconService.ensureDirectory(`${root}/remote`);
    const directory: string = `${root}/remote/${category}`;
    StandardIconService.ensureDirectory(directory);
    return directory;
  }

  private static hasPngSignature(bytes: Uint8Array): boolean {
    if (bytes.byteLength < StandardIconService.PNG_SIGNATURE.length) { return false; }
    for (let index: number = 0; index < StandardIconService.PNG_SIGNATURE.length; index++) {
      if (bytes[index] !== StandardIconService.PNG_SIGNATURE[index]) { return false; }
    }
    return true;
  }

  /** Revalidate even previously successful paths: the OS can evict files in cacheDir. */
  private static cached(destination: string): boolean {
    try {
      const stat: fileIo.Stat = fileIo.lstatSync(destination);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size < StandardIconService.MIN_BYTES ||
        stat.size > StandardIconService.MAX_BYTES) { return false; }
      const file: fileIo.File = fileIo.openSync(destination, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NOFOLLOW);
      try {
        const header: ArrayBuffer = new ArrayBuffer(StandardIconService.PNG_SIGNATURE.length);
        return fileIo.readSync(file.fd, header) === header.byteLength &&
          StandardIconService.hasPngSignature(new Uint8Array(header));
      } finally { fileIo.closeSync(file); }
    } catch (_) { return false; }
  }

  private static isRedirect(status: number): boolean {
    return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
  }

  /** Exact comparison excludes credentials, ports, query/fragment, changed paths and other hosts. */
  private static checkedRedirect(response: http.HttpResponse, expected: string): string {
    const headers: Record<string, Object> = response.header as Record<string, Object>;
    if (headers === undefined || headers === null || typeof headers !== 'object' || Array.isArray(headers)) {
      throw new Error('Missing icon redirect headers');
    }
    let location: string = '';
    let count: number = 0;
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === 'location') {
        count++;
        if (typeof headers[key] !== 'string') { throw new Error('Invalid icon redirect location'); }
        location = headers[key] as string;
      }
    }
    if (count !== 1 || location !== expected) { throw new Error('Untrusted icon redirect'); }
    return location;
  }

  /** Never enable automatic redirects: every hop retains the same size and timeout limits. */
  private static async requestIcon(url: string): Promise<http.HttpResponse> {
    const request: http.HttpRequest = http.createHttp();
    try {
      return await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 20000,
        maxLimit: StandardIconService.MAX_BYTES,
        maxRedirects: 0,
        usingCache: false,
      });
    } finally { request.destroy(); }
  }

  private static async materialize(category: string, name: string, destination: string): Promise<string> {
    StandardIconService.prepareDirectory(category);
    if (StandardIconService.cached(destination)) { return destination; }
    const relative: string = `${category}/${StandardIconService.sourceName(category, name)}.png`;
    let response: http.HttpResponse = await StandardIconService.requestIcon(`${STATIC_BASE}${relative}`);
    if (StandardIconService.isRedirect(response.responseCode)) {
      const target: string = StandardIconService.checkedRedirect(response, `${STATIC_REDIRECT_BASE}${relative}`);
      response = await StandardIconService.requestIcon(target);
    }
    // A redirect on the second request is rejected here; a loop can never add a third hop.
    if (response.responseCode !== http.ResponseCode.OK || !(response.result instanceof ArrayBuffer)) {
      throw new Error('Invalid icon response');
    }
    const bytes: Uint8Array = new Uint8Array(response.result as ArrayBuffer);
    // This is a bounded signature/size guard, not a full PNG decoder.
    if (bytes.byteLength < StandardIconService.MIN_BYTES || bytes.byteLength > StandardIconService.MAX_BYTES ||
      !StandardIconService.hasPngSignature(bytes)) { throw new Error('Invalid PNG icon'); }
    // Recheck directories after the asynchronous request before creating any temporary output.
    const directory: string = StandardIconService.prepareDirectory(category);
    if (!StandardIconService.cached(destination)) { StandardIconService.publish(directory, destination, bytes); }
    return destination;
  }

  /** API9 mkdtemp/rename/write: only this invocation's unique staging directory is ever removed. */
  private static publish(directory: string, destination: string, bytes: Uint8Array): void {
    const temporary: string = fileIo.mkdtempSync(`${directory}/.standard-icon-XXXXXX`);
    try {
      const staged: string = `${temporary}/image.png`;
      const file: fileIo.File = fileIo.openSync(staged,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.NOFOLLOW);
      try {
        const payload: ArrayBuffer = new Uint8Array(bytes).buffer as ArrayBuffer;
        if (fileIo.writeSync(file.fd, payload) !== payload.byteLength) { throw new Error('Incomplete icon write'); }
        fileIo.fsyncSync(file.fd);
      } finally { fileIo.closeSync(file); }
      // Same-filesystem rename publishes only a fully written file, never a partially truncated target.
      fileIo.renameSync(staged, destination);
    } finally {
      try { fileIo.rmdirSync(temporary); }
      catch (_) { Logger.warn(TAG, 'owned icon staging cleanup deferred'); }
    }
  }
}
