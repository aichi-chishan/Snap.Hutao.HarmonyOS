/**
 * PassportClient.ets
 * 米哈游 passport 账号系客户端（仅国服）：扫码登录 + 手机验证码登录。
 * - 扫码登录：createQRLogin / queryQRLoginStatus（HoyoPlay 协议，无 DS）
 * - 手机验证码：createLoginCaptcha / loginByMobileCaptcha（DS Gen2/PROD）
 */
import { http } from '@kit.NetworkKit';
import { AppConstants } from '../../common/Constants';
import { DsSigner } from './DsSigner';
import { ApiResponse } from '../../model/ApiResponse';
import { RsaEncryptor } from './RsaEncryptor';
import { Logger } from '../../common/Logger';

const TAG: string = 'PassportClient';

/** 扫码登录二维码数据 */
export class QrLogin {
  url: string = '';
  ticket: string = '';
}

/** 扫码登录轮询结果 */
export class QrLoginResult {
  status: string = '';
  tokens: TokenInfo[] = [];
  userInfo: QrUserInfo = new QrUserInfo();
}

/** QR 结果中的 token 条目 */
export class TokenInfo {
  tokenType: number = 0;
  token: string = '';
}

/** QR 结果中的用户信息（aid/mid） */
export class QrUserInfo {
  aid: string = '';
  mid: string = '';
  accountName: string = '';
}

/** 手机验证码发送结果 */
export class MobileCaptcha {
  sentNew: boolean = false;
  countdown: number = 0;
  actionType: string = '';
}

/** 验证码登录结果 */
export class LoginResult {
  tokenType: number = 0;
  token: string = '';
  aid: string = '';
  mid: string = '';
  accountName: string = '';
}

/** 登录链路解析的最终账号摘要 */
export class LoginSession {
  /** stuid（= aid） */
  stuid: string = '';
  /** stoken */
  stoken: string = '';
  mid: string = '';
  accountName: string = '';
}

export class PassportClient {
  /** 进程级固定 device_id（53 位小写字母+数字），扫码 create/query 必须一致，否则无法匹配会话 */
  private static deviceId53: string = PassportClient.randomDeviceId53();

  /** 生成 53 位小写字母+数字随机串（DeviceId53，HoyoPlay 用） */
  static randomDeviceId53(): string {
    const chars: string = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let result: string = '';
    for (let i = 0; i < 53; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  /** 统一 HYP 协议请求头（扫码登录用）—— device_id 必须在两次调用间保持一致 */
  private static hypHeaders(): Record<string, string> {
    return {
      'User-Agent': AppConstants.HYP_USER_AGENT,
      'Accept': 'application/json',
      'x-rpc-app_id': AppConstants.HYP_APP_ID,
      'x-rpc-client_type': AppConstants.HYP_CLIENT_TYPE,
      'x-rpc-device_id': PassportClient.deviceId53,
    };
  }

  /** 统一 BBS 账号系请求头（验证码登录用，DS 由调用方附加） */
  private static bbsHeaders(): Record<string, string> {
    return {
      'User-Agent': AppConstants.UA_MOBILE,
      'Accept': 'application/json',
      'x-rpc-app_id': AppConstants.BBS_APP_ID,
      'x-rpc-app_version': AppConstants.APP_VERSION,
      'x-rpc-client_type': AppConstants.X_RPC_CLIENT_TYPE,
      'x-rpc-device_id': `00000000-0000-0000-0000-${PassportClient.randomDeviceId53().substring(0, 12)}`,
      'x-rpc-game_biz': 'bbs_cn',
      'x-rpc-sdk_version': '2.16.0',
    };
  }

  // ================= 扫码登录 =================

  /** 创建登录二维码，返回 {url, ticket} */
  static async createQrLogin(): Promise<QrLogin> {
    const resp: ApiResponse = await PassportClient.postJsonRaw(
      AppConstants.URL_CREATE_QR_LOGIN, '{}', PassportClient.hypHeaders());
    if (!resp.success || resp.data === undefined) {
      throw new Error(`创建二维码失败：${resp.userFriendlyMessage()}`);
    }
    const data = resp.data as Record<string, Object>;
    const login: QrLogin = new QrLogin();
    login.url = String(data['url'] ?? '');
    login.ticket = String(data['ticket'] ?? '');
    if (login.url.length === 0 || login.ticket.length === 0) {
      throw new Error('创建二维码失败：返回数据不完整');
    }
    Logger.info(TAG, 'createQrLogin ok');
    return login;
  }

  /** 查询二维码登录状态，返回扫描确认后的登录摘要；未完成则抛出特定异常交由调用方轮询 */
  static async queryQrLoginStatus(ticket: string): Promise<QrLoginResult> {
    const bodyJson: string = JSON.stringify({ 'ticket': ticket });
    const resp: ApiResponse = await PassportClient.postJsonRaw(
      AppConstants.URL_QUERY_QR_STATUS, bodyJson, PassportClient.hypHeaders());
    if (!resp.success || resp.data === undefined) {
      throw new Error(`查询二维码状态失败：${resp.userFriendlyMessage()}`);
    }
    const data = resp.data as Record<string, Object>;
    const result: QrLoginResult = new QrLoginResult();
    result.status = String(data['status'] ?? '');
    const tokensArr = data['tokens'] as Array<Object>;
    if (tokensArr !== undefined && tokensArr !== null) {
      for (let i = 0; i < tokensArr.length; i++) {
        const item = tokensArr[i] as Record<string, Object>;
        const tokenInfo: TokenInfo = new TokenInfo();
        tokenInfo.tokenType = Number(item['token_type'] ?? 0);
        tokenInfo.token = String(item['token'] ?? '');
        result.tokens.push(tokenInfo);
      }
    }
    const info = data['user_info'] as Record<string, Object>;
    if (info !== undefined && info !== null) {
      result.userInfo.aid = String(info['aid'] ?? '');
      result.userInfo.mid = String(info['mid'] ?? '');
      result.userInfo.accountName = String(info['account_name'] ?? '');
    }
    Logger.info(TAG, `queryQrLoginStatus status=${result.status} tokens=${result.tokens.length}`);
    return result;
  }

  /** 从扫码结果提取登录会话（token_type==1 即 stoken） */
  static extractQrSession(result: QrLoginResult): LoginSession {
    const session: LoginSession = new LoginSession();
    session.stuid = result.userInfo.aid;
    session.mid = result.userInfo.mid;
    session.accountName = result.userInfo.accountName;
    for (let i = 0; i < result.tokens.length; i++) {
      const t: TokenInfo = result.tokens[i];
      if (t.tokenType === 1) {
        session.stoken = t.token;
        break;
      }
    }
    return session;
  }

  // ================= 手机验证码登录 =================

  /** 发送手机验证码；populate Aigis 需要极验时返回 true（目前仅提示） */
  static async createLoginCaptcha(mobile: string): Promise<MobileCaptcha> {
    const encMobile: string = await RsaEncryptor.encrypt(mobile);
    const encArea: string = await RsaEncryptor.encrypt('+86');
    const body: Record<string, string> = { 'area_code': encArea, 'mobile': encMobile };
    const bodyJson: string = JSON.stringify(body);
    const headers: Record<string, string> = await PassportClient.dsHeader(bodyJson);
    const resp: ApiResponse = await PassportClient.postJsonRaw(
      AppConstants.URL_CREATE_LOGIN_CAPTCHA, bodyJson, PassportClient.mergeBbs(headers));
    if (!resp.success || resp.data === undefined) {
      throw new Error(`发送验证码失败：${resp.userFriendlyMessage()}`);
    }
    const data = resp.data as Record<string, Object>;
    const captcha: MobileCaptcha = new MobileCaptcha();
    captcha.sentNew = Boolean(data['sent_new'] ?? false);
    captcha.countdown = Number(data['countdown'] ?? 0);
    captcha.actionType = String(data['action_type'] ?? '');
    Logger.info(TAG, `createLoginCaptcha sentNew=${captcha.sentNew} cd=${captcha.countdown}`);
    return captcha;
  }

  /** 使用手机验证码登录，返回登录会话 */
  static async loginByMobileCaptcha(mobile: string, captcha: string, actionType: string): Promise<LoginSession> {
    const encMobile: string = await RsaEncryptor.encrypt(mobile);
    const encArea: string = await RsaEncryptor.encrypt('+86');
    const body: Record<string, string> = {
      'area_code': encArea,
      'action_type': actionType,
      'captcha': captcha,
      'mobile': encMobile,
    };
    const bodyJson: string = JSON.stringify(body);
    const headers: Record<string, string> = await PassportClient.dsHeader(bodyJson);
    const resp: ApiResponse = await PassportClient.postJsonRaw(
      AppConstants.URL_LOGIN_BY_MOBILE_CAPTCHA, bodyJson, PassportClient.mergeBbs(headers));
    if (!resp.success || resp.data === undefined) {
      throw new Error(`登录失败：${resp.userFriendlyMessage()}`);
    }
    const data = resp.data as Record<string, Object>;
    const session: LoginSession = new LoginSession();
    const token = data['token'] as Record<string, Object>;
    if (token !== undefined && token !== null) {
      session.stoken = String(token['token'] ?? '');
    }
    const info = data['user_info'] as Record<string, Object>;
    if (info !== undefined && info !== null) {
      session.stuid = String(info['aid'] ?? '');
      session.mid = String(info['mid'] ?? '');
      session.accountName = String(info['account_name'] ?? '');
    }
    Logger.info(TAG, `loginByMobileCaptcha ok stuid=${session.stuid} hasStoken=${session.stoken.length > 0}`);
    return session;
  }

  // ================= 内部封装 =================

  /** DS Gen2/PROD 请求头（对齐 Windows LoginByMobileCaptchaAsync SignDataAsync(Gen2, PROD, true)：
   *  includeChars=true → r 为 6 位字母+数字；body 参与签名，query 为空） */
  private static async dsHeader(bodyJson: string): Promise<Record<string, string>> {
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomLowerAlphaNumeric();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_PROD, t, r, bodyJson, '');
    return { 'DS': ds };
  }

  /** BBS 头 + DS 合并 */
  private static mergeBbs(dsHeaders: Record<string, string>): Record<string, string> {
    const merged: Record<string, string> = PassportClient.bbsHeaders();
    for (const k of Object.keys(dsHeaders)) {
      merged[k] = dsHeaders[k];
    }
    return merged;
  }

  /** 发送 POST JSON 并解析统一响应 */
  private static async postJsonRaw(url: string, bodyJson: string, headers: Record<string, string>): Promise<ApiResponse> {
    const fullHeaders: Record<string, string> = { 'Content-Type': 'application/json' };
    for (const k of Object.keys(headers)) {
      fullHeaders[k] = headers[k];
    }
    const httpRequest = http.createHttp();
    try {
      const resp = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: fullHeaders,
        extraData: bodyJson,
        connectTimeout: AppConstants.NETWORK_TIMEOUT_MS,
        readTimeout: AppConstants.NETWORK_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
      });
      if (resp.responseCode === http.ResponseCode.OK) {
        return ApiResponse.fromJson(resp.result as string);
      }
      Logger.warn(TAG, `http code=${resp.responseCode} url=${url}`);
      return ApiResponse.fail(Number(resp.responseCode), `HTTP ${resp.responseCode}`);
    } catch (e) {
      const err = e as BusinessError;
      Logger.warn(TAG, `request error url=${url} code=${err.code} msg=${err.message}`);
      return ApiResponse.fail(-2, `网络异常：${err.message}`);
    } finally {
      httpRequest.destroy();
    }
  }
}
