import { UigfError } from '../model/UigfError';
/** Versioned primitive-only worker envelope; never carries JSON text, handles, or account state. */
import { GachaItem } from '../model/GachaItem';
import { GachaType } from '../model/GachaType';
import { UigfArchivePreview, UigfImportPreparation, UigfImportPreview } from '../model/UigfImportPreparation';
import { UigfBounds } from '../model/UigfBounds';
import { UigfCodec } from './UigfCodec';

export class UigfImportTransfer {
  static readonly FORMAT: string = 'uigf-records-2';
  static readonly ERROR: string = 'uigf-error-2';
  private static readonly ROW_FIELDS: number = 9;

  static encode(prepared: UigfImportPreparation, checkpoint: () => void): string[] {
    const archives: Map<string, GachaItem[]> = prepared.select();
    const wire: string[] = [UigfImportTransfer.FORMAT, prepared.preview().version, String(archives.size)];
    let units: number = 64;
    let rows: number = 0;
    for (const uid of archives.keys()) {
      const items: GachaItem[] = archives.get(uid) ?? [];
      wire.push(uid, String(items.length));
      units += uid.length + 16;
      for (const item of items) {
        if (++rows > UigfBounds.MAX_ROWS) { throw new UigfError('UIGF 记录超过 262144 条限制'); }
        if (rows % 256 === 0) { checkpoint(); }
        const fields: string[] = [item.gachaId, String(item.gachaType), String(item.itemId), String(item.count),
          item.time, item.name, item.itemType, String(item.rankType), String(item.scheduleId)];
        for (const value of fields) {
          if (value.length > UigfBounds.MAX_FIELD_UNITS) { throw new UigfError('UIGF 记录字段超过 4096 字符限制'); }
          units += value.length;
          if (units > UigfBounds.MAX_WIRE_UNITS) { throw new UigfError('UIGF 后台传输超过 48 Mi 字符限制'); }
          wire.push(value);
        }
      }
    }
    checkpoint();
    return wire;
  }

  /** Native structured clone supplies strings; restore models in bounded slices, never JSON.parse. */
  static async adopt(wire: string[], checkpoint: () => void): Promise<UigfImportPreparation> {
    checkpoint();
    if (!Array.isArray(wire) || wire.length < 2) { throw new UigfError('UIGF 后台结果无效'); }
    if (wire[0] === UigfImportTransfer.ERROR) {
      if (wire.length !== 2 || typeof wire[1] !== 'string' || wire[1].length > 512) { throw new UigfError('UIGF 后台结果无效'); }
      throw new UigfError(wire[1]);
    }
    if (wire.length < 5 || wire.length > 3 + 2 * UigfBounds.MAX_ARCHIVES + UigfImportTransfer.ROW_FIELDS * UigfBounds.MAX_ROWS ||
      wire[0] !== UigfImportTransfer.FORMAT || UigfCodec.VERSIONS.indexOf(wire[1]) < 0) { throw new UigfError('UIGF 后台结果无效'); }
    const archiveCount: number = UigfImportTransfer.integer(wire[2], 1, UigfBounds.MAX_ARCHIVES);
    const archives: Map<string, GachaItem[]> = new Map<string, GachaItem[]>();
    const preview: UigfImportPreview = new UigfImportPreview();
    preview.version = wire[1];
    let cursor: number = 3;
    let total: number = 0;
    let units: number = 64;
    let sliceUnits: number = 0;
    try {
      for (let archive: number = 0; archive < archiveCount; archive++) {
        checkpoint();
        const uid: string = wire[cursor++];
        if (typeof uid !== 'string' || !/^[1-9][0-9]{8,9}$/.test(uid) || archives.has(uid)) { throw new UigfError('UIGF 后台结果无效'); }
        const count: number = UigfImportTransfer.integer(wire[cursor++], 0, UigfBounds.MAX_ROWS);
        units += uid.length + 16;
        if (total + count > UigfBounds.MAX_ROWS || cursor + count * UigfImportTransfer.ROW_FIELDS > wire.length) { throw new UigfError('UIGF 后台结果无效'); }
        const summary: UigfArchivePreview = new UigfArchivePreview();
        summary.uid = uid;
        const items: GachaItem[] = [];
        const ids: Set<string> = new Set<string>();
        archives.set(uid, items);
        for (let row: number = 0; row < count; row++) {
          for (let field: number = 0; field < UigfImportTransfer.ROW_FIELDS; field++) {
            const value: string = wire[cursor + field];
            if (typeof value !== 'string' || value.length > UigfBounds.MAX_FIELD_UNITS) { throw new UigfError('UIGF 后台结果无效'); }
            units += value.length;
            sliceUnits += value.length;
          }
          if (units > UigfBounds.MAX_WIRE_UNITS) { throw new UigfError('UIGF 后台结果超过传输限制'); }
          const item: GachaItem = new GachaItem();
          item.uid = uid;
          item.gachaId = wire[cursor++];
          item.gachaType = UigfImportTransfer.integer(wire[cursor++], 1, 99999);
          item.itemId = UigfImportTransfer.integer(wire[cursor++], 1, Number.MAX_SAFE_INTEGER);
          item.count = UigfImportTransfer.integer(wire[cursor++], 1, Number.MAX_SAFE_INTEGER);
          item.time = wire[cursor++];
          if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(item.time)) { throw new UigfError('UIGF 后台时间无效'); }
          const timezone: number = UigfCodec.timezoneOfUid(uid);
          if (UigfCodec.normalizeTime(item.time, timezone, timezone) !== item.time) { throw new UigfError('UIGF 后台时间无效'); }
          item.name = wire[cursor++];
          item.itemType = wire[cursor++];
          item.rankType = UigfImportTransfer.integer(wire[cursor++], 3, 5);
          item.scheduleId = UigfImportTransfer.integer(wire[cursor++], 0, Number.MAX_SAFE_INTEGER);
          UigfCodec.validateItem(item);
          const beyond: boolean = GachaType.isBeyond(item.gachaType);
          const key: string = `${beyond ? 'b' : 's'}:${item.gachaId}`;
          if (ids.has(key)) { throw new UigfError('UIGF 后台结果包含重复记录'); }
          ids.add(key);
          items.push(item);
          if (beyond) { summary.beyondCount++; } else { summary.standardCount++; }
          total++;
          if (total % 256 === 0 || sliceUnits >= 65536) {
            sliceUnits = 0;
            // Only bounded hydration yields here. File reading, preflight and JSON parsing run in taskpool.
            await new Promise<void>((resolve) => { setTimeout(resolve, 0); });
            checkpoint();
          }
        }
        summary.totalCount = count;
        preview.archives.push(summary);
        preview.uids.push(uid);
      }
      if (cursor !== wire.length) { throw new UigfError('UIGF 后台结果包含多余数据'); }
      preview.totalCount = total;
      preview.archiveCount = archiveCount;
      checkpoint();
      return new UigfImportPreparation(preview.version, archives, preview);
    } catch (e) {
      archives.clear();
      if (e instanceof Error) { throw e; }
      throw new Error('UIGF 处理失败，请重新选择文件');
    }
  }

  private static integer(value: string, min: number, max: number): number {
    if (typeof value !== 'string' || value.length > 16 || !/^(0|[1-9][0-9]*)$/.test(value)) { throw new UigfError('UIGF 后台数值无效'); }
    const number: number = Number(value);
    if (!Number.isSafeInteger(number) || number < min || number > max) { throw new UigfError('UIGF 后台数值无效'); }
    return number;
  }
}
