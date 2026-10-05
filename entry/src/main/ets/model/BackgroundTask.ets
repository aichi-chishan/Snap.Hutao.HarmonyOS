import { ServerTime } from '../common/ServerTime';
import { User } from './User';
import { ApiResponse } from './ApiResponse';
import { RetCodes } from '../common/Constants';

export enum BackgroundTaskKind {
  DAILY_NOTE = 'daily_note',
  SIGN_IN = 'sign_in',
}

/** Captured before showing consent; contains no credentials and is never sent to the OS. */
export class BackgroundTaskBinding {
  revision: number = 0;
  userId: number = 0;
  uid: string = '';
  region: string = '';
  identity: string = '';
}

/** Operational data only; never export this state in a portable backup. */
export class BackgroundTaskState {
  kind: BackgroundTaskKind = BackgroundTaskKind.DAILY_NOTE;
  enabled: boolean = false;
  epoch: number = 0;
  userId: number = 0;
  uid: string = '';
  region: string = '';
  identity: string = '';
  intervalMinutes: number = 30;
  queued: boolean = false;
  status: string = 'disabled';
  message: string = '未开启后台任务';
  lastRunAt: number = 0;
  lastSuccessAt: number = 0;
  lease: string = '';
  leaseUntil: number = 0;
}

export class BackgroundTaskResult {
  status: string = 'retry';
  message: string = '网络暂不可用，等待系统下次调度';
  day: string = '';
  static of(status: string, message: string, day: string = ''): BackgroundTaskResult {
    const result: BackgroundTaskResult = new BackgroundTaskResult();
    result.status = status;
    result.message = message;
    result.day = day;
    return result;
  }
}

/** Injectable cooperative cancellation guard; no UI or permission callback exists. */
export interface BackgroundTaskGuard {
  isActive(): Promise<boolean>;
}

export class BackgroundOperation {
  kind: BackgroundTaskKind = BackgroundTaskKind.DAILY_NOTE;
  userId: number = 0;
  uid: string = '';
  region: string = '';
  day: string = '';
  completedDay: string = '';
  retryAt: number = 0;
  status: string = '';
  lease: string = '';
  leaseUntil: number = 0;
}

export class BackgroundTaskPolicy {
  static readonly MIN_INTERVAL_MINUTES: number = 20;
  static readonly BUDGET_MS: number = 80000;
  static readonly FAILURE_COOLDOWN_MS: number = 10 * 60 * 1000;
  static readonly KINDS: BackgroundTaskKind[] = [BackgroundTaskKind.DAILY_NOTE, BackgroundTaskKind.SIGN_IN];

  static interval(value: number): number {
    return Number.isFinite(value) ? Math.max(20, Math.min(1440, Math.floor(value))) : 30;
  }

  static day(region: string, now: number = Date.now()): string {
    return `${region}:${ServerTime.date(region, now)}`;
  }

  static identity(user: User): string {
    return `${user.createdAt}|${user.isOversea ? 1 : 0}|${user.aid}|${user.mid}`;
  }

  static owns(user: User, uid: string, region: string): boolean {
    return region.length > 0 && user.isOversea === region.startsWith('os_') &&
      user.roles.some(role => role.gameUid === uid && role.region === region);
  }

  static resultForResponse(response: ApiResponse): BackgroundTaskResult | undefined {
    const data: Record<string, Object> = response.data === undefined ? {} : response.data as Record<string, Object>;
    if (response.isRiskControl() || response.retcode === RetCodes.ACCOUNT_RISK ||
      response.header('x-rpc-aigis').length > 0 || String(data['gt'] ?? '').length > 0 ||
      String(data['challenge'] ?? '').length > 0 || Number(data['risk_code'] ?? 0) !== 0) {
      return BackgroundTaskResult.of('captcha', '请打开应用手动完成人机验证，再点“重新排队”');
    }
    if (response.isAuthExpired()) {
      return BackgroundTaskResult.of('login_required', '登录凭据已失效，请在应用内重新登录后重新排队');
    }
    if (!response.success && response.retcode !== RetCodes.ALREADY_SIGNED) {
      return BackgroundTaskResult.of('retry', '请求未完成，冷却后等待系统再次调度');
    }
    return undefined;
  }

  static due(operation: BackgroundOperation, day: string, now: number, signIn: boolean): boolean {
    if (operation.lease.length > 0 && operation.leaseUntil > now && operation.leaseUntil <= now + 86400000) { return false; }
    if (signIn && operation.completedDay === day) { return false; }
    if (operation.day === day &&
      (operation.status === 'captcha' || operation.status === 'login_required' || operation.status === 'manual')) {
      return false;
    }
    // Clock rollback must not suppress work forever. A future cooldown > one day is stale.
    return operation.retryAt <= now || operation.retryAt > now + 86400000;
  }
}
