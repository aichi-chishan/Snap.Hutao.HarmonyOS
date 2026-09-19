/**
 * CachedImageService.ets
 * 远程图片 → 沙盒缓存（cacheDir/remoteimg/），供 Image(file://) 渲染：
 * - 命中缓存直接返回本地路径，不发请求
 * - 并发去重（同 URL 只下载一次，等待中的调用共享结果）
 * - 失败返回空串，调用方回退不渲染（对齐 Windows CachedImage 行为）
 */
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const TAG: string = 'CachedImageService';

export class CachedImageService {
  /** 下载中去重：url → 进行中的 Promise */
  private static inflight: Map<string, Promise<string>> = new Map();

  /** 本地缓存路径（url 安全化命名）；不校验文件是否存在 */
  private static cachePath(url: string): string {
    let name: string = '';
    for (let i = 0; i < url.length; i++) {
      const c: string = url.charAt(i);
      name += (c === '/' || c === '?' || c === '=' || c === '&' || c === ':' || c === '#') ? '_' : c;
    }
    // URL 过长时保留尾部（米游社 CDN 图名唯一性在尾部）
    if (name.length > 120) {
      name = name.substring(name.length - 120);
    }
    return `${AppContextProvider.getCacheDir()}/remoteimg/${name}`;
  }

  /**
   * 取图片本地路径：已缓存直接返回；否则下载后返回；失败返回 ''。
   * 返回路径不含 file:// 前缀（调用方自行拼接或直接交 Image）。
   */
  static async fetchToCache(url: string): Promise<string> {
    if (url.length === 0) {
      return '';
    }
    const dest: string = CachedImageService.cachePath(url);
    try {
      if (fileIo.accessSync(dest)) {
        return dest;
      }
    } catch (e) {
      // accessSync 不存在时抛错，继续下载
    }
    const pending: Promise<string> | undefined = CachedImageService.inflight.get(url);
    if (pending !== undefined) {
      return pending;
    }
    const task: Promise<string> = CachedImageService.download(url, dest);
    CachedImageService.inflight.set(url, task);
    return task;
  }

  private static async download(url: string, dest: string): Promise<string> {
    const req = http.createHttp();
    try {
      const img = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      if (img.responseCode !== http.ResponseCode.OK) {
        Logger.warn(TAG, `http ${img.responseCode} url=${url}`);
        return '';
      }
      const dir: string = dest.substring(0, dest.lastIndexOf('/'));
      try {
        fileIo.mkdirSync(dir);
      } catch (e) {
        // 已存在
      }
      const file = fileIo.openSync(dest, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, img.result as ArrayBuffer);
      } finally {
        fileIo.closeSync(file);
      }
      return dest;
    } catch (e) {
      Logger.warn(TAG, `download fail url=${url} msg=${(e as Error).message}`);
      return '';
    } finally {
      req.destroy();
      CachedImageService.inflight.delete(url);
    }
  }
}
