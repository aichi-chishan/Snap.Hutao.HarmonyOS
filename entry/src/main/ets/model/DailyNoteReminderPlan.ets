import { DailyNote } from './DailyNote';

export class DailyNoteReminder {
  kind: number = 0;
  title: string = '';
  seconds: number = 0;
}

/** 基于最近快照预测恢复时刻。只安排尚未达标的状态，不伪造后台联网结果。 */
export class DailyNoteReminderPlan {
  static build(note: DailyNote, flags: number, resinThreshold: number, homeThreshold: number): DailyNoteReminder[] {
    const result: DailyNoteReminder[] = [];
    if ((flags & 1) !== 0 && note.currentResin < resinThreshold && resinThreshold <= note.maxResin) {
      DailyNoteReminderPlan.add(result, 0, `树脂预计达到 ${resinThreshold}`,
        note.resinRecoverySeconds() - (note.maxResin - resinThreshold) * 480);
    }
    if ((flags & 2) !== 0 && note.expeditions.length > 0 && !note.allExpeditionsFinished()) {
      let seconds: number = 0;
      for (const expedition of note.expeditions) {
        if (!expedition.isFinished()) {
          seconds = Math.max(seconds, Number(expedition.remainedTime));
        }
      }
      DailyNoteReminderPlan.add(result, 1, '派遣预计全部完成', seconds);
    }
    if ((flags & 8) !== 0 && note.transformer.hasTransformer() && !note.transformer.isReady()) {
      const recovery = note.transformer;
      DailyNoteReminderPlan.add(result, 3, '参量质变仪预计可使用',
        recovery.day * 86400 + recovery.hour * 3600 + recovery.minute * 60 + recovery.second);
    }
    if ((flags & 16) !== 0 && note.currentHomeCoin < homeThreshold && homeThreshold <= note.maxHomeCoin) {
      const remaining: number = note.maxHomeCoin - note.currentHomeCoin;
      if (remaining > 0) {
        DailyNoteReminderPlan.add(result, 4, `洞天宝钱预计达到 ${homeThreshold}`,
          Number(note.homeCoinRecoveryTime) * (homeThreshold - note.currentHomeCoin) / remaining);
      }
    }
    const elapsed: number = note.refreshTime > 0 ? Math.max(0, (Date.now() - note.refreshTime) / 1000) : 0;
    for (const reminder of result) { reminder.seconds = Math.ceil(reminder.seconds - elapsed); }
    return result.filter((reminder: DailyNoteReminder): boolean => reminder.seconds > 0);
  }

  private static add(result: DailyNoteReminder[], kind: number, title: string, seconds: number): void {
    if (!Number.isFinite(seconds) || seconds <= 0) { return; }
    const reminder: DailyNoteReminder = new DailyNoteReminder();
    reminder.kind = kind;
    reminder.title = title;
    reminder.seconds = Math.ceil(seconds);
    result.push(reminder);
  }
}
