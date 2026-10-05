/** Owner- and runtime-epoch-bound local snapshot. It contains no credentials. */
import { fileIo } from '@kit.CoreFileKit';
import { AppContextProvider } from '../../common/AppContext';

const FILE_NAME: string = 'form_snapshot.json';

export class FormSnapshotOwner {
  userId: number = 0;
  uid: string = '';
  epoch: number = -1;
}

export class FormSnapshot {
  static save(resin: string, maxResin: string, expeditionText: string,
    dailyText: string, homeCoinText: string, nickname: string, refreshMs: number,
    resinRecoveryText: string, userId: number = 0, uid: string = '', epoch: number = -1): void {
    const snapshot: Record<string, string> = {
      'nickname': nickname, 'resin': resin, 'maxResin': maxResin, 'expeditionText': expeditionText,
      'dailyText': dailyText, 'homeCoinText': homeCoinText, 'refreshText': FormSnapshot.formatTime(refreshMs),
      'resinRecoveryText': resinRecoveryText, 'tipText': '',
      '_ownerId': String(userId), '_uid': uid, '_epoch': String(epoch),
    };
    FormSnapshot.write(snapshot);
  }

  static empty(tip: string = ''): Record<string, string> {
    const defaults: Record<string, string> = {
      'nickname': '--', 'resin': '--', 'maxResin': '--', 'expeditionText': '暂无数据',
      'dailyText': '刷新后展示', 'homeCoinText': '--', 'refreshText': '--', 'resinRecoveryText': '--', 'tipText': tip,
    };
    return defaults;
  }

  static clear(): void { FormSnapshot.write(FormSnapshot.empty()); }

  private static write(snapshot: Record<string, string>): void {
    let file: fileIo.File | undefined = undefined;
    try {
      const path: string = `${AppContextProvider.getFilesDir()}/${FILE_NAME}`;
      file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, JSON.stringify(snapshot));
    } finally {
      if (file !== undefined) { fileIo.closeSync(file); }
    }
  }

  private static read(): Record<string, Object> {
    try {
      const path: string = `${AppContextProvider.getFilesDir()}/${FILE_NAME}`;
      return JSON.parse(fileIo.readTextSync(path)) as Record<string, Object>;
    } catch (e) { return {}; }
  }

  static owner(): FormSnapshotOwner {
    const data: Record<string, Object> = FormSnapshot.read();
    const owner: FormSnapshotOwner = new FormSnapshotOwner();
    owner.userId = Number(data['_ownerId'] ?? 0);
    owner.uid = String(data['_uid'] ?? '');
    owner.epoch = Number(data['_epoch'] ?? -1);
    if (!Number.isSafeInteger(owner.userId) || !Number.isSafeInteger(owner.epoch)) { return new FormSnapshotOwner(); }
    return owner;
  }

  /** Callers must validate owner/UID/epoch asynchronously before publishing this display-only payload. */
  static load(): Record<string, string> {
    const defaults: Record<string, string> = FormSnapshot.empty();
    const data: Record<string, Object> = FormSnapshot.read();
    const result: Record<string, string> = {};
    for (const key of Object.keys(defaults)) {
      result[key] = data[key] === undefined ? defaults[key] : String(data[key]);
    }
    return result;
  }

  private static formatTime(ms: number): string {
    if (ms <= 0) { return '--'; }
    const date: Date = new Date(ms);
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }
}
