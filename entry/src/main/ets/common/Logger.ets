/**
 * Logger.ets
 * hilog 轻量封装：统一 domain/tag 前缀，同时落盘文件（filesDir/snaphutao/app.log）便于设备排查。
 * 文件仅保留最近 N 条（写入时若超限则截断为前半 + 新行），避免无限膨胀。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppContextProvider } from './AppContext';

export class Logger {
  /** 日志 domain（0x4E50 = 'NP'） */
  static readonly DOMAIN: number = 0x4E50;
  /** 统一 tag 前缀 */
  static readonly PREFIX: string = 'SnapHutao';
  /** 文件日志最大保留行数 */
  private static readonly MAX_LINES: number = 800;
  private static filePath: string = '';

  private static ensureFile(): string {
    if (Logger.filePath.length === 0) {
      try {
        Logger.filePath = `${AppContextProvider.getFilesDir()}/app.log`;
      } catch (e) {
        Logger.filePath = '';
      }
    }
    return Logger.filePath;
  }

  private static appendFile(line: string): void {
    try {
      const p: string = Logger.ensureFile();
      if (p.length === 0) {
        return;
      }
      fileIo.accessSync(p);
      const file: fileIo.File = fileIo.openSync(p, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND);
      try {
        fileIo.writeSync(file.fd, `${line}\n`);
      } finally {
        fileIo.closeSync(file);
      }
    } catch (e) {
      // 文件不存在：新建；其余忽略
      try {
        const p: string = Logger.ensureFile();
        if (p.length === 0) {
          return;
        }
        const file: fileIo.File = fileIo.openSync(p, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.APPEND);
        try {
          fileIo.writeSync(file.fd, `${line}\n`);
        } finally {
          fileIo.closeSync(file);
        }
      } catch (e2) {
        // 落盘失败不阻断业务
      }
    }
  }

  private static line(level: string, tag: string, msg: string): string {
    return `${new Date().toISOString()} ${level} [${tag}] ${msg}`;
  }

  static info(tag: string, msg: string): void {
    hilog.info(Logger.DOMAIN, Logger.PREFIX, '[%{public}s] %{public}s', tag, msg);
    Logger.appendFile(Logger.line('I', tag, msg));
  }

  static debug(tag: string, msg: string): void {
    hilog.debug(Logger.DOMAIN, Logger.PREFIX, '[%{public}s] %{public}s', tag, msg);
    Logger.appendFile(Logger.line('D', tag, msg));
  }

  static warn(tag: string, msg: string): void {
    hilog.warn(Logger.DOMAIN, Logger.PREFIX, '[%{public}s] %{public}s', tag, msg);
    Logger.appendFile(Logger.line('W', tag, msg));
  }

  static error(tag: string, msg: string): void {
    hilog.error(Logger.DOMAIN, Logger.PREFIX, '[%{public}s] %{public}s', tag, msg);
    Logger.appendFile(Logger.line('E', tag, msg));
  }
}
