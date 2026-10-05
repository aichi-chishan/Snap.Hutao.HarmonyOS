/**
 * UigfService.ets
 * UIGF v2.2–v4.2 本地导入导出；具体版本和可表示性由纯 codec 校验。
 * 页面通过 taskpool 预检一次，确认只提交保留的数据。归档操作无云依赖。
 */
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaItem } from '../model/GachaItem';
import { GachaArchive } from '../model/GachaArchive';
import { UigfImportPreparation } from '../model/UigfImportPreparation';
import { UigfCodec } from './UigfCodec';
import { UigfExportCodec } from './UigfExportCodec';
import { AppConstants } from '../common/Constants';

/** 导入结果 */
export class UigfImportResult {
  ok: boolean = false;
  message: string = '';
  uid: string = '';
  inserted: number = 0;
  archiveCount: number = 0;
}

export class UigfService {
  private static instance: UigfService = new UigfService();

  static getInstance(): UigfService {
    return UigfService.instance;
  }

  /** Select before reading records. A legacy export never silently drops another UID. */
  async buildExportJson(selectedUids?: string[], version: string = 'v4.2'): Promise<string> {
    const requested: string[] | undefined = selectedUids?.slice();
    if (UigfCodec.VERSIONS.indexOf(version) < 0) { throw new Error('不支持的 UIGF 导出版本'); }
    const archives: GachaArchive[] = await GachaRepo.getAllArchives();
    const selected: string[] = UigfImportPreparation.selectedUids(archives.map((entry: GachaArchive): string => entry.uid), requested);
    if (!version.startsWith('v4.') && selected.length !== 1) { throw new Error(`${version} 只能导出单个 UID，请修改选择`); }
    const records: Map<string, GachaItem[]> = new Map<string, GachaItem[]>();
    for (const archive of archives) {
      if (selected.indexOf(archive.uid) >= 0) { records.set(archive.uid, await GachaRepo.getItemsByArchive(archive.id)); }
    }
    return UigfExportCodec.build(records, version, AppConstants.APP_VERSION);
  }

  /** Pure synchronous adapter for trusted/host callers. Native page uses UigfImportJob. */
  prepareImport(text: string): UigfImportPreparation {
    return new UigfCodec().prepareImport(text);
  }

  /** Confirm the retained validated payload. No JSON parsing and no selection-dependent validation shortcut. */
  async importPrepared(prepared: UigfImportPreparation, selectedUids?: string[], checkCurrent?: () => void): Promise<UigfImportResult> {
    const result: UigfImportResult = new UigfImportResult();
    try {
      checkCurrent?.();
      const pending: Map<string, GachaItem[]> = prepared.select(selectedUids);
      checkCurrent?.();
      const inserted: number = await GachaRepo.importArchives(pending);
      result.inserted = inserted;
      result.archiveCount = pending.size;
      const uids: string[] = Array.from(pending.keys());
      result.uid = uids[uids.length - 1];
      result.ok = true;
      result.message = `导入完成：${result.archiveCount} 个归档，新增 ${result.inserted} 条`;
    } catch (e) {
      result.message = `导入失败：${(e as Error).message}`;
    }
    return result;
  }

  /** Backwards-compatible one-shot entry; the page uses prepare + confirm instead. */
  async importFromText(text: string, selectedUids?: string[]): Promise<UigfImportResult> {
    let prepared: UigfImportPreparation | undefined = undefined;
    try {
      prepared = this.prepareImport(text);
      return await this.importPrepared(prepared, selectedUids);
    } catch (e) {
      const result: UigfImportResult = new UigfImportResult();
      result.message = `导入失败：${(e as Error).message}`;
      return result;
    } finally { prepared?.dispose(); }
  }

  static timezoneOfUid(uid: string): number { return UigfCodec.timezoneOfUid(uid); }
  static normalizeTime(value: string, from: number, to: number): string {
    return UigfCodec.normalizeTime(value, from, to);
  }
}
