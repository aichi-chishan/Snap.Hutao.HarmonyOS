/**
 * HutaoDailyImageService.ets
 * 胡桃每日一图（对齐 Windows HutaoWallpaperClient.GetTodayWallpaperAsync）：
 * 公开无鉴权的壁纸接口，按来源和日期缓存图片及署名。
 */
import { fileIo } from '@kit.CoreFileKit';
import { ApiClient } from '../data/network/ApiClient';
import { Logger } from '../common/Logger';
import { MediaCacheService } from './MediaCacheService';

const TAG: string = 'HutaoDailyImage';
const WALLPAPER_ROOT: string = 'https://api.snaphutaorp.org/wallpaper/';

interface WallpaperAttribution {
  author: string;
  sourceUrl: string;
}

/** 当日一图结果 */
export class HutaoDailyImage {
  /** 本地文件路径（不含 file:// 前缀） */
  path: string = '';
  /** 图片作者（如 miHoYo） */
  author: string = '';
  /** 来源页 URL */
  sourceUrl: string = '';
  /** true=本次使用了当日已缓存文件（未发起网络请求） */
  fromCache: boolean = false;
}

export class HutaoDailyImageService {
  private static instance: HutaoDailyImageService = new HutaoDailyImageService();
  private inflight: Map<string, Promise<HutaoDailyImage | undefined>> =
    new Map<string, Promise<HutaoDailyImage | undefined>>();

  static getInstance(): HutaoDailyImageService {
    return HutaoDailyImageService.instance;
  }

  async getToday(source: string = 'hutao'): Promise<HutaoDailyImage | undefined> {
    const type: string = source === 'bing' || source === 'hoyoplay' ? source : 'hutao';
    const endpoint: string = type === 'hutao' ? 'today' : type;
    const date: Date = new Date();
    const day: string = `${date.getFullYear()}${String(date.getMonth() + 1).padStart(2, '0')}${String(date.getDate()).padStart(2, '0')}`;
    const name: string = `${type}_${day}.jpg`;
    const generation: number = MediaCacheService.generation();
    if (!MediaCacheService.isCurrent(generation)) { return undefined; }

    const key: string = `${generation}:${name}`;
    const pending: Promise<HutaoDailyImage | undefined> | undefined = this.inflight.get(key);
    if (pending !== undefined) { return pending; }
    const task: Promise<HutaoDailyImage | undefined> = this.loadToday(endpoint, name, generation);
    this.inflight.set(key, task);
    try {
      return await task;
    } finally {
      this.inflight.delete(key);
    }
  }

  private async loadToday(endpoint: string, name: string, generation: number): Promise<HutaoDailyImage | undefined> {
    try {
      const path: string = MediaCacheService.path('wallpaper', name);
      if (path.length === 0) { return undefined; }
      const out: HutaoDailyImage = new HutaoDailyImage();
      if (await MediaCacheService.hasFile(path)) {
        await this.readAttribution(path, out);
        if (!MediaCacheService.isCurrent(generation)) { return undefined; }
        out.path = path;
        out.fromCache = true;
        return out;
      }
      if (!MediaCacheService.isCurrent(generation)) { return undefined; }

      const resp = await ApiClient.getInstance().get(WALLPAPER_ROOT + endpoint, { 'Accept': 'application/json' });
      if (!resp.success || resp.data === undefined) {
        Logger.warn(TAG, `today api fail retcode=${resp.retcode}`);
        return undefined;
      }
      const data = resp.data as Record<string, Object>;
      const url: Object = data['url'];
      if (typeof url !== 'string' || !url.startsWith('https://')) {
        Logger.warn(TAG, 'today api empty url');
        return undefined;
      }
      out.author = String(data['author'] ?? '');
      out.sourceUrl = String(data['source_url'] ?? '');
      const attribution: WallpaperAttribution = { author: out.author, sourceUrl: out.sourceUrl };
      out.path = await MediaCacheService.fetchFile(url, 'wallpaper', name, generation, JSON.stringify(attribution));
      return out.path.length > 0 ? out : undefined;
    } catch (e) {
      Logger.warn(TAG, `getToday fail: ${(e as Error).message}`);
      return undefined;
    }
  }

  private async readAttribution(path: string, out: HutaoDailyImage): Promise<void> {
    const metadataPath: string = `${path}.json`;
    try {
      if (!await MediaCacheService.hasFile(metadataPath)) { return; }
      const attribution: WallpaperAttribution = JSON.parse(await fileIo.readText(metadataPath)) as WallpaperAttribution;
      if (typeof attribution.author === 'string') { out.author = attribution.author; }
      if (typeof attribution.sourceUrl === 'string') { out.sourceUrl = attribution.sourceUrl; }
    } catch (_) {
      // 旧版缓存只有图片，署名缺失时仍能离线显示该图。
    }
  }
}
