import { ApiClient } from './ApiClient';
import { HoyolabClient } from './HoyolabClient';
import { DsSigner } from './DsSigner';
import { RiskVerifier } from './RiskVerifier';
import { ApiResponse } from '../../model/ApiResponse';
import { User } from '../../model/User';
import { UserGameRole } from '../../model/UserGameRole';
import { UserService } from '../../service/UserService';
import { RegionUtil } from '../../common/Constants';
import { HoyolabEndpoints } from '../../common/HoyolabEndpoints';
import { ChallengeCloudSchema } from '../../model/ChallengeCloud';

/** Captures game ownership without exposing credentials to the preview/cloud DTO. */
export class ChallengeGameOwner {
  readonly user: User;
  readonly uid: string;
  readonly region: string;
  readonly revision: number;
  constructor(uid: string) {
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    if (user === undefined || !Number.isSafeInteger(user.id) || user.id <= 0 || !user.hasCookie() || !RegionUtil.isValidUid(uid)) { throw new Error('请先登录并选择有效 UID'); }
    this.user = user; this.uid = uid; this.region = RegionUtil.regionOfUid(uid);
    this.revision = UserService.getInstance().sessionRevision(); this.assertCurrent();
  }
  assertCurrent(): void {
    const users: UserService = UserService.getInstance();
    if (users.getCurrentUser() !== this.user || users.sessionRevision() !== this.revision ||
      AppStorage.get<string>('currentUid') !== this.uid || !this.user.hasCookie() ||
      !this.user.roles.some((role: UserGameRole): boolean => role.gameUid === this.uid && role.region === this.region) ||
      this.user.isOversea !== HoyolabEndpoints.isOverseaRegion(this.region)) {
      throw new Error('账号或 UID 已变化，请重新采集并确认');
    }
  }
}

/** Read-only game collection. All replay attempts use the captured account and a fresh DS. */
export class ChallengeGameRecordClient {
  private owner: ChallengeGameOwner;
  private active: () => void;
  constructor(owner: ChallengeGameOwner, active: () => void) { this.owner = owner; this.active = active; }
  private check(): void { this.owner.assertCurrent(); this.active(); }
  async get(path: string, query: Record<string, string>): Promise<Object> { return this.read(path, query, ''); }
  async post(path: string, body: Record<string, Object>): Promise<Object> {
    const empty: Record<string, string> = {}; return this.read(path, empty, JSON.stringify(body));
  }
  private async read(path: string, query: Record<string, string>, body: string): Promise<Object> {
    if (!['index', 'character/list', 'character/detail', 'spiralAbyss', 'role_combat'].includes(path)) { throw new Error('不支持的战绩采集接口'); }
    this.check();
    if (this.owner.user.cookieToken.length === 0 || this.owner.user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(this.owner.user); this.check();
    }
    const sorted: string = DsSigner.sortQuery(query);
    const endpoint: string = HoyolabEndpoints.gameRecordUrl(path, this.owner.region);
    const url: string = sorted.length > 0 ? `${endpoint}?${sorted}` : endpoint;
    let challenge: string = '';
    const attempt: () => Promise<ApiResponse> = async (): Promise<ApiResponse> => {
      this.check();
      const cookie: string = this.owner.user.gameRecordCookie();
      if (cookie.length === 0) { throw new Error('账号缺少战绩凭据，请重新登录'); }
      const headers: Record<string, string> = { 'Cookie': cookie, 'DS': await DsSigner.signGen2(
        HoyolabEndpoints.gameRecordSalt(this.owner.region), DsSigner.nowTimestamp(), DsSigner.randomNumber(), body, sorted) };
      this.check();
      if (challenge.length > 0) { headers['x-rpc-challenge'] = challenge; }
      const merged: Record<string, string> = HoyolabClient.merge(HoyolabClient.getBaseHeaders(this.owner.region), headers);
      return body.length > 0 ? ApiClient.getInstance().postJson(url, body, merged) : ApiClient.getInstance().get(url, merged);
    };
    let response: ApiResponse = await attempt(); this.check();
    if (response.isRiskControl()) {
      if (this.owner.user.isOversea) { throw new Error('HoYoLAB 需要完成验证，请在官方应用验证后重新采集'); }
      challenge = await RiskVerifier.tryResolveRisk(response, this.owner.user.gameRecordCookie(), url); this.check();
      if (challenge.length === 0) { throw new Error('人机验证已取消，未提交战绩'); }
      response = await attempt(); this.check();
    }
    if (!response.success && UserService.isCookieAuthError(response)) {
      response = await UserService.retryWithRefreshedCookie(this.owner.user, attempt); this.check();
    }
    if (!response.success || response.data === undefined) { throw new Error(response.userFriendlyMessage()); }
    const data: Record<string, Object> = ChallengeCloudSchema.object(response.data, '战绩响应');
    ChallengeCloudSchema.identity(data, this.owner.uid, this.owner.region);
    return data;
  }
}
