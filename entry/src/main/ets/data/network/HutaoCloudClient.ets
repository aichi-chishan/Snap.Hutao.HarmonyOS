import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { PreferencesStore } from '../prefs/PreferencesStore';
import { HutaoCloudJson } from '../../model/HutaoCloud';

// Public key from upstream Web/Hutao/HutaoPassportClient.cs, converted PKCS#1 -> SPKI.
const CLOUD_PUBLIC_KEY: string = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtjUS4JLsfCVbueTReY1E/kFBzoCQZtbSGW/BatU9BaZbgd1iIHKbCQhs0Uf3POcavhqW2/UVTxBlhi3cfzRVBbd61FZk0Xt5EI+8SvGxVR176yobMvZt7JcpommpY4RvfItiiag5GplLS9jrkOPlKsQiIAZaawgxL1HVpf6cPkHzfZCuzlDOagntlYgP8wkZI+K6E63AHFRgfU7n0YO9jUPhSDPRXvGo5n/5B19L+fiPYbf++e8zywZVtoJ5ztJ/+6Vp+N7H/C5PEJGy9ZKHWSvTvCs8Curg2ahB8xD1aPd1XEOmkMBfDVuD0wOHnn7I03seIOU7l0w8ojP3E+eG3QIDAQAB';

export class HutaoCloudClient {
  static readonly ROOT: string = 'https://homa.snaphutaorp.org';

  static deviceId(): string {
    let id: string = PreferencesStore.getString('hutao_cloud_device_id', '');
    if (id.length === 0) {
      id = util.generateRandomUUID(true);
      PreferencesStore.setString('hutao_cloud_device_id', id);
    }
    return id;
  }

  static async encrypt(value: string): Promise<string> {
    const input: Uint8Array = new util.TextEncoder().encodeInto(value);
    if (input.length > 214) { throw new Error('输入超出通行证加密协议的长度限制'); }
    const base64: util.Base64Helper = new util.Base64Helper();
    const generator: cryptoFramework.AsyKeyGenerator = cryptoFramework.createAsyKeyGenerator('RSA2048');
    const keyPair: cryptoFramework.KeyPair = await generator.convertKey({ data: base64.decodeSync(CLOUD_PUBLIC_KEY) }, null);
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('RSA2048|PKCS1_OAEP|SHA1|MGF1_SHA1');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, keyPair.pubKey, null);
    const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: input });
    return base64.encodeToStringSync(output.data);
  }

  /** No Cookie jar, no redirects, no automatic endpoint fallback, no credential logging. */
  static async request(path: string, body: string = '', accessToken: string = ''): Promise<Object> {
    return HutaoCloudClient.exchange(path, body, accessToken, false);
  }

  /** Verified public challenge routes use no Bearer token; retain the server receipt envelope. */
  static async uploadChallenge(path: string, body: string): Promise<Object> {
    if ((path !== '/Record/Upload' && path !== '/RoleCombat/Upload') || body.length === 0) {
      throw new Error('无效的挑战上传接口');
    }
    return HutaoCloudClient.exchange(path, body, '', true);
  }

  private static async exchange(path: string, body: string, accessToken: string, receipt: boolean): Promise<Object> {
    if (!path.startsWith('/') || path.startsWith('//') || path.indexOf('://') >= 0) {
      throw new Error('无效的胡桃云接口');
    }
    const headers: Record<string, string> = {
      'Accept': 'application/json', 'Content-Type': 'application/json',
      'User-Agent': 'Snap.Hutao.HarmonyOS/1.0',
      'x-hutao-device-id': HutaoCloudClient.deviceId(),
      'x-hutao-device-os': 'HarmonyOS API24+',
      'x-hutao-device-name': 'HarmonyOS',
    };
    if (accessToken.length > 0) { headers['Authorization'] = `Bearer ${accessToken}`; }
    const client: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(HutaoCloudClient.ROOT + path, {
        method: body.length > 0 ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: headers, extraData: body, expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000, readTimeout: 30000, usingCache: false, maxRedirects: 0,
        maxLimit: 20 * 1024 * 1024,
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`胡桃云 HTTP ${response.responseCode}，请检查服务状态或重新登录`);
      }
      const root: Record<string, Object> = JSON.parse(HutaoCloudJson.preserveIds(String(response.result))) as Record<string, Object>;
      if (receipt && (root === null || typeof root !== 'object' || Array.isArray(root) || typeof root['retcode'] !== 'number')) {
        throw new Error('胡桃云未返回有效提交结果，请核实后重新预览');
      }
      if (Number(root['retcode'] ?? -1) !== 0) {
        throw new Error(`胡桃云 ${String(root['retcode'] ?? '-1')}：${String(root['message'] ?? '请求失败').substring(0, 240)}`);
      }
      if (receipt) { return root; }
      const empty: Record<string, Object> = {};
      return root['data'] ?? empty;
    } finally {
      client.destroy();
    }
  }
}
