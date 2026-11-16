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
import { ChallengePeriod } from '../model/ChallengePeriod';
import { UserService } from './UserService';
import { HoyolabEndpoints } from '../common/HoyolabEndpoints';
import { Logger } from '../common/Logger';
import { ChallengeSession } from './ChallengeSession';
import { GameDataService } from './GameDataService';

const TAG: string = 'HardChallengeService';
const API_PATH: string = 'hard_challenge';

interface HardChallengeScheduleRow {
  Id: number;
  Begin: string;
  End: string;
  Name: string;
}

export class HardChallengeService {
  private static instance: HardChallengeService = new HardChallengeService();

  static getInstance(): HardChallengeService {
    return HardChallengeService.instance;
  }

  static async publishedPeriods(): Promise<ChallengePeriod[]> {
    try {
      const text: string = await GameDataService.readMetadataFile('HardChallengeSchedule.json');
      const rows: HardChallengeScheduleRow[] = JSON.parse(text) as HardChallengeScheduleRow[];
      return rows.map((row: HardChallengeScheduleRow): ChallengePeriod =>
        new ChallengePeriod(row.Id, Date.parse(row.Begin), Date.parse(row.End), row.Name));
    } catch (e) {
      Logger.warn(TAG, 'hard challenge period metadata unavailable');
      return [];
    }
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
    const session: ChallengeSession = ChallengeSession.require(uid);
    const region: string = session.region;
    const cookie: string = await session.gameRecordCookie();
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
    return resp;
  }
}
