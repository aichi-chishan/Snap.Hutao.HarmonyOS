import { GachaEventMeta } from './WikiMetaService';
import { DateUtil } from '../common/DateUtil';
import { ServerTime } from '../common/ServerTime';

/** 轮换材料系列（dayPair：1=周一四 2=周二五 3=周三六） */
export class RotationalMaterialSeries {
  readonly dayPair: number;
  readonly highestId: number;

  constructor(dayPair: number, highestId: number) {
    this.dayPair = dayPair;
    this.highestId = highestId;
  }

  isTalent(): boolean {
    return this.highestId < 114000;
  }

  includes(id: number): boolean {
    return id <= this.highestId && id >= this.highestId - (this.isTalent() ? 2 : 3);
  }
}

function series(dayPair: number, id: number): RotationalMaterialSeries {
  return new RotationalMaterialSeries(dayPair, id);
}

/** Windows MaterialIds.Entries 轮换表（取每系列最高阶） */
export const ROTATIONAL_SERIES: RotationalMaterialSeries[] = [
  // 天赋书（1043xx，3 阶）
  series(1, 104303), series(1, 104312), series(1, 104322), series(1, 104331),
  series(1, 104340), series(1, 104349), series(1, 104358), series(1, 104367),
  series(2, 104306), series(2, 104315), series(2, 104325), series(2, 104334),
  series(2, 104343), series(2, 104352), series(2, 104361), series(2, 104370),
  series(3, 104309), series(3, 104318), series(3, 104328), series(3, 104337),
  series(3, 104346), series(3, 104355), series(3, 104364), series(3, 104373),
  // 武器突破材料（114xxx，4 阶）
  // 苍星军势最高阶为 114088（游戏元数据）；114089 是藏窖灵浆的第一阶。
  series(1, 114004), series(1, 114016), series(1, 114028), series(1, 114040),
  series(1, 114052), series(1, 114064), series(1, 114076), series(1, 114088),
  series(2, 114008), series(2, 114020), series(2, 114032), series(2, 114044),
  series(2, 114056), series(2, 114068), series(2, 114080), series(2, 114092),
  series(3, 114012), series(3, 114024), series(3, 114036), series(3, 114048),
  series(3, 114060), series(3, 114072), series(3, 114084), series(3, 114096),
];

/** Server-local calendar dates, independent of the device time zone and daylight saving. */
export class GameCalendarRules {
  static readonly DAY_MS: number = 86400000;
  static readonly DEFAULT_OFFSET_HOURS: number = 8;
  static readonly OFFSET_HOURS: number[] = [8, -5, 1];
  private static readonly HOUR_MS: number = 3600000;

  static serverOffset(region: string): number {
    return ServerTime.offsetHours(region);
  }

  static materialSeries(itemId: number): RotationalMaterialSeries | undefined {
    return ROTATIONAL_SERIES.find((series: RotationalMaterialSeries): boolean => series.includes(itemId));
  }

  static materialDayPair(itemId: number): number {
    return GameCalendarRules.materialSeries(itemId)?.dayPair ?? 0;
  }

  static normalizeOffset(offsetHours: number): number {
    return GameCalendarRules.OFFSET_HOURS.includes(offsetHours) ? offsetHours : GameCalendarRules.DEFAULT_OFFSET_HOURS;
  }

  static offsetLabel(offsetHours: number): string {
    const sign: string = offsetHours < 0 ? '-' : '+';
    return `UTC${sign}${DateUtil.pad2(Math.abs(offsetHours))}:00`;
  }

  static startOfServerDay(day: number, offsetHours: number): number {
    return day * GameCalendarRules.DAY_MS - offsetHours * GameCalendarRules.HOUR_MS;
  }

  static formatMonthDay(ms: number, offsetHours: number): string {
    if (!Number.isFinite(ms) || ms <= 0) { return '--'; }
    const date: Date = new Date(ms + offsetHours * GameCalendarRules.HOUR_MS);
    return `${DateUtil.pad2(date.getUTCMonth() + 1)}-${DateUtil.pad2(date.getUTCDate())} ` +
      `${DateUtil.pad2(date.getUTCHours())}:${DateUtil.pad2(date.getUTCMinutes())}`;
  }

  /** Integer date ordinal; use UTC getters when formatting the shifted value. */
  static serverDay(ms: number, offsetHours: number = GameCalendarRules.DEFAULT_OFFSET_HOURS): number {
    return Math.floor((ms + offsetHours * GameCalendarRules.HOUR_MS) / GameCalendarRules.DAY_MS);
  }

  /** Remastered GachaEventSchedule: character banners open every material for seven dates. */
  static allMaterialsOpen(ms: number, events: GachaEventMeta[],
    offsetHours: number = GameCalendarRules.DEFAULT_OFFSET_HOURS): boolean {
    const day: number = GameCalendarRules.serverDay(ms, offsetHours);
    for (const event of events) {
      if ((event.type !== 301 && event.type !== 400) || !Number.isFinite(event.from) || event.from <= 0) {
        continue;
      }
      const start: number = GameCalendarRules.serverDay(event.from, offsetHours);
      if (day >= start && day < start + 7) {
        return true;
      }
    }
    return false;
  }
}
