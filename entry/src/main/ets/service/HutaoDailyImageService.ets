/**
 * HutaoDailyImageService.ets
 * 胡桃每日一图（对齐 Windows HutaoWallpaperClient.GetTodayWallpaperAsync）：
 * GET https://api.snaphutaorp.org/wallpaper/today（公开无鉴权，返回 {url, source_url, author, uploader}），
 * 下载图片落盘 cacheDir/wallpaper/hutao_daily_{yyyyMMdd}.jpg，当天内复用不重复请求。
 * 图片作者署名（author/source_url）保留，供设置页展示。
 */
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { ApiClient } from '../data/network/ApiClient';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const TAG: string = 'HutaoDailyImage';
const TODAY_URL: string = 'https://api.snaphutaorp.org/wallpaper/today';

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

  static getInstance(): HutaoDailyImageService {
    return HutaoDailyImageService.instance;
  }

  /** 当日缓存文件路径（按日期滚动，跨天自动换新图） */
  private static todayPath(): string {
    const d = new Date();
    const day: string = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
    return `${AppContextProvider.getCacheDir()}/wallpaper/hutao_daily_${day}.jpg`;
  }

  /**
   * 获取今日一图：当日文件已存在直接复用；否则请求接口下载。
   * 失败返回 undefined（调用方回退主题纯色底，与 none 一致）。
   */
  async getToday(): Promise<HutaoDailyImage | undefined> {
    const dest: string = HutaoDailyImageService.todayPath();
    const dir: string = dest.substring(0, dest.lastIndexOf('/'));
    try {
      try {
        fileIo.mkdirSync(dir);
      } catch (e) {
        // 已存在
      }
      const out: HutaoDailyImage = new HutaoDailyImage();
      out.path = dest;
      if (fileIo.accessSync(dest)) {
        out.fromCache = true;
        return out;
      }
      // 1) 接口取图片 URL 与署名
      const resp = await ApiClient.getInstance().get(TODAY_URL, { 'Accept': 'application/json' });
      if (!resp.success || resp.data === undefined) {
        Logger.warn(TAG, `today api fail retcode=${resp.retcode}`);
        return undefined;
      }
      const data = resp.data as Record<string, Object>;
      const url: string = String(data['url'] ?? '');
      out.author = String(data['author'] ?? '');
      out.sourceUrl = String(data['source_url'] ?? '');
      if (url.length === 0) {
        Logger.warn(TAG, 'today api empty url');
        return undefined;
      }
      // 2) 下载图片
      const req = http.createHttp();
      try {
        const img = await req.request(url, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 15000,
          readTimeout: 30000,
        });
        if (img.responseCode !== http.ResponseCode.OK) {
          Logger.warn(TAG, `image http ${img.responseCode}`);
          return undefined;
        }
        const file = fileIo.openSync(dest, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, img.result as ArrayBuffer);
        } finally {
          fileIo.closeSync(file);
        }
        Logger.info(TAG, `daily image saved ${dest} (${out.author})`);
        return out;
      } finally {
        req.destroy();
      }
    } catch (e) {
      Logger.warn(TAG, `getToday fail: ${(e as Error).message}`);
      return undefined;
    }
  }
}
