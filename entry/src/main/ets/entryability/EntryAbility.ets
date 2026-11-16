import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ComponentContent, OverlayManager, UIContext, window } from '@kit.ArkUI';
import { RelationalStoreHelper } from '../data/db/RelationalStoreHelper';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { BackupService } from '../service/BackupService';
import { UserService } from '../service/UserService';
import { BackgroundTaskService } from '../service/BackgroundTaskService';
import { NotificationHelper } from '../data/local/NotificationHelper';
import { DailyNoteService } from '../service/DailyNoteService';
import { AutoSignInService } from '../service/AutoSignInService';
import { AppContextProvider } from '../common/AppContext';
import { Motion } from '../common/Motion';
import { UiSurface } from '../common/UiSurface';
import { GameDataService } from '../service/GameDataService';
import { RiskVerifyService } from '../service/RiskVerifyService';
import { buildRiskVerifyOverlay } from '../components/RiskVerifyModal';
import { Logger } from '../common/Logger';
import { AppLocaleService } from '../service/AppLocaleService';

const DOMAIN = 0x4E50;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private static runtimeInitialization: Promise<void> | undefined = undefined;
  private static deferredServicesStarted: boolean = false;
  private windowStage: window.WindowStage | undefined = undefined;
  private mainWindow: window.Window | undefined = undefined;
  private windowLayoutReady: boolean = false;
  private titleButtonListener: ((rect: window.TitleButtonRect) => void) | undefined = undefined;
  private avoidAreaListener: ((options: window.AvoidAreaOptions) => void) | undefined = undefined;
  private overlayManager: OverlayManager | undefined = undefined;
  private riskVerifyContent: ComponentContent<Object> | undefined = undefined;
  private startupPending: boolean = false;
  private startupErrorLoaded: boolean = false;
  private startupRetryListener: (() => void) | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    this.releaseWindowResources();
    AutoSignInService.getInstance().setForeground(false);
    DailyNoteService.getInstance().setForeground(false);
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
    Logger.flush();
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppLocaleService.onConfigurationUpdate(newConfig.language);
    // 跟随系统主题时，系统深浅切换实时同步（驱动壁纸遮罩/窗口底色/页面配色）
    const mode: string = PreferencesStore.isReady() ? PreferencesStore.getThemeMode() : 'system';
    if (mode !== 'light' && mode !== 'dark') {
      const sysDark: boolean = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate<boolean>('isDarkMode', sysDark);
      try {
        const mainWindow: window.Window | undefined = this.mainWindow;
        if (mainWindow !== undefined && this.windowLayoutReady) {
          EntryAbility.applySystemBarColors(mainWindow);
          // 窗口根底色随主题同步（不透明，修复透明窗口合成异常发黄问题）
          EntryAbility.applyWindowBackdrop(mainWindow);
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'config update bar color fail');
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.releaseWindowResources();
    this.windowStage = windowStage;
    // 沉浸式顶部：加载完成后配置窗口（getMainWindowSync 需在 loadContent 后）
    EntryAbility.bootstrap(this, windowStage);
  }

  /** 沉浸式顶部状态栏：读取系统状态栏/导航栏高度存入 AppStorage，供页面避让；
   *  背景图仍可延伸至状态栏下（expandSafeArea），其余内容整体下移。
   *  PC(2in1)/平板自由窗口：隐藏系统标题栏（应用图标+名称一栏），仅保留右上角三键，
   *  内容区接管原标题栏区域，由应用自绘 TitleBar（透明、透传壁纸）。 */
  private configureImmersive(windowStage: window.WindowStage): void {
    if (this.windowStage !== windowStage) { return; }
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      this.mainWindow = mainWindow;
      // 窗口根背景必须为不透明主题色（setWindowLayoutFullScreen 就绪后设置，见下方 then）。
      // 曾经为"透传桌面"设过透明（#00000000），但模拟器/部分合成器对透明窗口的 alpha 合成
      // 不完整：应用内半透明像素会被未初始化缓冲污染（整窗发黄）。
      // HarmonyOS 也无窗口级桌面模糊 API，透明透色没有实际收益 → 改为跟随主题的不透明底色。
      // 直接声明 vp 限制，显示器或窗口密度变化后由系统重新换算。
      try {
        mainWindow.setWindowLimits({
          maxWidth: 2560,
          maxHeight: 1600,
          minWidth: 360,
          minHeight: 640,
          pixelUnit: window.PixelUnit.VP,
        }).catch((e: Error): void => {
          hilog.warn(DOMAIN, TAG, 'setWindowLimits fail: %{public}s', e.message);
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'setWindowLimits min size unsupported');
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
      // 应用版本号（顶栏展示与更新检查共用）
      try {
        const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
        AppStorage.setOrCreate<string>('appVersion', info.versionName);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'versionName read fail');
      }
      EntryAbility.publishTitleButtonRect(mainWindow, decorButtons);
      try {
        const titleListener: (rect: window.TitleButtonRect) => void = (rect: window.TitleButtonRect): void => {
          if (this.mainWindow === mainWindow) { EntryAbility.publishTitleButtonRectValue(rect); }
        };
        mainWindow.on('windowTitleButtonRectChange', titleListener);
        this.titleButtonListener = titleListener;
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'on windowTitleButtonRectChange unsupported');
      }
      // 全屏布局（内容延伸至系统栏区域，背景可延伸）
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        if (this.mainWindow !== mainWindow) { return; }
        this.windowLayoutReady = true;
        // 状态栏图标色随深浅色切换（浅色=深图标 / 深色=白图标）
        EntryAbility.applySystemBarColors(mainWindow);
        // 窗口根底色随主题（不透明；窗口就绪后设置，过早调用报 1300002）
        EntryAbility.applyWindowBackdrop(mainWindow);
        EntryAbility.publishAvoidAreas(mainWindow);
      }).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen fail: %{public}s', e.message);
      });
      // 自动读取系统规避区高度（px → vp），供页面顶部/底部避让
      const avoidListener: (options: window.AvoidAreaOptions) => void = (_options: window.AvoidAreaOptions): void => {
        if (this.mainWindow === mainWindow && this.windowLayoutReady) { EntryAbility.publishAvoidAreas(mainWindow); }
      };
      mainWindow.on('avoidAreaChange', avoidListener);
      this.avoidAreaListener = avoidListener;
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
    // TitleButtonRect 已是 vp；保留系统实际占宽，不截断放大后的三键区。
    const widthVp: number = Math.max(0, Math.ceil(rect.right + rect.width));
    AppStorage.setOrCreate<number>('titleBtnWidthVp', widthVp);
  }

  /** 挂载全局人机验证浮层（窗口级 Overlay：位于一切 router 页面之上，随窗口存续） */
  private mountRiskVerifyOverlay(): void {
    const mainWindow: window.Window | undefined = this.mainWindow;
    if (mainWindow === undefined) { return; }
    try {
      const uiContext: UIContext = mainWindow.getUIContext();
      this.overlayManager = uiContext.getOverlayManager();
      this.riskVerifyContent =
        new ComponentContent<Object>(uiContext, wrapBuilder(buildRiskVerifyOverlay));
      this.overlayManager.addComponentContent(this.riskVerifyContent);
      hilog.info(DOMAIN, TAG, 'risk verify overlay mounted');
    } catch (e) {
      this.releaseRiskVerifyOverlay();
      hilog.error(DOMAIN, TAG, 'mount risk overlay fail: %{public}s', JSON.stringify(e));
    }
  }

  private releaseRiskVerifyOverlay(): void {
    const content: ComponentContent<Object> | undefined = this.riskVerifyContent;
    const manager: OverlayManager | undefined = this.overlayManager;
    this.riskVerifyContent = undefined;
    this.overlayManager = undefined;
    if (content === undefined) { return; }
    try {
      manager?.removeComponentContent(content);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'remove risk overlay fail: %{public}s', JSON.stringify(e));
    }
    try {
      content.dispose();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'dispose risk overlay fail: %{public}s', JSON.stringify(e));
    }
  }

  private releaseWindowResources(): void {
    const mainWindow: window.Window | undefined = this.mainWindow;
    const hadWindowStage: boolean = this.windowStage !== undefined;
    this.windowStage = undefined;
    this.mainWindow = undefined;
    this.windowLayoutReady = false;
    this.startupPending = false;
    this.startupErrorLoaded = false;
    this.stopStartupRetry();
    // 关闭窗口也结束等待中的验证；初次创建和重复清理不取消新的请求。
    if (hadWindowStage) { RiskVerifyService.getInstance().cancel(); }
    // 只解除本 Ability 注册的回调，保留同一窗口中其他功能的订阅。
    if (mainWindow !== undefined && this.titleButtonListener !== undefined) {
      try { mainWindow.off('windowTitleButtonRectChange', this.titleButtonListener); }
      catch (e) { hilog.warn(DOMAIN, TAG, 'off title button listener fail'); }
    }
    if (mainWindow !== undefined && this.avoidAreaListener !== undefined) {
      try { mainWindow.off('avoidAreaChange', this.avoidAreaListener); }
      catch (e) { hilog.warn(DOMAIN, TAG, 'off avoid area listener fail'); }
    }
    this.titleButtonListener = undefined;
    this.avoidAreaListener = undefined;
    this.releaseRiskVerifyOverlay();
    AppStorage.setOrCreate<boolean>('sysDecorButtons', false);
    AppStorage.setOrCreate<number>('titleBtnWidthVp', 0);
    AppStorage.setOrCreate<number>('topAvoidVp', 0);
    AppStorage.setOrCreate<number>('bottomAvoidVp', 0);
  }

  private enableStartupRetry(windowStage: window.WindowStage): void {
    if (this.startupRetryListener !== undefined) { return; }
    this.startupRetryListener = (): void => { EntryAbility.bootstrap(this, windowStage); };
    this.context.eventHub.on('hutao.startup.retry', this.startupRetryListener);
  }

  private stopStartupRetry(): void {
    if (this.startupRetryListener === undefined) { return; }
    this.context.eventHub.off('hutao.startup.retry', this.startupRetryListener);
    this.startupRetryListener = undefined;
  }

  /** 窗口根背景：跟随主题的不透明色，与 WallpaperLayer 的主题底色一致。 */
  static applyWindowBackdrop(mainWindow: window.Window): void {
    const isDark: boolean = AppStorage.get<boolean>('isDarkMode') ?? false;
    try {
      // 浅色与 wallpaper_base 同系（#F2F0EC 加 FF 不透明前缀，#AARRGGBB），对齐 Windows Mica Base 底色
      mainWindow.setWindowBackgroundColor(isDark ? '#FF141418' : '#FFF2F0EC');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor fail: %{public}s', JSON.stringify(e));
    }
  }

  /** 透明系统栏 + 图标色随深浅色（供启动与主题切换时调用） */
  static applySystemBarColors(mainWindow: window.Window): void {
    const isDark: boolean = AppStorage.get<boolean>('isDarkMode') ?? false;
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      statusBarContentColor: isDark ? '#FFFFFF' : '#1A1A1A',
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties fail: %{public}s', e.message);
    });
  }

  /** 读取状态栏(TOP)/底部导航指示区(BOTTOM)高度，转换为 vp 写入 AppStorage */
  private static publishAvoidAreas(mainWindow: window.Window): void {
    try {
      const systemAvoid: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const topPx: number = systemAvoid.topRect.height;
      const bottomAvoid: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const bottomPx: number = bottomAvoid.bottomRect.height;
      const uiContext: UIContext = mainWindow.getUIContext();
      const topVp: number = Math.ceil(uiContext.px2vp(topPx));
      const bottomVp: number = Math.ceil(uiContext.px2vp(bottomPx));
      AppStorage.setOrCreate<number>('topAvoidVp', topVp);
      AppStorage.setOrCreate<number>('bottomAvoidVp', bottomVp);
      hilog.info(DOMAIN, TAG, 'avoid area top=%{public}dpx(%{public}d vp) bottom=%{public}dpx',
        topPx, topVp, bottomPx);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'publishAvoidAreas fail: %{public}s', JSON.stringify(e));
    }
  }

  /** One process-wide initialization, shared by repeated window creation. */
  private static async initializeRuntime(context: common.UIAbilityContext): Promise<void> {
    if (EntryAbility.runtimeInitialization === undefined) {
      EntryAbility.runtimeInitialization = EntryAbility.prepareRuntime(context);
    }
    const pending: Promise<void> = EntryAbility.runtimeInitialization;
    try { await pending; }
    catch (e) {
      if (EntryAbility.runtimeInitialization === pending) { EntryAbility.runtimeInitialization = undefined; }
      if (e instanceof Error) { throw e; } throw new Error('应用运行环境初始化失败');
    }
  }

  private static async prepareRuntime(context: common.UIAbilityContext): Promise<void> {
    AppContextProvider.init(context);
    await PreferencesStore.init(context);
    // 界面材质令牌发布（模式/级别 → AppStorage，壳层与各表面即时读取）
    UiSurface.publish();
    await RelationalStoreHelper.init(context);
    await BackgroundTaskService.init(context);
    const users: UserService = UserService.getInstance();
    // Install before journal repair or any session restoration. A failed fence prevents
    // its dependent account mutation; normal cold start preserves the original opt-in.
    users.setSessionInvalidationHook(async (reason: string): Promise<boolean> => {
      try {
        if (reason === 'logout' || reason === 'localReplacement') {
          await BackgroundTaskService.reset();
          await DailyNoteService.getInstance().clearCardSnapshot();
          return true;
        }
        if (!await BackgroundTaskService.stopAndInvalidate()) { return false; }
        await DailyNoteService.getInstance().clearCardSnapshot();
        return true;
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'background session fence failed');
        return false;
      }
    });
    await BackupService.getInstance().recoverInterruptedRestore();
    AppLocaleService.initialize();
    await Promise.all([GameDataService.initializeSnapshot(), users.restoreSession()]);
    PreferencesStore.bumpLaunchTimes();
    users.addSessionRevisionListener((): void => {
      if (!users.isSessionTransitionPending()) {
        EntryAbility.reconcileBackgroundTasks();
        if (EntryAbility.deferredServicesStarted) { EntryAbility.refreshForegroundNotes(); }
      }
    });
  }

  /** 页面已挂载后再启动联网维护和通知调度，冷启动只等待本地数据。 */
  private static startDeferredServices(): void {
    if (EntryAbility.deferredServicesStarted) { return; }
    EntryAbility.deferredServicesStarted = true;
    UserService.getInstance().refreshSession().catch((): void => {
      hilog.warn(DOMAIN, TAG, 'session refresh deferred');
    });
    NotificationHelper.init().then((): void => {
      EntryAbility.reconcileBackgroundTasks();
    }).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'notification initialization failed');
    });
    // These foreground preferences remain independent from explicit OS background opt-in.
    AutoSignInService.getInstance().bootstrapAutoSignIn().catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'auto sign in fail: %{public}s', e.message);
    });
    AutoSignInService.getInstance().setForeground(AppStorage.get<boolean>('appForeground') === true);
    DailyNoteService.getInstance().setForeground(AppStorage.get<boolean>('appForeground') === true);
    EntryAbility.refreshForegroundNotes();
  }

  private static async bootstrap(ability: EntryAbility, windowStage: window.WindowStage): Promise<void> {
    if (ability.windowStage !== windowStage || ability.startupPending) { return; }
    ability.startupPending = true;
    AppStorage.setOrCreate<boolean>('startupRetrying', true);
    try {
      await EntryAbility.initializeRuntime(ability.context);
      if (ability.windowStage !== windowStage) { return; }
      EntryAbility.applyStartupAppearance(ability);
      ability.startupErrorLoaded = false;
      await windowStage.loadContent('pages/Index');
      if (ability.windowStage !== windowStage) { return; }
      ability.stopStartupRetry();
      ability.configureImmersive(windowStage);
      ability.mountRiskVerifyOverlay();
      EntryAbility.startDeferredServices();
    } catch (e) {
      if (ability.windowStage !== windowStage) { return; }
      hilog.error(DOMAIN, TAG, 'startup fail: %{public}s', e instanceof Error ? e.message : JSON.stringify(e));
      EntryAbility.applyStartupAppearance(ability);
      ability.enableStartupRetry(windowStage);
      if (!ability.startupErrorLoaded) {
        try {
          // 保留已有错误页；loadContent 会销毁旧 UIContent，只在确有需要时加载。
          await windowStage.loadContent('pages/StartupErrorPage');
          if (ability.windowStage === windowStage) { ability.startupErrorLoaded = true; }
        } catch (loadError) {
          hilog.error(DOMAIN, TAG, 'load startup error page fail: %{public}s', JSON.stringify(loadError));
        }
      }
    } finally {
      if (ability.windowStage === windowStage) {
        ability.startupPending = false;
        AppStorage.setOrCreate<boolean>('startupRetrying', false);
      }
    }
  }

  private static applyStartupAppearance(ability: EntryAbility): void {
    try {
      // 恢复流程可能替换偏好；首次创建页面前读取最终值，避免首帧播放旧动效。
      Motion.setReducedMotion(PreferencesStore.getReduceMotionEnabled());
    } catch (e) {
      Motion.setReducedMotion(false);
      hilog.warn(DOMAIN, TAG, 'restore reduce motion preference fail');
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
  }

  onWindowStageWillDestroy(windowStage: window.WindowStage): void {
    // 此时窗口仍有效；到 onWindowStageDestroy 再注销可能已报 1300002。
    if (this.windowStage === windowStage) { this.releaseWindowResources(); }
  }

  onWindowStageDestroy(): void {
    this.releaseWindowResources();
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  private static reconcileBackgroundTasks(): void {
    BackgroundTaskService.reconcile().catch(() => {
      hilog.warn(DOMAIN, TAG, 'background scheduling failed');
    });
  }

  private static refreshForegroundNotes(): void {
    DailyNoteService.getInstance().bootstrapAutoRefresh().catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'foreground note refresh failed: %{public}s', e.message);
    });
  }

  onForeground(): void {
    AppStorage.setOrCreate('appForeground', true);
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
    if (!EntryAbility.deferredServicesStarted) { return; }
    AutoSignInService.getInstance().setForeground(true);
    DailyNoteService.getInstance().setForeground(true);
    EntryAbility.reconcileBackgroundTasks();
    // 回前台：定时器在后台可能被系统冻结，重新对齐并按需补刷（缓存超过刷新间隔才拉）
    EntryAbility.refreshForegroundNotes();
  }

  onBackground(): void {
    AppStorage.setOrCreate('appForeground', false);
    AutoSignInService.getInstance().setForeground(false);
    DailyNoteService.getInstance().setForeground(false);
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
    Logger.flush();
  }
}
