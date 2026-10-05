/** Stable, app-owned status codes. Never carry server messages, credentials, filenames or UID values. */
export enum CommonOutcomeId {
  None = '', Preparing = 'preparing', Ready = 'ready', Cancelled = 'cancelled',
  InvalidFile = 'invalidFile', ImportFailed = 'importFailed', ImportComplete = 'importComplete',
  ExportFailed = 'exportFailed', ExportComplete = 'exportComplete', Busy = 'busy',
  NetworkUnavailable = 'networkUnavailable', PermissionRequired = 'permissionRequired',
  LoginExpired = 'loginExpired', Unsupported = 'unsupported', CopyComplete = 'copyComplete',
  CopyFailed = 'copyFailed', Failed = 'failed', LocaleFailed = 'localeFailed'
}
export class CommonOutcome {
  id: CommonOutcomeId;
  count: number;
  constructor(id: CommonOutcomeId = CommonOutcomeId.None, count: number = 0) {
    this.id = id; this.count = Number.isSafeInteger(count) && count >= 0 && count <= 10000000 ? count : 0;
  }
  static known(id: string): boolean {
    return ['', 'preparing', 'ready', 'cancelled', 'invalidFile', 'importFailed', 'importComplete',
      'exportFailed', 'exportComplete', 'busy', 'networkUnavailable', 'permissionRequired',
      'loginExpired', 'unsupported', 'copyComplete', 'copyFailed', 'failed', 'localeFailed'].includes(id);
  }
}
