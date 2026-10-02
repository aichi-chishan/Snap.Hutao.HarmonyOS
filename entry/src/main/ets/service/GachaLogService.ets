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
import { RefreshProgress, RecentGachaItem } from '../model/RefreshProgress';
import { User } from '../model/User';
import { UserService } from './UserService';
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
  async refreshByStoken(uid: string, onProgress: (p: RefreshProgress) => void, full: boolean = false): Promise<RefreshResult> {
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
    return this.fetchAll(uid, authInfo, onProgress, progress, full);
  }

  /**
   * 手动 URL 兜底导入。
   */
  async importByUrl(url: string, uid: string, onProgress: (p: RefreshProgress) => void, full: boolean = false): Promise<RefreshResult> {
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
    onProgress(progress);
    return this.fetchAll('', authInfo, onProgress, progress, full);
  }

  private async fetchAll(expectedUid: string, authInfo: GachaAuthInfo,
    onProgress: (p: RefreshProgress) => void, progress: RefreshProgress, full: boolean): Promise<RefreshResult> {
    let archive: GachaArchive | undefined = undefined;
    let actualUid: string = '';
    let totalInserted: number = 0;
    let failure: string = '';
    const allTypes: number[] = GachaType.QUERY_ORDER.concat(GachaType.BEYOND_ORDER);
    for (const gachaType of allTypes) {
      const isBeyond: boolean = GachaType.isBeyond(gachaType);
      const poolName: string = GachaType.nameOf(gachaType);
      const existingIds: Set<string> = new Set<string>();
      if (archive !== undefined) {
        for (const id of await GachaRepo.getAllGachaIds(archive.id, gachaType)) {
          existingIds.add(id);
        }
      }
      const fresh: GachaItem[] = [];
      const fetchedIds: Set<string> = new Set<string>();
      let endId: string = '';
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
          failure = `${poolName}：${GachaAuthApiError(resp)}`;
          break;
        }
        const items: GachaItem[] = this.parseList(resp.data, isBeyond);
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
        if (archive === undefined) {
          actualUid = pageUid;
          archive = await GachaRepo.getOrCreateArchive(actualUid);
          for (const id of await GachaRepo.getAllGachaIds(archive.id, gachaType)) {
            existingIds.add(id);
          }
        }
        let reachedExisting: boolean = false;
        for (const item of items) {
          if (existingIds.has(item.gachaId)) {
            reachedExisting = true;
            if (!full) {
              continue;
            }
          }
          if (fetchedIds.has(item.gachaId)) {
            continue;
          }
          fetchedIds.add(item.gachaId);
          item.archiveId = archive.id;
          fresh.push(item);
          existingIds.add(item.gachaId);
          if (progress.recentItems.length < 40) {
            const recent: RecentGachaItem = new RecentGachaItem();
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
        if ((!full && reachedExisting) || items.length < (isBeyond ? BEYOND_PAGE_SIZE : AppConstants.GACHA_PAGE_SIZE)) {
          break;
        }
        if (next.length === 0 || next === endId) {
          failure = `${poolName}：分页游标没有前进，已停止`;
          break;
        }
        endId = next;
        await this.delay();
      }
      // 全量失败/取消也只覆盖已验证返回的窗口，窗口外旧历史不受影响。
      totalInserted += full ? await GachaRepo.replaceFetchedWindow(fresh, gachaType) : await GachaRepo.insertItems(fresh);
      if (failure.length > 0) {
        break;
      }
      await this.delay();
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

  private async fetchPage(authInfo: GachaAuthInfo, gachaType: number, endId: string, isBeyond: boolean = false): Promise<ApiResponse> {
    const cnHost: string = isBeyond ? BEYOND_HOST : GACHA_HOST;
    const host: string = authInfo.isOversea
      ? cnHost.replace('public-operation-hk4e.mihoyo.com', 'public-operation-hk4e-sg.hoyoverse.com') : cnHost;
    const size: number = isBeyond ? BEYOND_PAGE_SIZE : AppConstants.GACHA_PAGE_SIZE;
    let url: string = `${host}?lang=${authInfo.lang}&auth_appid=${AppConstants.GACHA_AUTH_APPID}` +
      `&authkey=${encodeURIComponent(authInfo.authkey)}&authkey_ver=${authInfo.authkeyVer}` +
      `&sign_type=${authInfo.signType}&gacha_type=${gachaType}&size=${size}`;
    if (endId.length > 0) {
      url += `&end_id=${endId}`;
    }
    const headers: Record<string, string> = { 'User-Agent': AppConstants.UA_MOBILE, 'Referer': 'https://webstatic.mihoyo.com/' };
    // 网络抖动/瞬时错误：单页最多重试 2 次（仅网络类错误重试；authkey 失效/风控不重试以免浪费时间）
    for (let attempt = 0; attempt < 3; attempt++) {
      const resp: ApiResponse = await ApiClient.getInstance().get(url, headers);
      if (resp.success) {
        return resp;
      }
      // retcode == -2 由 ApiClient 网络异常归一化产生；HTTP 5xx 映射为 -1/-2 也重试
      if (resp.retcode === -2 || resp.retcode === -1) {
        await this.delay();
        continue;
      }
      return resp;
    }
    return ApiClient.getInstance().get(url, headers);
  }

  private parseList(data: Object | undefined, isBeyond: boolean = false): GachaItem[] {
    if (data === undefined) {
      return [];
    }
    const obj = data as Record<string, Object>;
    const list = obj['list'] as Array<Object>;
    const items: GachaItem[] = [];
    if (list === undefined || list === null) {
      return items;
    }
    for (let i = 0; i < list.length; i++) {
      const it: GachaItem = GachaItem.fromServer(list[i], isBeyond);
      if (it.gachaId.length > 0) {
        items.push(it);
      }
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
