/**
 * WikiService.ets
 * 图鉴数据：genshin.jmp.blue 社区数据 API（公开、无胡桃云依赖、无登录）。
 * - /characters 角色列表（slug 数组）
 * - /characters/{slug} 角色详情
 * - /weapons 武器列表（slug 数组）
 * - /weapons/{slug} 武器详情
 * jmp.blue 返回裸 JSON（非 mihoyo 包装），直接用 http 请求解析。
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../common/AppContext';
import { AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'WikiService';
const BASE: string = 'https://genshin.jmp.blue';
/** 在线接口缓存有效期（2 小时）：减少重复请求 + 断网可回退缓存 */
const CACHE_TTL_MS: number = 2 * 60 * 60 * 1000;

/** 角色详情 */
export class WikiAvatarDetail {
  slug: string = '';
  name: string = '';
  title: string = '';
  /** 元素（Pyro 等） */
  vision: string = '';
  /** 武器类型（POLEARM 等） */
  weaponType: string = '';
  rarity: number = 0;
  nation: string = '';
  description: string = '';
}

/** 武器详情 */
export class WikiWeaponDetail {
  slug: string = '';
  name: string = '';
  type: string = '';
  rarity: number = 0;
  baseAttack: number = 0;
  subStat: string = '';
  passiveName: string = '';
  passiveDesc: string = '';
  description: string = '';
}

/** 怪物详情 */
export class WikiEnemyDetail {
  slug: string = '';
  name: string = '';
  type: string = '';
  family: string = '';
  faction: string = '';
  /** 元素标签（数组） */
  elements: string[] = [];
  region: string = '';
  description: string = '';
}

export class WikiService {
  private static instance: WikiService = new WikiService();

  static getInstance(): WikiService {
    return WikiService.instance;
  }

  /** 角色列表（slug 数组） */
  async fetchCharacterList(): Promise<string[]> {
    const text: string = await WikiService.getText(`${BASE}/characters`);
    const arr = JSON.parse(text) as Array<Object>;
    const slugs: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      slugs.push(String(arr[i]));
    }
    return slugs;
  }

  /** 角色详情 */
  async fetchCharacterDetail(slug: string): Promise<WikiAvatarDetail> {
    const text: string = await WikiService.getText(`${BASE}/characters/${slug}`);
    const o = JSON.parse(text) as Record<string, Object>;
    const d: WikiAvatarDetail = new WikiAvatarDetail();
    d.slug = WikiService.str(o['id']);
    d.name = WikiService.str(o['name']);
    d.title = WikiService.str(o['title']);
    d.vision = WikiService.str(o['vision']);
    d.weaponType = WikiService.str(o['weapon_type']);
    d.rarity = WikiService.num(o['rarity']);
    d.nation = WikiService.str(o['nation']);
    d.description = WikiService.str(o['description']);
    return d;
  }

  /** 武器列表（slug 数组） */
  async fetchWeaponList(): Promise<string[]> {
    const text: string = await WikiService.getText(`${BASE}/weapons`);
    const arr = JSON.parse(text) as Array<Object>;
    const slugs: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      slugs.push(String(arr[i]));
    }
    return slugs;
  }

  /** 武器详情 */
  async fetchWeaponDetail(slug: string): Promise<WikiWeaponDetail> {
    const text: string = await WikiService.getText(`${BASE}/weapons/${slug}`);
    const o = JSON.parse(text) as Record<string, Object>;
    const d: WikiWeaponDetail = new WikiWeaponDetail();
    d.slug = WikiService.str(o['id']);
    d.name = WikiService.str(o['name']);
    d.type = WikiService.str(o['type']);
    d.rarity = WikiService.num(o['rarity']);
    d.baseAttack = WikiService.num(o['baseAttack']);
    d.subStat = WikiService.str(o['subStat']);
    d.passiveName = WikiService.str(o['passiveName']);
    d.passiveDesc = WikiService.str(o['passiveDesc']);
    d.description = WikiService.str(o['description']);
    return d;
  }

  /** 怪物列表（slug 数组） */
  async fetchEnemyList(): Promise<string[]> {
    const text: string = await WikiService.getText(`${BASE}/enemies`);
    const arr = JSON.parse(text) as Array<Object>;
    const slugs: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      slugs.push(String(arr[i]));
    }
    return slugs;
  }

  /** 怪物详情 */
  async fetchEnemyDetail(slug: string): Promise<WikiEnemyDetail> {
    const text: string = await WikiService.getText(`${BASE}/enemies/${slug}`);
    const o = JSON.parse(text) as Record<string, Object>;
    const d: WikiEnemyDetail = new WikiEnemyDetail();
    d.slug = WikiService.str(o['id']);
    d.name = WikiService.str(o['name']);
    d.type = WikiService.str(o['type']);
    d.family = WikiService.str(o['family']);
    d.faction = WikiService.str(o['faction']);
    d.region = WikiService.str(o['region']);
    d.description = WikiService.str(o['description']);
    const elements = o['elements'] as Array<Object>;
    if (elements !== undefined && elements !== null) {
      for (let i = 0; i < elements.length; i++) {
        d.elements.push(WikiService.str(elements[i]));
      }
    }
    return d;
  }

  /** GET 原始文本（带 2h 缓存：命中缓存直接返回；网络失败回退缓存） */
  private static async getText(url: string): Promise<string> {
    const cached: string = WikiService.readCache(url);
    if (cached.length > 0) {
      return cached;
    }
    try {
      const text: string = await WikiService.httpGet(url);
      WikiService.writeCache(url, text);
      return text;
    } catch (e) {
      // 网络失败：尝试回退过期缓存（无则抛错）
      const stale: string = WikiService.readCache(url, -1);
      if (stale.length > 0) {
        Logger.warn(TAG, `network fail, fallback stale cache url=${url}`);
        return stale;
      }
      throw new Error(`网络异常：${(e as Error).message}`);
    }
  }

  /** http.get 原始实现（无缓存逻辑） */
  private static async httpGet(url: string): Promise<string> {
    const httpRequest = http.createHttp();
    try {
      const resp = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: AppConstants.NETWORK_TIMEOUT_MS,
        readTimeout: AppConstants.NETWORK_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      });
      if (resp.responseCode === http.ResponseCode.OK) {
        return resp.result as string;
      }
      Logger.warn(TAG, `http ${resp.responseCode} url=${url}`);
      throw new Error(`HTTP ${resp.responseCode}`);
    } catch (e) {
      const err = e as BusinessError;
      Logger.warn(TAG, `request error url=${url} msg=${err.message}`);
      throw new Error(`网络异常：${err.message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  /** 缓存目录：cacheDir/wiki/{url 编码}.json */
  private static cachePath(url: string): string {
    return `${AppContextProvider.getCacheDir()}/wiki/${WikiService.sanitizeName(url)}.json`;
  }

  /** URL 安全化为文件名（换 / 为 _） */
  private static sanitizeName(url: string): string {
    let out: string = '';
    for (let i = 0; i < url.length; i++) {
      const c: string = url.charAt(i);
      out += (c === '/' || c === '?' || c === '=' || c === '&' || c === '#') ? '_' : c;
    }
    return out;
  }

  /** 读缓存；ttlMs<0 表示不过期（用于网络失败回退） */
  private static readCache(url: string, ttlMs: number = CACHE_TTL_MS): string {
    const p: string = WikiService.cachePath(url);
    try {
      const st: fileIo.Stat = fileIo.statSync(p);
      if (ttlMs >= 0 && Date.now() - st.mtime > ttlMs) {
        return '';
      }
      const f = fileIo.openSync(p, fileIo.OpenMode.READ_ONLY);
      try {
        const buf: ArrayBuffer = new ArrayBuffer(st.size);
        fileIo.readSync(f.fd, buf);
        return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      } finally {
        fileIo.closeSync(f);
      }
    } catch (e) {
      return '';
    }
  }

  /** 写缓存（幂等） */
  private static writeCache(url: string, text: string): void {
    try {
      const dir: string = `${AppContextProvider.getCacheDir()}/wiki`;
      try {
        fileIo.mkdirSync(dir);
      } catch (e) {
        // 已存在
      }
      const p: string = WikiService.cachePath(url);
      const f = fileIo.openSync(p, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(f.fd, util.TextEncoder.create().encodeInto(text));
      } finally {
        fileIo.closeSync(f);
      }
    } catch (e) {
      Logger.warn(TAG, `write cache fail url=${url}`);
    }
  }

  private static num(v: Object, def: number = 0): number {
    if (v === undefined || v === null) {
      return def;
    }
    const n: number = Number(v);
    return Number.isNaN(n) ? def : n;
  }

  private static str(v: Object): string {
    if (v === undefined || v === null) {
      return '';
    }
    return String(v);
  }
}
