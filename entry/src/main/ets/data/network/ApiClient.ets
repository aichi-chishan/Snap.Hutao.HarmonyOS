/**
 * ApiClient.ets
 * @ohos.net.http 统一封装：GET/POST/JSON header/超时/Cookie 注入/retcode 解析/错误归一化。
 */
import { http } from '@kit.NetworkKit';
import { ApiResponse } from '../../model/ApiResponse';
import { AppConstants } from '../../common/Constants';
import { Logger } from '../../common/Logger';

const TAG: string = 'ApiClient';

export class ApiClient {
  /** 当前注入的 Cookie（会话级，随账号切换更新） */
  private static currentCookie: string = '';
  private static instance: ApiClient = new ApiClient();

  static getInstance(): ApiClient {
    return ApiClient.instance;
  }

  /** 设置请求默认注入的 Cookie */
  setCookie(cookie: string): void {
    ApiClient.currentCookie = cookie;
  }

  getCurrentCookie(): string {
    return ApiClient.currentCookie;
  }

  /** 若调用方未显式给出 Cookie，则注入当前 Cookie */
  private mergeCookie(headers: Record<string, string>): Record<string, string> {
    const merged: Record<string, string> = { 'User-Agent': AppConstants.UA_MOBILE };
    for (const k of Object.keys(headers)) {
      merged[k] = headers[k];
    }
    if (headers['Cookie'] === undefined && ApiClient.currentCookie.length > 0) {
      merged['Cookie'] = ApiClient.currentCookie;
    }
    return merged;
  }

  /** GET 请求 */
  async get(url: string, headers: Record<string, string>): Promise<ApiResponse> {
    return this.request(url, http.RequestMethod.GET, headers, '');
  }

  /** POST JSON 请求 */
  async postJson(url: string, bodyJson: string, headers: Record<string, string>): Promise<ApiResponse> {
    const fullHeaders: Record<string, string> = { 'Content-Type': 'application/json' };
    for (const k of Object.keys(headers)) {
      fullHeaders[k] = headers[k];
    }
    return this.request(url, http.RequestMethod.POST, fullHeaders, bodyJson);
  }

  /** 归一化响应头为 Record<string,string>（键保持原大小写；同名头取首个） */
  static normalizeHeaders(raw: Object | undefined): Record<string, string> {
    const out: Record<string, string> = {};
    if (raw === undefined || raw === null) {
      return out;
    }
    const obj = raw as Record<string, Object>;
    for (const k of Object.keys(obj)) {
      const v: Object = obj[k];
      if (typeof v === 'string') {
        out[k] = v as string;
      } else if (Array.isArray(v)) {
        const arr: Array<Object> = v as Array<Object>;
        if (arr.length > 0) {
          out[k] = String(arr[0]);
        }
      } else if (v !== undefined && v !== null) {
        out[k] = String(v);
      }
    }
    return out;
  }

  private async request(url: string, method: http.RequestMethod,
    headers: Record<string, string>, bodyJson: string): Promise<ApiResponse> {
    const merged: Record<string, string> = this.mergeCookie(headers);
    const httpRequest = http.createHttp();
    try {
      const resp = await httpRequest.request(url, {
        method: method,
        header: merged,
        extraData: bodyJson,
        connectTimeout: AppConstants.NETWORK_TIMEOUT_MS,
        readTimeout: AppConstants.NETWORK_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      });
      if (resp.responseCode === http.ResponseCode.OK) {
        const result: string = resp.result as string;
        const parsed: ApiResponse = ApiResponse.fromJson(result);
        parsed.respHeaders = ApiClient.normalizeHeaders(resp.header);
        if (!parsed.success && parsed.retcode !== 0) {
          Logger.warn(TAG, `resp fail url=${url} retcode=${parsed.retcode} msg=${parsed.message}`);
        }
        return parsed;
      }
      const failResp: ApiResponse = ApiResponse.fail(Number(resp.responseCode), `HTTP ${resp.responseCode}`);
      failResp.respHeaders = ApiClient.normalizeHeaders(resp.header);
      return failResp;
    } catch (e) {
      const err = e as BusinessError;
      Logger.warn(TAG, `request error url=${url} code=${err.code} msg=${err.message}`);
      return ApiResponse.fail(-2, `网络异常：${err.message}`);
    } finally {
      httpRequest.destroy();
    }
  }
}
