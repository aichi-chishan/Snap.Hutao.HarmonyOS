/**
 * HardChallengeService.ets
 * 强敌挑战：GET hard_challenge?role_id&server&need_detail=true，DS Gen2/X4，Cookie(cookie_token+ltoken)。
 */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { DsSigner } from '../data/network/DsSigner';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { HardChallengeRoot, HardChallengeSimpleAvatar } from '../model/HardChallenge';
import { UserService } from './UserService';
import { RegionUtil, AppConstants } from '../common/Constants';
import { HoyolabEndpoints } from '../common/HoyolabEndpoints';
import { Logger } from '../common/Logger';

const TAG: string = 'HardChallengeService';
const API_PATH: string = 'hard_challenge';

export class HardChallengeService {
  private static instance: HardChallengeService = new HardChallengeService();

  static getInstance(): HardChallengeService {
    return HardChallengeService.instance;
  }

  /** 拉取强敌挑战数据
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头） */
  async fetch(uid: string, challenge?: string): Promise<HardChallengeRoot> {
    const resp: ApiResponse = await this.request(uid, API_PATH, true, challenge);
    const root: HardChallengeRoot = HardChallengeRoot.fromJson(resp.data as Object);
    root.rawJson = JSON.stringify(resp.data);
    return root;
  }

  /** 官方战绩人气角色接口；与账号自身每期 blings 独立。 */
  async fetchPopularity(uid: string): Promise<HardChallengeSimpleAvatar[]> {
    const resp: ApiResponse = await this.request(uid, 'hard_challenge/popularity', false);
    const data: Record<string, Object> = resp.data as Record<string, Object>;
    return HardChallengeRoot.avatarListFromJson(data['avatar_list']);
  }

  private async request(uid: string, path: string, detail: boolean, challenge?: string): Promise<ApiResponse> {
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
      'role_id': uid,
      'server': region,
    };
    if (detail) { query['need_detail'] = 'true'; }
    const sorted: string = DsSigner.sortQuery(query);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(HoyolabEndpoints.gameRecordSalt(region), t, r, '', sorted);
    const url: string = `${HoyolabEndpoints.gameRecordUrl(path, region)}?${sorted}`;
    const headers: Record<string, string> = { 'DS': ds, 'Cookie': cookie };
    if (challenge !== undefined && challenge.length > 0) {
      headers['x-rpc-challenge'] = challenge;
    }
    const resp0: ApiResponse = await ApiClient.getInstance().get(url,
      HoyolabClient.merge(HoyolabClient.getBaseHeaders(region), headers));
    let resp: ApiResponse = resp0;
    if (resp0.isRiskControl()) {
      if (HoyolabEndpoints.isOverseaRegion(region)) {
        throw new Error('HoYoLAB 需要完成验证，请在官方应用验证后重试');
      }
      // 1034：自动弹统一验证窗，成功后带 challenge 服务内重放一次
      const replayChallenge: string = await RiskVerifier.tryResolveRisk(resp0, cookie, url);
      if (replayChallenge.length === 0) {
        throw new Error('人机验证未完成或被取消，请稍后再试');
      }
      headers['x-rpc-challenge'] = replayChallenge;
      resp = await ApiClient.getInstance().get(url,
        HoyolabClient.merge(HoyolabClient.getBaseHeaders(region), headers));
    }
    if (!resp.success && UserService.isCookieAuthError(resp)) {
      resp = await UserService.retryWithRefreshedCookie(user, async (): Promise<ApiResponse> => {
        const retryHeaders: Record<string, string> = {
          'Cookie': user.gameRecordCookie(),
          'DS': await DsSigner.signGen2(HoyolabEndpoints.gameRecordSalt(region),
            DsSigner.nowTimestamp(), DsSigner.randomNumber(), '', sorted),
        };
        if (headers['x-rpc-challenge'] !== undefined) {
          retryHeaders['x-rpc-challenge'] = headers['x-rpc-challenge'];
        }
        return ApiClient.getInstance().get(url,
          HoyolabClient.merge(HoyolabClient.getBaseHeaders(region), retryHeaders));
      });
    }
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    return resp;
  }
}
