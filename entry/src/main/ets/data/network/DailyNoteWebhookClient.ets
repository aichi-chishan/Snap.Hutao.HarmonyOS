import { http } from '@kit.NetworkKit';

/** 用户明确配置的便笺转发地址。独立请求不附加账号 Cookie、DS 或设备身份。 */
export class DailyNoteWebhookClient {
  static async send(target: string, uid: string, payload: string): Promise<void> {
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = { 'Content-Type': 'application/json', 'x-uid': uid };
      const response = await request.request(target, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: payload,
        connectTimeout: 10000,
        readTimeout: 10000,
        maxRedirects: 0,
        usingCache: false,
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`Webhook HTTP ${response.responseCode}`);
      }
    } finally {
      request.destroy();
    }
  }
}
