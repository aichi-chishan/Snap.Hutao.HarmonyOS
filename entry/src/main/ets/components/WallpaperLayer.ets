/**
 * WallpaperLayer.ets
 * 全屏壁纸层（对齐 Windows BackgroundImageService，无胡桃云依赖）：
 * - none：无背景图片，主题纯色底（与窗口底色同色系）
 * - local：本地随机图片（用户目录递归扫描 8 种格式随机取 1，5 分钟轮换；
 *   未选目录或目录无图片时与 none 相同显示主题纯色底，保证两种模式观感一致）
 * - hutao：胡桃每日一图（Snap.Hutao 公开壁纸接口，当日缓存复用；失败与 none 观感一致）
 * 图片按亮度自适应透明度，并叠加 Mica 观感处理（blur 模糊 + saturation 降饱和 + 暗色提亮），
 * ImageFit.Cover。
 */
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { AppContextProvider } from '../common/AppContext';
import { HutaoDailyImageService } from '../service/HutaoDailyImageService';
import { Logger } from '../common/Logger';

const TAG: string = 'WallpaperLayer';
/** 本地图片扩展名白名单（对齐 Windows BackgroundImageService） */
const IMAGE_EXTS: string[] = ['.bmp', '.gif', '.ico', '.jpg', '.jpeg', '.png', '.tiff', '.webp'];
/** 壁纸模糊半径 vp（对齐 Windows Mica 模糊观感：模糊+降饱和的背景，提高前景卡片可读性） */
const WALLPAPER_BLUR_VP: number = 22;
/** Mica 降饱和系数（<1 压低壁纸色彩饱和度，贴近 Windows Mica 底材观感） */
const MICA_SATURATION: number = 0.9;
/** Mica 暗色提亮系数（暗色下轻微提亮壁纸，让侧栏/页签玻璃层透出明暗而非纯黑） */
const MICA_DARK_BRIGHTNESS: number = 1.15;

@Component
export struct WallpaperLayer {
  /** 是否深色模式（AppStorage isDarkMode，主题切换实时更新；@Watch 触发重渲） */
  @StorageProp('isDarkMode') @Watch('onDarkChanged') isDark: boolean = false;
  /** 背景来源：none / local */
  @Prop @Watch('onBgChanged') bgType: string = 'local';
  /** 本地图片目录（local 生效；空回退内置图） */
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

  aboutToAppear(): void {
    Logger.info(TAG, `aboutToAppear bgType=${this.bgType} folder=${this.folderPath} isDark=${this.isDark}`);
    this.loadImage();
    // 本地随机：5 分钟轮换（对齐 Windows Period=0:5:0）
    if (this.bgType === 'local' && this.folderPath.length > 0) {
      this.rotateTimer = setInterval(() => {
        this.pickLocalRandom();
      }, 300000);
    }
  }

  aboutToDisappear(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = -1;
    }
  }

  /** 主题切换实时触发（@StorageProp isDark 变化自动重建 build，无需手动占位） */
  onDarkChanged(): void {
    Logger.info(TAG, `isDark changed -> ${this.isDark}, bgType=${this.bgType}`);
  }

  /** 背景来源/目录变化时重新装载 */
  onBgChanged(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = -1;
    }
    this.loadImage();
    if (this.bgType === 'local' && this.folderPath.length > 0) {
      this.rotateTimer = setInterval(() => {
        this.pickLocalRandom();
      }, 300000);
    }
  }

  private loadImage(): void {
    if (this.bgType === 'hutao') {
      // 胡桃每日一图：当日缓存复用，失败回退主题纯色底（与 none 一致）
      this.hasImage = false;
      this.imgSrc = '';
      HutaoDailyImageService.getInstance().getToday().then((img) => {
        if (img !== undefined && this.bgType === 'hutao') {
          this.applyImage(img.path);
          Logger.info(TAG, `hutao daily image ready (${img.author}${img.fromCache ? ', cached' : ''})`);
        }
      });
      return;
    }
    if (this.bgType !== 'local' || this.folderPath.length === 0) {
      // none / local 未选目录：主题纯色底（观感一致）
      this.hasImage = false;
      this.imgSrc = '';
      return;
    }
    this.localPool = WallpaperLayer.scanImages(this.folderPath);
    this.pickLocalRandom();
  }

  private pickLocalRandom(): void {
    if (this.localPool.length === 0) {
      // 目录无图片：与 none 一致（主题纯色底）
      this.hasImage = false;
      this.imgSrc = '';
      return;
    }
    const idx: number = Math.floor(Math.random() * this.localPool.length);
    this.applyImage(this.localPool[idx]);
  }

  /** 应用背景图：亮度→不透明度（Windows：深色 1-L / 浅色 L），1s Quartic 渐变 */
  private applyImage(path: string): void {
    this.imgSrc = `file://${path}`;
    this.hasImage = true;
    WallpaperLayer.luminance(path).then((l: number) => {
      const target: number = this.isDark ? 1 - l : l;
      this.getUIContext().animateTo({ duration: 1000, curve: Curve.EaseInOut }, () => {
        this.imgOpacity = Math.min(1, Math.max(0, target));
      });
    });
  }

  /**
   * 图片平均亮度 L（对齐 Windows GetRgba32AccentColor 均值色 + Rgba32.Luminance）：
   * 全图 RGB 均值后按 Rec.709 加权（0.2126R+0.7152G+0.0722B）/255。
   * 解码降采样到 160x90 再求均值（均值与大图全量均值差异可忽略，避免大位图遍历开销）。
   */
  private static async luminance(path: string): Promise<number> {
    try {
      const src: image.ImageSource = image.createImageSource(path);
      const size: image.Size = { width: 160, height: 90 };
      const opts: image.DecodingOptions = {
        desiredSize: size,
      };
      const pm: image.PixelMap = await src.createPixelMap(opts);
      const info: image.ImageInfo = await pm.getImageInfo();
      const buf: ArrayBuffer = new ArrayBuffer(info.size.width * info.size.height * 4);
      await pm.readPixelsToBuffer(buf);
      const bytes: Uint8Array = new Uint8Array(buf);
      let r = 0; let g = 0; let b = 0;
      const px: number = Math.floor(bytes.length / 4);
      for (let i = 0; i < px; i++) {
        r += bytes[i * 4];
        g += bytes[i * 4 + 1];
        b += bytes[i * 4 + 2];
      }
      pm.release();
      src.release();
      const lum: number = (0.2126 * (r / px) + 0.7152 * (g / px) + 0.0722 * (b / px)) / 255;
      Logger.info(TAG, `luminance ${path.substring(path.lastIndexOf('/') + 1)} -> ${lum.toFixed(3)}`);
      return lum;
    } catch (e) {
      Logger.warn(TAG, `luminance fail: ${(e as Error).message}`);
      return WallpaperLayer.isDarkFallback();
    }
  }

  private static isDarkFallback(): number {
    // 解码失败：中性值 0.5（两种主题下均为中等透明度）
    return 0.5;
  }

  /** 递归扫描目录图片（对齐 Windows Directory.EnumerateFiles AllDirectories；支持 file:// URI 归一化） */
  private static scanImages(dir: string): string[] {
    let realDir: string = dir;
    if (dir.startsWith('file://')) {
      try {
        realDir = new fileUri.FileUri(dir).path;
      } catch (e) {
        Logger.warn(TAG, `uri convert fail: ${(e as Error).message}`);
        return [];
      }
    }
    const out: string[] = [];
    try {
      const names: string[] = fileIo.listFileSync(realDir, { recursion: true });
      for (const name of names) {
        const lower: string = name.toLowerCase();
        for (const ext of IMAGE_EXTS) {
          if (lower.endsWith(ext)) {
            out.push(`${realDir}/${name}`);
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
      // 背景图片（全量复刻 Windows：UniformToFill + 按图片亮度动态透明度；亮度低→浅色模式更不透明/
      // 深色模式更透明，自动保证前景对比度）。叠加 Mica 观感处理：模糊 + 降饱和（对齐 Windows Mica
      // "模糊+降饱和的背景"），暗色再轻微提亮让玻璃材质能透出壁纸明暗。仅 hasImage 时生效，
      // none 纯色底不受影响。
      if (this.hasImage) {
        Image(this.imgSrc)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(WALLPAPER_BLUR_VP)
          .saturate(MICA_SATURATION)
          .brightness(this.isDark ? MICA_DARK_BRIGHTNESS : 1)
          .opacity(this.imgOpacity)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
  }
}
