/**
 * MetaIcon.ets
 * 元数据图标（优先级：远端更新图标 → 直接图片源(URL/file://) → rawfile 沙盒缓存 → 云端资源包缓存）。
 * 类别：AvatarIcon / EquipIcon / MonsterIcon / Skill / Talent / ItemIcon / AchievementIcon / IconElement。
 *
 * 注意：本项目构建下 $rawfile 动态模板路径不可用（见 NavIcon.ets 注释），
 * 因此 rawfile 图标通过 resourceManager.getRawFileContent 读入后落盘 cacheDir/rawicons/，
 * Image 以 file:// 引用；同一图标进程内缓存，避免重复读包。
 */
import { fileIo } from '@kit.CoreFileKit';
import { ResourcePackService } from '../data/remote/ResourcePackService';
import { StandardIconService } from '../data/remote/StandardIconService';
import { GameDataService } from '../service/GameDataService';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const META_TAG: string = 'MetaIcon';

/** 进程内图标解析缓存：key = category/name → file:// 路径（'' 表示已知缺失，避免反复读包） */
const RAW_CACHE: Map<string, string> = new Map();

@Component
export struct MetaIcon {
  /** 图标类别目录 */
  @Prop @Watch('onMetaChanged') category: string = 'ItemIcon';
  /** 图标名（不含扩展名，如 UI_AvatarIcon_Ayaka）；也兼容 http/file:// 完整源 */
  @Prop @Watch('onMetaChanged') name: string = '';
  /** 显示尺寸（vp） */
  @Prop iconSize: number = 32;
  /** true 时按圆形裁剪（头像场景，objectFit Cover） */
  @Prop circular: boolean = false;
  /** true 时 rawfile 缺失走云端资源包缓存通道 */
  @Prop remoteFallback: boolean = false;
  /** 当前图源 */
  @State src: string = '';
  /** 异步解析令牌：name/category 变化后丢弃过期结果 */
  private resolveToken: number = 0;

  aboutToAppear(): void {
    this.resolve();
  }

  /** @Prop 变化（切换角色/物品）时重新解析图源 */
  onMetaChanged(): void {
    this.resolve();
  }

  resolve(): void {
    const token: number = ++this.resolveToken;
    if (this.name.length === 0) {
      Logger.info(META_TAG, `resolve skip: name empty`);
      this.src = '';
      return;
    }
    Logger.info(META_TAG, `resolve begin category=${this.category} name=${this.name}`);
    // 1) 远端更新图标优先（GitHub 数据更新后即用新版，未下载时不命中）
    try {
      const remote: string = GameDataService.getInstance().readIcon(this.category, this.name);
      Logger.info(META_TAG, `readIcon -> '${remote}'`);
      if (remote.length > 0) {
        this.src = remote;
        return;
      }
    } catch (e) {
      Logger.warn(META_TAG, `readIcon fail: ${(e as Error).message}`);
    }
    // 2) 直接图片源（http/file:// 透传，供 side_icon URL 等使用）
    if (this.name.startsWith('http') || this.name.startsWith('file://')) {
      this.src = this.name;
      return;
    }
    // 3) rawfile → 沙盒缓存文件
    Logger.info(META_TAG, `resolve -> loadRawfileCached`);
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
    let cur: string = '';
    for (let i = 0; i < segs.length; i++) {
      if (segs[i].length === 0) {
        continue;
      }
      cur += (cur.length > 0 ? '/' : '') + segs[i];
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
      Logger.info(META_TAG, `cache hit ${key} -> '${cached}'`);
      if (token === this.resolveToken) {
        this.src = cached;
        if (cached.length === 0 && this.remoteFallback) {
          this.tryRemote(category, name, token);
        }
      }
      return;
    }
    const dir: string = `${AppContextProvider.getCacheDir()}/rawicons/${category}`;
    const dest: string = `${dir}/${name}.png`;
    Logger.info(META_TAG, `cache miss ${key}; dest=${dest}`);
    try {
      if (fileIo.accessSync(dest)) {
        Logger.info(META_TAG, `dest exists ${dest}`);
        RAW_CACHE.set(key, `file://${dest}`);
        if (token === this.resolveToken) {
          this.src = `file://${dest}`;
        }
        return;
      }
    } catch (e) {
      Logger.info(META_TAG, `accessSync miss ${key}: ${(e as Error).message}`);
      // 未缓存，继续
    }
    try {
      const rm = AppContextProvider.getResourceManager();
      Logger.info(META_TAG, `reading rawfile icons/${category}/${name}.png...`);
      const raw: Uint8Array = await rm.getRawFileContent(`icons/${category}/${name}.png`);
      Logger.info(META_TAG, `rawfile read ok bytes=${raw.byteLength}`);
      await MetaIcon.ensureDirChain(dir);
      const file = fileIo.openSync(dest, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, raw.buffer as ArrayBuffer);
      } finally {
        fileIo.closeSync(file);
      }
      const src: string = `file://${dest}`;
      RAW_CACHE.set(key, src);
      Logger.info(META_TAG, `rawfile cached ${key} -> ${dest}`);
      if (token === this.resolveToken) {
        this.src = src;
      }
    } catch (e) {
      Logger.warn(META_TAG, `rawfile ${category}/${name} fail: ${(e as Error).message}`);
      RAW_CACHE.set(key, '');
      if (token === this.resolveToken) {
        this.src = '';
      }
      if (this.remoteFallback) {
        this.tryRemote(category, name, token);
      }
    }
  }

/** rawfile 缺失时从远端拉取（幂等）：标准图标静态 CDN 优先，云端资源包清单次之 */
  private async tryRemote(category: string, name: string, token: number): Promise<void> {
    if (!this.remoteFallback || name.length === 0) {
      return;
    }
    let found: string = await StandardIconService.ensure(category, name);
    if (found.length === 0) {
      found = await ResourcePackService.ensure(category, name);
    }
    if (found.length > 0) {
      const src: string = `file://${found}`;
      RAW_CACHE.set(`${category}/${name}`, src);
      if (token === this.resolveToken) {
        this.src = src;
      }
    }
  }

  build() {
    if (this.name.length > 0 && this.src !== '') {
      Image(this.src)
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(this.circular ? ImageFit.Cover : ImageFit.Contain)
        .borderRadius(this.circular ? this.iconSize / 2 : 0)
        .draggable(false)
    } else {
      Column()
        .width(this.iconSize)
        .height(this.iconSize)
        .borderRadius(this.iconSize / 6)
        .backgroundColor($r('app.color.page_background'))
    }
  }
}
