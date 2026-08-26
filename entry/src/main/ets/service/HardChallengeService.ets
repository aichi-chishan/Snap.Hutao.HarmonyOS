/**
 * HardChallengeService.ets
 * 强敌挑战：GET hard_challenge?role_id&server&need_detail=true，DS Gen2/X4，Cookie(cookie_token+ltoken)。
 */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { DsSigner } from '../data/network/DsSigner';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { HardChallengeRoot } from '../model/HardChallenge';
import { UserService } from './UserService';
import { RegionUtil, AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'HardChallengeService';
const URL: string = 'https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/hard_challenge';

export class HardChallengeService {
  private static instance: HardChallengeService = new HardChallengeService();

  static getInstance(): HardChallengeService {
    return HardChallengeService.instance;
  }

  /** 拉取强敌挑战数据
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头） */
  async fetch(uid: string, challenge?: string): Promise<HardChallengeRoot> {
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
      'need_detail': 'true',
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
      await RiskVerifier.checkForRisk(resp, cookie, URL);
    }
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const root: HardChallengeRoot = HardChallengeRoot.fromJson(resp.data);
    Logger.info(TAG, `hardChallenge unlock=${root.isUnlock} single=${root.data.single.hasData}/${root.data.single.challenges.length} mp=${root.data.mp.hasData}/${root.data.mp.challenges.length}`);
    return root;
  }
}
