/**
 * MiyoliveService.ets
 * 前瞻直播兑换码：米游社 home/new 找直播地址 → 提取 act_id → miyolive refreshCode 拉取兑换码。
 * 对齐 Windows AnnouncementViewModel 直播兑换码链路（MiyoliveClient.RefreshCodeAsync），无需登录。
 */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { MiyoliveCode } from '../model/MiyoliveCode';
import { AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'MiyoliveService';
const HOME_NEW_URL: string = 'https://bbs-api.miyoushe.com/apihub/api/home/new?gids=2';
const REFRESH_CODE_URL: string = 'https://api-takumi-static.mihoyo.com/event/miyolive/refreshCode';

export class MiyoliveService {
  private static instance: MiyoliveService = new MiyoliveService();

  static getInstance(): MiyoliveService {
    return MiyoliveService.instance;
  }

  /**
   * 拉取当前前瞻直播兑换码列表（无需登录）。
   * 任一环节失败返回空数组（对齐 Windows：拿不到就不显示入口）。
   */
  async fetchRedeemCodes(): Promise<MiyoliveCode[]> {
    const actId: string = await this.resolveActId();
    if (actId.length === 0) {
      Logger.info(TAG, 'no live act_id (no ongoing preview live)');
      return [];
    }
    try {
      const url: string = `${REFRESH_CODE_URL}?time=${Math.floor(Date.now() / 1000)}`;
      const headers: Record<string, string> = {
        'User-Agent': AppConstants.UA_BBS,
        'Accept': 'application/json',
        'x-rpc-act_id': actId,
      };
      const resp: ApiResponse = await ApiClient.getInstance().get(url, headers);
      if (!resp.success || resp.data === undefined) {
        Logger.warn(TAG, `refreshCode fail retcode=${resp.retcode}`);
        return [];
      }
      const data = resp.data as Record<string, Object>;
      const codeList = data['code_list'] as Array<Object>;
      const codes: MiyoliveCode[] = [];
      if (codeList !== undefined && codeList !== null) {
        for (let i = 0; i < codeList.length; i++) {
          const c: MiyoliveCode = MiyoliveCode.fromJson(codeList[i]);
          if (c.code.length > 0) {
            codes.push(c);
          }
        }
      }
      Logger.info(TAG, `redeem codes ${codes.length}`);
      return codes;
    } catch (e) {
      Logger.warn(TAG, `refreshCode error: ${(e as Error).message}`);
      return [];
    }
  }

  /**
   * 从米游社 home/new 定位直播地址并提取 act_id：
   * 优先 lives[0].data.live_url，其次 navigator 名为"直播兑换码/前瞻直播"的 app_path。
   * act_id 提取正则对齐 Windows ActIdExtractor：act_id=(.*?)&
   */
  private async resolveActId(): Promise<string> {
    try {
      const headers: Record<string, string> = { 'User-Agent': AppConstants.UA_BBS, 'Accept': 'application/json' };
      const resp: ApiResponse = await ApiClient.getInstance().get(HOME_NEW_URL, headers);
      if (!resp.success || resp.data === undefined) {
        Logger.warn(TAG, `home/new fail retcode=${resp.retcode}`);
        return '';
      }
      const data = resp.data as Record<string, Object>;
      // 1) lives[0].data.live_url
      const lives = data['lives'] as Array<Object>;
      if (lives !== undefined && lives !== null && lives.length > 0) {
        const live = lives[0] as Record<string, Object>;
        const liveData = live['data'] as Record<string, Object>;
        if (liveData !== undefined && liveData !== null) {
          const liveUrl: string = String(liveData['live_url'] ?? '');
          const actId: string = MiyoliveService.extractActId(liveUrl);
          if (actId.length > 0) {
            return actId;
          }
        }
      }
      // 2) navigator 名为 直播兑换码 / 前瞻直播 的 app_path
      const navigator = data['navigator'] as Array<Object>;
      if (navigator !== undefined && navigator !== null) {
        for (let i = 0; i < navigator.length; i++) {
          const nav = navigator[i] as Record<string, Object>;
          const name: string = String(nav['name'] ?? '');
          if (name === '直播兑换码' || name === '前瞻直播') {
            const actId: string = MiyoliveService.extractActId(String(nav['app_path'] ?? ''));
            if (actId.length > 0) {
              return actId;
            }
          }
        }
      }
      return '';
    } catch (e) {
      Logger.warn(TAG, `resolveActId error: ${(e as Error).message}`);
      return '';
    }
  }

  /** act_id=(.*?)& 提取（末尾无 & 时取到串尾） */
  private static extractActId(url: string): string {
    if (url.length === 0) {
      return '';
    }
    const key: string = 'act_id=';
    const start: number = url.indexOf(key);
    if (start < 0) {
      return '';
    }
    let value: string = url.substring(start + key.length);
    const amp: number = value.indexOf('&');
    if (amp >= 0) {
      value = value.substring(0, amp);
    }
    return value;
  }
}
