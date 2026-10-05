import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { BackgroundTaskService } from '../service/BackgroundTaskService';

/** OS may defer execution or stop the task at any time. No UIAbility is started here. */
export default class HutaoWorkSchedulerExtensionAbility extends WorkSchedulerExtensionAbility {
  private generations: Map<number, number> = new Map();
  private epochs: Map<number, number> = new Map();

  onWorkStart(work: workScheduler.WorkInfo): void {
    const generation: number = (this.generations.get(work.workId) ?? 0) + 1;
    this.generations.set(work.workId, generation);
    this.epochs.set(work.workId, Number(work.parameters?.['epoch'] ?? -1));
    BackgroundTaskService.init(this.context).then(async (): Promise<void> => {
      if (generation === this.generations.get(work.workId)) { await BackgroundTaskService.onWorkStart(work); }
    }).catch(() => {
      // Never log work parameters or account details; no interactive fallback from an extension.
      try { workScheduler.stopWork(work, false); } catch (e) {}
    });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
    if (Number(work.parameters?.['epoch'] ?? -1) === this.epochs.get(work.workId)) {
      this.generations.set(work.workId, (this.generations.get(work.workId) ?? 0) + 1);
    }
    BackgroundTaskService.onWorkStop(work);
  }
}
