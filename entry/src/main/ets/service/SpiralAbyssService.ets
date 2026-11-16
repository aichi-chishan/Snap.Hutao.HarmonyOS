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
import { HoyolabEndpoints } from '../common/HoyolabEndpoints';
import { Logger } from '../common/Logger';
import { ChallengeSession, ChallengeVerificationCancelled } from './ChallengeSession';

const TAG: string = 'SpiralAbyssService';
const API_PATH: string = 'spiralAbyss';

export class SpiralAbyssService {
  private static instance: SpiralAbyssService = new SpiralAbyssService();

  static getInstance(): SpiralAbyssService {
    return SpiralAbyssService.instance;
  }

  /** 拉取深渊数据（scheduleType：1=当期，2=上期）
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头） */
  async fetch(uid: string, scheduleType: number, challenge?: string): Promise<SpiralAbyssData> {
    const session: ChallengeSession = ChallengeSession.require(uid);
    const region: string = session.region;
    const cookie: string = await session.gameRecordCookie();
    const query: Record<string, string> = {
      'schedule_type': `${scheduleType}`,
      'role_id': uid,
      'server': region,
    };
    const sorted: string = DsSigner.sortQuery(query);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(HoyolabEndpoints.gameRecordSalt(region), t, r, '', sorted);
    const url: string = `${HoyolabEndpoints.gameRecordUrl(API_PATH, region)}?${sorted}`;
    const headers: Record<string, string> = { 'DS': ds, 'Cookie': cookie };
    if (challenge !== undefined && challenge.length > 0) {
      headers['x-rpc-challenge'] = challenge;
    }
    session.assertCurrent();
    const resp0: ApiResponse = await ApiClient.getInstance().get(url,
      HoyolabClient.merge(HoyolabClient.getBaseHeaders(region), headers));
    session.assertCurrent();
    let resp: ApiResponse = resp0;
    if (resp0.isRiskControl()) {
      // 1034：自动弹统一验证窗，成功后带 challenge 服务内重放一次
      const replayChallenge: string = await RiskVerifier.tryResolveRisk(resp0, cookie, url);
      if (replayChallenge.length === 0) {
        throw new ChallengeVerificationCancelled();
      }
      headers['x-rpc-challenge'] = replayChallenge;
      session.assertCurrent();
      resp = await ApiClient.getInstance().get(url,
        HoyolabClient.merge(HoyolabClient.getBaseHeaders(region), headers));
      session.assertCurrent();
    }
    // Cookie 鉴权失效（-100/10001）：强制换新凭证后重试一次（对齐 Windows CookieToken 刷新）
    if (!resp.success && UserService.isCookieAuthError(resp)) {
      resp = await UserService.retryWithRefreshedCookie(session.user, async (): Promise<ApiResponse> => {
        const retryHeaders: Record<string, string> = {
          'Cookie': session.user.gameRecordCookie(),
          'DS': await DsSigner.signGen2(HoyolabEndpoints.gameRecordSalt(region),
            DsSigner.nowTimestamp(), DsSigner.randomNumber(), '', sorted),
        };
        if (headers['x-rpc-challenge'] !== undefined) {
          retryHeaders['x-rpc-challenge'] = headers['x-rpc-challenge'];
        }
        session.assertCurrent();
        return ApiClient.getInstance().get(url,
          HoyolabClient.merge(HoyolabClient.getBaseHeaders(region), retryHeaders));
      });
    }
    session.assertCurrent();
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const data: SpiralAbyssData = SpiralAbyssData.fromJson(resp.data);
    data.rawJson = JSON.stringify(resp.data);
    Logger.info(TAG, `abyss schedule=${scheduleType} star=${data.totalStar} floor=${data.maxFloor}`);
    return data;
  }
}
