/**
 * SettingPage.ets（@Entry）
 * 设置：主题、沉浸光感、每日背景、便笺自动刷新、祈愿数据管理（清空/删除归档）、账号与数据入口、退出登录。
 */
import { router, LengthMetrics, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { window } from '@kit.ArkUI';
import { fileIo, fileShare, picker } from '@kit.CoreFileKit';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { UserService } from '../service/UserService';
import { DailyNoteService } from '../service/DailyNoteService';
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaArchive } from '../model/GachaArchive';
import { Logger } from '../common/Logger';
import { Motion } from '../common/Motion';
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';
import EntryAbility from '../entryability/EntryAbility';
import { GameDataService, GameDataUpdateStatus } from '../service/GameDataService';
import { GameDataUpdater } from '../data/remote/GameDataUpdater';
import { RiskVerifyService } from '../service/RiskVerifyService';
import { AiSettings } from '../components/AiSettings';
import { AppButtonModifier, UiSurface, MaterialMode, MaterialLevel, CardSurfaceModifier, ControlMaterialModifier, SelectMaterialModifier } from '../common/UiSurface';
import { BackupService } from '../service/BackupService';
import { SupportService } from '../service/SupportService';
import { BackgroundMediaService } from '../service/BackgroundMediaService';
import { BackgroundTaskSettings } from '../components/BackgroundTaskSettings';
import { MediaCacheService } from '../service/MediaCacheService';
import { AppLocaleService } from '../service/AppLocaleService';
import { LocalePolicy } from '../model/LocalePolicy';
import { CalendarWeekService } from '../service/CalendarWeekService';
import { OfficialWebShareMode, OfficialWebShareService } from '../service/OfficialWebShareService';
import { CommonOutcome, CommonOutcomeId } from '../model/CommonOutcome';
import { CommonOutcomeText } from '../model/CommonOutcomeText';

const TAG: string = 'SettingPage';
const SETTING_GROUPS: string[] = ['appearance', 'storage', 'verification', 'ai', 'account', 'home', 'other'];
const SETTING_LOCALES: string[] = ['system'].concat(LocalePolicy.locales());

/** 祈愿归档行（数据管理） */
class GachaArchiveRow {
  id: number = 0;
  uid: string = '';
  count: number = 0;
}

/** 主页卡片配置行（对齐 Windows SettingHomeCardViewModel：IsPresented + Order） */
class HomeCardRow {
  key: string = '';
  name: string = '';
  presented: boolean = true;
  order: number = 0;
}

@Entry
@Component
export struct SettingPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('helpLocaleVersion') @Watch('syncLocale') localeVersion: number = 0;
  @State localeIndex: number = 0;
  @State followSystemNotice: boolean = false;
  @State showGroupIndex: boolean = false;
  private readonly settingsScroller: Scroller = new Scroller();
  private readonly groupPositions: Map<string, number> = new Map<string, number>();
  @State themeMode: string = 'system';
  @StorageProp('reduceMotion') reduceMotion: boolean = false;
  @State mediaIndex: number = 0;
  @State mediaMuted: boolean = true;
  @State mediaLoop: boolean = true;
  @State importingVideo: boolean = false;
  @State firstWeekday: number = 1;
  @State webShareMode: OfficialWebShareMode = OfficialWebShareMode.Copy;
  @StorageProp('backgroundMediaStatus') mediaStatus: string = '';
  private mediaTypes: string[] = ['none', 'local', 'official'];
  private mediaOptions: SelectOption[] = [{ value: $r('app.string.ui_exception_close') }, { value: $r('app.string.ui_setting_background_media_local_folder') }, { value: $r('app.string.ui_setting_background_media_official_launcher_video') }];
  private weekdayOptions: SelectOption[] = [{ value: $r('app.string.ui_weekday_sunday') },
    { value: $r('app.string.ui_weekday_monday') }, { value: $r('app.string.ui_weekday_tuesday') },
    { value: $r('app.string.ui_weekday_wednesday') }, { value: $r('app.string.ui_weekday_thursday') },
    { value: $r('app.string.ui_weekday_friday') }, { value: $r('app.string.ui_weekday_saturday') }];
  @State autoRefresh: boolean = false;
  @State interval: number = 30;
  @State ambientLevel: number = 1;
  /** 界面材质（普通/高级）与高级材质级别（跟随系统推荐/低/中/高）——UiSurface 令牌层 */
  @StorageLink('materialMode') materialModeNum: number = 0;
  @StorageLink('materialLevel') materialLevelNum: number = -1;
  @State dailyBgEnabled: boolean = true;
  /** 背景图片来源（none/local/bing） */
  @StorageLink('bgType') bgType: string = 'local';
  @StorageProp('bgFolderPath') bgFolderPath: string = '';
  @State bgFolderPicking: boolean = false;
  @StorageProp('bgCopyright') bgCopyright: string = '';
  @StorageProp('bgSourceUrl') bgSourceUrl: string = '';
  @StorageProp('dailyWallpaperState') dailyWallpaperState: string = '';
  private readonly wallpaperTypes: string[] = ['none', 'local', 'bing', 'hutao', 'hoyoplay'];
  private readonly wallpaperOptions: SelectOption[] = [
    { value: $r('app.string.ui_wallpaper_none') }, { value: $r('app.string.ui_wallpaper_local') },
    { value: $r('app.string.ui_wallpaper_bing') }, { value: $r('app.string.ui_wallpaper_daily') },
    { value: $r('app.string.ui_wallpaper_launcher') },
  ];
  /** 数据源管理（GitHub 元数据更新） */
  @State dataBusy: boolean = false;
  @State dataDone: number = 0;
  @State dataTotal: number = 0;
  @State dataVersion: string = '';
  @State dataPending: string = '';
  @State dataChecking: boolean = false;
  @State dataCanRollback: boolean = false;
  @State dataCanCancel: boolean = false;
  @State dataPhase: string = '';
  @State dataCancelling: boolean = false;
  private dataOperationId: number = 0;
  private dataUnsubscribe: (() => void) | undefined = undefined;
  private dataCancelPending: boolean = false;
  private dataViewActive: boolean = false;
  private dataGeneration: number = 0;
  private dataCheckPending: boolean = false;
  private dataUpdatePending: boolean = false;
  private dataConfirmationPending: boolean = false;
  @State dataHasUpdate: string = '';
  @State dataUrl: string = '';
  /** 数据源 URL 编辑弹窗 */
  @State showUrlEdit: boolean = false;
  @State urlInput: string = '';
  /** 极验自定义组合接口编辑弹窗（对齐 Windows 无感验证 GeetestCustomUrlDialog） */
  @State showGeetestEdit: boolean = false;
  @State geetestInput: string = '';
  /** AI 分析（账号洞察）：通道与自定义 API 配置（对齐 Windows 2.0 AI 设置，双通道） */
  /** 应用版本与更新检查（GitHub Releases） */
  @State appVersion: string = '';
  @State backgroundControlsActive: boolean = false;
  /** 顶部用户卡（对齐 Windows 用户区：头像 + 昵称；currentUserId 变化驱动刷新） */
  @StorageLink('currentUserId') @Watch('refreshUserCard') currentUserIdNum: number = 0;
  @State userAvatar: string = '';
  @State userNickname: string = '';
  /** 每日一图加载状态（选中该背景时展示） */
  /** 读取主页卡片配置行（按用户顺序排序） */
  private loadHomeCardRows(): void {
    const rows: HomeCardRow[] = [];
    for (let i = 0; i < PreferencesStore.HOME_CARD_KEYS.length; i++) {
      const key: string = PreferencesStore.HOME_CARD_KEYS[i];
      const r: HomeCardRow = new HomeCardRow();
      r.key = key;
      r.name = PreferencesStore.HOME_CARD_NAMES[i];
      r.presented = PreferencesStore.getHomeCardPresented(key);
      r.order = PreferencesStore.getHomeCardOrder(key);
      rows.push(r);
    }
    rows.sort((a: HomeCardRow, b: HomeCardRow) => a.order - b.order);
    this.homeCardRows = rows;
  }

  /** 卡片显隐切换（立即生效：持久化 + bump 版本戳让主页重排） */
  private toggleHomeCard(row: HomeCardRow, presented: boolean): void {
    PreferencesStore.setHomeCardPresented(row.key, presented);
    this.loadHomeCardRows();
    this.bumpHomeCardsVersion();
  }

  /** 卡片上移/下移（delta=-1/+1）：与相邻卡片交换顺序值 */
  private moveHomeCard(row: HomeCardRow, delta: number): void {
    const idx: number = this.homeCardRows.indexOf(row);
    const otherIdx: number = idx + delta;
    if (idx < 0 || otherIdx < 0 || otherIdx >= this.homeCardRows.length) {
      return;
    }
    const other: HomeCardRow = this.homeCardRows[otherIdx];
    PreferencesStore.setHomeCardOrder(row.key, other.order);
    PreferencesStore.setHomeCardOrder(other.key, row.order);
    this.loadHomeCardRows();
    this.bumpHomeCardsVersion();
  }

  /** 主页卡片配置版本戳（Index 订阅重读配置） */
  private bumpHomeCardsVersion(): void {
    const v: number = (AppStorage.get<number>('homeCardsVersion') ?? 0) + 1;
    AppStorage.setOrCreate<number>('homeCardsVersion', v);
  }

  /** 主页游戏活动区域设置（对齐 Windows：日历显示默认开 / 未在进行中活动默认关） */
  @State homeActCalendarShown: boolean = true;
  @State homeActPreview: boolean = false;
  /** 主页卡片配置行（显隐 + 顺序，对齐 Windows SettingHomeCardViewModel） */
  @State homeCardRows: HomeCardRow[] = [];
  /** 自动签到开关（默认开，对齐 Windows AutoSignInEnabled 默认 true） */
  @State autoSignIn: boolean = true;
  @StorageProp('isLoggedIn') isLoggedIn: boolean = false;
  /** 祈愿归档（数据管理） */
  @State gachaRows: GachaArchiveRow[] = [];
  @State gachaEmptyOverview: boolean = false;
  @State gachaEmptyHistory: boolean = false;
  @State gachaUnobtained: boolean = false;
  /** 媒体与图标缓存占用文本（进入设置页后台统计） */
  @State mediaCacheSize: string = '';
  /** 缓存清理进行中（防重复点击） */
  @State mediaCacheBusy: boolean = false;
  private mediaCachePending: boolean = false;
  private mediaCacheRead: number = 0;

  aboutToAppear(): void {
    this.loadPreferences();
    this.refreshUserCard();
    this.backgroundControlsActive = true;
    this.attachDataUpdates();
    this.mediaCacheBusy = this.mediaCachePending;
    this.refreshMediaCacheSize();
    this.loadAppVersion();
    this.loadGachaRows();
  }

  private loadPreferences(): void {
    this.syncLocale();
    this.gachaEmptyOverview = PreferencesStore.getBool(PreferencesStore.KEY_GACHA_EMPTY_OVERVIEW, false);
    this.gachaEmptyHistory = PreferencesStore.getBool(PreferencesStore.KEY_GACHA_EMPTY_HISTORY, false);
    this.gachaUnobtained = PreferencesStore.getBool(PreferencesStore.KEY_GACHA_UNOBTAINED, false);
    this.mediaIndex = Math.max(0, this.mediaTypes.indexOf(PreferencesStore.getString(BackgroundMediaService.TYPE_KEY, 'none')));
    this.mediaMuted = PreferencesStore.getBool(BackgroundMediaService.MUTED_KEY, true);
    this.mediaLoop = PreferencesStore.getBool(BackgroundMediaService.LOOP_KEY, true);
    this.firstWeekday = CalendarWeekService.firstDayOfWeek();
    this.themeMode = PreferencesStore.getThemeMode();
    this.webShareMode = OfficialWebShareService.shareMode();
    Motion.setReducedMotion(PreferencesStore.getReduceMotionEnabled());
    this.autoRefresh = PreferencesStore.getAutoRefreshEnabled();
    this.interval = PreferencesStore.getRefreshIntervalMinutes();
    // 界面材质（UiSurface 令牌层；StorageLink 与壳层共享同一状态，切换即时生效）
    this.materialModeNum = PreferencesStore.getMaterialMode();
    this.materialLevelNum = PreferencesStore.getMaterialLevel();
    this.dailyBgEnabled = PreferencesStore.getDailyBgEnabled();
    this.dataUrl = GameDataUpdater.manifestUrl();
    this.geetestInput = RiskVerifyService.getCustomCompositeUrl();
    this.homeActCalendarShown = PreferencesStore.getHomeActCalendar();
    this.autoSignIn = PreferencesStore.getAutoSignInEnabled();
    this.loadHomeCardRows();
    this.homeActPreview = PreferencesStore.getHomeActPreview();
  }

  private async openWallpaperSource(): Promise<void> {
    if (this.bgSourceUrl.length === 0) { return; }
    try {
      await this.getHostContext()?.openLink(this.bgSourceUrl);
    } catch (_) {
      this.toast(CommonOutcomeText.text(new CommonOutcome(CommonOutcomeId.Failed), AppLocaleService.current()));
    }
  }

  /** 当前应用版本号（bundleManager versionName） */
  private loadAppVersion(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = info.versionName;
    } catch (e) {
      Logger.warn('SettingPage', `versionName fail: ${(e as Error).message}`);
    }
  }

  private getHostContext(): common.UIAbilityContext | undefined {
    const ctx = this.getUIContext().getHostContext();
    return ctx !== undefined ? ctx as common.UIAbilityContext : undefined;
  }

  /** 导出全量备份 JSON（用户自选保存位置） */
  async exportBackup(): Promise<void> {
    try {
      const json: string = await BackupService.getInstance().buildBackupJson();
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.newFileNames = [`hutao_backup_${Date.now()}.json`];
      const uris: string[] = await docPicker.save(opts);
      if (uris.length === 0) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, json);
      } finally {
        fileIo.closeSync(file);
      }
      this.toast('备份导出成功（含账号凭证，请妥善保管）');
    } catch (e) {
      this.toast(`导出失败：${(e as Error).message}`);
    }
  }

  /** 还原前二次确认（覆盖式，不可撤销） */
  private confirmRestoreBackup(): void {
    this.getUIContext().showAlertDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: $r('app.string.ui_settings_restore_backup'),
      message: $r('app.string.ui_settings_restore_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.ui_settings_restore_backup'),
        fontColor: $r('app.color.danger'),
        action: () => {
          this.restoreBackup();
        }
      },
      cancel: () => {
      }
    });
  }

  /** 选择备份文件并还原 */
  async restoreBackup(): Promise<void> {
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      opts.fileSuffixFilters = ['.json'];
      const uris: string[] = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      let text: string;
      try {
        const buf = new ArrayBuffer(fileIo.statSync(file.fd).size);
        fileIo.readSync(file.fd, buf);
        text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
      } finally {
        fileIo.closeSync(file);
      }
      const result = await BackupService.getInstance().restoreFromText(text);
      if (result.ok) {
        this.loadPreferences();
        this.applyTheme(this.themeMode);
        this.refreshUserCard();
        this.loadGachaRows();
      }
      this.toast(result.message);
    } catch (e) {
      this.toast(`还原失败：${(e as Error).message}`);
    }
  }

  /** 保存极验自定义组合接口（留空禁用） */
  applyGeetestUrl(): void {
    const template: string = this.geetestInput.trim();
    PreferencesStore.setString(PreferencesStore.KEY_GEETEST_CUSTOM_URL, template);
    this.showGeetestEdit = false;
    this.toast(template.length > 0 ? '已保存，触发人机验证时优先尝试自动过验' : '已清除，恢复弹窗验证');
  }

  /** 载入祈愿归档与各归档记录数 */
  async loadGachaRows(): Promise<void> {
    try {
      const archives: GachaArchive[] = await GachaRepo.getAllArchives();
      const rows: GachaArchiveRow[] = [];
      for (const a of archives) {
        const row: GachaArchiveRow = new GachaArchiveRow();
        row.id = a.id;
        row.uid = a.uid;
        row.count = await GachaRepo.countAll(a.id);
        rows.push(row);
      }
      this.gachaRows = rows;
    } catch (e) {
      Logger.warn(TAG, `load gacha rows fail: ${(e as Error).message}`);
    }
  }

  /** 删除单个祈愿归档（二次确认） */
  confirmDeleteArchive(row: GachaArchiveRow): void {
    this.getUIContext().getPromptAction().showDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: $r('app.string.ui_settings_delete_wish_archive'),
      message: `UID ${row.uid} · ${row.count}`,
      buttons: [
        { text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') },
        { text: $r('app.string.ui_account_insights_delete'), color: $r('app.color.danger') },
      ],
    }).then((dlg: ShowDialogSuccessResponse) => {
      if (dlg.index === 1) {
        GachaRepo.deleteArchiveByUid(row.uid).then(() => {
          this.toast('已删除');
          this.loadGachaRows();
        });
      }
    });
  }

  /** 清空全部祈愿数据（二次确认） */
  confirmClearAllGacha(): void {
    this.getUIContext().getPromptAction().showDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: $r('app.string.ui_settings_delete_wish'),
      message: $r('app.string.ui_settings_delete_wish_confirm'),
      buttons: [
        { text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') },
        { text: $r('app.string.ui_action_clear'), color: $r('app.color.danger') },
      ],
    }).then((dlg: ShowDialogSuccessResponse) => {
      if (dlg.index === 1) {
        GachaRepo.getAllArchives().then((archives: GachaArchive[]) => {
          const tasks: Promise<void>[] = [];
          for (const a of archives) {
            tasks.push(GachaRepo.deleteArchive(a.id));
          }
          Promise.all(tasks).then(() => {
            this.toast('已清空全部祈愿数据');
            this.loadGachaRows();
          });
        });
      }
    });
  }

  toast(msg: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1500 });
  }

  /** 让自动刷新设置实时生效 */
  syncAutoTimer(): void {
    if (this.autoRefresh) {
      DailyNoteService.getInstance().startAutoRefresh(PreferencesStore.getRefreshIntervalMinutes());
    } else {
      DailyNoteService.getInstance().stopAutoRefresh();
    }
  }

  private applyReduceMotion(enabled: boolean): void {
    PreferencesStore.setReduceMotionEnabled(enabled);
    Motion.setReducedMotion(enabled);
  }

  applyTheme(mode: string): void {
    PreferencesStore.setThemeMode(mode);
    this.themeMode = mode;
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return;
    }
    try {
      const appCtx: common.ApplicationContext = host.getApplicationContext();
      if (mode === 'light') {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === 'dark') {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
      // 同步深浅色状态（驱动壁纸遮罩/状态栏图标色）
      let sysDark: boolean = false;
      let applyOk: boolean = false;
      try {
        const cfg = appCtx.resourceManager.getConfigurationSync();
        // resourceManager.ColorMode：DARK=0；仅显式为深色才判深色（浅色/未设置均非深色）
        sysDark = cfg !== undefined && cfg.colorMode === 0;
        applyOk = true;
      } catch (e) {
        Logger.warn(TAG, 'read sys colorMode fail');
      }
      const isDark: boolean = mode === 'dark' || (mode !== 'light' && sysDark);
      AppStorage.setOrCreate<boolean>('isDarkMode', isDark);
      // setColorMode 后配置异步生效：跟随系统模式延迟重读兜底，避免读到旧配置导致主题错判
      if (mode !== 'light' && mode !== 'dark') {
        setTimeout(() => {
          try {
            const lateCfg = appCtx.resourceManager.getConfigurationSync();
            if (lateCfg !== undefined) {
              const lateDark: boolean = lateCfg.colorMode === 0;
              AppStorage.setOrCreate<boolean>('isDarkMode', lateDark);
            }
          } catch (e) {
            Logger.warn(TAG, 'late read sys colorMode fail');
          }
        }, 150);
      }
      // 状态栏图标色 + 窗口根底色同步深浅色
      window.getLastWindow(host).then((win: window.Window) => {
        EntryAbility.applySystemBarColors(win);
        EntryAbility.applyWindowBackdrop(win);
      }).catch(() => {
      });
    } catch (e) {
      Logger.warn(TAG, 'applyTheme fail');
    }
  }

  /** 顶部用户卡数据刷新（登录/切换/退出时由 currentUserId 变化驱动） */
  refreshUserCard(): void {
    const user = UserService.getInstance().getCurrentUser();
    this.userAvatar = user !== undefined ? user.avatar : '';
    this.userNickname = user !== undefined ? user.displayName : '';
  }

  /** 顶部用户卡（对齐 Windows 用户区：圆形头像 + 昵称；未登录显示登录入口） */
  @Builder
  userCard() {
    Row({ space: 12 }) {
      if (this.userAvatar.length > 0) {
        Image(this.userAvatar)
          .width(48)
          .height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.app_primary_bg'))
          .draggable(false)
      } else {
        Column() {
          Text(this.isLoggedIn && this.userNickname.length > 0 ? this.userNickname.substring(0, 1) : '旅')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_primary_text'))
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.app_primary_bg'))
      }
      Column({ space: 3 }) {
        Text(this.isLoggedIn && this.userNickname.length > 0 ? this.userNickname : $r('app.string.ui_settings_not_logged_in'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.isLoggedIn ? $r('app.string.ui_settings_signed_in') : $r('app.string.ui_account_insights_no_account'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Button(this.isLoggedIn ? $r('app.string.ui_section_account') : $r('app.string.page_title_login'),
        { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum, !this.isLoggedIn))
        .fontSize(13)
        .height(44)
        .accessibilityText(this.isLoggedIn ? '打开账号与数据' : '前往登录')
        .onClick(() => {
          router.pushUrl({ url: this.isLoggedIn ? 'pages/UserPage' : 'pages/LoginPage' }).catch(() => {
          });
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  header() {
    PageHeader({ title: $r('app.string.page_title_setting'), embedMode: this.embedMode, topAvoidVp: this.topAvoidVp })
  }

  @Builder
  sectionTitle(title: ResourceStr) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ top: 14, bottom: 6 })
  }

  private groupLabel(id: string): Resource {
    switch (id) {
      case 'appearance': return $r('app.string.ui_section_appearance');
      case 'storage': return $r('app.string.ui_section_storage');
      case 'verification': return $r('app.string.ui_section_verification');
      case 'ai': return $r('app.string.ui_section_ai');
      case 'account': return $r('app.string.ui_section_account');
      case 'home': return $r('app.string.ui_section_home');
      default: return $r('app.string.ui_section_other');
    }
  }

  @Builder
  groupTitle(id: string) {
    Row({ space: 8 }) {
      Divider().vertical(true).height(14).color($r('app.color.app_primary')).strokeWidth(3)
      Text(this.groupLabel(id))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .margin({ top: 18, bottom: 2 })
    .alignItems(VerticalAlign.Center)
    .onAreaChange((_old: Area, area: Area) => {
      this.groupPositions.set(id, Number(area.position.y));
    })
  }

  private scrollToGroup(id: string): void {
    const position: number | undefined = this.groupPositions.get(id);
    if (position === undefined || !Number.isFinite(position)) { return; }
    this.settingsScroller.scrollTo({ xOffset: 0, yOffset: Math.max(0, position - 12), animation: false });
  }

  @Builder
  groupIndex() {
    Scroll() {
      Column({ space: 2 }) {
        ForEach(SETTING_GROUPS, (id: string) => {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Text(this.groupLabel(id))
              .width('100%')
              .textAlign(TextAlign.Start)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
          }
            .width('100%')
            .constraintSize({ minHeight: 44 })
            .padding({ left: 10, right: 10 })
            .backgroundColor(Color.Transparent)
            .borderRadius(8)
            .accessibilityGroup(true)
            .hoverEffect(HoverEffect.Highlight).onClick(() => this.scrollToGroup(id))
        }, (id: string): string => id)
      }
      .width('100%')
      .padding(4)
      .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum, false))
      .border({ width: 1, color: $r('app.color.card_stroke'), radius: 12 })
    }
    .width(152)
    .height('100%')
    .padding({ left: 4, right: 12, top: 16 })
    .align(Alignment.TopStart)
    .scrollBar(BarState.Auto)
  }

  syncLocale(): void {
    this.localeIndex = Math.max(0, SETTING_LOCALES.indexOf(AppLocaleService.preference()));
    this.followSystemNotice = AppLocaleService.restartRequired();
    this.firstWeekday = CalendarWeekService.firstDayOfWeek();
  }

  private localeOptions(): SelectOption[] {
    return SETTING_LOCALES.map((locale: string): SelectOption => ({
      value: locale === 'system' ? $r('app.string.ui_language_system') : LocalePolicy.nativeName(locale)
    }));
  }

  private selectLocale(index: number): void {
    const locale: string | undefined = SETTING_LOCALES[index];
    if (locale === undefined) { return; }
    if (!AppLocaleService.select(locale)) {
      this.toast(CommonOutcomeText.text(new CommonOutcome(CommonOutcomeId.LocaleFailed), AppLocaleService.current()));
      return;
    }
    this.localeIndex = index;
    this.followSystemNotice = AppLocaleService.restartRequired();
  }

  @Builder
  webShareSetting() {
    Flex({ direction: this.showGroupIndex ? FlexDirection.Row : FlexDirection.Column, space: { main: LengthMetrics.vp(12) } }) {
      Column({ space: 4 }) {
        Text($r('app.string.ui_web_share_title')).fontSize(14).fontColor($r('app.color.text_primary'))
        Text($r('app.string.ui_web_share_description')).fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(this.showGroupIndex ? 1 : 0)
      Select([{ value: $r('app.string.ui_web_share_copy') }, { value: $r('app.string.ui_web_share_file') }])
        .attributeModifier(new SelectMaterialModifier(this.materialModeNum, this.materialLevelNum))
        .selected(this.webShareMode === OfficialWebShareMode.Copy ? 0 : 1)
        .value(this.webShareMode === OfficialWebShareMode.Copy ? $r('app.string.ui_web_share_copy') : $r('app.string.ui_web_share_file'))
        .width(this.showGroupIndex ? 208 : '100%')
        .constraintSize({ minHeight: 44 })
        .onSelect((index: number) => {
          this.webShareMode = index === 0 ? OfficialWebShareMode.Copy : OfficialWebShareMode.SavePng;
          OfficialWebShareService.setShareMode(this.webShareMode);
        })
    }
    .width('100%').padding(14)
    .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum)).borderRadius(8)
  }

  @Builder
  localeSection() {
    Column({ space: 6 }) {
      if (this.showGroupIndex) {
        Row({ space: 12 }) {
          Text($r('app.string.ui_section_language'))
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          this.localeSelect()
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
        .border({ width: 1, color: $r('app.color.card_stroke'), radius: 12 })
      } else {
        this.sectionTitle($r('app.string.ui_section_language'))
        this.localeSelect()
      }
      if (this.followSystemNotice) {
        Text($r('app.string.ui_language_restart_system')).fontSize(12).fontColor($r('app.color.text_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  localeSelect() {
    Select(this.localeOptions()).selected(this.localeIndex).value(this.localeOptions()[this.localeIndex].value)
      .width(this.showGroupIndex ? 208 : '100%').constraintSize({ minHeight: 44 })
      .font({ size: 14 })
      .attributeModifier(new SelectMaterialModifier(this.materialModeNum, this.materialLevelNum))
      .accessibilityText($r('app.string.ui_section_language'))
      .onSelect((index: number) => this.selectLocale(index))
  }

  @Builder
  themeSection() {
    Flex({ wrap: FlexWrap.Wrap }) {
      this.themeChip('system', $r('app.string.ui_language_system'))
      this.themeChip('light', $r('app.string.ui_theme_light'))
      this.themeChip('dark', $r('app.string.ui_theme_dark'))
    }
    .width('100%')
  }

  private gachaDisplayLabel(key: string): Resource {
    if (key === PreferencesStore.KEY_GACHA_EMPTY_OVERVIEW) { return $r('app.string.ui_wish_show_empty_overview'); }
    if (key === PreferencesStore.KEY_GACHA_EMPTY_HISTORY) { return $r('app.string.ui_wish_show_empty_history'); }
    return $r('app.string.ui_wish_show_unobtained');
  }

  private gachaDisplayEnabled(key: string): boolean {
    if (key === PreferencesStore.KEY_GACHA_EMPTY_OVERVIEW) { return this.gachaEmptyOverview; }
    if (key === PreferencesStore.KEY_GACHA_EMPTY_HISTORY) { return this.gachaEmptyHistory; }
    return this.gachaUnobtained;
  }

  @Builder
  gachaDisplayOption(key: string) {
    Row({ space: 12 }) {
      Text(this.gachaDisplayLabel(key)).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.gachaDisplayEnabled(key) }).attributeModifier(new ControlMaterialModifier(this.materialModeNum, this.materialLevelNum))
        .selectedColor($r('app.color.app_primary'))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.gachaDisplayLabel(key))
        .onChange((checked: boolean): void => {
          if (key === PreferencesStore.KEY_GACHA_EMPTY_OVERVIEW) { this.gachaEmptyOverview = checked; }
          else if (key === PreferencesStore.KEY_GACHA_EMPTY_HISTORY) { this.gachaEmptyHistory = checked; }
          else { this.gachaUnobtained = checked; }
          PreferencesStore.setBool(key, checked);
          AppStorage.setOrCreate<number>('gachaDisplayVersion', (AppStorage.get<number>('gachaDisplayVersion') ?? 0) + 1);
        })
    }
    .width('100%').padding(14).constraintSize({ minHeight: 52 })
    .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum)).borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  wallpaperSelector() {
    Row({ space: 8 }) {
      Text($r('app.string.ui_section_background')).fontSize(14)
        .fontColor($r('app.color.text_primary')).layoutWeight(1)
      Select(this.wallpaperOptions)
        .attributeModifier(new SelectMaterialModifier(this.materialModeNum, this.materialLevelNum))
        .selected(this.wallpaperTypes.indexOf(this.bgType))
        .value(this.wallpaperOptions[Math.max(0, this.wallpaperTypes.indexOf(this.bgType))].value)
        .width(this.showGroupIndex ? 208 : '58%').constraintSize({ minHeight: 44 })
        .onSelect((index: number): void => {
          this.bgType = this.wallpaperTypes[index];
          PreferencesStore.setBackgroundImageType(this.bgType);
        })
    }.width('100%')
  }

  /** Detach observation without cancelling foreground work or writing torn-down State. */
  onPageShow(): void { this.backgroundControlsActive = true; }

  onPageHide(): void { this.backgroundControlsActive = false; }

  aboutToDisappear(): void {
    this.backgroundControlsActive = false;
    this.dataViewActive = false; this.dataGeneration++;
    this.dataUnsubscribe?.(); this.dataUnsubscribe = undefined;
  }

  private attachDataUpdates(): void {
    this.dataUnsubscribe?.(); this.dataUnsubscribe = undefined;
    this.dataViewActive = true; this.dataGeneration++;
    const generation: number = this.dataGeneration;
    this.dataChecking = this.dataCheckPending;
    this.refreshDataState();
    this.dataUnsubscribe = GameDataService.subscribeUpdate((status: GameDataUpdateStatus): void => {
      if (this.dataViewActive && generation === this.dataGeneration) { this.applyDataUpdateStatus(status); }
    });
  }

  private dataActionBlocked(): boolean {
    return this.dataCheckPending || this.dataUpdatePending || this.dataConfirmationPending ||
      !GameDataService.updateStatus().settled;
  }

  private applyDataUpdateStatus(status: GameDataUpdateStatus): void {
    if (!this.dataViewActive || status.id < this.dataOperationId) { return; }
    this.dataOperationId = status.id;
    this.dataBusy = this.dataUpdatePending || !status.settled;
    this.dataCanCancel = status.canCancel;
    this.dataCancelling = status.state === 'cancelling' && !status.settled;
    this.dataDone = status.done; this.dataTotal = status.total;
    const count: string = status.total > 0 ? ` · 已校验 ${status.done}/${status.total}` : '';
    if (status.state === 'preparing') { this.dataPhase = '正在确认数据版本'; }
    else if (status.state === 'downloading') { this.dataPhase = `正在下载与校验 · ${status.activeFiles} 个任务进行中${count}`; }
    else if (status.state === 'validating') { this.dataPhase = `正在校验完整数据${count}`; }
    else if (this.dataCancelling) { this.dataPhase = `正在取消，等待已启动任务结束${count}`; }
    else if (status.state === 'failed' && !status.settled) { this.dataPhase = `更新失败，等待已启动任务结束${count}`; }
    else { this.dataPhase = ''; }
    if (!status.settled) { return; }
    this.refreshDataState();
    if (status.state === 'completed') {
      this.dataHasUpdate = this.dataPending.length > 0 ? `更新操作已完成；${this.dataPending}` : '更新操作已完成，已保存数据未变化';
    } else if (status.state === 'cancelled') { this.dataHasUpdate = '更新已取消，当前数据保持不变'; }
    else if (status.state === 'failed') { this.dataHasUpdate = `更新失败：${status.error}`; }
  }

  private refreshDataState(): void {
    this.dataVersion = GameDataService.getInstance().remoteVersion();
    const pending: string = GameDataService.getInstance().pendingState();
    this.dataPending = pending === 'bundled' ? '已安排恢复内置数据，重启后生效' :
      (pending === 'remote' ? `已保存 ${GameDataService.getInstance().pendingVersion()}，重启后生效` : '');
    this.dataCanRollback = GameDataService.getInstance().canRollback();
  }

  private refreshMediaCacheSize(): void {
    const generation: number = this.dataGeneration;
    const read: number = ++this.mediaCacheRead;
    MediaCacheService.size().then((bytes: number) => {
      if (!this.dataViewActive || generation !== this.dataGeneration || read !== this.mediaCacheRead) { return; }
      this.mediaCacheSize = MediaCacheService.formatSize(bytes);
    }).catch(() => {
      if (!this.dataViewActive || generation !== this.dataGeneration || read !== this.mediaCacheRead) { return; }
      this.mediaCacheSize = '';
    });
  }

  private async clearMediaCache(): Promise<void> {
    if (!this.dataViewActive || this.mediaCachePending) { return; }
    const generation: number = this.dataGeneration;
    this.mediaCacheRead++;
    this.mediaCachePending = true;
    this.mediaCacheBusy = true;
    try {
      const ok: boolean = await MediaCacheService.clear();
      if (this.dataViewActive && generation === this.dataGeneration) {
        this.toast(ok ? '缓存已清理' : '部分缓存清理失败，可重试');
      }
    } catch (e) {
      if (this.dataViewActive && generation === this.dataGeneration) { this.toast('清理失败，请稍后重试'); }
    } finally {
      this.mediaCachePending = false;
      if (this.dataViewActive) {
        this.mediaCacheBusy = false;
        this.refreshMediaCacheSize();
      }
    }
  }

  /** Checking never changes the process-pinned dataset. */
  async checkDataUpdate(): Promise<void> {
    if (!this.dataViewActive || this.dataActionBlocked()) { return; }
    const generation: number = this.dataGeneration;
    this.dataCheckPending = true; this.dataChecking = true;
    try {
      const has: boolean | null = await GameDataService.getInstance().checkUpdateAvailable();
      if (!this.dataViewActive || generation !== this.dataGeneration) { return; }
      this.refreshDataState();
      this.dataHasUpdate = has === null ? '检查失败：请确认受信任的数据源地址与网络' :
        (has ? '发现新版本，可下载并校验完整数据；重启后生效' :
          (this.dataPending.length > 0 ? this.dataPending : '已是最新版本'));
    } catch (e) {
      if (this.dataViewActive && generation === this.dataGeneration) { this.dataHasUpdate = `检查失败：${(e as Error).message}`; }
    } finally {
      this.dataCheckPending = false;
      if (this.dataViewActive) { this.dataChecking = false; }
    }
  }

  async updateGameData(): Promise<void> {
    if (!this.dataViewActive || this.dataActionBlocked()) { return; }
    const generation: number = this.dataGeneration;
    this.dataUpdatePending = true; this.dataBusy = true;
    this.dataDone = 0; this.dataTotal = 0; this.dataHasUpdate = '';
    let operationId: number = this.dataOperationId;
    try {
      // Progress belongs to the service subscription, not this page's Promise lifetime.
      const update: Promise<string> = GameDataService.getInstance().updateAll();
      operationId = GameDataService.updateStatus().id;
      await update;
      if (!this.dataViewActive || generation !== this.dataGeneration || operationId !== GameDataService.updateStatus().id) { return; }
      this.applyDataUpdateStatus(GameDataService.updateStatus());
      this.toast(this.dataPending.length > 0 ? '新数据已保存，重启应用后生效' : '更新操作已完成');
    } catch (e) {
      if (this.dataViewActive && generation === this.dataGeneration && operationId === GameDataService.updateStatus().id) {
        const status: GameDataUpdateStatus = GameDataService.updateStatus();
        this.applyDataUpdateStatus(status);
        if (status.state !== 'cancelled' && status.state !== 'failed') { this.dataHasUpdate = `更新未完成：${(e as Error).message}`; }
      }
    } finally {
      this.dataUpdatePending = false;
      if (this.dataViewActive) {
        // Reconcile ownership without replacing a new error with an older terminal status.
        this.dataBusy = !GameDataService.updateStatus().settled; this.refreshDataState();
      }
    }
  }

  private async cancelGameData(): Promise<void> {
    if (!this.dataViewActive || this.dataCancelPending || this.dataConfirmationPending || !this.dataCanCancel) { return; }
    const generation: number = this.dataGeneration;
    const operationId: number = this.dataOperationId;
    this.dataCancelPending = true; this.dataConfirmationPending = true;
    try {
      const response: ShowDialogSuccessResponse = await this.getUIContext().getPromptAction().showDialog({ systemMaterial: UiSurface.dialogMaterial(),
        title: $r('app.string.ui_settings_cancel_update'),
        message: $r('app.string.ui_settings_stop_download'),
        buttons: [{ text: $r('app.string.ui_action_continue'), color: $r('app.color.text_secondary') }, { text: $r('app.string.ui_settings_cancel_update'), color: $r('app.color.app_primary') }],
      });
      if (!this.dataViewActive || generation !== this.dataGeneration || response.index !== 1) { return; }
      const result: GameDataUpdateStatus = await GameDataService.cancelUpdate(operationId);
      if (!this.dataViewActive || generation !== this.dataGeneration || result.id !== operationId ||
        GameDataService.updateStatus().id !== operationId) { return; }
      this.applyDataUpdateStatus(GameDataService.updateStatus());
      if (result.state === 'completed') { this.toast('更新已经完成，取消不会撤销已保存结果；请重启后查看'); }
      else if (result.state === 'cancelled') { this.toast('本次更新已取消'); }
    } catch (e) {
      if (this.dataViewActive && generation === this.dataGeneration) { this.toast(`无法完成取消：${(e as Error).message}`); }
    } finally {
      this.dataCancelPending = false; this.dataConfirmationPending = false;
      if (this.dataViewActive) { this.applyDataUpdateStatus(GameDataService.updateStatus()); }
    }
  }

  applyDataUrl(): void {
    if (!this.dataViewActive || this.dataActionBlocked()) { return; }
    try {
      const url: string = this.urlInput.trim();
      GameDataUpdater.setManifestUrl(url);
      this.dataUrl = GameDataUpdater.manifestUrl();
      this.showUrlEdit = false;
      this.dataHasUpdate = '';
      this.toast('受信任数据源已保存，下次更新使用');
    } catch (e) { this.toast(`数据源未更改：${(e as Error).message}`); }
  }

  private async changeSavedData(rollback: boolean): Promise<void> {
    if (!this.dataViewActive || this.dataActionBlocked()) { return; }
    const generation: number = this.dataGeneration;
    this.dataConfirmationPending = true;
    let response: ShowDialogSuccessResponse;
    try {
      response = await this.getUIContext().getPromptAction().showDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: rollback ? $r('app.string.ui_settings_previous_data') : $r('app.string.ui_settings_reset_builtin'),
      message: $r('app.string.ui_settings_data_next_launch'),
      buttons: [{ text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') }, { text: $r('app.string.common_confirm'), color: $r('app.color.app_primary') }],
      });
    } finally { this.dataConfirmationPending = false; }
    if (!this.dataViewActive || generation !== this.dataGeneration || response.index !== 1 || this.dataActionBlocked()) { return; }
    this.dataUpdatePending = true; this.dataBusy = true;
    try {
      if (rollback) {
        if (!await GameDataService.rollbackRemote()) { throw new Error('没有可用的上一版数据'); }
      } else { GameDataService.clearRemote(); }
      if (this.dataViewActive && generation === this.dataGeneration) { this.refreshDataState(); this.toast('下次启动的数据已调整，请重启应用'); }
    } catch (e) {
      if (this.dataViewActive && generation === this.dataGeneration) { this.toast(`未能调整数据：${(e as Error).message}`); }
    } finally {
      this.dataUpdatePending = false;
      if (this.dataViewActive) { this.applyDataUpdateStatus(GameDataService.updateStatus()); }
    }
  }

  /** 选择本地背景图片文件夹（FOLDER 模式） */
  async pickBgFolder(): Promise<void> {
    if (this.bgFolderPicking) { return; }
    this.bgFolderPicking = true;
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.selectMode = picker.DocumentSelectMode.FOLDER;
      const uris: string[] = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      let persisted: boolean = false;
      if (canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) {
        const policy: fileShare.PolicyInfo = { uri: uri, operationMode: fileShare.OperationMode.READ_MODE };
        try {
          await fileShare.persistPermission([policy]);
          persisted = true;
        } catch (_) {
          Logger.warn(TAG, 'persist background folder read permission failed');
        }
      }
      if (persisted) { PreferencesStore.setBackgroundFolderPath(uri); }
      AppStorage.setOrCreate<string>('bgFolderPath', uri);
      this.toast(persisted ? $r('app.string.ui_bg_folder_saved') : $r('app.string.ui_bg_folder_temporary'));
    } catch (_) {
      this.toast($r('app.string.ui_bg_folder_picker_failed'));
    } finally {
      this.bgFolderPicking = false;
    }
  }

  async importBackgroundVideos(): Promise<void> {
    if (this.importingVideo) { return; }
    this.importingVideo = true;
    try {
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 10;
      options.fileSuffixFilters = ['视频|.mp4,.mov,.webm,.mkv,.m4v'];
      const uris: string[] = await new picker.DocumentViewPicker().select(options);
      if (uris.length === 0) { return; }
      const count: number = await BackgroundMediaService.importVideos(uris);
      this.mediaIndex = 1;
      this.toast(`已导入 ${count} 个视频`);
    } catch (error) {
      this.toast(`视频导入失败：${(error as Error).message}`);
    } finally {
      this.importingVideo = false;
    }
  }

  @Builder
  backgroundMediaSection() {
    this.sectionTitle($r('app.string.ui_section_background_video'))
    Column({ space: 12 }) {
      Select(this.mediaOptions).attributeModifier(new SelectMaterialModifier(this.materialModeNum, this.materialLevelNum)).selected(this.mediaIndex).value(this.mediaOptions[this.mediaIndex].value)
        .onSelect((index: number) => {
          this.mediaIndex = index;
          PreferencesStore.setString(BackgroundMediaService.TYPE_KEY, this.mediaTypes[index]);
          BackgroundMediaService.changed();
        }).hoverEffect(HoverEffect.Highlight)
      if (this.mediaIndex === 1) {
        Button(this.importingVideo ? $r('app.string.ui_common_loading') : $r('app.string.ui_settings_choose_video'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum)).constraintSize({ minHeight: 44 })
          .enabled(!this.importingVideo)
          .onClick(() => { this.importBackgroundVideos(); })
        Text($r('app.string.ui_settings_random_video')).fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      Row({ space: 12 }) {
        Text($r('app.string.ui_setting_background_video_is_muted_header')).fontColor($r('app.color.text_primary'))
        Toggle({ type: ToggleType.Switch, isOn: this.mediaMuted }).attributeModifier(new ControlMaterialModifier(this.materialModeNum, this.materialLevelNum)).onChange((value: boolean) => {
          this.mediaMuted = value;
          PreferencesStore.setBool(BackgroundMediaService.MUTED_KEY, value);
          BackgroundMediaService.changed();
        })
        Text($r('app.string.ui_setting_background_video_is_looping_header')).fontColor($r('app.color.text_primary'))
        Toggle({ type: ToggleType.Switch, isOn: this.mediaLoop }).attributeModifier(new ControlMaterialModifier(this.materialModeNum, this.materialLevelNum)).onChange((value: boolean) => {
          this.mediaLoop = value;
          PreferencesStore.setBool(BackgroundMediaService.LOOP_KEY, value);
          BackgroundMediaService.changed();
        })
      }
      Text(this.mediaStatus).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text($r('app.string.ui_settings_video_fallback'))
        .fontSize(12).fontColor($r('app.color.text_secondary'))
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
      .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum)).borderRadius(12)
    this.sectionTitle($r('app.string.ui_section_calendar'))
    Row({ space: 12 }) {
      Text($r('app.string.ui_setting_apperance_first_day_of_week_header')).fontColor($r('app.color.text_primary')).layoutWeight(1)
      Select(this.weekdayOptions).attributeModifier(new SelectMaterialModifier(this.materialModeNum, this.materialLevelNum)).selected(this.firstWeekday).value(this.weekdayOptions[this.firstWeekday].value)
        .onSelect((index: number) => {
          this.firstWeekday = index;
          CalendarWeekService.setFirstDayOfWeek(index);
          AppStorage.setOrCreate('calendarSettingsVersion', Date.now());
        }).hoverEffect(HoverEffect.Highlight)
    }.width('100%').padding(14).attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum)).borderRadius(12)
  }

  @Builder
  themeChip(mode: string, label: ResourceStr) {
    Text(label)
      .fontSize(14)
      .fontColor(this.themeMode === mode ? $r('app.color.app_primary_text') : $r('app.color.text_primary'))
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .margin({ right: 8, bottom: 4 })
      .backgroundColor(this.themeMode === mode ? $r('app.color.app_primary_bg') : $r('app.color.card_surface'))
      .border({ width: 1, radius: 10,
        color: this.themeMode === mode ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.themeMode = mode;
        this.applyTheme(mode);
      })
  }

  /** 界面材质模式滑块段（对齐 Windows「材质：默认/液态玻璃」切换；普通材质=磨砂半透明+阴影非纯色） */
  @Builder
  materialModeChip(value: number, label: Resource, desc: Resource) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(14)
        .fontWeight(this.materialModeNum === value ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.materialModeNum === value ? $r('app.color.app_primary_text') : $r('app.color.text_primary'))
      Text(desc)
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
    }
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(this.materialModeNum === value ? $r('app.color.app_primary_bg') : $r('app.color.card_inner_tint'))
    .border({ width: 1, radius: 10,
      color: this.materialModeNum === value ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText(label)
    .onClick(() => {
      if (this.materialModeNum !== value) {
        this.materialModeNum = value;
        UiSurface.setMode(value === 1 ? MaterialMode.IMMERSIVE : MaterialMode.NORMAL);
        this.toast(value === 1 ? '界面材质：高级材质（沉浸光感）' : '界面材质：普通材质');
      }
    })
  }

  /** 高级材质级别档（跟随系统推荐 / 低 / 中 / 高；仅高级材质模式可选） */
  @Builder
  materialLevelChip(value: number, label: Resource) {
    Text(label)
      .fontSize(12)
      .fontColor(this.materialLevelNum === value ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(10)
      .backgroundColor(this.materialLevelNum === value ? $r('app.color.app_primary_bg') : Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText(label)
      .onClick(() => {
        this.materialLevelNum = value;
        UiSurface.setLevel(value as MaterialLevel);
      })
  }

  @Builder
  rowItem(title: ResourceStr, subtitle: ResourceStr, action: () => void) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        if (subtitle !== '') {
          Text(subtitle)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(20)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(14)
    .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(action)
  }

  build() {
    Stack() {
      // 壁纸衬底：router 独立页透出壁纸，embed 内嵌时由壳层统一铺（组件内渲染为空）
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
      this.header()
      this.userCard()
      Row() {
      Scroll(this.settingsScroller) {
        Column({ space: 10 }) {
          this.groupTitle('appearance')
          this.localeSection()
          this.sectionTitle($r('app.string.ui_section_theme'))
          this.themeSection()

          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text($r('app.string.ui_settings_reduce_motion'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.ui_settings_reduced_motion_info'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.reduceMotion }).attributeModifier(new ControlMaterialModifier(this.materialModeNum, this.materialLevelNum))
              .constraintSize({ minWidth: 44, minHeight: 44 })
              .hoverEffect(HoverEffect.Highlight)
              .accessibilityText($r('app.string.ui_settings_reduce_motion'))
              .onChange((enabled: boolean) => {
                this.applyReduceMotion(enabled);
              })
          }
          .width('100%')
          .padding(14)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .borderRadius(12)

          this.sectionTitle($r('app.string.ui_section_material'))
          Row({ space: 10 }) {
            this.materialModeChip(0, $r('app.string.ui_settings_normal_material'), $r('app.string.ui_material_frosted'))
            this.materialModeChip(1, $r('app.string.ui_settings_immersive_material'), $r('app.string.ui_material_system_glass'))
          }
          .width('100%')
          .padding(14)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_stroke') })

          if (this.materialModeNum === 1) {
            Column({ space: 8 }) {
              Text($r('app.string.ui_settings_material_level'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
              Row({ space: 6 }) {
                this.materialLevelChip(-1, $r('app.string.ui_language_system'))
                this.materialLevelChip(0, $r('app.string.ui_settings_page_option_reasoning_effort_low'))
                this.materialLevelChip(1, $r('app.string.ui_settings_page_option_reasoning_effort_medium'))
                this.materialLevelChip(2, $r('app.string.ui_settings_page_option_reasoning_effort_high'))
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
          }
          Text($r('app.string.ui_settings_material_scope')).fontSize(11).fontColor($r('app.color.text_secondary'))
            .width('100%').padding({ left: 14, right: 14 })
          this.backgroundMediaSection()
          Column({ space: 8 }) {
            this.wallpaperSelector()
            if (this.dailyWallpaperState === 'loading') {
              Text($r('app.string.ui_common_loading')).fontSize(12).fontColor($r('app.color.text_secondary'))
            } else if (this.dailyWallpaperState === 'unavailable') {
              Text(CommonOutcomeText.text(new CommonOutcome(CommonOutcomeId.NetworkUnavailable), AppLocaleService.current()))
                .fontSize(12).fontColor($r('app.color.text_secondary'))
            } else if (this.bgCopyright.length > 0 || this.bgSourceUrl.length > 0) {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text($r('app.string.ui_wallpaper_copyright')).fontSize(14).fontColor($r('app.color.text_primary'))
                  if (this.bgCopyright.length > 0) {
                    Text(this.bgCopyright).fontSize(12).fontColor($r('app.color.text_secondary'))
                  }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (this.bgSourceUrl.length > 0) { Text('›').fontSize(18).fontColor($r('app.color.text_secondary')) }
              }.width('100%').constraintSize({ minHeight: 44 }).padding({ left: 8, right: 8 })
              .focusable(this.bgSourceUrl.length > 0).accessibilityGroup(true)
              .hoverEffect(this.bgSourceUrl.length > 0 ? HoverEffect.Highlight : HoverEffect.None)
              .onClick((): void => { this.openWallpaperSource(); })
            }

            if (this.bgType === 'local') {
              Row() {
                Column({ space: 2 }) {
                  Text($r('app.string.ui_setting_background_image_custom_folder_header'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                  Text(this.bgFolderPath.length > 0 ? this.bgFolderPath : $r('app.string.ui_settings_no_wallpaper'))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text($r('app.string.ui_action_choose'))
                  .fontSize(12)
                  .enabled(!this.bgFolderPicking)
                  .fontColor($r('app.color.app_primary_text'))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(10)
                  .backgroundColor($r('app.color.app_primary_bg'))
                  .onClick(() => {
                    this.pickBgFolder();
                  })
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
            }

            Text($r('app.string.ui_settings_wallpaper_sources'))
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
          .padding(14)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_stroke') })

          this.groupTitle('storage')
          this.sectionTitle($r('app.string.ui_settings_game_data'))
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_settings_data_source'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.ui_settings_verified_data'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_stroke') })
          Row() {
              Text($r('app.string.ui_settings_data_source'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(this.dataVersion.length > 0
              ? `当前版本 ${this.dataVersion}`
              : '未更新（使用内置数据）')
              .fontSize(10)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '55%' })
            Button($r('app.string.ui_action_edit'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum))
              .enabled(!this.dataBusy && !this.dataChecking)
              .constraintSize({ minHeight: 44 })
              .fontSize(12)
              .onClick(() => {
                this.urlInput = this.dataUrl;
                this.showUrlEdit = true;
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 2, bottom: 4 })
          if (this.dataHasUpdate.length > 0) {
            Row() {
              Text(this.dataHasUpdate)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 2, bottom: 2 })
          }
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Button(this.dataChecking ? $r('app.string.ui_update_checking') : $r('app.string.ui_check_update'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum))
              .enabled(!this.dataBusy && !this.dataChecking)
              .fontSize(13)
              .constraintSize({ minHeight: 44 })
              .margin({ right: 10 })
              .onClick(() => {
                this.checkDataUpdate();
              })
            Button(this.dataBusy ? $r('app.string.ui_settings_processing') : $r('app.string.ui_settings_download_verify'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum, true))
              .enabled(!this.dataBusy && !this.dataChecking)
              .fontSize(13)
              .constraintSize({ minHeight: 44 })
              .onClick(() => {
                this.updateGameData();
              })
            if (this.dataCanCancel || this.dataCancelling) {
              Button(this.dataCancelling ? $r('app.string.ui_settings_cancelling') : $r('app.string.ui_settings_cancel_update'), { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum))
                .enabled(this.dataCanCancel)
                .fontSize(13)
                .constraintSize({ minHeight: 44 })
                .margin({ left: 8 })
                .onClick(() => { this.cancelGameData(); })
            }
            if (this.dataBusy) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.app_primary'))
                .margin({ left: 10 })
            } else if (this.dataTotal > 0) {
              Text(`${this.dataDone}/${this.dataTotal}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 10 })
            }
          }
          .width('100%')
          .padding(14)

          if (this.dataPhase.length > 0) {
            Text(this.dataPhase).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }
          if (this.dataPending.length > 0) {
            Text(this.dataPending).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          }
          Flex({ wrap: FlexWrap.Wrap }) {
            Button($r('app.string.ui_settings_previous_data'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum))
              .constraintSize({ minHeight: 44 }).margin({ right: 8, bottom: 8 })
              .enabled(this.dataCanRollback && !this.dataBusy && !this.dataChecking)
              .onClick(() => { this.changeSavedData(true).catch(() => { if (this.dataViewActive) { this.toast('无法完成确认，请重试'); } }); })
            Button($r('app.string.ui_settings_reset_builtin'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum))
              .constraintSize({ minHeight: 44 }).margin({ bottom: 8 })
              .enabled(!this.dataBusy && !this.dataChecking)
              .onClick(() => { this.changeSavedData(false).catch(() => { if (this.dataViewActive) { this.toast('无法完成确认，请重试'); } }); })
          }.width('100%')

          this.sectionTitle($r('app.string.ui_section_wish'))
          this.gachaDisplayOption(PreferencesStore.KEY_GACHA_EMPTY_OVERVIEW)
          this.gachaDisplayOption(PreferencesStore.KEY_GACHA_EMPTY_HISTORY)
          this.gachaDisplayOption(PreferencesStore.KEY_GACHA_UNOBTAINED)
          this.sectionTitle($r('app.string.ui_section_wish_data'))
          if (this.gachaRows.length === 0) {
            Text($r('app.string.ui_settings_no_wish_archives'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 6, bottom: 6 })
          } else {
            Column({ space: 8 }) {
              ForEach(this.gachaRows, (row: GachaArchiveRow) => {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(`UID ${row.uid}`)
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                    Text(`${row.count} 条记录`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text($r('app.string.ui_account_insights_delete'))
                    .fontSize(12)
                    .fontColor($r('app.color.danger'))
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(10)
                    .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
                    .border({ width: 1, color: $r('app.color.card_stroke') })
                    .onClick(() => {
                      this.confirmDeleteArchive(row);
                    })
                }
                .width('100%')
              }, (row: GachaArchiveRow) => `gr_${row.id}_${row.count}`)
            }
            .width('100%')
            .padding(14)
            .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.card_stroke') })
          }
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_settings_delete_wish'))
                .fontSize(15)
                .fontColor($r('app.color.danger'))
              Text($r('app.string.ui_settings_delete_wish_confirm'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text($r('app.string.ui_action_clear'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(10)
              .border({ width: 1, color: $r('app.color.danger') })
              .onClick(() => {
                this.confirmClearAllGacha();
              })
          }
          .width('100%')
          .padding(14)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_stroke') })

          this.sectionTitle($r('app.string.ui_settings_cache'))
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_action_clear_cache'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text(this.mediaCacheSize.length > 0 ? $r('app.string.ui_settings_cache_size', this.mediaCacheSize)
                : $r('app.string.ui_common_loading'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button(this.mediaCacheBusy ? $r('app.string.ui_common_loading') : $r('app.string.ui_action_clear_cache'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum))
              .fontSize(12)
              .constraintSize({ minHeight: 44 })
              .enabled(!this.mediaCacheBusy)
              .onClick(() => {
                this.clearMediaCache();
              })
          }
          .width('100%')
          .padding(14)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_stroke') })

          this.groupTitle('verification')
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_setting_geetest_custom_url_header'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              if (this.geetestInput.length > 0) {
                Text(this.geetestInput).fontSize(11).fontColor($r('app.color.text_secondary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.geetestInput.length > 0 ? $r('app.string.ui_action_edit') : $r('app.string.ui_settings_configure'))
              .fontSize(12)
              .fontColor($r('app.color.app_primary_text'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(10)
              .border({ width: 1, color: $r('app.color.app_primary') })
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.geetestInput = RiskVerifyService.getCustomCompositeUrl();
            this.showGeetestEdit = true;
          })

          this.groupTitle('ai')
          AiSettings()

          this.groupTitle('account')
          this.rowItem($r('app.string.ui_section_account'), '', () => {
            router.pushUrl({ url: 'pages/UserPage' });
          })
          this.rowItem($r('app.string.ui_ai_insights'), '', () => {
            router.pushUrl({ url: 'pages/AccountInsightsPage' });
          })
          if (this.isLoggedIn) {
            Row() {
              Text($r('app.string.ui_setting_hutao_passport_logout_action'))
                .fontSize(15)
                .fontColor($r('app.color.danger'))
              Blank()
            }
            .width('100%')
            .padding(14)
            .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .onClick(() => {
              UserService.getInstance().logout().then(() => {
                this.toast('已退出登录');
              });
            })
          }

          this.sectionTitle($r('app.string.ui_section_sign_in'))
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_card_sign_in_auto_sign_in'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.ui_settings_auto_sign_info'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.autoSignIn ? $r('app.string.ui_action_enable') : $r('app.string.ui_action_disable'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Toggle({ type: ToggleType.Switch, isOn: this.autoSignIn }).attributeModifier(new ControlMaterialModifier(this.materialModeNum, this.materialLevelNum))
              .margin({ left: 10 })
              .onChange((isOn: boolean) => {
                this.autoSignIn = isOn;
                PreferencesStore.setAutoSignInEnabled(isOn);
              })
          }
          .width('100%')
          .padding(14)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_stroke') })

          BackgroundTaskSettings({ active: this.backgroundControlsActive })

          this.groupTitle('home')
          this.sectionTitle($r('app.string.ui_section_home_cards'))
          Text($r('app.string.ui_setting_home_card_description'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ bottom: 4 })
          ForEach(this.homeCardRows, (row: HomeCardRow) => {
            Row({ space: 8 }) {
              Text(row.name)
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text('↑')
                .fontSize(18)
                .fontColor($r('app.color.text_secondary'))
                .width(30)
                .height(30)
                .textAlign(TextAlign.Center)
                .borderRadius(15)
                .backgroundColor($r('app.color.card_inner_tint'))
                .hoverEffect(HoverEffect.Highlight)
                .onClick(() => {
                  this.moveHomeCard(row, -1);
                })
              Text('↓')
                .fontSize(18)
                .fontColor($r('app.color.text_secondary'))
                .width(30)
                .height(30)
                .textAlign(TextAlign.Center)
                .borderRadius(15)
                .backgroundColor($r('app.color.card_inner_tint'))
                .hoverEffect(HoverEffect.Highlight)
                .onClick(() => {
                  this.moveHomeCard(row, 1);
                })
              Text(row.presented ? $r('app.string.ui_setting_empty_history_visible_on') : $r('app.string.ui_setting_empty_history_visible_off'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              Toggle({ type: ToggleType.Switch, isOn: row.presented }).attributeModifier(new ControlMaterialModifier(this.materialModeNum, this.materialLevelNum))
                .onChange((isOn: boolean) => {
                  this.toggleHomeCard(row, isOn);
                })
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.card_stroke') })
          }, (row: HomeCardRow) => `${row.key}_${row.presented}_${row.order}`)

          this.sectionTitle($r('app.string.ui_section_home_calendar'))
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_setting_home_announcement_act_is_enable_header'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.ui_setting_home_announcement_act_is_enable_description'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.homeActCalendarShown ? $r('app.string.ui_setting_empty_history_visible_on') : $r('app.string.ui_setting_empty_history_visible_off'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Toggle({ type: ToggleType.Switch, isOn: this.homeActCalendarShown }).attributeModifier(new ControlMaterialModifier(this.materialModeNum, this.materialLevelNum))
              .margin({ left: 10 })
              .onChange((isOn: boolean) => {
                this.homeActCalendarShown = isOn;
                PreferencesStore.setHomeActCalendar(isOn);
                AppStorage.setOrCreate<boolean>('homeActCalendarShown', isOn);
              })
          }
          .width('100%')
          .padding(14)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_stroke') })
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_setting_home_announcement_act_preview_header'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.ui_setting_home_announcement_act_preview_description'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.homeActPreview ? $r('app.string.ui_setting_empty_history_visible_on') : $r('app.string.ui_setting_empty_history_visible_off'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Toggle({ type: ToggleType.Switch, isOn: this.homeActPreview }).attributeModifier(new ControlMaterialModifier(this.materialModeNum, this.materialLevelNum))
              .margin({ left: 10 })
              .onChange((isOn: boolean) => {
                this.homeActPreview = isOn;
                PreferencesStore.setHomeActPreview(isOn);
                AppStorage.setOrCreate<boolean>('homeActPreview', isOn);
              })
          }
          .width('100%')
          .padding(14)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.card_stroke') })

          this.groupTitle('other')
          this.webShareSetting()
          this.sectionTitle($r('app.string.ui_section_backup'))
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_settings_export_backup'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.ui_settings_backup_credentials'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text($r('app.string.ui_action_export'))
              .fontSize(12)
              .fontColor($r('app.color.app_primary_text'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(10)
              .border({ width: 1, color: $r('app.color.app_primary') })
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.exportBackup();
          })
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_settings_restore_backup'))
                .fontSize(15)
                .fontColor($r('app.color.danger'))
              Text($r('app.string.ui_settings_restore_scope'))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text($r('app.string.ui_action_restore'))
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(10)
              .border({ width: 1, color: $r('app.color.danger') })
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.confirmRestoreBackup();
          })

          this.sectionTitle($r('app.string.ui_settings_feedback'))
          this.rowItem($r('app.string.ui_settings_help'), '', () => {
            router.pushUrl({ url: 'pages/HelpPage' });
          })
          this.rowItem('GitHub Issues', '', () => {
            SupportService.openIssues().catch(() => { this.toast('暂时无法打开反馈页面'); });
          })
          this.sectionTitle($r('app.string.ui_section_about'))
          this.rowItem(`胡桃工具箱（鸿蒙版）${this.appVersion.length > 0 ? ` v${this.appVersion}` : ''}`,
            '多账号与服务器 · 本地数据存储', () => {
            this.toast(`胡桃工具箱 Snap.Hutao.HarmonyOS v${this.appVersion}`);
          })
          Row() {
            Column({ space: 2 }) {
              Text($r('app.string.ui_check_update'))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text($r('app.string.ui_setting_key_shortcut_virtual_key_code_action'))
              .fontSize(12)
              .fontColor($r('app.color.app_primary_text'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(10)
              .border({ width: 1, color: $r('app.color.app_primary') })
          }
          .width('100%')
          .padding(14)
          .borderRadius(12)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            router.pushUrl({ url: 'pages/UpdatePage' });
          })
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Center)
      }
      .layoutWeight(1)
      .height('100%')
      .align(Alignment.Top)
      if (this.showGroupIndex) { this.groupIndex() }
      }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Top)

      if (this.showUrlEdit) {
        Column() {
          Column({ space: 12 }) {
            Text($r('app.string.ui_settings_data_source'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text($r('app.string.ui_settings_manifest_help'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            TextInput({ placeholder: 'https://raw.githubusercontent.com/aichi-chishan/snap-hutao-data/main/manifest-hutao.json', text: this.urlInput })
              .fontSize(12)
              .constraintSize({ minHeight: 44 })
              .width('100%')
              .onChange((v: string) => {
                this.urlInput = v;
              })
            Row({ space: 10 }) {
              Button($r('app.string.common_cancel'), { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum))
                .fontSize(13)
                .constraintSize({ minHeight: 44 })
                .layoutWeight(1)
                .onClick(() => {
                  this.showUrlEdit = false;
                })
              Button($r('app.string.ui_action_save'), { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum, true))
                .fontSize(13)
                .constraintSize({ minHeight: 44 })
                .layoutWeight(1)
                .onClick(() => {
                  this.applyDataUrl();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.overlay_scrim'))
      }
      if (this.showGeetestEdit) {
        Column() {
          Column({ space: 12 }) {
            Text($r('app.string.ui_setting_geetest_custom_url_header'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text($r('app.string.ui_settings_geetest_help'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            TextInput({ placeholder: 'https://your.api/geetest?gt={0}&challenge={1}', text: this.geetestInput })
              .fontSize(12)
              .height(40)
              .width('100%')
              .onChange((v: string) => {
                this.geetestInput = v;
              })
            Row({ space: 10 }) {
              Button($r('app.string.common_cancel'), { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum))
                .fontSize(13)
                .height(44)
                .layoutWeight(1)
                .onClick(() => {
                  this.showGeetestEdit = false;
                })
              Button($r('app.string.ui_action_save'), { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.materialModeNum, this.materialLevelNum, true))
                .fontSize(13)
                .height(44)
                .layoutWeight(1)
                .onClick(() => {
                  this.applyGeetestUrl();
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .attributeModifier(new CardSurfaceModifier(this.materialModeNum, this.materialLevelNum))
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.overlay_scrim'))
        .onClick(() => {
          this.showGeetestEdit = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((_old: Area, area: Area) => { this.showGroupIndex = Number(area.width) >= 840; })
    }
    .width('100%')
    .height('100%')
  }
}
