/**
 * Index.ets — Shell 导航壳（@Entry）
 * 官方 HdsTabs 悬浮页签（API23）：barFloatingStyle + systemMaterialEffect 沉浸光感，
 * 系统自带"手指到哪光到哪"的高亮滑块动画；底部悬浮不贴边。
 * 首页：每日背景（可开关）+ 登录状态 + 功能入口；我的：账号入口 + 设置。
 * 状态栏：自动读取本机状态栏高度（topAvoidVp），背景延伸、内容整体下移不重叠。
 */
import { router } from '@kit.ArkUI';
import { curves, display, uiMaterial, window } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Motion } from '../common/Motion';
import { LoginStatusBar } from '../components/LoginStatusBar';
import { WallpaperLayer } from '../components/WallpaperLayer';
import { HomeHeroBanner } from '../components/HomeHeroBanner';
import { HomeGachaCard } from '../components/HomeGachaCard';
import { HomeDailyNoteCard } from '../components/HomeDailyNoteCard';
import { HomeSignInCard } from '../components/HomeSignInCard';
import { HomeAchievementCard } from '../components/HomeAchievementCard';
import { HomeActCard } from '../components/HomeActCard';
import { HomeAnnouncementCard } from '../components/HomeAnnouncementCard';
import { HomeGachaBannerCard } from '../components/HomeGachaBannerCard';
import { HomeActBannerCard } from '../components/HomeActBannerCard';
import { HomeCalendarCard } from '../components/HomeCalendarCard';
import { HomeChallengeCard } from '../components/HomeChallengeCard';
import { GachaLogPage } from './GachaLogPage';
import { DailyNotePage } from './DailyNotePage';
import { CharacterPage } from './CharacterPage';
import { SpiralAbyssPage } from './SpiralAbyssPage';
import { SignInPage } from './SignInPage';
import { CalendarPage } from './CalendarPage';
import { AnnouncementPage } from './AnnouncementPage';
import { UserPage } from './UserPage';
import { SettingPage } from './SettingPage';
import { RoleCombatPage } from './RoleCombatPage';
import { HardChallengePage } from './HardChallengePage';
import { CultivationPage } from './CultivationPage';
import { WikiAvatarPage } from './WikiAvatarPage';
import { WikiWeaponPage } from './WikiWeaponPage';
import { WikiMonsterPage } from './WikiMonsterPage';
import { AchievementPage } from './AchievementPage';
import { LaunchGamePage } from './LaunchGamePage';
import { NavIcon } from '../components/NavIcon';
import { PageContainer } from '../components/PageContainer';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { HomeViewModel, HomePoolSummary, HomeChallengeSummary } from '../viewmodel/HomeViewModel';
import { Logger } from '../common/Logger';
import { SignInService, SignInResult } from '../service/SignInService';
import { ActCalendarEntry, ActCalendarType } from '../model/ActCalendarEntry';

  @Entry
  @Component
  struct Index {
    /** 主页仪表盘数据容器 */
    @State homeVm: HomeViewModel = new HomeViewModel();
    @State homeSigning: boolean = false;
    @State todayDay: number = new Date().getDate();
    /** 周期挑战进度快照（@Observed VM 深层属性变化不触发 Index 重建；快照显式同步） */
    @State challengeSnap: HomeChallengeSummary = new HomeChallengeSummary();
    /** 当前登录账号默认 UID（登录/绑定后主页自动重载挑战/便笺/签到等） */
    @StorageProp('currentUid') @Watch('onUidChanged') boundUid: string = '';
    /** 登录态（登录/登出后主页重载） */
    @StorageProp('isLoggedIn') @Watch('onLoginChanged') boundLoggedIn: boolean = false;
    /** 祈愿数据版本戳（祈愿页刷新成功后 bump；主页祈愿卡订阅重读本地库） */
    @StorageLink('gachaDataVersion') @Watch('onGachaDataChanged') gachaDataVersion: number = 0;
    @StorageProp('topAvoidVp') topAvoidVp: number = 0;
    @StorageProp('bottomAvoidVp') bottomAvoidVp: number = 0;
    /** 当前选中页签（窄屏 0-3 / 宽屏 0-7） */
    @State currentIndex: number = 0;
    /** 宽屏侧边栏（>=840vp 平板/PC 显示） */
    @State isWide: boolean = false;
    /** 沉浸光感材质等级：-1=关闭；0=自适应(ADAPTIVE)；1=精细；2=柔和；3=平滑 */
    @State materialLevelIdx: number = 0;
    /** API 26 沉浸光感可用性（运行时门控；低版本回退 scrim 半透明） */
    private immersive: boolean = Motion.detectImmersive();
    /** 宽屏侧栏/标题栏沉浸材质（仅 API 26+ 生效） */
    private panelMaterial: uiMaterial.Material | undefined = Motion.detectImmersive()
      ? new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN }) : undefined;
    /** 每日背景开关 */
    /** 背景来源（none/local/bing，对齐 Windows 背景图片设置） */
    @StorageProp('bgType') bgType: string = 'local';
    @StorageProp('bgFolderPath') bgFolderPath: string = '';
    /** 是否深色模式（驱动每日背景渐变配色） */
    @StorageProp('isDarkMode') isDarkMode: boolean = false;
    /** 侧边栏折叠（仅图标），对齐 Windows CompactPaneLength=45 */
    @State sidebarFold: boolean = false;
    /** 系统三键区（最小化/全屏/关闭）占位宽度 vp（PC 自定义窗口装饰；0=无系统三键） */
    @StorageProp('titleBtnWidthVp') titleBtnWidthVp: number = 0;
    /** 是否正在通过自绘 TitleBar 拖拽窗口（避免重复触发 startMoving） */
    private windowDragging: boolean = false;
    private controller: HdsTabsController = new HdsTabsController();

    aboutToAppear(): void {
      const strength: number = PreferencesStore.getAmbientStrength();
      // 三档映射：0=关闭；0.5 档=标准(GENTLE)；1=增强(EXQUISITE)
      if (strength <= 0) {
        this.materialLevelIdx = -1;
      } else if (strength >= 1) {
        this.materialLevelIdx = 1;
      } else {
        this.materialLevelIdx = 2;
      }
      AppStorage.setOrCreate<string>('bgType', PreferencesStore.getBackgroundImageType());
      AppStorage.setOrCreate<string>('bgFolderPath', PreferencesStore.getBackgroundFolderPath());
      // 立即检测宽屏（PC/平板>普通手机）：屏幕宽度 vp 判断，避免等待 onAreaChange 首帧
      this.isWide = Index.detectWideScreen();
      this.reloadHome();
    }

    /** 聚合加载主页仪表盘数据（祈愿/便笺/签到/活动/公告） */
    reloadHome(): void {
      this.todayDay = new Date().getDate();
      const uid: string = AppStorage.get<string>('currentUid') ?? '';
      this.homeVm.load(uid).then(() => {
        // 同步周期挑战快照（@Observed 深属性不触发 Index 重建）
        this.challengeSnap = HomeChallengeSummary.of(this.homeVm.challenge);
        Logger.info('Index', `challengeSnap loaded=${this.challengeSnap.loaded} abyss=${this.challengeSnap.abyssFloor}/${this.challengeSnap.abyssStar} ` +
          `rc=${this.challengeSnap.roleCombatMedals}/${this.challengeSnap.roleCombatMaxRound} hc=${this.challengeSnap.hardChallengeBest}/${this.challengeSnap.hardChallengeSecond}`);
      });
    }

    /** 祈愿页刷新成功：主页祈愿卡重读本地库 */
    onGachaDataChanged(): void {
      const uid: string = AppStorage.get<string>('currentUid') ?? '';
      this.homeVm.reloadGacha(uid).then(() => {
      });
    }

    /** 默认 UID 变化（登录/绑定角色）：主页整体重载（挑战/便笺/签到/活动） */
    onUidChanged(): void {
      this.reloadHome();
    }

    /** 登录态变化：主页重载（登出清空展示、登录拉取） */
    onLoginChanged(): void {
      this.reloadHome();
    }

    /** 主页签到（直接调用服务） */
    doHomeSignIn(): void {
      if (this.homeSigning) {
        return;
      }
      const uid: string = AppStorage.get<string>('currentUid') ?? '';
      if (uid.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '请先登录并绑定 UID' });
        return;
      }
      this.homeSigning = true;
      SignInService.getInstance().sign(uid).then((r: SignInResult) => {
        this.getUIContext().getPromptAction().showToast({ message: r.message.length > 0 ? r.message : (r.ok ? '签到成功' : '签到失败') });
        this.homeVm.load(uid).then(() => {
        });
      }).catch((e: Error) => {
        this.getUIContext().getPromptAction().showToast({ message: e.message });
      }).finally(() => {
        this.homeSigning = false;
      });
    }

  /** 宽屏检测：屏幕宽度 vp >= WIDE_THRESHOLD 视为平板/PC */
  private static detectWideScreen(): boolean {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const dp: number = d.densityPixels;
      const widthPx: number = d.width;
      const widthVp: number = dp > 0 ? widthPx / dp : widthPx;
      const thresholdVp = 720;
      return widthVp >= thresholdVp;
    } catch (e) {
      return false;
    }
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

  /** 官方沉浸光感材质参数（关闭时返回 undefined） */
  materialEffect(): SystemMaterialParams | undefined {
    if (this.materialLevelIdx < 0) {
      return undefined;
    }
    const level: hdsMaterial.MaterialLevel =
      this.materialLevelIdx === 1 ? hdsMaterial.MaterialLevel.EXQUISITE
        : (this.materialLevelIdx === 2 ? hdsMaterial.MaterialLevel.GENTLE
          : (this.materialLevelIdx === 3 ? hdsMaterial.MaterialLevel.SMOOTH
            : hdsMaterial.MaterialLevel.ADAPTIVE));
    const cfg: SystemMaterialParams = {
      materialType: hdsMaterial.MaterialType.IMMERSIVE,
      materialLevel: level,
    };
    return cfg;
  }

  /** 宽屏内容切换（统一入口）：animateTo 驱动 geometryTransition 指示条与页面转场 */
  private switchTo(index: number): void {
    this.getUIContext().animateTo({ curve: Motion.springSoft() }, () => {
      this.currentIndex = index;
    });
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

  /** 窄屏：底部 HdsTabs 悬浮页签（手机） */
  @Builder
  phoneShell() {
    HdsTabs({ controller: this.controller }) {
      TabContent() {
        this.homeTab()
      }
      .tabBar(this.bottomTab(0, 'Announcement', '首页'))

      TabContent() {
        this.gachaTab()
      }
      .tabBar(this.bottomTab(1, 'GachaLog', '祈愿'))

      TabContent() {
        this.noteTab()
      }
      .tabBar(this.bottomTab(2, 'DailyNote', '便笺'))

      TabContent() {
        this.mineTab()
      }
      .tabBar(this.bottomTab(3, 'Passport', '我的'))
    }
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .onChange((index: number) => {
      this.currentIndex = index;
    })
    .barFloatingStyle({
      barBottomMargin: 20,
      gradientMask: { maskColor: ('app.color.mask_scrim'), maskHeight: 96 },
      systemMaterialEffect: this.materialEffect(),
    })
    .barBackgroundColor('#00FFFFFF')
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const w: number = newValue.width as number;
      this.isWide = w >= Index.WIDE_VP;
    })
  }

  /** 宽屏：全屏壁纸底 + 顶部自定义 TitleBar + 左侧分组导航（可折叠）+ 右侧内容区 */
  @Builder
  wideShell() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 全屏壁纸层（覆盖整个窗口，含侧边栏与标题栏底下）
      WallpaperLayer({ bgType: this.bgType, folderPath: this.bgFolderPath })

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

      // 底部指示点：内容区背景半透明达标的视觉 (宽屏无底部tab，保留)
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      // 与 phoneShell 同阈值：窗口缩到 <720vp 时切回窄屏（2in1 旋转/缩放）
      const w: number = newValue.width as number;
      this.isWide = w >= Index.WIDE_VP;
    })
  }

  /** 顶部自定义 TitleBar：系统标题栏已由 setWindowDecorVisible(false) 隐藏，
   *  此区域背景透明透传壁纸；左侧=全局返回/折叠侧栏/版本号，右侧=系统三键保留区（勿放交互元素） */
  @Builder
  topBar() {
    Row({ space: 4 }) {
      // 返回按钮（全局返回上一步）
      Stack({ alignContent: Alignment.Center }) {
        Text('‹')
          .fontSize(22)
          .fontColor($r('app.color.text_primary'))
      }
      .width(36)
      .height(36)
      .borderRadius(8)
      .hoverEffect(HoverEffect.Highlight)
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

      // 三条杠（折叠侧栏：仅图标 / 图标+文字）
      Stack({ alignContent: Alignment.Center }) {
        Text('☰')
          .fontSize(18)
          .fontColor($r('app.color.text_primary'))
      }
      .width(36)
      .height(36)
      .borderRadius(8)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.sidebarFold = !this.sidebarFold;
      })

      // 版本号（胡桃 1.20.0）
      Text('胡桃 1.20.0')
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
    Scroll() {
      Column({ space: 2 }) {
        // 主页项独立顶置（不放在任何小标题下）
        this.navItemHome(0)

        this.navSectionTitle('工具')
        this.navItem(14, 'LaunchGame', '启动游戏')
        this.navItem(1, 'GachaLog', '祈愿记录')
        this.navItem(2, 'Achievement', '成就管理')
        this.navItem(3, 'DailyNote', '实时便笺')
        this.navItem(4, 'AvatarProperty', '我的角色')
        this.navItem(5, 'Cultivation', '养成计划')

        this.navSectionTitle('周期')
        this.navItem(6, 'SpiralAbyss', '深境螺旋')
        this.navItem(7, 'RoleCombat', '幻想真境剧诗')
        this.navItem(8, 'HardChallenge', '幽境危战')

        this.navSectionTitle('数据')
        this.navItem(9, 'WikiAvatar', '角色资料')
        this.navItem(10, 'WikiWeapon', '武器资料')
        this.navItem(11, 'WikiMonster', '怪物资料')

        this.navSectionTitle('系统')
        this.navItem(12, 'Passport', '账号与数据')
        this.navItem(13, '⚙️', '设置')

        Blank()
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width(this.sidebarFold ? 52 : 208)
    .height('100%')
    .scrollBar(BarState.Off)
    // API 26+ 沉浸光感侧栏（低版本回退 scrim 半透明）
    .systemMaterial(this.panelMaterial)
    .backgroundColor(this.immersive ? Color.Transparent : ('app.color.nav_scrim'))
    .border({ width: { right: 1 }, color: ('app.color.nav_border') })
  }

  /** 主页导航项（置顶，Windows Announcement 彩色图标；选中态=左侧强调色指示条） */
  @Builder
  navItemHome(index: number) {
    Row({ space: 10 }) {
      Column()
        .width(3)
        .height(18)
        .borderRadius(2)
        .backgroundColor(this.currentIndex === index ? $r('app.color.app_primary') : Color.Transparent)
        .geometryTransition(this.currentIndex === index ? 'navIndicator' : '')
      NavIcon({ name: 'Announcement', iconSize: 24 })
      if (!this.sidebarFold) {
        Text('主页')
          .fontSize(15)
          .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentIndex === index ? $r('app.color.app_primary') : $r('app.color.text_primary'))
      }
      Blank()
    }
    .width(this.sidebarFold ? 52 : '100%')
    .padding({ left: this.sidebarFold ? 12 : 4, right: this.sidebarFold ? 0 : 14, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(this.currentIndex === index ? $r('app.color.app_primary_bg') : Color.Transparent)
    .animation({ curve: Motion.springFast() })
    .onClick(() => {
      this.switchTo(index);
    })
  }

  @Builder
  navSectionTitle(title: string) {
    if (!this.sidebarFold) {
      Text(title)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 4 })
    }
  }

  @Builder
  navItem(index: number, icon: string, label: string) {
    Row({ space: 10 }) {
      // 左侧强调色指示条（对齐 Windows NavigationView 选中态；geometryTransition 弹性形变滑动）
      Column()
        .width(3)
        .height(18)
        .borderRadius(2)
        .backgroundColor(this.currentIndex === index ? $r('app.color.app_primary') : Color.Transparent)
        .geometryTransition(this.currentIndex === index ? 'navIndicator' : '')
      if (Index.isEmoji(icon)) {
        Text(icon)
          .fontSize(18)
          .width(24)
          .textAlign(TextAlign.Center)
      } else {
        NavIcon({ name: icon, iconSize: 22 })
      }
      if (!this.sidebarFold) {
        Text(label)
          .fontSize(15)
          .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentIndex === index ? $r('app.color.app_primary') : $r('app.color.text_primary'))
      }
      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: 14, top: 9, bottom: 9 })
    .borderRadius(10)
    .backgroundColor(this.currentIndex === index ? $r('app.color.app_primary_bg') : Color.Transparent)
    .animation({ curve: Motion.springFast() })
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
        PageContainer() {
          this.homeTabWide()
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
  bottomTab(index: number, icon: string, label: string) {
    Column({ space: 2 }) {
      Image(NavIcon.resolve(icon))
        .width(52)
        .height(30)
        .objectFit(ImageFit.Contain)
        .backgroundColor(this.currentIndex === index ? $r('app.color.app_primary_bg') : Color.Transparent)
      Text(label)
        .fontSize(11)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .animation({ curve: Motion.springFast() })
  }

  @Builder
  homeTab() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 壁纸层（渐变 + 本地胡桃横幅 + 可选）
      WallpaperLayer({ bgType: this.bgType, folderPath: this.bgFolderPath })

      Scroll() {
        Column({ space: 12 }) {
          // 欢迎横幅（对齐电脑版主页顶部）
          HomeHeroBanner({
            title: '旅行者，欢迎来到提瓦特大陆！',
            subtitle: '胡桃工具箱 · 祈愿记录 / 实时便笺 / 签到日历',
          })

          LoginStatusBar()

          // 祈愿统计卡（真实数据：各池抽数 + 橙/紫保底进度）
          HomeGachaCard({
            uid: this.homeVm.currentUid,
            pools: this.homeVm.gachaPools,
            total: this.homeVm.gachaTotal,
            loaded: this.homeVm.gachaLoaded,
            onTap: () => {
              if (this.isWide) {
                this.switchTo(1);
              } else {
                this.controller.changeIndex(1);
              }
            },
          })

          // 实时便笺卡（真实数据：树脂/宝钱/委托/周本折扣/参变仪/派遣）
          HomeDailyNoteCard({
            uid: this.homeVm.currentUid,
            note: this.homeVm.note,
            refreshTime: this.homeVm.noteRefreshTime,
            loaded: this.homeVm.noteLoaded,
            onTap: () => {
              if (this.isWide) {
                this.switchTo(3);
              } else {
                this.controller.changeIndex(2);
              }
            },
          })

          // 签到卡（真实数据：奖励网格 + 签到/补签按钮）
          HomeSignInCard({
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

          // 成就管理卡（完成度统计，点击进成就管理页）
          HomeAchievementCard({
            onTap: () => {
              if (this.isWide) {
                this.switchTo(2);
              } else {
                router.pushUrl({ url: 'pages/AchievementPage' });
              }
            },
          })

          // 近期活动/卡池（真实数据：进行中 + 即将开始）
          Row() {
            Text('近期活动 / 卡池')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Text('查看日历 ›')
              .fontSize(12)
              .fontColor($r('app.color.app_primary'))
              .onClick(() => {
                router.pushUrl({ url: 'pages/CalendarPage' });
              })
          }
          .width('100%')

          if (this.homeVm.acts.length > 0) {
            Grid() {
              ForEach(this.homeVm.acts, (act: ActCalendarEntry) => {
                GridItem() {
                  HomeActCard({
                    entry: act,
                    onTap: () => {
                      router.pushUrl({ url: 'pages/CalendarPage' });
                    },
                  })
                }
              }, (act: ActCalendarEntry) => `home_act_${act.type}_${act.name}_${act.endTime}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')
          } else if (this.homeVm.actsLoaded) {
            Text('暂无活动安排')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 8, bottom: 8 })
              .textAlign(TextAlign.Center)
          }

          // 游戏公告预览（真实数据：最新 3 条）
          HomeAnnouncementCard({
            items: this.homeVm.announcements,
            loaded: this.homeVm.announcementsLoaded,
            onTapAnnouncement: (id: number) => {
              router.pushUrl({ url: 'pages/AnnouncementDetailPage', params: { annId: id } });
            },
            onTapMore: () => {
              router.pushUrl({ url: 'pages/AnnouncementPage' });
            },
          })

          // 功能入口（双列网格：祈愿/便笺/签到/日历/公告/设置）
          Grid() {
            GridItem() {
              this.entryTile('GachaLog', '祈愿记录', '分池统计 / 出金历史', () => {
                if (this.isWide) {
                  this.switchTo(1);
                } else {
                  this.controller.changeIndex(1);
                }
              })
            }
            GridItem() {
              this.entryTile('DailyNote', '实时便笺', '树脂 / 派遣 / 通知', () => {
                if (this.isWide) {
                  this.switchTo(3);
                } else {
                  this.controller.changeIndex(2);
                }
              })
            }
            GridItem() {
              this.entryTile('AvatarProperty', '我的角色', '角色列表 / 详情', () => {
                if (this.isWide) {
                  this.switchTo(3);
                } else {
                  router.pushUrl({ url: 'pages/CharacterPage' });
                }
              })
            }
            GridItem() {
              this.entryTile('SpiralAbyss', '深境螺旋', '当期 / 上期战绩', () => {
                if (this.isWide) {
                  this.switchTo(4);
                } else {
                  router.pushUrl({ url: 'pages/SpiralAbyssPage' });
                }
              })
            }
            GridItem() {
              this.entryTile('CheckIn', '每日签到', '米游社签到奖励', () => {
                router.pushUrl({ url: 'pages/SignInPage' });
              })
            }
            GridItem() {
              this.entryTile('Database', '活动日历', '活动 / 卡池 / 签到', () => {
                router.pushUrl({ url: 'pages/CalendarPage' });
              })
            }
            GridItem() {
              this.entryTile('Announcement', '游戏公告', '版本更新 / 新闻', () => {
                router.pushUrl({ url: 'pages/AnnouncementPage' });
              })
            }
            GridItem() {
              this.entryTile('Achievement', '成就管理', '进度 / UIAF 互通', () => {
                router.pushUrl({ url: 'pages/AchievementPage' });
              })
            }
            GridItem() {
              this.entryTile('⚙️', '设置', '主题 / 刷新 / 账号', () => {
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
        // Row1：顶部欢迎大标题（对齐 Windows 顶部大标题）
        HomeHeroBanner({
          title: '旅行者，欢迎来到提瓦特大陆！',
          subtitle: '胡桃工具箱 · 祈愿记录 / 实时便笺 / 签到日历',
        })

        // Row2：祈愿横幅池卡（竖排 3 池） | 活动卡 2x2
        Row({ space: 12 }) {
          Column({ space: 8 }) {
            if (this.poolBanners().length > 0) {
              ForEach(this.poolBanners(), (pool: ActCalendarEntry, idx: number) => {
                HomeGachaBannerCard({
                  pool: pool,
                  onTap: () => {
                    this.switchTo(1);
                  },
                })
              }, (pool: ActCalendarEntry, idx: number) => `pool_${idx}_${pool.name.length}`)
            } else if (this.localPoolSummaries().length > 0) {
              // 本地祈愿统计兜底：离线也有横幅（抽数/五星/四星统计）
              ForEach(this.localPoolSummaries(), (p: HomePoolSummary, idx: number) => {
                HomeGachaBannerCard({
                  pool: new ActCalendarEntry(),
                  summary: p,
                  onTap: () => {
                    this.switchTo(1);
                  },
                })
              }, (p: HomePoolSummary, idx: number) => `lpool_${idx}_${p.gachaType}`)
            } else {
              this.emptyWideCard('暂无祈愿横幅', '登录并同步后显示卡池横幅与活动安排', 184)
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Grid() {
            GridItem() {
              this.actBannerGridItem(0)
            }
            GridItem() {
              this.actBannerGridItem(1)
            }
            GridItem() {
              this.actBannerGridItem(2)
            }
            GridItem() {
              this.actBannerGridItem(3)
            }
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .layoutWeight(1.2)        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        // Row3：等高 4 列卡（对齐 Windows 启动/保底/成就/便笺/刷新行）
        Row({ space: 10 }) {
          HomeGachaCard({
            uid: this.homeVm.currentUid,
            pools: this.homeVm.gachaPools,
            total: this.homeVm.gachaTotal,
            loaded: this.homeVm.gachaLoaded,
            onTap: () => {
              this.switchTo(1);
            },
          })
          .layoutWeight(1)
          .height('100%')

          HomeAchievementCard({
            onTap: () => {
              this.switchTo(2);
            },
          })
          .layoutWeight(1)
          .height('100%')

          HomeDailyNoteCard({
            uid: this.homeVm.currentUid,
            note: this.homeVm.note,
            refreshTime: this.homeVm.noteRefreshTime,
            loaded: this.homeVm.noteLoaded,
            onTap: () => {
              this.switchTo(3);
            },
          })
          .layoutWeight(1)
          .height('100%')

          HomeSignInCard({
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
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .height(260)
        .alignItems(VerticalAlign.Center)

        // Row3.5：周期挑战卡（深境/剧诗/幽境 三格进度）
        HomeChallengeCard({
          data: this.challengeSnap,
          onTap: (index: number) => {
            if (index === 0) {
              router.pushUrl({ url: 'pages/SpiralAbyssPage' });
            } else if (index === 1) {
              router.pushUrl({ url: 'pages/RoleCombatPage' });
            } else {
              router.pushUrl({ url: 'pages/HardChallengePage' });
            }
          },
        })
        .width('100%')

        // Row4：等高 2 列卡：日历 | 公告
        Row({ space: 10 }) {
          HomeCalendarCard({
            eventDays: this.calendarEventDays(),
            todayActs: this.todayActNames(),
            onTap: () => {
              router.pushUrl({ url: 'pages/CalendarPage' });
            },
          })
          .layoutWeight(1)
          .height('100%')

          HomeAnnouncementCard({
            items: this.homeVm.announcements,
            loaded: this.homeVm.announcementsLoaded,
            onTapAnnouncement: (id: number) => {
              router.pushUrl({ url: 'pages/AnnouncementDetailPage', params: { annId: id } });
            },
            onTapMore: () => {
              router.pushUrl({ url: 'pages/AnnouncementPage' });
            },
          })
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .height(240)
        .alignItems(VerticalAlign.Center)

        // Row5：登录状态 + 功能入口网格（4 列）
        Row({ space: 10 }) {
          Column({ space: 10 }) {
            LoginStatusBar()
            if (this.homeVm.acts.length > 0) {
              this.actListTitle()
              Grid() {
                ForEach(this.homeVm.acts, (act: ActCalendarEntry) => {
                  GridItem() {
                    HomeActCard({
                      entry: act,
                      onTap: () => {
                        router.pushUrl({ url: 'pages/CalendarPage' });
                      },
                    })
                  }
                }, (act: ActCalendarEntry) => `home_act_${act.type}_${act.name}_${act.endTime}`)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(8)
              .rowsGap(8)
              .width('100%')
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          // 功能入口（2 列网格）
          Grid() {
            GridItem() {
              this.entryTile('GachaLog', '祈愿记录', '分池统计', () => {
                this.switchTo(1);
              })
            }
            GridItem() {
              this.entryTile('AvatarProperty', '我的角色', '角色详情', () => {
                this.switchTo(4);
              })
            }
            GridItem() {
              this.entryTile('SpiralAbyss', '深境螺旋', '当期战绩', () => {
                this.switchTo(6);
              })
            }
            GridItem() {
              this.entryTile('RoleCombat', '幻想真境剧诗', '回合奖章', () => {
                this.switchTo(7);
              })
            }
            GridItem() {
              this.entryTile('HardChallenge', '幽境危战', '强敌挑战', () => {
                this.switchTo(8);
              })
            }
            GridItem() {
              this.entryTile('Cultivation', '养成计划', '材料计算', () => {
                this.switchTo(5);
              })
            }
            GridItem() {
              this.entryTile('Achievement', '成就管理', 'UIAF 导入导出', () => {
                this.switchTo(2);
              })
            }
            GridItem() {
              this.entryTile('WikiAvatar', '角色资料', '资料百科', () => {
                this.switchTo(9);
              })
            }
            GridItem() {
              this.entryTile('⚙️', '设置', '主题 / 账号', () => {
                this.switchTo(13);
              })
            }
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

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
  }

  /** 时后活动小标题 */
  @Builder
  actListTitle() {
    Row() {
      Text('近期活动 / 卡池')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text('查看日历 ›')
        .fontSize(12)
        .fontColor($r('app.color.app_primary'))
        .onClick(() => {
          router.pushUrl({ url: 'pages/CalendarPage' });
        })
    }
    .width('100%')
  }

  /** 祈愿横幅池数（网络卡池优先；无网络数据用本地统计，离线可用） */
  private poolBanners(): ActCalendarEntry[] {
    const out: ActCalendarEntry[] = [];
    for (const a of this.homeVm.acts) {
      if (a.type === ActCalendarType.CARD_POOL) {
        out.push(a);
        if (out.length >= 3) {
          break;
        }
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

  /** 活动横幅（非卡池类型，最多 4 条） */
  private actBanners(): ActCalendarEntry[] {
    const out: ActCalendarEntry[] = [];
    for (const a of this.homeVm.acts) {
      if (a.type !== ActCalendarType.CARD_POOL) {
        out.push(a);
        if (out.length >= 4) {
          break;
        }
      }
    }
    return out;
  }

  /** 活动卡 2x2 网格项（空数据时仅显示一句提示，其余格隐藏避免黑色占位块） */
  @Builder
  actBannerGridItem(idx: number) {
    if (idx < this.actBanners().length) {
      HomeActBannerCard({
        entry: this.actBanners()[idx],
        onTap: () => {
          router.pushUrl({ url: 'pages/CalendarPage' });
        },
      })
    } else if (idx === 0) {
      this.emptyWideCard('暂无活动安排', '登录后同步活动/卡池/签到日历', 184)
    }
  }

  /** 宽屏空态占位卡（Row2 无数据时替代黑块） */
  @Builder
  emptyWideCard(title: string, desc: string, height: number = 88) {
    Column({ space: 6 }) {
      Text('◆')
        .fontSize(12)
        .fontColor($r('app.color.app_primary'))
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
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 日历事件日期（活动/卡池结束日） */
  private calendarEventDays(): number[] {
    const days: number[] = [];
    for (const a of this.homeVm.acts) {
      if (a.endTime > 0) {
        days.push(new Date(a.endTime).getDate());
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
  entryTile(icon: string, title: string, desc: string, onClick: () => void) {
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
    .backgroundColor($r('app.color.card_background'))
    .transition(Motion.riseIn())
    .onClick(onClick)
  }

  @Builder
  entryCard(icon: string, title: string, desc: string, onClick: () => void) {
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
    .backgroundColor($r('app.color.card_background'))
    .onClick(onClick)
  }

  @Builder
  gachaTab() {
    Column() {
      GachaLogPage()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topAvoidVp })
  }

  @Builder
  noteTab() {
    Column() {
      DailyNotePage()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.topAvoidVp })
  }

  @Builder
  mineTab() {
    Scroll() {
      Column({ space: 12 }) {
        Text('我的')
          .fontSize($r('app.float.page_title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ top: 8 })

        LoginStatusBar()

        this.entryCard('Cultivation', '养成计划', '角色养成 / 材料计算', () => {
          router.pushUrl({ url: 'pages/CultivationPage' });
        })
        this.entryCard('Achievement', '成就管理', '进度统计 / UIAF 导入导出', () => {
          router.pushUrl({ url: 'pages/AchievementPage' });
        })
        this.entryCard('WikiAvatar', '角色资料', '全角色资料 / 元素 / 描述', () => {
          router.pushUrl({ url: 'pages/WikiAvatarPage' });
        })
        this.entryCard('WikiWeapon', '武器资料', '全武器资料 / 基础攻击', () => {
          router.pushUrl({ url: 'pages/WikiWeaponPage' });
        })
        this.entryCard('WikiMonster', '怪物资料', '全怪物资料 / 元素 / 阵营', () => {
          router.pushUrl({ url: 'pages/WikiMonsterPage' });
        })
        this.entryCard('Passport', '账号与数据', '多账号管理与角色绑定', () => {
          router.pushUrl({ url: 'pages/UserPage' });
        })
        this.entryCard('AvatarProperty', '我的角色', '角色列表 / 详情 / 圣遗物', () => {
          router.pushUrl({ url: 'pages/CharacterPage' });
        })
        this.entryCard('SpiralAbyss', '深境螺旋', '当期/上期战绩与出战角色', () => {
          router.pushUrl({ url: 'pages/SpiralAbyssPage' });
        })
        this.entryCard('RoleCombat', '幻想真境剧诗', '回合/奖章/候补角色', () => {
          router.pushUrl({ url: 'pages/RoleCombatPage' });
        })
        this.entryCard('HardChallenge', '强敌挑战', '单挑/多人/最佳成绩', () => {
          router.pushUrl({ url: 'pages/HardChallengePage' });
        })
        this.entryCard('CheckIn', '每日签到', '米游社每日签到与奖励', () => {
          router.pushUrl({ url: 'pages/SignInPage' });
        })
        this.entryCard('Database', '活动日历', '活动 / 卡池 / 签到条目', () => {
          router.pushUrl({ url: 'pages/CalendarPage' });
        })
        this.entryCard('Announcement', '游戏公告', '版本更新 / 活动 / 新闻', () => {
          router.pushUrl({ url: 'pages/AnnouncementPage' });
        })
        this.entryCard('⚙️', '设置', '主题 / 刷新 / 账号', () => {
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
