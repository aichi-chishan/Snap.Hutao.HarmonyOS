/**
 * GachaLogPage.ets（Index 祈愿 Tab 内嵌组件）
 * 祈愿记录：Pivot 五页（对齐 Windows 版 Pivot）：
 *   总览：各池统计卡（大数字抽数/六项统计/橙紫保底进度/五星头像网格）
 *   历史：当前池全部记录列表（橙/紫/蓝分组标题 + LazyForEach 列表）
 *   角色：全池 5 星/4 星角色头像网格
 *   武器：全池 5 星/4 星/3 星武器头像网格
 *   倒计时：各池距保底剩余抽数卡
 * 池切换高亮、刷新按钮/进度展示、手动 URL 兜底；未登录引导。
 * 快照模式：每次装载/刷新/切池后 syncPoolCards() 整体重建 @State poolCards 数组，
 * 池卡片所有展示字段取自同一 PoolCardData 对象，杜绝“部分统计为 0/切池不刷新”。
 */
import { router, LengthMetrics } from '@kit.ArkUI';
import { fileIo, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { GachaLogViewModel } from '../viewmodel/GachaLogViewModel';
import { GachaType } from '../model/GachaType';
import { GachaItem } from '../model/GachaItem';
import { RecentGachaItem } from '../model/RefreshProgress';
import { PoolStatistics, FiveStarDetail } from '../model/GachaStatistics';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { UigfService } from '../service/UigfService';
import { WikiMetaService } from '../service/WikiMetaService';
import { MetaIcon } from '../components/MetaIcon';
import { NavIcon } from '../components/NavIcon';
import { Logger } from '../common/Logger';

const GACHA_TAG: string = 'GachaLogPage';

const ORANGE_GUARANTEE: number = 90;
const PURPLE_GUARANTEE: number = 10;

/** 多池卡片响应式断点（读组件自身宽度，非屏幕宽）：<840 单列 / 840~1199 双列 / >=1200 四列 */
const POOL_SINGLE_COLUMN_VP: number = 840;
const POOL_FOUR_COLUMN_VP: number = 1200;
/** 多池卡片一行最多列数（对齐 Windows 四池同排） */
const MAX_POOL_COLUMNS: number = 4;
/** 同行卡片间距 / 相邻两行间距 */
const POOL_CARD_GAP: number = 10;
/** 行高未知哨兵（实测行高恒 > 0；0 表示尚未测得，按内容自适应） */
const POOL_ROW_HEIGHT_UNKNOWN: number = 0;

/** 池卡内单个五星头像（圆形占位 + 抽数标签） */
class FiveStarPull {
  name: string = '';
  time: string = '';
  lastPull: number = 0;
  isUp: boolean = false;
  /** 角色/武器（决定图标分类 AvatarIcon/EquipIcon） */
  itemType: string = '';
}

/** 池卡片快照（每次同步整体重建，非 @Observed 嵌套追踪） */
class PoolCardData {
  gachaType: number = 0;
  typeName: string = '';
  totalCount: number = 0;
  fiveCount: number = 0;
  fourCount: number = 0;
  sinceLastFive: number = 0;
  sinceLastFour: number = 0;
  avgOrange: number = 0;
  /** UP 平均抽数（对齐 Windows AverageUpOrangePull） */
  avgUpOrange: number = 0;
  maxOrange: number = 0;
  minOrange: number = 0;
  /** 橙/紫/蓝百分比（比例模式） */
  orangePercent: number = 0;
  purplePercent: number = 0;
  bluePercent: number = 0;
  startDate: string = '';
  endDate: string = '';
  isCurrent: boolean = false;
  fivePulls: FiveStarPull[] = [];
  lastFiveName: string = '';
  /** 卡片内容标识（ForEach key + 折叠态查表 + 自然高度测量失效判定） */
  key: string = '';
}

/** 多池卡片多列布局的行内单元（单参 @Builder 传参用，避免多参 Builder 不刷新） */
class PoolCellData {
  /** 该单元对应卡片的内容标识 */
  key: string = '';
  /** 所属行的标识（测量回调用，免去渲染期查表） */
  rowKey: string = '';
  /** 卡片快照 */
  card: PoolCardData = new PoolCardData();
  /** 该单元统一高度（vp）；0 = 尚未测得，按内容自适应 */
  height: number = POOL_ROW_HEIGHT_UNKNOWN;
}

/** 多池卡片多列布局的一行（同行卡片等高：height 取该行内容最高者） */
class PoolRowData {
  /** 行内容标识（含本行全部卡片 key；列数变化/数据变化时整体失效重测） */
  key: string = '';
  /** 本行渲染单元（等宽 + 等高） */
  cells: PoolCellData[] = [];
  /** 本行统一高度（vp）；0 = 尚未测得 */
  height: number = POOL_ROW_HEIGHT_UNKNOWN;
}

/** 池卡内容高度回调包装（ArkTS 禁未类型化对象字面量：以类承载 state/键/行标识） */
class PoolHeightHandler {
  /** 所属组件实例（@State 数组整体替换才触发刷新） */
  state: GachaLogPage | undefined = undefined;
  /** 被测量卡片的内容标识 */
  cardKey: string = '';
  /** 所属行标识 */
  rowKey: string = '';
}

/** 角色/武器分池计数项 */
class ItemCountEntry {
  name: string = '';
  itemType: string = '';
  rankType: number = 0;
  count: number = 0;
}

@Component
export struct GachaLogPage {
  @StorageLink('isLoggedIn') @Watch('onLoginStateChanged') isLoggedIn: boolean = false;
  @StorageLink('currentUid') @Watch('onUidChanged') currentUid: string = '';
  @State vm: GachaLogViewModel = new GachaLogViewModel();
  @State showUrlInput: boolean = false;
  @State urlInput: string = '';
  @State initialized: boolean = false;
  /** 池卡片快照（整体替换驱动渲染） */
  @State poolCards: PoolCardData[] = [];
  /** 宽屏断点（>=840vp 两列，窄屏单列） */
  @State isWide: boolean = false;
  /** 组件自身宽度（vp，onAreaChange 读取；多池列数用它判定，不用屏幕宽） */
  @State areaWidth: number = 0;
  /** 多池卡片多列行快照（整体替换驱动刷新；每行等高） */
  @State poolRows: PoolRowData[] = [];
  /** 当前列数（1 / 2 / 4，最多 4；池数不足时降列） */
  @State poolColumnCount: number = 1;
  /** 已折叠统计详情的池（对齐 Windows Expander 收起；不在表内 = 初始展开） */
  @State poolCollapsed: number[] = [];
  /** 刷新进度快照 */
  @State progressText: string = '';
  @State progressCount: number = 0;
  @State recentItems: RecentGachaItem[] = [];
  @State showProgressDetail: boolean = false;
  /** 统计/比例模式（Windows StatisticsCard 双模式） */
  @State showRatioMode: boolean = false;
  /** Pivot 当前页 */
  @State pivotIndex: number = 0;
  /** 颂愿（千星奇域）模式：切换后页签/卡片/历史只显示颂愿池（对齐 Windows IsBeyondMode） */
  @State beyondMode: boolean = false;
  /** 角色/武器聚合快照 */
  @State charCounts: ItemCountEntry[] = [];
  @State weaponCounts: ItemCountEntry[] = [];
  /** 长列表数据源（LazyForEach） */
  historySource: SimpleDataSource<GachaItem> = new SimpleDataSource<GachaItem>([]);

  aboutToAppear(): void {
    this.vm.onProgressChanged = () => {
      this.syncProgress();
    };
    // 预载角色/武器图标名映射（统计网格真图标）
    WikiMetaService.ensureIconMaps().then(() => {
      this.syncAll();
    });
    this.reloadData();
  }

  aboutToDisappear(): void {
  }

  /** 登录态变化时重新装载（登录成功后自动绑定 UID → 拉取统计） */
  onLoginStateChanged(): void {
    if (this.isLoggedIn) {
      this.reloadData();
    }
  }

  /** UID 变化（自动绑定/切换角色）时重新装载 */
  onUidChanged(): void {
    if (this.currentUid.length > 0) {
      this.reloadData();
    }
  }

  /** 装载数据并同步统计/历史 */
  reloadData(): void {
    this.vm.load(this.currentUid).then(() => {
      this.initialized = true;
      this.syncAll();
    }).catch((e: Error) => {
      this.toast(`加载失败：${e.message}`);
    });
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

  /** 聚合全池角色/武器按名称计数（Pivot：角色/武器页） */
  syncCounts(): void {
    const charMap: Map<string, ItemCountEntry> = new Map<string, ItemCountEntry>();
    const weaponMap: Map<string, ItemCountEntry> = new Map<string, ItemCountEntry>();
    const pools: PoolStatistics[] = this.vm.stats.pools;
    for (let i = 0; i < pools.length; i++) {
      const pool: PoolStatistics = pools[i];
      if (pool.totalCount <= 0) {
        continue;
      }
      // 五星明细按服务端实际 item_type 归桶（常驻/颂愿池混有武器，按池名判断不可靠）
      const details: FiveStarDetail[] = pool.fiveDetails;
      for (let j = 0; j < details.length; j++) {
        const detail: FiveStarDetail = details[j];
        const isChar: boolean = detail.itemType.indexOf('武器') < 0;
        if (isChar) {
          GachaLogPage.accumulate(charMap, detail.name, detail.itemType, 5);
        } else {
          GachaLogPage.accumulate(weaponMap, detail.name, detail.itemType, 5);
        }
      }
    }
    // 加上当前池全部四星/三星（角色页补充四星角色；武器页补充四星/三星武器）
    const allItems: GachaItem[] = this.vm.items;
    for (let i = 0; i < allItems.length; i++) {
      const item: GachaItem = allItems[i];
      if (item.rankType < 4) {
        continue;
      }
      const isChar: boolean = item.itemType.indexOf('角色') >= 0;
      if (isChar) {
        GachaLogPage.accumulate(charMap, item.name, item.itemType, item.rankType);
      } else {
        GachaLogPage.accumulate(weaponMap, item.name, item.itemType, item.rankType);
      }
    }
    this.charCounts = GachaLogPage.mapToSorted(charMap);
    this.weaponCounts = GachaLogPage.mapToSorted(weaponMap);
  }

  private static accumulate(map: Map<string, ItemCountEntry>, name: string, itemType: string, rank: number): void {
    if (name.length === 0) {
      return;
    }
    const key: string = `${rank}_${name}`;
    const existing: ItemCountEntry | undefined = map.get(key);
    if (existing !== undefined) {
      existing.count++;
    } else {
      const e: ItemCountEntry = new ItemCountEntry();
      e.name = name;
      e.itemType = itemType;
      e.rankType = rank;
      e.count = 1;
      map.set(key, e);
    }
  }

  private static mapToSorted(map: Map<string, ItemCountEntry>): ItemCountEntry[] {
    const list: ItemCountEntry[] = [];
    map.forEach((v: ItemCountEntry) => {
      list.push(v);
    });
    // 星级降序 → 名称拼音序（近似：按码点）
    list.sort((a: ItemCountEntry, b: ItemCountEntry) => {
      if (a.rankType !== b.rankType) {
        return b.rankType - a.rankType;
      }
      return a.name.localeCompare(b.name);
    });
    return list;
  }

  /** 按 vm.stats.pools 整体重建池卡片快照：每个字段同源，杜绝匹配不到/字段错配 */
  syncPoolCards(): void {
    const cards: PoolCardData[] = [];
    const pools: PoolStatistics[] = this.vm.stats.pools;
    for (let i = 0; i < pools.length; i++) {
      const pool: PoolStatistics = pools[i];
      // 无数据池不展示卡片（宽屏多列展示有数据的池，同电脑版）
      if (pool.totalCount <= 0) {
        continue;
      }
      // 颂愿池仅在颂愿模式展示，常规池仅在常规模式展示
      if (GachaType.isBeyond(pool.gachaType) !== this.beyondMode) {
        continue;
      }
      const card: PoolCardData = new PoolCardData();
      card.gachaType = pool.gachaType;
      card.typeName = pool.typeName;
      card.totalCount = pool.totalCount;
      card.fiveCount = pool.fiveStarCount;
      card.fourCount = pool.fourStarCount;
      card.sinceLastFive = pool.sinceLastFive;
      card.sinceLastFour = pool.sinceLastFour;
      card.avgOrange = pool.averageOrangePull;
      card.maxOrange = pool.maxOrangePull;
      card.minOrange = pool.minOrangePull;
      card.startDate = pool.startDate;
      card.endDate = pool.endDate;
      card.lastFiveName = pool.lastFiveName;
      card.isCurrent = pool.gachaType === this.vm.currentPoolType;
      // 橙/紫/蓝占比（比例模式，对齐 Windows TotalOrangePercent 等）
      if (pool.totalCount > 0) {
        card.orangePercent = pool.fiveStarCount * 100 / pool.totalCount;
        card.purplePercent = pool.fourStarCount * 100 / pool.totalCount;
        const blue: number = pool.totalCount - pool.fiveStarCount - pool.fourStarCount;
        card.bluePercent = blue * 100 / pool.totalCount;
      }
      // UP 平均抽数（对齐 Windows AverageUpOrangePull：UP 条目 lastPull 的平均；无 UP 记录 = 五星平均兜底）
      let upSum: number = 0;
      let upCount: number = 0;
      for (let j = 0; j < pool.fiveDetails.length; j++) {
        const src: FiveStarDetail = pool.fiveDetails[j];
        if (src.isUp && src.lastPull > 0) {
          upSum += src.lastPull;
          upCount++;
        }
      }
      card.avgUpOrange = upCount > 0 ? Math.round(upSum / upCount * 100) / 100 : card.avgOrange;
      for (let j = 0; j < pool.fiveDetails.length; j++) {
        const src: FiveStarDetail = pool.fiveDetails[j];
        const pull: FiveStarPull = new FiveStarPull();
        pull.name = src.name;
        pull.time = src.time;
        pull.lastPull = src.lastPull;
        pull.isUp = src.isUp;
        pull.itemType = src.itemType;
        card.fivePulls.push(pull);
      }
      card.key = GachaLogPage.cardKey(card);
      cards.push(card);
      Logger.info(GACHA_TAG, `card ${pool.typeName}: total=${card.totalCount} ` +
        `5star=${card.fiveCount} 4star=${card.fourCount} since=${card.sinceLastFive} ` +
        `avg=${card.avgOrange} min=${card.minOrange} max=${card.maxOrange} current=${card.isCurrent}`);
    }
    this.poolCards = cards;
    this.rebuildPoolRows();
    Logger.info(GACHA_TAG, `syncPoolCards current=${this.vm.currentPoolType} cards=${cards.length}`);
  }

  /** 卡片内容标识（字段即渲染内容：任一变化都需重建测量缓存） */
  private static cardKey(card: PoolCardData): string {
    return `${card.gachaType}_${card.typeName}_${card.totalCount}_${card.fiveCount}_${card.fourCount}_` +
      `${card.sinceLastFive}_${card.sinceLastFour}_${card.startDate}_${card.endDate}_${card.avgOrange}_` +
      `${card.avgUpOrange}_${card.maxOrange}_${card.minOrange}_${card.fivePulls.length}`;
  }

  /** 按当前组件宽度与池数决定列数：<840 单列 / 840~1199 双列 / >=1200 最多四列（池少则降列） */
  private poolColumnsFor(widthVp: number): number {
    if (widthVp < POOL_SINGLE_COLUMN_VP) {
      return 1;
    }
    const byWidth: number = widthVp >= POOL_FOUR_COLUMN_VP ? MAX_POOL_COLUMNS : 2;
    const byPoolCount: number = Math.max(1, this.poolCards.length);
    return Math.min(byWidth, byPoolCount);
  }

  /**
   * 依据 poolCards + 当前列数重建多列行快照。
   * 每行整体替换（新对象），并在列数或行内容变化时清空测量高度，触发重测 → 同行卡片等高。
   */
  rebuildPoolRows(): void {
    // 旧行的测量回调随旧组件销毁，清掉缓存防无界增长（已挂载回调持有对象引用，不受影响）
    this.poolHeightHandlers.clear();
    const columns: number = this.poolColumnsFor(this.areaWidth);
    const rows: PoolRowData[] = [];
    for (let i = 0; i < this.poolCards.length; i += columns) {
      const row: PoolRowData = new PoolRowData();
      const end: number = Math.min(i + columns, this.poolCards.length);
      let key: string = `c${columns}`;
      for (let j = i; j < end; j++) {
        const card: PoolCardData = this.poolCards[j];
        const cell: PoolCellData = new PoolCellData();
        cell.key = card.key;
        cell.card = card;
        cell.height = POOL_ROW_HEIGHT_UNKNOWN;
        row.cells.push(cell);
        key += `|${card.key}`;
      }
      row.key = key;
      for (let j = 0; j < row.cells.length; j++) {
        row.cells[j].rowKey = key;
      }
      // 内容标识未变的行沿用已测高度，并把该高度下发到各单元（避免重复测量导致的闪动）
      row.height = GachaLogPage.findRowHeight(this.poolRows, key);
      for (let j = 0; j < row.cells.length; j++) {
        row.cells[j].height = row.height;
      }
      rows.push(row);
    }
    this.poolColumnCount = columns;
    this.poolRows = rows;
  }

  private static findRowHeight(rows: PoolRowData[], key: string): number {
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].key === key) {
        return rows[i].height;
      }
    }
    return POOL_ROW_HEIGHT_UNKNOWN;
  }

  /** 测量缓存：行+卡标识 → 该卡在自然高度下的实测值（防止链式刷新，见 onPoolCellArea） */
  private poolHeightCache: Map<string, number> = new Map<string, number>();

  private static heightHandlerKey(rowKey: string, cardKey: string): string {
    return `${rowKey}#${cardKey}`;
  }

  /** 隐藏测量副本的高度回调（回调包装缓存，避免每次渲染重建闭包导致无谓重测） */
  private poolHeightHandlers: Map<string, (area: Area) => void> = new Map<string, (area: Area) => void>();

  private heightHandlerFor(cell: PoolCellData): (area: Area) => void {
    const id: string = GachaLogPage.heightHandlerKey(cell.rowKey, cell.key);
    const cached: ((area: Area) => void) | undefined = this.poolHeightHandlers.get(id);
    if (cached !== undefined) {
      return cached;
    }
    const handler: PoolHeightHandler = new PoolHeightHandler();
    handler.state = this;
    handler.cardKey = cell.key;
    handler.rowKey = cell.rowKey;
    const cb: (area: Area) => void = (area: Area) => {
      GachaLogPage.onPoolCellArea(handler, area);
    };
    this.poolHeightHandlers.set(id, cb);
    return cb;
  }

  /**
   * 隐藏测量副本测得“卡片在自然高度下的高度”后，把行高提升到该行最大值。
   * 隐藏副本恒为自适应高度，因此可见卡片被拉伸不会反向影响测量值 → 不产生刷新环。
   */
  private static onPoolCellArea(handler: PoolHeightHandler, area: Area): void {
    const state: GachaLogPage | undefined = handler.state;
    if (state === undefined) {
      return;
    }
    const measured: number = Number(area.height);
    if (!(measured > 0)) {
      return;
    }
    const cacheId: string = `${handler.rowKey}#${handler.cardKey}`;
    const known: number | undefined = state.poolHeightCache.get(cacheId);
    if (known !== undefined && Math.abs(known - measured) < 0.5) {
      return;
    }
    state.poolHeightCache.set(cacheId, measured);
    const rows: PoolRowData[] = state.poolRows;
    let hit: number = -1;
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].key === handler.rowKey) {
        hit = i;
        break;
      }
    }
    if (hit < 0) {
      return;
    }
    const current: number = rows[hit].height;
    if (current > 0 && current >= measured - 0.5) {
      return;
    }
    // 整体替换 @State 数组（行与单元都用新对象），驱动同行卡片统一改高
    const next: PoolRowData[] = [];
    for (let i = 0; i < rows.length; i++) {
      const copy: PoolRowData = new PoolRowData();
      copy.key = rows[i].key;
      copy.height = i === hit ? measured : rows[i].height;
      const cells: PoolCellData[] = [];
      for (let j = 0; j < rows[i].cells.length; j++) {
        const src: PoolCellData = rows[i].cells[j];
        const cell: PoolCellData = new PoolCellData();
        cell.key = src.key;
        cell.rowKey = src.rowKey;
        cell.card = src.card;
        cell.height = copy.height;
        cells.push(cell);
      }
      copy.cells = cells;
      next.push(copy);
    }
    state.poolRows = next;
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
    // 折叠会改变卡片自然高度：清测量缓存并重建行，保证折叠后同行仍等高（不裁剪内容）
    this.poolHeightCache.clear();
    this.rebuildPoolRows();
  }

  /** 组件宽度变化：同步宽屏断点与多池列数（列数变化时重测行高） */
  onPoolAreaChange(widthVp: number): void {
    this.isWide = widthVp >= POOL_SINGLE_COLUMN_VP;
    if (Math.abs(this.areaWidth - widthVp) < 0.5) {
      return;
    }
    this.areaWidth = widthVp;
    const columns: number = this.poolColumnsFor(widthVp);
    if (columns !== this.poolColumnCount) {
      this.poolHeightCache.clear();
      this.rebuildPoolRows();
    }
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  /** 条目名 → 元数据图标名（祈愿页真图标替换首字占位） */
  iconOfEntry(entry: ItemCountEntry): string {
    if (entry.itemType === '角色') {
      return WikiMetaService.iconOfAvatarName(GachaLogPage.cleanName(entry.name));
    }
    return WikiMetaService.iconOfWeaponName(GachaLogPage.cleanName(entry.name));
  }

  /** 角色名 → 图标名（命名规范化：☆/★/◆ 前缀 + 空格清洗） */
  iconOfName(name: string): string {
    return WikiMetaService.iconOfAvatarName(GachaLogPage.cleanName(name));
  }

  /** 武器名 → 图标名（命名规范化） */
  weaponIconOfName(name: string): string {
    return WikiMetaService.iconOfWeaponName(GachaLogPage.cleanName(name));
  }

  /** 头像首字（无名字回退 ★） */
  avatarInitial(pull: FiveStarPull): string {
    if (pull.name.length === 0) {
      return '★';
    }
    return pull.name.substring(0, 1);
  }

  /** 出金记录 → 图标名（常驻池混有武器，池类型判定不可靠：先按 itemType，未命中双表回退） */
  iconOfPull(pull: FiveStarPull): string {
    const clean: string = GachaLogPage.cleanName(pull.name);
    if (pull.itemType === '武器') {
      return WikiMetaService.iconOfWeaponName(clean);
    }
    const avatar: string = WikiMetaService.iconOfAvatarName(clean);
    if (avatar.length > 0) {
      return avatar;
    }
    return WikiMetaService.iconOfWeaponName(clean);
  }

  /** 出金头像分类（按实际解析出的图标名回推；武器图未命中时保持 AvatarIcon 让回退头像兜底） */
  pullCategory(pull: FiveStarPull): string {
    const clean: string = GachaLogPage.cleanName(pull.name);
    if (pull.itemType === '武器') {
      return 'EquipIcon';
    }
    const avatar: string = WikiMetaService.iconOfAvatarName(clean);
    if (avatar.length > 0) {
      return 'AvatarIcon';
    }
    return WikiMetaService.iconOfWeaponName(clean).length > 0 ? 'EquipIcon' : 'AvatarIcon';
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
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'GachaLog', iconSize: 60 })
      Text('需登录后查看祈愿记录')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('登录并绑定 UID 后，可一键拉取全量抽卡历史')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Button('去登录')
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          router.pushUrl({ url: 'pages/LoginPage' });
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  poolTabs() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.beyondMode ? GachaType.BEYOND_ORDER : GachaType.QUERY_ORDER, (type: number) => {
          Text(GachaType.nameOf(type))
            .fontSize(12)
            .fontColor(this.vm.currentPoolType === type ? Color.White : $r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor(this.vm.currentPoolType === type ? $r('app.color.app_primary') : $r('app.color.card_background'))
            .border({ width: 1, color: $r('app.color.divider') })
            .constraintSize({ minWidth: 56 })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.vm.selectPool(type).then(() => {
                this.syncAll();
              });
            })
        }, (type: number) => `${type}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height(40)
  }

  /** 颂愿（千星奇域）模式切换 chip（对齐 Windows SwitchToBeyondGachaMode） */
  @Builder
  beyondToggleChip() {
    Text(this.beyondMode ? '颂愿·开' : '颂愿')
      .fontSize(12)
      .fontWeight(this.beyondMode ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.beyondMode ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.beyondMode ? $r('app.color.app_primary') : $r('app.color.card_background'))
      .border({
        width: 1,
        color: this.beyondMode ? $r('app.color.app_primary') : $r('app.color.divider')
      })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.toggleBeyondMode();
      })
  }

  /** 切换颂愿模式：换默认选中池并重建快照 */
  toggleBeyondMode(): void {
    this.beyondMode = !this.beyondMode;
    const target: number = this.beyondMode ? GachaType.UGC_STANDARD : GachaType.AVATAR_EVENT;
    this.vm.selectPool(target).then(() => {
      this.syncAll();
    });
  }

  @Builder
  statCell(label: string, value: string, color: Resource) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  @Builder
  pillBadge(text: string, bg: Resource) {
    Text(text)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(Color.White)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(9)
      .backgroundColor(bg)
  }

  /** 五星头像网格：星级色圆形占位 + 右下角抽数标签（完整展示，不做截断） */
  @Builder
  avatarGrid(pulls: FiveStarPull[]) {
    if (pulls.length === 0) {
      Text('暂无五星出金记录')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    } else {
      // 对齐 Windows StatisticsCard：OrangeGrid 完整绑定 GridView，不 Take、不加“+N 更多”
      // Windows 侧仅 ToolTip（悬停显示时间），无点击弹窗，故此处不加 onClick/hover
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(pulls, (pull: FiveStarPull, index: number) => {
          Stack({ alignContent: Alignment.BottomEnd }) {
            if (this.iconOfPull(pull).length > 0) {
              MetaIcon({ category: this.pullCategory(pull), name: this.iconOfPull(pull), iconSize: 40 })
                .borderRadius(20)
                .clip(true)
            } else {
              Text(this.avatarInitial(pull))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .width(40)
                .height(40)
                .textAlign(TextAlign.Center)
                .borderRadius(20)
                .backgroundColor($r('app.color.five_star'))
            }
            Text(`${pull.lastPull}`)
              .fontSize(8)
              .fontColor(Color.White)
              .padding({ left: 4, right: 4 })
              .borderRadius(6)
              .backgroundColor('#99000000')
              .margin({ right: 1, bottom: 1 })
          }
          .width(40)
          .height(42)
          .borderRadius(10)
        }, (pull: FiveStarPull, index: number) => `${pull.name}_${pull.time}_${pull.lastPull}_${index}`)
      }
      .width('100%')
    }
  }

  /**
   * 单张池卡片：对齐电脑版 Windows StatisticsCard.xaml
   *   外框 Grid（AcrylicGridCardStyle）
   *   ├─ Expander「卡头 + 统计详情」：卡头常显（池名 + 抽数 + Chevron），详情可折叠
   *   └─ SwitchPresenter「五星列表/网格」：位于 Expander 之外 → 始终完整显示
   * Chevron 折叠状态每卡独立（对齐 WinUI Expander 内建开合），初始展开。
   */
  @Builder
  poolCard(card: PoolCardData) {
    Column({ space: 8 }) {
      // 卡头：池名 + 五星徽章 + 抽数摘要（折叠时可见）+ Chevron 开合
      Row({ space: 6 }) {
        Text(card.typeName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('★')
          .fontSize(10)
          .fontColor(Color.White)
          .width(20)
          .height(20)
          .textAlign(TextAlign.Center)
          .borderRadius(6)
          .backgroundColor($r('app.color.five_star'))
        // 仅在折叠时于头部显示总抽数（对齐 Windows：Expander 收起后头部保留 FormattedTotalCount），
        // 展开态由详情区大数字承担，避免同一数值重复出现
        if (this.isPoolCollapsed(card)) {
          Text(`${card.totalCount} 抽`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }
        Text('›')
          .fontSize(20)
          .fontColor($r('app.color.text_secondary'))
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(12)
          .rotate({ angle: this.isPoolCollapsed(card) ? 0 : 90 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .borderRadius(8)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.togglePoolDetail(card);
      })

      // Expander 主体：统计详情（折叠时仅隐藏此段，五星区不受影响）
      if (!this.isPoolCollapsed(card)) {
        // 大数字抽数（同电脑版 2008 抽）
        Row() {
          Text(`${card.totalCount}`)
            .fontSize(38)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('抽')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4, bottom: 6 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)

        // 距上个五星/四星 徽章
        Row({ space: 8 }) {
          this.pillBadge(`距上个五星 ${card.sinceLastFive}`, $r('app.color.danger'))
          this.pillBadge(`距上个四星 ${card.sinceLastFour}`, $r('app.color.four_star'))
        }
        .width('100%')

        // 日期范围
        if (card.startDate.length > 0) {
          Text(`${card.startDate} - ${card.endDate}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }

        // 橙/紫保底进度条（对齐 Windows StatisticsCard CardProgressBar）
        Column({ space: 2 }) {
          Text(`累计五星 ${card.fiveCount} 个 · 距保底 ${Math.max(0, ORANGE_GUARANTEE - card.sinceLastFive)} 抽`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Progress({
            value: Math.min(card.sinceLastFive, ORANGE_GUARANTEE),
            total: ORANGE_GUARANTEE,
            type: ProgressType.Linear,
          })
            .width('100%')
            .color($r('app.color.five_star'))
            .style({ strokeWidth: 6 })
          Text(`累计四星 ${card.fourCount} 个 · 距保底 ${Math.max(0, PURPLE_GUARANTEE - card.sinceLastFour)} 抽`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ top: 4 })
          Progress({
            value: Math.min(card.sinceLastFour, PURPLE_GUARANTEE),
            total: PURPLE_GUARANTEE,
            type: ProgressType.Linear,
          })
            .width('100%')
            .color($r('app.color.four_star'))
            .style({ strokeWidth: 6 })
        }
        .width('100%')

        // Windows StatisticsCard：统计/比例 双模式（切换 chip）
        Row({ space: 8 }) {
          this.statModeChip('统计', false)
          this.statModeChip('比例', true)
        }
        .width('100%')
        .padding({ top: 2, bottom: 4 })

        if (!this.showRatioMode) {
          // 统计模式：五星平均/UP 平均/最非/最欧（对齐 Windows）
          Row({ space: 12 }) {
            this.statCell('五星平均', `${card.avgOrange} 抽`, $r('app.color.app_primary'))
            this.statCell('UP 平均', `${card.avgUpOrange} 抽`, $r('app.color.app_primary'))
            this.statCell('最非', `${card.maxOrange} 抽`, $r('app.color.danger'))
            this.statCell('最欧', `${card.minOrange} 抽`, $r('app.color.success'))
          }
          .width('100%')
        } else {
          // 比例模式：橙/紫/蓝占比（对齐 Windows TotalOrangePercent 等）
          Row({ space: 12 }) {
            this.statCell('五星', `${card.orangePercent.toFixed(2)}%`, $r('app.color.five_star'))
            this.statCell('四星', `${card.purplePercent.toFixed(2)}%`, $r('app.color.four_star'))
            this.statCell('三星', `${card.bluePercent.toFixed(2)}%`, $r('app.color.text_secondary'))
            this.statCell('合计', `${card.totalCount}`, $r('app.color.app_primary'))
          }
          .width('100%')
        }
      }

      Divider()
        .width('100%')
        .color($r('app.color.divider'))

      // 五星头像网格：Expander 之外，始终完整显示（每个头像带抽数标签）
      this.avatarGrid(card.fivePulls)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .border({
      width: card.isCurrent && !this.isWide ? 2 : 1,
      color: card.isCurrent && !this.isWide ? $r('app.color.app_primary') : $r('app.color.divider'),
    })
  }

  /** 统计/比例 模式切换 chip（Windows StatisticsCard 顶部双按钮） */
  @Builder
  statModeChip(label: string, isRatio: boolean) {
    Text(label)
      .fontSize(11)
      .fontColor(this.showRatioMode === isRatio ? Color.White : $r('app.color.text_secondary'))
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(this.showRatioMode === isRatio ? $r('app.color.app_primary') : $r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider') })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.showRatioMode = isRatio;
      })
  }

  /** 多池卡片区：按组件自身宽度分列（<840 单列 / 840~1199 双列 / >=1200 最多四列），同行等高 */
  @Builder
  poolCardsArea() {
    if (this.poolCards.length === 0) {
      Text('暂无池数据，点击右上角「刷新」拉取')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .textAlign(TextAlign.Center)
    } else {
      Column({ space: POOL_CARD_GAP }) {
        ForEach(this.poolRows, (row: PoolRowData) => {
          this.poolCardRow(row);
        }, (row: PoolRowData) => row.key)
      }
      .width('100%')
    }
  }

  /** 一行池卡：外层 Row 高度 = 本行内容最高者，卡片按该高度拉伸，禁止固定/裁剪 */
  @Builder
  poolCardRow(row: PoolRowData) {
    Row({ space: POOL_CARD_GAP }) {
      ForEach(row.cells, (cell: PoolCellData) => {
        this.poolRowCell(cell);
      }, (cell: PoolCellData) => cell.key)
      // 末行不足列数时补齐占位，保证同行卡片宽度一致（与 Windows 等宽卡片一致）
      ForEach(GachaLogPage.gapSlots(row.cells.length, this.poolColumnCount), (slotIndex: number) => {
        this.poolRowGap();
      }, (slotIndex: number) => `gap_${row.key}_${slotIndex}`)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .height(row.height > 0 ? row.height : 'auto')
  }

  /** 占位槽位（ForEach 数据源：只用索引，卡片内容不参与刷新）。补位上限=当前列数，
   *  而非固定四列：否则双列/按池数降列时，末行卡片会被占位挤成 1/4 宽，与上方整行不对齐。 */
  private static gapSlots(cardCount: number, columns: number): number[] {
    const slots: number[] = [];
    for (let i = cardCount; i < columns; i++) {
      slots.push(i);
    }
    return slots;
  }

  @Builder
  poolRowGap() {
    Column()
      .layoutWeight(1)
      .height(1)
  }

  /**
   * 行内单个单元（单参 @Builder，保证动态刷新）：可见卡片按精确行高拉伸；
   * 行高未知时叠加一份不可交互、恒定自适应高度的测量副本上报本行统一高度。
   * 高度用明确数值（cell.height）而非百分比，避免 auto 父级 + 百分比子级的循环依赖；
   * 行高 0 时按内容自适应（首帧），测得后即用数值。
   * 测量副本必须参与布局（故用 opacity(0) 而非 Visibility.None）才能触发 onAreaChange；
   * 它恒为自然高度，因此可见卡片被拉伸不会反向改变测量值 → 不产生刷新环；
   * 行高已知后不再渲染副本，避免五星头像节点翻倍（数据/列数变化会重新测量）。
   */
  @Builder
  poolRowCell(cell: PoolCellData) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.poolCard(cell.card)
      }
      .width('100%')
      .height(cell.height > 0 ? cell.height : 'auto')

      if (cell.height <= 0) {
        Column() {
          this.poolCard(cell.card)
        }
        .width('100%')
        .opacity(0)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
        .onAreaChange(this.heightHandlerFor(cell))
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  itemRow(item: GachaItem) {
    Row({ space: 10 }) {
      // 真实素材图标：角色→AvatarIcon 武器→EquipIcon（本地元数据映射；未命中回退星级占位）
      if (item.itemType === '角色') {
        if (this.iconOfName(item.name).length > 0) {
          MetaIcon({ category: 'AvatarIcon', name: this.iconOfName(item.name), iconSize: 36 })
            .borderRadius(18)
            .clip(true)
        } else {
          this.starPlaceholder(item.rankType)
        }
      } else if (item.itemType === '武器') {
        if (this.weaponIconOfName(item.name).length > 0) {
          MetaIcon({ category: 'EquipIcon', name: this.weaponIconOfName(item.name), iconSize: 36 })
            .borderRadius(18)
            .clip(true)
        } else {
          this.starPlaceholder(item.rankType)
        }
      } else {
        this.starPlaceholder(item.rankType)
      }
      Column({ space: 2 }) {
        Text(item.name)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.itemType)
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
    const poolName: string = GachaType.nameOf(this.vm.currentPoolType);
    this.getUIContext().getPromptAction().showDialog({
      title: item.name,
      message:
        `类型：${item.itemType}\n` +
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
      Row() {
        Text('抽卡历史')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Button('剪贴板')
          .fontSize(11)
          .height(26)
          .margin({ right: 4 })
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.importFromClipboard();
          })
        Button('UIGF')
          .fontSize(11)
          .height(26)
          .margin({ right: 4 })
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.uigfImport();
          })
        Button('导出')
          .fontSize(11)
          .height(26)
          .margin({ right: 4 })
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.uigfExport();
          })
        Button('手动 URL')
          .fontSize(11)
          .height(26)
          .backgroundColor($r('app.color.app_primary_bg'))
          .fontColor($r('app.color.app_primary'))
          .onClick(() => {
            this.showUrlInput = !this.showUrlInput;
          })
      }
      .width('100%')
      if (this.vm.items.length === 0) {
        Text('暂无记录，点击「刷新」拉取')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 20, bottom: 20 })
          .textAlign(TextAlign.Center)
      }
      List({ space: 0 }) {
        LazyForEach(this.historySource, (item: GachaItem) => {
          ListItem() {
            this.itemRow(item)
          }
        }, (item: GachaItem) => {
          if (item.gachaId.length > 0) {
            return item.gachaId;
          }
          return `${item.time}_${item.name}`;
        })
      }
      .width('100%')
      .height(420)
      .cachedCount(5)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
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
        Text(this.showProgressDetail ? '收起 ‹' : '详情 ›')
          .fontSize(11)
          .fontColor($r('app.color.app_primary'))
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
          Text(`当前卡池：${this.vm.progress.currentPoolName.length > 0 ? this.vm.progress.currentPoolName : '--'}`)
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          // 新拉取记录头像流（对齐 Windows：实时滚动物品/角色头像，星级描边 + 计数角标）
          if (this.recentItems.length > 0) {
            Text('最新抽到')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_primary'))
              .width('100%')
              .margin({ top: 2 })
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.recentItems, (it: RecentGachaItem, idx: number) => {
                  Column({ space: 2 }) {
                    Stack({ alignContent: Alignment.BottomEnd }) {
                      MetaIcon({
                        category: it.itemType === '武器' ? 'EquipIcon' : 'AvatarIcon',
                        name: WikiMetaService.iconOfItemName(it.name, it.itemType),
                        iconSize: 40,
                      })
                      if (it.count > 1) {
                        Text(`x${it.count}`)
                          .fontSize(9)
                          .fontColor(Color.White)
                          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                          .borderRadius(6)
                          .backgroundColor('#B3000000')
                      }
                    }
                    .width(44)
                    .height(44)
                    .borderRadius(10)
                    .border({
                      width: it.rank >= 5 ? 2 : 1,
                      color: it.rank >= 5 ? $r('app.color.five_star') :
                        (it.rank === 4 ? $r('app.color.four_star') : $r('app.color.divider')),
                    })
                  }
                }, (it: RecentGachaItem, idx: number) => `rn_${idx}_${it.name}`)
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
        .backgroundColor($r('app.color.card_background'))
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor($r('app.color.app_primary_bg'))
  }

  /** 弹窗展示拉取进度详情（保留：供外部入口调用时显示静态摘要） */
  showProgressDetailDialog(): void {
    this.getUIContext().getPromptAction().showDialog({
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
    try {
      const data: string = await pasteboard.getSystemPasteboard().getData().then((pd: pasteboard.PasteData) => {
        return pd.getPrimaryText();
      });
      if (data.length === 0 || !data.includes('authkey=')) {
        this.toast('剪贴板中没有检测到祈愿链接（需包含 authkey）');
        return;
      }
      this.urlInput = data;
      this.showUrlInput = true;
      this.toast('已从剪贴板读取链接，点击「导入」开始拉取');
    } catch (e) {
      this.toast(`读取剪贴板失败：${(e as Error).message}`);
    }
  }

  /** 选择文件导入 UIGF（v4.2 / v4.0 / v3.x） */
  async uigfImport(): Promise<void> {
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['.json'];
      const uris: string[] = await docPicker.select(opts);
      if (uris.length === 0) {
        return;
      }
      const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
      try {
        const stat: fileIo.Stat = fileIo.statSync(file.fd);
        const buf: ArrayBuffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buf);
        const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
        const result = await UigfService.getInstance().importFromText(text);
        this.toast(result.ok ? result.message : `导入失败：${result.message}`);
        if (result.ok && result.inserted > 0) {
          await this.vm.load(this.vm.currentUid.length > 0 ? this.vm.currentUid : result.uid);
          this.syncAll();
        }
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      this.toast(`导入失败：${(e as Error).message}`);
    }
  }

  /** 导出全部祈愿数据为 UIGF v4.2 文件（含千星奇域） */
  async uigfExport(): Promise<void> {
    try {
      const json: string = await UigfService.getInstance().buildExportJson();
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      opts.newFileNames = ['uigf_gacha_export.json'];
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
      this.toast('导出成功（UIGF v4.2）');
    } catch (e) {
      this.toast(`导出失败：${(e as Error).message}`);
    }
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
        Button('取消')
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_background'))
          .fontColor($r('app.color.text_primary'))
          .fontSize(14)
          .onClick(() => {
            this.showUrlInput = false;
          })
        Button('导入')
          .layoutWeight(1)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .fontSize(14)
          .onClick(() => {
            this.vm.importByUrl(this.urlInput).then((ok: boolean) => {
              this.syncAll();
              this.toast(ok ? `导入完成：${this.vm.message}` : `导入失败：${this.vm.message}`);
              if (ok) {
                this.showUrlInput = false;
              }
            });
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
  }

  build() {
    Column() {
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else {
        Row() {
          Text('祈愿记录')
            .fontSize($r('app.float.page_title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Blank()
          if (this.vm.currentUid.length > 0) {
            Text(this.vm.currentUid)
              .fontSize(12)
              .fontColor($r('app.color.app_primary'))
              .margin({ right: 10 })
          }
          Button('刷新')
            .fontSize(13)
            .height(32)
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .onClick(() => {
              if (this.vm.currentUid.length === 0) {
                this.toast('请先在「账号与数据」选择默认 UID');
                return;
              }
              this.vm.refresh().then((ok: boolean) => {
                this.syncAll();
                this.toast(ok ? this.vm.message : this.vm.message);
              });
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        // Pivot 五个页签（总览/历史/角色/武器/倒计时）+ 颂愿模式切换
        Row({ space: 6 }) {
          this.pivotTab(0, '总览')
          Blank()
          this.beyondToggleChip()
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column({ space: 10 }) {
            if (this.vm.isRefreshing) {
              this.progressPanel()
            }
            if (this.showUrlInput) {
              this.urlInputPanel()
            }

            // 池切换工具行（仅手机/窄屏；PC 宽屏用 Pivot 总览直接展示所有池，对齐 Windows 无此栏）
            if (!this.isWide) {
              this.poolTabs()
            }

            if (this.pivotIndex === 0) {
              this.poolCardsArea()
            } else if (this.pivotIndex === 1) {
              this.recentSection()
            } else if (this.pivotIndex === 2) {
              this.avatarSection(this.charCounts, true)
            } else if (this.pivotIndex === 3) {
              this.avatarSection(this.weaponCounts, false)
            } else {
              this.countdownSection()
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
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.onPoolAreaChange(Number(newValue.width));
    })
  }

  /** Pivot 页签按钮 */
  @Builder
  pivotTab(index: number, label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.pivotIndex === index ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.pivotIndex === index ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.pivotIndex === index ? $r('app.color.app_primary') : $r('app.color.card_background'))
      .border({ width: 1, color: this.pivotIndex === index ? $r('app.color.app_primary') : $r('app.color.divider') })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.pivotIndex = index;
        this.syncAll();
      })
  }

  /** 角色/武器头像网格区（按星级分组） */
  @Builder
  avatarSection(entries: ItemCountEntry[], isChar: boolean) {
    if (entries.length === 0) {
      Text('暂无数据，点击右上角「刷新」拉取')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .textAlign(TextAlign.Center)
    } else {
      Column({ space: 10 }) {
        if (entries.filter((e: ItemCountEntry) => e.rankType === 5).length > 0) {
          this.rankGroup(entries.filter((e: ItemCountEntry) => e.rankType === 5), '五星', $r('app.color.five_star'))
        }
        if (entries.filter((e: ItemCountEntry) => e.rankType === 4).length > 0) {
          this.rankGroup(entries.filter((e: ItemCountEntry) => e.rankType === 4), '四星', $r('app.color.four_star'))
        }
        if (!isChar && entries.filter((e: ItemCountEntry) => e.rankType === 3).length > 0) {
          this.rankGroup(entries.filter((e: ItemCountEntry) => e.rankType === 3), '三星', $r('app.color.text_secondary'))
        }
      }
      .width('100%')
    }
  }

  @Builder
  rankGroup(entries: ItemCountEntry[], title: string, color: Resource) {
    if (entries.length > 0) {
      Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text('◆')
          .fontSize(10)
          .fontColor(color)
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${entries.length} 个`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(entries, (entry: ItemCountEntry) => {
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
              if (entry.count > 1) {
                Text(`×${entry.count}`)
                  .fontSize(8)
                  .fontColor(Color.White)
                  .padding({ left: 4, right: 4 })
                  .borderRadius(6)
                  .backgroundColor('#99000000')
                  .margin({ right: 1, bottom: 1 })
              }
            }
            Text(entry.name.length > 5 ? `${entry.name.substring(0, 5)}…` : entry.name)
              .fontSize(10)
              .fontColor($r('app.color.text_primary'))
              .width(44)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }, (entry: ItemCountEntry) => `cnt_${entry.rankType}_${entry.name}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
    }
  }

  /** 单抽五星概率（pity 为第 pity 抽，1 起）：74 前基准 0.6%，74 起软保底线性抬升至 90 硬保底 */
  private static pullFiveRate(pity: number): number {
    if (pity >= ORANGE_GUARANTEE) {
      return 1;
    }
    if (pity >= 74) {
      return Math.min(1, 0.06 + (pity - 73) * 0.06);
    }
    return 0.006;
  }

  /** 当前垫 c 抽时，接下来 N 抽内至少出一个五星的概率（0-1） */
  private static predictFive(c: number, n: number): number {
    let survive: number = 1;
    const end: number = Math.min(c + n, ORANGE_GUARANTEE);
    for (let i: number = c + 1; i <= end; i++) {
      survive *= (1 - GachaLogPage.pullFiveRate(i));
    }
    return 1 - survive;
  }

  /** 抽卡预测面板：当前池接下来 N 抽出五星概率（对齐 Windows PullPredictionService 的概率模型） */
  @Builder
  predictionPanel() {
    if (this.poolCards.length > 0) {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          NavIcon({ name: 'GachaLog', iconSize: 16 })
          Text('抽卡预测')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(this.vm.currentPoolType === GachaType.WEAPON_EVENT ? '武器活动祈愿' : '角色活动祈愿')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        Row({ space: 8 }) {
          ForEach([10, 20, 30, 50, 90], (n: number) => {
            Column({ space: 3 }) {
              Text(`${Math.round(GachaLogPage.predictFive(this.currentPity(), n) * 100)}%`)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.five_star'))
              Text(`${n} 抽内`)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .padding({ top: 8, bottom: 8 })
            .borderRadius(10)
            .backgroundColor($r('app.color.page_background'))
            .alignItems(HorizontalAlign.Center)
          }, (n: number) => `pred_${n}_${this.currentPity()}`)
        }
        .width('100%')

        Text('基于 0.6% 基准概率 + 74 抽软保底 + 90 抽硬保底的概率模型；「歪」后大保底必为 UP')
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius($r('app.float.card_radius'))
      .backgroundColor($r('app.color.card_background'))
    }
  }

  /** 当前池已垫抽数（预测用） */
  private currentPity(): number {
    for (const card of this.poolCards) {
      if (card.gachaType === this.vm.currentPoolType) {
        return card.sinceLastFive;
      }
    }
    // 未找到当前池：取角色池垫数
    for (const card of this.poolCards) {
      if (card.gachaType === GachaType.AVATAR_EVENT) {
        return card.sinceLastFive;
      }
    }
    return 0;
  }

  /** 倒计时区：各池距保底剩余抽数卡 */
  @Builder
  countdownSection() {
    if (this.poolCards.length === 0) {
      Text('暂无池数据，点击右上角「刷新」拉取')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .textAlign(TextAlign.Center)
    } else {
    Column({ space: 10 }) {
      this.predictionPanel()
      ForEach(this.poolCards, (card: PoolCardData) => {
        Column({ space: 10 }) {
          Row({ space: 6 }) {
            Text('◆')
              .fontSize(10)
              .fontColor($r('app.color.app_primary'))
            Text(card.typeName)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            if (card.lastFiveName.length > 0) {
              Text(`最近五星：${card.lastFiveName}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .width('100%')

          Row({ space: 8 }) {
            // 五星倒计时
            Column({ space: 4 }) {
              Text(`${Math.max(0, ORANGE_GUARANTEE - card.sinceLastFive)}`)
                .fontSize(30)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.five_star'))
              Text('距五星保底抽数')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
              Progress({
                value: Math.min(card.sinceLastFive, ORANGE_GUARANTEE),
                total: ORANGE_GUARANTEE,
                type: ProgressType.Linear,
              })
                .width('100%')
                .color($r('app.color.five_star'))
                .style({ strokeWidth: 6 })
              Text(`已垫 ${card.sinceLastFive} / 保底 ${ORANGE_GUARANTEE} 抽`)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .padding(12)
            .borderRadius(10)
            .backgroundColor($r('app.color.page_background'))
            .border({ width: 1, color: $r('app.color.divider') })
            .alignItems(HorizontalAlign.Center)

            // 四星倒计时
            Column({ space: 4 }) {
              Text(`${Math.max(0, PURPLE_GUARANTEE - card.sinceLastFour)}`)
                .fontSize(30)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.four_star'))
              Text('距四星保底抽数')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
              Progress({
                value: Math.min(card.sinceLastFour, PURPLE_GUARANTEE),
                total: PURPLE_GUARANTEE,
                type: ProgressType.Linear,
              })
                .width('100%')
                .color($r('app.color.four_star'))
                .style({ strokeWidth: 6 })
              Text(`已垫 ${card.sinceLastFour} / 保底 ${PURPLE_GUARANTEE} 抽`)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .padding(12)
            .borderRadius(10)
            .backgroundColor($r('app.color.page_background'))
            .border({ width: 1, color: $r('app.color.divider') })
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
        }
        .width('100%')
        .padding(14)
        .borderRadius($r('app.float.card_radius'))
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 1, color: card.isCurrent && !this.isWide ? $r('app.color.app_primary') : $r('app.color.divider') })
      }, (card: PoolCardData) => `cd_${card.gachaType}`)
      }
      .width('100%')
    }
  }
}
