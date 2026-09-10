/**
 * FormSnapshot.ets
 * 便笺卡片快照：以 JSON 形式写入应用 filesDir（跨进程共享），供 Form 卡片同步读取（同步 API，无异步初始化约束）。
 */
import { fileIo } from '@kit.CoreFileKit';
import { AppContextProvider } from '../../common/AppContext';
import { Logger } from '../../common/Logger';

const TAG: string = 'FormSnapshot';
const FILE_NAME: string = 'form_snapshot.json';

export class FormSnapshot {
  /** 保存快照（在主应用刷新成功后调用） */
  static save(resin: string, maxResin: string, expeditionText: string,
    dailyText: string, homeCoinText: string, nickname: string, refreshMs: number,
    resinRecoveryText: string): void {
    try {
      const snapshot: Record<string, string> = {
        'nickname': nickname,
        'resin': resin,
        'maxResin': maxResin,
        'expeditionText': expeditionText,
        'dailyText': dailyText,
        'homeCoinText': homeCoinText,
        'refreshText': FormSnapshot.formatTime(refreshMs),
        'resinRecoveryText': resinRecoveryText,
        // 刷新成功清空上一次的失败提示（卡片手动刷新用）
        'tipText': '',
      };
      const path: string = `${AppContextProvider.getFilesDir()}/${FILE_NAME}`;
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, JSON.stringify(snapshot));
      fileIo.closeSync(file);
      Logger.info(TAG, 'snapshot saved');
    } catch (e) {
      Logger.warn(TAG, `snapshot save fail ${JSON.stringify(e)}`);
    }
  }

  /** 读取快照（Form 卡片进程同步读取），无数据返回默认 */
  static load(): Record<string, string> {
    const defaults: Record<string, string> = {
      'nickname': '--',
      'resin': '--',
      'maxResin': '--',
      'expeditionText': '暂无数据',
      'dailyText': '刷新后展示',
      'homeCoinText': '--',
      'refreshText': '--',
      'resinRecoveryText': '--',
      'tipText': '',
    };
    try {
      const path: string = `${AppContextProvider.getFilesDir()}/${FILE_NAME}`;
      const text: string = fileIo.readTextSync(path);
      const obj = JSON.parse(text) as Record<string, Object>;
      const result: Record<string, string> = {};
      for (const k of Object.keys(defaults)) {
        const v: Object = obj[k];
        result[k] = v === undefined ? defaults[k] : String(v);
      }
      return result;
    } catch (e) {
      return defaults;
    }
  }

  private static formatTime(ms: number): string {
    if (ms <= 0) {
      return '--';
    }
    const d: Date = new Date(ms);
    const pad = (n: number): string => (n < 10 ? '0' + n : n.toString());
    return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
}
