import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { DailyNoteRecord } from '../data/repo/DailyNoteRepo';
import { DailyNote } from '../model/DailyNote';
import { DailyNoteReminder, DailyNoteReminderPlan } from '../model/DailyNoteReminderPlan';

/** API 24 支持的系统代理提醒。进程退出仍可提醒，但不替代服务器数据刷新。 */
export class DailyNoteReminderService {
  static readonly ENABLED_KEY: string = 'dailynote.agent_enabled';
  static readonly ERROR_KEY: string = 'dailyNoteReminderError';
  private static readonly PREFIX: string = 'daily-note:';

  static isEnabled(): boolean {
    return PreferencesStore.getBool(DailyNoteReminderService.ENABLED_KEY, false);
  }

  static async setEnabled(enabled: boolean): Promise<void> {
    if (enabled && !canIUse('SystemCapability.Notification.ReminderAgent')) {
      throw new Error('此设备不支持系统代理提醒');
    }
    PreferencesStore.setBool(DailyNoteReminderService.ENABLED_KEY, enabled);
    if (!enabled) {
      await DailyNoteReminderService.cancelPrefix(DailyNoteReminderService.PREFIX);
    }
    AppStorage.setOrCreate<string>(DailyNoteReminderService.ERROR_KEY, '');
  }

  static async cancelUser(userId: number): Promise<void> {
    await DailyNoteReminderService.cancelPrefix(`${DailyNoteReminderService.PREFIX}${userId}:`);
  }

  static async cancelUid(userId: number, uid: string): Promise<void> {
    await DailyNoteReminderService.cancelPrefix(`${DailyNoteReminderService.PREFIX}${userId}:${uid}:`);
  }

  private static async cancelPrefix(prefix: string): Promise<void> {
    if (!canIUse('SystemCapability.Notification.ReminderAgent')) { return; }
    const existing: reminderAgentManager.ReminderInfo[] = await reminderAgentManager.getAllValidReminders();
    for (const reminder of existing) {
      if ((reminder.reminderReq.groupId ?? '').startsWith(prefix)) {
        await reminderAgentManager.cancelReminder(reminder.reminderId);
      }
    }
  }

  static async sync(userId: number, uid: string, note: DailyNote, settings?: DailyNoteRecord): Promise<void> {
    if (!DailyNoteReminderService.isEnabled()) { return; }
    if (!canIUse('SystemCapability.Notification.ReminderAgent')) {
      throw new Error('此设备不支持系统代理提醒');
    }
    if (!await notificationManager.isNotificationEnabled()) {
      throw new Error('请先授权系统通知，再启用代理提醒');
    }
    await DailyNoteReminderService.cancelUid(userId, uid);
    const plans: DailyNoteReminder[] = DailyNoteReminderPlan.build(note, settings?.notifyFlags ?? 31,
      settings?.resinNotifyThreshold ?? 120, settings?.homeCoinNotifyThreshold ?? 1800);
    for (const plan of plans) {
      if (!DailyNoteReminderService.isEnabled()) {
        await DailyNoteReminderService.cancelUid(userId, uid);
        return;
      }
      const request: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: plan.seconds,
        title: `UID ${uid} · ${plan.title}`,
        content: '根据上次便笺估算，打开应用刷新最新状态。',
        expiredContent: '打开应用查看最新便笺。',
        ringDuration: 0,
        slotType: notificationManager.SlotType.SERVICE_INFORMATION,
        notificationId: DailyNoteReminderService.notificationId(uid, plan.kind),
        groupId: `${DailyNoteReminderService.PREFIX}${userId}:${uid}:${plan.kind}`,
        wantAgent: { pkgName: 'com.example.snaphutaoharmonyos', abilityName: 'EntryAbility' },
      };
      try {
        await reminderAgentManager.publishReminder(request);
      } catch (e) {
        const error: BusinessError = e as BusinessError;
        const reason: string = error.code === 1700002 ? '系统提醒数量已达上限' :
          (error.code === 201 || error.code === 1700001 ? '系统未授予提醒权限' : error.message);
        throw new Error(`代理提醒未发布：${reason}（${error.code}）`);
      }
    }
    AppStorage.setOrCreate<string>(DailyNoteReminderService.ERROR_KEY, '');
  }

  private static notificationId(uid: string, kind: number): number {
    let hash: number = 0;
    for (let i: number = 0; i < uid.length; i++) {
      hash = (hash * 31 + uid.charCodeAt(i)) % 200000000;
    }
    return hash * 10 + kind;
  }
}
