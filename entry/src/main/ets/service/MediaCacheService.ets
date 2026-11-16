/**
 * MediaCacheService.ets
 * 媒体与图标缓存管理（设置→存储）：统计/清理沙盒 cacheDir 下的可再生缓存目录。
 * 目录为固定白名单（壁纸和官方视频/远程图片/CDN 图标/rawfile 落盘图标），
 * 清理后按需自动重建；符号链接一律跳过，绝不越出 cacheDir。
 */
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const TAG: string = 'MediaCacheService';

/** 可再生缓存白名单（cacheDir 相对目录；与各服务的落盘路径一一对应） */
const CACHE_ROOTS: string[] = ['wallpaper', 'remoteimg', 'remote', 'rawicons'];

export class MediaCacheService {
  private static revision: number = 0;
  private static clearTask: Promise<boolean> | undefined;
  private static downloads: Map<string, Promise<string>> = new Map<string, Promise<string>>();

  static generation(): number {
    return MediaCacheService.revision;
  }

  static isCurrent(generation: number): boolean {
    return generation === MediaCacheService.revision && MediaCacheService.clearTask === undefined;
  }

  static path(directory: 'wallpaper' | 'remoteimg', name: string): string {
    const base: string = AppContextProvider.getCacheDir();
    return base.length > 0 && /^[a-z0-9][a-z0-9_.-]*$/i.test(name) ? `${base}/${directory}/${name}` : '';
  }

  /** 完整 URL（包括查询参数）决定文件名。 */
  static urlHash(url: string): string {
    const digest: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: util.TextEncoder.create().encodeInto(url) });
    let hash: string = '';
    for (const byte of digest.digestSync().data) { hash += byte.toString(16).padStart(2, '0'); }
    return hash;
  }

  /** 路径可能已由系统或设置页清理，命中时仍检查磁盘。 */
  static async hasFile(path: string): Promise<boolean> {
    if (path.length === 0) { return false; }
    try {
      if (!await MediaCacheService.safeDirectory(path.substring(0, path.lastIndexOf('/')))) { return false; }
      const stat: fileIo.Stat = await fileIo.lstat(path);
      return stat.isFile() && !stat.isSymbolicLink() && stat.size > 0;
    } catch (_) {
      return false;
    }
  }

  static async fetchFile(url: string, directory: 'wallpaper' | 'remoteimg', name: string,
    generation: number, metadata: string = ''): Promise<string> {
    const path: string = MediaCacheService.path(directory, name);
    if (path.length === 0 || !MediaCacheService.isCurrent(generation)) { return ''; }
    const cached: boolean = await MediaCacheService.hasFile(path);
    if (!MediaCacheService.isCurrent(generation)) { return ''; }
    if (cached) { return path; }

    const key: string = `${generation}:${path}`;
    const pending: Promise<string> | undefined = MediaCacheService.downloads.get(key);
    if (pending !== undefined) { return pending; }
    const task: Promise<string> = MediaCacheService.download(url, path, generation, metadata);
    MediaCacheService.downloads.set(key, task);
    try {
      return await task;
    } finally {
      MediaCacheService.downloads.delete(key);
    }
  }

  private static async download(url: string, path: string, generation: number, metadata: string): Promise<string> {
    const directory: string = path.substring(0, path.lastIndexOf('/'));
    const staged: string = `${path}.${util.generateRandomUUID()}.part`;
    const stagedMetadata: string = `${staged}.json`;
    let prepared: boolean = false;
    try {
      try { await fileIo.mkdir(directory); } catch (error) {
        if ((error as BusinessError).code !== 13900015) { throw error as Error; }
      }
      if (!await MediaCacheService.safeDirectory(directory) || !MediaCacheService.isCurrent(generation)) { return ''; }
      prepared = true;

      const session: rcp.Session = rcp.createSession({
        requestConfiguration: { transfer: { timeout: { connectMs: 15000, inactivityMs: 30000 } } },
      });
      try {
        const target: rcp.DownloadToFile = { kind: 'file', file: staged };
        const response: rcp.Response = await session.downloadToFile(url, target);
        if (response.statusCode !== 200) { throw new Error(`HTTP ${response.statusCode}`); }
      } finally {
        session.close();
      }

      if (!await MediaCacheService.hasFile(staged) || !MediaCacheService.isCurrent(generation)) { return ''; }
      if (metadata.length > 0) {
        const bytes: Uint8Array = util.TextEncoder.create().encodeInto(metadata);
        const file: fileIo.File = await fileIo.open(stagedMetadata,
          fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.NOFOLLOW);
        try {
          if (await fileIo.write(file.fd, bytes.buffer as ArrayBuffer) !== bytes.byteLength) {
            throw new Error('Incomplete media metadata write');
          }
        } finally {
          await fileIo.close(file);
        }
      }
      if (!MediaCacheService.isCurrent(generation)) { return ''; }
      // 同一轮事件循环内发布，清理要么看到完整文件，要么使这次下载过期。
      if (metadata.length > 0) { fileIo.renameSync(stagedMetadata, `${path}.json`); }
      fileIo.renameSync(staged, path);
    } catch (error) {
      Logger.warn(TAG, `media download failed: ${(error as Error).message}`);
      return '';
    } finally {
      if (prepared) {
        // 成功发布后暂存路径已不存在。
        try { await fileIo.unlink(staged); } catch (_) { }
        if (metadata.length > 0) {
          try { await fileIo.unlink(stagedMetadata); } catch (_) { }
        }
      }
    }
    return MediaCacheService.isCurrent(generation) ? path : '';
  }

  /** 缓存根目录绝对路径（cacheDir 不存在时返回空数组） */
  private static roots(): string[] {
    const base: string = AppContextProvider.getCacheDir();
    if (base.length === 0) {
      return [];
    }
    const roots: string[] = [];
    for (const name of CACHE_ROOTS) {
      const root: string = `${base}/${name}`;
      roots.push(root);
    }
    return roots;
  }

  /** 仅接受真实目录（拒绝符号链接），对齐 StandardIconService 的目录校验 */
  private static async safeDirectory(path: string): Promise<boolean> {
    const stat: fileIo.Stat = await fileIo.lstat(path);
    return stat.isDirectory() && !stat.isSymbolicLink();
  }

  /** 递归求目录字节数；符号链接与不可读项跳过（缓存文件皆可再生，统计近似即可） */
  private static async sizeOf(path: string): Promise<number> {
    let total: number = 0;
    let names: string[] = [];
    try {
      if (!await MediaCacheService.safeDirectory(path)) { return 0; }
      names = await fileIo.listFile(path, { recursion: false, listNum: 0 });
    } catch (_) {
      return 0;
    }
    for (const name of names) {
      const full: string = `${path}/${name}`;
      try {
        const stat: fileIo.Stat = await fileIo.lstat(full);
        if (stat.isSymbolicLink()) {
          continue;
        }
        if (stat.isDirectory()) {
          total += await MediaCacheService.sizeOf(full);
        } else if (stat.isFile()) {
          total += stat.size;
        }
      } catch (_) { /* Raced or unreadable entry contributes nothing. */ }
    }
    return total;
  }

  /** 缓存总占用（字节；目录缺失按 0 计） */
  static async size(): Promise<number> {
    let total: number = 0;
    for (const root of MediaCacheService.roots()) {
      total += await MediaCacheService.sizeOf(root);
    }
    return total;
  }

  /** 字节数 → 可读文本（KB/MB，一位小数） */
  static formatSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }

  /** 逐文件清理并跳过链接；保留全部子目录，不使用递归 rmdir。 */
  private static async clearDirectory(path: string): Promise<boolean> {
    let allOk: boolean = true;
    let names: string[] = [];
    try {
      if (!await MediaCacheService.safeDirectory(path)) { return true; }
      names = await fileIo.listFile(path, { recursion: false, listNum: 0 });
    } catch (e) {
      if ((e as BusinessError).code === 13900002) { return true; }
      Logger.warn(TAG, `list cache failed: ${(e as BusinessError).code}`);
      return false;
    }
    for (const name of names) {
      const full: string = `${path}/${name}`;
      try {
        const stat: fileIo.Stat = await fileIo.lstat(full);
        if (stat.isSymbolicLink()) { continue; }
        if (stat.isDirectory()) {
          if (!await MediaCacheService.clearDirectory(full)) { allOk = false; }
        } else if (stat.isFile()) {
          await fileIo.unlink(full);
        }
      } catch (e) {
        // 系统或并发清理已经移除的文件也算清理完成。
        if ((e as BusinessError).code === 13900002) { continue; }
        allOk = false;
        Logger.warn(TAG, `clear cache failed: ${(e as BusinessError).code}`);
      }
    }
    return allOk;
  }

  private static async clearRoots(): Promise<boolean> {
    let allOk: boolean = true;
    for (const root of MediaCacheService.roots()) {
      if (!await MediaCacheService.clearDirectory(root)) { allOk = false; }
    }
    return allOk;
  }

  /** 清空白名单缓存目录内容，并使清理前发起的下载失效。 */
  static async clear(): Promise<boolean> {
    if (MediaCacheService.clearTask !== undefined) { return MediaCacheService.clearTask; }
    MediaCacheService.revision++;
    const task: Promise<boolean> = MediaCacheService.clearRoots();
    MediaCacheService.clearTask = task;
    try {
      return await task;
    } finally {
      MediaCacheService.clearTask = undefined;
      AppStorage.setOrCreate('mediaCacheVersion', MediaCacheService.revision);
    }
  }
}
