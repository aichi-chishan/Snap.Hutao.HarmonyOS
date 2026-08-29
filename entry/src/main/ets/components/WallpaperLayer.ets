/**
 * WallpaperLayer.ets
 * 全屏壁纸层（对齐 Windows BackgroundImageService，无胡桃云依赖）：
 * - none：无背景图片，主题纯色底（与窗口底色同色系）
 * - local：本地随机图片（用户目录递归扫描 8 种格式随机取 1，5 分钟轮换；
 *   未选目录或目录无图片时与 none 相同显示主题纯色底，保证两种模式观感一致）
 * 图片上层保留主题化遮罩（深色压暗/浅色提亮），ImageFit.Cover。
 */
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const TAG: string = 'WallpaperLayer';
/** 本地图片扩展名白名单（对齐 Windows BackgroundImageService） */
const IMAGE_EXTS: string[] = ['.bmp', '.gif', '.ico', '.jpg', '.jpeg', '.png', '.tiff', '.webp'];

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
  /** 本地图片池 */
  private localPool: string[] = [];
  /** 轮换计时器 */
  private rotateTimer: number = -1;

  aboutToAppear(): void {
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
    this.imgSrc = `file://${this.localPool[idx]}`;
    this.hasImage = true;
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
      // 基底必须用纯色（禁止 linearGradient）：部分合成器/软渲染路径对渐变着色器
      // 支持不完整，会把整块渐变输出为纯黄（历史"浅色模式整窗发黄"的根因）。
      // 纯色与窗口底色（EntryAbility.applyWindowBackdrop）同色系，视觉无缝。
      if (this.bgType === 'none') {
        Column()
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .backgroundColor(this.isDark ? '#1B1B20' : '#F2F0EC')
      } else {
        // local：中性底（图片下层兜底；浅色用中性灰白，避免暖黄底透色）
        Column()
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .backgroundColor(this.isDark ? '#14100C' : '#F5F4F2')
      }
      // 背景图片（ImageFit.Cover = UniformToFill；none 时无图）
      if (this.hasImage) {
        Image(this.imgSrc)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.isDark ? 0.38 : 0.5)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .backgroundBlurStyle(BlurStyle.Regular)
      }
      // 主题化遮罩层（none 时以模糊+半透明调暗即足）
      if (this.bgType !== 'none') {
        Column()
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .backgroundColor(this.isDark ? '#00000033' : '#FFFFFF99')
      }
    }
    .width('100%')
    .height('100%')
  }
}
