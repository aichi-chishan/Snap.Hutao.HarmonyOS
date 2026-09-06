/**
 * LedgerService.ets
 * 旅行者札记（月历）服务（对齐 Windows GameRecordClient.GetLedgerAsync）：
 *   GET hk4e-api.mihoyo.com/event/ys_ledger/monthInfo?month&bind_uid&bind_region&bbs_*&utm_*
 *   Cookie(cookie_token) + DS Gen2/X4（query 参签）+ Referer(webstatic)
 */
import { Ledger } from '../model/Ledger';
import { ApiResponse } from '../model/ApiResponse';
import { ApiClient } from '../data/network/ApiClient';
import { AppConstants, RegionUtil } from '../common/Constants';
import { DsSigner } from '../data/network/DsSigner';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { User } from '../model/User';
import { UserService } from './UserService';
import { Logger } from '../common/Logger';

const TAG: string = 'LedgerService';
const LEDGER_URL: string = 'https://hk4e-api.mihoyo.com/event/ys_ledger/monthInfo';

export class LedgerService {
  private static instance: LedgerService = new LedgerService();

  static getInstance(): LedgerService {
    return LedgerService.instance;
  }

  /** 拉取某月札记（month=0 为当月） */
  async fetchMonth(month: number, uid: string): Promise<Ledger> {
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    if (user.cookieToken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(user);
    }
    const region: string = RegionUtil.regionOfUid(uid);

    const query: Record<string, string> = {
      'month': `${month}`,
      'bind_uid': uid,
      'bind_region': region,
      'bbs_presentation_style': 'fullscreen',
      'bbs_auth_required': 'true',
      'utm_source': 'bbs',
      'utm_medium': 'mys',
      'utm_campaign': 'icon',
    };
    const sorted: string = DsSigner.sortQuery(query);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, '', sorted);
    const url: string = `${LEDGER_URL}?${sorted}`;
    const headers: Record<string, string> = {
      'DS': ds,
      'Cookie': user.gameRecordCookie(),
      'Referer': 'https://webstatic.mihoyo.com/',
    };

    let resp: ApiResponse = await ApiClient.getInstance().get(url,
      HoyolabClient.merge(headers, HoyolabClient.getBaseHeaders()));
    if (resp.isRiskControl()) {
      const challenge: string = await RiskVerifier.tryResolveRisk(resp, user.gameRecordCookie(), 'event/ys_ledger/monthInfo');
      if (challenge.length > 0) {
        headers['x-rpc-challenge'] = challenge;
        resp = await ApiClient.getInstance().get(url,
          HoyolabClient.merge(headers, HoyolabClient.getBaseHeaders()));
      } else {
        throw new Error('人机验证未完成或被取消，请稍后再试');
      }
    }
    // Cookie 鉴权失效（-100/10001）：强制换新凭证后重试一次（对齐 Windows CookieToken 刷新）
    if (!resp.success && UserService.isCookieAuthError(resp)) {
      resp = await UserService.retryWithRefreshedCookie(user, (): Promise<ApiResponse> => {
        const retryHeaders: Record<string, string> = {
          'DS': headers['DS'],
          'Cookie': user.gameRecordCookie(),
          'Referer': 'https://webstatic.mihoyo.com/',
        };
        return ApiClient.getInstance().get(url,
          HoyolabClient.merge(retryHeaders, HoyolabClient.getBaseHeaders()));
      });
    }
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const ledger: Ledger = Ledger.fromJson(resp.data);
    Logger.info(TAG, `ledger month=${ledger.month} primogems=${ledger.monthData.currentPrimogems} mora=${ledger.monthData.currentMora}`);
    return ledger;
  }
}
