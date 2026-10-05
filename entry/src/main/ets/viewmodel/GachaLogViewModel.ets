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
import { WikiMetaService, GachaEventMeta } from '../service/WikiMetaService';
import { UigfImportJob } from '../service/UigfImportJob';
import { UigfService, UigfImportResult } from '../service/UigfService';
import { UigfImportPreparation, UigfImportPreview } from '../model/UigfImportPreparation';
import { Logger } from '../common/Logger';

const TAG: string = 'GachaLogViewModel';

@Observed
export class GachaLogViewModel {
  archives: GachaArchive[] = [];
  currentArchiveId: number = 0;
  /** 本地归档与登录账号是两个独立上下文。 */
  currentUid: string = '';
  gameAccountUid: string = '';
  isTransferring: boolean = false;
  importPreview: UigfImportPreview = new UigfImportPreview();
  importUids: string[] = [];
  exportUids: string[] = [];
  exportVersion: string = 'v4.2';
  isPreparingImport: boolean = false;
  private importJob: UigfImportJob | undefined = undefined;
  private preparedImport: UigfImportPreparation | undefined = undefined;
  private importGeneration: number = 0;
  private loadGeneration: number = 0;
  private statsGeneration: number = 0;
  private itemsGeneration: number = 0;
  private operationGeneration: number = 0;
  /** 当前池 */
  currentPoolType: number = GachaType.AVATAR_EVENT;
  stats: GachaStatistics = new GachaStatistics();
  /** 当前池历史列表（倒序） */
  items: GachaItem[] = [];
  progress: RefreshProgress = new RefreshProgress();
  isRefreshing: boolean = false;
  fullRefresh: boolean = false;

  cancelRefresh(): void {
    GachaLogService.getInstance().cancelRefresh();
  }
  message: string = '';
  loaded: boolean = false;
  /** 进度更新回调（页面注入，用于强制刷新 UI） */
  onProgressChanged: (() => void) = () => {
  };

  /** 使旧页面/账号读取失效；网络任务仍占用忙碌锁，直到底层调用结束。 */
  invalidateRequests(): void {
    this.clearImport();
    this.exportUids = [];
    this.loadGeneration++;
    this.statsGeneration++;
    this.itemsGeneration++;
    this.operationGeneration++;
    if (this.isRefreshing) {
      this.cancelRefresh();
      // Service 会复用同一个进度对象；失效时断开引用，旧对象后续原地修改也不能泄漏到新页面。
      this.progress = new RefreshProgress();
      this.progress.reportText = '正在停止刷新，请稍后重试';
    }
  }

  /** 只读装载本地归档；登录/默认角色变更不会覆盖用户当前的离线选档。 */
  async load(uid: string, preferredArchiveUid: string = ''): Promise<void> {
    const accountUid: string = /^[1-9][0-9]{8,9}$/.test(uid) ? uid : '';
    if (accountUid !== this.gameAccountUid) { this.invalidateRequests(); }
    this.gameAccountUid = accountUid;
    const generation: number = ++this.loadGeneration;
    this.statsGeneration++;
    this.itemsGeneration++;
    const archives: GachaArchive[] = await GachaRepo.getAllArchives();
    if (generation !== this.loadGeneration) { return; }
    // 不展示历史版本留下的空 UID 归档，也不在只读装载时创建任何归档。
    this.archives = archives.filter((archive: GachaArchive): boolean =>
      archive.id > 0 && /^[1-9][0-9]{8,9}$/.test(archive.uid));
    let selected: GachaArchive | undefined = this.archives.find((archive: GachaArchive): boolean =>
      preferredArchiveUid.length > 0 && archive.uid === preferredArchiveUid);
    if (selected === undefined) {
      selected = this.archives.find((archive: GachaArchive): boolean => archive.id === this.currentArchiveId);
    }
    if (selected === undefined) {
      selected = this.archives.find((archive: GachaArchive): boolean => archive.isSelected);
    }
    if (selected === undefined) {
      selected = this.archives.find((archive: GachaArchive): boolean => archive.uid === accountUid);
    }
    if (selected === undefined && this.archives.length > 0) { selected = this.archives[0]; }
    if (this.currentArchiveId !== (selected?.id ?? 0)) {
      this.stats = new GachaStatistics();
      this.items = [];
    }
    this.currentArchiveId = selected?.id ?? 0;
    this.currentUid = selected?.uid ?? '';
    await this.reloadStats();
    if (generation !== this.loadGeneration) { return; }
    await this.reloadItems();
    if (generation === this.loadGeneration) { this.loaded = true; }
  }

  /** 显式选档才更新本地选中标记；不改变网络账号，不创建归档。 */
  async selectArchive(id: number): Promise<void> {
    if (this.isRefreshing || this.isTransferring) { throw new Error('请等待当前操作完成'); }
    const archive: GachaArchive | undefined = this.archives.find((item: GachaArchive): boolean => item.id === id);
    if (archive === undefined) { throw new Error('所选祈愿档案不存在'); }
    this.clearImport();
    this.exportUids = [];
    this.isTransferring = true;
    const generation: number = ++this.loadGeneration;
    this.statsGeneration++;
    this.itemsGeneration++;
    try {
      await GachaRepo.selectArchive(id);
      if (generation !== this.loadGeneration) { return; }
      await this.load(this.gameAccountUid, archive.uid);
    } finally { this.isTransferring = false; }
  }

  /** Native preparation is cancellable and never adopts a stale owner's worker result. */
  async prepareImport(text: string): Promise<boolean> { return await this.prepareImportSource(text, false); }

  async prepareImportFile(uri: string): Promise<boolean> { return await this.prepareImportSource(uri, true); }

  private async prepareImportSource(source: string, isFile: boolean): Promise<boolean> {
    this.clearImport();
    const generation: number = this.importGeneration;
    const operation: number = this.operationGeneration;
    const job: UigfImportJob = new UigfImportJob();
    this.importJob = job;
    this.isPreparingImport = true;
    let prepared: UigfImportPreparation | undefined = undefined;
    try {
      prepared = await job.prepare(source, isFile, () => {
        if (generation !== this.importGeneration || operation !== this.operationGeneration) { throw new Error('UIGF 预览已失效'); }
      });
      if (generation !== this.importGeneration || operation !== this.operationGeneration) { return false; }
      this.preparedImport = prepared;
      this.importPreview = prepared.preview();
      this.importUids = this.importPreview.uids.slice();
      prepared = undefined;
      return true;
    } catch (e) {
      if (generation !== this.importGeneration || operation !== this.operationGeneration) { return false; }
      if (e instanceof Error) { throw e; }
      throw new Error('UIGF 处理失败，请重新选择文件');
    } finally {
      prepared?.dispose();
      if (this.importJob === job) { this.importJob = undefined; this.isPreparingImport = false; }
    }
  }

  clearImport(): void {
    this.importGeneration++;
    this.importJob?.cancel();
    this.importJob = undefined;
    this.isPreparingImport = false;
    this.preparedImport?.dispose();
    this.preparedImport = undefined;
    this.importPreview = new UigfImportPreview();
    this.importUids = [];
  }

  async confirmImport(): Promise<UigfImportResult> {
    if (this.isRefreshing || this.isTransferring) { throw new Error('请等待当前操作完成'); }
    const prepared: UigfImportPreparation | undefined = this.preparedImport;
    if (prepared === undefined) { throw new Error('请先选择并预览 UIGF 文件'); }
    const generation: number = this.importGeneration;
    const operation: number = this.operationGeneration;
    const selection: string[] = this.importUids.slice();
    this.isTransferring = true;
    try {
      const result: UigfImportResult = await UigfService.getInstance().importPrepared(prepared, selection, () => {
        if (generation !== this.importGeneration || operation !== this.operationGeneration || prepared !== this.preparedImport) {
          throw new Error('UIGF 预览已失效，未写入数据');
        }
      });
      if (result.ok) {
        AppStorage.setOrCreate<number>('gachaDataVersion', Date.now());
        if (generation !== this.importGeneration || operation !== this.operationGeneration) { return result; }
        this.clearImport();
        try { await this.load(this.gameAccountUid, result.uid); }
        catch (e) {
          Logger.warn(TAG, `import committed; view reload failed: ${(e as Error).message}`);
          result.message += '；请重新打开页面刷新本地视图';
        }
      }
      return result;
    } finally { this.isTransferring = false; }
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
    const generation: number = ++this.statsGeneration;
    const archiveId: number = this.currentArchiveId;
    const stats: GachaStatistics = new GachaStatistics();
    stats.uid = this.currentUid;
    stats.archiveId = archiveId;
    if (archiveId > 0) {
      const pools: PoolStatistics[] = [];
      let total: number = 0;
      // 常规池 + 千星奇域颂愿池一起聚合（颂愿卡片仅在颂愿模式展示）
      const allTypes: number[] = GachaType.QUERY_ORDER.concat(GachaType.BEYOND_ORDER);
      for (let i = 0; i < allTypes.length; i++) {
        const type: number = allTypes[i];
        try {
          const pool: PoolStatistics = await this.buildPoolStats(archiveId, type);
          if (generation !== this.statsGeneration || archiveId !== this.currentArchiveId) { return; }
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
    }
    if (generation === this.statsGeneration && archiveId === this.currentArchiveId) { this.stats = stats; }
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
    const fiveItems: GachaItem[] = [];
    const events: GachaEventMeta[] = await WikiMetaService.getGachaEvents();
    const archive = this.archives.find((item: GachaArchive): boolean => item.id === archiveId);
    const timezone: number = UigfService.timezoneOfUid(archive?.uid ?? this.currentUid);
    // 五星出金之间的抽数序列（升序遍历）
    const fiveSpans: number[] = [];
    let spanSinceLastFive: number = 0;
    for (let i = 0; i < items.length; i++) {
      if (items[i].rankType === 5) {
        fiveStar++;
        fiveNames.push(items[i].name);
        fiveItems.push(items[i]);
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
      pool.averageOrangePull = Math.round(fiveSpans.reduce((sum: number, span: number): number => sum + span, 0) / fiveStar);
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
      pool.averagePurplePull = Math.round((items.length - sinceLastFour) / fourStar);
    }
    if (fiveNames.length > 0) {
      pool.lastFiveName = fiveNames[fiveNames.length - 1];
      pool.lastFiveTime = fiveTimes[fiveTimes.length - 1];
    }
    const cycles: number[] = [];
    let cycle: number = 0;
    for (let i: number = 0; i < fiveItems.length; i++) {
      cycle += fiveSpans[i];
      const up: boolean | undefined = GachaLogViewModel.isEventUp(fiveItems[i], events, timezone);
      cycles.push(up === true ? cycle : 0);
      if (up === true) {
        cycle = 0;
      }
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
      const up: boolean | undefined = GachaLogViewModel.isEventUp(fiveItems[i], events, timezone);
      detail.isUp = up === true;
      detail.upKnown = up !== undefined;
      detail.totalCyclePull = cycles[i];
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

  /** 只按当期池元数据判定UP；缺失元数据时保留未知，不推测中奖。 */
  private static isEventUp(item: GachaItem, events: GachaEventMeta[], timezone: number): boolean | undefined {
    let timestamp: number = 0;
    try {
      timestamp = Date.parse(UigfService.normalizeTime(item.time, timezone, 0).replace(' ', 'T') + 'Z');
    } catch (e) {
      return undefined;
    }
    for (const event of events) {
      if (event.type === item.gachaType && timestamp >= event.from && timestamp <= event.to) {
        return event.upOrange.indexOf(item.itemId) >= 0;
      }
    }
    return undefined;
  }

  /** 重载当前池历史；旧选档/旧池结果不能覆盖新上下文。 */
  async reloadItems(): Promise<void> {
    const generation: number = ++this.itemsGeneration;
    const archiveId: number = this.currentArchiveId;
    const pool: number = this.currentPoolType;
    const items: GachaItem[] = archiveId > 0 ? await GachaRepo.getItems(archiveId, pool, 100000, 0) : [];
    if (generation === this.itemsGeneration && archiveId === this.currentArchiveId && pool === this.currentPoolType) {
      this.items = items;
    }
  }

  /** 自动鉴权仅针对登录账号 UID，绝不借用离线选档 UID。 */
  async refresh(): Promise<boolean> {
    if (this.isRefreshing || this.isTransferring) { return false; }
    if (this.gameAccountUid.length === 0) {
      this.message = '请先登录并选择默认 UID';
      return false;
    }
    const uid: string = this.gameAccountUid;
    const operation: number = ++this.operationGeneration;
    this.isRefreshing = true;
    this.progress = new RefreshProgress();
    try {
      const result: RefreshResult = await GachaLogService.getInstance()
        .refreshByStoken(uid, (p: RefreshProgress) => {
          if (operation !== this.operationGeneration) { return; }
          this.progress = p;
          this.onProgressChanged();
        }, this.fullRefresh);
      // 已发生的持久化变更仍需通知其它页面，但不能恢复过期的页面状态。
      if (result.ok) { AppStorage.setOrCreate<number>('gachaDataVersion', Date.now()); }
      if (operation !== this.operationGeneration) { return false; }
      this.message = result.message;
      await this.load(this.gameAccountUid);
      return operation === this.operationGeneration && result.ok;
    } catch (e) {
      if (operation === this.operationGeneration) {
        this.message = (e as Error).message;
        Logger.warn(TAG, `refresh fail ${this.message}`);
      }
      return false;
    } finally { this.isRefreshing = false; }
  }

  /** URL 自带鉴权；归属由服务端响应校验，不能借用选档或登录账号。 */
  async importByUrl(url: string): Promise<boolean> {
    if (this.isRefreshing || this.isTransferring) { return false; }
    const operation: number = ++this.operationGeneration;
    this.isRefreshing = true;
    this.progress = new RefreshProgress();
    try {
      const result: RefreshResult = await GachaLogService.getInstance()
        .importByUrl(url, '', (p: RefreshProgress) => {
          if (operation !== this.operationGeneration) { return; }
          this.progress = p;
          this.onProgressChanged();
        }, this.fullRefresh);
      if (result.ok) { AppStorage.setOrCreate<number>('gachaDataVersion', Date.now()); }
      if (operation !== this.operationGeneration) { return false; }
      this.message = result.message;
      await this.load(this.gameAccountUid, result.uid);
      return operation === this.operationGeneration && result.ok;
    } catch (e) {
      if (operation === this.operationGeneration) { this.message = (e as Error).message; }
      return false;
    } finally { this.isRefreshing = false; }
  }

  /** 删除后的装载仍然只读；不因登录 UID 重新创建已删除归档。 */
  async deleteCurrentArchive(): Promise<void> {
    if (this.isRefreshing || this.isTransferring) { throw new Error('请等待当前操作完成'); }
    const archiveId: number = this.currentArchiveId;
    if (archiveId <= 0) { return; }
    const operation: number = ++this.operationGeneration;
    this.isTransferring = true;
    try {
      await GachaRepo.deleteArchive(archiveId);
      AppStorage.setOrCreate<number>('gachaDataVersion', Date.now());
      if (operation !== this.operationGeneration) { return; }
      await this.load(this.gameAccountUid);
    } finally { this.isTransferring = false; }
  }
}
