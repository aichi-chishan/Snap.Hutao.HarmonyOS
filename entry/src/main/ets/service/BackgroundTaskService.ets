import { common } from '@kit.AbilityKit';
import { workScheduler } from '@kit.BackgroundTasksKit';
import { AppContextProvider } from '../common/AppContext';
import { RegionUtil } from '../common/Constants';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { RelationalStoreHelper } from '../data/db/RelationalStoreHelper';
import { BackgroundTaskRepo } from '../data/repo/BackgroundTaskRepo';
import { UserRepo } from '../data/repo/UserRepo';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { BackgroundTaskGuard, BackgroundTaskKind, BackgroundTaskPolicy, BackgroundTaskResult,
  BackgroundTaskState, BackgroundOperation, BackgroundTaskBinding } from '../model/BackgroundTask';
import { AutoSignInService } from './AutoSignInService';
import { DailyNoteService } from './DailyNoteService';
import { UserService } from './UserService';

class NativeTaskGuard implements BackgroundTaskGuard {
  cancelled: boolean = false;
  state: BackgroundTaskState;
  token: string;
  constructor(state: BackgroundTaskState, token: string) { this.state = state; this.token = token; }
  async isActive(): Promise<boolean> {
    if (this.cancelled || !await BackgroundTaskRepo.live(this.state.kind, this.state.epoch, this.token)) { return false; }
    const user: User | undefined = await BackgroundTaskService.boundUser(this.state);
    return !this.cancelled && user !== undefined &&
      await BackgroundTaskRepo.live(this.state.kind, this.state.epoch, this.token);
  }
}

class WidgetTaskGuard implements BackgroundTaskGuard {
  cancelled: boolean = false;
  private state: BackgroundTaskState;
  private token: string;
  private deadline: number;
  private cancelledByCaller: () => boolean;
  constructor(state: BackgroundTaskState, token: string, deadline: number, cancelledByCaller: () => boolean) {
    this.state = state; this.token = token; this.deadline = deadline; this.cancelledByCaller = cancelledByCaller;
  }
  async isActive(): Promise<boolean> {
    if (this.cancelled || this.cancelledByCaller() || Date.now() >= this.deadline) { return false; }
    if ((await BackgroundTaskRepo.get(BackgroundTaskKind.DAILY_NOTE)).epoch !== this.state.epoch) { return false; }
    if (await BackgroundTaskService.boundUser(this.state) === undefined) { return false; }
    const op: BackgroundOperation = await BackgroundTaskRepo.operation(
      BackgroundTaskKind.DAILY_NOTE, this.state.userId, this.state.uid, this.state.region);
    return !this.cancelled && !this.cancelledByCaller() && Date.now() < this.deadline &&
      op.lease === this.token && op.leaseUntil > Date.now() &&
      (await BackgroundTaskRepo.get(BackgroundTaskKind.DAILY_NOTE)).epoch === this.state.epoch;
  }
}

/** Best-effort OS deferred work, never a precise alarm or foreground-service workaround. */
export class BackgroundTaskService {
  static readonly STATUS_VERSION_KEY: string = 'backgroundTaskStatusVersion';
  static readonly EXPLANATION: string = '后台任务只绑定开启时选择的账号和 UID。系统按电量、网络和使用情况择机执行，不能保证固定间隔或零点签到。退出登录、切换账号或恢复数据会停止旧任务；需要验证时请回到应用处理。';
  private static readonly BUNDLE: string = 'com.example.snaphutaoharmonyos';
  private static readonly ABILITY: string = 'HutaoWorkSchedulerExtensionAbility';
  private static readonly DAILY_WORK_ID: number = 19001;
  private static readonly SIGN_WORK_ID: number = 20001;
  private static guards: Map<BackgroundTaskKind, NativeTaskGuard> = new Map();
  private static changes: Promise<void> = Promise.resolve();
  private static initializing: Promise<void> | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (BackgroundTaskService.initializing === undefined) {
      BackgroundTaskService.initializing = BackgroundTaskService.initialize(context);
    }
    const pending: Promise<void> = BackgroundTaskService.initializing;
    try { await pending; }
    finally { if (BackgroundTaskService.initializing === pending) { BackgroundTaskService.initializing = undefined; } }
  }

  private static async initialize(context: common.Context): Promise<void> {
    // Do not replace a live UIAbilityContext with an extension context in a shared process.
    try { AppContextProvider.getAppContext(); } catch (e) { AppContextProvider.init(context); }
    await PreferencesStore.init(context);
    await RelationalStoreHelper.init(context);
    await BackgroundTaskRepo.init(context);
  }

  private static async serialize(action: () => Promise<void>): Promise<void> {
    const next: Promise<void> = BackgroundTaskService.changes.then(action, action);
    BackgroundTaskService.changes = next.catch(() => {});
    return next;
  }

  private static changed(): void {
    const version: number = AppStorage.get<number>(BackgroundTaskService.STATUS_VERSION_KEY) ?? 0;
    AppStorage.setOrCreate<number>(BackgroundTaskService.STATUS_VERSION_KEY, version + 1);
  }

  static async getState(kind: BackgroundTaskKind): Promise<BackgroundTaskState> {
    const state: BackgroundTaskState = await BackgroundTaskRepo.get(kind);
    if (state.status === 'running' && (state.leaseUntil <= Date.now() || state.leaseUntil > Date.now() + 86400000)) {
      state.status = 'interrupted';
      state.message = '上次任务未完成，等待系统重新调度';
    }
    return state;
  }

  static captureBinding(): BackgroundTaskBinding {
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    const uid: string = PreferencesStore.getCurrentUid();
    const region: string = RegionUtil.regionOfUid(uid);
    if (user === undefined || user.id !== PreferencesStore.getCurrentUserId() ||
      !BackgroundTaskPolicy.owns(user, uid, region)) { throw new Error('请先登录并选择属于此账号的 UID'); }
    const binding: BackgroundTaskBinding = new BackgroundTaskBinding();
    binding.revision = UserService.getInstance().sessionRevision();
    binding.userId = user.id; binding.uid = uid; binding.region = region;
    binding.identity = BackgroundTaskPolicy.identity(user);
    return binding;
  }

  private static currentBinding(binding: BackgroundTaskBinding): boolean {
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    return !UserService.getInstance().isSessionTransitionPending() &&
      PreferencesStore.getBackupJournal().length === 0 && user !== undefined &&
      UserService.getInstance().sessionRevision() === binding.revision && user.id === binding.userId &&
      PreferencesStore.getCurrentUserId() === binding.userId && PreferencesStore.getCurrentUid() === binding.uid &&
      BackgroundTaskPolicy.identity(user) === binding.identity && BackgroundTaskPolicy.owns(user, binding.uid, binding.region);
  }

  /** User-facing explicit toggle. Capture before any await; never bind a newly selected account implicitly. */
  static async setEnabled(kind: BackgroundTaskKind, enabled: boolean, expectedBinding?: BackgroundTaskBinding): Promise<void> {
    const binding: BackgroundTaskBinding | undefined = enabled ? expectedBinding ?? BackgroundTaskService.captureBinding() : undefined;
    await BackgroundTaskService.serialize(async (): Promise<void> => {
      if (binding !== undefined && !BackgroundTaskService.currentBinding(binding)) {
        throw new Error('账号或 UID 已变化，请重新确认后台任务绑定');
      }
      const state: BackgroundTaskState = await BackgroundTaskRepo.get(kind);
      state.enabled = enabled;
      if (enabled && binding !== undefined) {
        if (!BackgroundTaskService.currentBinding(binding)) { throw new Error('账号或 UID 已变化，请重新确认绑定'); }
        if (!canIUse('SystemCapability.ResourceSchedule.WorkScheduler')) {
          throw new Error('此设备不支持系统延迟任务');
        }
        state.userId = binding.userId; state.uid = binding.uid; state.region = binding.region;
        state.identity = binding.identity;
        const user: User | undefined = await BackgroundTaskService.boundUser(state);
        if (!BackgroundTaskService.currentBinding(binding) || user === undefined || !user.hasCookie()) {
          throw new Error('账号或 UID 已变化，请重新确认绑定');
        }
        state.intervalMinutes = kind === BackgroundTaskKind.DAILY_NOTE
          ? BackgroundTaskPolicy.interval(PreferencesStore.getRefreshIntervalMinutes()) : 30;
      }
      BackgroundTaskService.cancelLocal(kind);
      await BackgroundTaskRepo.configure(state);
      if (enabled && binding !== undefined && !BackgroundTaskService.currentBinding(binding)) {
        await BackgroundTaskRepo.stop(kind, '账号或 UID 已变化，需要重新确认绑定');
        await BackgroundTaskService.reconcileKind(kind);
        throw new Error('账号或 UID 已变化，请重新确认绑定');
      }
      if (enabled) { await BackgroundTaskRepo.clearBlocked(state); }
      if (enabled && binding !== undefined && !BackgroundTaskService.currentBinding(binding)) {
        await BackgroundTaskRepo.stop(kind, '账号或 UID 已变化，需要重新确认绑定');
        await BackgroundTaskService.reconcileKind(kind);
        throw new Error('账号或 UID 已变化，请重新确认绑定');
      }
      await BackgroundTaskService.reconcileKind(kind);
      if (enabled && binding !== undefined && !BackgroundTaskService.currentBinding(binding)) {
        await BackgroundTaskRepo.stop(kind, '账号或 UID 已变化，需要重新确认绑定');
        await BackgroundTaskService.reconcileKind(kind);
        throw new Error('账号或 UID 已变化，请重新确认绑定');
      }
      BackgroundTaskService.changed();
    });
  }

  /** Reconcile on startup/foreground/settings changes. Does not execute network jobs. */
  static async reconcile(): Promise<void> {
    await BackgroundTaskService.serialize(async (): Promise<void> => {
      for (const kind of BackgroundTaskPolicy.KINDS) { await BackgroundTaskService.reconcileKind(kind); }
      BackgroundTaskService.changed();
    });
  }

  private static work(kind: BackgroundTaskKind, state?: BackgroundTaskState): workScheduler.WorkInfo {
    const work: workScheduler.WorkInfo = {
      workId: kind === BackgroundTaskKind.DAILY_NOTE ? BackgroundTaskService.DAILY_WORK_ID : BackgroundTaskService.SIGN_WORK_ID,
      bundleName: BackgroundTaskService.BUNDLE, abilityName: BackgroundTaskService.ABILITY,
    };
    if (state !== undefined) {
      work.isPersisted = true;
      work.networkType = workScheduler.NetworkType.NETWORK_TYPE_ANY;
      work.isRepeat = true;
      work.repeatCycleTime = BackgroundTaskPolicy.interval(state.intervalMinutes) * 60000;
      work.earliestStartTime = work.repeatCycleTime;
      // Only a configuration generation, never a UID, account identifier or credential.
      work.parameters = { 'epoch': state.epoch };
    }
    return work;
  }

  private static replacementPending(): boolean {
    return PreferencesStore.getBackupJournal().length > 0 || UserService.getInstance().isSessionTransitionPending();
  }

  private static async reconcileKind(kind: BackgroundTaskKind): Promise<void> {
    let state: BackgroundTaskState = await BackgroundTaskRepo.get(kind);
    if (!canIUse('SystemCapability.ResourceSchedule.WorkScheduler')) {
      await BackgroundTaskRepo.scheduling(kind, state.epoch, false, 'unsupported', '此设备不支持系统延迟任务');
      return;
    }
    try {
      const works: workScheduler.WorkInfo[] = await workScheduler.obtainAllWorks();
      const existing: workScheduler.WorkInfo | undefined = works.find(work => work.workId === BackgroundTaskService.work(kind).workId);
      if (state.enabled && BackgroundTaskService.replacementPending()) {
        BackgroundTaskService.cancelLocal(kind);
        await BackgroundTaskRepo.fence(kind);
        if (existing !== undefined) { workScheduler.stopWork(existing, true); }
        return;
      }
      if (state.enabled && await BackgroundTaskService.boundUser(state) === undefined) {
        BackgroundTaskService.cancelLocal(kind);
        if (BackgroundTaskService.replacementPending()) {
          await BackgroundTaskRepo.fence(kind);
          if (existing !== undefined) { workScheduler.stopWork(existing, true); }
          return;
        }
        await BackgroundTaskRepo.stop(kind, '账号或 UID 已变化，请重新开启并确认绑定');
        state = await BackgroundTaskRepo.get(kind);
      }
      if (!state.enabled) {
        if (existing !== undefined) { workScheduler.stopWork(existing, true); }
        await BackgroundTaskRepo.scheduling(kind, state.epoch, false, 'disabled', state.message);
        return;
      }
      const wanted: workScheduler.WorkInfo = BackgroundTaskService.work(kind, state);
      if (existing !== undefined && existing.parameters?.['epoch'] === state.epoch &&
        existing.repeatCycleTime === wanted.repeatCycleTime && existing.isPersisted === true) {
        // Keep last outcome rather than disguising blocked/manual states as fresh success.
        await BackgroundTaskRepo.scheduling(kind, state.epoch, true, state.status === 'pending' ? 'queued' : state.status,
          state.status === 'pending' ? '已排队，执行时间由系统决定' : state.message);
        return;
      }
      if (existing !== undefined) { workScheduler.stopWork(existing, true); }
      workScheduler.startWork(wanted);
      await BackgroundTaskRepo.scheduling(kind, state.epoch, true, 'queued', '已排队，执行时间由系统决定');
    } catch (e) {
      await BackgroundTaskRepo.scheduling(kind, state.epoch, false, 'blocked', '系统任务注册或取消失败，请在应用内重新排队');
    }
  }

  /** A deliberate retry clears manual/captcha blocks only for the currently bound owner. */
  static async retryBlocked(kind: BackgroundTaskKind): Promise<void> {
    await BackgroundTaskService.serialize(async (): Promise<void> => {
      const state: BackgroundTaskState = await BackgroundTaskRepo.get(kind);
      if (!state.enabled || await BackgroundTaskService.boundUser(state) === undefined) {
        throw new Error('请先重新开启并确认账号与 UID 绑定');
      }
      BackgroundTaskService.cancelLocal(kind);
      await BackgroundTaskRepo.configure(state);
      await BackgroundTaskRepo.clearBlocked(state);
      await BackgroundTaskService.reconcileKind(kind);
      BackgroundTaskService.changed();
    });
  }

  /** Re-read authoritative account/selection/role data; never restore or switch the global session. */
  static async boundUser(state: BackgroundTaskState): Promise<User | undefined> {
    if (PreferencesStore.getBackupJournal().length > 0 ||
      UserService.getInstance().isSessionTransitionPending()) { return undefined; }
    if (await UserRepo.getSelectedUserId() !== state.userId) { return undefined; }
    const user: User | undefined = await UserRepo.getUserById(state.userId);
    if (user === undefined || BackgroundTaskPolicy.identity(user) !== state.identity ||
      !BackgroundTaskPolicy.owns(user, state.uid, state.region)) { return undefined; }
    const selected: UserGameRole | undefined = await UserRepo.getDefaultRole(state.userId);
    if (selected === undefined || selected.gameUid !== state.uid || selected.region !== state.region ||
      await UserRepo.getSelectedUserId() !== state.userId || PreferencesStore.getBackupJournal().length > 0 ||
      UserService.getInstance().isSessionTransitionPending()) { return undefined; }
    return user;
  }

  private static kind(work: workScheduler.WorkInfo): BackgroundTaskKind | undefined {
    if (work.bundleName !== BackgroundTaskService.BUNDLE || work.abilityName !== BackgroundTaskService.ABILITY) { return undefined; }
    if (work.workId === BackgroundTaskService.DAILY_WORK_ID) { return BackgroundTaskKind.DAILY_NOTE; }
    if (work.workId === BackgroundTaskService.SIGN_WORK_ID) { return BackgroundTaskKind.SIGN_IN; }
    return undefined;
  }

  static async onWorkStart(work: workScheduler.WorkInfo): Promise<void> {
    const kind: BackgroundTaskKind | undefined = BackgroundTaskService.kind(work);
    if (kind === undefined) { return; }
    const state: BackgroundTaskState = await BackgroundTaskRepo.get(kind);
    if (!state.enabled) {
      try { workScheduler.stopWork(work, true); } catch (e) {}
      return;
    }
    if (work.parameters?.['epoch'] !== state.epoch) { return; }
    const user: User | undefined = await BackgroundTaskService.boundUser(state);
    if (user === undefined) {
      if (BackgroundTaskService.replacementPending()) { await BackgroundTaskRepo.fence(kind); }
      else { await BackgroundTaskRepo.stop(kind, '账号或 UID 已变化，请重新开启并确认绑定'); }
      try { workScheduler.stopWork(work, true); } catch (e) {}
      BackgroundTaskService.changed();
      return;
    }
    const token: string = `${Date.now()}-${Math.random()}`;
    if (!await BackgroundTaskRepo.claim(state, token, Date.now())) { return; }
    const guard: NativeTaskGuard = new NativeTaskGuard(state, token);
    BackgroundTaskService.guards.set(kind, guard);
    let timer: number = -1;
    const timeout: Promise<BackgroundTaskResult> = new Promise<BackgroundTaskResult>((resolve) => {
      timer = setTimeout(() => {
        guard.cancelled = true;
        resolve(BackgroundTaskResult.of('timeout', '系统任务时限已到，等待下次调度'));
      }, BackgroundTaskPolicy.BUDGET_MS);
    });
    let result: BackgroundTaskResult;
    try {
      result = await Promise.race<BackgroundTaskResult>([
        BackgroundTaskService.execute(state, user, guard), timeout,
      ]);
    } catch (e) {
      result = BackgroundTaskResult.of('blocked', '后台处理失败，请打开应用检查状态后重新排队');
    } finally {
      clearTimeout(timer);
      guard.cancelled = true;
      if (BackgroundTaskService.guards.get(kind) === guard) { BackgroundTaskService.guards.delete(kind); }
    }
    await BackgroundTaskRepo.finish(state, token, result);
    BackgroundTaskService.changed();
    // false ends this execution while retaining the persisted repeating schedule.
    try { workScheduler.stopWork(work, false); } catch (e) {}
  }

  private static async execute(state: BackgroundTaskState, user: User, guard: NativeTaskGuard): Promise<BackgroundTaskResult> {
    if (state.kind === BackgroundTaskKind.SIGN_IN) {
      return AutoSignInService.getInstance().runBackground(user, state.uid, state.region, guard);
    }
    const day: string = BackgroundTaskPolicy.day(state.region);
    const op: BackgroundOperation = await BackgroundTaskRepo.operation(state.kind, state.userId, state.uid, state.region);
    if (!BackgroundTaskPolicy.due(op, day, Date.now(), false)) {
      if (op.day === day && (op.status === 'captcha' || op.status === 'login_required' || op.status === 'manual')) {
        return BackgroundTaskResult.of(op.status, '需要手动处理，请在应用内处理后重新排队');
      }
      return BackgroundTaskResult.of('cooldown', '便笺刚刷新或仍在冷却，等待下次调度');
    }
    if (!await guard.isActive() || !await BackgroundTaskRepo.claimOperation(op, day, guard.token, Date.now())) {
      return BackgroundTaskResult.of('cancelled', '任务已停止或已有任务在执行');
    }
    let result: BackgroundTaskResult;
    try { result = await DailyNoteService.getInstance().refreshBackground(user, state.uid, state.region, guard); }
    catch (e) { result = BackgroundTaskResult.of('retry', '便笺刷新未完成，等待系统再次调度'); }
    if (!await guard.isActive()) { result = BackgroundTaskResult.of('cancelled', '任务已停止'); }
    await BackgroundTaskRepo.finishOperation(op, guard.token, result, state.intervalMinutes);
    return result;
  }

  /** Explicit widget tap only. Does not enable/register periodic work or restore the global session. */
  static async refreshWidget(timeoutMs: number = 15000, isCancelled: () => boolean = (): boolean => false): Promise<BackgroundTaskResult> {
    const budget: number = Math.max(1000, Math.min(15000, timeoutMs));
    const epoch: number = (await BackgroundTaskRepo.get(BackgroundTaskKind.DAILY_NOTE)).epoch;
    const userId: number = await UserRepo.getSelectedUserId();
    const user: User | undefined = await UserRepo.getUserById(userId);
    const role: UserGameRole | undefined = await UserRepo.getDefaultRole(userId);
    if (user === undefined || role === undefined || isCancelled()) {
      return BackgroundTaskResult.of('login_required', '请先打开应用登录并选择 UID');
    }
    const state: BackgroundTaskState = new BackgroundTaskState();
    state.userId = user.id; state.uid = role.gameUid; state.region = role.region;
    state.identity = BackgroundTaskPolicy.identity(user); state.epoch = epoch;
    if ((await BackgroundTaskRepo.get(BackgroundTaskKind.DAILY_NOTE)).epoch !== epoch ||
      await BackgroundTaskService.boundUser(state) === undefined || isCancelled()) {
      return BackgroundTaskResult.of('cancelled', '账号或数据状态已变化，请打开应用确认');
    }
    const op: BackgroundOperation = await BackgroundTaskRepo.operation(state.kind, state.userId, state.uid, state.region);
    const token: string = `${Date.now()}-${Math.random()}`;
    if (!await BackgroundTaskRepo.claimOperation(op, BackgroundTaskPolicy.day(state.region), token, Date.now(), true)) {
      return BackgroundTaskResult.of('cooldown', '已有刷新任务在执行，请稍后再试');
    }
    const guard: WidgetTaskGuard = new WidgetTaskGuard(state, token, Date.now() + budget, isCancelled);
    let timer: number = -1;
    const timeout: Promise<BackgroundTaskResult> = new Promise<BackgroundTaskResult>((resolve) => {
      timer = setTimeout(() => {
        guard.cancelled = true;
        resolve(BackgroundTaskResult.of('timeout', '刷新超时，请打开应用查看'));
      }, budget);
    });
    let result: BackgroundTaskResult;
    try {
      result = await Promise.race<BackgroundTaskResult>([
        DailyNoteService.getInstance().refreshBackground(user, state.uid, state.region, guard), timeout,
      ]);
      if (!await guard.isActive() && result.status !== 'timeout') {
        result = BackgroundTaskResult.of('cancelled', '刷新已停止，请打开应用确认');
      }
    } catch (e) { result = BackgroundTaskResult.of('retry', '刷新失败，请打开应用查看'); }
    finally { clearTimeout(timer); guard.cancelled = true; }
    await BackgroundTaskRepo.finishOperation(op, token, result, 30);
    return result;
  }

  static onWorkStop(work: workScheduler.WorkInfo): void {
    const kind: BackgroundTaskKind | undefined = BackgroundTaskService.kind(work);
    if (kind !== undefined) {
      const guard: NativeTaskGuard | undefined = BackgroundTaskService.guards.get(kind);
      if (guard !== undefined && guard.state.epoch === work.parameters?.['epoch']) { guard.cancelled = true; }
    }
  }

  private static cancelLocal(kind: BackgroundTaskKind): void {
    const guard: NativeTaskGuard | undefined = BackgroundTaskService.guards.get(kind);
    if (guard !== undefined) { guard.cancelled = true; }
  }

  /** Nonthrowing, no-network restore/reset hook. False means callers must not assume invalidation succeeded. */
  static async stopAndInvalidate(): Promise<boolean> {
    return BackgroundTaskService.invalidate(false);
  }

  private static async invalidate(reset: boolean): Promise<boolean> {
    let ok: boolean = true;
    for (const kind of BackgroundTaskPolicy.KINDS) { BackgroundTaskService.cancelLocal(kind); }
    try {
      await BackgroundTaskService.serialize(async (): Promise<void> => {
        for (const kind of BackgroundTaskPolicy.KINDS) {
          if (reset) { await BackgroundTaskRepo.stop(kind, '任务已重置，需要重新开启'); }
          else { await BackgroundTaskRepo.fence(kind); }
          if (canIUse('SystemCapability.ResourceSchedule.WorkScheduler')) {
            try { workScheduler.stopWork(BackgroundTaskService.work(kind), true); } catch (e) {
              // The durable epoch already prevents a queued old task from doing work.
            }
          }
        }
        await BackgroundTaskRepo.clearOperationLeases();
        if (reset) {
          await BackgroundTaskRepo.clearOperations();
          await BackgroundTaskRepo.clearBindings();
        }
      });
    } catch (e) { ok = false; }
    BackgroundTaskService.changed();
    return ok;
  }

  static async reset(): Promise<void> {
    if (!await BackgroundTaskService.invalidate(true)) { throw new Error('未能停止后台任务，请稍后重试'); }
  }

  static async invalidateAccount(userId: number): Promise<boolean> {
    try {
      await BackgroundTaskService.serialize(async (): Promise<void> => {
        for (const kind of BackgroundTaskPolicy.KINDS) {
          const state: BackgroundTaskState = await BackgroundTaskRepo.get(kind);
          if (state.userId !== userId) { continue; }
          BackgroundTaskService.cancelLocal(kind);
          await BackgroundTaskRepo.stop(kind, '账号已退出或移除，后台任务已停止');
          if (canIUse('SystemCapability.ResourceSchedule.WorkScheduler')) {
            try { workScheduler.stopWork(BackgroundTaskService.work(kind), true); } catch (e) {}
          }
        }
        await BackgroundTaskRepo.clearUser(userId);
      });
      BackgroundTaskService.changed();
      return true;
    } catch (e) { return false; }
  }
}
