/**
 * DailyNoteFormExtensionAbility.ets
 * 实时便笺桌面卡片：onAddForm/onUpdateForm 读取最新便笺快照（FormSnapshot）→ formBindingData 渲染；
 * 定时刷新由 form_config 的 updateEnabled/scheduledUpdateTime 驱动 onUpdateForm。
 */
import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { AppContextProvider } from '../common/AppContext';
import { FormSnapshot } from '../data/local/FormSnapshot';
import { Logger } from '../common/Logger';

const TAG: string = 'DailyNoteForm';

export default class DailyNoteFormExtensionAbility extends FormExtensionAbility {
  private buildCardData(): formBindingData.FormBindingData {
    const snapshot: Record<string, string> = FormSnapshot.load();
    return formBindingData.createFormBindingData(snapshot);
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

  onCastToNormalForm(formId: string): void {
    Logger.info(TAG, `onCastToNormalForm formId=${formId}`);
  }

  onRemoveForm(formId: string): void {
    Logger.info(TAG, `onRemoveForm formId=${formId}`);
  }
}
