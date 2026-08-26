/**
 * StandardIconService.ets
 * 标准游戏图标静态 CDN 兜底（对齐 Windows Uri.xaml / AvatarIconConverter 的
 * https://api.snaphutaorp.org/static/raw/{Category}/{Name}.png 规则）：
 * 用于本地 rawfile 缺失的标准图标（UI_ItemIcon_106 树脂、UI_MarkTower、UI_MarkQuest_* 等），
 * 下载后落盘 cacheDir/remote/{category}/{name}.png，与 ResourcePackService 共用目录。
 */
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { AppContextProvider } from '../../common/AppContext';
import { Logger } from '../../common/Logger';

const TAG: string = 'StandardIconService';
/** 静态图标基址（Windows 版胡桃启动器同源映射规则） */
const STATIC_BASE: string = 'https://api.snaphutaorp.org/static/raw/';

export class StandardIconService {
  private static cache: Map<string, string> = new Map();

  /** 本地是否已缓存 */
  static localPath(category: string, name: string): string {
    if (category.length === 0 || name.length === 0) {
      return '';
    }
    return `${AppContextProvider.getCacheDir()}/remote/${category}/${name}.png`;
  }

  /** 确保标准图标存在（已缓存则直接返回文件路径，否则按静态 CDN 规则下载，失败返回 ''） */
  static async ensure(category: string, name: string): Promise<string> {
    if (category.length === 0 || name.length === 0) {
      return '';
    }
    const key: string = `${category}/${name}`;
    const hit: string | undefined = StandardIconService.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const dest: string = StandardIconService.localPath(category, name);
    try {
      if (fileIo.accessSync(dest)) {
        StandardIconService.cache.set(key, dest);
        return dest;
      }
    } catch (e) {
      // 未缓存，继续
    }
    const dir: string = `${AppContextProvider.getCacheDir()}/remote/${category}`;
    try {
      try {
        fileIo.mkdirSync(dir);
      } catch (e) {
        // 已存在
      }
      const req = http.createHttp();
      try {
        const resp = await req.request(`${STATIC_BASE}${category}/${name}.png`, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 10000,
        });
        if (resp.responseCode !== http.ResponseCode.OK) {
          Logger.warn(TAG, `http ${resp.responseCode} for ${key}`);
          StandardIconService.cache.set(key, '');
          return '';
        }
        const file = fileIo.openSync(dest, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, resp.result as ArrayBuffer);
        } finally {
          fileIo.closeSync(file);
        }
        Logger.info(TAG, `downloaded ${key}`);
        StandardIconService.cache.set(key, dest);
        return dest;
      } finally {
        req.destroy();
      }
    } catch (e) {
      Logger.warn(TAG, `ensure ${key} fail: ${(e as Error).message}`);
      StandardIconService.cache.set(key, '');
      return '';
    }
  }
}
