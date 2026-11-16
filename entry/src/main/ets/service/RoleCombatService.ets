/**
 * RoleCombatService.ets
 * 幻象真境剧诗/幽境危战：GET role_combat?role_id&server&need_detail=true&active=1，
 * DS Gen2/X4，Cookie(cookie_token+ltoken)。参考 Windows GameRecordClient.GetRoleCombatAsync。
 */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { DsSigner } from '../data/network/DsSigner';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { RoleCombatRoot } from '../model/RoleCombat';
import { UserService } from './UserService';
import { HoyolabEndpoints } from '../common/HoyolabEndpoints';
import { Logger } from '../common/Logger';
import { ChallengeSession } from './ChallengeSession';

const TAG: string = 'RoleCombatService';
const API_PATH: string = 'role_combat';

export class RoleCombatService {
  private static instance: RoleCombatService = new RoleCombatService();

  static getInstance(): RoleCombatService {
    return RoleCombatService.instance;
  }

  /** 拉取剧诗数据
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头） */
  async fetch(uid: string, challenge?: string): Promise<RoleCombatRoot> {
    const session: ChallengeSession = ChallengeSession.require(uid);
    const region: string = session.region;
    const cookie: string = await session.gameRecordCookie();
    const query: Record<string, string> = {
      'role_id': uid,
      'server': region,
      'need_detail': 'true',
      'active': '1',
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
        throw new Error('人机验证未完成或被取消，请稍后再试');
      }
      headers['x-rpc-challenge'] = replayChallenge;
      session.assertCurrent();
      resp = await ApiClient.getInstance().get(url,
        HoyolabClient.merge(HoyolabClient.getBaseHeaders(region), headers));
      session.assertCurrent();
    }
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
    const root: RoleCombatRoot = RoleCombatRoot.fromJson(resp.data);
    // 各期原始 JSON（与 data[] 下标一一对应，期数历史入库用；回看时 dataItemFromJson 重建）
    const dataArr = (resp.data as Record<string, Object>)['data'] as Array<Object>;
    if (dataArr !== undefined && dataArr !== null) {
      for (let i = 0; i < dataArr.length; i++) {
        root.itemRawJson.push(JSON.stringify(dataArr[i]));
      }
    }
    Logger.info(TAG, `roleCombat unlock=${root.isUnlock} data=${root.data.length}`);
    return root;
  }
}
