/**
 * SpiralAbyssService.ets
 * 深境螺旋：GET spiralAbyss?schedule_type=1/2&role_id&server，DS Gen2/X4，Cookie(cookie_token+ltoken)。
 * 参考 Windows 版 GameRecordClient.GetSpiralAbyssAsync（CN XRpc 头）。
 */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { DsSigner } from '../data/network/DsSigner';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { SpiralAbyssData } from '../model/SpiralAbyss';
import { UserService } from './UserService';
import { RegionUtil, AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'SpiralAbyssService';
const URL: string = 'https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/spiralAbyss';

export class SpiralAbyssService {
  private static instance: SpiralAbyssService = new SpiralAbyssService();

  static getInstance(): SpiralAbyssService {
    return SpiralAbyssService.instance;
  }

  /** 拉取深渊数据（scheduleType：1=当期，2=上期）
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头） */
  async fetch(uid: string, scheduleType: number, challenge?: string): Promise<SpiralAbyssData> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(user);
    }
    const region: string = RegionUtil.regionOfUid(uid);
    const cookie: string = user.gameRecordCookie();
    if (cookie.length === 0) {
      throw new Error('账号缺少 cookie_token，请重新登录');
    }
    const query: Record<string, string> = {
      'schedule_type': `${scheduleType}`,
      'role_id': uid,
      'server': region,
    };
    const sorted: string = DsSigner.sortQuery(query);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, '', sorted);
    const url: string = `${URL}?${sorted}`;
    const headers: Record<string, string> = { 'DS': ds, 'Cookie': cookie };
    if (challenge !== undefined && challenge.length > 0) {
      headers['x-rpc-challenge'] = challenge;
    }
    const resp0: ApiResponse = await ApiClient.getInstance().get(url,
      HoyolabClient.merge(HoyolabClient.getBaseHeaders(), headers));
    let resp: ApiResponse = resp0;
    if (resp0.isRiskControl()) {
      // 1034：自动弹统一验证窗，成功后带 challenge 服务内重放一次
      const replayChallenge: string = await RiskVerifier.tryResolveRisk(resp0, cookie, url);
      if (replayChallenge.length === 0) {
        throw new Error('人机验证未完成或被取消，请稍后再试');
      }
      headers['x-rpc-challenge'] = replayChallenge;
      resp = await ApiClient.getInstance().get(url,
        HoyolabClient.merge(HoyolabClient.getBaseHeaders(), headers));
    }
    // Cookie 鉴权失效（-100/10001）：强制换新凭证后重试一次（对齐 Windows CookieToken 刷新）
    if (!resp.success && UserService.isCookieAuthError(resp)) {
      resp = await UserService.retryWithRefreshedCookie(user, (): Promise<ApiResponse> => {
        const retryHeaders: Record<string, string> = { 'Cookie': user.gameRecordCookie() };
        if (headers['x-rpc-challenge'] !== undefined) {
          retryHeaders['x-rpc-challenge'] = headers['x-rpc-challenge'];
        }
        retryHeaders['DS'] = headers['DS'];
        return ApiClient.getInstance().get(url,
          HoyolabClient.merge(HoyolabClient.getBaseHeaders(), retryHeaders));
      });
    }
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const data: SpiralAbyssData = SpiralAbyssData.fromJson(resp.data);
    data.rawJson = resp.raw;
    Logger.info(TAG, `abyss schedule=${scheduleType} star=${data.totalStar} floor=${data.maxFloor}`);
    return data;
  }
}
