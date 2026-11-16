/**
 * CalendarService.ets
 * 活动日历：act_calendar（DS Gen2/X4 + Cookie）。
 */
import { UserService } from './UserService';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { ApiResponse } from '../model/ApiResponse';
import { ActCalendarEntry } from '../model/ActCalendarEntry';
import { RegionUtil } from '../common/Constants';
import { HoyolabEndpoints } from '../common/HoyolabEndpoints';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { Logger } from '../common/Logger';

const TAG: string = 'CalendarService';

export enum CalendarEntryOrder {
  Chronological,
  Home,
}

export class CalendarService {
  private static instance: CalendarService = new CalendarService();

  static getInstance(): CalendarService {
    return CalendarService.instance;
  }

  /** 同一份活动日历响应可按日历时间或首页上游列表顺序呈现。 */
  async fetchCalendar(uid: string, isCurrent?: () => boolean,
    order: CalendarEntryOrder = CalendarEntryOrder.Chronological): Promise<ActCalendarEntry[]> {
    const users: UserService = UserService.getInstance();
    const user: User | undefined = users.getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    if (user.isOversea || !RegionUtil.isCnUid(uid)) {
      throw new Error('活动日历仅支持国服角色');
    }
    const region: string = RegionUtil.regionOfUid(uid);
    if (!user.roles.some((role: UserGameRole): boolean =>
      role.gameUid === uid && role.region === region && (role.userId === 0 || role.userId === user.id))) {
      throw new Error('请选择当前账号已绑定的游戏角色');
    }
    const revision: number = users.sessionRevision();
    const owns: () => boolean = (): boolean =>
      users.sessionRevision() === revision && users.getCurrentUser() === user && (isCurrent?.() ?? true);
    const checkOwner: () => void = (): void => {
      if (!owns()) { throw new Error('账号或日历查询已改变，请重试'); }
    };
    checkOwner();
    // 缺 cookie_token/ltoken 时先用 SToken 补齐
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await users.completeTokenChainPublic(user);
      checkOwner();
    }

    let verified: boolean = false;
    let refreshed: boolean = false;
    let challenge: string = '';
    while (true) {
      const headers: Record<string, string> = {};
      if (challenge.length > 0) { headers['x-rpc-challenge'] = challenge; }
      const cookie: string = user.gameRecordCookie();
      if (cookie.length === 0) { throw new Error('账号缺少活动日历凭据，请重新登录'); }
      const response: ApiResponse = await HoyolabClient.fetchActCalendar(uid, region, cookie, headers, owns);
      checkOwner();
      if (response.isRiskControl() && !verified) {
        verified = true;
        // 上游 CreateForActCalendar 使用同区服 hard_challenge 路径注册极验。
        challenge = await RiskVerifier.tryResolveRisk(response, cookie, HoyolabEndpoints.gameRecordUrl('hard_challenge', region));
        checkOwner();
        if (challenge.length === 0) { throw new Error('人机验证未完成或被取消，请重试'); }
        continue;
      }
      if (!response.success && UserService.isCookieAuthError(response) && !refreshed) {
        refreshed = true;
        const ok: boolean = await users.refreshCookieTokenForced(user);
        checkOwner();
        if (!ok) { throw new Error('活动日历登录态已失效，请重新登录'); }
        challenge = '';
        continue;
      }
      if (!response.success || response.data === undefined) {
        throw new Error(response.userFriendlyMessage());
      }
      return CalendarService.parse(response.data, order);
    }
  }

  private static parse(data: Object, order: CalendarEntryOrder): ActCalendarEntry[] {
    if (data === null || typeof data !== 'object' || Array.isArray(data)) {
      throw new Error('活动日历数据格式无效');
    }
    const obj: Record<string, Object> = data as Record<string, Object>;
    const entries: ActCalendarEntry[] = [];

    const forHome: boolean = order === CalendarEntryOrder.Home;
    // Windows 首页按固定活动、普通活动排列，各卡池沿 API 列表顺序。
    CalendarService.addActs(entries, obj[forHome ? 'fixed_act_list' : 'act_list']);
    CalendarService.addActs(entries, obj[forHome ? 'act_list' : 'fixed_act_list']);
    CalendarService.addCardPools(entries, obj['avatar_card_pool_list']);
    CalendarService.addCardPools(entries, obj['weapon_card_pool_list']);
    CalendarService.addCardPools(entries, obj['mixed_card_pool_list']);

    if (!forHome) {
      entries.sort((a: ActCalendarEntry, b: ActCalendarEntry): number => a.startTime - b.startTime);
    }
    Logger.info(TAG, `calendar fetched ${entries.length} entries`);
    return entries;
  }

  private static addActs(entries: ActCalendarEntry[], raw: Object): void {
    if (!Array.isArray(raw)) { return; }
    for (const item of raw as Object[]) {
      if (item !== null && typeof item === 'object') { entries.push(ActCalendarEntry.fromAct(item)); }
    }
  }

  private static addCardPools(entries: ActCalendarEntry[], raw: Object): void {
    if (!Array.isArray(raw)) { return; }
    for (const item of raw as Object[]) {
      if (item !== null && typeof item === 'object') { entries.push(ActCalendarEntry.fromCardPool(item)); }
    }
  }
}
