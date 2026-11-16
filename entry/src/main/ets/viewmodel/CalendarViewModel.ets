/**
 * CalendarViewModel.ets
 * 活动日历页状态容器。
 */
import { CalendarService } from '../service/CalendarService';
import { CalendarWeekData, CalendarWeekDay, CalendarWeekService } from '../service/CalendarWeekService';
import { ActCalendarEntry } from '../model/ActCalendarEntry';

@Observed
export class CalendarViewModel {
  entries: ActCalendarEntry[] = [];
  loading: boolean = false;
  message: string = '';
  week: CalendarWeekData | undefined = undefined;
  weekMessage: string = '';
  selectedDateMs: number = 0;
  private activityGeneration: number = 0;
  private weekGeneration: number = 0;

  clearActivities(): void {
    this.activityGeneration++;
    this.entries = [];
    this.message = '';
    this.loading = false;
  }

  dispose(): void {
    this.weekGeneration++;
    this.activityGeneration++;
  }

  selectedDay(): CalendarWeekDay | undefined {
    return this.week?.days.find((day: CalendarWeekDay): boolean => day.dateMs === this.selectedDateMs);
  }

  async loadWeek(nowMs: number): Promise<void> {
    const generation: number = ++this.weekGeneration;
    this.weekMessage = '';
    try {
      const week: CalendarWeekData = await CalendarWeekService.loadWeek(nowMs);
      if (generation !== this.weekGeneration) { return; }
      const selected: CalendarWeekDay | undefined = this.selectedDay();
      const keepSelection: boolean = this.week?.offsetHours === week.offsetHours && selected?.isToday === false;
      const day: CalendarWeekDay | undefined = keepSelection
        ? week.days.find((item: CalendarWeekDay): boolean => item.dateMs === this.selectedDateMs) : undefined;
      this.week = week;
      this.selectedDateMs = day?.dateMs ?? week.days.find((item: CalendarWeekDay): boolean => item.isToday)?.dateMs ?? 0;
    } catch (e) {
      if (generation === this.weekGeneration) { this.weekMessage = (e as Error).message; }
    }
  }

  async load(uid: string, isCurrent: () => boolean): Promise<void> {
    const generation: number = ++this.activityGeneration;
    const owns: () => boolean = (): boolean => generation === this.activityGeneration && isCurrent();
    this.loading = true;
    this.message = '';
    try {
      const entries: ActCalendarEntry[] = await CalendarService.getInstance().fetchCalendar(uid, owns);
      if (owns()) { this.entries = entries; }
    } catch (e) {
      if (owns()) { this.message = (e as Error).message; }
    } finally {
      if (owns()) { this.loading = false; }
    }
  }
}
