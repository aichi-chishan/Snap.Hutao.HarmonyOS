/**
 * CalendarService.ets
 * 活动日历：act_calendar（DS Gen2/X4 + Cookie）。
 */
import { UserService } from './UserService';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { ApiResponse } from '../model/ApiResponse';
import { ActCalendarEntry } from '../model/ActCalendarEntry';
import { RegionUtil } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'CalendarService';

export class CalendarService {
  private static instance: CalendarService = new CalendarService();

  static getInstance(): CalendarService {
    return CalendarService.instance;
  }

  /** 拉取活动日历（活动 + 卡池合并，按开始时间升序） */
  async fetchCalendar(uid: string): Promise<ActCalendarEntry[]> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    // 缺 cookie_token/ltoken 时先用 SToken 补齐
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(user);
    }
    const region: string = RegionUtil.regionOfUid(uid);
    const cookie: string = user.gameRecordCookie();
    const resp: ApiResponse = await HoyolabClient.fetchActCalendar(uid, region, cookie);
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const obj = resp.data as Record<string, Object>;
    const entries: ActCalendarEntry[] = [];

    // 活动：act_list + fixed_act_list
    CalendarService.addActs(entries, obj['act_list']);
    CalendarService.addActs(entries, obj['fixed_act_list']);
    // 卡池：角色/武器/混池
    CalendarService.addCardPools(entries, obj['avatar_card_pool_list']);
    CalendarService.addCardPools(entries, obj['weapon_card_pool_list']);
    CalendarService.addCardPools(entries, obj['mixed_card_pool_list']);

    // 按开始时间排序
    entries.sort((a: ActCalendarEntry, b: ActCalendarEntry) => {
      return a.startTime - b.startTime;
    });
    Logger.info(TAG, `calendar fetched ${entries.length} entries`);
    return entries;
  }

  private static addActs(entries: ActCalendarEntry[], raw: Object): void {
    const list = raw as Array<Object>;
    if (list === undefined || list === null) {
      return;
    }
    for (let i = 0; i < list.length; i++) {
      entries.push(ActCalendarEntry.fromAct(list[i]));
    }
  }

  private static addCardPools(entries: ActCalendarEntry[], raw: Object): void {
    const list = raw as Array<Object>;
    if (list === undefined || list === null) {
      return;
    }
    for (let i = 0; i < list.length; i++) {
      entries.push(ActCalendarEntry.fromCardPool(list[i]));
    }
  }
}
