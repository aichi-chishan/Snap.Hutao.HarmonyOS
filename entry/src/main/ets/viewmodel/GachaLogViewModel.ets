/**
 * GachaLogViewModel.ets
 * 祈愿记录页状态容器：归档管理、分池统计聚合、刷新进度、历史列表、手动 URL 导入命令。
 */
import { GachaLogService, RefreshResult } from '../service/GachaLogService';
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaType } from '../model/GachaType';
import { GachaArchive } from '../model/GachaArchive';
import { GachaItem } from '../model/GachaItem';
import { GachaStatistics, PoolStatistics } from '../model/GachaStatistics';
import { GachaStatisticsService } from '../service/GachaStatisticsService';
import { GachaItemIdentityService } from '../service/GachaItemIdentityService';
import { RefreshProgress } from '../model/RefreshProgress';
import { WikiMetaService, GachaEventMeta } from '../service/WikiMetaService';
import { UigfImportJob } from '../service/UigfImportJob';
import { UigfService, UigfImportResult } from '../service/UigfService';
import { UigfImportPreparation, UigfImportPreview } from '../model/UigfImportPreparation';
import { Logger } from '../common/Logger';
import { GachaCollection, GachaCollectionService } from '../service/GachaCollectionService';
import { PreferencesStore } from '../data/prefs/PreferencesStore';

const TAG: string = 'GachaLogViewModel';
const HISTORY_ITEM_LIMIT: number = 100000;

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

  async confirmImport(fillGaps: boolean = false): Promise<UigfImportResult> {
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
      }, fillGaps);
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

  /** 归档统计与选中的历史池无关。 */
  async selectPool(gachaType: number): Promise<void> {
    this.currentPoolType = gachaType;
    Logger.info(TAG, `selectPool -> ${GachaType.nameOf(gachaType)}(${gachaType})`);
    await this.reloadItems();
  }

  /** 统计、收藏和当前池历史使用同一次归档读取。 */
  async reloadStats(): Promise<void> {
    const generation: number = ++this.statsGeneration;
    const itemsGeneration: number = ++this.itemsGeneration;
    const archiveId: number = this.currentArchiveId;
    const selectedPool: number = this.currentPoolType;
    const stats: GachaStatistics = new GachaStatistics();
    stats.uid = this.currentUid;
    stats.archiveId = archiveId;
    if (archiveId <= 0) {
      this.stats = stats;
      this.items = [];
      return;
    }
    const stored: GachaItem[] = await GachaRepo.getItemsByArchive(archiveId);
    if (generation !== this.statsGeneration || archiveId !== this.currentArchiveId) { return; }
    const allItems: GachaItem[] = await GachaItemIdentityService.resolveMissing(stored);
    if (generation !== this.statsGeneration || archiveId !== this.currentArchiveId) { return; }
    const events: GachaEventMeta[] = await WikiMetaService.getGachaEvents();
    const collection: GachaCollection = GachaCollectionService.count(allItems,
      await WikiMetaService.getAvatars(), await WikiMetaService.getWeapons(), events,
      PreferencesStore.getBool(PreferencesStore.KEY_GACHA_UNOBTAINED, false));
    if (generation !== this.statsGeneration || archiveId !== this.currentArchiveId) { return; }

    const grouped: Map<number, GachaItem[]> = new Map<number, GachaItem[]>();
    for (const item of allItems) {
      const type: number = GachaType.queryTypeOf(item.gachaType);
      const group: GachaItem[] = grouped.get(type) ?? [];
      group.push(item);
      grouped.set(type, group);
    }
    const timezone: number = UigfService.timezoneOfUid(stats.uid);
    for (const type of GachaType.QUERY_ORDER.concat(GachaType.BEYOND_ORDER)) {
      try {
        const pool: PoolStatistics = GachaStatisticsService.buildPool(grouped.get(type) ?? [], type, events, timezone);
        if (GachaType.isStandard(type)) { stats.totalPulls += pool.totalCount; }
        stats.pools.push(pool);
      } catch (e) {
        Logger.warn(TAG, `buildPoolStats type=${type} fail: ${(e as Error).message}`);
        stats.pools.push(GachaLogViewModel.emptyPool(type));
      }
    }
    stats.avatars = collection.avatars;
    stats.weapons = collection.weapons;
    Logger.info(TAG, `reloadStats archive=${archiveId} total=${stats.totalPulls} pools=${stats.pools.length}`);
    for (const pool of stats.pools) {
      Logger.info(TAG, `summary pool ${pool.typeName}: total=${pool.totalCount} ` +
        `5star=${pool.fiveStarCount} 4star=${pool.fourStarCount} since=${pool.sinceLastFive} ` +
        `avg=${pool.averageOrangePull} min=${pool.minOrangePull} max=${pool.maxOrangePull} date=[${pool.startDate}~${pool.endDate}]`);
    }
    this.stats = stats;
    if (!this.ownsHistoryRead(itemsGeneration, archiveId, selectedPool)) { return; }
    const history: GachaItem[] = grouped.get(selectedPool) ?? allItems.filter(
      (item: GachaItem): boolean => item.gachaType === selectedPool);
    // 上限作用于去重后的逻辑记录，并与本次统计共享同一快照。
    const items: GachaItem[] = history.slice(-HISTORY_ITEM_LIMIT).sort((left: GachaItem, right: GachaItem): number => {
        const order: number = GachaItem.compareIds(right.gachaId, left.gachaId);
        if (order !== 0 || left.time === right.time) { return order; }
        return left.time < right.time ? 1 : -1;
      });
    if (this.ownsHistoryRead(itemsGeneration, archiveId, selectedPool)) { this.items = items; }
  }

  private static emptyPool(gachaType: number): PoolStatistics {
    const pool: PoolStatistics = new PoolStatistics();
    pool.gachaType = gachaType;
    pool.typeName = GachaType.nameOf(gachaType);
    return pool;
  }

  private static async readPoolItems(archiveId: number, pool: number): Promise<GachaItem[]> {
    return archiveId > 0
      ? await GachaItemIdentityService.resolveMissing(await GachaRepo.getItems(archiveId, pool, HISTORY_ITEM_LIMIT, 0)) : [];
  }

  private ownsHistoryRead(generation: number, archiveId: number, pool: number): boolean {
    return generation === this.itemsGeneration && archiveId === this.currentArchiveId && pool === this.currentPoolType;
  }

  /** 重载当前池历史；旧选档/旧池结果不能覆盖新上下文。 */
  async reloadItems(): Promise<void> {
    const generation: number = ++this.itemsGeneration;
    const archiveId: number = this.currentArchiveId;
    const pool: number = this.currentPoolType;
    const items: GachaItem[] = await GachaLogViewModel.readPoolItems(archiveId, pool);
    if (this.ownsHistoryRead(generation, archiveId, pool)) { this.items = items; }
  }

  /** 自动鉴权仅针对登录账号 UID，绝不借用离线选档 UID。onlyTypes 限定池（失败池单项重试）。 */
  async refresh(onlyTypes: number[] | undefined = undefined): Promise<boolean> {
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
        }, this.fullRefresh, onlyTypes);
      // 已发生的持久化变更仍需通知其它页面，但不能恢复过期的页面状态。
      if (result.ok || result.fetchedCount > 0) { AppStorage.setOrCreate<number>('gachaDataVersion', Date.now()); }
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
  async importByUrl(url: string, onlyTypes: number[] | undefined = undefined): Promise<boolean> {
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
        }, this.fullRefresh, onlyTypes);
      if (result.ok || result.fetchedCount > 0) { AppStorage.setOrCreate<number>('gachaDataVersion', Date.now()); }
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
