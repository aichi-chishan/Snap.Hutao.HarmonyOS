/**
 * Ledger.ets
 * 旅行者札记（月历）模型（对齐 Windows Web/Hoyolab/Takumi/GameRecord/Ledger/*）：
 *   Ledger = API data 根：uid/region/nickname/date/month/optional_month/day_data/month_data
 *   MonthData：当月/上月 原石与摩拉 + 环比 + group_by 分类来源
 *   IncomeSource：分类来源（action_id/action/num/percent）
 */

/** 分类来源（原石/摩拉获取途径） */
export class LedgerIncomeSource {
  actionId: number = 0;
  action: string = '';
  num: number = 0;
  percent: number = 0;

  static fromJson(obj: Object): LedgerIncomeSource {
    const o = obj as Record<string, Object>;
    const s = new LedgerIncomeSource();
    s.actionId = Number(o['action_id'] ?? 0);
    s.action = String(o['action'] ?? '');
    s.num = Number(o['num'] ?? 0);
    s.percent = Number(o['percent'] ?? 0);
    return s;
  }
}

/** 月度累计 */
export class LedgerMonthData {
  currentPrimogems: number = 0;
  currentMora: number = 0;
  lastPrimogems: number = 0;
  lastMora: number = 0;
  currentPrimogemsLevel: number = 0;
  primogemsRate: number = 0;
  moraRate: number = 0;
  groupBy: LedgerIncomeSource[] = [];

  static fromJson(obj: Object): LedgerMonthData {
    const o = obj as Record<string, Object>;
    const d = new LedgerMonthData();
    d.currentPrimogems = Number(o['current_primogems'] ?? 0);
    d.currentMora = Number(o['current_mora'] ?? 0);
    d.lastPrimogems = Number(o['last_primogems'] ?? 0);
    d.lastMora = Number(o['last_mora'] ?? 0);
    d.currentPrimogemsLevel = Number(o['current_primogems_level'] ?? 0);
    d.primogemsRate = Number(o['primogems_rate'] ?? 0);
    d.moraRate = Number(o['mora_rate'] ?? 0);
    const group = o['group_by'] as Array<Object>;
    if (group !== undefined && group !== null) {
      for (const g of group) {
        d.groupBy.push(LedgerIncomeSource.fromJson(g));
      }
    }
    return d;
  }
}

/** 每日数据 */
export class LedgerDayData {
  currentPrimogems: number = 0;
  currentMora: number = 0;
  lastPrimogems: number = 0;
  lastMora: number = 0;

  static fromJson(obj: Object): LedgerDayData {
    const o = obj as Record<string, Object>;
    const d = new LedgerDayData();
    d.currentPrimogems = Number(o['current_primogems'] ?? 0);
    d.currentMora = Number(o['current_mora'] ?? 0);
    d.lastPrimogems = Number(o['last_primogems'] ?? 0);
    d.lastMora = Number(o['last_mora'] ?? 0);
    return d;
  }
}

/** 札记根（monthInfo 响应 data） */
export class Ledger {
  uid: number = 0;
  region: string = '';
  nickname: string = '';
  date: string = '';
  month: number = 0;
  optionalMonth: number[] = [];
  dayData: LedgerDayData = new LedgerDayData();
  monthData: LedgerMonthData = new LedgerMonthData();

  static fromJson(obj: Object): Ledger {
    const o = obj as Record<string, Object>;
    const l = new Ledger();
    l.uid = Number(o['uid'] ?? 0);
    l.region = String(o['region'] ?? '');
    l.nickname = String(o['nickname'] ?? '');
    l.date = String(o['date'] ?? '');
    l.month = Number(o['month'] ?? 0);
    const months = o['optional_month'] as Array<Object>;
    if (months !== undefined && months !== null) {
      for (const m of months) {
        l.optionalMonth.push(Number(m));
      }
    }
    if (o['day_data'] !== undefined && o['day_data'] !== null) {
      l.dayData = LedgerDayData.fromJson(o['day_data']);
    }
    if (o['month_data'] !== undefined && o['month_data'] !== null) {
      l.monthData = LedgerMonthData.fromJson(o['month_data']);
    }
    return l;
  }
}
