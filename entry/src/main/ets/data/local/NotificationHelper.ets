/**
 * NotificationHelper.ets
 * @ohos.notificationManager 封装：通知渠道、发布/取消本地通知、通知权限申请。
 */
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../../common/Logger';

const TAG: string = 'NotificationHelper';

export class NotificationHelper {
  static readonly CHANNEL_ID: string = 'dailynote_threshold';

  /** 初始化渠道（应用启动/首次使用通知前调用） */
  static async init(): Promise<void> {
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
      Logger.info(TAG, 'slot created');
    } catch (e) {
      Logger.warn(TAG, 'addSlot fail');
    }
  }

  /** 通知是否已授权 */
  static isEnabled(): boolean {
    try {
      return notificationManager.isNotificationEnabledSync();
    } catch (e) {
      return false;
    }
  }

  /** 申请通知权限（需 UIAbilityContext） */
  static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }
      await notificationManager.requestEnableNotification(context);
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      Logger.warn(TAG, 'requestPermission fail');
      return false;
    }
  }

  /** 发布本地通知（id 相同则更新） */
  static async publish(title: string, text: string, id: number): Promise<void> {
    const request: notificationManager.NotificationRequest = {
      id: id,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text,
        },
      },
    };
    try {
      await notificationManager.publish(request);
      Logger.info(TAG, `published id=${id} title=${title}`);
    } catch (e) {
      const err = e as BusinessError;
      Logger.warn(TAG, `publish fail code=${err.code}`);
    }
  }

  /** 取消通知 */
  static async cancel(id: number): Promise<void> {
    try {
      await notificationManager.cancel(id);
    } catch (e) {
      Logger.warn(TAG, 'cancel fail');
    }
  }
}
