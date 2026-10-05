import { BackgroundTaskBinding, BackgroundTaskKind, BackgroundTaskResult, BackgroundTaskState } from '../model/BackgroundTask';
import { BackgroundTaskService } from '../service/BackgroundTaskService';
import { AutoSignInService } from '../service/AutoSignInService';
import { UserService } from '../service/UserService';

/** A single-use consent ticket, scoped to this visible settings instance and account revision. */
export class BackgroundEnableReview {
  kind: BackgroundTaskKind = BackgroundTaskKind.DAILY_NOTE;
  binding: BackgroundTaskBinding = new BackgroundTaskBinding();
  generation: number = 0;
}

@Observed
export class BackgroundTaskSettingsViewModel {
  daily: BackgroundTaskState = new BackgroundTaskState();
  signIn: BackgroundTaskState = new BackgroundTaskState();
  busy: boolean = false;
  message: string = '';
  private active: boolean = false;
  private generation: number = 0;
  private refreshSequence: number = 0;
  private operationPending: boolean = false;
  private review: BackgroundEnableReview | undefined = undefined;
  private unsubscribe: (() => void) | undefined = undefined;

  activate(): void {
    if (this.active) { return; }
    this.active = true;
    this.generation++;
    this.message = '';
    this.busy = this.operationPending;
    const generation: number = this.generation;
    this.unsubscribe = UserService.getInstance().addSessionRevisionListener(() => {
      if (!this.current(generation)) { return; }
      this.review = undefined;
      this.busy = this.operationPending;
      this.message = '账号状态已变化；开启后台任务前请重新确认 UID';
      this.refresh();
    });
    this.refresh();
  }

  invalidate(): void {
    this.active = false;
    this.generation++;
    this.refreshSequence++;
    this.review = undefined;
    this.unsubscribe?.(); this.unsubscribe = undefined;
  }

  private current(generation: number): boolean { return this.active && generation === this.generation; }

  async refresh(): Promise<void> {
    if (!this.active) { return; }
    const generation: number = this.generation;
    const sequence: number = ++this.refreshSequence;
    try {
      const daily: BackgroundTaskState = await BackgroundTaskService.getState(BackgroundTaskKind.DAILY_NOTE);
      const signIn: BackgroundTaskState = await BackgroundTaskService.getState(BackgroundTaskKind.SIGN_IN);
      if (this.current(generation) && sequence === this.refreshSequence) { this.daily = daily; this.signIn = signIn; }
    } catch (e) { if (this.current(generation) && sequence === this.refreshSequence) { this.message = '无法读取后台任务状态，请稍后重试'; } }
  }

  prepareEnable(kind: BackgroundTaskKind): BackgroundEnableReview | undefined {
    if (!this.active || this.busy || this.operationPending) { return undefined; }
    try {
      const review: BackgroundEnableReview = new BackgroundEnableReview();
      review.kind = kind;
      review.binding = BackgroundTaskService.captureBinding();
      review.generation = this.generation;
      this.review = review;
      this.busy = true;
      this.message = '';
      return review;
    } catch (e) { this.message = '请先登录并选择属于此账号的 UID'; return undefined; }
  }

  cancelEnable(review: BackgroundEnableReview): void {
    if (this.review !== review) { return; }
    this.review = undefined;
    if (this.active) { this.busy = this.operationPending; }
  }

  async confirmEnable(review: BackgroundEnableReview): Promise<void> {
    if (this.review !== review || !this.current(review.generation) || this.operationPending) { return; }
    this.review = undefined;
    if (review.binding.revision !== UserService.getInstance().sessionRevision()) {
      this.busy = false; this.message = '账号状态已变化，请重新确认 UID'; return;
    }
    await this.run(async (): Promise<void> => {
      await BackgroundTaskService.setEnabled(review.kind, true, review.binding);
    });
  }

  async disable(kind: BackgroundTaskKind): Promise<void> {
    if (!this.active || this.busy) { return; }
    await this.run(async (): Promise<void> => { await BackgroundTaskService.setEnabled(kind, false); });
  }

  async retry(kind: BackgroundTaskKind): Promise<void> {
    if (!this.active || this.busy) { return; }
    await this.run(async (): Promise<void> => { await BackgroundTaskService.retryBlocked(kind); });
  }

  /** Explicit foreground action only. Page activation never calls the sign-in service. */
  async retryCurrentSignIn(): Promise<void> {
    if (!this.active || this.busy) { return; }
    await this.run(async (): Promise<void> => {
      const generation: number = this.generation;
      const revision: number = UserService.getInstance().sessionRevision();
      const result: BackgroundTaskResult = await AutoSignInService.getInstance().retryCurrent();
      if (this.current(generation) && revision === UserService.getInstance().sessionRevision()) { this.message = result.message; }
    });
  }

  private async run(action: () => Promise<void>): Promise<void> {
    if (!this.active || this.operationPending) { return; }
    const generation: number = this.generation;
    this.operationPending = true; this.busy = true; this.message = '';
    try { await action(); }
    catch (e) { if (this.current(generation)) { this.message = '操作未完成；请检查账号绑定与任务状态后重试'; } }
    finally {
      this.operationPending = false;
      if (this.active) { this.busy = false; await this.refresh(); }
    }
  }
}
