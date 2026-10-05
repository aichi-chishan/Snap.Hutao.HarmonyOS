/** API24 taskpool admission stays occupied until native execution AND hydration settle. */
import { taskpool } from '@kit.ArkTS';
import { prepareUigfImport } from '../data/taskpool/UigfImportWorker';
import { UigfBounds } from '../model/UigfBounds';
import { UigfImportPreparation } from '../model/UigfImportPreparation';
import { UigfImportTransfer } from './UigfImportTransfer';

export class UigfImportJob {
  private static occupied: boolean = false;
  private task: taskpool.Task | undefined = undefined;
  private cancelled: boolean = false;
  private rejectWaiter: ((reason: Error) => void) | undefined = undefined;
  private timer: number = -1;

  cancel(): void {
    this.cancelled = true;
    this.rejectWaiter?.(new Error('UIGF 解析已取消'));
    if (this.task !== undefined) {
      try { taskpool.cancel(this.task); } catch (_) { /* Already settled: ownership fence still applies. */ }
    }
  }

  async prepare(source: string, isFile: boolean, checkCurrent: () => void): Promise<UigfImportPreparation> {
    if (this.cancelled) { throw new Error('UIGF 解析已取消'); }
    checkCurrent();
    if (UigfImportJob.occupied) { throw new Error('UIGF 后台解析仍在处理，请稍后重试'); }
    if (!isFile && (source.length === 0 || source.length > UigfBounds.MAX_TEXT_UNITS)) { throw new Error('UIGF 文件为空或超过 32 Mi 字符限制'); }
    UigfImportJob.occupied = true;
    const deadline: number = Date.now() + UigfBounds.WAIT_MS;
    let execution: Promise<Object>;
    try {
      this.task = new taskpool.Task(prepareUigfImport, source, isFile, deadline);
      execution = taskpool.execute(this.task);
    } catch (_) {
      this.task = undefined;
      UigfImportJob.occupied = false;
      throw new Error('UIGF 后台任务无法启动，请稍后重试');
    }
    return new Promise<UigfImportPreparation>((resolve, reject) => {
      let waiting: boolean = true;
      this.rejectWaiter = (error: Error): void => {
        if (waiting) { waiting = false; reject(error); }
      };
      this.timer = setTimeout(() => {
        this.rejectWaiter?.(new Error('UIGF 后台解析超时，请拆分文件后重试'));
        this.cancel();
      }, UigfBounds.WAIT_MS);
      execution.then(async (wire: Object) => {
        let prepared: UigfImportPreparation | undefined = undefined;
        try {
          if (!waiting) { return; }
          const check: () => void = (): void => {
            checkCurrent();
            if (this.cancelled || !waiting) { throw new Error('UIGF 解析已取消'); }
            if (Date.now() >= deadline) { throw new Error('UIGF 后台解析超时，请拆分文件后重试'); }
          };
          prepared = await UigfImportTransfer.adopt(wire as string[], check);
          check();
          waiting = false;
          resolve(prepared);
          prepared = undefined;
        } catch (e) { this.rejectWaiter?.(e as Error); }
        finally { prepared?.dispose(); this.release(); }
      }, (_: Error) => {
        this.rejectWaiter?.(new Error(this.cancelled ? 'UIGF 解析已取消' : 'UIGF 后台任务失败，请重新选择文件'));
        this.release();
      });
    });
  }

  private release(): void {
    clearTimeout(this.timer);
    this.rejectWaiter = undefined;
    this.task = undefined;
    UigfImportJob.occupied = false;
  }
}
