/**
 * GachaLogPage.ets（Index 祈愿 Tab 内嵌组件）
 * 祈愿记录：总览、历史、角色、武器、UP 倒计时和经验分布。
 *   总览：各池统计卡、保底进度和按池展示的抽取摘要。
 *   历史：当前池全部记录列表（橙/紫/蓝分组标题 + LazyForEach 列表）
 *   角色：全池 5 星/4 星角色头像网格
 *   武器：全池 5 星/4 星/3 星武器头像网格
 *   倒计时：UP 角色与武器的历史期次。
 * 池切换高亮、刷新按钮/进度展示、手动 URL 兜底；未登录引导。
 * 统计区使用等宽 Row，垫数栏按内容确定高度，统计格使用统一高度。
 * 抽取摘要：列表/方块双视图切换（对齐 Windows StatisticsCard LayoutSwitch + SwitchPresenter，
 *   每池独立记忆，持久化键复刻 Control.PanelSelector.StatisticsCard.SummaryList{池类型}）。
 * 快照模式：每次装载/刷新/切池后 syncPoolCards() 整体重建 @State poolCards 数组，
 * 池卡片所有展示字段取自同一 PoolCardData 对象，杜绝“部分统计为 0/切池不刷新”。
 */
import { router, LengthMetrics, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { GachaLogViewModel } from '../viewmodel/GachaLogViewModel';
import { GachaType } from '../model/GachaType';
import { GachaPoolRules } from '../model/GachaPoolRules';
import { gachaPoolLabel } from '../common/GachaPoolLabel';
import { GachaItem } from '../model/GachaItem';
import { GachaArchive } from '../model/GachaArchive';
import { UigfArchivePreview } from '../model/UigfImportPreparation';
import { PoolOutcome, RecentGachaItem, RefreshProgress } from '../model/RefreshProgress';
import { FiveStarDetail, PoolStatistics, WishSummaryItem, GachaItemCount as ItemCountEntry } from '../model/GachaStatistics';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { UigfService } from '../service/UigfService';
import { WikiMetaService } from '../service/WikiMetaService';
import { GachaHistoryService, HistoryWishView, HistoryUpItem } from '../service/GachaHistoryService';
import { CachedImageService } from '../service/CachedImageService';
import { Loading } from '../components/Loading';
import { MetaIcon } from '../components/MetaIcon';
import { NavIcon } from '../components/NavIcon';
import { PageBackdrop } from '../components/PageBackdrop';
import { PageToolbar } from '../components/PageToolbar';
import { Logger } from '../common/Logger';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { AppButtonModifier, CardSurfaceModifier, ControlMaterialModifier, SelectMaterialModifier, UiSurface } from '../common/UiSurface';
import { WishHistoryPage } from './WishHistoryPage';

const GACHA_TAG: string = 'GachaLogPage';
const UIGF_MAX_BYTES: number = 32 * 1024 * 1024;
const COMBINED_MODE_LABEL: string = '合并显示限定金总抽数';


/** 宽屏按 Windows HorizontalEqualPanel 展示，窄屏纵向排列。 */
const POOL_SINGLE_COLUMN_VP: number = 840;
const POOL_MIN_CARD_WIDTH: number = 302;
const POOL_CARD_GAP: number = 16;
const POOL_VIEW_INSET: number = 16;

class GachaItemIcon {
  category: string;
  name: string;

  constructor(category: string, name: string) {
    this.category = category;
    this.name = name;
  }
}

/** 池卡片快照（每次同步整体重建，非 @Observed 嵌套追踪） */
class PoolCardData {
  gachaType: number = 0;
  typeName: string = '';
  totalCount: number = 0;
  fiveCount: number = 0;
  fourCount: number = 0;
  threeCount: number = 0;
  otherCount: number = 0;
  sinceLastFive: number = 0;
  sinceLastFour: number = 0;
  sinceLastThree: number = 0;
  avgOrange: number = 0;
  avgUpOrange: number = 0;
  avgPurple: number = 0;
  maxOrange: number = 0;
  minOrange: number = 0;
  startDate: string = '';
  endDate: string = '';
  isCurrent: boolean = false;
  /** 池内是否已有 UP 标记（"歪=红块"等 UP 语义仅在确有 UP 数据时启用，规避常驻/武器池全红误判） */
  hasUpMark: boolean = false;
  summaryItems: WishSummaryItem[] = [];
  /** 内容变化时刷新 ForEach 内的摘要。 */
  key: string = '';
}

/** 期次横幅图缓存命中（url → 沙盒本地路径） */
class GachaBannerPath {
  url: string = '';
  path: string = '';
}

@Component
export struct GachaLogPage {
  @StorageProp('helpLocaleVersion') @Watch('onLocaleChanged') localeVersion: number = 0;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('gachaDisplayVersion') @Watch('onDisplaySettingsChanged') displaySettingsVersion: number = 0;
  @StorageLink('isLoggedIn') @Watch('onLoginStateChanged') isLoggedIn: boolean = false;
  @StorageLink('currentUid') @Watch('onUidChanged') currentUid: string = '';
  private pageActive: boolean = false;
  private pageEpoch: number = 0;
  private historyGeneration: number = 0;
  @State vm: GachaLogViewModel = new GachaLogViewModel();
  @State showUrlInput: boolean = false;
  @State showImportPreview: boolean = false;
  @State showExportOptions: boolean = false;
  @State urlInput: string = '';
  @State initialized: boolean = false;
  private poolSelectionRequest: number = 0;
  /** 池卡片快照（整体替换驱动渲染） */
  @State poolCards: PoolCardData[] = [];
  /** >=840vp 时总览采用单行横向滚动。 */
  @State isWide: boolean = false;
  /** 组件自身尺寸，用于计算横滚卡宽和临时面板的可用高度。 */
  @State areaWidth: number = 0;
  @State areaHeight: number = 0;
  /** 已折叠统计详情的池（对齐 Windows Expander 收起；不在表内 = 初始展开） */
  @State poolCollapsed: number[] = [];
  /** 列表视图开启的池（对齐 Windows Control.PanelSelector.StatisticsCard.SummaryList{池}；不在表内 = 方块视图） */
  @State poolViewList: number[] = [];
  @State showCombinedAvatarPulls: boolean = false;
  /** 期次汇总（对齐 Windows PivotHistory，懒构建：首次切到历史页签时构建） */
  @State historyWishes: HistoryWishView[] = [];
  /** 深色模式（横幅遮罩用；浅色不叠遮罩，对齐 Windows DarkOnlyOverlayMask） */
  @StorageProp('isDarkMode') isDark: boolean = false;
  /** 期次横幅图缓存命中表（url → 本地路径；整体 push 后需重赋值触发刷新） */
  @State bannerPaths: GachaBannerPath[] = [];
  private historyLoading: boolean = false;
  private historyLoadedFor: number = -1;
  /** 刷新进度快照 */
  @State progressText: string = '';
  @State progressCount: number = 0;
  @State recentItems: RecentGachaItem[] = [];
  @State showProgressDetail: boolean = false;
  /** 各池独立的统计/比例分段。 */
  @State ratioPools: number[] = [];
  /** Pivot 当前页 */
  @State pivotIndex: number = 0;
  /** 颂愿（千星奇域）模式：切换后页签/卡片/历史只显示颂愿池（对齐 Windows IsBeyondMode） */
  @State beyondMode: boolean = false;
  /** 角色/武器聚合快照 */
  @State charCounts: ItemCountEntry[] = [];
  @State weaponCounts: ItemCountEntry[] = [];
  /** 长列表数据源（LazyForEach） */
  historySource: SimpleDataSource<GachaItem> = new SimpleDataSource<GachaItem>([]);
  /** 刷新结果快照（完成后取 vm.progress 终态；UX07 结果摘要卡） */
  @State refreshResult: RefreshProgress | undefined = undefined;
  @State appliedLocaleVersion: number = -1;
  private metadataSequence: number = 0;

  aboutToAppear(): void {
    this.pageActive = true;
    this.loadPoolViewModes();
    this.vm.onProgressChanged = () => {
      if (this.pageActive) { this.syncProgress(); }
    };
    this.reloadData();
    this.loadDisplayMetadata();
  }

  aboutToDisappear(): void {
    this.invalidatePoolSelection();
    this.pageActive = false;
    this.metadataSequence++;
    this.pageEpoch++;
    this.historyGeneration++;
    this.showImportPreview = false;
    this.showExportOptions = false;
    this.vm.invalidateRequests();
    this.vm.onProgressChanged = () => {};
  }

  onDisplaySettingsChanged(): void {
    if (this.pageActive) { this.reloadData(); }
  }

  private onLocaleChanged(): void { this.loadDisplayMetadata(true); }

  private async loadDisplayMetadata(reloadStats: boolean = false): Promise<void> {
    if (!this.pageActive) { return; }
    const sequence: number = ++this.metadataSequence;
    const localeVersion: number = this.localeVersion;
    await WikiMetaService.ensureIconMaps();
    if (!this.pageActive || sequence !== this.metadataSequence) { return; }
    await WikiMetaService.ensureBeyondItemMaps();
    if (!this.pageActive || sequence !== this.metadataSequence) { return; }
    if (reloadStats) { await this.vm.reloadStats(); }
    if (!this.pageActive || sequence !== this.metadataSequence) { return; }
    this.appliedLocaleVersion = localeVersion;
    this.syncAll();
    if (reloadStats) {
      this.historyGeneration++;
      this.historyLoadedFor = -1;
      this.historyLoading = false;
      if (this.pivotIndex === 1) { this.loadHistoryWishes(false); }
    }
  }

  /** 登录只影响自动鉴权刷新，不关闭本地归档。 */
  onLoginStateChanged(): void {
    this.urlInput = '';
    this.showUrlInput = false;
    this.showImportPreview = false;
    this.showExportOptions = false;
    this.vm.clearImport();
    this.vm.exportUids = [];
    if (this.pageActive) { this.reloadData(); }
  }

  onUidChanged(): void {
    this.urlInput = '';
    this.showUrlInput = false;
    this.showImportPreview = false;
    this.showExportOptions = false;
    this.vm.clearImport();
    this.vm.exportUids = [];
    if (this.pageActive) { this.reloadData(); }
  }

  private resetLocalView(): void {
    this.invalidatePoolSelection();
    this.historyGeneration++;
    this.historyLoading = false;
    this.historyLoadedFor = -1;
    this.historyWishes = [];
    this.poolCards = [];
    this.charCounts = [];
    this.weaponCounts = [];
    this.historySource.notifyDataReload([]);
  }

  /** 无论是否登录都装载本地；退出登录不能把旧的存储 UID 当作刷新凭据。 */
  reloadData(): void {
    const epoch: number = ++this.pageEpoch;
    this.resetLocalView();
    this.vm.load(this.isLoggedIn ? this.currentUid : '').then(() => {
      if (!this.pageActive || epoch !== this.pageEpoch) { return; }
      this.initialized = true;
      this.syncAll();
      if (this.pivotIndex === 1) { this.loadHistoryWishes(); }
    }).catch((e: Error) => {
      if (this.pageActive && epoch === this.pageEpoch) { this.toast(`加载失败：${e.message}`); }
    });
  }

  private archiveOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const archive of this.vm.archives) {
      const option: SelectOption = { value: archive.uid };
      options.push(option);
    }
    return options;
  }

  private currentArchiveIndex(): number {
    return this.vm.archives.findIndex((archive: GachaArchive): boolean => archive.id === this.vm.currentArchiveId);
  }

  private async chooseLocalArchive(id: number): Promise<void> {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    const epoch: number = ++this.pageEpoch;
    this.showImportPreview = false;
    this.showExportOptions = false;
    this.resetLocalView();
    try {
      await this.vm.selectArchive(id);
      if (!this.pageActive || epoch !== this.pageEpoch) { return; }
      this.syncAll();
      if (this.pivotIndex === 1) { this.loadHistoryWishes(); }
    } catch (e) {
      if (this.pageActive && epoch === this.pageEpoch) {
        this.syncAll();
        this.toast((e as Error).message);
      }
    }
  }

  private async removeLocalArchive(): Promise<void> {
    const archiveId: number = this.vm.currentArchiveId;
    let epoch: number = this.pageEpoch;
    if (!this.pageActive || archiveId <= 0 || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    try {
      const choice: ShowDialogSuccessResponse | undefined = await this.getUIContext().getPromptAction().showDialog({
        systemMaterial: UiSurface.dialogMaterial(),
        title: `删除归档 ${this.vm.currentUid}`,
        message: '确定删除此归档及其中的全部本地祈愿记录？',
        buttons: [
          { text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.ui_account_insights_delete'), color: $r('app.color.danger') },
        ],
      }).catch((): undefined => undefined);
      if (choice?.index !== 1 || !this.pageActive || epoch !== this.pageEpoch || archiveId !== this.vm.currentArchiveId) { return; }
      epoch = ++this.pageEpoch;
      this.vm.clearImport();
      await this.vm.deleteCurrentArchive();
      if (!this.pageActive || epoch !== this.pageEpoch) { return; }
      this.showExportOptions = false;
      this.showImportPreview = false;
      this.refreshResult = undefined;
      this.resetLocalView();
      this.syncAll();
      if (this.pivotIndex === 1) { this.loadHistoryWishes(); }
    } catch (e) {
      if (this.pageActive && epoch === this.pageEpoch) { this.toast(`删除失败：${(e as Error).message}`); }
    }
  }

  private archiveActions(): MenuElement[] {
    const idle: boolean = !this.vm.isRefreshing && !this.vm.isTransferring;
    const actions: MenuElement[] = [
      { value: '导入 UIGF', enabled: idle, action: () => { this.uigfImport(); } },
      { value: '导出 UIGF', enabled: idle && this.vm.archives.length > 0, action: () => { this.prepareUigfExport(); } },
      { value: '输入祈愿链接', enabled: idle, action: () => { this.showUrlInput = !this.showUrlInput; } },
      { value: '粘贴祈愿链接', enabled: idle, action: () => { this.importFromClipboard(); } },
      { value: this.vm.fullRefresh ? $r('app.string.ui_gacha_full_refresh_selected') : $r('app.string.ui_gacha_full_refresh'),
        enabled: idle, action: () => { this.vm.fullRefresh = !this.vm.fullRefresh; } },
      { value: $r('app.string.ui_ai_insights'), action: () => { router.pushUrl({ url: 'pages/AccountInsightsPage' }); } },
      { value: $r('app.string.ui_settings_delete_wish_archive'), enabled: idle && this.vm.currentArchiveId > 0,
        action: () => { this.removeLocalArchive(); } },
    ];
    if (!this.isLoggedIn) {
      actions.push({ value: '登录以在线刷新', action: () => { router.pushUrl({ url: 'pages/LoginPage' }); } });
    }
    if (!this.beyondMode) {
      actions.push({ value: $r('app.string.ui_gacha_pivot_statistics'), action: () => { this.selectPivot(5); } });
    }
    return actions;
  }

  private async refreshAccount(): Promise<void> {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    if (!this.isLoggedIn || this.vm.gameAccountUid.length === 0) {
      this.toast('请先登录并在「账号与数据」选择默认 UID');
      return;
    }
    const epoch: number = this.pageEpoch;
    await this.vm.refresh(this.beyondMode ? GachaType.BEYOND_ORDER : GachaType.QUERY_ORDER);
    if (!this.pageActive || epoch !== this.pageEpoch) { return; }
    this.refreshResult = this.vm.progress;
    this.resetLocalView();
    this.syncAll();
    this.toast(this.vm.message);
    if (this.pivotIndex === 1) { this.loadHistoryWishes(); }
  }

  /** 失败池单项重试（UX07：部分成功时可只重试未完成的池） */
  private async retryPool(gachaType: number): Promise<void> {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    if (!this.isLoggedIn || this.vm.gameAccountUid.length === 0) {
      this.toast('请先登录并在「账号与数据」选择默认 UID');
      return;
    }
    const epoch: number = this.pageEpoch;
    await this.vm.refresh([gachaType]);
    if (!this.pageActive || epoch !== this.pageEpoch) { return; }
    this.refreshResult = this.vm.progress;
    this.resetLocalView();
    this.syncAll();
    this.toast(this.vm.message);
    if (this.pivotIndex === 1) { this.loadHistoryWishes(); }
  }

  /** 刷新结果摘要卡可见性：非刷新中且已完成一次含池级明细的刷新（UX07 闭环呈现） */
  showRefreshResult(): boolean {
    return !this.vm.isRefreshing && !this.vm.isTransferring
      && this.refreshResult !== undefined && this.refreshResult.hasPoolResults();
  }

  dismissRefreshResult(): void {
    this.refreshResult = undefined;
  }

  /** 面板内取非空快照（未完成时为空对象，编译器无法跨渲染条件窄化） */
  private resultOrEmpty(): RefreshProgress {
    return this.refreshResult !== undefined ? this.refreshResult : new RefreshProgress();
  }

  private async submitUrlImport(): Promise<void> {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    const epoch: number = this.pageEpoch;
    const ok: boolean = await this.vm.importByUrl(this.urlInput, this.beyondMode ? GachaType.BEYOND_ORDER : GachaType.QUERY_ORDER);
    if (!this.pageActive || epoch !== this.pageEpoch) { return; }
    this.resetLocalView();
    this.syncAll();
    this.toast(ok ? `导入完成：${this.vm.message}` : `导入失败：${this.vm.message}`);
    if (ok) { this.showUrlInput = false; this.urlInput = ''; }
    if (this.pivotIndex === 1) { this.loadHistoryWishes(); }
  }

  /** 同步历史列表数据源 */
  syncHistorySource(): void {
    this.historySource.notifyDataReload(this.vm.items);
  }

  /** 同步进度快照到页面状态 */
  syncProgress(): void {
    this.progressText = this.vm.progress.reportText;
    this.progressCount = this.vm.progress.fetchedCount;
    this.recentItems = this.vm.progress.recentItems.slice(-40).reverse();
  }

  /** 同步全部统计/历史快照到页面状态（@State 直接驱动） */
  syncAll(): void {
    this.syncPoolCards();
    this.syncCounts();
    this.syncProgress();
    this.syncHistorySource();
  }

  /** 全归档统计已由 ViewModel 聚合，切换卡池不会重复计数或丢失三星。 */
  syncCounts(): void {
    this.charCounts = this.vm.stats.avatars;
    this.weaponCounts = this.vm.stats.weapons;
  }

  /** 按 vm.stats.pools 整体重建池卡片快照：每个字段同源，杜绝匹配不到/字段错配 */
  syncPoolCards(): void {
    const cards: PoolCardData[] = [];
    const pools: PoolStatistics[] = this.vm.stats.pools;
    const showEmpty: boolean = PreferencesStore.getBool(PreferencesStore.KEY_GACHA_EMPTY_OVERVIEW, false);
    // 按 Windows PivotOverview 中统计卡的布局顺序显示。
    const order: number[] = this.beyondMode ? GachaType.BEYOND_ORDER
      : [GachaType.AVATAR_EVENT, GachaType.WEAPON_EVENT, GachaType.PERMANENT, GachaType.CHRONICLE, GachaType.NOVICE];
    for (const type of order) {
      const pool: PoolStatistics | undefined = pools.find((entry: PoolStatistics): boolean => entry.gachaType === type);
      if (pool === undefined || (pool.totalCount <= 0 && !showEmpty)) {
        continue;
      }
      const card: PoolCardData = new PoolCardData();
      card.gachaType = pool.gachaType;
      card.typeName = pool.typeName;
      card.totalCount = pool.totalCount;
      card.fiveCount = pool.fiveStarCount;
      card.fourCount = pool.fourStarCount;
      card.threeCount = pool.threeStarCount;
      card.otherCount = pool.otherStarCount;
      card.sinceLastFive = pool.sinceLastFive;
      card.sinceLastFour = pool.sinceLastFour;
      card.sinceLastThree = pool.sinceLastThree;
      card.avgOrange = pool.averageOrangePull;
      card.avgUpOrange = pool.averageUpOrangePull;
      card.avgPurple = pool.averagePurplePull;
      card.maxOrange = pool.maxOrangePull;
      card.minOrange = pool.minOrangePull;
      card.startDate = pool.startDate;
      card.endDate = pool.endDate;
      card.isCurrent = pool.gachaType === this.vm.currentPoolType;
      card.hasUpMark = pool.fiveDetails.some((pull: WishSummaryItem): boolean => pull.isUp);
      card.summaryItems = pool.summaryItems;
      card.key = `${GachaLogPage.cardKey(card)}_${this.appliedLocaleVersion}`;
      cards.push(card);
      Logger.info(GACHA_TAG, `card ${pool.typeName}: total=${card.totalCount} ` +
        `5star=${card.fiveCount} 4star=${card.fourCount} since=${card.sinceLastFive} ` +
        `avg=${card.avgOrange} min=${card.minOrange} max=${card.maxOrange} current=${card.isCurrent}`);
    }
    this.poolCards = cards;
    Logger.info(GACHA_TAG, `syncPoolCards current=${this.vm.currentPoolType} cards=${cards.length}`);
  }

  /** 卡片键包含统计和明细，支持同总抽数下的数据更新。 */
  private static cardKey(card: PoolCardData): string {
    const details: string[] = card.summaryItems.map((pull: WishSummaryItem): string =>
      `${pull.gachaId}:${pull.itemId}:${pull.rankType}:${pull.time}:${pull.name}:${pull.itemType}:` +
      `${pull.lastPull}:${pull.isUp}:${pull.upKnown}:${pull.isGuarantee}:${pull instanceof FiveStarDetail ? pull.totalCyclePull : 0}`);
    return `${card.gachaType}_${card.typeName}_${card.totalCount}_${card.fiveCount}_${card.fourCount}_` +
      `${card.threeCount}_${card.otherCount}_${card.sinceLastFive}_${card.sinceLastFour}_${card.sinceLastThree}_` +
      `${card.startDate}_${card.endDate}_${card.avgOrange}_${card.avgUpOrange}_${card.avgPurple}_${card.maxOrange}_` +
      `${card.minOrange}_${card.hasUpMark}_${card.isCurrent}_${details.join('|')}`;
  }

  private widePoolCardWidth(): number {
    const count: number = Math.max(1, this.poolCards.length);
    const viewport: number = this.areaWidth - 2 * POOL_VIEW_INSET;
    return Math.max(POOL_MIN_CARD_WIDTH, (viewport - (count - 1) * POOL_CARD_GAP) / count);
  }

  /** 该池统计详情是否已折叠（对齐 Windows Expander：默认展开，仅折叠统计详情） */
  private isPoolCollapsed(card: PoolCardData): boolean {
    return this.poolCollapsed.indexOf(card.gachaType) >= 0;
  }

  /** 卡头 Chevron 点击：每卡独立切换（初始展开） */
  private togglePoolDetail(card: PoolCardData): void {
    const next: number[] = [];
    let removed: boolean = false;
    for (let i = 0; i < this.poolCollapsed.length; i++) {
      if (this.poolCollapsed[i] === card.gachaType) {
        removed = true;
      } else {
        next.push(this.poolCollapsed[i]);
      }
    }
    if (!removed) {
      next.push(card.gachaType);
    }
    this.poolCollapsed = next;
  }

  /** 池记录视图持久化键（复刻 Windows：Control.PanelSelector.StatisticsCard.SummaryList{池类型}） */
  private static listViewKey(gachaType: number): string {
    return `Control.PanelSelector.StatisticsCard.SummaryList${gachaType}`;
  }

  /** 启动时装载各池视图记忆（缺省 = 方块视图，对齐 Windows 默认 OrangeGrid） */
  private loadPoolViewModes(): void {
    const list: number[] = [];
    if (PreferencesStore.isReady()) {
      const types: number[] = GachaType.QUERY_ORDER.concat(GachaType.BEYOND_ORDER);
      for (const t of types) {
        if (PreferencesStore.getBool(GachaLogPage.listViewKey(t), false)) {
          list.push(t);
        }
      }
    }
    this.poolViewList = list;
  }

  /** 该池是否列表视图 */
  private isPoolListView(card: PoolCardData): boolean {
    return this.poolViewList.indexOf(card.gachaType) >= 0;
  }

  /** 切换池记录视图并保存布局。 */
  private setPoolListView(gachaType: number, isList: boolean): void {
    const next: number[] = [];
    for (const t of this.poolViewList) {
      if (t !== gachaType) {
        next.push(t);
      }
    }
    if (isList) {
      next.push(gachaType);
    }
    this.poolViewList = next;
    if (PreferencesStore.isReady()) {
      PreferencesStore.setBool(GachaLogPage.listViewKey(gachaType), isList);
    }
  }

  /** 是否带 UP 语义的池（结构判定：UP 平均列显隐用；歪块红底另受 hasUpMark 数据门控） */
  private static poolHasUp(gachaType: number): boolean {
    return gachaType === GachaType.AVATAR_EVENT || gachaType === GachaType.WEAPON_EVENT ||
      gachaType === GachaType.UGC_AVATAR_EVENT;
  }

  /** 取颜色数值的 R/G/B 分量（shift: 16=R 8=G 0=B） */
  private static colorChan(c: number, shift: number): number {
    return (c >> shift) & 0xFF;
  }

  /**
   * 列表行水位条颜色：距金抽数按该池阈值 在 success→danger 资源色间线性插值
   * （等价 Windows #48FF7A→#FF4949 渐变，端点取现有资源色，深浅色各自生效；20% 透明度由 .opacity 统一叠加）
   */
  private listBarColor(lastPull: number, threshold: number): ResourceColor {
    const t: number = threshold > 0 ? Math.max(0, Math.min(1, lastPull / threshold)) : 0;
    try {
      // getColorSync 数字 id 重载（Resource 重载已弃用）
      const from: number = getContext(this).resourceManager.getColorSync($r('app.color.success').id);
      const to: number = getContext(this).resourceManager.getColorSync($r('app.color.danger').id);
      const r: number = Math.round(GachaLogPage.colorChan(from, 16)
        + (GachaLogPage.colorChan(to, 16) - GachaLogPage.colorChan(from, 16)) * t);
      const g: number = Math.round(GachaLogPage.colorChan(from, 8)
        + (GachaLogPage.colorChan(to, 8) - GachaLogPage.colorChan(from, 8)) * t);
      const b: number = Math.round(GachaLogPage.colorChan(from, 0)
        + (GachaLogPage.colorChan(to, 0) - GachaLogPage.colorChan(from, 0)) * t);
      return 255 << 24 | r << 16 | g << 8 | b;
    } catch (e) {
      // 资源解析失败兜底：走品质金色
      return $r('app.color.five_star');
    }
  }

  /** 内容宽度决定祈愿总览断点。 */
  onPoolAreaChange(widthVp: number, heightVp: number): void {
    this.areaWidth = widthVp;
    this.areaHeight = heightVp;
    this.isWide = widthVp >= POOL_SINGLE_COLUMN_VP;
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 1800 });
  }

  iconOfEntry(entry: ItemCountEntry): string {
    return entry.icon || this.itemIcon(entry.itemId, entry.name, entry.itemType).name;
  }

  private static itemType(itemType: string): string {
    switch (itemType.trim().toLowerCase()) {
      case 'weapon':
      case '武器': return '武器';
      case 'avatar':
      case 'character':
      case '角色': return '角色';
      default: return itemType;
    }
  }

  private displayItemName(id: number, name: string, itemType: string): string {
    return WikiMetaService.displayNameOfItem(id, GachaLogPage.cleanName(name), GachaLogPage.itemType(itemType));
  }

  private poolLabelText(type: number): string {
    const label: ResourceStr = gachaPoolLabel(type);
    if (typeof label === 'string') { return label; }
    return this.getUIContext().getHostContext()?.resourceManager.getStringSync(label.id) ?? GachaType.nameOf(type);
  }

  private itemIcon(id: number, name: string, itemType: string): GachaItemIcon {
    const normalized: string = GachaLogPage.itemType(itemType);
    const clean: string = GachaLogPage.cleanName(name);
    if (id > 0) {
      const beyond: string = WikiMetaService.iconOfBeyondId(id);
      if (beyond.length > 0) { return new GachaItemIcon('BeyondItemIcon', beyond); }
      const avatar: string = WikiMetaService.iconOfAvatar(id);
      if (avatar.length > 0) { return new GachaItemIcon('AvatarIcon', avatar); }
      const weapon: string = WikiMetaService.iconOfWeapon(id);
      if (weapon.length > 0) { return new GachaItemIcon('EquipIcon', weapon); }
    }
    const weapon: string = WikiMetaService.iconOfWeaponName(clean);
    const avatar: string = WikiMetaService.iconOfAvatarName(clean);
    if (weapon.length > 0 && (normalized === '武器' || avatar.length === 0)) {
      return new GachaItemIcon('EquipIcon', weapon);
    }
    if (avatar.length > 0) { return new GachaItemIcon('AvatarIcon', avatar); }
    const beyond: string = WikiMetaService.iconOfBeyondName(clean);
    if (beyond.length > 0) { return new GachaItemIcon('BeyondItemIcon', beyond); }
    return new GachaItemIcon(normalized === '武器' ? 'EquipIcon' : 'AvatarIcon', '');
  }

  private displayItemType(item: GachaItem): string {
    const type: string = GachaLogPage.itemType(item.itemType);
    if (type.length > 0) { return type; }
    const icon: GachaItemIcon = this.itemIcon(item.itemId, item.name, item.itemType);
    if (icon.name.length === 0) { return '—'; }
    switch (icon.category) {
      case 'EquipIcon': return '武器';
      case 'BeyondItemIcon': return '颂愿物品';
      default: return '角色';
    }
  }

  private static pullColor(rank: number): Resource {
    if (rank === 5) { return $r('app.color.five_star'); }
    return rank === 4 ? $r('app.color.four_star') : $r('app.color.three_star');
  }

  private static averageText(value: number): string {
    return value.toFixed(2);
  }

  private static countText(count: number, total: number): string {
    const percent: number = total > 0 ? count * 100 / total : 0;
    return `${count} [${percent.toFixed(2)}%]`;
  }

  private showsCombined(gachaType: number): boolean {
    return this.showCombinedAvatarPulls && gachaType === GachaType.AVATAR_EVENT;
  }

  private visibleSummaryItems(card: PoolCardData): WishSummaryItem[] {
    if (!this.showsCombined(card.gachaType)) { return card.summaryItems; }
    return card.summaryItems.filter((pull: WishSummaryItem, index: number): boolean => pull.isUp || index === 0);
  }

  private summaryPullCount(gachaType: number, pull: WishSummaryItem): number {
    return this.showsCombined(gachaType) && pull.isUp && pull instanceof FiveStarDetail
      ? pull.totalCyclePull : pull.lastPull;
  }

  private summaryThreshold(gachaType: number, pull: WishSummaryItem): number {
    const threshold: number = GachaPoolRules.fiveStarThreshold(gachaType);
    return this.showsCombined(gachaType) && pull.isUp ? threshold * 2 : threshold;
  }

  private summaryItemKey(gachaType: number, pull: WishSummaryItem): string {
    return `${pull.gachaId}_${pull.rankType}_${this.appliedLocaleVersion}_${this.showsCombined(gachaType)}`;
  }

  private pullInitial(pull: WishSummaryItem): string {
    const name: string = this.displayItemName(pull.itemId, pull.name, pull.itemType);
    return name.length > 0 ? name.substring(0, 1) : '★';
  }

  private iconOfPull(pull: WishSummaryItem): string {
    return this.itemIcon(pull.itemId, pull.name, pull.itemType).name;
  }

  private pullCategory(pull: WishSummaryItem): string {
    return this.itemIcon(pull.itemId, pull.name, pull.itemType).category;
  }

  /** 清洗抽卡记录名：剔除星级符号/空格（★/◆/空格），对齐元数据名字做 icon 映射 */
  private static cleanName(raw: string): string {
    if (raw.length === 0) {
      return raw;
    }
    let s: string = raw;
    if (s.startsWith('★ ') || s.startsWith('◆ ') || s.startsWith('♢ ')) {
      s = s.substring(2);
    }
    s = s.trim();
    return s;
  }

  @Builder
  poolTabs() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.beyondMode ? GachaType.BEYOND_ORDER : GachaType.QUERY_ORDER, (type: number) => {
          Text(gachaPoolLabel(type))
            .fontSize(12)
            .fontColor(this.vm.currentPoolType === type ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.vm.currentPoolType === type ? $r('app.color.nav_selected') : $r('app.color.card_inner_tint'))
            .border({ width: 1, color: $r('app.color.card_stroke') })
            .constraintSize({ minWidth: 56, minHeight: 44 })
            .enabled(!this.vm.isRefreshing && !this.vm.isTransferring)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.selectPool(type);
            })
        }, (type: number) => `${type}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height(44)
  }

  /** 颂愿（千星奇域）模式切换。 */
  @Builder
  beyondToggleChip() {
    Button() {
      Row({ space: 4 }) {
        Text('✦').fontSize(15).fontColor(this.beyondMode ? $r('app.color.app_primary_text') : $r('app.color.text_secondary'))
        if (this.isWide) {
          Text($r('app.string.ui_gacha_log_switch_to_beyond_gacha_mode_header'))
            .fontSize(13).fontColor($r('app.color.text_primary')).maxLines(1)
        }
      }
    }
      .type(ButtonType.Normal).buttonStyle(ButtonStyleMode.NORMAL)
      .constraintSize({ minHeight: 44, minWidth: 44 })
      .accessibilityText($r('app.string.ui_gacha_log_switch_to_beyond_gacha_mode_header'))
      .accessibilityDescription(this.beyondMode ? $r('app.string.ui_option_selected') : $r('app.string.ui_option_unselected'))
      .enabled(!this.vm.isRefreshing && !this.vm.isTransferring)
      .padding({ left: this.isWide ? 8 : 0, right: this.isWide ? 8 : 0 })
      .borderRadius(6)
      .backgroundColor(this.beyondMode ? $r('app.color.nav_selected') : Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.toggleBeyondMode();
      })
  }

  /** 切换颂愿模式：换默认选中池并重建快照 */
  toggleBeyondMode(): void {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    this.beyondMode = !this.beyondMode;
    // 颂愿模式仅保留总览页签（PivotBeyondModeBehavior 语义）：离开颂愿时也先回到总览
    if (this.pivotIndex !== 0) { this.pivotIndex = 0; }
    const target: number = this.beyondMode ? GachaType.UGC_STANDARD : GachaType.AVATAR_EVENT;
    this.selectPool(target);
  }

  /**
   * 保底进度条单元（对齐 Windows CardProgressBar：底层通栏 Progress + 上层文字块，MinHeight 32）。
   * 对齐关键：数值文本 layoutWeight(1) + 居中，占满剩余宽度——位数不影响布局；
   * maxFontSize/minFontSize 等价 Viewbox DownOnly（数字只缩不放）。
   * 两个栏位在 Row 内平分宽度，垫数栏按内容确定高度。
   */
  @Builder
  guaranteeBar(label: Resource, cur: number, guarantee: number, desc: string, color: Resource) {
    if (guarantee > 0) {
      Stack({ alignContent: Alignment.Center }) {
        Progress({ value: Math.min(cur, guarantee), total: guarantee, type: ProgressType.Linear })
          .width('100%').height(32).color(color).opacity(0.2).style({ strokeWidth: 32 })
        Row({ space: 4 }) {
          Text(label).fontSize(11).fontColor(color).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(`${cur}`).fontSize(12).fontWeight(FontWeight.Medium).fontColor(color).maxLines(1)
        }.width('100%').padding({ left: 7, right: 7 }).alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1).height(32).borderRadius(4).clip(true)
      .border({ width: 1, color: $r('app.color.card_stroke') })
      .accessibilityText(label).accessibilityDescription(`${cur}/${guarantee} · ${desc}`)
    }
  }

  /**
   * 统计格（对齐 Windows BorderShimmer 盒状格子：说明 + 大数值，固定高度保证跨卡对齐）。
   * 等分统计行的宽度，数值随可用宽度缩小。
   */
  @Builder
  statCellBox(caption: ResourceStr, value: string, valueColor: Resource, captionColor: Resource, showUnit: boolean) {
    Column({ space: 2 }) {
      Text(caption)
        .fontSize(11)
        .fontColor(captionColor)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Row({ space: 3 }) {
        Text(value).fontSize(15).fontWeight(FontWeight.Medium).fontColor(valueColor)
          .maxFontSize(15).minFontSize(10).maxLines(1)
        if (showUnit) {
          Text($r('app.string.ui_account_insights_unit_wish')).fontSize(10)
            .fontColor($r('app.color.text_secondary')).maxLines(1)
        }
      }.width('100%')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .height(64)
    .padding({ left: 7, right: 7 })
    .borderRadius(4)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 上下叠放半高统计格（对齐 Windows Case 0 右列：最大/最小两行各占一半）；数字只缩不放 */
  @Builder
  statMiniBox(text: string, color: Resource) {
    Text(text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(color)
      .maxFontSize(13)
      .minFontSize(9)
      .maxLines(1)
      .textAlign(TextAlign.Center)
      .width('100%')
      .layoutWeight(1)
      .borderRadius(4)
      .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 分段器单元（对齐 Windows StatisticsSegmented：全宽二等分） */
  @Builder
  statSegmentChip(gachaType: number, label: Resource, ratio: boolean) {
    Stack({ alignContent: Alignment.Bottom }) {
      Text(label).height(44).width('100%').textAlign(TextAlign.Center)
        .fontSize(13).fontWeight(this.showsRatio(gachaType) === ratio ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.showsRatio(gachaType) === ratio ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      if (this.showsRatio(gachaType) === ratio) {
        Row().width(18).height(2).borderRadius(1).backgroundColor($r('app.color.app_primary')).margin({ bottom: 2 })
      }
    }.layoutWeight(1).height(44).borderRadius(4)
      .backgroundColor(this.showsRatio(gachaType) === ratio ? $r('app.color.card_inner_tint') : Color.Transparent)
      .accessibilityText(label)
      .accessibilityDescription(this.showsRatio(gachaType) === ratio ? $r('app.string.ui_option_selected') : $r('app.string.ui_option_unselected'))
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.setRatio(gachaType, ratio);
      })
  }

  private showsRatio(gachaType: number): boolean { return this.ratioPools.includes(gachaType); }

  private setRatio(gachaType: number, ratio: boolean): void {
    if (this.showsRatio(gachaType) === ratio) { return; }
    this.ratioPools = ratio ? [...this.ratioPools, gachaType]
      : this.ratioPools.filter((type: number): boolean => type !== gachaType);
  }

  /**
   * 抽取摘要（对齐 Windows StatisticsCard SwitchPresenter）：列表/方块双视图，
   * 视图由 poolViewList 每池记忆（见 setPoolListView）。Windows 侧仅 ToolTip（悬停显示时间），
   * 无点击弹窗，故条目不加 onClick。
   */
  @Builder
  summaryArea(card: PoolCardData) {
    if (card.summaryItems.length === 0) {
      Text(GachaType.isBeyond(card.gachaType) ? '暂无抽取摘要' : '暂无五星出金记录')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    } else if (this.isPoolListView(card)) {
      this.summaryListView(card)
    } else {
      this.summaryGridView(card)
    }
  }

  /**
   * 列表视图（对齐 Windows SummaryListTemplate）：全宽行三层叠放——
   * ① 底层通栏 Progress（使用对应卡池阈值，Value=距金抽数，前景按抽数绿→红渐变、20% 透明度）；
   * ② 左 40×40 圆角图标 + 品质色名称；③ 右「保底」角标 →「UP」角标 → 计数（minWidth 24 居中防跳动）。
   */
  @Builder
  summaryListView(card: PoolCardData) {
    Column({ space: 4 }) {
      ForEach(this.visibleSummaryItems(card), (pull: WishSummaryItem) => {
        Stack({ alignContent: Alignment.Start }) {
          if (this.summaryThreshold(card.gachaType, pull) > 0) {
            Progress({
              value: Math.min(this.summaryPullCount(card.gachaType, pull), this.summaryThreshold(card.gachaType, pull)),
              total: this.summaryThreshold(card.gachaType, pull),
              type: ProgressType.Linear,
            })
              .width('100%')
              .height(40)
              .color(this.listBarColor(this.summaryPullCount(card.gachaType, pull), this.summaryThreshold(card.gachaType, pull)))
              .opacity(0.2)
              .borderRadius(4)
              .style({ strokeWidth: 40 })
          }
          Row({ space: 6 }) {
            this.pullIcon(pull)
            Text(this.displayItemName(pull.itemId, pull.name, pull.itemType))
              .fontSize(13)
              .fontColor(GachaLogPage.pullColor(pull.rankType))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (pull.isGuarantee) {
              this.pullBadge('保底', $r('app.color.app_primary_text'))
            }
            if (pull.isUp) {
              this.pullBadge('UP', $r('app.color.five_star'))
            }
            Text(`${this.summaryPullCount(card.gachaType, pull)}`)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .constraintSize({ minWidth: 24 })
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .height(40)
          .padding({ left: 4, right: 8 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(40)
        .borderRadius(4)
        .clip(true)
        .backgroundColor($r('app.color.card_inner_tint'))
        .border({ width: 1, color: $r('app.color.card_stroke') })
      }, (pull: WishSummaryItem) => this.summaryItemKey(card.gachaType, pull))
    }
    .width('100%')
  }

  /**
   * 方块视图（对齐 Windows OrangeGridTemplate）：小方块卡（内衬底 + 1px 描边 + 圆角 4），
   * 上部 40×40 图标按品质着色，底部显示同星级间隔；已确认非 UP 的条目使用红底。
   * 网格随卡宽自动换行平铺，块间距右 2 下 4。
   */
  @Builder
  summaryGridView(card: PoolCardData) {
    Flex({
      wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.Start,
      space: { main: LengthMetrics.vp(3), cross: LengthMetrics.vp(4) }
    }) {
      ForEach(this.visibleSummaryItems(card), (pull: WishSummaryItem) => {
        Column({ space: 1 }) {
          this.pullIcon(pull)
          Text(`${this.summaryPullCount(card.gachaType, pull)}`)
            .fontSize(12)
            .fontColor(this.summaryThreshold(card.gachaType, pull) > 0
              ? this.listBarColor(this.summaryPullCount(card.gachaType, pull), this.summaryThreshold(card.gachaType, pull))
              : GachaLogPage.pullColor(pull.rankType))
            .maxLines(1)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width(44)
        .padding({ top: 1, bottom: 3 })
        .borderRadius(4)
        .backgroundColor(pull.upKnown && !pull.isUp && card.hasUpMark ? $r('app.color.danger_bg') : $r('app.color.card_inner_tint'))
        .border({ width: 1, color: $r('app.color.card_stroke') })
        .alignItems(HorizontalAlign.Center)
      }, (pull: WishSummaryItem) => this.summaryItemKey(card.gachaType, pull))
    }
    .width('100%')
  }

  /** 40×40 物品图标，底色对应品质。 */
  @Builder
  pullIcon(pull: WishSummaryItem) {
    Stack() {
      Column().width(40).height(40).backgroundColor(GachaLogPage.pullColor(pull.rankType)).opacity(0.18)
      if (this.iconOfPull(pull).length > 0) {
        MetaIcon({ category: this.pullCategory(pull), name: this.iconOfPull(pull), iconSize: 40, remoteFallback: true })
      } else {
        Text(this.pullInitial(pull))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
      }
    }
    .width(40).height(40).borderRadius(6).clip(true)
    .accessibilityText(this.displayItemName(pull.itemId, pull.name, pull.itemType))
  }

  /** 列表行角标（保底/UP） */
  @Builder
  pullBadge(label: string, color: ResourceColor) {
    Text(label)
      .fontSize(11)
      .fontColor(color)
  }

  /** 卡头记录视图切换按钮（对齐 Windows LayoutSwitch 两档：≡ 列表 / ▦ 方块） */
  @Builder
  poolViewBtn(card: PoolCardData, isListMode: boolean) {
    Button() {
      Stack({ alignContent: Alignment.Bottom }) {
        Text(isListMode ? '≡' : '▦').fontSize(16).height(44)
          .fontColor(this.isPoolListView(card) === isListMode ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        if (this.isPoolListView(card) === isListMode) {
          Row().width(14).height(2).borderRadius(1).backgroundColor($r('app.color.app_primary')).margin({ bottom: 4 })
        }
      }.height(44)
    }
      .type(ButtonType.Normal).buttonStyle(ButtonStyleMode.NORMAL)
      .width(44)
      .height(44)
      .padding(0)
      .accessibilityText(isListMode ? '列表视图' : '网格视图')
      .borderRadius(6)
      .backgroundColor(this.isPoolListView(card) === isListMode
        ? $r('app.color.card_inner_tint')
        : Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.setPoolListView(card.gachaType, isListMode);
      })
  }

  /**
   * 单张池卡片：对齐电脑版 Windows StatisticsCard.xaml
   *   外框 Grid（AcrylicGridCardStyle）
   *   ├─ Expander「卡头 + 统计详情」：卡头常显（池名 + 抽数 + Chevron），详情可折叠
   *   └─ 抽取摘要列表或网格在详情折叠后仍可查看。
   * Chevron 折叠状态每卡独立（对齐 WinUI Expander 内建开合），初始展开。
   */
  @Builder
  poolCard(card: PoolCardData) {
    Column() {
      // 卡头：池名、折叠时的总抽数、布局切换及展开按钮。
      Row({ space: 2 }) {
        Row({ space: 4 }) {
          Text(gachaPoolLabel(card.gachaType))
            .fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            .maxFontSize(16).minFontSize(12)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.isPoolCollapsed(card)) {
            Text(`${card.totalCount} 抽`).fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(1)
          }
        }
        .layoutWeight(1).height(44).borderRadius(8).hoverEffect(HoverEffect.Highlight)
        .onClick(() => { this.togglePoolDetail(card); })

        if (card.gachaType === GachaType.AVATAR_EVENT) {
          Toggle({ type: ToggleType.Button, isOn: this.showCombinedAvatarPulls }) {
            Text('★').fontSize(13).fontWeight(FontWeight.Medium)
              .fontColor(this.showCombinedAvatarPulls ? $r('app.color.app_primary_text') : $r('app.color.text_secondary'))
          }
          .width(44).height(44).padding(0).hoverEffect(HoverEffect.Highlight)
          .attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .selectedColor($r('app.color.nav_selected'))
          .borderRadius(6)
          .accessibilityText(COMBINED_MODE_LABEL)
          .bindTips(COMBINED_MODE_LABEL, { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
          .onChange((isOn: boolean) => { this.showCombinedAvatarPulls = isOn; })
        }
        if (!this.isPoolCollapsed(card)) {
          Row() {
            this.poolViewBtn(card, true)
            this.poolViewBtn(card, false)
          }.borderRadius(6).border({ width: 1, color: $r('app.color.card_stroke') })
        }
        Button(this.isPoolCollapsed(card) ? '⌄' : '⌃').type(ButtonType.Normal).buttonStyle(ButtonStyleMode.NORMAL)
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .width(44).height(44).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText(this.isPoolCollapsed(card) ? '展开统计' : '折叠统计')
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => { this.togglePoolDetail(card); })
      }
      .width('100%')
      .padding({ left: 10, right: 4, top: 2, bottom: 2 })
      .alignItems(VerticalAlign.Center)
      .borderRadius(6)
      .backgroundColor($r('app.color.card_inner_tint'))

      Column({ space: 7 }) {
        if (!this.isPoolCollapsed(card)) {
          Row() {
            Text(`${card.totalCount}`).fontSize(44).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text($r('app.string.ui_account_insights_unit_wish')).fontSize(12).fontColor($r('app.color.text_secondary'))
              .margin({ left: 8, bottom: 8 })
          }.width('100%').alignItems(VerticalAlign.Bottom)

          Row({ space: 5 }) {
            if (card.gachaType !== GachaType.UGC_STANDARD) {
              this.guaranteeBar($r('app.string.ui_gacha_card_to_five'), card.sinceLastFive,
                GachaPoolRules.fiveStarThreshold(card.gachaType), `累计五星 ${card.fiveCount} 个`, $r('app.color.five_star'))
            }
            this.guaranteeBar($r('app.string.ui_gacha_card_to_four'), card.sinceLastFour,
              GachaPoolRules.fourStarThreshold(card.gachaType), `累计四星 ${card.fourCount} 个`, $r('app.color.four_star'))
            if (card.gachaType === GachaType.UGC_STANDARD) {
              this.guaranteeBar($r('app.string.ui_gacha_card_to_three'), card.sinceLastThree,
                GachaPoolRules.threeStarThreshold(card.gachaType), `累计三星 ${card.threeCount} 个`, $r('app.color.three_star'))
            }
          }.width('100%').alignItems(VerticalAlign.Top)

          Row({ space: 5 }) {
            Divider().layoutWeight(1).color($r('app.color.divider'))
            if (card.startDate.length > 0) {
              Text(`${card.startDate} - ${card.endDate}`).fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(1)
            }
            Divider().layoutWeight(1).color($r('app.color.divider'))
          }.width('100%').height(18)

          Row() {
            this.statSegmentChip(card.gachaType, $r('app.string.ui_gacha_card_statistics'), false)
            this.statSegmentChip(card.gachaType, $r('app.string.ui_gacha_card_ratio'), true)
          }.width('100%').borderRadius(4).border({ width: 1, color: $r('app.color.divider') })

          if (!this.showsRatio(card.gachaType)) {
            Row({ space: 4 }) {
              this.statCellBox(card.gachaType === GachaType.UGC_STANDARD
                ? $r('app.string.ui_gacha_card_four_average') : $r('app.string.ui_gacha_card_five_average'),
                GachaLogPage.averageText(card.gachaType === GachaType.UGC_STANDARD ? card.avgPurple : card.avgOrange),
                $r('app.color.text_primary'), $r('app.color.text_secondary'), true)
              if (GachaLogPage.poolHasUp(card.gachaType)) {
                this.statCellBox($r('app.string.ui_gacha_card_up_average'), GachaLogPage.averageText(card.avgUpOrange),
                  $r('app.color.text_primary'), $r('app.color.text_secondary'), true)
              }
              Column({ space: 4 }) {
                this.statMiniBox(`最非 ${card.maxOrange}`, $r('app.color.text_primary'))
                this.statMiniBox(`最欧 ${card.minOrange}`, $r('app.color.text_primary'))
              }.layoutWeight(1).height(64)
            }.width('100%')
          } else {
            Row({ space: 4 }) {
              if (card.gachaType !== GachaType.UGC_STANDARD) {
                this.statCellBox($r('app.string.ui_model_intrinsic_item_quality_orange'),
                  GachaLogPage.countText(card.fiveCount, card.totalCount), $r('app.color.five_star'), $r('app.color.five_star'), false)
              }
              this.statCellBox($r('app.string.ui_model_intrinsic_item_quality_purple'),
                GachaLogPage.countText(card.fourCount, card.totalCount), $r('app.color.four_star'), $r('app.color.four_star'), false)
              this.statCellBox($r('app.string.ui_model_intrinsic_item_quality_blue'),
                GachaLogPage.countText(card.threeCount, card.totalCount), $r('app.color.three_star'), $r('app.color.three_star'), false)
              if (card.gachaType === GachaType.UGC_STANDARD) {
                this.statCellBox('其他', GachaLogPage.countText(card.otherCount, card.totalCount),
                  $r('app.color.success'), $r('app.color.success'), false)
              }
            }.width('100%')
          }
        }

        Divider().width('100%').color($r('app.color.divider'))
        if (this.isWide) {
          Scroll() {
            Column() { this.summaryArea(card) }.width('100%').alignItems(HorizontalAlign.Start)
          }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
            .width('100%')
            .layoutWeight(1)
            .align(Alignment.TopStart)
        } else {
          this.summaryArea(card)
        }
      }.width('100%').layoutWeight(this.isWide ? 1 : 0).padding(10)
    }
    .width(this.isWide ? this.widePoolCardWidth() : '100%')
    .height(this.isWide ? LayoutPolicy.matchParent : LayoutPolicy.wrapContent)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .borderRadius(8)
    .border({
      width: card.isCurrent && !this.isWide ? 2 : 1,
      color: card.isCurrent && !this.isWide ? $r('app.color.app_primary') : $r('app.color.card_stroke'),
    })
  }

  /** 宽屏等高横滚，窄屏随页面纵向滚动。 */
  @Builder
  poolCardsArea() {
    if (this.poolCards.length === 0) {
      Text(this.vm.currentArchiveId > 0 ? '此归档暂无祈愿记录' : '导入 UIGF 或登录后刷新以创建祈愿归档')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .textAlign(TextAlign.Center)
    } else if (this.isWide) {
      Scroll() {
        Row({ space: POOL_CARD_GAP }) {
          ForEach(this.poolCards, (card: PoolCardData) => {
            this.poolCard(card)
          }, (card: PoolCardData): string => card.key)
        }
          .width(this.poolCards.length * this.widePoolCardWidth() + (this.poolCards.length - 1) * POOL_CARD_GAP)
          .height('100%')
          .alignItems(VerticalAlign.Top)
      }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.TopStart)
    } else {
      Column({ space: 10 }) {
        ForEach(this.poolCards, (card: PoolCardData) => {
          this.poolCard(card)
        }, (card: PoolCardData): string => card.key)
      }.width('100%')
    }
  }

  @Builder
  itemRow(item: GachaItem) {
    Row({ space: 10 }) {
      this.historyItemIcon(this.itemIcon(item.itemId, item.name, item.itemType), item.rankType)
      Column({ space: 2 }) {
        Text(this.displayItemName(item.itemId, item.name, item.itemType))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.displayItemType(item))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(item.time)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.showItemDetail(item);
    })
  }

  @Builder
  historyItemIcon(icon: GachaItemIcon, rank: number) {
    if (icon.name.length > 0) {
      MetaIcon({ category: icon.category, name: icon.name, iconSize: 36, remoteFallback: true })
        .borderRadius(18).clip(true)
    } else {
      this.starPlaceholder(rank)
    }
  }

  /** 星级占位（无元数据映射时兜底） */
  @Builder
  starPlaceholder(rank: number) {
    Text(rank === 5 ? '★' : (rank === 4 ? '◆' : '·'))
      .fontSize(16)
      .fontColor(rank === 5 ? $r('app.color.app_primary') : (rank === 4 ? $r('app.color.notice_on') : $r('app.color.text_secondary')))
      .width(36)
      .height(36)
      .textAlign(TextAlign.Center)
      .borderRadius(18)
      .backgroundColor(rank === 5 ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))
      .border({ width: 1, color: rank === 5 ? $r('app.color.app_primary') : $r('app.color.divider') })
  }

  /** 弹出抽卡记录详情 */
  showItemDetail(item: GachaItem): void {
    const poolName: string = this.poolLabelText(item.gachaType);
    this.getUIContext().getPromptAction().showDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: this.displayItemName(item.itemId, item.name, item.itemType),
      message:
        `类型：${this.displayItemType(item)}\n` +
        `星级：${item.rankStars()}\n` +
        `卡池：${poolName}\n` +
        `时间：${item.time}`,
      buttons: [
        { text: '知道了', color: $r('app.color.app_primary') },
      ],
    });
  }

  /** 抽卡历史列表（当前选中池，LazyForEach 虚拟滚动；历史页） */
  @Builder
  recentSection() {
    Column({ space: 6 }) {
      Text('抽卡明细').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      if (this.vm.items.length === 0) {
        Text('当前卡池暂无抽卡明细').fontSize(13).fontColor($r('app.color.text_secondary'))
          .width('100%').padding({ top: 20, bottom: 20 }).textAlign(TextAlign.Center)
      } else {
        List({ space: 0 }) {
          LazyForEach(this.historySource, (item: GachaItem) => {
            ListItem() { this.itemRow(item) }
          }, (item: GachaItem): string =>
            `${item.gachaId || `${item.time}_${item.name}`}_${this.appliedLocaleVersion}`)
        }.width('100%').height(420).cachedCount(5).scrollBar(BarState.Auto)
          .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  @Builder
  progressPanel() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color($r('app.color.app_primary'))
        Text(this.progressText)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button($r('app.string.common_cancel')).attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .constraintSize({ minHeight: 44 })
          .onClick(() => this.vm.cancelRefresh())
        Text(this.showProgressDetail ? '收起 ‹' : '详情 ›')
          .fontSize(11)
          .fontColor($r('app.color.app_primary_text'))
          .onClick(() => {
            this.showProgressDetail = !this.showProgressDetail;
          })
      }
      .width('100%')
      Text(`已拉取 ${this.progressCount} 条`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      // 展开的实时详情区（动态更新，非静态弹窗）
      if (this.showProgressDetail) {
        Column({ space: 6 }) {
          if (this.vm.progress.pools.length > 0) {
            Text(gachaPoolLabel(this.vm.progress.pools[this.vm.progress.pools.length - 1].gachaType))
              .fontSize(12).fontColor($r('app.color.text_primary')).width('100%')
          }
          // 新拉取记录头像流（对齐 Windows：实时滚动物品/角色头像，星级描边 + 计数角标）
          if (this.recentItems.length > 0) {
            Text('最新抽到')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_primary_text'))
              .width('100%')
              .margin({ top: 2 })
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.recentItems, (it: RecentGachaItem, idx: number) => {
                  Column({ space: 2 }) {
                    Stack({ alignContent: Alignment.BottomEnd }) {
                      MetaIcon({
                        category: this.itemIcon(it.itemId, it.name, it.itemType).category,
                        name: this.itemIcon(it.itemId, it.name, it.itemType).name,
                        iconSize: 40,
                        remoteFallback: true,
                      })
                      if (it.count > 1) {
                        Text(`x${it.count}`)
                          .fontSize(9)
                          .fontColor(Color.White)
                          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                          .borderRadius(6)
                          .backgroundColor($r('app.color.overlay_scrim'))
                      }
                    }
                    .width(44)
                    .height(44)
                    .borderRadius(10)
                    .accessibilityText(this.displayItemName(it.itemId, it.name, it.itemType))
                    .border({
                      width: it.rank >= 5 ? 2 : 1,
                      color: it.rank >= 5 ? $r('app.color.five_star') :
                        (it.rank === 4 ? $r('app.color.four_star') : $r('app.color.divider')),
                    })
                  }
                }, (it: RecentGachaItem, idx: number) => `rn_${idx}_${it.itemId}_${it.name}_${this.appliedLocaleVersion}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
            .height(58)
          } else {
            Text('暂无新记录')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
        }
        .width('100%')
        .padding({ top: 6, left: 4, right: 4 })
        .borderRadius(8)
        .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor($r('app.color.app_primary_bg'))
  }

  /** 刷新结果摘要卡（UX07：来源/目标/增量全量/新增/重复/失败分列 + 失败池单项重试） */
  @Builder
  resultPanel() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('刷新结果')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.vm.fullRefresh ? '全量' : '增量'} · ${this.resultOrEmpty().sourceText}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text($r('app.string.ui_info_bar_panel_contract_content')).fontSize(11).fontColor($r('app.color.app_primary_text'))
          .onClick(() => this.dismissRefreshResult())
      }
      .width('100%')
      Text(`目标 UID：${this.resultOrEmpty().uid.length > 0 ? this.resultOrEmpty().uid : '--'} · 共写入 ${this.resultOrEmpty().fetchedCount} 条`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      // 池级明细：新增/重复分列，失败池给出原因与单项重试（部分成功可见）
      ForEach(this.resultOrEmpty().pools, (o: PoolOutcome) => {
        Row({ space: 8 }) {
          Text(gachaPoolLabel(o.gachaType))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (o.failed) {
            Text(o.errorText)
              .fontSize(11)
              .fontColor($r('app.color.danger'))
              .layoutWeight(2)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Button('重试此池').attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .constraintSize({ minHeight: 44 })
              .onClick(() => this.retryPool(o.gachaType))
          } else {
            Text(o.inserted > 0 ? `新增 ${o.inserted}` : '无新增')
              .fontSize(11)
              .fontColor($r('app.color.app_primary_text'))
            Text(`重复 ${o.duplicates}`)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (o: PoolOutcome) => `po_${o.gachaType}_${o.inserted}_${o.duplicates}_${o.failed}`)
      if (this.resultOrEmpty().error.length > 0) {
        Text(this.resultOrEmpty().error)
          .fontSize(11)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Button('重新刷新').attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
        .constraintSize({ minHeight: 44 })
        .onClick(() => this.refreshAccount())
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .alignItems(HorizontalAlign.Start)
  }

  /** 弹窗展示拉取进度详情（保留：供外部入口调用时显示静态摘要） */
  showProgressDetailDialog(): void {
    this.getUIContext().getPromptAction().showDialog({ systemMaterial: UiSurface.dialogMaterial(),
      title: '拉取进度',
      message:
        `当前卡池：${this.vm.progress.currentPoolName.length > 0 ? this.vm.progress.currentPoolName : '--'}\n` +
        `已拉取：${this.progressCount} 条\n` +
        `${this.progressText}`,
      buttons: [
        { text: '知道了', color: $r('app.color.app_primary') },
      ],
    });
  }

  /** 从系统剪贴板读取祈愿 URL（含 authkey）并导入 */
  async importFromClipboard(): Promise<void> {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    const epoch: number = this.pageEpoch;
    try {
      const data: string = await pasteboard.getSystemPasteboard().getData().then((pd: pasteboard.PasteData) => {
        return pd.getPrimaryText();
      });
      if (!this.pageActive || epoch !== this.pageEpoch) { return; }
      if (data.length === 0 || !data.includes('authkey=')) {
        this.toast('剪贴板中没有检测到祈愿链接（需包含 authkey）');
        return;
      }
      this.urlInput = data;
      this.showUrlInput = true;
      this.toast('已从剪贴板读取链接，点击「导入」开始拉取');
    } catch (e) {
      if (this.pageActive && epoch === this.pageEpoch) { this.toast(`读取剪贴板失败：${(e as Error).message}`); }
    }
  }

  /** 选择 UIGF 文件；文档读取、UTF-8 解码及全文件校验在 taskpool 完成。 */
  async uigfImport(): Promise<void> {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    const epoch: number = this.pageEpoch;
    this.vm.isTransferring = true;
    this.vm.clearImport();
    this.showImportPreview = false;
    this.showExportOptions = false;
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['.json'];
      const uris: string[] = await docPicker.select(opts);
      if (!this.pageActive || epoch !== this.pageEpoch || uris.length === 0) {
        return;
      }
      const ready: boolean = await this.vm.prepareImportFile(uris[0]);
      if (!this.pageActive || epoch !== this.pageEpoch || !ready) { return; }
      this.showImportPreview = true;
    } catch (e) {
      if (this.pageActive && epoch === this.pageEpoch) {
        this.vm.clearImport();
        this.showImportPreview = false;
        this.toast(`导入失败：${(e as Error).message}`);
      }
    } finally { this.vm.isTransferring = false; }
  }

  /** 用户选择目标版本和 UID 后导出；不能表示的数据会明确拒绝。 */
  async uigfExport(): Promise<void> {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring || this.vm.archives.length === 0) { return; }
    const epoch: number = this.pageEpoch;
    this.vm.isTransferring = true;
    try {
      const json: string = await UigfService.getInstance().buildExportJson(this.vm.exportUids.slice(), this.vm.exportVersion);
      if (!this.pageActive || epoch !== this.pageEpoch) { return; }
      if (json.length > UIGF_MAX_BYTES) { throw new Error('UIGF 导出超过 32 MiB 限制'); }
      const bytes: Uint8Array = util.TextEncoder.create().encodeInto(json);
      if (bytes.byteLength > UIGF_MAX_BYTES) { throw new Error('UIGF 导出超过 32 MiB 限制'); }
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.newFileNames = ['uigf_gacha_export.json'];
      const uris: string[] = await docPicker.save(opts);
      if (!this.pageActive || epoch !== this.pageEpoch || uris.length === 0) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try {
        const written: number = fileIo.writeSync(file.fd, bytes.buffer);
        if (written !== bytes.byteLength) { throw new Error('UIGF 文件写入不完整，请重新导出'); }
      } finally {
        fileIo.closeSync(file);
      }
      this.showExportOptions = false;
      this.toast(`导出成功（UIGF ${this.vm.exportVersion}）`);
    } catch (e) {
      const message: string = `导出失败：${(e as Error).message}`;
      Logger.warn('GachaLogPage', message);
      if (this.pageActive && epoch === this.pageEpoch) { this.toast(message); }
    } finally { this.vm.isTransferring = false; }
  }

  private async confirmUigfImport(fillGaps: boolean = false): Promise<void> {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    const epoch: number = this.pageEpoch;
    try {
      const result = await this.vm.confirmImport(fillGaps);
      if (!this.pageActive || epoch !== this.pageEpoch) { return; }
      this.toast(result.message);
      if (result.ok) {
        this.showImportPreview = false;
        this.resetLocalView();
        this.syncAll();
        if (this.pivotIndex === 1) { this.loadHistoryWishes(); }
      }
    } catch (e) {
      if (this.pageActive && epoch === this.pageEpoch) { this.toast(`导入失败：${(e as Error).message}`); }
    }
  }

  private prepareUigfExport(): void {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    this.vm.clearImport();
    this.showImportPreview = false;
    this.vm.exportUids = this.vm.archives.map((archive: GachaArchive): string => archive.uid);
    this.showExportOptions = true;
  }

  private changeUigfSelection(uid: string, selected: boolean, importing: boolean): void {
    if (this.vm.isTransferring || this.vm.isRefreshing) { return; }
    const source: string[] = importing ? this.vm.importUids : this.vm.exportUids;
    const next: string[] = source.filter((value: string): boolean => value !== uid);
    if (selected) { next.push(uid); }
    if (importing) { this.vm.importUids = next; } else { this.vm.exportUids = next; }
  }

  @Builder
  importPreviewPanel() {
    Column({ space: 8 }) {
      Text(`UIGF ${this.vm.importPreview.version} · ${this.vm.importPreview.totalCount} 条唯一记录`)
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text('默认追加早于各池最旧记录的历史。也可以补齐文件中所有缺失记录。')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      ForEach(this.vm.importPreview.archives, (archive: UigfArchivePreview) => {
        Row({ space: 8 }) {
          Checkbox({ name: `uigf_import_${archive.uid}` }).select(this.vm.importUids.indexOf(archive.uid) >= 0)
            .width(44).height(44).accessibilityText(`导入 UID ${archive.uid}，${archive.totalCount} 条记录`)
            .enabled(!this.vm.isTransferring).onChange((selected: boolean) => this.changeUigfSelection(archive.uid, selected, true))
          Text(`${archive.uid} · ${archive.totalCount} 条（颂愿 ${archive.beyondCount}）`).fontSize(12).fontColor($r('app.color.text_primary'))
        }.width('100%').constraintSize({ minHeight: 44 })
      }, (archive: UigfArchivePreview) => archive.uid)
      Flex({ wrap: FlexWrap.Wrap }) {
        Button($r('app.string.common_cancel')).constraintSize({ minHeight: 44 }).margin({ right: 8, bottom: 4 }).enabled(!this.vm.isTransferring).hoverEffect(HoverEffect.Highlight)
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .onClick(() => { this.vm.clearImport(); this.showImportPreview = false; })
        Button('确认导入所选 UID').constraintSize({ minHeight: 44 }).margin({ right: 8, bottom: 4 }).enabled(this.vm.importUids.length > 0 && !this.vm.isTransferring && !this.vm.isRefreshing)
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .hoverEffect(HoverEffect.Highlight).onClick(() => this.confirmUigfImport())
        Button('补齐缺失记录').constraintSize({ minHeight: 44 }).margin({ right: 8, bottom: 4 }).enabled(this.vm.importUids.length > 0 && !this.vm.isTransferring && !this.vm.isRefreshing)
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .hoverEffect(HoverEffect.Highlight).onClick(() => this.confirmUigfImport(true))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12)
      .borderRadius($r('app.float.card_radius')).attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  @Builder
  exportOptionsPanel() {
    Column({ space: 8 }) {
      Text(`选择导出 UID · UIGF ${this.vm.exportVersion}`).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Select([{ value: 'v4.2' }, { value: 'v4.1' }, { value: 'v4.0' }, { value: 'v3.0' }, { value: 'v2.4' }, { value: 'v2.3' }, { value: 'v2.2' }]).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
        .value(this.vm.exportVersion).constraintSize({ minHeight: 44 }).accessibilityText('UIGF 导出版本')
        .enabled(!this.vm.isTransferring).onSelect((index: number, value: string) => { this.vm.exportVersion = value; })
      Text('选择需要导出的归档。颂愿使用 v4.2，集录使用 v3.0 及以上版本；v2.x 和 v3.0 每次导出一个 UID。')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      ForEach(this.vm.archives, (archive: GachaArchive) => {
        Row({ space: 8 }) {
          Checkbox({ name: `uigf_export_${archive.uid}` }).select(this.vm.exportUids.indexOf(archive.uid) >= 0)
            .width(44).height(44).accessibilityText(`导出 UID ${archive.uid}`)
            .enabled(!this.vm.isTransferring).onChange((selected: boolean) => this.changeUigfSelection(archive.uid, selected, false))
          Text(archive.uid).fontSize(12).fontColor($r('app.color.text_primary'))
        }.width('100%').constraintSize({ minHeight: 44 })
      }, (archive: GachaArchive) => archive.uid)
      Flex({ wrap: FlexWrap.Wrap }) {
        Button($r('app.string.common_cancel')).constraintSize({ minHeight: 44 }).margin({ right: 8, bottom: 4 }).enabled(!this.vm.isTransferring).hoverEffect(HoverEffect.Highlight)
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .onClick(() => { this.vm.exportUids = []; this.showExportOptions = false; })
        Button('导出所选 UID').constraintSize({ minHeight: 44 }).margin({ right: 8, bottom: 4 }).enabled(this.vm.exportUids.length > 0 && !this.vm.isTransferring && !this.vm.isRefreshing)
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .hoverEffect(HoverEffect.Highlight).onClick(() => this.uigfExport())
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12)
      .borderRadius($r('app.float.card_radius')).attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  @Builder
  archivePicker() {
    if (this.vm.archives.length > 0) {
      Select(this.archiveOptions())
        .attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
        .font({ size: 13 }).borderRadius(6)
        .selected(this.currentArchiveIndex()).value(this.vm.currentUid)
        .width(this.isWide ? 144 : '100%').constraintSize({ minHeight: 44, maxWidth: 144 }).optionWidth(160)
        .accessibilityText('选择本地祈愿归档').accessibilityDescription(this.vm.currentUid)
        .enabled(!this.vm.isRefreshing && !this.vm.isTransferring)
        .onSelect((index: number) => {
          if (index >= 0 && index < this.vm.archives.length) { this.chooseLocalArchive(this.vm.archives[index].id); }
        })
    } else {
      Text($r('app.string.ui_settings_no_wish_archives')).fontSize(12).fontColor($r('app.color.text_secondary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  toolbarTabs() {
    Scroll() {
      Row({ space: 2 }) {
        this.pivotTab(0, $r('app.string.ui_gacha_pivot_overview'))
        if (!this.beyondMode) {
          this.pivotTab(1, $r('app.string.ui_gacha_pivot_history'))
          this.pivotTab(2, $r('app.string.ui_gacha_pivot_avatar'))
          this.pivotTab(3, $r('app.string.ui_gacha_pivot_weapon'))
          this.pivotTab(4, $r('app.string.ui_gacha_pivot_countdown'))
        }
      }
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(44)
      .align(Alignment.TopStart)
  }

  @Builder
  toolbarActions() {
    Button() {
      Row({ space: 4 }) {
        Text('↻').fontSize(17).fontColor($r('app.color.text_primary'))
        if (this.isWide) {
          Text($r('app.string.common_refresh')).fontSize(13).fontColor($r('app.color.text_primary')).maxLines(1)
        }
      }
    }
      .type(ButtonType.Normal).buttonStyle(ButtonStyleMode.NORMAL).backgroundColor(Color.Transparent).borderRadius(6)
      .padding({ left: this.isWide ? 8 : 0, right: this.isWide ? 8 : 0 })
      .constraintSize({ minHeight: 44, minWidth: 44 }).hoverEffect(HoverEffect.Highlight)
      .accessibilityText($r('app.string.common_refresh'))
      .enabled(this.isLoggedIn && this.vm.gameAccountUid.length > 0 && !this.vm.isRefreshing && !this.vm.isTransferring)
      .onClick(() => { this.refreshAccount(); })
    this.beyondToggleChip()
    Button('⋯').type(ButtonType.Normal).buttonStyle(ButtonStyleMode.NORMAL).backgroundColor(Color.Transparent).borderRadius(6)
      .fontSize(18).fontColor($r('app.color.text_primary')).width(44).height(44).padding(0)
      .hoverEffect(HoverEffect.Highlight).accessibilityText('祈愿归档操作')
      .bindMenu(this.archiveActions(), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
  }

  @Builder
  toolbarLeading() {
    Row({ space: 8 }) {
      this.archivePicker()
      Column() { this.toolbarTabs() }.layoutWeight(1)
    }.width('100%')
  }

  @Builder
  compactToolbar() {
    Column() {
      Row({ space: 4 }) {
        Column() { this.archivePicker() }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.toolbarActions()
      }.width('100%')
      this.toolbarTabs()
    }.width('100%')
  }

  @Builder
  importBusyNotice() {
    Row({ space: 8 }) {
      Text('正在后台读取、校验 UIGF…').fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
      Button($r('app.string.common_cancel')).constraintSize({ minHeight: 44 })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .onClick(() => { this.vm.clearImport(); this.showImportPreview = false; })
    }.width('100%')
  }

  @Builder
  urlInputPanel() {
    Column({ space: 10 }) {
      Text('粘贴祈愿链接（含 authkey）')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextArea({ placeholder: 'https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog?...', text: this.urlInput })
        .height(90)
        .fontSize(12)
        .onChange((value: string) => {
          this.urlInput = value;
        })
      Row({ space: 10 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .constraintSize({ minHeight: 44 })
          .onClick(() => {
            this.showUrlInput = false;
          })
        Button($r('app.string.ui_action_import'))
          .layoutWeight(1)
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .constraintSize({ minHeight: 44 })
          .onClick(() => {
            this.submitUrlImport();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }

  private hasTransferPanels(): boolean {
    return this.vm.isPreparingImport || this.showImportPreview || this.showExportOptions ||
      this.vm.isRefreshing || this.showRefreshResult() || this.showUrlInput;
  }

  @Builder
  transferPanels() {
    if (this.vm.isPreparingImport) { this.importBusyNotice() }
    if (this.showImportPreview) { this.importPreviewPanel() }
    if (this.showExportOptions) { this.exportOptionsPanel() }
    if (this.vm.isRefreshing) {
      this.progressPanel()
    } else if (this.showRefreshResult()) {
      this.resultPanel()
    }
    if (this.showUrlInput) { this.urlInputPanel() }
  }

  build() {
    Stack() {
      // 壁纸衬底：本页恒为 Index 壳层内嵌（壳层已铺壁纸），PageBackdrop 渲染为空仅透传
      PageBackdrop({ embedMode: true })
      Column() {
        Column() {
          if (this.isWide) {
            PageToolbar({ leading: (): void => this.toolbarLeading(), trailing: (): void => this.toolbarActions() })
          } else {
            PageToolbar({ leading: (): void => this.compactToolbar() })
          }
        }.width('100%').padding({ left: 16, right: 16, top: 6, bottom: 8 })

        if (this.isWide && this.pivotIndex === 0) {
          Column({ space: 8 }) {
            if (this.hasTransferPanels()) {
              Scroll() {
                Column({ space: 10 }) { this.transferPanels() }.width('100%')
              }
                .width('100%')
                .constraintSize({ maxHeight: this.areaHeight * 0.4 })
                .scrollBar(BarState.Auto)
                .align(Alignment.TopStart)
            }
            this.poolCardsArea()
          }.width('100%').layoutWeight(1)
            .padding({ left: POOL_VIEW_INSET, right: POOL_VIEW_INSET, bottom: 16 })
        } else if (!this.beyondMode && this.pivotIndex === 4 && !this.vm.isPreparingImport && !this.vm.isRefreshing &&
          !this.showImportPreview && !this.showExportOptions && !this.showUrlInput) {
          Column() {
            WishHistoryPage({ embedMode: true, showHeader: false })
          }.width('100%').layoutWeight(1)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              this.transferPanels()

              // 总览在宽屏同时展示所有池，历史的抽卡明细始终按所选池展示。
              if (this.vm.currentArchiveId > 0 && (this.pivotIndex === 1 || (!this.isWide && this.pivotIndex === 0))) {
                this.poolTabs()
              }

              if (this.pivotIndex === 0) {
                this.poolCardsArea()
              } else if (this.pivotIndex === 1) {
                this.historyWishSection()
                this.recentSection()
              } else if (this.pivotIndex === 2) {
                this.avatarSection(true)
              } else if (this.pivotIndex === 3) {
                this.avatarSection(false)
              } else if (this.pivotIndex === 5) {
                this.distributionPanel()
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 16 })
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
        }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.onPoolAreaChange(Number(newValue.width), Number(newValue.height));
    })
    }
    .width('100%')
    .height('100%')
  }

  /** Pivot 页签按钮 */
  @Builder
  pivotTab(index: number, label: Resource) {
    Stack({ alignContent: Alignment.Bottom }) {
      Text(label)
        .fontSize(14).fontWeight(this.pivotIndex === index ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.pivotIndex === index ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .padding({ left: 10, right: 10 }).height(44).maxLines(1)
      if (this.pivotIndex === index) {
        Row().width(22).height(3).borderRadius(2).backgroundColor($r('app.color.app_primary')).margin({ bottom: 2 })
      }
    }.height(44).constraintSize({ minWidth: 44 }).borderRadius(6)
      .accessibilityText(label)
      .accessibilityDescription(this.pivotIndex === index ? $r('app.string.ui_option_selected') : $r('app.string.ui_option_unselected'))
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => { this.selectPivot(index); })
  }

  private selectPivot(index: number): void {
    this.pivotIndex = index;
    if (index === 1) { this.loadHistoryWishes(); }
    this.syncAll();
  }

  /** 期次汇总（对齐 Windows PivotHistory：版本+池名+UP 五星/四星获取数+时间跨度） */
  async loadHistoryWishes(preloadBanners: boolean = true): Promise<void> {
    if (!this.pageActive || this.vm.currentArchiveId <= 0 || this.historyLoading) {
      return;
    }
    if (this.historyLoadedFor === this.vm.currentArchiveId && this.historyWishes.length > 0) {
      return;
    }
    this.historyLoading = true;
    const epoch: number = this.pageEpoch;
    const generation: number = ++this.historyGeneration;
    const archiveId: number = this.vm.currentArchiveId;
    try {
      const views: HistoryWishView[] = await GachaHistoryService.getInstance()
        .buildHistory(archiveId,
        PreferencesStore.getBool(PreferencesStore.KEY_GACHA_EMPTY_HISTORY, false));
      if (!this.pageActive || epoch !== this.pageEpoch || generation !== this.historyGeneration || archiveId !== this.vm.currentArchiveId) { return; }
      this.historyWishes = views;
      this.historyLoadedFor = archiveId;
      if (preloadBanners) { this.preloadHistoryBanners(views); }
    } catch (e) {
      if (this.pageActive && epoch === this.pageEpoch && generation === this.historyGeneration && archiveId === this.vm.currentArchiveId) {
        this.toast(`祈愿历史加载失败：${(e as Error).message}`);
      }
    } finally {
      if (generation === this.historyGeneration) { this.historyLoading = false; }
    }
  }

  /**
   * 预载期次横幅图到沙盒缓存（对齐 Windows HistoryWish.BannerImage）：
   * 下载完成整体替换 @State 数组触发卡片补绘横幅；失败留空，卡片不渲染横幅。
   */
  private preloadHistoryBanners(views: HistoryWishView[]): void {
    const epoch: number = this.pageEpoch;
    const archiveId: number = this.vm.currentArchiveId;
    // 循环外快照已命中的 URL（避免循环内反复读 @State）
    const known: Set<string> = new Set<string>();
    for (const k of this.bannerPaths) {
      known.add(k.url);
    }
    const jobs: Promise<GachaBannerPath | undefined>[] = [];
    for (const v of views) {
      if (v.banner.length === 0 || known.has(v.banner)) {
        continue;
      }
      known.add(v.banner);
      const url: string = v.banner;
      // 循环内不触碰 @State：只收集异步结果（lint: 避免循环内反复访问状态变量）
      jobs.push(CachedImageService.fetchToCache(url).then((p: string): GachaBannerPath | undefined => {
        if (!this.pageActive || epoch !== this.pageEpoch || archiveId !== this.vm.currentArchiveId || p.length === 0) {
          return undefined;
        }
        const hit: GachaBannerPath = new GachaBannerPath();
        hit.url = url;
        hit.path = p;
        return hit;
      }));
    }
    if (jobs.length > 0) {
      // 全部下载收敛后一次性重赋值 @State（@State 数组 push 不触发深层级刷新）
      Promise.all(jobs).then((loaded: (GachaBannerPath | undefined)[]) => {
        const snapshot: GachaBannerPath[] = this.bannerPaths.slice();
        let added: number = 0;
        for (const item of loaded) {
          if (item !== undefined) {
            snapshot.push(item);
            added++;
          }
        }
        if (added === 0) { return; }
        this.bannerPaths = snapshot;
      }).catch(() => {
      });
    }
  }

  /** 横幅 URL → 本地缓存路径（未命中返回空串） */
  private bannerPathOf(url: string): string {
    for (let i = 0; i < this.bannerPaths.length; i++) {
      if (this.bannerPaths[i].url === url) {
        return this.bannerPaths[i].path;
      }
    }
    return '';
  }

  /** 期次横幅高度：按 1080:533 比例随卡宽走（对齐 Windows ConstrainedBox），限幅防超长 */
  private historyBannerHeight(): number {
    const byRatio: number = Math.max(0, this.areaWidth - 72) * (533 / 1080);
    return Math.round(Math.min(260, Math.max(120, byRatio)));
  }

  /** 期次卡头时间跨度文案（对齐 FormattedTimeSpan：yyyy/MM/dd - yyyy/MM/dd） */
  private static wishSpanText(view: HistoryWishView): string {
    if (view.from <= 0 || view.to <= 0) {
      return '';
    }
    return `${GachaLogPage.wishDay(view.from)} - ${GachaLogPage.wishDay(view.to)}`;
  }

  private static historyWishKey(view: HistoryWishView): string {
    const items: string[] = view.orangeUps.concat(view.purpleUps).map((item: HistoryUpItem): string =>
      `${item.itemId}:${item.name}:${item.icon}:${item.category}:${item.count}`);
    return `history_${view.type}_${view.from}_${view.to}_${view.version}_${view.name}_${view.banner}_${view.totalCount}_${items.join('|')}`;
  }

  private static wishDay(ms: number): string {
    const d: Date = new Date(ms);
    const m: string = `${d.getMonth() + 1}`.padStart(2, '0');
    const day: string = `${d.getDate()}`.padStart(2, '0');
    return `${d.getFullYear()}/${m}/${day}`;
  }

  /** 期次 UP 条目（图标 + 获取数；对齐 HistoryWishItemTemplate：上图标下计数） */
  @Builder
  wishUpCell(up: HistoryUpItem) {
    Column({ space: 2 }) {
      if (up.icon.length > 0) {
        MetaIcon({ category: up.category, name: up.icon, iconSize: 40 })
      } else {
        Text(up.name)
          .fontSize(9)
          .fontColor($r('app.color.text_secondary'))
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
      }
      Text(`${up.count}`)
        .fontSize(11)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
    }
    .width(44)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  historyWishSection() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        Text('期次历史')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.historyWishes.length}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text('按卡池期次汇总')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      if (this.historyLoading) {
        Loading()
      } else if (this.historyWishes.length === 0) {
        Text(this.vm.currentArchiveId > 0
          ? '暂无期次记录（需常规池抽卡数据）'
          : '暂无本地归档，先导入 UIGF 或登录后刷新')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 6, bottom: 6 })
          .textAlign(TextAlign.Center)
      } else {
        ForEach(this.historyWishes, (view: HistoryWishView) => {
          Column({ space: 8 }) {
            // 卡池横幅图（对齐 Windows PivotHistory：1080:533 比例 UniformToFill，深色叠暗遮罩）
            if (view.banner.length > 0 && this.bannerPathOf(view.banner).length > 0) {
              Stack() {
                Image(`file://${this.bannerPathOf(view.banner)}`)
                  .width('100%')
                  .height(this.historyBannerHeight())
                  .objectFit(ImageFit.Cover)
                  .borderRadius(8)
                if (this.isDark) {
                  Column()
                    .width('100%')
                    .height(this.historyBannerHeight())
                    .borderRadius(8)
                    .backgroundColor($r('app.color.wallpaper_mask'))
                }
              }
              .width('100%')
            }
            Row({ space: 6 }) {
              Text(view.version.length > 0 ? `${view.version} · ${view.name}` : view.name)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${view.totalCount} 抽`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')

            if (view.orangeUps.length > 0) {
              Flex({
                wrap: FlexWrap.Wrap,
                justifyContent: FlexAlign.Start,
                space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) }
              }) {
                ForEach(view.orangeUps, (up: HistoryUpItem) => {
                  this.wishUpCell(up)
                }, (up: HistoryUpItem) => `o_${view.from}_${up.itemId}_${up.count}`)
              }
              .width('100%')
            }
            if (view.purpleUps.length > 0) {
              Flex({
                wrap: FlexWrap.Wrap,
                justifyContent: FlexAlign.Start,
                space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) }
              }) {
                ForEach(view.purpleUps, (up: HistoryUpItem) => {
                  this.wishUpCell(up)
                }, (up: HistoryUpItem) => `p_${view.from}_${up.itemId}_${up.count}`)
              }
              .width('100%')
            }

            if (GachaLogPage.wishSpanText(view).length > 0) {
              Text(GachaLogPage.wishSpanText(view))
                .fontSize(10)
                .opacity(0.6)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
          }
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
          .border({ width: 1, color: $r('app.color.card_stroke') })
          .alignItems(HorizontalAlign.Start)
        }, (view: HistoryWishView) => GachaLogPage.historyWishKey(view))
      }
    }
    .width('100%')
  }

  /**
   * 角色/武器头像网格区（按星级分组）。
   * 单参 @Builder：参数只放常量类别（是否角色），会变的条目列表在渲染期读组件状态——
   * ArkUI 规则：参数里带会变字段时 @Builder 内部 UI 不随状态刷新（见 AGENTS.md）。
   */
  @Builder
  avatarSection(isChar: boolean) {
    if (this.countsFor(isChar).length === 0) {
      Text('暂无数据，点击右上角「刷新」拉取')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .textAlign(TextAlign.Center)
    } else {
      Column({ space: 10 }) {
        if (this.countsFor(isChar).filter((e: ItemCountEntry) => e.rankType === 5).length > 0) {
          this.rankGroup(isChar, 5)
        }
        if (this.countsFor(isChar).filter((e: ItemCountEntry) => e.rankType === 4).length > 0) {
          this.rankGroup(isChar, 4)
        }
        if (!isChar && this.countsFor(isChar).filter((e: ItemCountEntry) => e.rankType === 3).length > 0) {
          this.rankGroup(isChar, 3)
        }
      }
      .width('100%')
    }
  }

  /** 头像网格条目（渲染期读取：角色/武器分列） */
  private countsFor(isChar: boolean): ItemCountEntry[] {
    return isChar ? this.charCounts : this.weaponCounts;
  }

  private countsForRank(isChar: boolean, rank: number): ItemCountEntry[] {
    return this.countsFor(isChar).filter((entry: ItemCountEntry): boolean => entry.rankType === rank);
  }

  @Builder
  rankGroup(isChar: boolean, rank: number) {
    if (this.countsForRank(isChar, rank).length > 0) {
      Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text('◆')
          .fontSize(10)
          .fontColor(rank === 5 ? $r('app.color.five_star') : rank === 4 ? $r('app.color.four_star') : $r('app.color.text_secondary'))
        Text(rank === 5 ? $r('app.string.ui_model_intrinsic_item_quality_orange') : rank === 4 ? $r('app.string.ui_model_intrinsic_item_quality_purple') : $r('app.string.ui_model_intrinsic_item_quality_blue'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.countsForRank(isChar, rank).length} 个`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(this.countsForRank(isChar, rank), (entry: ItemCountEntry) => {
          Column({ space: 4 }) {
            Stack({ alignContent: Alignment.BottomEnd }) {
              if (this.iconOfEntry(entry).length > 0) {
                MetaIcon({ category: entry.itemType === '角色' ? 'AvatarIcon' : 'EquipIcon', name: this.iconOfEntry(entry), iconSize: 44 })
                  .borderRadius(22)
                  .clip(true)
              } else {
                Text(entry.name.length > 0 ? entry.name.substring(0, 1) : '★')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .width(44)
                  .height(44)
                  .textAlign(TextAlign.Center)
                  .borderRadius(22)
                  .backgroundColor(entry.rankType === 5 ? $r('app.color.five_star') :
                    (entry.rankType === 4 ? $r('app.color.four_star') : $r('app.color.text_secondary')))
              }
              if (entry.count !== 1) {
                Text(`×${entry.count}`)
                  .fontSize(8)
                  .fontColor(Color.White)
                  .padding({ left: 4, right: 4 })
                  .borderRadius(6)
                  .backgroundColor($r('app.color.overlay_scrim'))
                  .margin({ right: 1, bottom: 1 })
              }
            }
            Text(this.displayItemName(entry.itemId, entry.name, entry.itemType))
              .fontSize(10)
              .fontColor($r('app.color.text_primary'))
              .width(44)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .accessibilityText(this.displayItemName(entry.itemId, entry.name, entry.itemType))
          }
        }, (entry: ItemCountEntry) => `cnt_${entry.itemId}_${entry.rankType}_${entry.name}_${entry.count}_${this.appliedLocaleVersion}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
    }
  }

  private invalidatePoolSelection(): void {
    this.poolSelectionRequest++;
  }

  /** 切换卡池：只读本地归档，不触发任何网络请求。 */
  private async selectPool(type: number): Promise<void> {
    if (!this.pageActive || this.vm.isRefreshing || this.vm.isTransferring) { return; }
    const request: number = ++this.poolSelectionRequest;
    const epoch: number = this.pageEpoch;
    try {
      await this.vm.selectPool(type);
      if (!this.pageActive || epoch !== this.pageEpoch || request !== this.poolSelectionRequest || type !== this.vm.currentPoolType) { return; }
      this.syncAll();
    } catch (e) {
      if (this.pageActive && epoch === this.pageEpoch && request === this.poolSelectionRequest) {
        this.toast(`卡池切换失败：${(e as Error).message}`);
      }
    }
  }
  /** 胡桃云经验分布未接入（占位）：本移植版不提供云统计，不做任何预测。 */
  @Builder
  distributionPanel() {
    Column({ space: 6 }) {
      Text('五星经验分布').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text('本移植版不提供胡桃云统计，经验分布数据源未接入；此处仅保留入口占位，不计算也不联网。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(14)
      .borderRadius($r('app.float.card_radius')).attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }
}
