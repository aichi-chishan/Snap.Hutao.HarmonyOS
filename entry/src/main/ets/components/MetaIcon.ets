/**
 * MetaIcon.ets
 * 元数据图标（优先级：远端更新图标 → 直接图片源(URL/file://) → rawfile 沙盒缓存 → 云端资源包缓存）。
 * 类别：AvatarIcon / EquipIcon / MonsterIcon / Skill / Talent / ItemIcon / AchievementIcon / IconElement。
 *
 * 注意：本项目构建下 $rawfile 动态模板路径不可用（见 NavIcon.ets 注释），
 * 因此 rawfile 图标通过 resourceManager.getRawFileContent 读入后落盘 cacheDir/rawicons/，
 * Image 以 file:// 引用；同一图标进程内缓存，避免重复读包。
 */
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { ResourcePackService } from '../data/remote/ResourcePackService';
import { StandardIconService } from '../data/remote/StandardIconService';
import { GameDataService } from '../service/GameDataService';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const META_TAG: string = 'MetaIcon';

/** 进程内图标解析缓存：key = category/name → 沙盒路径；使用前确认文件仍在。 */
const RAW_CACHE: Map<string, string> = new Map();

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

  /** 逐级创建目录（fileIo.mkdirSync 非递归；父目录缺失时避免 openSync 失败） */
  private static async ensureDirChain(full: string): Promise<void> {
    try {
      fileIo.mkdirSync(full);
      return;
    } catch (e) {
      // 已存在或父目录缺失：逐级创建
    }
    const segs: string[] = full.split('/');
    let cur: string = full.startsWith('/') ? '/' : '';
    for (let i = 0; i < segs.length; i++) {
      if (segs[i].length === 0) {
        continue;
      }
      cur += (cur.length > 0 && !cur.endsWith('/') ? '/' : '') + segs[i];
      try {
        fileIo.mkdirSync(cur);
      } catch (e) {
        // 已存在则忽略
      }
    }
  }

  /** rawfile 读入并缓存（幂等，按需单张）；进程内命中直接复用 */
  private async loadRawfileCached(category: string, name: string, token: number): Promise<void> {
    const key: string = `${category}/${name}`;
    const cached: string | undefined = RAW_CACHE.get(key);
    if (cached !== undefined) {
      try {
        if (fileIo.accessSync(cached)) {
          if (this.attached && token === this.resolveToken) { this.publishSource(fileUri.getUriFromPath(cached)); }
          return;
        }
      } catch (_) { /* Evicted cache entries are retried below. */ }
      RAW_CACHE.delete(key);
    }
    const dir: string = `${AppContextProvider.getCacheDir()}/rawicons/${category}`;
    const dest: string = `${dir}/${name}.png`;
    try {
      if (fileIo.accessSync(dest)) {
        RAW_CACHE.set(key, dest);
        if (this.attached && token === this.resolveToken) {
          this.publishSource(fileUri.getUriFromPath(dest));
        }
        return;
      }
    } catch (e) {
      // 未缓存，继续
    }
    try {
      const rm = AppContextProvider.getResourceManager();
      const raw: Uint8Array = await rm.getRawFileContent(`icons/${category}/${name}.png`);
      if (!this.attached || token !== this.resolveToken) { return; }
      await MetaIcon.ensureDirChain(dir);
      if (!this.attached || token !== this.resolveToken) { return; }
      MetaIcon.writeCache(dest, raw);
      const src: string = fileUri.getUriFromPath(dest);
      RAW_CACHE.set(key, dest);
      if (this.attached && token === this.resolveToken) {
        this.publishSource(src);
      }
    } catch (e) {
      Logger.warn(META_TAG, `rawfile ${category}/${name} fail: ${(e as Error).message}`);
      if (this.attached && token === this.resolveToken) {
        this.publishSource('');
      }
      if (this.remoteFallback) {
        this.tryRemote(category, name, token).catch((error: Error) => {
            Logger.warn(META_TAG, `remote icon failed: ${error.message}`);
          });
      }
    }
  }

/** rawfile 缺失时从远端拉取（幂等）：标准图标静态 CDN 优先，云端资源包清单次之 */
  private async tryRemote(category: string, name: string, token: number): Promise<void> {
    if (!this.attached || token !== this.resolveToken || !this.remoteFallback || name.length === 0) {
      return;
    }
    let found: string = await StandardIconService.ensure(category, name);
    if (!this.attached || token !== this.resolveToken || !this.remoteFallback) { return; }
    if (found.length === 0) {
      found = await ResourcePackService.ensure(category, name);
    }
    if (found.length > 0) {
      const src: string = fileUri.getUriFromPath(found);
      RAW_CACHE.set(`${category}/${name}`, found);
      if (this.attached && token === this.resolveToken) {
        this.publishSource(src);
      }
    }
  }

  /** Publish only a complete, closed write from an OS-unique staging directory. */
  private static writeCache(dest: string, raw: Uint8Array): void {
    const staging: string = fileIo.mkdtempSync(`${dest}.stage-XXXXXX`);
    const temporary: string = `${staging}/image.png`;
    try {
      const file = fileIo.openSync(temporary, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      try {
        const buffer: ArrayBuffer = new Uint8Array(raw).buffer as ArrayBuffer;
        if (fileIo.writeSync(file.fd, buffer) !== buffer.byteLength) { throw new Error('Incomplete icon cache write'); }
      } finally { fileIo.closeSync(file); }
      fileIo.renameSync(temporary, dest);
    } finally {
      // The OS returned this directory to this operation; never remove the shared cache parent.
      try { fileIo.rmdirSync(staging); } catch (_) { /* Cache cleanup is best effort. */ }
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
      Column()
        .width(this.iconSize)
        .height(this.iconSize)
        .borderRadius(this.iconSize / 6)
        .backgroundColor($r('app.color.page_background'))
    }
  }
}
