/**
 * GachaLogService.ets
 * 祈愿刷新流程：genAuthKey(SToken)→逐 gacha_type 分页拉取(size=20, end_id 游标)→去重合并写入→进度上报。
 * 手动 URL 兜底：解析 authkey 后走同一分页流程。防封：每页间 1~2s 随机延时；authkey 超时检测。
 */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { GachaAuthApi, GachaAuthInfo } from '../data/network/GachaAuthApi';
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaType } from '../model/GachaType';
import { GachaItem } from '../model/GachaItem';
import { GachaArchive } from '../model/GachaArchive';
import { RefreshProgress, PoolOutcome, RecentGachaItem } from '../model/RefreshProgress';
import { User } from '../model/User';
import { UserService } from './UserService';
import { GachaItemIdentityService } from './GachaItemIdentityService';
import { RegionUtil, AppConstants, RetCodes } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'GachaLogService';
const GACHA_HOST: string = 'https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog';
const BEYOND_HOST: string = 'https://public-operation-hk4e.mihoyo.com/gacha_info/api/getBeyondGachaLog';
/** 千星奇域分页大小（对齐 Windows GachaLogTypedQueryOptions.BeyondSize） */
const BEYOND_PAGE_SIZE: number = 5;

export class RefreshResult {
  ok: boolean = false;
  message: string = '';
  fetchedCount: number = 0;
  uid: string = '';
}

export class GachaLogService {
  private static instance: GachaLogService = new GachaLogService();
  private cancelRequested: boolean = false;

  cancelRefresh(): void {
    this.cancelRequested = true;
  }

  static getInstance(): GachaLogService {
    return GachaLogService.instance;
  }

  /**
   * SToken 自动鉴权刷新。
   * @param uid 拉取 UID（默认当前 UID）
   */
  async refreshByStoken(uid: string, onProgress: (p: RefreshProgress) => void, full: boolean = false,
    onlyTypes: number[] | undefined = undefined): Promise<RefreshResult> {
    this.cancelRequested = false;
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    if (user === undefined || user.stoken.length === 0) {
      const r: RefreshResult = new RefreshResult();
      r.ok = false;
      r.message = '请先登录并确保 Cookie 含 SToken';
      return r;
    }
    if (user.isOversea || RegionUtil.regionOfUid(uid).startsWith('os_')) {
      const result: RefreshResult = new RefreshResult();
      result.message = '上游不支持海外 SToken 祈愿鉴权，请使用游戏祈愿记录 URL 导入';
      return result;
    }
    const region: string = RegionUtil.regionOfUid(uid);
    const progress: RefreshProgress = new RefreshProgress();
    progress.running = true;
    progress.sourceText = 'SToken 自动鉴权';
    onProgress(progress);
    progress.reportText = '正在生成 authkey...';
    onProgress(progress);

    const authResp: ApiResponse = await GachaAuthApi.genAuthKey(uid, region, user.stokenCookie());
    if (!authResp.success || authResp.data === undefined) {
      progress.running = false;
      progress.error = authResp.userFriendlyMessage();
      onProgress(progress);
      const r: RefreshResult = new RefreshResult();
      r.ok = false;
      r.message = progress.error;
      return r;
    }
    const authInfo: GachaAuthInfo = GachaAuthApi.parseAuthInfo(authResp.data);
    if (authInfo.authkey.length === 0) {
      progress.running = false;
      progress.error = '鉴权失败：未获取到 authkey';
      onProgress(progress);
      const r: RefreshResult = new RefreshResult();
      r.ok = false;
      r.message = progress.error;
      return r;
    }
    return this.fetchAll(uid, authInfo, onProgress, progress, full, onlyTypes);
  }

  /**
   * 手动 URL 兜底导入。
   */
  async importByUrl(url: string, uid: string, onProgress: (p: RefreshProgress) => void, full: boolean = false,
    onlyTypes: number[] | undefined = undefined): Promise<RefreshResult> {
    this.cancelRequested = false;
    const authInfo: GachaAuthInfo | undefined = GachaAuthApi.parseAuthFromUrl(url);
    if (authInfo === undefined) {
      const r: RefreshResult = new RefreshResult();
      r.ok = false;
      r.message = 'URL 中未解析到有效 authkey';
      return r;
    }
    const progress: RefreshProgress = new RefreshProgress();
    progress.running = true;
    progress.sourceText = '祈愿链接';
    onProgress(progress);
    return this.fetchAll('', authInfo, onProgress, progress, full, onlyTypes);
  }

  private async fetchAll(expectedUid: string, authInfo: GachaAuthInfo,
    onProgress: (p: RefreshProgress) => void, progress: RefreshProgress, full: boolean,
    onlyTypes: number[] | undefined = undefined): Promise<RefreshResult> {
    let archive: GachaArchive | undefined = undefined;
    let actualUid: string = '';
    let totalInserted: number = 0;
    let failure: string = '';
    const allTypes: number[] = onlyTypes !== undefined && onlyTypes.length > 0
      ? onlyTypes.slice()
      : GachaType.QUERY_ORDER;
    for (const gachaType of allTypes) {
      const isBeyond: boolean = GachaType.isBeyond(gachaType);
      const poolName: string = GachaType.nameOf(gachaType);
      // UX07 池级明细：新增/跳过重复/失败原因逐池可辨
      const outcome: PoolOutcome = new PoolOutcome();
      outcome.gachaType = gachaType;
      outcome.name = poolName;
      progress.pools.push(outcome);
      try {
        const existingRecords: Map<string, GachaItem> = new Map<string, GachaItem>();
        let newestStoredId: string = archive !== undefined && !full
          ? await GachaLogService.readStoredWatermark(archive.id, gachaType, existingRecords) : '0';
        const fresh: GachaItem[] = [];
        const fetchedRecords: Map<string, GachaItem> = new Map<string, GachaItem>();
        let endId: string = '0';
        progress.currentPoolName = poolName;
        for (let page: number = 0; page < 999; page++) {
          if (this.cancelRequested) {
            failure = '已取消刷新';
            break;
          }
          progress.reportText = `正在拉取：${poolName}`;
          onProgress(progress);
          const resp: ApiResponse = await this.fetchPage(authInfo, gachaType, endId, isBeyond);
          if (!resp.success) {
            Logger.warn(TAG, `wish request failed pool=${gachaType} page=${page + 1} retcode=${resp.retcode}`);
            failure = `${poolName}：${GachaAuthApiError(resp)}`;
            break;
          }
          let items: GachaItem[];
          try {
            items = this.parseList(resp.data, isBeyond);
          } catch (error) {
            failure = `${poolName}：${(error as Error).message}，未保存本页`;
            break;
          }
          if (items.length === 0) {
            break;
          }
          // 响应UID是唯一归档依据。手工URL不借用已登录账号UID。
          const pageUid: string = items[0].uid;
          if (!/^[1-9][0-9]{8,9}$/.test(pageUid)
            || (expectedUid.length > 0 && pageUid !== expectedUid)
            || (actualUid.length > 0 && pageUid !== actualUid)
            || items.some((item: GachaItem): boolean => item.uid !== pageUid)) {
            failure = `${poolName}：接口 UID 与归档不一致，未保存本页`;
            break;
          }
          if (items.some((item: GachaItem): boolean => GachaType.queryTypeOf(item.gachaType) !== gachaType)) {
            failure = `${poolName}：接口记录不属于请求卡池，未保存本页`;
            break;
          }
          if (archive === undefined) {
            actualUid = pageUid;
            progress.uid = pageUid;
            archive = await GachaRepo.getOrCreateArchive(actualUid);
            if (!full) { newestStoredId = await GachaLogService.readStoredWatermark(archive.id, gachaType, existingRecords); }
          }
          await GachaItemIdentityService.resolveMissing(items, authInfo.lang);
          let reachedWatermark: boolean = false;
          const pageItems: GachaItem[] = [];
          for (const item of items) {
            const key: string = GachaItem.recordKey(item);
            const fetched: GachaItem | undefined = fetchedRecords.get(key);
            if (fetched !== undefined) {
              fetchedRecords.set(key, GachaItem.mergeRecord(fetched, item, `UID ${pageUid}`));
              continue;
            }
            fetchedRecords.set(key, item);
            if (!full && GachaItem.compareIds(item.gachaId, newestStoredId) <= 0) {
              reachedWatermark = true;
              const stored: GachaItem | undefined = existingRecords.get(key);
              if (stored !== undefined) {
                GachaItem.mergeRecord(stored, item, `UID ${pageUid}`);
                outcome.duplicates++;
              }
              continue;
            }
            item.archiveId = archive.id;
            pageItems.push(item);
          }
          const invalid: GachaItem | undefined = pageItems.find(
            (item: GachaItem): boolean => !Number.isSafeInteger(item.itemId) || item.itemId <= 0);
          if (invalid !== undefined) {
            failure = `${poolName}：记录 ${invalid.gachaId} 的物品 ID（item_id=${invalid.itemId}）无法确定，未保存本页`;
            break;
          }
          if (this.cancelRequested) {
            failure = '已取消刷新';
            break;
          }
          for (const item of pageItems) {
            fresh.push(item);
            if (progress.recentItems.length < 40) {
              const recent: RecentGachaItem = new RecentGachaItem();
              recent.itemId = item.itemId;
              recent.name = item.name;
              recent.itemType = item.itemType;
              recent.rank = item.rankType;
              recent.count = item.count;
              progress.recentItems.push(recent);
            }
          }
          progress.fetchedCount = totalInserted + fresh.length;
          onProgress(progress);
          const next: string = items[items.length - 1].gachaId;
          if (reachedWatermark || items.length < (isBeyond ? BEYOND_PAGE_SIZE : AppConstants.GACHA_PAGE_SIZE)) {
            break;
          }
          if (endId !== '0' && GachaItem.compareIds(next, endId) >= 0) {
            failure = `${poolName}：分页游标没有前进，已停止`;
            break;
          }
          endId = next;
          await this.delay();
        }
        // 全量失败/取消也只覆盖已验证返回的窗口，窗口外旧历史不受影响。
        const inserted: number = full ? await GachaRepo.replaceFetchedWindow(fresh, gachaType) : await GachaRepo.insertItems(fresh);
        outcome.inserted = inserted;
        totalInserted += inserted;
        if (failure.length > 0) {
          outcome.failed = true;
          outcome.errorText = failure;
          Logger.warn(TAG, `wish refresh stopped pool=${gachaType} saved=${inserted}`);
          break;
        }
        await this.delay();
      } catch (error) {
        failure = `${poolName}：${(error as Error).message}`;
        outcome.failed = true;
        outcome.errorText = failure;
        Logger.warn(TAG, `wish refresh stopped pool=${gachaType}: ${(error as Error).message}`);
        break;
      }
    }
    if (archive !== undefined) {
      await GachaRepo.selectArchive(archive.id);
    }
    const result: RefreshResult = new RefreshResult();
    result.uid = actualUid;
    result.ok = failure.length === 0;
    result.fetchedCount = totalInserted;
    result.message = failure.length > 0 ? `已保存 ${totalInserted} 条记录；${failure}`
      : `刷新完成：写入 ${totalInserted} 条记录`;
    progress.running = false;
    progress.done = result.ok;
    progress.error = failure;
    progress.fetchedCount = totalInserted;
    progress.reportText = result.message;
    onProgress(progress);
    return result;
  }

  private static async readStoredWatermark(archiveId: number, gachaType: number,
    existingRecords: Map<string, GachaItem>): Promise<string> {
    let newest: string = '0';
    const stored: GachaItem[] = await GachaItemIdentityService.resolveMissing(await GachaRepo.getItemsByType(archiveId, gachaType));
    for (const item of stored) {
      existingRecords.set(GachaItem.recordKey(item), item);
      if (GachaItem.compareIds(item.gachaId, newest) > 0) { newest = item.gachaId; }
    }
    return newest;
  }

  private async fetchPage(authInfo: GachaAuthInfo, gachaType: number, endId: string, isBeyond: boolean = false): Promise<ApiResponse> {
    const cnHost: string = isBeyond ? BEYOND_HOST : GACHA_HOST;
    const host: string = authInfo.isOversea
      ? cnHost.replace('public-operation-hk4e.mihoyo.com', 'public-operation-hk4e-sg.hoyoverse.com') : cnHost;
    const size: number = isBeyond ? BEYOND_PAGE_SIZE : AppConstants.GACHA_PAGE_SIZE;
    const url: string = `${host}?lang=${authInfo.lang}&auth_appid=${AppConstants.GACHA_AUTH_APPID}` +
      `&authkey=${encodeURIComponent(authInfo.authkey)}&authkey_ver=${authInfo.authkeyVer}` +
      `&sign_type=${authInfo.signType}&gacha_type=${gachaType}&size=${size}&end_id=${endId}`;
    const headers: Record<string, string> = { 'User-Agent': AppConstants.UA_MOBILE, 'Referer': 'https://webstatic.mihoyo.com/' };
    // 网络抖动/瞬时错误：单页最多重试 2 次（仅网络类错误重试；authkey 失效/风控不重试以免浪费时间）
    for (let attempt: number = 0; attempt < 3; attempt++) {
      const resp: ApiResponse = await ApiClient.getInstance().get(url, headers);
      if (resp.success) {
        return resp;
      }
      // retcode == -2 由 ApiClient 网络异常归一化产生；HTTP 5xx 映射为 -1/-2 也重试
      if ((resp.retcode === -2 || resp.retcode === -1) && attempt < 2) {
        await this.delay();
        continue;
      }
      return resp;
    }
    throw new Error('祈愿请求重试已结束');
  }

  private parseList(data: Object | undefined, isBeyond: boolean = false): GachaItem[] {
    if (data === undefined || data === null || typeof data !== 'object' || Array.isArray(data)) {
      throw new Error('祈愿接口响应缺少有效数据');
    }
    const obj = data as Record<string, Object>;
    if (!Array.isArray(obj['list'])) { throw new Error('祈愿接口响应缺少记录列表'); }
    const list: Object[] = obj['list'] as Object[];
    const items: GachaItem[] = [];
    for (let i = 0; i < list.length; i++) {
      const raw: Object = list[i];
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
        throw new Error(`第 ${i + 1} 条祈愿记录格式无效`);
      }
      const id: Object | undefined = (raw as Record<string, Object>)['id'];
      const cursor: string = String(id ?? '');
      if ((typeof id !== 'string' && typeof id !== 'number') || !/^[0-9]+$/.test(cursor) ||
        (typeof id === 'number' && !Number.isSafeInteger(id)) || GachaItem.compareIds(cursor, '0') <= 0 ||
        GachaItem.compareIds(cursor, GachaItem.MAX_SIGNED_ID) > 0) {
        throw new Error(`第 ${i + 1} 条祈愿记录 ID 无效`);
      }
      const item: GachaItem = GachaItem.fromServer(raw, isBeyond);
      item.gachaId = GachaItem.decimalId(item.gachaId);
      items.push(item);
    }
    return items;
  }

  private async delay(): Promise<void> {
    const min: number = AppConstants.GACHA_DELAY_MIN;
    const max: number = AppConstants.GACHA_DELAY_MAX;
    const ms: number = min + Math.floor(Math.random() * (max - min));
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}

function GachaAuthApiError(resp: ApiResponse): string {
  if (resp.retcode === RetCodes.RISK_CONTROL) {
    return '被风控拦截，请稍后再试';
  }
  if (resp.retcode === -101 || resp.retcode === 10201 || resp.retcode === -100) {
    return 'authkey 已失效或超时，请重新刷新';
  }
  return resp.userFriendlyMessage();
}
