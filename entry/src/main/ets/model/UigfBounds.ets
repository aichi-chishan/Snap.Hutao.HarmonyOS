import { UigfError } from './UigfError';
/** Independent bounds apply before parsing, normalization, transfer, and hydration. */
export class UigfBounds {
  static readonly MAX_BYTES: number = 32 * 1024 * 1024;
  static readonly MAX_TEXT_UNITS: number = 32 * 1024 * 1024;
  static readonly MAX_ARCHIVES: number = 1024;
  static readonly MAX_ROWS: number = 262144;
  static readonly MAX_DEPTH: number = 32;
  static readonly MAX_FIELD_UNITS: number = 4096;
  static readonly MAX_WIRE_UNITS: number = 48 * 1024 * 1024;
  static readonly WAIT_MS: number = 30000;

  /** Scan nesting/string boundaries before JSON.parse, with bounded cooperative checkpoints. */
  static preflight(text: string, checkpoint?: () => void): void {
    if (text.length === 0 || text.length > UigfBounds.MAX_TEXT_UNITS) { throw new UigfError('UIGF 文件为空或超过 32 Mi 字符限制'); }
    let depth: number = 0;
    let quoted: boolean = false;
    let escaped: boolean = false;
    for (let i: number = 0; i < text.length; i++) {
      if (i % 4096 === 0) { checkpoint?.(); }
      const c: string = text.charAt(i);
      if (quoted) {
        if (escaped) { escaped = false; }
        else if (c === '\\') { escaped = true; }
        else if (c === '"') { quoted = false; }
      } else if (c === '"') { quoted = true; }
      else if (c === '{' || c === '[') {
        if (++depth > UigfBounds.MAX_DEPTH) { throw new UigfError('UIGF JSON 嵌套超过 32 层限制'); }
      } else if (c === '}' || c === ']') { depth--; }
      if (depth < 0) { throw new UigfError('UIGF JSON 格式无效'); }
    }
    if (quoted || depth !== 0) { throw new UigfError('UIGF JSON 格式无效'); }
    checkpoint?.();
  }
}
