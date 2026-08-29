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

export class RefreshResult {
  ok: boolean = false;
  message: string = '';
  fetchedCount: number = 0;
}

export class GachaLogService {
  private static instance: GachaLogService = new GachaLogService();

  static getInstance(): GachaLogService {
    return GachaLogService.instance;
  }

  /**
   * SToken 自动鉴权刷新。
   * @param uid 拉取 UID（默认当前 UID）
   */
  async refreshByStoken(uid: string, onProgress: (p: RefreshProgress) => void): Promise<RefreshResult> {
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    if (user === undefined || user.stoken.length === 0) {
      const r: RefreshResult = new RefreshResult();
      r.ok = false;
      r.message = '请先登录并确保 Cookie 含 SToken';
      return r;
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
    return this.fetchAll(uid, authInfo, onProgress, progress);
  }

  /**
   * 手动 URL 兜底导入。
   */
  async importByUrl(url: string, uid: string, onProgress: (p: RefreshProgress) => void): Promise<RefreshResult> {
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
    return this.fetchAll(uid, authInfo, onProgress, progress);
  }

  private async fetchAll(uid: string, authInfo: GachaAuthInfo,
    onProgress: (p: RefreshProgress) => void, progress: RefreshProgress): Promise<RefreshResult> {
    // 归档
    const archive: GachaArchive = await GachaRepo.getOrCreateArchive(uid);
    await GachaRepo.selectArchive(archive.id);

    let totalFetched: number = 0;
    let aborted: boolean = false;
    let abortMsg: string = '';

    for (let i = 0; i < GachaType.QUERY_ORDER.length; i++) {
      const gachaType: number = GachaType.QUERY_ORDER[i];
      const poolName: string = GachaType.nameOf(gachaType);
      progress.currentPoolName = poolName;
      progress.reportText = `正在拉取：${poolName}`;
      onProgress(progress);

      // 已有游标集合（Lazy 去重）
      const existingIds: Set<string> = new Set<string>();
      const ids: string[] = await GachaRepo.getAllGachaIds(archive.id, gachaType);
      for (let j = 0; j < ids.length; j++) {
        existingIds.add(ids[j]);
      }

      let endId: string = '';
      const newItems: GachaItem[] = [];
      let pageGuard: number = 0;
      while (true) {
        pageGuard++;
        if (pageGuard > 999) {
          break; // 安全上限
        }
        const resp: ApiResponse = await this.fetchPage(authInfo, gachaType, endId);
        if (!resp.success) {
          // authkey 失效/风控：中止
          aborted = true;
          abortMsg = GachaAuthApiError(resp);
          progress.error = abortMsg;
          progress.reportText = `拉取中止：${abortMsg}`;
          onProgress(progress);
          break;
        }
        const list: GachaItem[] = this.parseList(resp.data);
        if (list.length === 0) {
          break;
        }
        for (let k = 0; k < list.length; k++) {
          const item: GachaItem = list[k];
          item.archiveId = archive.id;
          if (!existingIds.has(item.gachaId)) {
            newItems.push(item);
            existingIds.add(item.gachaId);
            // 收集新拉记录（最近 40 条，供 UI 头像流展示）
            if (progress.recentItems.length < 40) {
              const ri: RecentGachaItem = new RecentGachaItem();
              ri.name = item.name;
              ri.itemType = item.itemType;
              ri.rank = item.rankType;
              ri.count = item.count;
              progress.recentItems.push(ri);
            }
          }
        }
        totalFetched += list.length;
        progress.fetchedCount = totalFetched;
        progress.reportText = `${poolName}：已拉取 ${totalFetched} 条`;
        onProgress(progress);

        // 翻页
        if (list.length < AppConstants.GACHA_PAGE_SIZE) {
          break;
        }
        endId = list[list.length - 1].gachaId;
        if (endId.length === 0) {
          break;
        }
        // 防封延时
        await this.delay();
      }

      // 写入本池新增
      if (newItems.length > 0) {
        await GachaRepo.insertItems(newItems);
        Logger.info(TAG, `pool ${gachaType} inserted ${newItems.length} new`);
      }
      if (aborted) {
        break;
      }
      // 池间也延时
      await this.delay();
    }

    progress.done = true;
    progress.running = false;
    if (aborted) {
      progress.reportText = `已保存部分数据（${totalFetched} 条），${abortMsg}`;
      onProgress(progress);
      const r: RefreshResult = new RefreshResult();
      r.ok = false;
      r.message = progress.reportText;
      r.fetchedCount = totalFetched;
      return r;
    }
    progress.reportText = `刷新完成：共拉取 ${totalFetched} 条，已去重合并`;
    onProgress(progress);
    const r: RefreshResult = new RefreshResult();
    r.ok = true;
    r.message = progress.reportText;
    r.fetchedCount = totalFetched;
    return r;
  }

  private async fetchPage(authInfo: GachaAuthInfo, gachaType: number, endId: string): Promise<ApiResponse> {
    let url: string = `${GACHA_HOST}?lang=${authInfo.lang}&auth_appid=${AppConstants.GACHA_AUTH_APPID}` +
      `&authkey=${encodeURIComponent(authInfo.authkey)}&authkey_ver=${authInfo.authkeyVer}` +
      `&sign_type=${authInfo.signType}&gacha_type=${gachaType}&size=${AppConstants.GACHA_PAGE_SIZE}`;
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

  private parseList(data: Object | undefined): GachaItem[] {
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
      const it: GachaItem = GachaItem.fromServer(list[i]);
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
