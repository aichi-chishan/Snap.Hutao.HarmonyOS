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
export { GameDataItem, GameDataManifest, ItemType } from './GameDataManifestPolicy';

const TAG: string = 'GameDataUpdater';
export class UpdateProgress {
  done: number = 0;
  total: number = 0;
  current: string = '';
}

export class GameDataUpdater {
  private static ioValue: HarmonySnapshotIo | undefined = undefined;
  private static storeValue: GameDataSnapshotStore | undefined = undefined;
  private static initializing: Promise<void> | undefined = undefined;
  private static updating: boolean = false;
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
  private static async refreshCommitted(): Promise<void> {
    if (GameDataUpdater.store().needsRefresh()) {
      GameDataUpdater.store().adoptSelection(await GameDataUpdater.verify('selection'), false);
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

  /** Branch/tag is resolved afresh per operation; an explicit 40-hex commit needs no mutable lookup. */
  static async fetchManifest(): Promise<GameDataManifest> {
    const selected: string = GameDataUpdater.manifestUrl();
    const source: GameDataSource = GameDataManifestPolicy.source(selected);
    let revision: string = source.ref;
    if (!GameDataManifestPolicy.isRevision(revision)) {
      const bytes: Uint8Array = await GameDataUpdater.getBytes(
        `https://api.github.com/repos/${GameDataManifestPolicy.REPOSITORY}/commits?sha=${source.ref}&per_page=1`, 2 * 1024 * 1024);
      const commits: Object[] = GameDataManifestPolicy.array(GameDataManifestPolicy.parseJson(GameDataUpdater.io().decode(bytes)), 'commits');
      if (commits.length !== 1) { throw new Error('无法解析唯一数据版本'); }
      revision = GameDataManifestPolicy.text(GameDataManifestPolicy.object(commits[0], 'commit')['sha'], 'sha');
      if (!GameDataManifestPolicy.isRevision(revision)) { throw new Error('数据源未返回可信提交版本'); }
    }
    const bytes: Uint8Array = await GameDataUpdater.getBytes(
      `${GameDataManifestPolicy.RAW_ROOT}${revision}/${source.file}`, GameDataManifestPolicy.MAX_MANIFEST_BYTES);
    if (GameDataUpdater.manifestUrl() !== selected) { throw new Error('检查期间数据源已变化，请重试'); }
    return GameDataManifestPolicy.parse(GameDataUpdater.io().decode(bytes), source, revision);
  }
  private static checkSource(source: string, deadline: number): void {
    if (GameDataUpdater.manifestUrl() !== source) { throw new Error('数据源已变化，旧版本保持不变'); }
    if (Date.now() >= deadline) { throw new Error('本次更新已超时，旧版本保持不变'); }
  }
  private static space(used: number, incoming: number): void {
    if (used + incoming + GameDataManifestPolicy.MAX_MANIFEST_BYTES > 3 * GameDataManifestPolicy.MAX_SNAPSHOT_BYTES ||
      GameDataUpdater.io().freeBytes() < incoming + GameDataManifestPolicy.MAX_MANIFEST_BYTES + 16 * 1024 * 1024) {
      throw new Error('游戏数据存储空间不足，旧版本保持不变');
    }
  }
  static async update(onProgress?: (p: UpdateProgress) => void): Promise<GameDataManifest> {
    if (GameDataUpdater.updating) { throw new Error('已有游戏数据更新任务，请勿重复启动'); }
    GameDataUpdater.updating = true;
    let lock: fileIo.File | undefined = undefined;
    try {
      await GameDataUpdater.initializeSnapshot(); lock = GameDataUpdater.io().acquire();
      await GameDataUpdater.refreshCommitted();
      const source: string = GameDataUpdater.manifestUrl(); const deadline: number = Date.now() + 24 * 60 * 60 * 1000;
      const manifest: GameDataManifest = await GameDataUpdater.fetchManifest(); GameDataUpdater.checkSource(source, deadline);
      if (!GameDataUpdater.hasUpdate(manifest)) { return manifest; }
      const id: string = `${manifest.sourceRevision}-${Date.now()}-${Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, '0')}`;
      let used: number = GameDataUpdater.io().usedBytes(); GameDataUpdater.space(used, 0);
      const staging: string = GameDataUpdater.store().begin(id);
      let total: number = 0; let done: number = 0;
      for (const item of manifest.items) {
        GameDataUpdater.checkSource(source, deadline);
        GameDataUpdater.space(used, item.size > 0 ? item.size : GameDataManifestPolicy.MAX_FILE_BYTES);
        const bytes: Uint8Array = await GameDataUpdater.getBytes(item.url, item.size > 0 ? item.size : GameDataManifestPolicy.MAX_FILE_BYTES);
        GameDataUpdater.checkSource(source, deadline);
        const hash: string = await GameDataUpdater.io().sha256Async(bytes);
        GameDataUpdater.checkSource(source, deadline);
        total += bytes.length;
        if (total > GameDataManifestPolicy.MAX_SNAPSHOT_BYTES) { throw new Error('完整快照超过容量限制'); }
        GameDataUpdater.space(used, bytes.length);
        GameDataUpdater.io().write(`${staging}/${item.path}`, bytes);
        const descriptor: string = JSON.stringify(item);
        let receipt: string[];
        try { receipt = await GameDataUpdater.verify('file', id, descriptor, hash); }
        catch (error) { throw new Error(`数据文件 ${item.path} 校验失败：${(error as Error).message}`); }
        GameDataUpdater.checkSource(source, deadline);
        if (receipt.length !== 6 || receipt[0] !== 'file' || receipt[1] !== GameDataUpdater.io().root || receipt[2] !== id ||
          receipt[3] !== descriptor || receipt[4] !== String(bytes.length) || receipt[5] !== hash) {
          throw new Error('文件校验收据与本次更新不一致');
        }
        item.size = bytes.length; item.sha256 = hash; used += bytes.length; done++;
        if (onProgress !== undefined) {
          const progress: UpdateProgress = new UpdateProgress(); progress.done = done; progress.total = manifest.items.length; progress.current = item.path;
          try { onProgress(progress); } catch (_) { Logger.warn(TAG, 'progress callback unavailable'); }
        }
      }
      const receipt: Uint8Array = GameDataUpdater.io().encode(JSON.stringify(manifest));
      if (receipt.length > GameDataManifestPolicy.MAX_MANIFEST_BYTES) { throw new Error('完整快照收据过大'); }
      GameDataUpdater.io().write(`${staging}/complete.json`, receipt);
      const verified: string[] = await GameDataUpdater.verify('stage', id);
      GameDataUpdater.store().publish(id, manifest, verified, (): void => GameDataUpdater.checkSource(source, deadline));
      Logger.info(TAG, `verified cohort saved: ${manifest.channelVersion}; restart required`);
      return manifest;
    } finally { if (lock !== undefined) { GameDataUpdater.io().release(lock); } GameDataUpdater.updating = false; }
  }

  /** Small bounded foreground requests only; redirects and untrusted mirrors are never followed. */
  private static async getBytes(url: string, limit: number): Promise<Uint8Array> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const result: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        header: { 'Accept': 'application/vnd.github+json', 'User-Agent': 'SnapHutaoHarmonyOS' },
        connectTimeout: 15000, readTimeout: 60000, maxRedirects: 0, maxLimit: limit, usingCache: false,
      });
      if (result.responseCode !== http.ResponseCode.OK || !(result.result instanceof ArrayBuffer)) { throw new Error(`数据下载 HTTP ${result.responseCode}`); }
      const bytes: Uint8Array = new Uint8Array(result.result);
      if (bytes.length < 1 || bytes.length > limit) { throw new Error('数据下载为空或超过大小限制'); }
      return bytes;
    } finally { client.destroy(); }
  }
}
