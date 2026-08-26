/**
 * WallpaperLayer.ets
 * 全屏壁纸层（对齐 Windows BackgroundImageService，无胡桃云依赖）：
 * - none：无背景图片，仅主题渐变（亮=橙白 / 暗=橙黑）
 * - local：本地随机图片（用户目录递归扫描 8 种格式随机取 1，5 分钟轮换；
 *   未选目录时回退内置每日一图打包图，按日期轮换）
 * - bing：必应每日一图（直连 cn.bing.com，当日结果落盘缓存不重复下载）
 * 图片上层保留主题化遮罩（深色压暗/浅色提亮），Stretch 对齐 UniformToFill(ImageFit.Cover)。
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
  /** 背景来源：none / local / bing */
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

  /** 内置背景图片（无目录时回退，按日期轮换） */
  private static readonly backgrounds: Resource[] = [
    $r('app.media.daily_bg_1'),
    $r('app.media.daily_bg_2'),
    $r('app.media.daily_bg_3'),
  ];

  private static dailyBackground(): Resource {
    const day: number = new Date().getDate();
    return WallpaperLayer.backgrounds[day % WallpaperLayer.backgrounds.length];
  }

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
    if (this.bgType === 'none') {
      this.hasImage = false;
      this.imgSrc = '';
      return;
    }
    if (this.bgType === 'bing') {
      this.loadBing();
      return;
    }
    // local
    if (this.folderPath.length === 0) {
      this.imgSrc = WallpaperLayer.dailyBackground();
      this.hasImage = true;
      return;
    }
    this.localPool = WallpaperLayer.scanImages(this.folderPath);
    this.pickLocalRandom();
  }

  private pickLocalRandom(): void {
    if (this.localPool.length === 0) {
      this.imgSrc = WallpaperLayer.dailyBackground();
      this.hasImage = true;
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

  /** 必应每日一图：当日缓存命中直接用，否则直连拉取并落盘 */
  private async loadBing(): Promise<void> {
    const now: Date = new Date();
    const day: string = `${now.getFullYear()}${WallpaperLayer.pad(now.getMonth() + 1)}${WallpaperLayer.pad(now.getDate())}`;
    const cachePath: string = `${AppContextProvider.getCacheDir()}/wallpaper_bing_${day}.jpg`;
    try {
      fileIo.accessSync(cachePath);
      this.imgSrc = `file://${cachePath}`;
      this.hasImage = true;
      return;
    } catch (e) {
      // 不存在则下载
    }
    try {
      // 1) 取元数据
      const metaReq: http.HttpRequest = http.createHttp();
      let imgUrl: string = '';
      let copyright: string = '';
      try {
        const resp = await metaReq.request('https://cn.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1', {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 10000,
        });
        if (resp.responseCode !== http.ResponseCode.OK) {
          throw new Error(`meta http ${resp.responseCode}`);
        }
        const root: Record<string, Object> = JSON.parse(resp.result as string) as Record<string, Object>;
        const images: Object[] = (root['images'] as Object[]) ?? [];
        if (images.length === 0) {
          throw new Error('empty images');
        }
        const first: Record<string, Object> = images[0] as Record<string, Object>;
        const url: string = String(first['url'] ?? '');
        if (url.length === 0) {
          throw new Error('empty url');
        }
        imgUrl = url.startsWith('http') ? url : `https://cn.bing.com${url}`;
        copyright = String(first['copyright'] ?? '');
      } finally {
        metaReq.destroy();
      }
      // 2) 下载图片
      const imgReq: http.HttpRequest = http.createHttp();
      try {
        const imgResp = await imgReq.request(imgUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 10000,
        });
        if (imgResp.responseCode !== http.ResponseCode.OK) {
          throw new Error(`img http ${imgResp.responseCode}`);
        }
        const file: fileIo.File = fileIo.openSync(cachePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(file.fd, imgResp.result as ArrayBuffer);
        } finally {
          fileIo.closeSync(file);
        }
      } finally {
        imgReq.destroy();
      }
      AppStorage.setOrCreate<string>('bgCopyright', copyright);
      this.imgSrc = `file://${cachePath}`;
      this.hasImage = true;
      Logger.info(TAG, `bing wallpaper cached: ${cachePath}`);
    } catch (e) {
      Logger.warn(TAG, `bing wallpaper fail: ${(e as Error).message}`);
      // 失败回退主题渐变
      this.hasImage = false;
    }
  }

  private static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      // none：应用级磨砂玻璃（对齐 Windows Acrylic 视觉，无背景图时也能透出"窗口后内容"的观感）
      // 注意：HarmonyOS 无窗口级桌面透传模糊 API（组件 backdropBlur 仅模糊应用内内容），
      // 此处用「低饱和渐变 + 半透明遮罩 + 主题化亮度」模拟 Acrylic，保证内容可读性。
      if (this.bgType === 'none') {
        Column()
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .linearGradient({
            angle: 135,
            colors: [
              [this.isDark ? '#1E1E22' : '#F2F0EC', 0.0],
              [this.isDark ? '#141418' : '#E8E6E2', 1.0],
            ],
          })
          .opacity(0.92)
      } else {
        // local/bing：主题渐变底（图片下层兜底；浅色用中性灰白，避免暖黄底透色）
        Column()
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .linearGradient({
            angle: 180,
            colors: [
              [this.isDark ? '#14100C' : '#F5F4F2', 0.0],
              [this.isDark ? '#0B0B0C' : '#EDECEA', 1.0],
            ],
          })
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
      // 底部柔光增强氛围
      Column()
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .linearGradient({
          angle: 180,
          colors: [
            [this.isDark ? '#00000000' : '#FFFFFF24', 0.0],
            [this.isDark ? '#00000066' : '#FFFFFF00', 1.0],
          ],
        })
    }
    .width('100%')
    .height('100%')
  }
}
