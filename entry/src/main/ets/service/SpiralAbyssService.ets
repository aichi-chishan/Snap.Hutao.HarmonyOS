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
    const resp: ApiResponse = await ApiClient.getInstance().get(url,
      HoyolabClient.merge(HoyolabClient.getBaseHeaders(), headers));
    if (resp.isRiskControl()) {
      await RiskVerifier.checkForRisk(resp, cookie, url);
    }
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const data: SpiralAbyssData = SpiralAbyssData.fromJson(resp.data);
    Logger.info(TAG, `abyss schedule=${scheduleType} star=${data.totalStar} floor=${data.maxFloor}`);
    return data;
  }
}
