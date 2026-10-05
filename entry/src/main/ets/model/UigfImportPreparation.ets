/** Pure, owned preparation for the confirmation screen; no database or account dependencies. */
import { GachaItem } from './GachaItem';
import { GachaType } from './GachaType';

export class UigfArchivePreview {
  uid: string = '';
  totalCount: number = 0;
  standardCount: number = 0;
  beyondCount: number = 0;
}

export class UigfImportPreview {
  version: string = '';
  archiveCount: number = 0;
  totalCount: number = 0;
  archives: UigfArchivePreview[] = [];
  uids: string[] = [];
}

export class UigfImportPreparation {
  static readonly MAX_TEXT_CODE_UNITS: number = 32 * 1024 * 1024;
  static readonly MAX_ARCHIVES: number = 1024;
  private archives: Map<string, GachaItem[]>;
  private version: string;
  private disposed: boolean = false;

  constructor(version: string, archives: Map<string, GachaItem[]>) {
    if (archives.size === 0) { throw new Error('UIGF 没有可导入的原神归档'); }
    if (archives.size > UigfImportPreparation.MAX_ARCHIVES) { throw new Error('UIGF 最多预览 1024 个归档，请拆分文件'); }
    this.version = version;
    this.archives = archives;
  }

  /** Fresh summaries cannot mutate the prepared records or expand the selected UID set. */
  preview(): UigfImportPreview {
    this.checkActive();
    const result: UigfImportPreview = new UigfImportPreview();
    result.version = this.version;
    for (const uid of this.archives.keys()) {
      const archive: UigfArchivePreview = new UigfArchivePreview();
      archive.uid = uid;
      for (const item of this.archives.get(uid) ?? []) {
        if (GachaType.isBeyond(item.gachaType)) { archive.beyondCount++; } else { archive.standardCount++; }
      }
      archive.totalCount = archive.standardCount + archive.beyondCount;
      result.archives.push(archive);
      result.uids.push(uid);
      result.totalCount += archive.totalCount;
    }
    result.archiveCount = result.archives.length;
    return result;
  }

  /** Repository owns value copies. It must not mutate the prepared records during retries. */
  select(selectedUids?: string[]): Map<string, GachaItem[]> {
    this.checkActive();
    const selected: string[] = UigfImportPreparation.selectedUids(Array.from(this.archives.keys()), selectedUids);
    const result: Map<string, GachaItem[]> = new Map<string, GachaItem[]>();
    for (const uid of selected) { result.set(uid, (this.archives.get(uid) ?? []).slice()); }
    return result;
  }

  dispose(): void {
    this.disposed = true;
    this.archives.clear();
  }

  private checkActive(): void {
    if (this.disposed) { throw new Error('UIGF 预览已失效，请重新选择文件'); }
  }

  /** undefined means all; explicit empty/unknown selection must never fall back to all. */
  static selectedUids(available: string[], selectedUids?: string[]): string[] {
    const source: string[] = selectedUids === undefined ? available : selectedUids;
    if (source.length === 0) { throw new Error('请至少选择一个 UID'); }
    const selected: string[] = [];
    for (const uid of source) {
      if (!/^[1-9][0-9]{8,9}$/.test(uid) || available.indexOf(uid) < 0) { throw new Error(`未找到有效的所选 UID：${uid}`); }
      if (selected.indexOf(uid) < 0) { selected.push(uid); }
    }
    return selected;
  }
}
