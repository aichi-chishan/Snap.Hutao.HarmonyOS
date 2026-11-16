/**
 * MetaIcon.ets
 * 元数据图标（优先级：远端更新图标 → 直接图片源(URL/file://) → rawfile 沙盒缓存 → 云端资源包缓存）。
 * 类别：AvatarIcon / EquipIcon / MonsterIcon / Skill / Talent / ItemIcon / AchievementIcon / IconElement。
 *
 * 注意：本项目构建下 $rawfile 动态模板路径不可用（见 NavIcon.ets 注释），
 * 因此 rawfile 图标通过 resourceManager.getRawFileContent 读入后落盘 cacheDir/rawicons/，
 * Image 以 file:// 引用；同一图标进程内缓存，避免重复读包。
 */
import { bundleManager } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { ResourcePackService } from '../data/remote/ResourcePackService';
import { StandardIconService } from '../data/remote/StandardIconService';
import { GameDataService } from '../service/GameDataService';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const META_TAG: string = 'MetaIcon';

/**
 * 进程内图标解析缓存：key = category/name → 沙盒路径；使用前确认文件仍在。
 * 有界 LRU：长会话翻图鉴/祈愿会累计上千条目，无上限的 Map 会持续占用内存。
 * 只淘汰「记住的路径」，磁盘缓存文件保留，重新访问时命中 accessSync 分支即可，不重复读包。
 */
const RAW_CACHE_LIMIT: number = 512;
const RAW_CACHE: Map<string, string> = new Map();

class RawIconLoad {
  owners: (() => boolean)[] = [];
  result: Promise<string> | undefined = undefined;
}

const RAW_PENDING: Map<string, RawIconLoad> = new Map();

/** 写入并维护 LRU 顺序（Map 迭代序 = 插入序，重设键即移到最新）。 */
function cachePut(key: string, path: string): void {
  if (RAW_CACHE.has(key)) {
    RAW_CACHE.delete(key);
  }
  RAW_CACHE.set(key, path);
  while (RAW_CACHE.size > RAW_CACHE_LIMIT) {
    const oldest: string | undefined = RAW_CACHE.keys().next().value;
    if (oldest === undefined) {
      break;
    }
    RAW_CACHE.delete(oldest);
  }
}

/** One immutable native Image request; source equality alone cannot identify retries. */
class MetaIconFrame {
  readonly id: number;
  readonly token: number;
  readonly source: string;
  readonly size: number;
  readonly circular: boolean;

  constructor(id: number, token: number, source: string, size: number, circular: boolean) {
    this.id = id;
    this.token = token;
    this.source = source;
    this.size = size;
    this.circular = circular;
  }
}

@Component
export struct MetaIcon {
  private static bundleKey: Promise<string> | undefined = undefined;
  /** 图标类别目录 */
  @Prop @Watch('onMetaChanged') category: string = 'ItemIcon';
  /** 图标名（不含扩展名，如 UI_AvatarIcon_Ayaka）；也兼容 http/file:// 完整源 */
  @Prop @Watch('onMetaChanged') name: string = '';
  /** 显示尺寸（vp） */
  @Prop @Watch('onRenderChanged') iconSize: number = 32;
  /** true 时按圆形裁剪（头像场景，objectFit Cover） */
  @Prop @Watch('onRenderChanged') circular: boolean = false;
  /** true 时 rawfile 缺失走云端资源包缓存通道 */
  @Prop @Watch('onMetaChanged') remoteFallback: boolean = false;
  /** 当前图源 */
  @State src: string = '';
  @State private frames: MetaIconFrame[] = [];
  private nextFrameId: number = 0;
  /** 异步解析令牌：name/category 变化后丢弃过期结果 */
  private resolveToken: number = 0;

  private attached: boolean = false;

  aboutToAppear(): void {
    this.attached = true;
    this.resolve();
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.resolveToken++;
  }

  /** @Prop 变化（切换角色/物品）时重新解析图源 */
  onMetaChanged(): void {
    this.resolve();
  }

  /** Resizing/reclipping owns a fresh Image node without rereading or downloading its source. */
  onRenderChanged(): void {
    if (this.attached) { this.publishSource(this.src); }
  }

  private publishSource(source: string): void {
    this.src = source;
    this.frames = source.length > 0 ? [new MetaIconFrame(++this.nextFrameId, this.resolveToken,
      source, this.iconSize, this.circular)] : [];
  }

  private onImageError(frame: MetaIconFrame): void {
    if (!this.attached || frame.token !== this.resolveToken || this.frames.length !== 1 ||
      this.frames[0].id !== frame.id) { return; }
    // A decode failure is a display failure, not permission to delete a user's URI or shared cache file.
    this.publishSource('');
  }

  resolve(): void {
    if (!this.attached) { return; }
    const token: number = ++this.resolveToken;
    this.publishSource('');
    if (this.name.length === 0) {
      return;
    }
    if (this.name.startsWith('https://') || this.name.startsWith('http://') || this.name.startsWith('file://')) {
      this.publishSource(this.name);
      return;
    }
    // Metadata names are path segments, never arbitrary relative filesystem paths.
    if (!/^[A-Za-z0-9_-]+$/.test(this.category) || !/^[A-Za-z0-9_-]+$/.test(this.name)) { return; }
    // 1) 远端更新图标优先（GitHub 数据更新后即用新版，未下载时不命中）
    try {
      const remote: string = GameDataService.getInstance().readIcon(this.category, this.name);
      if (remote.length > 0) {
        this.publishSource(remote);
        return;
      }
    } catch (e) {
      Logger.warn(META_TAG, `readIcon fail: ${(e as Error).message}`);
    }
    // 3) rawfile → 沙盒缓存文件
    this.loadRawfileCached(this.category, this.name, token).catch((e: Error) => {
      Logger.error(META_TAG, `loadRawfileCached rejected: ${e.message}`);
    });
  }

  private static installedBundle(): Promise<string> {
    if (MetaIcon.bundleKey === undefined) {
      MetaIcon.bundleKey = bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
        .then((info: bundleManager.BundleInfo): string => `${info.versionCode}-${info.updateTime}`)
        .catch((): string => `run-${Date.now()}`);
    }
    return MetaIcon.bundleKey;
  }

  private static async exists(path: string): Promise<boolean> {
    try { return await fileIo.access(path); } catch (_) { return false; }
  }

  private async loadRawfileCached(category: string, name: string, token: number): Promise<void> {
    const root: string = AppContextProvider.getCacheDir();
    const key: string = `${root}/${category}/${name}`;
    const current = (): boolean => this.attached && token === this.resolveToken;
    const path: string = await MetaIcon.rawPath(root, key, category, name, current);
    if (!current()) { return; }
    if (path.length > 0) {
      this.publishSource(fileUri.getUriFromPath(path));
    } else if (this.remoteFallback) {
      await this.tryRemote(category, name, key, token);
    }
  }

  private static rawPath(root: string, key: string, category: string, name: string,
    owner: () => boolean): Promise<string> {
    const pending: RawIconLoad | undefined = RAW_PENDING.get(key);
    if (pending?.result !== undefined) {
      pending.owners.push(owner);
      return pending.result;
    }
    const request: RawIconLoad = new RawIconLoad();
    request.owners.push(owner);
    RAW_PENDING.set(key, request);
    const wanted = (): boolean => {
      if (request.owners.some((isCurrent: () => boolean): boolean => isCurrent())) { return true; }
      if (RAW_PENDING.get(key) === request) { RAW_PENDING.delete(key); }
      return false;
    };
    const result: Promise<string> = MetaIcon.materializeRaw(root, key, category, name, wanted)
      .catch((error: Error): string => {
        Logger.warn(META_TAG, `rawfile ${category}/${name} fail: ${error.message}`);
        return '';
      }).finally(() => {
        if (RAW_PENDING.get(key) === request) { RAW_PENDING.delete(key); }
      });
    request.result = result;
    return result;
  }

  private static async materializeRaw(root: string, key: string, category: string, name: string,
    wanted: () => boolean): Promise<string> {
    const cached: string | undefined = RAW_CACHE.get(key);
    if (cached !== undefined && await MetaIcon.exists(cached)) {
      cachePut(key, cached);
      return cached;
    }
    if (RAW_CACHE.get(key) === cached) { RAW_CACHE.delete(key); }
    const bundle: string = await MetaIcon.installedBundle();
    const directory: string = `${root}/rawicons/${bundle}/${category}`;
    const dest: string = `${directory}/${name}.png`;
    if (await MetaIcon.exists(dest)) {
      cachePut(key, dest);
      return dest;
    }
    if (!wanted()) { return ''; }
    const bytes: Uint8Array = await AppContextProvider.getResourceManager().getRawFileContent(`icons/${category}/${name}.png`);
    if (!wanted()) { return ''; }
    try { await fileIo.mkdir(directory, true); }
    catch (error) { if (!(await fileIo.stat(directory)).isDirectory()) { throw error as Error; } }
    if (!wanted() || !await MetaIcon.writeCache(dest, bytes, wanted)) { return ''; }
    cachePut(key, dest);
    return dest;
  }

  /** Raw assets absent from the package may use a static CDN when the caller enables it. */
  private async tryRemote(category: string, name: string, key: string, token: number): Promise<void> {
    let found: string = await StandardIconService.ensure(category, name);
    if (!this.attached || token !== this.resolveToken || !this.remoteFallback) { return; }
    if (found.length === 0) { found = await ResourcePackService.ensure(category, name); }
    if (found.length > 0 && this.attached && token === this.resolveToken && this.remoteFallback) {
      if (!RAW_CACHE.has(key)) { cachePut(key, found); }
      this.publishSource(fileUri.getUriFromPath(found));
    }
  }

  /** Publish only a complete, closed write from an OS-unique staging directory. */
  private static async writeCache(dest: string, raw: Uint8Array, wanted: () => boolean): Promise<boolean> {
    const staging: string = await fileIo.mkdtemp(`${dest}.stage-XXXXXX`);
    try {
      if (!wanted()) { return false; }
      const temporary: string = `${staging}/image.png`;
      const file: fileIo.File = await fileIo.open(temporary,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.NOFOLLOW);
      try {
        if (!wanted()) { return false; }
        const buffer: ArrayBuffer = new Uint8Array(raw).buffer as ArrayBuffer;
        if (await fileIo.write(file.fd, buffer) !== buffer.byteLength) { throw new Error('Incomplete icon cache write'); }
      } finally { await fileIo.close(file); }
      if (!wanted()) { return false; }
      await fileIo.rename(temporary, dest);
      return true;
    } finally {
      try { await fileIo.rmdir(staging); } catch (_) { /* Cache cleanup is best effort. */ }
    }
  }

  build() {
    if (this.name.length > 0 && this.src !== '') {
      ForEach(this.frames, (frame: MetaIconFrame) => {
        Image(frame.source)
          .width(frame.size)
          .height(frame.size)
          .objectFit(frame.circular ? ImageFit.Cover : ImageFit.Contain)
          .borderRadius(frame.circular ? frame.size / 2 : 0)
          // ArkUI derives the decode size from layout/density and fit, preserving non-square sources.
          .autoResize(true)
          .draggable(false)
          .onError(() => { this.onImageError(frame); })
      }, (frame: MetaIconFrame) => `${frame.id}`)
    } else {
      // 缺图/加载中：中性半透明底板（勿用 page_background——深色主题下即纯黑，看起来像黑块）
      Column()
        .width(this.iconSize)
        .height(this.iconSize)
        .borderRadius(this.iconSize / 6)
        .backgroundColor($r('app.color.icon_placeholder'))
    }
  }
}
