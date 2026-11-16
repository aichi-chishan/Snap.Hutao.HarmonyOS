import { MediaCacheService } from './MediaCacheService';

/** 远程横幅图片缓存。保留本地路径接口，下载失败时返回空串。 */
export class CachedImageService {
  static async fetchToCache(url: string): Promise<string> {
    if (!url.startsWith('https://') && !url.startsWith('http://')) { return ''; }
    const generation: number = MediaCacheService.generation();
    const extension: RegExpMatchArray | null = url.split(/[?#]/)[0].match(/\.(?:jpe?g|png|gif|webp|bmp|svg|ico|tiff?|heic|heif|avif)$/i);
    try {
      const suffix: string = extension === null ? '' : extension[0].toLowerCase();
      const name: string = MediaCacheService.urlHash(url) + suffix;
      return await MediaCacheService.fetchFile(url, 'remoteimg', name, generation);
    } catch (_) {
      return '';
    }
  }
}
