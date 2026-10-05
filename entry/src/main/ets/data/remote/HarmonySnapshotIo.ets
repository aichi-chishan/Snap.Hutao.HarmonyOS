import { fileIo, statfs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { GameDataSnapshotIo } from './GameDataSnapshotStore';

class SnapshotIoError { code: number | string = 0; }

/** All paths stay in an isolated cohort root; legacy gamedata is never overwritten or deleted. */
export class HarmonySnapshotIo implements GameDataSnapshotIo {
  readonly root: string;
  private sandbox: string;
  constructor(filesDir: string) { this.sandbox = filesDir; this.root = `${filesDir}/gamedata/cohort-v1`; }
  static missing(error: Object): boolean {
    const code: number | string = (error as SnapshotIoError).code;
    return code === 13900002 || code === 2 || code === 'ENOENT';
  }
  encode(text: string): Uint8Array { return new util.TextEncoder().encodeInto(text); }
  decode(bytes: Uint8Array): string { return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes); }
  sha256(bytes: Uint8Array): string {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256'); md.updateSync({ data: bytes });
    let text: string = ''; for (const byte of md.digestSync().data) { text += byte.toString(16).padStart(2, '0'); } return text;
  }
  /** Native asynchronous hashing avoids running payload digest work on the UI runtime. */
  async sha256Async(bytes: Uint8Array): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256'); await md.update({ data: bytes });
    const digest: cryptoFramework.DataBlob = await md.digest();
    let text: string = ''; for (const byte of digest.data) { text += byte.toString(16).padStart(2, '0'); } return text;
  }
  private guard(path: string): void {
    if ((path !== this.root && !path.startsWith(`${this.root}/`)) || path.includes('\\') ||
      path.substring(this.sandbox.length + 1).split('/').some((part: string): boolean => !/^[A-Za-z0-9_.-]+$/.test(part) || part === '.' || part === '..')) {
      throw new Error('游戏数据路径超出所属目录');
    }
  }
  private directories(path: string, create: boolean): void {
    let current: string = this.sandbox;
    const base: fileIo.Stat = fileIo.lstatSync(current);
    if (!base.isDirectory() || base.isSymbolicLink()) { throw new Error('应用存储目录无效'); }
    for (const part of path.substring(this.sandbox.length + 1).split('/')) {
      current += `/${part}`;
      let stat: fileIo.Stat;
      try { stat = fileIo.lstatSync(current); }
      catch (error) {
        if (!create || !HarmonySnapshotIo.missing(error as Object)) { throw error as Error; }
        fileIo.mkdirSync(current); stat = fileIo.lstatSync(current);
      }
      if (!stat.isDirectory() || stat.isSymbolicLink()) { throw new Error('游戏数据目录包含不安全路径'); }
    }
  }
  mkdir(path: string): void { this.guard(path); this.directories(path, true); }
  exists(path: string): boolean {
    this.guard(path);
    try { this.directories(path.substring(0, path.lastIndexOf('/')), false); fileIo.lstatSync(path); return true; }
    catch (error) { if (HarmonySnapshotIo.missing(error as Object)) { return false; } throw error as Error; }
  }
  read(path: string, limit: number): Uint8Array {
    this.guard(path); this.directories(path.substring(0, path.lastIndexOf('/')), false);
    const file: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NOFOLLOW);
    try {
      const stat: fileIo.Stat = fileIo.statSync(file.fd);
      if (!stat.isFile() || stat.size < 1 || stat.size > limit) { throw new Error('文件大小超过校验限制'); }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      if (fileIo.readSync(file.fd, buffer) !== stat.size) { throw new Error('文件读取不完整'); }
      return new Uint8Array(buffer);
    } finally { fileIo.closeSync(file); }
  }
  write(path: string, bytes: Uint8Array): void {
    this.guard(path); this.directories(path.substring(0, path.lastIndexOf('/')), true);
    const file: fileIo.File = fileIo.openSync(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.NOFOLLOW);
    try {
      const buffer: ArrayBuffer = new ArrayBuffer(bytes.byteLength); new Uint8Array(buffer).set(bytes);
      if (fileIo.writeSync(file.fd, buffer) !== bytes.byteLength) { throw new Error('文件写入不完整，旧版本未改变'); }
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
  }
  rename(from: string, to: string): void {
    this.guard(from); this.guard(to);
    this.directories(from.substring(0, from.lastIndexOf('/')), false);
    this.directories(to.substring(0, to.lastIndexOf('/')), true);
    const source: fileIo.Stat = fileIo.lstatSync(from);
    if (source.isSymbolicLink() || (!source.isFile() && !source.isDirectory())) { throw new Error('快照路径类型无效'); }
    try {
      const target: fileIo.Stat = fileIo.lstatSync(to);
      if (!source.isFile() || !target.isFile() || target.isSymbolicLink()) { throw new Error('快照目标已占用'); }
    } catch (error) { if (!HarmonySnapshotIo.missing(error as Object)) { throw error as Error; } }
    fileIo.renameSync(from, to);
  }
  acquire(): fileIo.File {
    this.mkdir(this.root);
    const file: fileIo.File = fileIo.openSync(`${this.root}/writer.lock`, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.NOFOLLOW);
    try { file.tryLock(true); return file; }
    catch (error) { fileIo.closeSync(file); throw new Error('游戏数据正在由另一任务处理，请稍后重试'); }
  }
  release(file: fileIo.File): void { fileIo.closeSync(file); }
  /** Includes abandoned staging and previous snapshots. No data is deleted to make room. */
  usedBytes(): number {
    this.mkdir(this.root);
    const pending: string[] = [this.root];
    let entries: number = 0;
    let bytes: number = 0;
    while (pending.length > 0) {
      const directory: string = pending[pending.length - 1]; pending.pop();
      // Never ask a recursive enumerator to traverse an entry before its type is checked.
      this.directories(directory, false);
      const names: string[] = fileIo.listFileSync(directory, { recursion: false, listNum: 100001 - entries });
      entries += names.length;
      if (entries > 100000) { throw new Error('游戏数据文件数量超过工作区限制'); }
      for (const name of names) {
        const relative: string = name.startsWith('/') ? name.substring(1) : name;
        if (relative.length === 0 || relative.includes('/')) { throw new Error('工作区包含不安全路径'); }
        const path: string = `${directory}/${relative}`; this.guard(path);
        const stat: fileIo.Stat = fileIo.lstatSync(path);
        if (stat.isSymbolicLink() || (!stat.isFile() && !stat.isDirectory())) { throw new Error('工作区包含不安全路径'); }
        if (stat.isFile()) { bytes += stat.size; }
        else { pending.push(path); }
      }
    }
    return bytes;
  }
  freeBytes(): number { return statfs.getFreeSizeSync(this.root); }
}

/** Verification worker may only read. No method can rename, write, reset or publish. */
export class HarmonySnapshotReadIo extends HarmonySnapshotIo {
  private identities: Map<string, string> = new Map<string, string>();
  private identity(path: string): string {
    const stat: fileIo.Stat = fileIo.lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink()) { throw new Error('快照不是普通文件'); }
    return `${stat.ino}:${stat.size}:${stat.mtimeNs ?? stat.mtime}:${stat.ctimeNs ?? stat.ctime}`;
  }
  read(path: string, limit: number): Uint8Array {
    const before: string = this.identity(path); const bytes: Uint8Array = super.read(path, limit);
    if (this.identity(path) !== before) { throw new Error('快照文件在读取期间变化'); }
    const previous: string | undefined = this.identities.get(path);
    if (previous !== undefined && previous !== before) { throw new Error('快照文件在校验期间变化'); }
    this.identities.set(path, before); return bytes;
  }
  verifyUnchanged(): void {
    for (const item of this.identities) { if (this.identity(item[0]) !== item[1]) { throw new Error('快照文件在校验期间变化'); } }
  }
  write(_path: string, _bytes: Uint8Array): void { throw new Error('快照校验只读'); }
  mkdir(_path: string): void { throw new Error('快照校验只读'); }
  rename(_from: string, _to: string): void { throw new Error('快照校验只读'); }
  acquire(): fileIo.File { throw new Error('快照校验只读'); }
}
