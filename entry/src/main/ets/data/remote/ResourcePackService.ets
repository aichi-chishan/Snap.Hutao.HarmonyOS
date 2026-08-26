/**
 * ResourcePackService.ets
 * 云端资源包二次下载（可维护）：大图（角色立绘/名片/时装等，单张 >100KB，不宜打包进安装包）。
 * 数据源：由用户自己在 GitHub 仓库维护的 resource_manifest.json + 静态资源目录。
 * 默认 URL 指向占位仓库（可在设置页修改）。条目结构：
 *   { "category": "GachaAvatarImg", "name": "UI_Gacha_AvatarImg_Ayaka", "url": ".../GachaAvatarImg/UI_Gacha_AvatarImg_Ayaka.png" }
 * 下载后落盘 cacheDir/remote/{category}/{name}.png，供 MetaIcon(remote=true) 引用；已存在则直接引用。
 * 兼容胡桃云静态 CDN 规则；用户上传 GitHub 后仅需更新 manifest 的 url。
 */
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../../common/AppContext';
import { PreferencesStore } from '../prefs/PreferencesStore';
import { Logger } from '../../common/Logger';

const TAG: string = 'ResourcePackService';
/** 铁拳默认清单 URL（上传大图扩展包后替换 OWNER；设置页可改） */
const DEFAULT_MANIFEST = 'https://raw.githubusercontent.com/OWNER/snap-hutao-data/main/resource_manifest.json';

/** 资源条目 */
export class RemoteResourceItem {
  category: string = '';
  name: string = '';
  url: string = '';
}

/** 清单 */
export class RemoteResourceManifest {
  version: number = 0;
  resources: RemoteResourceItem[] = [];
}

export class ResourcePackService {
  private static manifestUrl: string = PreferencesStore.getString('remote_manifest_url', DEFAULT_MANIFEST);

  /** 根目录 */
  private static root(): string {
    return `${AppContextProvider.getCacheDir()}/remote`;
  }

  /** 更新清单 URL */
  static setManifestUrl(url: string): void {
    ResourcePackService.manifestUrl = url;
    PreferencesStore.setString('remote_manifest_url', url);
  }

  static getManifestUrl(): string {
    return ResourcePackService.manifestUrl;
  }

  /** 拉取清单（缓存 5 分钟） */
  static async fetchManifest(): Promise<RemoteResourceManifest> {
    const resp = await ResourcePackService.httpGetString(ResourcePackService.manifestUrl);
    const root = JSON.parse(resp) as Record<string, Object>;
    const manifest: RemoteResourceManifest = new RemoteResourceManifest();
    manifest.version = Number(root['version'] ?? 0);
    const arr = (root['resources'] as Object[]) ?? [];
    for (const r of arr) {
      const o = r as Record<string, Object>;
      const item: RemoteResourceItem = new RemoteResourceItem();
      item.category = String(o['category'] ?? '');
      item.name = String(o['name'] ?? '');
      item.url = String(o['url'] ?? '');
      manifest.resources.push(item);
    }
    Logger.info(TAG, `manifest: ${manifest.resources.length} items`);
    return manifest;
  }

  /** 是否已下载某资源（本地命中则返回文件路径） */
  static localPath(category: string, name: string): string {
    const p = `${ResourcePackService.root()}/${category}/${name}.png`;
    try {
      fileIo.accessSync(p);
      return p;
    } catch (e) {
      return '';
    }
  }

  /** 下载单个资源（幂等：已存在跳过） */
  static async download(category: string, name: string, url: string): Promise<string> {
    const hit = ResourcePackService.localPath(category, name);
    if (hit.length > 0) {
      return hit;
    }
    const dir = `${ResourcePackService.root()}/${category}`;
    try {
      fileIo.mkdirSync(dir);
    } catch (e) {
      // 已存在
    }
    const dest = `${dir}/${name}.png`;
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 20000,
      });
      if (resp.responseCode !== http.ResponseCode.OK) {
        throw new Error(`http ${resp.responseCode}`);
      }
      const file = fileIo.openSync(dest, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, resp.result as ArrayBuffer);
      } finally {
        fileIo.closeSync(file);
      }
      Logger.info(TAG, `downloaded ${category}/${name}`);
      return dest;
    } finally {
      req.destroy();
    }
  }

  /** 下载整个清单（进度回调按条目返回） */
  static async downloadAll(onProgress: (done: number, total: number, name: string) => void): Promise<number> {
    const manifest = await ResourcePackService.fetchManifest();
    let done = 0;
    for (const item of manifest.resources) {
      try {
        await ResourcePackService.download(item.category, item.name, item.url);
      } catch (e) {
        Logger.warn(TAG, `download ${item.name} fail: ${(e as Error).message}`);
      }
      done += 1;
      if (onProgress !== undefined) {
        onProgress(done, manifest.resources.length, item.name);
      }
    }
    return done;
  }

  /** metaIcon 用：若本地无资源且清单含该条目则尝试下载 */
  static async ensure(category: string, name: string): Promise<string> {
    const hit = ResourcePackService.localPath(category, name);
    if (hit.length > 0) {
      return hit;
    }
    try {
      const manifest = await ResourcePackService.fetchManifest();
      for (const item of manifest.resources) {
        if (item.category === category && item.name === name) {
          return await ResourcePackService.download(category, name, item.url);
        }
      }
    } catch (e) {
      Logger.warn(TAG, `ensure ${category}/${name} fail`);
    }
    return '';
  }

  private static async httpGetString(url: string): Promise<string> {
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
      });
      if (resp.responseCode !== http.ResponseCode.OK) {
        throw new Error(`http ${resp.responseCode}`);
      }
      return resp.result as string;
    } finally {
      req.destroy();
    }
  }
}
