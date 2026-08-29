import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ComponentContent, UIContext, display, window } from '@kit.ArkUI';
import { RelationalStoreHelper } from '../data/db/RelationalStoreHelper';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { UserService } from '../service/UserService';
import { NotificationHelper } from '../data/local/NotificationHelper';
import { AppContextProvider } from '../common/AppContext';
import { buildRiskVerifyOverlay } from '../components/RiskVerifyModal';

const DOMAIN = 0x4E50;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private windowStage: window.WindowStage | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 跟随系统主题时，系统深浅切换实时同步（驱动壁纸遮罩/窗口底色/页面配色）
    const mode: string = PreferencesStore.getThemeMode();
    if (mode !== 'light' && mode !== 'dark') {
      const sysDark: boolean = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate<boolean>('isDarkMode', sysDark);
      try {
        const mainWindow: window.Window | undefined = this.windowStage?.getMainWindowSync();
        if (mainWindow !== undefined) {
          EntryAbility.applySystemBarColors(mainWindow);
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'config update bar color fail');
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    // 沉浸式顶部：加载完成后配置窗口（getMainWindowSync 需在 loadContent 后）
    EntryAbility.bootstrap(this, windowStage);
  }

  /** 沉浸式顶部状态栏：读取系统状态栏/导航栏高度存入 AppStorage，供页面避让；
   *  背景图仍可延伸至状态栏下（expandSafeArea），其余内容整体下移。
   *  PC(2in1)/平板自由窗口：隐藏系统标题栏（应用图标+名称一栏），仅保留右上角三键，
   *  内容区接管原标题栏区域，由应用自绘 TitleBar（透明、透传壁纸）。 */
  private configureImmersive(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      // 关键：窗口根背景设透明（默认是不透明 #FFF0F0F0/#FF1A1A1A，会挡住桌面，导致无法透传）。
      // 设透明后，WallpaperLayer 的模糊+半透明遮罩才能透出桌面内容，实现"透传桌面+模糊+调暗"。
      try {
        mainWindow.setWindowBackgroundColor('#00000000');
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor transparent unsupported');
      }
      // 自定义窗口装饰：三键区高度与自绘 TitleBar(40vp) 对齐；隐藏标题栏仅留三键
      let decorButtons: boolean = false;
      try {
        mainWindow.setWindowDecorHeight(40);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'setWindowDecorHeight unsupported');
      }
      try {
        mainWindow.setWindowDecorVisible(false);
        decorButtons = true;
      } catch (e) {
        // 手机等无标题栏形态：无系统三键，无需避让
        hilog.warn(DOMAIN, TAG, 'setWindowDecorVisible unsupported');
      }
      AppStorage.setOrCreate<boolean>('sysDecorButtons', decorButtons);
      EntryAbility.publishTitleButtonRect(mainWindow, decorButtons);
      try {
        mainWindow.on('windowTitleButtonRectChange', (rect: window.TitleButtonRect) => {
          EntryAbility.publishTitleButtonRectValue(rect);
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'on windowTitleButtonRectChange unsupported');
      }
      // 全屏布局（内容延伸至系统栏区域，背景可延伸）
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        // 状态栏图标色随深浅色切换（浅色=深图标 / 深色=白图标）
        EntryAbility.applySystemBarColors(mainWindow);
      }).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen fail: %{public}s', e.message);
      });
      // 自动读取系统规避区高度（px → vp），供页面顶部/底部避让
      EntryAbility.publishAvoidAreas(mainWindow);
      mainWindow.on('avoidAreaChange', () => {
        EntryAbility.publishAvoidAreas(mainWindow);
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'configureImmersive fail: %{public}s', JSON.stringify(e));
    }
  }

  /** 读取系统三键区（最小化/全屏/关闭）占位宽度写入 AppStorage（vp），供自绘 TitleBar 右侧避让 */
  private static publishTitleButtonRect(mainWindow: window.Window, decorButtons: boolean): void {
    try {
      EntryAbility.publishTitleButtonRectValue(mainWindow.getTitleButtonRect());
    } catch (e) {
      // 无三键（手机）：0；有装饰但读取失败：兜底 150vp
      AppStorage.setOrCreate<number>('titleBtnWidthVp', decorButtons ? 150 : 0);
      hilog.warn(DOMAIN, TAG, 'getTitleButtonRect fail, fallback=%{public}d', decorButtons ? 150 : 0);
    }
  }

  private static publishTitleButtonRectValue(rect: window.TitleButtonRect): void {
    // TitleButtonRect 相对窗口右上角：占宽 = right(右边距) + width；钳制到合理区间
    const widthVp: number = Math.min(200, Math.max(0, Math.ceil(rect.right + rect.width)));
    AppStorage.setOrCreate<number>('titleBtnWidthVp', widthVp);
  }

  /** 挂载全局人机验证浮层（窗口级 Overlay：位于一切 router 页面之上，随窗口存续） */
  private static mountRiskVerifyOverlay(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      const uiContext: UIContext = mainWindow.getUIContext();
      const content: ComponentContent<Object> =
        new ComponentContent<Object>(uiContext, wrapBuilder(buildRiskVerifyOverlay));
      uiContext.getOverlayManager().addComponentContent(content);
      hilog.info(DOMAIN, TAG, 'risk verify overlay mounted');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'mount risk overlay fail: %{public}s', JSON.stringify(e));
    }
  }

  /** 透明系统栏 + 图标色随深浅色（供启动与主题切换时调用） */  static applySystemBarColors(mainWindow: window.Window): void {
    const isDark: boolean = AppStorage.get<boolean>('isDarkMode') ?? false;
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: isDark ? '#FFFFFF' : '#1A1A1A',
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties fail: %{public}s', e.message);
    });
  }

  /** 读取状态栏(TOP)/底部导航指示区(BOTTOM)高度，转换为 vp 写入 AppStorage */  private static publishAvoidAreas(mainWindow: window.Window): void {
    try {
      const systemAvoid: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const topPx: number = systemAvoid.topRect.height;
      const bottomAvoid: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const bottomPx: number = bottomAvoid.bottomRect.height;
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const topVp: number = density > 0 ? Math.ceil(topPx / density) : 0;
      const bottomVp: number = density > 0 ? Math.ceil(bottomPx / density) : 0;
      AppStorage.setOrCreate<number>('topAvoidVp', topVp);
      AppStorage.setOrCreate<number>('bottomAvoidVp', bottomVp);
      hilog.info(DOMAIN, TAG, 'avoid area top=%{public}dpx(%{public}d vp) bottom=%{public}dpx',
        topPx, topVp, bottomPx);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'publishAvoidAreas fail: %{public}s', JSON.stringify(e));
    }
  }

  private static async bootstrap(ability: EntryAbility, windowStage: window.WindowStage): Promise<void> {
    try {
      AppContextProvider.init(ability.context);
      await PreferencesStore.init(ability.context);
      await RelationalStoreHelper.init(ability.context);
      await NotificationHelper.init();
      // 恢复登录态（预登录态）：AppStorage currentUser/currentUid/isLoggedIn
      await UserService.getInstance().restoreSession();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'init fail: %{public}s', JSON.stringify(e));
    }
    try {
      const mode: string = PreferencesStore.getThemeMode();
      const appCtx = ability.context.getApplicationContext();
      if (mode === 'light') {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === 'dark') {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
      // 发布当前深浅色状态（供每日背景渐变等配色）
      let sysMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      try {
        const cfg = ability.context.config;
        if (cfg !== undefined && cfg.colorMode !== undefined) {
          sysMode = cfg.colorMode;
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'read sys colorMode fail');
      }
      const isDark: boolean = mode === 'dark' ||
        (mode !== 'light' && sysMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      AppStorage.setOrCreate<boolean>('isDarkMode', isDark);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'set colorMode fail: %{public}s', JSON.stringify(e));
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'load content fail: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'load content ok');
      // 沉浸式配置需在 loadContent 成功、窗口就绪后执行
      ability.configureImmersive(windowStage);
      // 全局人机验证浮层（覆盖所有 router 页面，供 RiskVerifyService 弹出）
      EntryAbility.mountRiskVerifyOverlay(windowStage);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
