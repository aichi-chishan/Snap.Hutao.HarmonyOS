/**
 * RsaEncryptor.ets
 * 国服 passport 手机号 RSA 公钥加密（RSA/ECB/PKCS1Padding → Base64）。
 * 公钥来自 Snap Hutao 参考实现（UIGF Hoyolab.Salt 中 cn_passport 公钥，1024-bit）。
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer, util } from '@kit.ArkTS';
import { Logger } from '../../common/Logger';

const TAG: string = 'RsaEncryptor';

/** 国服 passport RSA 公钥（X.509/PKCS#1 1024 bit，PEM → 去掉头尾后为 base64 DER） */
const CN_PASSPORT_PUB_KEY_B64: string =
  'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDDvekdPMHN3AYhm/vktJT+YJr7' +
  'cI5DcsNKqdsx5DZX0gDuWFuIjzdwButrIYPNmRJ1G8ybDIF7oDW2eEpm5sMbL9zs' +
  '9ExXCdvqrn51qELbqj0XxtMTIpaCHFSI50PfPpTFV9Xt/hmyVwokoOXFlAEgCn+Q' +
  'CgGs52bFoYMtyi+xEQIDAQAB';

export class RsaEncryptor {
  private static base64: util.Base64Helper = new util.Base64Helper();

  /** 将公钥 Base64(DER) 转为密钥 DataBlob */
  private static pubKeyBlob(): cryptoFramework.DataBlob {
    const bytes: Uint8Array = RsaEncryptor.base64.decodeSync(CN_PASSPORT_PUB_KEY_B64);
    const blob: cryptoFramework.DataBlob = { data: bytes };
    return blob;
  }

  /** 使用国服公钥 RSA/PKCS1 加密字符串，返回 base64 */
  static async encrypt(source: string): Promise<string> {
    const generator: cryptoFramework.AsyKeyGenerator =
      cryptoFramework.createAsyKeyGenerator('RSA1024');
    const keyPair: cryptoFramework.KeyPair =
      await generator.convertKey(RsaEncryptor.pubKeyBlob(), null);
    // RSA|PKCS1 单块加密（PKCS#1 v1.5），等价 Java RSA/ECB/PKCS1Padding
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('RSA|PKCS1');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, keyPair.pubKey, null);
    const input: Uint8Array = new Uint8Array(buffer.from(source, 'utf-8').buffer);
    const out: cryptoFramework.DataBlob = await cipher.doFinal({ data: input });
    const result: string = RsaEncryptor.base64.encodeToStringSync(out.data);
    Logger.debug(TAG, `rsa encrypt ${source.length} charset -> ${result.length} b64`);
    return result;
  }
}
