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
import { RegionUtil, AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'RoleCombatService';
const URL: string = 'https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/role_combat';

export class RoleCombatService {
  private static instance: RoleCombatService = new RoleCombatService();

  static getInstance(): RoleCombatService {
    return RoleCombatService.instance;
  }

  /** 拉取剧诗数据
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头） */
  async fetch(uid: string, challenge?: string): Promise<RoleCombatRoot> {
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
      'active': '1',
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
    const root: RoleCombatRoot = RoleCombatRoot.fromJson(resp.data);
    Logger.info(TAG, `roleCombat unlock=${root.isUnlock} data=${root.data.length}`);
    return root;
  }
}
