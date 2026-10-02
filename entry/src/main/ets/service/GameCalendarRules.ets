import { GachaEventMeta } from './WikiMetaService';

/** Server-local calendar dates, independent of the device time zone and daylight saving. */
export class GameCalendarRules {
  static readonly DAY_MS: number = 86400000;

  static serverOffset(region: string): number {
    if (region === 'os_usa') { return -5; }
    if (region === 'os_euro') { return 1; }
    return 8;
  }

  /** Integer date ordinal; use UTC getters when formatting the shifted value. */
  static serverDay(ms: number, offsetHours: number = 8): number {
    return Math.floor((ms + offsetHours * 3600000) / GameCalendarRules.DAY_MS);
  }

  /** Remastered GachaEventSchedule: character banners open every material for seven dates. */
  static allMaterialsOpen(ms: number, events: GachaEventMeta[], offsetHours: number = 8): boolean {
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
