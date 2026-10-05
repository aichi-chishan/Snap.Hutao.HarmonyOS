import { GameDataItem, GameDataManifest, GameDataManifestPolicy, GameDataSource, ItemType } from './GameDataManifestPolicy';

export interface GameDataSnapshotIo {
  read(path: string, limit: number): Uint8Array;
  write(path: string, bytes: Uint8Array): void;
  mkdir(path: string): void;
  exists(path: string): boolean;
  rename(from: string, to: string): void;
  encode(text: string): Uint8Array;
  decode(bytes: Uint8Array): string;
  sha256(bytes: Uint8Array): string;
}
export class GameDataSnapshot {
  id: string = '';
  directory: string = '';
  manifest: GameDataManifest = new GameDataManifest();
  metadata: Map<string, string> = new Map<string, string>();
  paths: Set<string> = new Set<string>();
}
class SnapshotPointer {
  schema: number = 1;
  current: string = '';
  previous: string = '';
}

/** Immutable directories and one atomic selection pointer. No file/tree deletion capability. */
export class GameDataSnapshotStore {
  readonly root: string;
  private io: GameDataSnapshotIo;
  private initialized: boolean = false;
  private knownSelection: boolean = false;
  private session: GameDataSnapshot | undefined = undefined;
  private committed: GameDataSnapshot | undefined = undefined;
  private committedStamp: string = '';
  private state: string = 'uninitialized';
  static readonly MAX_TEXT_UNITS: number = 32 * 1024 * 1024;

  constructor(root: string, io: GameDataSnapshotIo) { this.root = root; this.io = io; }
  static validId(id: string): boolean { return GameDataManifestPolicy.validId(id); }
  stagingPath(id: string): string {
    if (!GameDataSnapshotStore.validId(id)) { throw new Error('暂存版本 ID 无效'); }
    return `${this.root}/staging/${id}`;
  }
  snapshotPath(id: string): string {
    if (!GameDataSnapshotStore.validId(id)) { throw new Error('快照版本 ID 无效'); }
    return `${this.root}/snapshots/${id}`;
  }
  private pointer(name: string): SnapshotPointer | undefined {
    try {
      const raw: Record<string, Object> = GameDataManifestPolicy.object(GameDataManifestPolicy.parseJson(
        this.io.decode(this.io.read(`${this.root}/${name}`, 4096))), 'pointer');
      const value: SnapshotPointer = new SnapshotPointer();
      value.current = GameDataManifestPolicy.text(raw['current'], 'current');
      value.previous = GameDataManifestPolicy.text(raw['previous'], 'previous');
      if (raw['schema'] !== 1 || (value.current !== '' && !GameDataSnapshotStore.validId(value.current)) ||
        (value.previous !== '' && !GameDataSnapshotStore.validId(value.previous))) { return undefined; }
      return value;
    } catch (_) { return undefined; }
  }
  stamp(): string {
    const values: string[] = [];
    for (const name of ['active.json', 'active.previous.json']) {
      try { values.push(this.io.sha256(this.io.read(`${this.root}/${name}`, 4096))); }
      catch (_) { values.push(''); }
    }
    return values.join(':');
  }
  private load(id: string, directory: string): GameDataSnapshot {
    const source: GameDataSource = new GameDataSource(); source.ref = id.substring(0, 40);
    const text: string = this.io.decode(this.io.read(`${directory}/complete.json`, GameDataManifestPolicy.MAX_MANIFEST_BYTES));
    const raw: Record<string, Object> = GameDataManifestPolicy.object(GameDataManifestPolicy.parseJson(text), 'complete manifest');
    if (raw['sourceRevision'] !== source.ref) { throw new Error('快照与源码版本不一致'); }
    const result: GameDataSnapshot = new GameDataSnapshot(); result.id = id; result.directory = directory;
    result.manifest = GameDataManifestPolicy.parse(text, source, source.ref);
    let bytes: number = 0;
    for (const item of result.manifest.items) {
      if (item.size < 1 || item.sha256.length !== 64) { throw new Error('快照缺少完整校验收据'); }
      const value: Uint8Array = this.io.read(`${directory}/${item.path}`, item.size);
      GameDataManifestPolicy.validateBytes(item, value, this.io.sha256(value)); bytes += value.length;
      if (bytes > GameDataManifestPolicy.MAX_SNAPSHOT_BYTES) { throw new Error('快照容量超限'); }
      result.paths.add(item.path);
      if (item.type === ItemType.Text) {
        const decoded: string = this.io.decode(value);
        result.metadata.set(item.path, decoded.charCodeAt(0) === 0xFEFF ? decoded.substring(1) : decoded);
      }
    }
    GameDataManifestPolicy.validateModels(result.metadata); return result;
  }
  private tryLoad(id: string): GameDataSnapshot | undefined {
    if (id === '') { return undefined; }
    try { return this.load(id, this.snapshotPath(id)); } catch (_) { return undefined; }
  }
  private recover(): GameDataSnapshot | undefined {
    const active: SnapshotPointer | undefined = this.pointer('active.json');
    if (active !== undefined) {
      if (active.current === '') { this.state = 'reset'; return undefined; }
      const current: GameDataSnapshot | undefined = this.tryLoad(active.current);
      if (current !== undefined) { this.state = 'active'; return current; }
      const previous: GameDataSnapshot | undefined = this.tryLoad(active.previous);
      if (previous !== undefined) { this.state = 'previous'; return previous; }
    }
    const backup: SnapshotPointer | undefined = this.pointer('active.previous.json');
    if (backup !== undefined) {
      const previous: GameDataSnapshot | undefined = this.tryLoad(backup.current) ?? this.tryLoad(backup.previous);
      if (previous !== undefined) { this.state = 'previous'; return previous; }
    }
    this.state = this.stamp() === ':' ? 'bundled' : 'corrupt'; return undefined;
  }

  /** Called only by a new read-only worker store; no persisted receipt can stand in for these reads. */
  prepare(mode: string, id: string = ''): string[] {
    const stamp: string = this.stamp();
    let snapshot: GameDataSnapshot | undefined;
    if (mode === 'selection') { snapshot = this.recover(); }
    else if (mode === 'stage') { snapshot = this.load(id, this.stagingPath(id)); this.state = 'stage'; }
    else if (mode === 'rollback') { snapshot = this.load(id, this.snapshotPath(id)); this.state = 'rollback'; }
    else { throw new Error('快照校验模式无效'); }
    const result: string[] = ['1', this.root, stamp, this.state, snapshot?.id ?? '', snapshot === undefined ? '' : JSON.stringify(snapshot.manifest)];
    let units: number = 0;
    if (snapshot !== undefined) {
      for (const item of snapshot.manifest.items) {
        if (item.type !== ItemType.Text) { continue; }
        const text: string = snapshot.metadata.get(item.path) ?? ''; units += text.length;
        if (units > GameDataSnapshotStore.MAX_TEXT_UNITS) { throw new Error('快照文本超过后台传输限制'); }
        result.push(item.path, text);
      }
    }
    if (this.stamp() !== stamp) { throw new Error('快照选择在校验期间变化'); }
    return result;
  }
  private decodePrepared(result: string[], mode: string, expectedId: string = ''): GameDataSnapshot | undefined {
    const allowed: string[] = mode === 'selection' ? ['active', 'previous', 'bundled', 'reset', 'corrupt'] : [mode];
    if (result.length < 6 || result.length > 6 + 2 * GameDataManifestPolicy.METADATA.length ||
      result[0] !== '1' || result[1] !== this.root || result[2] !== this.stamp() || !allowed.includes(result[3]) ||
      (expectedId !== '' && result[4] !== expectedId)) { throw new Error('后台校验结果已失效'); }
    if (result[4] === '') {
      if (result.length !== 6 || result[5] !== '' || ['active', 'previous', 'stage', 'rollback'].includes(result[3])) {
        throw new Error('后台校验结果不完整');
      }
      return undefined;
    }
    if (!GameDataSnapshotStore.validId(result[4]) || !['active', 'previous', 'stage', 'rollback'].includes(result[3]) ||
      result[5].length > GameDataManifestPolicy.MAX_MANIFEST_BYTES) { throw new Error('后台快照身份无效'); }
    const source: GameDataSource = new GameDataSource(); source.ref = result[4].substring(0, 40);
    const snapshot: GameDataSnapshot = new GameDataSnapshot(); snapshot.id = result[4]; snapshot.directory = this.snapshotPath(snapshot.id);
    snapshot.manifest = GameDataManifestPolicy.parse(result[5], source, source.ref);
    let offset: number = 6; let units: number = 0;
    for (const item of snapshot.manifest.items) {
      if (item.size < 1 || item.sha256.length !== 64) { throw new Error('后台快照缺少收据'); }
      snapshot.paths.add(item.path);
      if (item.type !== ItemType.Text) { continue; }
      if (offset + 1 >= result.length || result[offset] !== item.path || result[offset + 1].length > GameDataManifestPolicy.MAX_FILE_BYTES) {
        throw new Error('后台元数据不完整');
      }
      units += result[offset + 1].length;
      if (units > GameDataSnapshotStore.MAX_TEXT_UNITS) { throw new Error('后台元数据传输超限'); }
      snapshot.metadata.set(item.path, result[offset + 1]); offset += 2;
    }
    if (offset !== result.length) { throw new Error('后台元数据范围无效'); }
    return snapshot;
  }
  adoptSelection(result: string[], initial: boolean): void {
    if (initial && this.initialized) { return; }
    const snapshot: GameDataSnapshot | undefined = this.decodePrepared(result, 'selection');
    if (initial) { this.session = snapshot; this.initialized = true; this.state = result[3]; }
    this.committed = snapshot; this.committedStamp = result[2]; this.knownSelection = true;
  }
  failInitialization(): void {
    if (this.initialized) { return; }
    this.initialized = true; this.session = undefined; this.committed = undefined;
    this.knownSelection = false; this.state = 'unavailable';
  }
  current(): GameDataSnapshot | undefined {
    if (!this.initialized) { throw new Error('游戏数据尚未初始化'); } return this.session;
  }
  stateText(): string { return this.state; }
  requireReady(): void {
    this.current(); if (!this.knownSelection) { throw new Error('快照校验未完成，请重启后再修改游戏数据'); }
  }
  needsRefresh(): boolean { this.requireReady(); return this.committedStamp !== this.stamp(); }
  committedRevision(): string { this.requireReady(); return this.committed?.manifest.sourceRevision ?? ''; }
  pendingState(): string {
    this.current();
    return this.committed?.id === this.session?.id ? 'none' : this.committed === undefined ? 'bundled' : 'remote';
  }
  pendingVersion(): string { return this.committed?.id !== this.session?.id ? this.committed?.manifest.channelVersion ?? '' : ''; }
  begin(id: string): string {
    this.requireReady(); const path: string = this.stagingPath(id);
    if (this.io.exists(path) || this.io.exists(this.snapshotPath(id))) { throw new Error('暂存版本 ID 已占用'); }
    this.io.mkdir(path); return path;
  }
  private replacePointer(name: string, pointer: SnapshotPointer): void {
    this.io.write(`${this.root}/${name}.next`, this.io.encode(JSON.stringify(pointer)));
    this.io.rename(`${this.root}/${name}.next`, `${this.root}/${name}`);
  }
  publish(id: string, manifest: GameDataManifest, result: string[], check: () => void): void {
    this.requireReady();
    const verified: GameDataSnapshot | undefined = this.decodePrepared(result, 'stage', id);
    if (verified === undefined || JSON.stringify(verified.manifest) !== JSON.stringify(manifest)) { throw new Error('暂存清单与校验结果不一致'); }
    const pointer: SnapshotPointer = new SnapshotPointer(); pointer.current = id; pointer.previous = this.committed?.id ?? '';
    const backup: SnapshotPointer = new SnapshotPointer(); backup.current = pointer.previous;
    check(); this.io.mkdir(`${this.root}/snapshots`); this.io.rename(this.stagingPath(id), this.snapshotPath(id));
    check(); this.replacePointer('active.previous.json', backup);
    check(); this.replacePointer('active.json', pointer);
    this.committed = verified; this.committedStamp = this.stamp();
  }
  reset(): void {
    this.requireReady(); const pointer: SnapshotPointer = new SnapshotPointer();
    this.replacePointer('active.json', pointer);
    // The tombstone already takes effect even if refreshing its backup subsequently fails.
    this.committed = undefined; this.committedStamp = this.stamp();
    this.replacePointer('active.previous.json', pointer); this.committedStamp = this.stamp();
  }
  canRollback(): boolean {
    if (!this.initialized || !this.knownSelection) { return false; }
    try { const id: string = this.rollbackId(); return id !== '' && this.io.exists(`${this.snapshotPath(id)}/complete.json`); }
    catch (_) { return false; }
  }
  rollbackId(): string { this.requireReady(); return this.pointer('active.json')?.previous ?? ''; }
  rollback(result: string[]): boolean {
    this.requireReady(); const id: string = this.rollbackId(); if (id === '') { return false; }
    const verified: GameDataSnapshot | undefined = this.decodePrepared(result, 'rollback', id);
    if (verified === undefined) { throw new Error('回滚快照不可用'); }
    const pointer: SnapshotPointer = new SnapshotPointer(); pointer.current = id; pointer.previous = this.committed?.id ?? '';
    const backup: SnapshotPointer = new SnapshotPointer(); backup.current = pointer.previous;
    this.replacePointer('active.previous.json', backup); this.replacePointer('active.json', pointer);
    this.committed = verified; this.committedStamp = this.stamp(); return true;
  }
}
