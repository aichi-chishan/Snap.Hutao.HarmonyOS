/**
 * DailyNoteFormExtensionAbility.ets
 * 实时便笺桌面卡片：onAddForm/onUpdateForm 读取最新便笺快照（FormSnapshot）→ formBindingData 渲染；
 * 定时刷新由 form_config 的 updateEnabled/scheduledUpdateTime 驱动 onUpdateForm。
 * 手动刷新：卡片右上角 ⟳ → postCardAction(message) → onFormEvent → 补齐运行时（偏好/DB/会话）
 *   → DailyNoteService.refreshForCard（带超时）→ 回推卡片；失败时把原因写在卡片 tipText 上。
 */
import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { AppContextProvider } from '../common/AppContext';
import { FormSnapshot } from '../data/local/FormSnapshot';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { RelationalStoreHelper } from '../data/db/RelationalStoreHelper';
import { UserService } from '../service/UserService';
import { DailyNoteService } from '../service/DailyNoteService';
import { Logger } from '../common/Logger';

const TAG: string = 'DailyNoteForm';
/** 卡片手动刷新超时（命中需 UI 的风控时不无限占用卡片进程） */
const CARD_REFRESH_TIMEOUT_MS: number = 15000;

export default class DailyNoteFormExtensionAbility extends FormExtensionAbility {
  private buildCardData(): formBindingData.FormBindingData {
    const snapshot: Record<string, string> = FormSnapshot.load();
    return formBindingData.createFormBindingData(snapshot);
  }

  /** 卡片进程可能独立于主应用：补齐偏好/数据库/会话运行时（已就绪时为空操作） */
  private async ensureRuntime(): Promise<void> {
    AppContextProvider.init(this.context);
    if (!PreferencesStore.isReady()) {
      await PreferencesStore.init(this.context);
    }
    if (!RelationalStoreHelper.isReady()) {
      await RelationalStoreHelper.init(this.context);
    }
    if (UserService.getInstance().getCurrentUser() === undefined) {
      await UserService.getInstance().restoreSession();
    }
  }

  /** 推送一条卡片提示（保留既有快照数据，仅覆盖 tipText） */
  private pushTip(formId: string, tip: string): void {
    const data: Record<string, string> = FormSnapshot.load();
    data['tipText'] = tip;
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data)).catch((e: Error) => {
      Logger.warn(TAG, `pushTip fail ${e.message}`);
    });
  }

  /** 卡片 ⟳ 手动刷新：拉取最新便笺并回推卡片 */
  private async refreshCard(formId: string): Promise<void> {
    this.pushTip(formId, '刷新中…');
    try {
      await this.ensureRuntime();
      const uid: string = PreferencesStore.getCurrentUid();
      if (uid.length === 0) {
        this.pushTip(formId, '请先打开应用登录并绑定 UID');
        return;
      }
      await DailyNoteService.getInstance().refreshForCard(uid, CARD_REFRESH_TIMEOUT_MS);
      // 成功：服务层已写快照并推送全部卡片，此处兜底再推一次本卡片
      await formProvider.updateForm(formId, this.buildCardData());
      Logger.info(TAG, `manual refresh ok formId=${formId}`);
    } catch (e) {
      const msg: string = (e as Error).message;
      Logger.warn(TAG, `manual refresh fail ${msg}`);
      this.pushTip(formId, msg.length > 0 && msg.length <= 20 ? msg : '刷新失败，请打开应用重试');
    }
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    AppContextProvider.init(this.context);
    Logger.info(TAG, `onAddForm want=${JSON.stringify(want)}`);
    return this.buildCardData();
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    AppContextProvider.init(this.context);
    Logger.info(TAG, `onUpdateForm formId=${formId}`);
    formProvider.updateForm(formId, this.buildCardData()).catch((e: Error) => {
      Logger.warn(TAG, `onUpdateForm updateForm fail ${e.message}`);
    });
  }

  /** 卡片交互事件（postCardAction action='message'）：当前仅支持手动刷新 */
  onFormEvent(formId: string, message: string): void {
    Logger.info(TAG, `onFormEvent formId=${formId} message=${message}`);
    let method: string = message;
    try {
      const obj = JSON.parse(message) as Record<string, Object>;
      const m: Object = obj['method'];
      if (m !== undefined && m !== null) {
        method = String(m);
      }
    } catch (e) {
      // message 非 JSON：按原始字符串匹配
    }
    if (method === 'refresh') {
      this.refreshCard(formId);
    }
  }

  onCastToNormalForm(formId: string): void {
    Logger.info(TAG, `onCastToNormalForm formId=${formId}`);
  }

  onRemoveForm(formId: string): void {
    Logger.info(TAG, `onRemoveForm formId=${formId}`);
  }
}
