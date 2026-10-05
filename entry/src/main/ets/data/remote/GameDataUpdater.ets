/** Foreground-only, operation-pinned immutable cohorts. No resume queue, mirror or live-file deletion. */
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { taskpool } from '@kit.ArkTS';
import { AppContextProvider } from '../../common/AppContext';
import { PreferencesStore } from '../prefs/PreferencesStore';
import { Logger } from '../../common/Logger';
import { GameDataItem, GameDataManifest, GameDataManifestPolicy, GameDataSource, ItemType } from './GameDataManifestPolicy';
import { GameDataSnapshot, GameDataSnapshotStore } from './GameDataSnapshotStore';
import { HarmonySnapshotIo } from './HarmonySnapshotIo';
import { prepareGameDataSnapshot } from './GameDataSnapshotWorker';
import { GameDataUpdateStatus } from '../../model/GameDataUpdateStatus';
export { GameDataItem, GameDataManifest, ItemType } from './GameDataManifestPolicy';

const TAG: string = 'GameDataUpdater';
export class UpdateProgress {
  done: number = 0;
  total: number = 0;
  current: string = '';
}

class GameDataUpdateOperation {
  status: GameDataUpdateStatus = new GameDataUpdateStatus();
  source: string = '';
  deadline: number = 0;
  snapshotId: string = '';
  cancelled: boolean = false;
  failure: Error | undefined = undefined;
  succeeded: boolean = false;
  publishing: boolean = false;
  next: number = 0;
  used: number = 0;
  received: number = 0;
  diskReserved: number = 0;
  snapshotReserved: number = 0;
  requests: Set<http.HttpRequest> = new Set<http.HttpRequest>();
  aborted: Set<http.HttpRequest> = new Set<http.HttpRequest>();
  onProgress: ((progress: UpdateProgress) => void) | undefined = undefined;
  completion: Promise<void>;
  finish: () => void = (): void => {};
  constructor(id: number, onProgress?: (progress: UpdateProgress) => void) {
    this.status.id = id; this.status.state = 'preparing'; this.status.settled = false;
    this.onProgress = onProgress;
    this.completion = new Promise<void>((resolve: () => void): void => { this.finish = resolve; });
  }
}
class GameDataUpdateListener {
  callback: (status: GameDataUpdateStatus) => void;
  constructor(callback: (status: GameDataUpdateStatus) => void) { this.callback = callback; }
}
class GameDataFileReservation {
  disk: number = 0;
  snapshot: number = 0;
  active: boolean = false;
}

export class GameDataUpdater {
  private static ioValue: HarmonySnapshotIo | undefined = undefined;
  private static storeValue: GameDataSnapshotStore | undefined = undefined;
  private static initializing: Promise<void> | undefined = undefined;
  private static updating: boolean = false;
  static readonly MAX_PARALLEL: number = 4;
  private static sequence: number = 0;
  private static operation: GameDataUpdateOperation | undefined = undefined;
  private static lastStatus: GameDataUpdateStatus = new GameDataUpdateStatus();
  private static listeners: Set<GameDataUpdateListener> = new Set<GameDataUpdateListener>();
  private static io(): HarmonySnapshotIo {
    if (GameDataUpdater.ioValue === undefined) { GameDataUpdater.ioValue = new HarmonySnapshotIo(AppContextProvider.getFilesDir()); }
    return GameDataUpdater.ioValue;
  }
  private static store(): GameDataSnapshotStore {
    if (GameDataUpdater.storeValue === undefined) {
      GameDataUpdater.storeValue = new GameDataSnapshotStore(GameDataUpdater.io().root, GameDataUpdater.io());
    }
    return GameDataUpdater.storeValue;
  }
  static initializeSnapshot(): Promise<void> {
    if (GameDataUpdater.initializing === undefined) { GameDataUpdater.initializing = GameDataUpdater.initialize(); }
    return GameDataUpdater.initializing;
  }
  private static async verify(mode: string, id: string = '', item: string = '', hash: string = ''): Promise<string[]> {
    const task: taskpool.Task = new taskpool.Task(prepareGameDataSnapshot, AppContextProvider.getFilesDir(), mode, id, item, hash);
    const configs: taskpool.Configs = { timeout: mode === 'selection' || mode === 'file' ? 15000 : 60000 };
    return await taskpool.execute(task, configs) as string[];
  }
  private static async initialize(): Promise<void> {
    let lock: fileIo.File | undefined = undefined;
    try {
      lock = GameDataUpdater.io().acquire();
      GameDataUpdater.store().adoptSelection(await GameDataUpdater.verify('selection'), true);
    } catch (_) {
      // A late worker is read-only. Keep this process wholly bundled and do not change disk pointers.
      GameDataUpdater.store().failInitialization();
      Logger.warn(TAG, 'snapshot validation unavailable; bundled cohort pinned until restart');
    } finally { if (lock !== undefined) { GameDataUpdater.io().release(lock); } }
  }
  static snapshotState(): string { return GameDataUpdater.store().stateText(); }
  private static async refreshCommitted(operation?: GameDataUpdateOperation): Promise<void> {
    if (operation !== undefined) { GameDataUpdater.checkOperation(operation); }
    if (GameDataUpdater.store().needsRefresh()) {
      const result: string[] = await GameDataUpdater.verify('selection');
      if (operation !== undefined) { GameDataUpdater.checkOperation(operation); }
      GameDataUpdater.store().adoptSelection(result, false);
    }
  }
  static defaultManifestUrl(): string { return `${GameDataManifestPolicy.RAW_ROOT}main/manifest-hutao.json`; }
  static manifestUrl(): string { return PreferencesStore.getString('gamedata_manifest_url', GameDataUpdater.defaultManifestUrl()); }
  static setManifestUrl(url: string): void {
    const selected: string = url.trim() === '' ? GameDataUpdater.defaultManifestUrl() : url.trim();
    GameDataManifestPolicy.source(selected);
    if (GameDataUpdater.updating) { throw new Error('正在更新，请完成后再更改数据源'); }
    const lock: fileIo.File = GameDataUpdater.io().acquire();
    try { PreferencesStore.setString('gamedata_manifest_url', selected); }
    finally { GameDataUpdater.io().release(lock); }
  }
  static localVersion(): string { return GameDataUpdater.store().current()?.manifest.channelVersion ?? ''; }
  static pendingVersion(): string { return GameDataUpdater.store().pendingVersion(); }
  static pendingState(): string { return GameDataUpdater.store().pendingState(); }
  static canRollback(): boolean { return !GameDataUpdater.updating && GameDataUpdater.store().canRollback(); }
  static hasUpdate(remote: GameDataManifest): boolean { return remote.sourceRevision !== GameDataUpdater.store().committedRevision(); }

  private static metadataName(path: string): string { return path.startsWith('metadata/') ? path : `metadata/${path}`; }
  static readMetadata(relPath: string): string {
    const current: GameDataSnapshot | undefined = GameDataUpdater.store().current();
    const path: string = GameDataUpdater.metadataName(relPath);
    // Legacy community domains have no slot in the verified cohort and use their bundled fallback.
    try { GameDataManifestPolicy.validatePath(path, ItemType.Text); } catch (_) { return ''; }
    return current?.metadata.get(path) ?? '';
  }
  static metadataPath(relPath: string): string {
    const current: GameDataSnapshot | undefined = GameDataUpdater.store().current();
    const path: string = GameDataUpdater.metadataName(relPath); GameDataManifestPolicy.validatePath(path, ItemType.Text);
    return current === undefined ? '' : `${current.directory}/${path}`;
  }
  static imagePath(relPath: string): string {
    const current: GameDataSnapshot | undefined = GameDataUpdater.store().current();
    GameDataManifestPolicy.validatePath(relPath, ItemType.Icon);
    return current !== undefined && current.paths.has(relPath) ? `${current.directory}/${relPath}` : '';
  }
  static readImage(relPath: string): string {
    GameDataUpdater.store().current();
    try { const path: string = GameDataUpdater.imagePath(relPath); return path === '' ? '' : fileUri.getUriFromPath(path); }
    catch (_) { return ''; }
  }
  static isItemLocal(item: GameDataItem): boolean {
    const current: GameDataSnapshot | undefined = GameDataUpdater.store().current();
    try { GameDataManifestPolicy.validatePath(item.path, item.type); return current?.paths.has(item.path) ?? false; }
    catch (_) { return false; }
  }
  static async ensureItem(item: GameDataItem): Promise<void> {
    await GameDataUpdater.initializeSnapshot();
    if (!GameDataUpdater.isItemLocal(item)) { throw new Error('请更新完整游戏数据，不支持单文件覆盖'); }
  }
  /** Reset is a next-launch tombstone; existing readers and every legacy/snapshot byte remain intact. */
  static clearAll(): void {
    if (GameDataUpdater.updating) { throw new Error('正在更新，请完成后再重置'); }
    const lock: fileIo.File = GameDataUpdater.io().acquire();
    try { GameDataUpdater.store().reset(); }
    finally { GameDataUpdater.io().release(lock); }
  }
  static async rollback(): Promise<boolean> {
    if (GameDataUpdater.updating) { throw new Error('正在更新，请完成后再回滚'); }
    GameDataUpdater.updating = true;
    let lock: fileIo.File | undefined = undefined;
    try {
      await GameDataUpdater.initializeSnapshot(); lock = GameDataUpdater.io().acquire();
      await GameDataUpdater.refreshCommitted();
      const id: string = GameDataUpdater.store().rollbackId(); if (id === '') { return false; }
      return GameDataUpdater.store().rollback(await GameDataUpdater.verify('rollback', id));
    } finally { if (lock !== undefined) { GameDataUpdater.io().release(lock); } GameDataUpdater.updating = false; }
  }

  private static copyStatus(status: GameDataUpdateStatus): GameDataUpdateStatus {
    const copy: GameDataUpdateStatus = new GameDataUpdateStatus();
    copy.id = status.id; copy.state = status.state; copy.done = status.done; copy.total = status.total;
    copy.current = status.current; copy.bytes = status.bytes; copy.activeFiles = status.activeFiles;
    copy.error = status.error; copy.canCancel = status.canCancel; copy.settled = status.settled;
    return copy;
  }
  static updateStatus(): GameDataUpdateStatus {
    return GameDataUpdater.copyStatus(GameDataUpdater.operation?.status ?? GameDataUpdater.lastStatus);
  }
  private static emit(listener: GameDataUpdateListener): void {
    // Read the latest copy for each observer: reentrant cancel/replacement cannot emit stale outer state.
    try { listener.callback(GameDataUpdater.updateStatus()); }
    catch (_) { Logger.warn(TAG, 'update status listener unavailable'); }
  }
  /** Bounded page-lifecycle subscription; unsubscribe is idempotent and never cancels the update. */
  static subscribeUpdate(callback: (status: GameDataUpdateStatus) => void): () => void {
    if (GameDataUpdater.listeners.size >= 16) { throw new Error('游戏数据状态订阅过多'); }
    const listener: GameDataUpdateListener = new GameDataUpdateListener(callback);
    GameDataUpdater.listeners.add(listener); GameDataUpdater.emit(listener);
    return (): void => { GameDataUpdater.listeners.delete(listener); };
  }
  private static notify(operation: GameDataUpdateOperation): void {
    operation.status.canCancel = !operation.status.settled && !operation.cancelled && operation.failure === undefined && !operation.succeeded;
    // Newly registered listeners receive their immediate event, never an extra event from this pass.
    const listeners: GameDataUpdateListener[] = Array.from(GameDataUpdater.listeners);
    const callback: ((progress: UpdateProgress) => void) | undefined = operation.onProgress;
    if (callback !== undefined) {
      const progress: UpdateProgress = new UpdateProgress();
      progress.done = operation.status.done; progress.total = operation.status.total; progress.current = operation.status.current;
      try { callback(progress); } catch (_) { Logger.warn(TAG, 'progress callback unavailable'); }
    }
    for (const listener of listeners) {
      if (GameDataUpdater.listeners.has(listener)) { GameDataUpdater.emit(listener); }
    }
  }
  private static abortRequests(operation: GameDataUpdateOperation): void {
    for (const client of operation.requests) {
      if (operation.aborted.has(client)) { continue; }
      try { client.destroy(); operation.aborted.add(client); } catch (_) { Logger.warn(TAG, 'request cancellation deferred until settlement'); }
    }
  }
  /** Returns only after this invocation drains and releases its writer ownership. */
  static cancelUpdate(expectedId?: number): Promise<GameDataUpdateStatus> {
    const operation: GameDataUpdateOperation | undefined = GameDataUpdater.operation;
    if (operation === undefined || (expectedId !== undefined && operation.status.id !== expectedId)) {
      return Promise.resolve(GameDataUpdater.updateStatus());
    }
    if (!operation.succeeded && operation.failure === undefined && !operation.cancelled) {
      operation.cancelled = true; operation.status.state = 'cancelling';
      GameDataUpdater.abortRequests(operation); GameDataUpdater.notify(operation);
    }
    return operation.completion.then((): GameDataUpdateStatus => GameDataUpdater.copyStatus(operation.status));
  }
  private static checkOperation(operation: GameDataUpdateOperation): void {
    if (operation.failure !== undefined) { throw operation.failure; }
    if (operation.cancelled || GameDataUpdater.operation !== operation) { throw new Error('游戏数据更新已取消'); }
    if (GameDataUpdater.manifestUrl() !== operation.source) { throw new Error('数据源已变化，旧版本保持不变'); }
    if (Date.now() >= operation.deadline) { throw new Error('本次更新已超时，旧版本保持不变'); }
  }
  private static fail(operation: GameDataUpdateOperation, error: Error): void {
    if (!operation.cancelled && operation.failure === undefined && !operation.succeeded) {
      operation.failure = error; operation.status.state = 'failed'; operation.status.error = error.message || '游戏数据更新失败';
    }
    GameDataUpdater.abortRequests(operation); GameDataUpdater.notify(operation);
  }

  /** Branch/tag is resolved afresh per operation; an explicit 40-hex commit needs no mutable lookup. */
  static fetchManifest(): Promise<GameDataManifest> { return GameDataUpdater.fetchManifestFor(GameDataUpdater.manifestUrl()); }
  private static async fetchManifestFor(selected: string, operation?: GameDataUpdateOperation): Promise<GameDataManifest> {
    if (operation !== undefined) { GameDataUpdater.checkOperation(operation); }
    const source: GameDataSource = GameDataManifestPolicy.source(selected);
    let revision: string = source.ref;
    if (!GameDataManifestPolicy.isRevision(revision)) {
      const bytes: Uint8Array = await GameDataUpdater.getBytes(
        `https://api.github.com/repos/${GameDataManifestPolicy.REPOSITORY}/commits?sha=${source.ref}&per_page=1`, 2 * 1024 * 1024, operation);
      if (operation !== undefined) { GameDataUpdater.checkOperation(operation); }
      const commits: Object[] = GameDataManifestPolicy.array(GameDataManifestPolicy.parseJson(GameDataUpdater.io().decode(bytes)), 'commits');
      if (commits.length !== 1) { throw new Error('无法解析唯一数据版本'); }
      revision = GameDataManifestPolicy.text(GameDataManifestPolicy.object(commits[0], 'commit')['sha'], 'sha');
      if (!GameDataManifestPolicy.isRevision(revision)) { throw new Error('数据源未返回可信提交版本'); }
    }
    const bytes: Uint8Array = await GameDataUpdater.getBytes(
      `${GameDataManifestPolicy.RAW_ROOT}${revision}/${source.file}`, GameDataManifestPolicy.MAX_MANIFEST_BYTES, operation);
    if (operation !== undefined) { GameDataUpdater.checkOperation(operation); }
    if (GameDataUpdater.manifestUrl() !== selected) { throw new Error('检查期间数据源已变化，请重试'); }
    return GameDataManifestPolicy.parse(GameDataUpdater.io().decode(bytes), source, revision);
  }
  private static spaceAvailable(used: number, incoming: number): boolean {
    const overhead: number = GameDataManifestPolicy.MAX_MANIFEST_BYTES + 16 * 1024;
    return used + incoming + overhead <= 3 * GameDataManifestPolicy.MAX_SNAPSHOT_BYTES &&
      GameDataUpdater.io().freeBytes() >= incoming + overhead + 16 * 1024 * 1024;
  }
  private static space(used: number, incoming: number): void {
    if (!GameDataUpdater.spaceAvailable(used, incoming)) { throw new Error('游戏数据存储空间不足，旧版本保持不变'); }
  }
  /** Reservations are claimed synchronously before each await, shared by all four lanes. */
  private static reserve(operation: GameDataUpdateOperation, limit: number, reservation: GameDataFileReservation): boolean {
    GameDataUpdater.checkOperation(operation);
    const cohortFits: boolean = operation.received + operation.snapshotReserved + limit <= GameDataManifestPolicy.MAX_SNAPSHOT_BYTES;
    const diskFits: boolean = GameDataUpdater.spaceAvailable(operation.used, operation.diskReserved + limit);
    if (!cohortFits || !diskFits) {
      // Drop this spare lane while another can make progress; never multiply the budget.
      if (operation.status.activeFiles > 0) { return false; }
      throw new Error(cohortFits ? '游戏数据存储空间不足，旧版本保持不变' : '完整快照超过容量限制');
    }
    operation.diskReserved += limit; operation.snapshotReserved += limit;
    reservation.disk = limit; reservation.snapshot = limit; reservation.active = true;
    operation.status.activeFiles++; return true;
  }
  private static releaseReservation(operation: GameDataUpdateOperation, reservation: GameDataFileReservation): void {
    operation.diskReserved -= reservation.disk; operation.snapshotReserved -= reservation.snapshot;
    if (reservation.active) { operation.status.activeFiles--; }
    reservation.disk = 0; reservation.snapshot = 0; reservation.active = false;
  }
  private static async transferItem(operation: GameDataUpdateOperation, item: GameDataItem, staging: string,
    reservation: GameDataFileReservation): Promise<void> {
    GameDataUpdater.checkOperation(operation);
    const bytes: Uint8Array = await GameDataUpdater.getBytes(item.url, item.size > 0 ? item.size : GameDataManifestPolicy.MAX_FILE_BYTES, operation);
    GameDataUpdater.checkOperation(operation);
    operation.received += bytes.length; operation.snapshotReserved -= reservation.snapshot; reservation.snapshot = 0;
    const hash: string = await GameDataUpdater.io().sha256Async(bytes);
    GameDataUpdater.checkOperation(operation);
    GameDataUpdater.space(operation.used, operation.diskReserved);
    GameDataUpdater.io().write(`${staging}/${item.path}`, bytes);
    operation.used += bytes.length; operation.diskReserved -= reservation.disk; reservation.disk = 0;
    const descriptor: string = JSON.stringify(item);
    GameDataUpdater.checkOperation(operation);
    let receipt: string[];
    try { receipt = await GameDataUpdater.verify('file', operation.snapshotId, descriptor, hash); }
    catch (error) { throw new Error(`数据文件 ${item.path} 校验失败：${(error as Error).message}`); }
    GameDataUpdater.checkOperation(operation);
    if (receipt.length !== 6 || receipt[0] !== 'file' || receipt[1] !== GameDataUpdater.io().root || receipt[2] !== operation.snapshotId ||
      receipt[3] !== descriptor || receipt[4] !== String(bytes.length) || receipt[5] !== hash) { throw new Error('文件校验收据与本次更新不一致'); }
    item.size = bytes.length; item.sha256 = hash;
    operation.status.done++; operation.status.bytes += bytes.length; operation.status.current = item.path;
    GameDataUpdater.notify(operation);
  }
  /** Each lane catches its own error. Promise.all below therefore drains every started lane. */
  private static async lane(operation: GameDataUpdateOperation, manifest: GameDataManifest, staging: string): Promise<void> {
    while (!operation.cancelled && operation.failure === undefined) {
      const reservation: GameDataFileReservation = new GameDataFileReservation();
      try {
        GameDataUpdater.checkOperation(operation);
        if (operation.next >= manifest.items.length) { return; }
        const item: GameDataItem = manifest.items[operation.next];
        if (!GameDataUpdater.reserve(operation, item.size > 0 ? item.size : GameDataManifestPolicy.MAX_FILE_BYTES, reservation)) { return; }
        operation.next++; operation.status.current = item.path; GameDataUpdater.notify(operation);
        await GameDataUpdater.transferItem(operation, item, staging, reservation);
        GameDataUpdater.checkOperation(operation);
      } catch (error) { GameDataUpdater.fail(operation, error as Error); }
      finally { GameDataUpdater.releaseReservation(operation, reservation); GameDataUpdater.notify(operation); }
    }
  }
  static async update(onProgress?: (p: UpdateProgress) => void): Promise<GameDataManifest> {
    if (GameDataUpdater.updating) { throw new Error('已有游戏数据更新任务，请勿重复启动'); }
    GameDataUpdater.updating = true;
    const operation: GameDataUpdateOperation = new GameDataUpdateOperation(++GameDataUpdater.sequence, onProgress);
    GameDataUpdater.operation = operation;
    let lock: fileIo.File | undefined = undefined;
    let manifest: GameDataManifest | undefined = undefined;
    try {
      operation.source = GameDataUpdater.manifestUrl(); operation.deadline = Date.now() + 24 * 60 * 60 * 1000;
      GameDataUpdater.notify(operation); GameDataUpdater.checkOperation(operation);
      await GameDataUpdater.initializeSnapshot(); GameDataUpdater.checkOperation(operation);
      lock = GameDataUpdater.io().acquire(); GameDataUpdater.checkOperation(operation);
      await GameDataUpdater.refreshCommitted(operation); GameDataUpdater.checkOperation(operation);
      manifest = await GameDataUpdater.fetchManifestFor(operation.source, operation); GameDataUpdater.checkOperation(operation);
      operation.status.total = manifest.items.length;
      if (!GameDataUpdater.hasUpdate(manifest)) { operation.status.done = operation.status.total; operation.succeeded = true; }
      else {
        operation.snapshotId = `${manifest.sourceRevision}-${Date.now()}-${Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, '0')}`;
        operation.used = GameDataUpdater.io().usedBytes(); GameDataUpdater.space(operation.used, 0);
        const staging: string = GameDataUpdater.store().begin(operation.snapshotId);
        operation.status.state = 'downloading'; GameDataUpdater.notify(operation); GameDataUpdater.checkOperation(operation);
        const lanes: Promise<void>[] = [];
        for (let index: number = 0; index < Math.min(GameDataUpdater.MAX_PARALLEL, manifest.items.length); index++) {
          lanes.push(GameDataUpdater.lane(operation, manifest, staging));
        }
        await Promise.all(lanes); // lanes absorb first failure and stop admission, then all drain
        GameDataUpdater.checkOperation(operation);
        operation.status.state = 'validating'; GameDataUpdater.notify(operation); GameDataUpdater.checkOperation(operation);
        const receipt: Uint8Array = GameDataUpdater.io().encode(JSON.stringify(manifest));
        if (receipt.length > GameDataManifestPolicy.MAX_MANIFEST_BYTES) { throw new Error('完整快照收据过大'); }
        GameDataUpdater.space(operation.used, receipt.length);
        GameDataUpdater.io().write(`${staging}/complete.json`, receipt); GameDataUpdater.checkOperation(operation);
        const verified: string[] = await GameDataUpdater.verify('stage', operation.snapshotId); GameDataUpdater.checkOperation(operation);
        operation.publishing = true;
        GameDataUpdater.store().publish(operation.snapshotId, manifest, verified, (): void => GameDataUpdater.checkOperation(operation));
        // Publication is the linearization point. A later cancel cannot undo this successful pointer.
        operation.succeeded = true;
        Logger.info(TAG, `verified cohort saved: ${manifest.channelVersion}; restart required`);
      }
    } catch (error) {
      if (operation.publishing) {
        const published: string = GameDataUpdater.store().publicationState(operation.snapshotId);
        if (published === 'published') { operation.succeeded = true; }
        else if (published === 'unknown') { operation.failure = new Error('更新提交结果未确认，请重启后核验'); }
      }
      if (!operation.succeeded) { GameDataUpdater.fail(operation, error as Error); }
    } finally {
      try { if (lock !== undefined) { GameDataUpdater.io().release(lock); } }
      catch (error) {
        if (!operation.succeeded && operation.failure === undefined) { operation.failure = error as Error; }
        Logger.warn(TAG, 'writer close reported an error');
      }
      operation.status.state = operation.succeeded ? 'completed' : operation.failure !== undefined ? 'failed' : 'cancelled';
      operation.status.error = operation.succeeded ? '' : operation.failure?.message ?? '游戏数据更新已取消';
      operation.status.settled = true; operation.status.canCancel = false;
      GameDataUpdater.lastStatus = GameDataUpdater.copyStatus(operation.status);
      if (GameDataUpdater.operation === operation) { GameDataUpdater.operation = undefined; }
      GameDataUpdater.updating = false; operation.finish(); GameDataUpdater.notify(operation);
    }
    if (operation.succeeded && manifest !== undefined) { return manifest; }
    throw operation.failure ?? new Error('游戏数据更新已取消');
  }

  /** Native destroy requests stop; admission stays held until the original request promise settles. */
  private static async getBytes(url: string, limit: number, operation?: GameDataUpdateOperation): Promise<Uint8Array> {
    if (operation !== undefined) { GameDataUpdater.checkOperation(operation); }
    const client: http.HttpRequest = http.createHttp();
    if (operation !== undefined) { operation.requests.add(client); }
    try {
      if (operation !== undefined) { GameDataUpdater.checkOperation(operation); }
      const result: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: { 'Accept': 'application/vnd.github+json', 'User-Agent': 'SnapHutaoHarmonyOS' },
        connectTimeout: 15000, readTimeout: 60000, maxRedirects: 0, maxLimit: limit, usingCache: false,
      });
      if (operation !== undefined) { GameDataUpdater.checkOperation(operation); }
      if (result.responseCode !== http.ResponseCode.OK || !(result.result instanceof ArrayBuffer)) { throw new Error(`数据下载 HTTP ${result.responseCode}`); }
      const bytes: Uint8Array = new Uint8Array(result.result);
      if (bytes.length < 1 || bytes.length > limit) { throw new Error('数据下载为空或超过大小限制'); }
      return bytes;
    } finally {
      const destroyed: boolean = operation?.aborted.has(client) ?? false;
      operation?.requests.delete(client); operation?.aborted.delete(client);
      if (!destroyed) { try { client.destroy(); } catch (_) { Logger.warn(TAG, 'request cleanup failed'); } }
    }
  }
}
