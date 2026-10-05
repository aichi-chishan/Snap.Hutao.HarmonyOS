/** Regional travelers' diary. Every retry re-signs and retains its original account/UID owner. */
import { Ledger } from '../model/Ledger';
import { ApiResponse } from '../model/ApiResponse';
import { ApiClient } from '../data/network/ApiClient';
import { RegionUtil } from '../common/Constants';
import { HoyolabEndpoints } from '../common/HoyolabEndpoints';
import { DsSigner } from '../data/network/DsSigner';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { UserService } from './UserService';

export class LedgerService {
  private static instance: LedgerService = new LedgerService();
  static getInstance(): LedgerService { return LedgerService.instance; }

  static query(month: number, uid: string, region: string): Record<string, string> {
    if (!Number.isInteger(month) || month < 0 || month > 12 || RegionUtil.regionOfUid(uid) !== region) {
      throw new Error('札记 UID、区服或月份无效');
    }
    HoyolabEndpoints.requireRegion(region);
    if (RegionUtil.isOverseaRegion(region)) {
      const oversea: Record<string, string> = { 'month': String(month), 'region': region, 'uid': uid, 'lang': 'zh-cn' };
      return oversea;
    }
    const chinese: Record<string, string> = {
      'month': String(month), 'bind_uid': uid, 'bind_region': region,
      'bbs_presentation_style': 'fullscreen', 'bbs_auth_required': 'true',
      'utm_source': 'bbs', 'utm_medium': 'mys', 'utm_campaign': 'icon',
    };
    return chinese;
  }

  private checkOwner(user: User, userId: number, uid: string, region: string, isCurrent?: () => boolean): void {
    const current: User | undefined = UserService.getInstance().getCurrentUser();
    if (current !== user || user.id !== userId || (isCurrent !== undefined && !isCurrent())) {
      throw new Error('账号或札记查询已改变，已丢弃旧请求');
    }
    if (user.isOversea !== RegionUtil.isOverseaRegion(region)) { throw new Error('当前账号与角色区服不匹配，请切换账号'); }
    const role: UserGameRole | undefined = user.roles.find((candidate: UserGameRole): boolean => candidate.gameUid === uid);
    if (role === undefined || role.region !== region || (role.userId > 0 && role.userId !== userId)) {
      throw new Error('请选择当前账号已绑定的游戏角色');
    }
  }

  private async request(month: number, uid: string, region: string, user: User, ownerId: number,
    challenge: string, isCurrent?: () => boolean): Promise<ApiResponse> {
    this.checkOwner(user, ownerId, uid, region, isCurrent);
    const query: string = DsSigner.sortQuery(LedgerService.query(month, uid, region));
    const ds: string = await DsSigner.signGen2(HoyolabEndpoints.gameRecordSalt(region), DsSigner.nowTimestamp(), DsSigner.randomNumber(), '', query);
    this.checkOwner(user, ownerId, uid, region, isCurrent);
    const headers: Record<string, string> = {};
    const base: Record<string, string> = HoyolabClient.getBaseHeaders(region);
    for (const key of Object.keys(base)) {
      // Pinned upstream XRpc3 has no Referer; never carry the China webstatic header overseas.
      if (!user.isOversea || key.toLowerCase() !== 'referer') { headers[key] = base[key]; }
    }
    headers['DS'] = ds;
    headers['Cookie'] = user.gameRecordCookie();
    if (headers['Cookie'].length === 0) { throw new Error('账号缺少札记凭据，请重新登录'); }
    if (challenge.length > 0) { headers['x-rpc-challenge'] = challenge; }
    const response: ApiResponse = await ApiClient.getInstance().get(`${HoyolabEndpoints.ledgerUrl(region)}?${query}`, headers);
    this.checkOwner(user, ownerId, uid, region, isCurrent);
    return response;
  }

  async fetchMonth(month: number, uid: string, isCurrent?: () => boolean): Promise<Ledger> {
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) { throw new Error('请先登录'); }
    const region: string = RegionUtil.regionOfUid(uid);
    LedgerService.query(month, uid, region);
    const ownerId: number = user.id;
    this.checkOwner(user, ownerId, uid, region, isCurrent);
    if (user.cookieToken.length === 0) {
      await UserService.getInstance().refreshCookieTokenForced(user);
      this.checkOwner(user, ownerId, uid, region, isCurrent);
    }
    let refreshed: boolean = false;
    let verified: boolean = false;
    let challenge: string = '';
    while (true) {
      const response: ApiResponse = await this.request(month, uid, region, user, ownerId, challenge, isCurrent);
      this.checkOwner(user, ownerId, uid, region, isCurrent);
      if (response.isRiskControl()) {
        if (user.isOversea) { throw new Error('HoYoLAB 札记需要验证，请在官方 HoYoLAB 完成验证后重试'); }
        if (verified) { throw new Error('札记验证后仍被拦截，请稍后重试'); }
        verified = true;
        challenge = await RiskVerifier.tryResolveRisk(response, user.gameRecordCookie(), 'event/ys_ledger/monthInfo');
        this.checkOwner(user, ownerId, uid, region, isCurrent);
        if (challenge.length === 0) { throw new Error('人机验证未完成或被取消，显示的数据未刷新'); }
        continue;
      }
      if (!response.success && UserService.isCookieAuthError(response) && !refreshed) {
        refreshed = true;
        const ok: boolean = await UserService.getInstance().refreshCookieTokenForced(user);
        this.checkOwner(user, ownerId, uid, region, isCurrent);
        if (!ok) { throw new Error('札记登录态已失效，请重新登录对应区服的账号'); }
        challenge = '';
        continue;
      }
      if (!response.success || response.data === undefined) { throw new Error(response.userFriendlyMessage()); }
      const data: Record<string, Object> = response.data as Record<string, Object>;
      if (data === null || typeof data !== 'object' || Array.isArray(data) ||
        (typeof data['uid'] !== 'string' && typeof data['uid'] !== 'number') || String(data['uid']) !== uid ||
        (typeof data['month'] !== 'string' && typeof data['month'] !== 'number') ||
        data['region'] !== region || !Number.isInteger(Number(data['month'])) || Number(data['month']) < 1 || Number(data['month']) > 12 ||
        (month !== 0 && Number(data['month']) !== month)) { throw new Error('札记响应的账号区服或月份不匹配'); }
      const monthData: Object = data['month_data'];
      if (monthData === null || typeof monthData !== 'object' || Array.isArray(monthData)) { throw new Error('札记缺少月度统计'); }
      const totals: Record<string, Object> = monthData as Record<string, Object>;
      for (const key of ['current_primogems', 'current_mora', 'last_primogems', 'last_mora']) {
        const value: Object = totals[key];
        if ((typeof value !== 'number' && typeof value !== 'string') || String(value).trim().length === 0 ||
          !Number.isSafeInteger(Number(value)) || Number(value) < 0) { throw new Error('札记月度统计数据不完整'); }
      }
      const ledger: Ledger = Ledger.fromJson(response.data);
      if (!Number.isFinite(ledger.monthData.currentPrimogems) || !Number.isFinite(ledger.monthData.currentMora)) {
        throw new Error('札记统计数据无效');
      }
      ledger.optionalMonth = ledger.optionalMonth.filter((value: number, index: number, months: number[]): boolean =>
        Number.isInteger(value) && value >= 1 && value <= 12 && months.indexOf(value) === index);
      return ledger;
    }
  }
}
