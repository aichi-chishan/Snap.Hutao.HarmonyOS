/**
 * Index.ets — Shell 导航壳（@Entry）
 * 官方 HdsTabs 悬浮页签（API23）：barFloatingStyle + systemMaterialEffect 沉浸光感，
 * 系统自带"手指到哪光到哪"的高亮滑块动画；底部悬浮不贴边。
 * 首页：每日背景（可开关）+ 登录状态 + 功能入口；我的：账号入口 + 设置。
 * 状态栏：自动读取本机状态栏高度（topAvoidVp），背景延伸、内容整体下移不重叠。
 */
import { router } from '@kit.ArkUI';
import { curves, display, window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { MiyoliveCode } from '../model/MiyoliveCode';
import { MiyoliveService } from '../service/MiyoliveService';
import { HdsTabs, HdsTabsController, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Motion } from '../common/Motion';
import { UiSurface, AppButtonModifier, CardSurfaceModifier, ShellSurfaceModifier } from '../common/UiSurface';
import { LoginStatusBar } from '../components/LoginStatusBar';
import { WallpaperLayer } from '../components/WallpaperLayer';
import { HomeHeroBanner } from '../components/HomeHeroBanner';
import { HomeUpdateNotice } from '../components/HomeUpdateNotice';
import { AppUpdateService } from '../service/AppUpdateService';
import { AppLocaleService } from '../service/AppLocaleService';
import { HomeGachaCard } from '../components/HomeGachaCard';
import { HomeDailyNoteCard } from '../components/HomeDailyNoteCard';
import { HomeSignInCard } from '../components/HomeSignInCard';
import { HomeAchievementCard } from '../components/HomeAchievementCard';
import { HomeLaunchCard } from '../components/HomeLaunchCard';
import { HomeTravelersDiaryCard } from '../components/HomeTravelersDiaryCard';
import { HomeActCard } from '../components/HomeActCard';
import { HomeAnnouncementCard } from '../components/HomeAnnouncementCard';
import { Announcement } from '../model/Announcement';
import { AnnouncementDetailParams } from '../model/RouteParams';
import { HomeGachaBannerCard } from '../components/HomeGachaBannerCard';
import { HomeActBannerCard } from '../components/HomeActBannerCard';
import { HomeCalendarCard } from '../components/HomeCalendarCard';
import lazy { GachaLogPage } from './GachaLogPage';
import lazy { DailyNotePage } from './DailyNotePage';
import lazy { CharacterPage } from './CharacterPage';
import lazy { SpiralAbyssPage } from './SpiralAbyssPage';
import { SignInPage } from './SignInPage';
import { CalendarPage } from './CalendarPage';
import { AnnouncementPage } from './AnnouncementPage';
import lazy { UserPage } from './UserPage';
import { SidebarAccountSwitcher } from '../components/SidebarAccountSwitcher';
import lazy { SettingPage } from './SettingPage';
import lazy { RoleCombatPage } from './RoleCombatPage';
import lazy { HardChallengePage } from './HardChallengePage';
import lazy { CultivationPage } from './CultivationPage';
import lazy { BackpackPage } from './BackpackPage';
import lazy { WishHistoryPage } from './WishHistoryPage';
import lazy { WikiAvatarPage } from './WikiAvatarPage';
import lazy { WikiWeaponPage } from './WikiWeaponPage';
import lazy { WikiMonsterPage } from './WikiMonsterPage';
import lazy { LedgerPage } from './LedgerPage';
import lazy { AchievementPage } from './AchievementPage';
import lazy { HutaoCloudPage } from './HutaoCloudPage';
import lazy { LaunchGamePage } from './LaunchGamePage';
import { NavIcon } from '../components/NavIcon';
import { PageContainer } from '../components/PageContainer';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { HomeViewModel } from '../viewmodel/HomeViewModel';
import { Logger } from '../common/Logger';
import { SignInService, SignInResult } from '../service/SignInService';
import { ChallengeSession } from '../service/ChallengeSession';
import { ActCalendarEntry, ActCalendarType } from '../model/ActCalendarEntry';
import { GachaHomeStatService, GachaArchiveStatPage, HomePoolSummary } from '../service/GachaHomeStatService';

/** 主页仪表板卡片规格（设置页可隐藏/重排，对齐 Windows SettingHomeCardViewModel） */
class DashCardSpec {
  key: string = '';
  name: string = '';
}

  @Entry
  @Component
  struct Index {
    /** 主页仪表盘数据容器 */
    @State homeVm: HomeViewModel = new HomeViewModel();
    @State homeSigning: boolean = false;
    @State todayDay: number = new Date().getDate();
    @StorageProp('officialSignInVersion') @Watch('onOfficialSignInClosed') officialSignInVersion: number = 0;
    /** 祈愿数据版本戳（祈愿页刷新成功后 bump；主页祈愿卡订阅重读本地库） */
    @StorageLink('gachaDataVersion') @Watch('onGachaDataChanged') gachaDataVersion: number = 0;
    /** 便笺数据版本戳（服务层自动刷新/桌面卡片刷新成功后 bump；主页便笺卡订阅重读本地库） */
    @StorageLink('dailyNoteVersion') @Watch('onNoteDataChanged') noteDataVersion: number = 0;
    @StorageProp('topAvoidVp') topAvoidVp: number = 0;
    @StorageProp('bottomAvoidVp') bottomAvoidVp: number = 0;
    @StorageProp('isDarkMode') isDark: boolean = false;
    @StorageProp('reduceMotion') reduceMotion: boolean = false;
    /** 当前选中页（宽屏 canonical 索引；手机页签索引独立存放于 phoneTab，跨断点互不串页） */
    @State currentIndex: number = 0;
    /** 手机底部页签索引（0=首页 1=祈愿 2=便笺 3=我的）；与 currentIndex 分离，避免跨 720vp 断点时错页 */
    @State phoneTab: number = 0;
    /** 宽屏侧边栏（>=840vp 平板/PC 显示） */
    @State isWide: boolean = false;
    /** 界面材质模式/级别（UiSurface 令牌层发布；设置页变更即时联动壳层——修复旧级别设置不生效） */
    @StorageProp('materialMode') materialModeNum: number = 0;
    @StorageProp('materialLevel') materialLevelNum: number = -1;
    /** 宽屏侧栏/标题栏沉浸材质（随材质模式/级别重建） */
    /** 每日背景开关 */
    /** 背景来源（none/local/bing，对齐 Windows 背景图片设置） */
    @StorageProp('bgType') bgType: string = 'local';
    @StorageProp('bgFolderPath') bgFolderPath: string = '';
    /** 是否深色模式（驱动每日背景渐变配色） */
    @StorageProp('isDarkMode') isDarkMode: boolean = false;
    /** 侧边栏折叠（仅图标），对齐 Windows CompactPaneLength=45 */
    @State sidebarFold: boolean = false;
    /** 首页下拉刷新状态 */
    @State homeRefreshing: boolean = false;
    /** 主页数据在途加载标记（reloadHome 防抖） */
    private homeReloading: boolean = false;
    private homeRequestSequence: number = 0;
    private gachaPagesSequence: number = 0;
    private stopWatchingHomeSession: (() => void) | undefined = undefined;
    /** 系统三键区（最小化/全屏/关闭）占位宽度 vp（PC 自定义窗口装饰；0=无系统三键） */
    @StorageProp('titleBtnWidthVp') titleBtnWidthVp: number = 0;
    @StorageProp('appVersion') appVersion: string = '';
    /** 主页内容区宽度（UniformPanel 式响应列数：列数 = floor((W+gap)/(minItem+gap))） */
    @State homeW: number = 0;
    @State homeViewportH: number = 0;
    /** 主页游戏活动区域设置（对齐 Windows：日历显示默认开 / 未在进行中活动默认关） */
    @StorageProp('homeActCalendarShown') homeActCalendarShown: boolean = true;
    @StorageProp('homeActPreview') homeActPreview: boolean = false;
    /** 主页卡片配置版本戳（设置页变更后 bump，触发卡片重排/显隐） */
    @StorageProp('homeCardsVersion') @Watch('onCardsVersionChanged') homeCardsVersion: number = 0;
    /** 主页仪表板卡片（按用户顺序、过滤隐藏；对齐 Windows HomeCards） */
    @State dashCards: DashCardSpec[] = [];
    /** 欢迎语文案（对齐 Windows GreetingText：随机彩蛋 / 启动次数） */
    @State greeting: ResourceStr = $r('app.string.ui_home_greeting');
    /** 前瞻直播兑换码弹层（对齐 Windows 主页兑换码 Flyout） */
    @State showHomeCodes: boolean = false;
    /** 祈愿多归档翻页数据（归档数 >= 2 才填充；单归档卡片走原单 UID 路径） */
    @State gachaPages: GachaArchiveStatPage[] = [];
    @State homeCodes: MiyoliveCode[] = [];
    @State homeCodesLoading: boolean = false;
    /** 是否正在通过自绘 TitleBar 拖拽窗口（避免重复触发 startMoving） */
    private windowDragging: boolean = false;
    private controller: HdsTabsController = new HdsTabsController();

    aboutToAppear(): void {
      AppLocaleService.initialize();
      AppStorage.setOrCreate<string>('appUpdateSkippedTag', AppUpdateService.skippedTag());
      AppUpdateService.startupCheck();
      AppStorage.setOrCreate<string>('bgType', PreferencesStore.getBackgroundImageType());
    AppStorage.setOrCreate<boolean>('homeActCalendarShown', PreferencesStore.getHomeActCalendar());
    AppStorage.setOrCreate<boolean>('homeActPreview', PreferencesStore.getHomeActPreview());
      AppStorage.setOrCreate<string>('bgFolderPath', PreferencesStore.getBackgroundFolderPath());
      // 立即检测宽屏（PC/平板>普通手机）：屏幕宽度 vp 判断，避免等待 onAreaChange 首帧
      this.isWide = Index.detectWideScreen();
      this.greeting = Index.pickGreeting();
      this.loadDashCards();
      if (this.stopWatchingHomeSession === undefined) {
        this.stopWatchingHomeSession = this.homeVm.watchSession((): void => { this.reloadHome(true); });
      }
      this.reloadHome();
    }

    aboutToDisappear(): void {
      this.stopWatchingHomeSession?.();
      this.stopWatchingHomeSession = undefined;
      this.homeVm.invalidate();
      this.homeRequestSequence++;
      this.gachaPagesSequence++;
      this.homeReloading = false;
    }

    /**
     * 欢迎语文案（对齐 Windows AnnouncementViewModel.UpdateGreetingTextCore）：
     * 0.6% 彩蛋；其余显示启动次数（首启保留欢迎语）
     */
    private static pickGreeting(): ResourceStr {
      if (Math.random() * 1000 < 6) {
        return $r('app.string.ui_home_greeting_rare');
      }
      const times: number = PreferencesStore.getLaunchTimes();
      return times > 1 ? $r('app.string.ui_home_greeting_count', String(times)) : $r('app.string.ui_home_greeting');
    }

    /** 打开兑换码弹层（首次打开时拉取，无需登录） */
    openHomeCodes(): void {
      this.showHomeCodes = true;
      if (this.homeCodes.length > 0 || this.homeCodesLoading) {
        return;
      }
      this.homeCodesLoading = true;
      MiyoliveService.getInstance().fetchRedeemCodes().then((codes: MiyoliveCode[]) => {
        this.homeCodes = codes;
      }).catch(() => {
        // 拉取失败保持空列表（弹层内提示暂无）
      }).finally(() => {
        this.homeCodesLoading = false;
      });
    }

    /** 复制兑换码 */
    private copyHomeCode(code: string): void {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(),
          message: $r('app.string.ui_code_copied'), duration: 1500 });
      });
    }

    /** 兑换码弹层（遮罩 + 居中卡片，对齐 AnnouncementPage codeSheet 行布局） */
    @Builder
    homeCodeSheet() {
      if (this.showHomeCodes) {
        Column() {
          Column({ space: 10 }) {
            Text($r('app.string.ui_announcement_redeem_code_label'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Scroll() {
              Column({ space: 8 }) {
                if (this.homeCodesLoading) {
                  Text($r('app.string.ui_common_loading'))
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding({ top: 20, bottom: 20 })
                } else if (this.homeCodes.length === 0) {
                  Text($r('app.string.ui_home_no_codes'))
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding({ top: 20, bottom: 20 })
                } else {
                  ForEach(this.homeCodes, (c: MiyoliveCode) => {
                    Row({ space: 10 }) {
                      Column({ space: 2 }) {
                        Text(c.title)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(c.code)
                          .fontSize(16)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .letterSpacing(1)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                      Text($r('app.string.ui_settings_page_label_copy_profile'))
                        .fontSize(12)
                        .fontColor($r('app.color.app_primary_text'))
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .borderRadius(10)
                        .border({ width: 1, color: $r('app.color.app_primary') })
                        .hoverEffect(HoverEffect.Highlight)
                        .onClick(() => {
                          this.copyHomeCode(c.code);
                        })
                    }
                    .width('100%')
                    .padding(10)
                    .borderRadius(10)
                    .backgroundColor($r('app.color.page_background'))
                    .border({ width: 1, color: $r('app.color.divider') })
                  }, (c: MiyoliveCode) => `hcode_${c.code}`)
                }
              }
              .width('100%')
            }
            .width('100%')
            .constraintSize({ maxHeight: 320 })
            .scrollBar(BarState.Auto)
            Button($r('app.string.ui_exception_close'))
              .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum))
              .constraintSize({ minHeight: 44 })
              .width('100%')
              .onClick(() => {
                this.showHomeCodes = false;
              })
          }
          .width(360)
          .padding(16)
          .borderRadius(16)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .border({ width: 1, color: $r('app.color.card_stroke') })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay_scrim'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.showHomeCodes = false;
        })
      }
    }

    /** 从设置页返回本页时重读卡片配置（路由返回不走 aboutToAppear） */
    onPageShow(): void {
      this.loadDashCards();
    }

    /** 设置页 bump 版本戳后重读卡片配置 */
    onCardsVersionChanged(): void {
      this.loadDashCards();
    }

    /** 读取主页卡片配置：按用户顺序排序并过滤隐藏（对齐 Windows Dashboard 卡组构建） */
    loadDashCards(): void {
      const cards: DashCardSpec[] = [];
      for (let i = 0; i < PreferencesStore.HOME_CARD_KEYS.length; i++) {
        const key: string = PreferencesStore.HOME_CARD_KEYS[i];
        if (!PreferencesStore.getHomeCardPresented(key)) {
          continue;
        }
        const spec: DashCardSpec = new DashCardSpec();
        spec.key = key;
        spec.name = PreferencesStore.HOME_CARD_NAMES[i];
        cards.push(spec);
      }
      cards.sort((a: DashCardSpec, b: DashCardSpec) => {
        return PreferencesStore.getHomeCardOrder(a.key) - PreferencesStore.getHomeCardOrder(b.key);
      });
      this.dashCards = cards;
    }

    /** 卡片是否在当前配置中显示（手机端堆叠卡用） */
    dashCardVisible(key: string): boolean {
      for (const c of this.dashCards) {
        if (c.key === key) {
          return true;
        }
      }
      return false;
    }

    /** 聚合加载主页仪表盘数据（祈愿/便笺/签到/活动/公告） */
    reloadHome(force: boolean = false): void {
      const uid: string = AppStorage.get<string>('currentUid') ?? '';
      if (!force && this.homeReloading && this.homeVm.currentUid === uid) {
        return; // 在途加载中：避免连点/快速切页重复拉网络
      }
      const sequence: number = ++this.homeRequestSequence;
      this.homeReloading = true;
      this.todayDay = new Date().getDate();
      this.loadGachaPages();
      this.homeVm.load(uid).then((accepted: boolean): void => {
        if (!accepted || sequence !== this.homeRequestSequence) { return; }
        Logger.info('Index', 'home data loaded');
        this.homeRefreshing = false;
        this.homeReloading = false;
      }).catch(() => {
        if (sequence !== this.homeRequestSequence) { return; }
        this.homeRefreshing = false;
        this.homeReloading = false;
      });
    }

    /** 祈愿多归档翻页数据重载（仅读本地库；归档数 >= 2 才启用翻页） */
    loadGachaPages(): void {
      const sequence: number = ++this.gachaPagesSequence;
      GachaHomeStatService.loadArchivePages().then((pages: GachaArchiveStatPage[]) => {
        if (sequence === this.gachaPagesSequence) { this.gachaPages = pages.length >= 2 ? pages : []; }
      }).catch((e: Error) => {
        if (sequence !== this.gachaPagesSequence) { return; }
        Logger.warn('Index', `load gacha pages fail: ${e.message}`);
        this.gachaPages = [];
      });
    }

    /** 祈愿页刷新成功：主页祈愿卡重读本地库 */
    onGachaDataChanged(): void {
      const uid: string = AppStorage.get<string>('currentUid') ?? '';
      this.homeVm.reloadGacha(uid).then(() => {
      });
      this.loadGachaPages();
    }

    /** 便笺刷新成功：主页便笺卡重读本地库（不触发其他数据源网络请求） */
    onNoteDataChanged(): void {
      const uid: string = AppStorage.get<string>('currentUid') ?? '';
      this.homeVm.reloadNote(uid).then(() => {
      });
    }

    onOfficialSignInClosed(): void { this.reloadHome(true); }

    /** 主页签到（直接调用服务） */
    async doHomeSignIn(): Promise<void> {
      if (this.homeSigning) {
        return;
      }
      const uid: string = AppStorage.get<string>('currentUid') ?? '';
      const owner: ChallengeSession | undefined = ChallengeSession.capture(uid);
      if (owner === undefined) {
        this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(),
          message: $r('app.string.ui_account_insights_no_account') });
        return;
      }
      this.homeSigning = true;
      try {
        let result: SignInResult = new SignInResult();
        try { result = await SignInService.getInstance().sign(uid); }
        catch (error) { result.message = (error as Error).message; }
        if (!owner.isCurrent()) { return; }
        if (result.message.length > 0) {
          this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: result.message });
        }
        if (result.shouldOpenOfficialPage()) {
          await router.pushUrl({ url: 'pages/OfficialWebPage', params: { kind: 'sign-in' } });
        } else {
          this.reloadHome(true);
        }
      } catch (error) {
        if (owner.isCurrent()) {
          this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: (error as Error).message });
        }
      } finally {
        this.homeSigning = false;
      }
    }

  /** 屏幕宽度 vp（异常回退 0） */
  private static detectWidthVp(): number {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const dp: number = d.densityPixels;
      const widthPx: number = d.width;
      return dp > 0 ? widthPx / dp : widthPx;
    } catch (e) {
      return 0;
    }
  }

  /** 宽屏检测：屏幕宽度 vp >= 720 视为平板/PC（壳层侧边栏阈值；页面内容区用 840，见 AGENTS.md 断点规范） */
  private static detectWideScreen(): boolean {
    return Index.detectWidthVp() >= Index.WIDE_VP;
  }

  /** 通过自绘 TitleBar 拖拽移动窗口（接管被隐藏的系统标题栏拖拽能力） */
  private startWindowMoving(): void {
    if (this.windowDragging) {
      return;
    }
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    this.windowDragging = true;
    window.getLastWindow(ctx).then((win: window.Window) => {
      win.startMoving().catch(() => {
      });
    }).catch(() => {
    }).finally(() => {
      this.windowDragging = false;
    });
  }

  /** 在渲染时读取响应式属性，侧栏与悬浮页签使用同一份设置。 */
  private panelMaterial(): ShellSurfaceModifier {
    return new ShellSurfaceModifier(this.materialModeNum, this.materialLevelNum);
  }

  private navPaneWidth(): number {
    return this.sidebarFold ? 52 : 208;
  }

  /** HDS 的普通模式显式关闭材质；手动档位按设备能力选取。 */
  materialEffect(): SystemMaterialParams {
    if (this.materialModeNum !== 1 || !canIUse('SystemCapability.UIDesign.HDSComponent.Core')) {
      return { materialType: hdsMaterial.MaterialType.NONE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE };
    }
    let level: hdsMaterial.MaterialLevel =
      this.materialLevelNum === 2 ? hdsMaterial.MaterialLevel.EXQUISITE
        : (this.materialLevelNum === 1 ? hdsMaterial.MaterialLevel.GENTLE
          : (this.materialLevelNum === 0 ? hdsMaterial.MaterialLevel.SMOOTH
            : hdsMaterial.MaterialLevel.ADAPTIVE));
    let type: hdsMaterial.MaterialType = hdsMaterial.MaterialType.ADAPTIVE;
    if (level !== hdsMaterial.MaterialLevel.ADAPTIVE) {
      try {
        if (hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE)) {
          type = hdsMaterial.MaterialType.IMMERSIVE;
        } else { level = hdsMaterial.MaterialLevel.SMOOTH; }
      } catch (_) { level = hdsMaterial.MaterialLevel.SMOOTH; }
    }
    const cfg: SystemMaterialParams = {
      materialType: type,
      materialLevel: level,
    };
    return cfg;
  }

  /**
   * 手机底部页签 → 宽屏 canonical 索引。
   * 手机页签语义固定为 0=首页 1=祈愿 2=便笺 3=我的；宽屏索引是页面标识。
   * 二者不再共用一个数字，跨 720vp 断点切换不会错页（对齐 Windows：窗口尺寸不改变业务页面）。
   */
  private static phoneTabToIndex(tab: number): number {
    if (tab === 0) { return 0; }
    if (tab === 1) { return 1; }
    if (tab === 2) { return 3; }
    return -1;
  }

  /** 宽屏 canonical 索引 → 手机底部页签（-1 = 手机无对应页签，例如宽屏独有的图鉴/挑战页） */
  private static indexToPhoneTab(index: number): number {
    if (index === 0) { return 0; }
    if (index === 1) { return 1; }
    if (index === 3) { return 2; }
    return -1;
  }

  /** 断点切换后把手机页签对齐到当前业务页面，避免宽→窄时停留在上一次的页签 */
  private syncPhoneTabForCurrentPage(): void {
    if (this.isWide) {
      return;
    }
    const tab: number = Index.indexToPhoneTab(this.currentIndex);
    if (tab >= 0 && tab !== this.phoneTab) {
      this.phoneTab = tab;
      this.controller.changeIndex(tab);
    }
  }

  /** 内容切换（统一入口）：animateTo 驱动 geometryTransition 指示条与页面转场 */
  private switchTo(index: number): void {
    if (this.reduceMotion) {
      this.currentIndex = index;
    } else {
      this.getUIContext().animateTo({ curve: Motion.springSoft() }, () => {
        this.currentIndex = index;
      });
    }
    // 切回主页自动拉新数据（对齐 Windows；替代下拉刷新——模拟器 Refresh+Scroll 嵌套渲染异常）
    if (index === 0) {
      this.reloadHome();
    }
  }

  /**
   * 窄屏切页：底部页签与业务页面必须一起变，二者索引语义不同（见 phoneTabToIndex）。
   * 宽屏走 switchTo；此处是手机唯一入口，避免两套索引各自漂移。
   */
  private switchPhoneTab(tab: number): void {
    this.phoneTab = tab;
    const mapped: number = Index.phoneTabToIndex(tab);
    if (mapped >= 0) {
      this.currentIndex = mapped;
    }
    this.controller.changeIndex(tab);
    if (mapped === 0) {
      this.reloadHome();
    }
  }

  private toggleSidebar(): void {
    if (this.reduceMotion) {
      this.sidebarFold = !this.sidebarFold;
    } else {
      this.getUIContext().animateTo({ curve: Motion.springSoft() }, () => {
        this.sidebarFold = !this.sidebarFold;
      });
    }
  }

  build() {
    if (this.isWide) {
      this.wideShell()
    } else {
      this.phoneShell()
    }
  }

  /** 宽窄判定统一阈值（vp）：与 detectWideScreen 一致，避免 720/840 竞态 */
  private static readonly WIDE_VP: number = 720;

  /** 窄屏：底部 HdsTabs 悬浮页签（手机）；最底全屏壁纸层，内容/悬浮页签浮上（对齐 Windows 透明页面栈） */
  @Builder
  phoneShell() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 全屏壁纸层（手机壳最底层，与宽屏壳同构；渐变 + 本地胡桃横幅 + 可选）
      WallpaperLayer({ bgType: this.bgType, folderPath: this.bgFolderPath })

      HdsTabs({ controller: this.controller }) {
        TabContent() {
          this.homeTab()
        }
        .tabBar(this.bottomTab(0, 'Announcement', $r('app.string.tab_home')))

        TabContent() {
          this.gachaTab()
        }
        .tabBar(this.bottomTab(1, 'GachaLog', $r('app.string.tab_gacha')))

        TabContent() {
          this.noteTab()
        }
        .tabBar(this.bottomTab(2, 'DailyNote', $r('app.string.tab_note')))

        TabContent() {
          this.mineTab()
        }
        .tabBar(this.bottomTab(3, 'Passport', $r('app.string.tab_mine')))
      }
      .barOverlap(true)
      .vertical(false)
      .barPosition(BarPosition.End)
      .onChange((index: number) => {
        // 手机页签索引独立记录；同时把 canonical 索引映射为对应业务页面，
        // 保证切回宽屏时仍是同一个业务页面（此前两者共用一个数字导致跨断点错页）
        this.phoneTab = index;
        // 「我的」是手机独有页签，无宽屏对应页：此时保留上一个业务页面，
        // 避免把 canonical 索引置为无效值导致切回宽屏后落到错误页面。
        const mapped: number = Index.phoneTabToIndex(index);
        if (mapped >= 0) {
          this.currentIndex = mapped;
        }
      })
      .barFloatingStyle({
        barBottomMargin: 20,
        gradientMask: { maskColor: $r('app.color.mask_scrim'), maskHeight: 96 },
        // API<26 传 IMMERSIVE 材质参数不生效：只在 API26+ 传入，低版本回退 barBackgroundBlurStyle
        systemMaterialEffect: this.materialEffect(),
      })
      // 普通材质（或 API<26 材质不可用）时悬浮页签用系统组件材质 COMPONENT_THICK
      // 给半透明玻璃底兜底；沉浸材质生效路径用 NONE 不叠加
      .barBackgroundBlurStyle(this.materialEffect().materialType === hdsMaterial.MaterialType.NONE
        ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE, {
        colorMode: this.isDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT,
      })
      .barBackgroundColor(Color.Transparent)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const w: number = newValue.width as number;
        const wasWide: boolean = this.isWide;
        this.isWide = w >= Index.WIDE_VP;
        if (wasWide !== this.isWide) {
          this.syncPhoneTabForCurrentPage();
        }
        // 窗口不足平板宽（<840）时自动折叠侧栏（图标态）给内容让位；用户此后可手动展开，
        // 仅在宽度变化跨越时触发，不与手动操作打架
        if (w > 0 && w < 840) {
          this.sidebarFold = true;
        }
      })
    }
    .width('100%')
    .height('100%')
  }

  /** 宽屏：全屏壁纸底 + 顶部自定义 TitleBar + 左侧分组导航（可折叠）+ 右侧内容区 */
  @Builder
  wideShell() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 全屏壁纸层（覆盖整个窗口，含侧边栏与标题栏底下）
      WallpaperLayer({ bgType: this.bgType, folderPath: this.bgFolderPath })
      this.shellBackdrop()

      Column() {
        // 顶部 TitleBar：返回按钮 / 三条杠（折叠侧栏） / 版本号 / 窗口控制按钮
        this.topBar()

        Row() {
          // 左侧导航（可折叠：图标-ONLY 或 图标+文字）
          this.sideNav()

          // 右侧内容区（嵌入页面组件）
          Column() {
            this.wideContent()
          }
          .layoutWeight(1)
          .height('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height('100%')
      // 沉浸式窗口的状态栏由内容层避让，壁纸保持全屏；标题栏自身仍为 40vp。
      .padding({ top: this.topAvoidVp })

      // 底部指示点：内容区背景半透明达标的视觉 (宽屏无底部tab，保留)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      // 与 phoneShell 同阈值：窗口缩到 <720vp 时切回窄屏（2in1 旋转/缩放）
      const w: number = newValue.width as number;
      const wasWide: boolean = this.isWide;
      this.isWide = w >= Index.WIDE_VP;
      if (wasWide !== this.isWide) {
        this.syncPhoneTabForCurrentPage();
      }
      // 窗口不足平板宽（<840）时自动折叠侧栏（图标态）给内容让位；用户此后可手动展开，
      // 仅在宽度变化跨越时触发，不与手动操作打架
      if (w > 0 && w < 840) {
        this.sidebarFold = true;
      }
    })
  }

  /** 顶部与侧栏共用连续的轻磨砂，两块背景不相叠；前景只负责布局和交互。 */
  @Builder
  shellBackdrop() {
    Column() {
      Column()
        .width('100%')
        .height(this.topAvoidVp + 40)
        .attributeModifier(this.panelMaterial())
      Row() {
        Column()
          .width(this.navPaneWidth())
          .height('100%')
          .attributeModifier(this.panelMaterial())
          .border({ width: { right: 0.5 }, color: $r('app.color.nav_border') })
        Blank().layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
  }

  /** 顶部自定义 TitleBar：系统标题栏已由 setWindowDecorVisible(false) 隐藏，
   *  与侧栏共用 shellBackdrop；左侧=全局返回/折叠侧栏/版本号，右侧=系统三键保留区。 */
  @Builder
  topBar() {
    Row({ space: 4 }) {
      // 返回按钮（全局返回上一步）
      Stack({ alignContent: Alignment.Center }) {
        Text('‹')
          .fontSize(20)
          .fontColor($r('app.color.text_primary'))
      }
      .width(36)
      .height(36)
      .borderRadius(8)
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText($r('app.string.ui_plugin_setting_back_button'))
      .accessibilityLevel('yes')
      .onClick(() => {
        const state = router.getState();
        const idx: number = state !== undefined ? state.index : 1;
        if (idx > 1) {
          // 有 router 深层页面：先返回
          router.back();
        } else {
          // 内嵌页面（侧边栏切换）：回主页
          this.switchTo(0);
        }
      })

      // 三条杠（折叠侧栏：仅图标 / 图标+文字）；用系统符号替代 emoji，跟随主题色
      Stack({ alignContent: Alignment.Center }) {
        NavIcon({ name: 'Menu', iconSize: 22, symbolColor: $r('app.color.text_primary') })
      }
      .width(36)
      .height(36)
      .borderRadius(8)
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText(this.sidebarFold ? $r('app.string.ui_navigation_expand') : $r('app.string.ui_navigation_collapse'))
      .accessibilityLevel('yes')
      .onClick(() => {
        this.toggleSidebar();
      })

      // 版本号（胡桃 x.y.z，来自 bundleManager versionName）
      Text(`胡桃 ${this.appVersion}`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .padding({ left: 6, right: 10, top: 2, bottom: 2 })

      Blank()

      // 右侧：系统三键保留区（最小化/全屏/关闭由系统窗口装饰绘制，宽度动态避让）
      Row()
        .width(this.titleBtnWidthVp)
        .height('100%')
    }
    .width('100%')
    // 材质由同级 shellBackdrop 提供，避免顶栏与侧栏交界处重复叠加。
    .height(40)
    .padding({ left: 6, right: 0 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .onTouch((event: TouchEvent) => {
      // 拖拽移动窗口：接管被隐藏系统标题栏的拖拽（点击按钮不受影响）
      if (event.type === TouchType.Move) {
        this.startWindowMoving();
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.windowDragging = false;
      }
    })
  }

  /** 左侧导航栏（折叠：仅图标 48px；展开：图标+文字 208px） */
  @Builder
  sideNav() {
    Column({ space: 2 }) {
      Scroll() {
        Column({ space: 2 }) {
          // 主页项独立顶置（不放在任何小标题下）；其下紧邻「胡桃通行证」（对齐 Windows 置顶组）
          this.navItemHome(0)
          this.navItem(16, 'Passport', $r('app.string.ui_nav_passport'))

          this.navSectionTitle($r('app.string.ui_group_tools'))
          this.navItem(14, 'LaunchGame', $r('app.string.ui_nav_launch'))
          this.navItem(1, 'GachaLog', $r('app.string.page_title_gacha'))
          this.navItem(2, 'Achievement', $r('app.string.ui_nav_achievement'))
          this.navItem(3, 'DailyNote', $r('app.string.page_title_note'))
          this.navItem(4, 'AvatarProperty', $r('app.string.ui_nav_character'))
          this.navItem(17, 'Backpack', $r('app.string.ui_nav_backpack'))
          this.navItem(5, 'Cultivation', $r('app.string.ui_nav_cultivation'))

          this.navSectionTitle($r('app.string.ui_group_period'))
          this.navItem(6, 'SpiralAbyss', $r('app.string.ui_nav_abyss'))
          this.navItem(7, 'RoleCombat', $r('app.string.ui_nav_theater'))
          this.navItem(8, 'HardChallenge', $r('app.string.ui_nav_challenge'))

          this.navSectionTitle($r('app.string.ui_group_data'))
          this.navItem(9, 'WikiAvatar', $r('app.string.ui_nav_wiki_avatar'))
          this.navItem(10, 'WikiWeapon', $r('app.string.ui_nav_wiki_weapon'))
          this.navItem(11, 'WikiMonster', $r('app.string.ui_nav_wiki_monster'))
        }
        .width('100%')
        .padding({ left: this.sidebarFold ? 4 : 8, right: this.sidebarFold ? 4 : 8, top: 8, bottom: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(Color.Transparent)
      Column({ space: 2 }) {
        SidebarAccountSwitcher({ compact: this.sidebarFold, onOpenAccounts: (): void => { this.switchTo(12); } })
        this.navItem(13, 'Setting', $r('app.string.page_title_setting'))
      }
      .width('100%')
      .padding({ left: this.sidebarFold ? 4 : 8, right: this.sidebarFold ? 4 : 8, bottom: 8 })
    }
    .width(this.navPaneWidth())
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  /** 主页导航项（置顶，Windows Announcement 彩色图标；选中态=左侧强调色指示条） */
  @Builder
  navItemHome(index: number) {
    Row({ space: this.sidebarFold ? 3 : 10 }) {
      Column()
        .width(3)
        .height(18)
        .borderRadius(2)
        .backgroundColor(this.currentIndex === index ? $r('app.color.app_primary') : Color.Transparent)
        .geometryTransition(!this.reduceMotion && this.currentIndex === index ? 'navIndicator' : '')
      NavIcon({ name: 'Announcement', iconSize: 24 })
      if (!this.sidebarFold) {
        Text($r('app.string.page_title_home'))
          .fontSize(15)
          .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor($r('app.color.text_primary'))
          .transition(this.reduceMotion ? TransitionEffect.IDENTITY.animation({ duration: 0 }) :
            TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }
      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: this.sidebarFold ? 4 : 10, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.currentIndex === index ? $r('app.color.nav_selected') : Color.Transparent)
    .hoverEffect(HoverEffect.Highlight)
    .animation(this.reduceMotion ? { duration: 0 } : { curve: Motion.springFast() })
    .onClick(() => {
      this.switchTo(index);
    })
  }

  @Builder
  navSectionTitle(title: ResourceStr) {
    if (this.sidebarFold) {
      Blank().height(8)
    } else {
      Text(title)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 4 })
    }
  }

  @Builder
  navItem(index: number, icon: string, label: ResourceStr) {
    Row({ space: this.sidebarFold ? 3 : 10 }) {
      // 左侧强调色指示条（对齐 Windows NavigationView 选中态；geometryTransition 弹性形变滑动）
      Column()
        .width(3)
        .height(18)
        .borderRadius(2)
        .backgroundColor(this.currentIndex === index ? $r('app.color.app_primary') : Color.Transparent)
        .geometryTransition(!this.reduceMotion && this.currentIndex === index ? 'navIndicator' : '')
      if (Index.isEmoji(icon)) {
        Text(icon)
          .fontSize(18)
          .width(24)
          .textAlign(TextAlign.Center)
      } else {
        NavIcon({ name: icon, iconSize: 24 })
      }
      if (!this.sidebarFold) {
        Text(label)
          .fontSize(15)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor($r('app.color.text_primary'))
          .transition(this.reduceMotion ? TransitionEffect.IDENTITY.animation({ duration: 0 }) :
            TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
      }
      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: this.sidebarFold ? 4 : 10, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.currentIndex === index ? $r('app.color.nav_selected') : Color.Transparent)
    .hoverEffect(HoverEffect.Highlight)
    .animation(this.reduceMotion ? { duration: 0 } : { curve: Motion.springFast() })
    .onClick(() => {
      this.switchTo(index);
    })
  }

  /** icon 参数是否为 emoji（emoji 走 Text，否则走 rawfile 图） */
  private static isEmoji(icon: string): boolean {
    // emoji 码点判断：首个字符 FD 以上（>0x1F000）或常见 emoji 区
    const code: number = icon.length > 0 ? icon.codePointAt(0) ?? 0 : 0;
    return code > 0x2100;
  }

  /** 宽屏内容区：直接内嵌页面组件（embedMode 去返回栏），背景透传全屏壁纸层，
   *  仅由页面内卡片等实体元素遮盖壁纸（对齐 Windows 版透背景效果） */
  @Builder
  wideContent() {
    Column() {
      if (this.currentIndex === 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          PageContainer() {
            this.homeTabWide()
            }
          this.homeCodeSheet()
        }
      } else if (this.currentIndex === 1) {
        PageContainer() {
          this.gachaTab()
          }
      } else if (this.currentIndex === 2) {
        PageContainer() {
          AchievementPage({ embedMode: true })
          }
      } else if (this.currentIndex === 3) {
        PageContainer() {
          this.noteTab()
          }
      } else if (this.currentIndex === 4) {
        PageContainer() {
          CharacterPage({ embedMode: true })
          }
      } else if (this.currentIndex === 5) {
        PageContainer() {
          CultivationPage({ embedMode: true })
          }
      } else if (this.currentIndex === 6) {
        PageContainer() {
          SpiralAbyssPage({ embedMode: true })
          }
      } else if (this.currentIndex === 7) {
        PageContainer() {
          RoleCombatPage({ embedMode: true })
          }
      } else if (this.currentIndex === 8) {
        PageContainer() {
          HardChallengePage({ embedMode: true })
          }
      } else if (this.currentIndex === 9) {
        PageContainer() {
          WikiAvatarPage({ embedMode: true })
          }
      } else if (this.currentIndex === 10) {
        PageContainer() {
          WikiWeaponPage({ embedMode: true })
          }
      } else if (this.currentIndex === 11) {
        PageContainer() {
          WikiMonsterPage({ embedMode: true })
          }
      } else if (this.currentIndex === 12) {
        PageContainer() {
          UserPage({ embedMode: true })
          }
      } else if (this.currentIndex === 14) {
        PageContainer() {
          LaunchGamePage({ embedMode: true })
          }
      } else if (this.currentIndex === 18) {
        PageContainer() {
          WishHistoryPage({ embedMode: true })
        }
      } else if (this.currentIndex === 17) {
        PageContainer() {
          BackpackPage({ embedMode: true })
        }
      } else if (this.currentIndex === 16) {
        PageContainer() {
          HutaoCloudPage({ embedMode: true })
        }
      } else if (this.currentIndex === 15) {
        PageContainer() {
          LedgerPage({ embedMode: true })
          }
      } else {
        PageContainer() {
          SettingPage({ embedMode: true })
          }
      }
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(Color.Transparent)
  }

  @Builder
  bottomTab(index: number, icon: string, label: ResourceStr) {
    Column({ space: 2 }) {
      Image(NavIcon.resolve(icon))
        .width(52)
        .height(30)
        .objectFit(ImageFit.Contain)
        .backgroundColor(this.currentIndex === index ? $r('app.color.app_primary_bg') : Color.Transparent)
      Text(label)
        .fontSize(11)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .animation(this.reduceMotion ? { duration: 0 } : { curve: Motion.springFast() })
  }

  /** All form factors consume the same ordered/visible dashboard card configuration. */
  @Builder
  dashboardCard(key: string) {
              if (key === 'launch') {
                HomeLaunchCard({
                  fillHeight: this.isWide,
                  onLaunched: (ok: boolean, message: string) => {
                    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: message, duration: 2200 });
                  },
                })
              } else if (key === 'gacha') {
                HomeGachaCard({
                  fillHeight: this.isWide,
                  uid: this.homeVm.gachaUid,
                  pools: this.homeVm.gachaPools,
                  loaded: this.homeVm.gachaLoaded,
                  pages: this.gachaPages,
                  onTap: () => {
                    if (this.isWide) { this.switchTo(1); } else { this.switchPhoneTab(1); }
                  },
                })
              } else if (key === 'achievement') {
                HomeAchievementCard({
                  fillHeight: this.isWide,
                  onTap: () => {
                    if (this.isWide) { this.switchTo(2); } else { router.pushUrl({ url: 'pages/AchievementPage' }); }
                  },
                })
              } else if (key === 'dailynote') {
                HomeDailyNoteCard({
                  fillHeight: this.isWide,
                  entries: this.homeVm.noteEntries,
                  loaded: this.homeVm.noteLoaded,
                  refreshing: this.homeVm.noteRefreshing,
                  onRefresh: () => {
                    this.homeVm.refreshNotes().then((message: string) => {
                      if (message.length > 0) {
                        this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: message });
                      }
                    }).catch((error: Error) => {
                      this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: error.message });
                    });
                  },
                  onTap: () => {
                    if (this.isWide) { this.switchTo(3); } else { this.switchPhoneTab(2); }
                  },
                })
              } else if (key === 'ledger') {
                HomeTravelersDiaryCard({
                  fillHeight: this.isWide,
                  onTap: () => {
                    if (this.isWide) { this.switchTo(15); } else { router.pushUrl({ url: 'pages/LedgerPage' }); }
                  },
                })
              } else if (key === 'calendar') {
                HomeCalendarCard({
                  fillHeight: this.isWide,
                  eventDays: this.calendarEventDays(),
                  todayActs: this.todayActNames(),
                  onTap: () => {
                    router.pushUrl({ url: 'pages/CalendarPage' });
                  },
                })
              } else {
                HomeSignInCard({
                  fillHeight: this.isWide,
                  uid: this.homeVm.currentUid,
                  info: this.homeVm.signInfo,
                  loaded: this.homeVm.signLoaded,
                  signing: this.homeSigning,
                  todayDay: this.todayDay,
                  onTap: () => {
                    router.pushUrl({ url: 'pages/SignInPage' });
                  },
                  onSignIn: () => {
                    this.doHomeSignIn();
                  },
                  onResignIn: () => {
                    router.pushUrl({ url: 'pages/SignInPage' });
                  },
                })
              }
  }

  @Builder
  homeTab() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 壁纸层已上移至 phoneShell 最底（全 Tab 共享一份，避免双份加载）；此处仅内容 + 弹层
      Scroll() {
        Column({ space: 12 }) {
          // 欢迎横幅（对齐电脑版主页顶部；文案含随机彩蛋，对齐 Windows GreetingText）
          HomeHeroBanner({ title: this.greeting })

          LoginStatusBar()

          HomeUpdateNotice()

          ForEach(this.dashCards, (spec: DashCardSpec) => {
            this.dashboardCard(spec.key)
          }, (spec: DashCardSpec) => spec.key)

          if (this.homeActCalendarShown) {
            // 手机和宽屏共享活动开关及预告过滤。
            Row() {
              Text($r('app.string.ui_home_recent'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text($r('app.string.ui_section_calendar'))
                .fontSize(12)
                .fontColor($r('app.color.app_primary_text'))
                .onClick(() => {
                  router.pushUrl({ url: 'pages/CalendarPage' });
                })
            }
            .width('100%')

            if (this.phoneActivities().length > 0) {
              Grid() {
                ForEach(this.phoneActivities(), (act: ActCalendarEntry) => {
                  GridItem() {
                    HomeActCard({
                      entry: act,
                      onTap: () => {
                        router.pushUrl({ url: 'pages/CalendarPage' });
                      },
                    })
                  }
                }, (act: ActCalendarEntry) => `home_act_${act.id}_${act.type}_${act.name}_${act.startTime}_${act.endTime}_${act.avatarIcons.join('|')}_${act.weaponIcons.join('|')}`)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(10)
              .rowsGap(10)
              .width('100%')
              // 行高由内容决定（窄屏卡高自适应），Grid 默认 clip=true 会裁掉首末行卡片的阴影与受光
              .clip(false)
            } else if (this.homeVm.actsLoaded) {
              Text($r('app.string.ui_home_no_events'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding({ top: 8, bottom: 8 })
                .textAlign(TextAlign.Center)
            }
          }

          // 游戏公告按官方分类展示，保留兑换码入口。
          HomeAnnouncementCard({
            groups: this.homeVm.announcementGroups,
            loaded: this.homeVm.announcementsLoaded,
            onTapAnnouncement: (item: Announcement) => {
              const params: AnnouncementDetailParams = { annId: item.id, title: item.title, banner: item.banner,
                region: item.sourceRegion, language: item.sourceLanguage, level: item.sourceLevel };
              router.pushUrl({ url: 'pages/AnnouncementDetailPage', params: params });
            },
            onTapMore: () => {
              router.pushUrl({ url: 'pages/AnnouncementPage' });
            },
            onRedeem: () => {
              this.openHomeCodes();
            },
          })

          // 功能入口（双列网格：祈愿/便笺/签到/日历/公告/设置）
          Grid() {
            GridItem() {
              this.entryTile('GachaLog', $r('app.string.ui_section_wish'), $r('app.string.ui_desc_wish'), () => {
                if (this.isWide) {
                  this.switchTo(1);
                } else {
                  this.switchPhoneTab(1);
                }
              })
            }
            GridItem() {
              this.entryTile('DailyNote', $r('app.string.tab_note'), $r('app.string.ui_desc_daily_note'), () => {
                if (this.isWide) {
                  this.switchTo(3);
                } else {
                  this.switchPhoneTab(2);
                }
              })
            }
            GridItem() {
              this.entryTile('AvatarProperty', $r('app.string.ui_nav_character'), $r('app.string.ui_desc_character'), () => {
                if (this.isWide) {
                  this.switchTo(4);
                } else {
                  router.pushUrl({ url: 'pages/CharacterPage' });
                }
              })
            }
            GridItem() {
              this.entryTile('SpiralAbyss', $r('app.string.ui_nav_abyss'), $r('app.string.ui_desc_abyss'), () => {
                if (this.isWide) {
                  this.switchTo(6);
                } else {
                  router.pushUrl({ url: 'pages/SpiralAbyssPage' });
                }
              })
            }
            GridItem() {
              this.entryTile('CheckIn', $r('app.string.ui_section_sign_in'), $r('app.string.ui_desc_sign_in'), () => {
                router.pushUrl({ url: 'pages/SignInPage' });
              })
            }
            GridItem() {
              this.entryTile('Database', $r('app.string.ui_section_calendar'), $r('app.string.ui_desc_calendar'), () => {
                router.pushUrl({ url: 'pages/CalendarPage' });
              })
            }
            GridItem() {
              this.entryTile('Announcement', $r('app.string.ui_nav_announcements'), $r('app.string.ui_desc_announcements'), () => {
                router.pushUrl({ url: 'pages/AnnouncementPage' });
              })
            }
            GridItem() {
              this.entryTile('Achievement', $r('app.string.ui_nav_achievement'), $r('app.string.ui_desc_achievement'), () => {
                router.pushUrl({ url: 'pages/AchievementPage' });
              })
            }
            GridItem() {
              this.entryTile('Setting', $r('app.string.page_title_setting'), $r('app.string.ui_desc_settings'), () => {
                router.pushUrl({ url: 'pages/SettingPage' });
              })
            }
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')

          Text('.')
            .fontSize(1)
            .opacity(0)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16, top: this.topAvoidVp + 8 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .backgroundColor(Color.Transparent)
      // 前瞻直播兑换码弹层（覆盖全页）
      this.homeCodeSheet()
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 宽屏主页：对齐 Windows 主页.png 的等高多列紧凑布局：
   *  Row1 顶部欢迎大标题
   *  Row2 祈愿横幅池卡（3 池竖排）| 活动卡 2x2
   *  Row3 等高 4 列卡：保底计数 | 成就统计 | 实时便笺 | 每日签到
   *  Row4 等高 2 列卡：日历 | 公告
   *  Row5 登录状态 + 功能入口网格
   */
  @Builder
  homeTabWide() {
    Scroll() {
      Column({ space: 12 }) {
        // Row1：顶部欢迎大标题（对齐 Windows 顶部大标题；文案含随机彩蛋）
        HomeHeroBanner({ title: this.greeting })

        HomeUpdateNotice()

        // Windows 的活动区开关同时控制卡池与活动；内容在限高面板内滚动。
        if (this.homeActCalendarShown) {
          Row({ space: 8 }) {
            Scroll() {
              Column() {
                if (this.poolBanners().length > 0) {
                  ForEach(this.poolBanners(), (pool: ActCalendarEntry, idx: number) => {
                    Column() {
                      HomeGachaBannerCard({
                        pool: pool,
                        plain: true,
                        rowHeight: Index.ACT_POOL_ROW_H,
                        onTap: () => {
                          this.switchTo(1);
                        },
                      })
                      if (idx < this.poolBanners().length - 1) {
                        Divider()
                          .color($r('app.color.divider'))
                          .margin({ top: 4, bottom: 4 })
                      }
                    }
                    .width('100%')
                    .onClick(() => {
                      this.switchTo(1);
                    })
                  }, (pool: ActCalendarEntry) => `pool_${pool.id}_${pool.startTime}_${pool.endTime}_${pool.avatarIcons.join('|')}_${pool.weaponIcons.join('|')}`)
                } else if (this.localPoolSummaries().length > 0) {
                  ForEach(this.localPoolSummaries(), (p: HomePoolSummary, idx: number) => {
                    Column() {
                      HomeGachaBannerCard({
                        pool: new ActCalendarEntry(),
                        summary: p,
                        plain: true,
                        rowHeight: Index.ACT_POOL_ROW_H,
                        onTap: () => {
                          this.switchTo(1);
                        },
                      })
                      if (idx < this.localPoolSummaries().length - 1) {
                        Divider()
                          .color($r('app.color.divider'))
                          .margin({ top: 4, bottom: 4 })
                      }
                    }
                    .width('100%')
                    .onClick(() => {
                      this.switchTo(1);
                    })
                  }, (p: HomePoolSummary, idx: number) => `lpool_${p.gachaType}_${p.totalCount}_${p.fiveStarCount}_${p.fourStarCount}`)
                } else {
                  this.emptyWideCard('暂无祈愿卡池', '登录并同步后显示', 120)
                }
              }
              .width('100%')
              .padding(4)
              .alignItems(HorizontalAlign.Start)
            }
            .layoutWeight(1)
            .height('100%')
            .scrollBar(BarState.Auto)
            .align(Alignment.TopStart)
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })

            Scroll() {
              Column() {
                if (this.actBannersFiltered().length > 0) {
                  ForEach(this.actBannersFiltered(), (act: ActCalendarEntry, idx: number) => {
                    Column() {
                      HomeActBannerCard({
                        entry: act,
                        plain: true,
                        rowHeight: Index.ACT_ENTRY_ROW_H,
                        onTap: () => {
                          router.pushUrl({ url: 'pages/CalendarPage' });
                        },
                      })
                      if (idx < this.actBannersFiltered().length - 1) {
                        Divider()
                          .color($r('app.color.divider'))
                          .margin({ top: 4, bottom: 4 })
                      }
                    }
                    .width('100%')
                    .onClick(() => {
                      router.pushUrl({ url: 'pages/CalendarPage' });
                    })
                  }, (act: ActCalendarEntry) => `ab_${act.type}_${act.name}_${act.startTime}`)
                } else {
                  this.emptyWideCard('暂无活动与挑战', '登录并同步后显示', 120)
                }
              }
              .width('100%')
              .padding(4)
              .alignItems(HorizontalAlign.Start)
            }
            .layoutWeight(1)
            .height('100%')
            .scrollBar(BarState.Auto)
            .align(Alignment.TopStart)
            .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
          }
          .width('100%')
          .height(this.activityPanelH())
          .padding(8)
          .alignItems(VerticalAlign.Top)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .borderRadius(8)
        }

        // Windows UniformPanel：最小列宽 300、间距 DASH_GAP，HomeAdaptiveCardHeight 为 DASH_CARD_H。
        // 卡组由设置页「主页卡片」配置（显隐 + 顺序），对齐 Windows HomeCards。
        Grid() {
          ForEach(this.dashCards, (spec: DashCardSpec) => {
            GridItem() {
              this.dashboardCard(spec.key)
            }
            .height(Index.DASH_CARD_H)
          }, (spec: DashCardSpec) => spec.key)
        }
        .columnsTemplate(Array(this.homeCols(Index.DASH_MIN_WIDTH, Index.DASH_GAP)).fill('1fr').join(' '))
        .rowsTemplate(Array(Math.ceil(this.dashCards.length / this.homeCols(Index.DASH_MIN_WIDTH, Index.DASH_GAP))).fill('1fr').join(' '))
        .columnsGap(Index.DASH_GAP)
        .rowsGap(Index.DASH_GAP)
        .width('100%')
        .height(Math.max(0, Math.ceil(this.dashCards.length / this.homeCols(Index.DASH_MIN_WIDTH, Index.DASH_GAP)) * (Index.DASH_CARD_H + Index.DASH_GAP) - Index.DASH_GAP))
        // 页面 Scroll 负责视口裁剪；卡组不裁掉首末行的阴影和受光。
        .clip(false)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.homeW = Number(newValue.width);
        })
        // Row5：游戏公告（全宽；头部含前瞻直播兑换码入口，对齐 Windows 主页兑换码 Flyout）
        HomeAnnouncementCard({
          groups: this.homeVm.announcementGroups,
          loaded: this.homeVm.announcementsLoaded,
          onTapAnnouncement: (item: Announcement) => {
            const params: AnnouncementDetailParams = { annId: item.id, title: item.title, banner: item.banner,
                region: item.sourceRegion, language: item.sourceLanguage, level: item.sourceLevel };
              router.pushUrl({ url: 'pages/AnnouncementDetailPage', params: params });
          },
          onTapMore: () => {
            router.pushUrl({ url: 'pages/AnnouncementPage' });
          },
          onRedeem: () => {
            this.openHomeCodes();
          },
        })
        .width('100%')

        Text('.')
          .fontSize(1)
          .opacity(0)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .onAreaChange((_old: Area, area: Area): void => { this.homeViewportH = Number(area.height); })
  }

  /** UniformPanel 列数（对齐 Windows UniformPanel.MeasureOverride）：floor((W+gap)/(minItem+gap))，至少 1 */
  homeCols(minItem: number, gap: number): number {
    if (this.homeW <= 0) {
      return 4;
    }
    const maxColumns: number = this.homeW >= 1200 ? 4 : 3;
    return Math.min(maxColumns, Math.max(1, Math.floor((this.homeW + gap) / (minItem + gap))));
  }

  static readonly ACT_POOL_ROW_H: number = 104;
  static readonly ACT_ENTRY_ROW_H: number = 76;
  /** 行间分割线占位（Divider 1 + margin 4+4） */
  private static readonly ACT_DIVIDER_H: number = 9;

  /** 仪表板卡片高度（对齐 Windows HomeAdaptiveCardHeight=204，ThemeResource 单一事实来源） */
  static readonly DASH_CARD_H: number = 204;
  /** 平板在接近 300vp 的卡宽下留出三列，超宽窗口保持四列。 */
  private static readonly DASH_MIN_WIDTH: number = 280;
  /** 仪表板网格列/行间距 vp（对齐 Windows UniformPanel 间距 12） */
  private static readonly DASH_GAP: number = 12;
  /** 仪表板默认卡片数量（启动游戏/祈愿/成就/便笺/旅行者札记/日历/签到；实际数量由设置页配置决定） */
  static readonly DASH_CARD_COUNT: number = PreferencesStore.HOME_CARD_KEYS.length;

  /** Windows ActivityCalendarGrid 的最大高度为 354.6；多余条目在面板内滚动。 */
  activityPanelH(): number {
    const pools: number = this.poolBanners().length > 0
      ? this.poolBanners().length : this.localPoolSummaries().length;
    const acts: number = this.homeActCalendarShown ? this.actBannersFiltered().length : 0;
    if (pools === 0 && acts === 0) {
      return 148;
    }
    const poolHeight: number = pools * Index.ACT_POOL_ROW_H + Math.max(0, pools - 1) * Index.ACT_DIVIDER_H;
    const actHeight: number = acts * Index.ACT_ENTRY_ROW_H + Math.max(0, acts - 1) * Index.ACT_DIVIDER_H;
    const maxHeight: number = this.homeViewportH > 0 ? Math.min(354.6, this.homeViewportH * 0.45) : 354.6;
    return Math.min(maxHeight, 24 + Math.max(poolHeight, actHeight));
  }

  /** 未在进行中（无有效起止时间）的活动过滤（对齐 Windows ActPreview 开关） */
  private actBannersFiltered(): ActCalendarEntry[] {
    const all: ActCalendarEntry[] = this.actBanners();
    if (this.homeActPreview) {
      return all;
    }
    const out: ActCalendarEntry[] = [];
    for (const a of all) {
      if (a.startTime > 0 && a.endTime > 0) {
        out.push(a);
      }
    }
    return out;
  }

  /** 祈愿横幅池数（网络卡池优先；无网络数据用本地统计，离线可用） */
  private poolBanners(): ActCalendarEntry[] {
    const out: ActCalendarEntry[] = [];
    for (const a of this.homeVm.acts) {
      if (a.type === ActCalendarType.CARD_POOL) {
        out.push(a);
      }
    }
    return out;
  }

  /** 本地祈愿统计（网络卡池为空时兜底，HomeGachaBannerCard summary 数据源） */
  private localPoolSummaries(): HomePoolSummary[] {
    const out: HomePoolSummary[] = [];
    for (const p of this.homeVm.gachaPools) {
      out.push(p);
      if (out.length >= 3) {
        break;
      }
    }
    return out;
  }

  /** 活动横幅（非卡池类型，面板内滚动展示完整集合） */
  private actBanners(): ActCalendarEntry[] {
    const out: ActCalendarEntry[] = [];
    for (const a of this.homeVm.acts) {
      if (a.type !== ActCalendarType.CARD_POOL) {
        out.push(a);
      }
    }
    return out;
  }

  private phoneActivities(): ActCalendarEntry[] {
    return this.poolBanners().concat(this.actBannersFiltered());
  }

  /** 宽屏空态占位卡（Row2 无数据时替代黑块） */
  @Builder
  emptyWideCard(title: string, desc: string, height: number = 88) {
    Column({ space: 6 }) {
      Text('◆')
        .fontSize(12)
        .fontColor($r('app.color.app_primary_text'))
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(desc)
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(height)
    .justifyContent(FlexAlign.Center)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  /** 日历事件日期（活动/卡池结束日） */
  private calendarEventDays(): number[] {
    const days: number[] = [];
    for (const a of this.homeVm.acts) {
      if (a.endTime > 0) {
        days.push(a.endTime);
      }
    }
    return days;
  }

  /** 今日进行中的活动/卡池名称（主页日历卡徽标） */
  private todayActNames(): string[] {
    const now: number = Date.now();
    const out: string[] = [];
    for (const a of this.homeVm.acts) {
      if (a.isOngoing(now)) {
        out.push(a.name);
      }
    }
    return out;
  }

  @Builder
  entryTile(icon: string, title: ResourceStr, desc: ResourceStr, onClick: () => void) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (Index.isEmoji(icon)) {
          Text(icon)
            .fontSize(24)
            .width(42)
            .height(42)
            .textAlign(TextAlign.Center)
        } else {
          NavIcon({ name: icon, iconSize: 24 })
        }
      }
      .width(42)
      .height(42)
      .borderRadius(12)
      .backgroundColor($r('app.color.app_primary_bg'))
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(desc)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(64)
    .padding(10)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
    .transition(this.reduceMotion ? TransitionEffect.IDENTITY.animation({ duration: 0 }) : Motion.riseIn())
    .hoverEffect(HoverEffect.Highlight)
    .onClick(onClick)
  }

  @Builder
  entryCard(icon: string, title: ResourceStr, desc: ResourceStr, onClick: () => void) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (Index.isEmoji(icon)) {
          Text(icon)
            .fontSize(26)
            .width(46)
            .height(46)
            .textAlign(TextAlign.Center)
        } else {
          NavIcon({ name: icon, iconSize: 26 })
        }
      }
      .width(46)
      .height(46)
      .borderRadius(12)
      .backgroundColor($r('app.color.app_primary_bg'))
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(12)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
    .onClick(onClick)
  }

  @Builder
  gachaTab() {
    Column() {
      GachaLogPage()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.isWide ? 0 : this.topAvoidVp })
  }

  @Builder
  noteTab() {
    Column() {
      DailyNotePage()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.isWide ? 0 : this.topAvoidVp })
  }

  @Builder
  mineTab() {
    Scroll() {
      Column({ space: 12 }) {
        Text($r('app.string.tab_mine'))
          .fontSize($r('app.float.page_title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ top: 8 })

        LoginStatusBar()

        // 分组与宽屏侧栏一致（对齐 Windows NavigationView：工具 / 周期 / 数据 / 系统），
        // 手机「我的」即全功能目录；祈愿/便笺已是底部页签，不再重复列出。
        // 「胡桃通行证」置顶（对齐 Windows 主页下方的置顶组）
        this.entryCard('Passport', $r('app.string.ui_nav_passport'), $r('app.string.ui_desc_passport'), () => {
          router.pushUrl({ url: 'pages/HutaoCloudPage' });
        })

        this.navSectionTitle($r('app.string.ui_group_tools'))
        this.entryCard('LaunchGame', $r('app.string.ui_nav_launch'), $r('app.string.ui_desc_launch'), () => {
          router.pushUrl({ url: 'pages/LaunchGamePage' });
        })
        this.entryCard('Achievement', $r('app.string.ui_nav_achievement'), $r('app.string.ui_desc_achievement'), () => {
          router.pushUrl({ url: 'pages/AchievementPage' });
        })
        this.entryCard('AvatarProperty', $r('app.string.ui_nav_character'), $r('app.string.ui_desc_character'), () => {
          router.pushUrl({ url: 'pages/CharacterPage' });
        })
        this.entryCard('Cultivation', $r('app.string.ui_nav_cultivation'), $r('app.string.ui_desc_cultivation'), () => {
          router.pushUrl({ url: 'pages/CultivationPage' });
        })
        this.entryCard('Backpack', $r('app.string.ui_nav_backpack'), $r('app.string.ui_desc_backpack'), () => {
          router.pushUrl({ url: 'pages/BackpackPage' });
        })
        this.entryCard('GachaLog', $r('app.string.ui_nav_banner_history'), $r('app.string.ui_desc_banner_history'), () => {
          router.pushUrl({ url: 'pages/WishHistoryPage' });
        })

        this.navSectionTitle($r('app.string.ui_group_period'))
        this.entryCard('SpiralAbyss', $r('app.string.ui_nav_abyss'), $r('app.string.ui_desc_abyss'), () => {
          router.pushUrl({ url: 'pages/SpiralAbyssPage' });
        })
        this.entryCard('RoleCombat', $r('app.string.ui_nav_theater'), $r('app.string.ui_desc_theater'), () => {
          router.pushUrl({ url: 'pages/RoleCombatPage' });
        })
        this.entryCard('HardChallenge', $r('app.string.ui_nav_challenge'), $r('app.string.ui_desc_challenge'), () => {
          router.pushUrl({ url: 'pages/HardChallengePage' });
        })

        this.navSectionTitle($r('app.string.ui_group_data'))
        this.entryCard('WikiAvatar', $r('app.string.ui_nav_wiki_avatar'), $r('app.string.ui_desc_wiki_avatar'), () => {
          router.pushUrl({ url: 'pages/WikiAvatarPage' });
        })
        this.entryCard('WikiWeapon', $r('app.string.ui_nav_wiki_weapon'), $r('app.string.ui_desc_wiki_weapon'), () => {
          router.pushUrl({ url: 'pages/WikiWeaponPage' });
        })
        this.entryCard('WikiMonster', $r('app.string.ui_nav_wiki_monster'), $r('app.string.ui_desc_wiki_monster'), () => {
          router.pushUrl({ url: 'pages/WikiMonsterPage' });
        })
        this.entryCard('TravelersDiary', $r('app.string.ui_nav_ledger'), $r('app.string.ui_desc_ledger'), () => {
          router.pushUrl({ url: 'pages/LedgerPage' });
        })

        this.navSectionTitle('日常')
        this.entryCard('CheckIn', $r('app.string.ui_section_sign_in'), $r('app.string.ui_desc_sign_in'), () => {
          router.pushUrl({ url: 'pages/SignInPage' });
        })
        this.entryCard('Database', $r('app.string.ui_section_calendar'), $r('app.string.ui_desc_calendar'), () => {
          router.pushUrl({ url: 'pages/CalendarPage' });
        })
        this.entryCard('Announcement', $r('app.string.ui_nav_announcements'), $r('app.string.ui_desc_announcements'), () => {
          router.pushUrl({ url: 'pages/AnnouncementPage' });
        })

        this.navSectionTitle($r('app.string.ui_group_system'))
        this.entryCard('Passport', $r('app.string.ui_section_account'), $r('app.string.ui_desc_account'), () => {
          router.pushUrl({ url: 'pages/UserPage' });
        })
        this.entryCard('Setting', $r('app.string.page_title_setting'), $r('app.string.ui_desc_settings'), () => {
          router.pushUrl({ url: 'pages/SettingPage' });
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16, top: this.topAvoidVp + 8 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor($r('app.color.page_background'))
  }
}
