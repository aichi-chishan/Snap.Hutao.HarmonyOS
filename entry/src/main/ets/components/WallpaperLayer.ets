/**
 * WallpaperLayer.ets
 * 全屏壁纸层（对齐 Windows BackgroundImageService）：
 * - none：无背景图片，主题纯色底（与窗口底色同色系）
 * - local：本地随机图片（用户目录递归扫描 8 种格式随机取 1，5 分钟轮换；
 *   未选目录或目录无图片时与 none 相同显示主题纯色底，保证两种模式观感一致）
 * - hutao：胡桃每日一图（Snap.Hutao 公开壁纸接口，当日缓存复用；失败与 none 观感一致）
 * 图片保持清晰并按亮度自适应透明度（ImageFit.Cover）；局部磨砂由 UiSurface 处理。
 */
import { BackgroundVideoLayer } from './BackgroundVideoLayer';
import { fileIo, fileShare, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { HutaoDailyImage, HutaoDailyImageService } from '../service/HutaoDailyImageService';
import { Logger } from '../common/Logger';

const TAG: string = 'WallpaperLayer';
/** 本地图片扩展名白名单（对齐 Windows BackgroundImageService） */
const IMAGE_EXTS: string[] = ['.bmp', '.gif', '.ico', '.jpg', '.jpeg', '.png', '.tiff', '.webp'];

@Component
export struct WallpaperLayer {
  /** 是否深色模式（AppStorage isDarkMode，主题切换实时更新；@Watch 触发重渲） */
  @StorageProp('isDarkMode') @Watch('onDarkChanged') isDark: boolean = false;
  @StorageProp('reduceMotion') @Watch('onMotionChanged') reduceMotion: boolean = false;
  /** 背景来源：none / local / hutao / bing / hoyoplay */
  @Prop @Watch('onBgChanged') bgType: string = 'local';
  /** 本地图片目录（local 生效；空目录显示主题底色） */
  @Prop @Watch('onBgChanged') folderPath: string = '';
  /** 当前图片源（file:// 路径或内置 Resource） */
  @State imgSrc: string | Resource = '';
  @State hasImage: boolean = false;
  /** 图片不透明度：按图片亮度动态计算（Windows Luminance 规则），渐变过渡 */
  @State imgOpacity: number = 0;
  /** 本地图片池 */
  private localPool: string[] = [];
  /** 轮换计时器 */
  private rotateTimer: number = -1;
  private imageSequence: number = 0;
  private currentLuminance: number = 0.5;
  private currentLocalPath: string = '';
  private attached: boolean = false;

  aboutToAppear(): void {
    this.attached = true;
    Logger.info(TAG, `aboutToAppear bgType=${this.bgType} folder=${this.folderPath} isDark=${this.isDark}`);
    this.onBgChanged();
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.imageSequence++;
    this.localPool = [];
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = -1;
    }
  }

  /** 主题切换实时触发（@StorageProp isDark 变化自动重建 build，无需手动占位） */
  onDarkChanged(): void {
    this.imgOpacity = this.isDark ? 1 - this.currentLuminance : this.currentLuminance;
  }

  /** 动态关闭过渡时，以零时长重定向当前不透明度；不重载图片或更改轮换计时器。 */
  onMotionChanged(): void {
    if (this.reduceMotion && this.hasImage) {
      const target: number = this.isDark ? 1 - this.currentLuminance : this.currentLuminance;
      this.getUIContext().animateTo({ duration: 0 }, () => {
        this.imgOpacity = Math.min(1, Math.max(0, target));
      });
    }
  }

  /** 背景来源/目录变化时重新装载 */
  onBgChanged(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = -1;
    }
    if (!this.attached) { return; }
    this.loadImage();
    if (this.bgType === 'local' && this.folderPath.length > 0) {
      this.rotateTimer = setInterval(() => {
        this.pickLocalRandom();
      }, 300000);
    }
  }

  private async loadImage(): Promise<void> {
    const sequence: number = ++this.imageSequence;
    this.localPool = [];
    this.currentLocalPath = '';
    this.hasImage = false;
    this.imgSrc = '';
    AppStorage.setOrCreate<string>('bgCopyright', '');
    AppStorage.setOrCreate<string>('bgSourceUrl', '');
    if (this.bgType === 'hutao' || this.bgType === 'bing' || this.bgType === 'hoyoplay') {
      const source: string = this.bgType;
      AppStorage.setOrCreate<string>('dailyWallpaperState', 'loading');
      try {
        const img: HutaoDailyImage | undefined = await HutaoDailyImageService.getInstance().getToday(source);
        if (sequence !== this.imageSequence) { return; }
        if (img !== undefined) {
          this.applyImage(img.path);
          AppStorage.setOrCreate<string>('bgCopyright', img.author);
          AppStorage.setOrCreate<string>('bgSourceUrl', /^https?:\/\/[^\s]+$/i.test(img.sourceUrl) ? img.sourceUrl : '');
          AppStorage.setOrCreate<string>('dailyWallpaperState', 'ready');
          Logger.info(TAG, `${source} daily image ready (${img.author}${img.fromCache ? ', cached' : ''})`);
        } else {
          AppStorage.setOrCreate<string>('dailyWallpaperState', 'unavailable');
        }
      } catch (e) {
        if (sequence !== this.imageSequence) { return; }
        AppStorage.setOrCreate<string>('dailyWallpaperState', 'unavailable');
        Logger.warn(TAG, `daily image fail: ${(e as Error).message}`);
      }
      return;
    }
    AppStorage.setOrCreate<string>('dailyWallpaperState', '');
    if (this.bgType !== 'local' || this.folderPath.length === 0) {
      return;
    }
    await this.pickLocalRandom();
  }

  private async pickLocalRandom(): Promise<void> {
    if (this.bgType !== 'local' || this.folderPath.length === 0) { return; }
    const sequence: number = ++this.imageSequence;
    if (this.localPool.length === 0) {
      let paths: string[] = await WallpaperLayer.scanImages(this.folderPath);
      if (sequence !== this.imageSequence) { return; }
      // Windows 每轮取出后移除，耗尽再扫描；新一轮也不紧接着重复上一张。
      if (paths.length > 1) {
        paths = paths.filter((path: string): boolean => path !== this.currentLocalPath);
      }
      this.localPool = paths;
    }
    if (this.localPool.length === 0) {
      // 目录无图片：与 none 一致（主题纯色底）
      this.hasImage = false;
      this.imgSrc = '';
      return;
    }
    const idx: number = Math.floor(Math.random() * this.localPool.length);
    const path: string = this.localPool.splice(idx, 1)[0];
    if (path === this.currentLocalPath) { return; }
    this.currentLocalPath = path;
    this.applyImage(path);
  }

  /** 应用背景图：亮度→不透明度（Windows：深色 1-L / 浅色 L），1s Quartic 渐变 */
  private applyImage(path: string): void {
    const sequence: number = ++this.imageSequence;
    this.imgSrc = fileUri.getUriFromPath(path);
    this.hasImage = true;
    WallpaperLayer.luminance(path).then((l: number) => {
      if (sequence !== this.imageSequence) { return; }
      this.currentLuminance = l;
      const target: number = this.isDark ? 1 - l : l;
      if (this.reduceMotion) {
        this.imgOpacity = Math.min(1, Math.max(0, target));
      } else {
        this.getUIContext().animateTo({ duration: 1000, curve: Curve.EaseInOut }, () => {
          this.imgOpacity = Math.min(1, Math.max(0, target));
        });
      }
    });
  }

  /**
   * 图片平均亮度 L（对齐 Windows GetRgba32AccentColor 均值色 + Rgba32.Luminance）：
   * 全图 RGB 均值后按 Rec.709 加权（0.2126R+0.7152G+0.0722B）/255。
   * 解码降采样到 160x90 再求均值（均值与大图全量均值差异可忽略，避免大位图遍历开销）。
   */
  private static async luminance(path: string): Promise<number> {
    let src: image.ImageSource | undefined = undefined;
    let pm: image.PixelMap | undefined = undefined;
    try {
      src = image.createImageSource(path);
      const size: image.Size = { width: 160, height: 90 };
      const opts: image.DecodingOptions = {
        desiredSize: size,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      };
      pm = await src.createPixelMap(opts);
      const info: image.ImageInfo = await pm.getImageInfo();
      const buf: ArrayBuffer = new ArrayBuffer(info.size.width * info.size.height * 4);
      await pm.readPixelsToBuffer(buf);
      const bytes: Uint8Array = new Uint8Array(buf);
      let r: number = 0; let g: number = 0; let b: number = 0;
      const px: number = Math.floor(bytes.length / 4);
      for (let i: number = 0; i < px; i++) {
        r += bytes[i * 4];
        g += bytes[i * 4 + 1];
        b += bytes[i * 4 + 2];
      }
      const lum: number = (0.2126 * (r / px) + 0.7152 * (g / px) + 0.0722 * (b / px)) / 255;
      Logger.info(TAG, `luminance ${path.substring(path.lastIndexOf('/') + 1)} -> ${lum.toFixed(3)}`);
      return lum;
    } catch (e) {
      Logger.warn(TAG, `luminance fail: ${(e as Error).message}`);
      return 0.5;
    } finally {
      // 两个对象分别释放，PixelMap 释放失败也不能跳过 ImageSource。
      if (pm !== undefined) {
        await pm.release().catch((e: Error): void => { Logger.warn(TAG, `release pixels fail: ${e.message}`); });
      }
      if (src !== undefined) {
        await src.release().catch((e: Error): void => { Logger.warn(TAG, `release image source fail: ${e.message}`); });
      }
    }
  }

  /** 递归扫描目录图片（对齐 Windows Directory.EnumerateFiles AllDirectories；支持 file:// URI 归一化） */
  private static async scanImages(dir: string): Promise<string[]> {
    let realDir: string = dir;
    if (dir.startsWith('file://')) {
      if (canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) {
        const policy: fileShare.PolicyInfo = { uri: dir, operationMode: fileShare.OperationMode.READ_MODE };
        try {
          const persisted: boolean[] = await fileShare.checkPersistentPermission([policy]);
          if (persisted[0]) { await fileShare.activatePermission([policy]); }
        } catch (e) {
          // 仍可使用本次 Picker 给的临时授权；不能因持久授权失败而阻断当前选择。
          Logger.warn(TAG, `activate folder permission fail: ${(e as Error).message}`);
        }
      }
      try {
        realDir = new fileUri.FileUri(dir).path;
      } catch (e) {
        Logger.warn(TAG, `uri convert fail: ${(e as Error).message}`);
        return [];
      }
    }
    const out: string[] = [];
    try {
      const names: string[] = await fileIo.listFile(realDir, { recursion: true });
      for (const name of names) {
        const lower: string = name.toLowerCase();
        for (const ext of IMAGE_EXTS) {
          if (lower.endsWith(ext)) {
            // recursion=true 的相对路径以 / 开头，非递归返回的名称则不带 /。
            const relative: string = name.startsWith('/') ? name.substring(1) : name;
            out.push(`${realDir.replace(/\/$/, '')}/${relative}`);
            break;
          }
        }
      }
    } catch (e) {
      Logger.warn(TAG, `scan ${realDir} fail: ${(e as Error).message}`);
    }
    Logger.info(TAG, `scan ${realDir}: ${out.length} images`);
    return out;
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      // 基底一律纯色（禁止 linearGradient）并与窗口底色同色系（EntryAbility.applyWindowBackdrop），
      // 配色走资源色 wallpaper_base（base/dark 双份），主题切换实时生效。
      Column()
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .backgroundColor($r('app.color.wallpaper_base'))
      // 对齐 Windows：壁纸清晰铺满，亮度 L 决定浅色 L / 深色 1-L 的不透明度。
      if (this.hasImage) {
        Image(this.imgSrc)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.imgOpacity)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      BackgroundVideoLayer()
    }
    .width('100%')
    .height('100%')
  }
}
