/**
 * GachaLogViewModel.ets
 * 祈愿记录页状态容器：归档管理、分池统计聚合、刷新进度、历史列表、手动 URL 导入命令。
 */
import { GachaLogService, RefreshResult } from '../service/GachaLogService';
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaType } from '../model/GachaType';
import { GachaArchive } from '../model/GachaArchive';
import { GachaItem } from '../model/GachaItem';
import { GachaStatistics, PoolStatistics, FiveStarDetail } from '../model/GachaStatistics';
import { RefreshProgress } from '../model/RefreshProgress';
import { Logger } from '../common/Logger';

const TAG: string = 'GachaLogViewModel';

@Observed
export class GachaLogViewModel {
  archives: GachaArchive[] = [];
  currentArchiveId: number = 0;
  currentUid: string = '';
  /** 当前池 */
  currentPoolType: number = GachaType.AVATAR_EVENT;
  stats: GachaStatistics = new GachaStatistics();
  /** 当前池历史列表（倒序） */
  items: GachaItem[] = [];
  progress: RefreshProgress = new RefreshProgress();
  isRefreshing: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 进度更新回调（页面注入，用于强制刷新 UI） */
  onProgressChanged: (() => void) = () => {
  };

  /** 初始化：按 UID 装载归档（uid 恒为权威值，绝不回退到其它归档的 uid） */
  async load(uid: string): Promise<void> {
    this.currentUid = uid;
    this.archives = await GachaRepo.getAllArchives();
    if (uid.length === 0) {
      // 未登录/未绑定默认 UID：只读展示既有归档，不创建、不覆盖
      if (this.archives.length > 0) {
        this.currentArchiveId = this.archives[0].id;
      } else {
        this.currentArchiveId = 0;
        this.stats = new GachaStatistics();
        this.items = [];
        this.loaded = true;
        return;
      }
    } else {
      let found: boolean = false;
      for (let i = 0; i < this.archives.length; i++) {
        if (this.archives[i].uid === uid) {
          this.currentArchiveId = this.archives[i].id;
          found = true;
          break;
        }
      }
      if (!found) {
        const archive: GachaArchive = await GachaRepo.getOrCreateArchive(uid);
        this.currentArchiveId = archive.id;
        this.archives = await GachaRepo.getAllArchives();
      }
    }
    await this.reloadStats();
    await this.reloadItems();
    this.loaded = true;
  }

  /** 切换池子：重算全池统计（保证六项统计随池切换刷新）并重载当前池记录 */
  async selectPool(gachaType: number): Promise<void> {
    this.currentPoolType = gachaType;
    Logger.info(TAG, `selectPool -> ${GachaType.nameOf(gachaType)}(${gachaType})`);
    await this.reloadStats();
    await this.reloadItems();
  }

  /** 重算统计 */
  async reloadStats(): Promise<void> {
    const stats: GachaStatistics = new GachaStatistics();
    stats.uid = this.currentUid;
    stats.archiveId = this.currentArchiveId;
    if (this.currentArchiveId > 0) {
      const pools: PoolStatistics[] = [];
      let total: number = 0;
      // 常规池 + 千星奇域颂愿池一起聚合（颂愿卡片仅在颂愿模式展示）
      const allTypes: number[] = GachaType.QUERY_ORDER.concat(GachaType.BEYOND_ORDER);
      for (let i = 0; i < allTypes.length; i++) {
        const type: number = allTypes[i];
        try {
          const pool: PoolStatistics = await this.buildPoolStats(this.currentArchiveId, type);
          if (GachaType.isStandard(type)) {
            total += pool.totalCount;
          }
          pools.push(pool);
        } catch (e) {
          Logger.warn(TAG, `buildPoolStats type=${type} fail: ${(e as Error).message}`);
          pools.push(GachaLogViewModel.emptyPool(type));
        }
      }
      stats.pools = pools;
      stats.totalPulls = total;
      Logger.info(TAG, `reloadStats archive=${this.currentArchiveId} total=${total} pools=${pools.length}`);
      for (let i = 0; i < pools.length; i++) {
        const p: PoolStatistics = pools[i];
        Logger.info(TAG, `summary pool ${p.typeName}: total=${p.totalCount} ` +
          `5star=${p.fiveStarCount} 4star=${p.fourStarCount} since=${p.sinceLastFive} ` +
          `avg=${p.averageOrangePull} min=${p.minOrangePull} max=${p.maxOrangePull} date=[${p.startDate}~${p.endDate}]`);
      }
      // 填充全部统计用 uid
      const archives: GachaArchive[] = await GachaRepo.getAllArchives();
      for (let i = 0; i < archives.length; i++) {
        if (archives[i].id === this.currentArchiveId) {
          stats.uid = archives[i].uid;
          break;
        }
      }
    }
    this.stats = stats;
  }

  private static emptyPool(gachaType: number): PoolStatistics {
    const pool: PoolStatistics = new PoolStatistics();
    pool.gachaType = gachaType;
    pool.typeName = GachaType.nameOf(gachaType);
    return pool;
  }

  private async buildPoolStats(archiveId: number, gachaType: number): Promise<PoolStatistics> {
    const pool: PoolStatistics = new PoolStatistics();
    pool.gachaType = gachaType;
    pool.typeName = GachaType.nameOf(gachaType);
    const items: GachaItem[] = await GachaRepo.getItemsByType(archiveId, gachaType);
    pool.totalCount = items.length;
    if (items.length === 0) {
      return pool;
    }
    // 纯本地同步聚合（数据量级小，无需 TaskPool，避免序列化/返回值解析导致统计为 0）
    let fiveStar: number = 0;
    let fourStar: number = 0;
    let sinceLastFive: number = 0;
    let sinceLastFour: number = 0;
    const fiveNames: string[] = [];
    const fiveTimes: string[] = [];
    const fiveItemTypes: string[] = [];
    // 五星出金之间的抽数序列（升序遍历）
    const fiveSpans: number[] = [];
    let spanSinceLastFive: number = 0;
    for (let i = 0; i < items.length; i++) {
      if (items[i].rankType === 5) {
        fiveStar++;
        fiveNames.push(items[i].name);
        fiveTimes.push(items[i].time);
        fiveItemTypes.push(items[i].itemType);
        fiveSpans.push(spanSinceLastFive + 1);
        spanSinceLastFive = 0;
      } else if (items[i].rankType === 4) {
        fourStar++;
        spanSinceLastFive++;
      } else {
        spanSinceLastFive++;
      }
    }
    // 当前垫数（最新距上次五星/四星）
    for (let i = items.length - 1; i >= 0; i--) {
      if (items[i].rankType === 5) {
        break;
      }
      sinceLastFive++;
    }
    for (let i = items.length - 1; i >= 0; i--) {
      if (items[i].rankType === 4) {
        break;
      }
      sinceLastFour++;
    }
    pool.fiveStarCount = fiveStar;
    pool.fourStarCount = fourStar;
    pool.sinceLastFive = sinceLastFive;
    pool.sinceLastFour = sinceLastFour;
    // 池日期范围（升序查询：首条最早、末条最新）
    pool.startDate = GachaLogViewModel.formatPoolDate(items[0].time);
    pool.endDate = GachaLogViewModel.formatPoolDate(items[items.length - 1].time);
    // 五星平均抽数 / 最非 / 最欧
    if (fiveStar > 0) {
      pool.averageOrangePull = Math.round(items.length / fiveStar);
      pool.maxOrangePull = 0;
      pool.minOrangePull = 0;
      for (let i = 0; i < fiveSpans.length; i++) {
        if (pool.maxOrangePull === 0 || fiveSpans[i] > pool.maxOrangePull) {
          pool.maxOrangePull = fiveSpans[i];
        }
        if (pool.minOrangePull === 0 || fiveSpans[i] < pool.minOrangePull) {
          pool.minOrangePull = fiveSpans[i];
        }
      }
    }
    // 四星平均抽数
    if (fourStar > 0) {
      pool.averagePurplePull = Math.round(items.length / fourStar);
    }
    if (fiveNames.length > 0) {
      pool.lastFiveName = fiveNames[fiveNames.length - 1];
      pool.lastFiveTime = fiveTimes[fiveTimes.length - 1];
    }
    // 出金历史（倒序）+ 每角色用抽数明细（itemType 优先用服务端实际记录）
    for (let i = fiveNames.length - 1; i >= 0; i--) {
      const copied: GachaItem = new GachaItem();
      copied.name = fiveNames[i];
      copied.time = fiveTimes[i];
      copied.rankType = 5;
      pool.fiveHistory.push(copied);
      const detail: FiveStarDetail = new FiveStarDetail();
      detail.name = fiveNames[i];
      detail.time = fiveTimes[i];
      detail.lastPull = fiveSpans.length > i ? fiveSpans[i] : 0;
      detail.isUp = GachaLogViewModel.isLikelyUp(gachaType, i, fiveNames.length);
      detail.itemType = fiveItemTypes.length > i && fiveItemTypes[i].length > 0
        ? fiveItemTypes[i]
        : (gachaType === GachaType.WEAPON_EVENT ? '武器' : '角色');
      pool.fiveDetails.push(detail);
    }
    Logger.info(TAG, `pool ${gachaType} stats: ${pool.toString()}`);
    return pool;
  }

  /** 'yyyy-MM-dd HH:mm:ss' → 'yyyy.MM.dd'（不足则原样返回） */
  private static formatPoolDate(time: string): string {
    if (time.length < 10) {
      return time;
    }
    return `${time.substring(0, 4)}.${time.substring(5, 7)}.${time.substring(8, 10)}`;
  }

  /** 简化 UP 判定：角色事件池(301)每期第一个五星视为 UP 角色（需当期池元数据，此处近似） */
  private static isLikelyUp(gachaType: number, indexFromLatest: number, totalFive: number): boolean {
    if (gachaType === GachaType.AVATAR_EVENT) {
      // 角色池：最近一个五星 50% 是 UP（按 half 周期假设），简化标记最近一个为 UP
      return indexFromLatest === 0;
    }
    return false;
  }

  /** 重载当前池历史（全部，倒序；UI 用 List LazyForEach 虚拟滚动） */
  async reloadItems(): Promise<void> {
    if (this.currentArchiveId <= 0) {
      this.items = [];
      return;
    }
    this.items = await GachaRepo.getItems(this.currentArchiveId, this.currentPoolType, 100000, 0);
  }

  /** 一键刷新（SToken） */
  async refresh(): Promise<boolean> {
    if (this.isRefreshing) {
      return false;
    }
    if (this.currentUid.length === 0) {
      this.message = '请先登录并选择默认 UID';
      return false;
    }
    this.isRefreshing = true;
    this.progress = new RefreshProgress();
    try {
      const result: RefreshResult = await GachaLogService.getInstance()
        .refreshByStoken(this.currentUid, (p: RefreshProgress) => {
          this.progress = p;
          this.onProgressChanged();
        });
      this.message = result.message;
      await this.reloadStats();
      await this.reloadItems();
      // 通知主页祈愿卡重新读库（AppStorage 版本戳 + @Watch）
      if (result.ok) {
        AppStorage.setOrCreate<number>('gachaDataVersion', Date.now());
      }
      return result.ok;
    } catch (e) {
      this.message = (e as Error).message;
      Logger.warn(TAG, `refresh fail ${this.message}`);
      return false;
    } finally {
      this.isRefreshing = false;
    }
  }

  /** 手动 URL 导入 */
  async importByUrl(url: string): Promise<boolean> {
    if (this.isRefreshing) {
      return false;
    }
    this.isRefreshing = true;
    this.progress = new RefreshProgress();
    try {
      const result: RefreshResult = await GachaLogService.getInstance()
        .importByUrl(url, this.currentUid, (p: RefreshProgress) => {
          this.progress = p;
          this.onProgressChanged();
        });
      this.message = result.message;
      await this.reloadStats();
      await this.reloadItems();
      // 通知主页祈愿卡重新读库（AppStorage 版本戳 + @Watch）
      if (result.ok) {
        AppStorage.setOrCreate<number>('gachaDataVersion', Date.now());
      }
      return result.ok;
    } catch (e) {
      this.message = (e as Error).message;
      return false;
    } finally {
      this.isRefreshing = false;
    }
  }

  /** 删除当前归档 */
  async deleteCurrentArchive(): Promise<void> {
    if (this.currentArchiveId <= 0) {
      return;
    }
    await GachaRepo.deleteArchive(this.currentArchiveId);
    this.archives = await GachaRepo.getAllArchives();
    this.stats = new GachaStatistics();
    this.items = [];
    this.currentArchiveId = 0;
  }
}
