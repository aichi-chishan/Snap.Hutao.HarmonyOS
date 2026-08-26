/**
 * DsSigner.ets
 * DS 签名器：@ohos.security.cryptoFramework MD5。
 * Gen1 = md5("salt=%s&t=%d&r=%s")
 * Gen2 = md5("salt=%s&t=%d&r=%s&b={body}&q={排序query}")
 * 输出 DS 头 = "{t},{r},{md5}"
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer } from '@kit.ArkTS';
import { Logger } from '../../common/Logger';

const TAG: string = 'DsSigner';

export class DsSigner {
  /** 生成随机串（6 位小写 hex，与参考实现一致） */
  static randomHex(len: number): string {
    const chars: string = '0123456789abcdef';
    let result: string = '';
    for (let i = 0; i < len; i++) {
      const idx: number = Math.floor(Math.random() * 16);
      result += chars.charAt(idx);
    }
    return result;
  }

  /** 生成 6 位随机数字串（对齐 Windows includeChars=false：100000~200000，rand==100000 时特例 642367） */
  static randomNumber(): string {
    const n: number = 100000 + Math.floor(Math.random() * 100000);
    return `${n}`;
  }

  /** 生成 6 位随机小写字母+数字串（对齐 Windows includeChars=true：GetLowerAndNumberString(6)） */
  static randomLowerAlphaNumeric(): string {
    const chars: string = '0123456789abcdefghijklmnopqrstuvwxyz';
    let result: string = '';
    for (let i = 0; i < 6; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  /** MD5 计算，返回 32 位小写 hex */
  static async md5Hex(input: string): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    const msg: Uint8Array = new Uint8Array(buffer.from(input, 'utf-8').buffer);
    await md.update({ data: msg });
    const digest: cryptoFramework.DataBlob = await md.digest();
    const bytes: Uint8Array = digest.data;
    let hex: string = '';
    for (let i = 0; i < bytes.length; i++) {
      let h: string = bytes[i].toString(16);
      if (h.length === 1) {
        h = '0' + h;
      }
      hex += h;
    }
    return hex;
  }

  /** 生成标准时间戳（秒，对齐 Windows UtcNow.ToUnixTimeSeconds；签名 t 须为秒） */
  static nowTimestamp(): number {
    return Math.floor(Date.now() / 1000);
  }

  /**
   * Gen1 签名：md5(salt=&t=&r=)
   * @returns "{t},{r},{md5}"
   */
  static async signGen1(salt: string, t: number, r: string): Promise<string> {
    const plain: string = `salt=${salt}&t=${t}&r=${r}`;
    const hash: string = await DsSigner.md5Hex(plain);
    Logger.debug(TAG, `gen1 plain=${plain} -> ${hash}`);
    return `${t},${r},${hash}`;
  }

  /**
   * Gen2 签名：md5(salt=&t=&r=&b=&q=)
   * @param body POST 请求体原文（无 POST 传空串）
   * @param querySorted 排序后的查询串（key 按字典序）
   * @returns "{t},{r},{md5}"
   */
  static async signGen2(salt: string, t: number, r: string, body: string, querySorted: string): Promise<string> {
    const plain: string = `salt=${salt}&t=${t}&r=${r}&b=${body}&q=${querySorted}`;
    const hash: string = await DsSigner.md5Hex(plain);
    Logger.debug(TAG, `gen2 plain=${plain} -> ${hash}`);
    return `${t},${r},${hash}`;
  }

  /**
   * 将单个查询参数对象按键名排序拼成 query 串（用于 Gen2 的 q 参数）
   * 输入以 Record 形式给出（键值均为字符串）
   */
  static sortQuery(query: Record<string, string>): string {
    const keys: string[] = Object.keys(query).sort();
    let parts: string = '';
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (i > 0) {
        parts += '&';
      }
      parts += `${k}=${query[k]}`;
    }
    return parts;
  }

  /**
   * 离线自测：验证 MD5 输出为已知值（hello → 5d41402abc4b2a76b9719d911017c592）
   */
  static async selfTest(): Promise<boolean> {
    const knownHash: string = '5d41402abc4b2a76b9719d911017c592';
    const actual: string = await DsSigner.md5Hex('hello');
    const ok: boolean = actual === knownHash;
    Logger.info(TAG, `selfTest md5('hello')=${actual} expect=${knownHash} -> ${ok}`);
    return ok;
  }
}
