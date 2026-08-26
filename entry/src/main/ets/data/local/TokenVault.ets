/**
 * TokenVault.ets
 * 基于 @kit.AssetStoreKit 的关键资产安全存储，用于 Cookie/Token 密文落库与读取。
 * 每个账号一条资产，alias = "snap_hutao_token_{userId}"，secret = 完整 Cookie 串。
 */
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../../common/Logger';

const TAG: string = 'TokenVault';

export class TokenVault {
  private static aliasOf(userId: number): Uint8Array {
    return TokenVault.strToBytes(`snap_hutao_token_${userId}`);
  }

  private static strToBytes(s: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(s);
  }

  private static bytesToStr(b: Uint8Array): string {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(b);
  }

  /** 保存某账号的完整 Cookie（upsert） */
  static async saveCookie(userId: number, cookie: string): Promise<void> {
    const attr: asset.AssetMap = new Map();
    attr.set(asset.Tag.SECRET, TokenVault.strToBytes(cookie));
    attr.set(asset.Tag.ALIAS, TokenVault.aliasOf(userId));
    attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attr.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(attr);
      Logger.info(TAG, `saved cookie for user ${userId}`);
    } catch (e) {
      // 已存在则更新
      try {
        const query: asset.AssetMap = new Map();
        query.set(asset.Tag.ALIAS, TokenVault.aliasOf(userId));
        const update: asset.AssetMap = new Map();
        update.set(asset.Tag.SECRET, TokenVault.strToBytes(cookie));
        await asset.update(query, update);
        Logger.info(TAG, `updated cookie for user ${userId}`);
      } catch (e2) {
        Logger.warn(TAG, `save cookie fail: ${JSON.stringify(e2)}`);
      }
    }
  }

  /** 读取某账号的完整 Cookie，未找到返回空串 */
  static async loadCookie(userId: number): Promise<string> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, TokenVault.aliasOf(userId));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const res: Array<asset.AssetMap> = await asset.query(query);
      if (res.length === 0) {
        return '';
      }
      const secret: asset.Value = res[0].get(asset.Tag.SECRET) as asset.Value;
      if (secret === undefined || secret === null) {
        return '';
      }
      const bytes: Uint8Array = secret as Uint8Array;
      return TokenVault.bytesToStr(bytes);
    } catch (e) {
      Logger.warn(TAG, `load cookie fail: ${JSON.stringify(e)}`);
      return '';
    }
  }

  /** 删除某账号的关键资产（退出登录/删除账号时） */
  static async removeCookie(userId: number): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, TokenVault.aliasOf(userId));
    try {
      await asset.remove(query);
      Logger.info(TAG, `removed cookie for user ${userId}`);
    } catch (e) {
      Logger.warn(TAG, `remove cookie fail: ${JSON.stringify(e)}`);
    }
  }
}
