import { UigfError } from '../../model/UigfError';
import { fileIo } from '@kit.CoreFileKit';
import { taskpool, util } from '@kit.ArkTS';
import { UigfBounds } from '../../model/UigfBounds';
import { UigfImportPreparation } from '../../model/UigfImportPreparation';
import { UigfCodec } from '../../service/UigfCodec';
import { UigfImportTransfer } from '../../service/UigfImportTransfer';

/** Primitive URI/text/deadline in; fully validated primitive records out. No database dependency. */
@Concurrent
export function prepareUigfImport(source: string, isFile: boolean, deadline: number): string[] {
  let prepared: UigfImportPreparation | undefined = undefined;
  try {
    const check: () => void = (): void => {
      if (taskpool.Task.isCanceled()) { throw new UigfError('UIGF 解析已取消'); }
      if (!Number.isSafeInteger(deadline) || Date.now() >= deadline) { throw new UigfError('UIGF 后台解析超时，请拆分文件后重试'); }
    };
    check();
    let text: string = source;
    if (isFile) {
      const file: fileIo.File = fileIo.openSync(source, fileIo.OpenMode.READ_ONLY);
      try {
        const size: number = fileIo.statSync(file.fd).size;
        if (!Number.isSafeInteger(size) || size <= 0 || size > UigfBounds.MAX_BYTES) { throw new UigfError('UIGF 文件为空或超过 32 MiB 限制'); }
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        const read: number = fileIo.readSync(file.fd, buffer);
        if (read !== size || fileIo.statSync(file.fd).size !== size) { throw new UigfError('UIGF 文件读取不完整或大小发生变化'); }
        check();
        try { text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(buffer)); }
        catch (_) { throw new UigfError('UIGF 文件不是有效的 UTF-8 文本'); }
      } finally { fileIo.closeSync(file); }
    }
    check();
    prepared = new UigfCodec().prepareImport(text, check);
    return UigfImportTransfer.encode(prepared, check);
  } catch (e) {
    const message: string = (e as Error).message;
    // Do not leak paths, document provider errors or raw JSON parser fragments to the UI.
    return [UigfImportTransfer.ERROR, e instanceof UigfError && typeof message === 'string'
      ? message.substring(0, 512) : 'UIGF 文件无法读取或后台解析失败，请重新选择文件'];
  } finally { prepared?.dispose(); }
}
