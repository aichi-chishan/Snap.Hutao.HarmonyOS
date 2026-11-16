import { ServerTime } from '../common/ServerTime';

/** One game period with published metadata and, when present, the selected role's local record. */
export class ChallengePeriod {
  scheduleId: number;
  startTime: number;
  endTime: number;
  name: string;
  hasRecord: boolean = false;
  recordTime: number = 0;
  totalStar: number = 0;
  summary: string = '';

  constructor(scheduleId: number, startTime: number, endTime: number, name: string = '') {
    this.scheduleId = scheduleId;
    this.startTime = startTime;
    this.endTime = endTime;
    this.name = name;
  }

  static recorded(id: number, start: number, end: number, savedAt: number, stars: number = 0): ChallengePeriod {
    const period: ChallengePeriod = new ChallengePeriod(id, start, end);
    period.hasRecord = true;
    period.recordTime = savedAt;
    period.totalStar = stars;
    return period;
  }

  static merge(records: ChallengePeriod[], published: ChallengePeriod[]): ChallengePeriod[] {
    const byId: Map<number, ChallengePeriod> = new Map();
    for (const item of published) { if (item.scheduleId > 0) { byId.set(item.scheduleId, item); } }
    for (const item of records) {
      const known: ChallengePeriod | undefined = byId.get(item.scheduleId);
      if (known !== undefined) {
        if (known.name.length > 0) { item.name = known.name; }
        if (item.startTime <= 0) { item.startTime = known.startTime; }
        if (item.endTime <= 0) { item.endTime = known.endTime; }
      }
      byId.set(item.scheduleId, item);
    }
    return Array.from(byId.values()).sort((a: ChallengePeriod, b: ChallengePeriod): number => b.scheduleId - a.scheduleId);
  }

  static hardChallengeNumber(id: number): number { return id > 5269000 ? id - 5269000 : id; }

  static serverDate(ms: number): Date { return new Date(ms + ServerTime.offsetHours('cn_gf01') * 3600000); }

  static monthDay(ms: number): string {
    if (!Number.isFinite(ms) || ms <= 0) { return ''; }
    const date: Date = ChallengePeriod.serverDate(ms);
    return `${date.getUTCMonth() + 1}/${date.getUTCDate()}`;
  }

  static dateRange(start: number, end: number): string {
    const first: string = ChallengePeriod.monthDay(start);
    const last: string = ChallengePeriod.monthDay(end);
    return first.length > 0 && last.length > 0 ? `${first}–${last}` : '';
  }

  static dateTime(ms: number): string {
    if (!Number.isFinite(ms) || ms <= 0) { return ''; }
    const date: Date = ChallengePeriod.serverDate(ms);
    return `${date.getUTCFullYear()}.${String(date.getUTCMonth() + 1).padStart(2, '0')}.${String(date.getUTCDate()).padStart(2, '0')} ` +
      `${String(date.getUTCHours()).padStart(2, '0')}:${String(date.getUTCMinutes()).padStart(2, '0')}`;
  }

  static detailedRange(start: number, end: number): string {
    const first: string = ChallengePeriod.dateTime(start);
    const last: string = ChallengePeriod.dateTime(end);
    return first.length > 0 && last.length > 0 ? `${first} – ${last}` : first || last;
  }
}
