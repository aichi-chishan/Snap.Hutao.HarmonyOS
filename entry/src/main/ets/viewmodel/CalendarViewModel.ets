/**
 * CalendarViewModel.ets
 * 活动日历页状态容器。
 */
import { CalendarService } from '../service/CalendarService';
import { ActCalendarEntry } from '../model/ActCalendarEntry';

@Observed
export class CalendarViewModel {
  entries: ActCalendarEntry[] = [];
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;

  async load(uid: string): Promise<void> {
    this.loading = true;
    try {
      this.entries = await CalendarService.getInstance().fetchCalendar(uid);
    } catch (e) {
      this.message = (e as Error).message;
    } finally {
      this.loading = false;
      this.loaded = true;
    }
  }
}
