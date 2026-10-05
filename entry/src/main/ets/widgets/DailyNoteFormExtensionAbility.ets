/** Cached form updates never sign in. Only an explicit refresh tap starts one bounded read-only request. */
import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { AppContextProvider } from '../common/AppContext';
import { FormSnapshot } from '../data/local/FormSnapshot';
import { BackgroundTaskService } from '../service/BackgroundTaskService';
import { DailyNoteService } from '../service/DailyNoteService';
import { BackgroundTaskResult } from '../model/BackgroundTask';

const CARD_REFRESH_TIMEOUT_MS: number = 15000;

export default class DailyNoteFormExtensionAbility extends FormExtensionAbility {
  private refreshing: Set<string> = new Set();
  private nextGeneration: number = 0;
  private generations: Map<string, number> = new Map();

  private injectContext(): void {
    try { AppContextProvider.getAppContext(); } catch (e) { AppContextProvider.init(this.context); }
  }

  private async ensureRuntime(): Promise<void> {
    this.injectContext();
    await BackgroundTaskService.init(this.context);
  }

  private async publishCached(formId: string): Promise<void> {
    try {
      await this.ensureRuntime();
      await DailyNoteService.getInstance().publishCard(formId);
    } catch (e) {
      // No account/session fallback and no raw form identifier or Want logging.
    }
  }

  private async refreshCard(formId: string): Promise<void> {
    if (this.refreshing.has(formId)) { return; }
    this.refreshing.add(formId);
    const generation: number = ++this.nextGeneration;
    this.generations.set(formId, generation);
    const cancelled = (): boolean => this.generations.get(formId) !== generation;
    try {
      await this.ensureRuntime();
      if (cancelled()) { return; }
      await DailyNoteService.getInstance().publishCard(formId, '刷新中…');
      if (cancelled()) { return; }
      const result: BackgroundTaskResult = await BackgroundTaskService.refreshWidget(CARD_REFRESH_TIMEOUT_MS, cancelled);
      if (!cancelled()) {
        await DailyNoteService.getInstance().publishCard(formId, result.status === 'success' ? '' : result.message);
      }
    } catch (e) {
      if (!cancelled()) {
        try { await DailyNoteService.getInstance().publishCard(formId, '刷新失败，请打开应用查看'); } catch (ignored) {}
      }
    } finally {
      if (this.generations.get(formId) === generation) {
        this.refreshing.delete(formId);
        this.generations.delete(formId);
      }
    }
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    this.injectContext();
    // Synchronous construction cannot validate persisted ownership; return safe placeholders first.
    const formId: string = String(want.parameters?.[formInfo.FormParam.IDENTITY_KEY] ?? '');
    if (formId.length > 0) { this.publishCached(formId); }
    return formBindingData.createFormBindingData(FormSnapshot.empty());
  }

  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    this.publishCached(formId);
  }

  onFormEvent(formId: string, message: string): void {
    if (message.length > 1024 || formId.length === 0 || formId.length > 256) { return; }
    let method: string = message;
    try {
      const object: Record<string, Object> = JSON.parse(message) as Record<string, Object>;
      method = String(object['method'] ?? '');
    } catch (e) {}
    if (method === 'refresh') { this.refreshCard(formId); }
  }

  onCastToNormalForm(formId: string): void {}

  onRemoveForm(formId: string): void {
    this.generations.delete(formId);
    this.refreshing.delete(formId);
  }
}
