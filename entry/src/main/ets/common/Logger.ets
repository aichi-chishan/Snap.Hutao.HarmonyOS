import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppContextProvider } from './AppContext';

/** Immediate HiLog output and a bounded, best-effort app.log. */
export class Logger {
  static readonly DOMAIN: number = 0x4E50;
  static readonly PREFIX: string = 'SnapHutao';
  private static readonly FILE_LIMIT: number = 256 * 1024;
  private static readonly MAX_PENDING_LINES: number = 800;
  private static readonly MAX_LINE_CHARS: number = 4096;
  private static readonly FLUSH_DELAY_MS: number = 250;
  private static pending: string[] = [];
  private static timer: number = -1;
  private static writing: Promise<void> | undefined = undefined;

  /** Flush queued diagnostics when the ability enters the background. */
  static flush(): Promise<void> {
    if (Logger.timer >= 0) {
      clearTimeout(Logger.timer);
      Logger.timer = -1;
    }
    if (Logger.writing !== undefined) { return Logger.writing; }
    if (Logger.pending.length === 0) { return Promise.resolve(); }
    const writing: Promise<void> = Logger.drain().finally(() => {
      Logger.writing = undefined;
      Logger.schedule();
    });
    Logger.writing = writing;
    return writing;
  }

  private static enqueue(level: string, tag: string, message: string): void {
    const line: string = `${new Date().toISOString()} ${level} [${tag}] ${message}`;
    if (Logger.pending.length >= Logger.MAX_PENDING_LINES) { Logger.pending.shift(); }
    Logger.pending.push(line.length > Logger.MAX_LINE_CHARS ? `${line.substring(0, Logger.MAX_LINE_CHARS - 1)}…` : line);
    Logger.schedule();
  }

  private static schedule(): void {
    if (Logger.timer < 0 && Logger.writing === undefined && Logger.pending.length > 0) {
      Logger.timer = setTimeout(() => { Logger.flush(); }, Logger.FLUSH_DELAY_MS);
    }
  }

  private static async drain(): Promise<void> {
    while (Logger.pending.length > 0) {
      const lines: string[] = Logger.pending;
      Logger.pending = [];
      try { await Logger.appendBatch(lines); }
      catch (_) { /* HiLog already received the messages. */ }
    }
  }

  /** Drop a partial line at the cut so the retained UTF-8 starts at a line boundary. */
  private static tail(bytes: Uint8Array, limit: number): Uint8Array {
    if (bytes.byteLength <= limit) { return bytes; }
    const separator: number = bytes.indexOf(10, bytes.byteLength - limit - 1);
    return separator < 0 ? new Uint8Array(0) : bytes.slice(separator + 1);
  }

  private static async appendBatch(lines: string[]): Promise<void> {
    const text: string = `${lines.join('\n')}\n`;
    const bytes: Uint8Array = Logger.tail(util.TextEncoder.create('utf-8').encodeInto(text), Logger.FILE_LIMIT);
    const path: string = `${AppContextProvider.getFilesDir()}/app.log`;
    const file: fileIo.File = await fileIo.open(path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND | fileIo.OpenMode.NOFOLLOW);
    try {
      // Extension abilities share the same app.log. Closing the file releases the lock.
      await file.lock(true);
      const size: number = (await fileIo.stat(file.fd)).size;
      let appendOffset: number = size;
      let output: Uint8Array = bytes;
      if (size + bytes.byteLength > Logger.FILE_LIMIT) {
        const limit: number = Logger.FILE_LIMIT - bytes.byteLength;
        const length: number = Math.min(size, limit + 1);
        if (length > 0 && limit > 0) {
          const old: ArrayBuffer = new ArrayBuffer(length);
          if (await fileIo.read(file.fd, old, { offset: size - length }) !== length) {
            throw new Error('Incomplete log read');
          }
          const retained: Uint8Array = Logger.tail(new Uint8Array(old), limit);
          output = new Uint8Array(retained.byteLength + bytes.byteLength);
          output.set(retained);
          output.set(bytes, retained.byteLength);
        }
        await fileIo.truncate(file.fd, 0);
        appendOffset = 0;
      }
      const buffer: ArrayBuffer = new Uint8Array(output).buffer as ArrayBuffer;
      const written: number = await fileIo.write(file.fd, buffer);
      if (written < output.byteLength) {
        const complete: number = written > 0 ? output.lastIndexOf(10, written - 1) + 1 : 0;
        await fileIo.truncate(file.fd, appendOffset + complete);
      }
    } finally {
      await fileIo.close(file);
    }
  }

  static info(tag: string, message: string): void {
    hilog.info(Logger.DOMAIN, Logger.PREFIX, '[%{public}s] %{public}s', tag, message);
    Logger.enqueue('I', tag, message);
  }

  static debug(tag: string, message: string): void {
    hilog.debug(Logger.DOMAIN, Logger.PREFIX, '[%{public}s] %{public}s', tag, message);
    Logger.enqueue('D', tag, message);
  }

  static warn(tag: string, message: string): void {
    hilog.warn(Logger.DOMAIN, Logger.PREFIX, '[%{public}s] %{public}s', tag, message);
    Logger.enqueue('W', tag, message);
  }

  static error(tag: string, message: string): void {
    hilog.error(Logger.DOMAIN, Logger.PREFIX, '[%{public}s] %{public}s', tag, message);
    Logger.enqueue('E', tag, message);
  }
}
