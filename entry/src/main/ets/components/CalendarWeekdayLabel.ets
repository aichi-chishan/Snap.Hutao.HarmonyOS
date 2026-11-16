import { UIContext } from '@kit.ArkUI';
import { CalendarWeekDay } from '../service/CalendarWeekService';

const WEEKDAY_LABELS: Resource[] = [
  $r('app.string.ui_weekday_sunday'), $r('app.string.ui_weekday_monday'),
  $r('app.string.ui_weekday_tuesday'), $r('app.string.ui_weekday_wednesday'),
  $r('app.string.ui_weekday_thursday'), $r('app.string.ui_weekday_friday'),
  $r('app.string.ui_weekday_saturday')
];

export function calendarWeekdayLabel(weekday: number): Resource {
  return WEEKDAY_LABELS[weekday];
}

export function calendarDateLabel(context: UIContext, day: CalendarWeekDay | undefined): string {
  if (day === undefined) { return ''; }
  const resources = context.getHostContext()?.resourceManager;
  const weekday: string = resources?.getStringSync(calendarWeekdayLabel(day.weekday).id) ?? '';
  const dateLabel: string = weekday.length > 0 ? `${weekday} ${day.monthDay}` : day.monthDay;
  if (!day.isToday) { return dateLabel; }
  const today: string = resources?.getStringSync($r('app.string.ui_travelers_diary_today').id) ?? '';
  return today.length > 0 ? `${dateLabel} · ${today}` : dateLabel;
}
