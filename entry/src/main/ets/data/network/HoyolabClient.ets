/**
 * HoyolabClient.ets
 * �?host 注入 x-rpc �?UA/Cookie，封装各端点：dailyNote / act_calendar / luna sign / genAuthKey / getActionTicket / getUserGameRoles�? */
import { ApiClient } from './ApiClient';
import { ApiResponse } from '../../model/ApiResponse';
import { AppConstants } from '../../common/Constants';
import { DsSigner } from './DsSigner';
import { PreferencesStore } from '../prefs/PreferencesStore';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Logger } from '../../common/Logger';

const TAG: string = 'HoyolabClient';

export class HoyolabClient {
  private static client: ApiClient = ApiClient.getInstance();

  /** 通用 x-rpc + UA + device_fp（真实设备指纹，降风控；未获取到时不带该头） */
  private static baseHeaders(): Record<string, string> {
    const deviceId: string = PreferencesStore.getDeviceId();
    const fp: string = PreferencesStore.getDeviceFp();
    const headers: Record<string, string> = {
      'x-rpc-app_version': AppConstants.APP_VERSION,
      'x-rpc-client_type': AppConstants.GAMERECORD_CLIENT_TYPE,
      'x-rpc-device_id': deviceId,
      'x-rpc-language': AppConstants.X_RPC_LANGUAGE,
      'User-Agent': AppConstants.UA_GAMERECORD,
      'Accept': 'application/json',
      'Referer': 'https://webstatic.mihoyo.com/',
    };
    if (fp.length > 0) {
      headers['x-rpc-device_fp'] = fp;
    }
    return headers;
  }

  /** 公开访问：通用 x-rpc 头（供其他 Service/页面构建请求复用） */
  static getBaseHeaders(): Record<string, string> {
    return HoyolabClient.baseHeaders();
  }

  /** passport 系接口完整头（对齐参考项目 XRpc2 Configuration），供 Token 交换/登录类接口使用 */
  static passportHeaders(): Record<string, string> {
    const deviceId: string = PreferencesStore.getDeviceId();
    const fp: string = PreferencesStore.getDeviceFp();
    const deviceName: string = HoyolabClient.bbsDeviceName();
    const headers: Record<string, string> = {
      'User-Agent': AppConstants.UA_BBS,
      'Accept': 'application/json',
      'x-rpc-aigis': '',
      'x-rpc-app_id': AppConstants.PASSPORT_APP_ID,
      'x-rpc-app_version': AppConstants.APP_VERSION,
      'x-rpc-client_type': AppConstants.PASSPORT_CLIENT_TYPE,
      'x-rpc-device_id': deviceId,
      'x-rpc-device_name': deviceName,
      'x-rpc-game_biz': AppConstants.PASSPORT_GAME_BIZ,
      'x-rpc-sdk_version': AppConstants.PASSPORT_SDK_VERSION,
    };
    if (fp.length > 0) {
      headers['x-rpc-device_fp'] = fp;
    }
    return headers;
  }

  /** 读取当前设备名（如 MatePad Pro 11），用于 x-rpc-device_name 上报 */
  private static bbsDeviceName(): string {
    try {
      const name: string = deviceInfo.marketName;
      return name.length > 0 ? name : 'Huawei';
    } catch (e) {
      return 'Huawei';
    }
  }

  /**
   * 实时便笺 dailyNote（GET，GameRecord）。DS Gen2/X4；Cookie: account_id/cookie_token。
   * @param extraHeaders 可选重放头（如 x-rpc-challenge，风控验证后使用）
   */
  static async fetchDailyNote(uid: string, region: string, cookie: string,
    extraHeaders: Record<string, string>): Promise<ApiResponse> {
    const query: Record<string, string> = { 'role_id': uid, 'server': region };
    const sorted: string = DsSigner.sortQuery(query);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, '', sorted);
    const url: string = `https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/dailyNote?${sorted}`;
    const headers: Record<string, string> = {
      'DS': ds,
      'Cookie': cookie,
      'x-rpc-tool_verison': 'v5.0.1-ys',
    };
    const mergedExtra: Record<string, string> = HoyolabClient.merge(headers, extraHeaders);
    Logger.info(TAG, `fetchDailyNote uid=${uid} challenge=${extraHeaders['x-rpc-challenge'] ?? ''}`);
    return HoyolabClient.client.get(url, HoyolabClient.merge(HoyolabClient.baseHeaders(), mergedExtra));
  }

  /** 活动日历 act_calendar（POST，GameRecord，body=role_id/server）。DS Gen2/X4 */
  static async fetchActCalendar(uid: string, region: string, cookie: string): Promise<ApiResponse> {
    const body: Record<string, string> = { 'role_id': uid, 'server': region };
    const bodyJson: string = JSON.stringify(body);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, bodyJson, '');
    const url: string = 'https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/act_calendar';
    const headers: Record<string, string> = { 'DS': ds, 'Cookie': cookie };
    return HoyolabClient.client.postJson(url, bodyJson, HoyolabClient.merge(HoyolabClient.baseHeaders(), headers));
  }

  /** 每日签到 sign（POST Luna）。DS Gen1/LK2；body 含 act_id/region/uid。
   *  @param extraHeaders 可选重放头（体内极验通过后的 x-rpc-challenge/validate/seccode） */
  static async signIn(uid: string, region: string, cookie: string,
    extraHeaders?: Record<string, string>): Promise<ApiResponse> {
    const body: Record<string, string> = { 'act_id': AppConstants.SIGN_ACT_ID, 'region': region, 'uid': uid };
    const bodyJson: string = JSON.stringify(body);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen1(AppConstants.DS_SALT_LK2, t, r);
    const url: string = 'https://api-takumi.mihoyo.com/event/luna/sign';
    const headers: Record<string, string> = { 'DS': ds, 'Cookie': cookie, 'x-rpc-signgame': 'hk4e' };
    const mergedExtra: Record<string, string> = extraHeaders ?? {};
    Logger.info(TAG, `signIn uid=${uid} region=${region} challenge=${mergedExtra['x-rpc-challenge'] ?? ''}`);
    return HoyolabClient.client.postJson(url, bodyJson, HoyolabClient.merge(HoyolabClient.baseHeaders(),
      HoyolabClient.merge(headers, mergedExtra)));
  }

  /** 签到活动信息 info（GET Luna：is_sign/total_sign_day）。DS Gen1/LK2 + x-rpc-signgame */
  static async fetchSignInfo(uid: string, region: string, cookie: string): Promise<ApiResponse> {
    const query: Record<string, string> = {
      'lang': AppConstants.X_RPC_LANGUAGE,
      'act_id': AppConstants.SIGN_ACT_ID,
      'uid': uid,
      'region': region,
    };
    const sorted: string = DsSigner.sortQuery(query);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen1(AppConstants.DS_SALT_LK2, t, r);
    const url: string = `https://api-takumi.mihoyo.com/event/luna/info?${sorted}`;
    const headers: Record<string, string> = { 'DS': ds, 'Cookie': cookie, 'x-rpc-signgame': 'hk4e' };
    return HoyolabClient.client.get(url, HoyolabClient.merge(HoyolabClient.baseHeaders(), headers));
  }

  /** 签到活动奖励列表 home（GET Luna：month/awards）。无 DS，带 x-rpc-signgame */
  static async fetchSignHome(region: string, cookie: string): Promise<ApiResponse> {
    const url: string = `https://api-takumi.mihoyo.com/event/luna/home?lang=${AppConstants.X_RPC_LANGUAGE}&act_id=${AppConstants.SIGN_ACT_ID}&region=${region}`;
    const headers: Record<string, string> = { 'Cookie': cookie, 'x-rpc-signgame': 'hk4e' };
    return HoyolabClient.client.get(url, HoyolabClient.merge(HoyolabClient.baseHeaders(), headers));
  }

  /** genAuthKey（POST，DS Gen1/LK2 + SToken Cookie；对齐 Windows BindingClient2.cs:52 用 LK2 盐） */
  static async genAuthKey(bodyJson: string, cookie: string): Promise<ApiResponse> {
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen1(AppConstants.DS_SALT_LK2, t, r);
    const url: string = 'https://api-takumi.mihoyo.com/binding/api/genAuthKey';
    const headers: Record<string, string> = {
      'DS': ds,
      'Cookie': cookie,
      'x-rpc-client_type': '2',
      'x-rpc-game_biz': 'bbs_cn',
    };
    return HoyolabClient.client.postJson(url, bodyJson, HoyolabClient.merge(HoyolabClient.baseHeaders(), headers));
  }

  /** getActionTicketBySToken（GET auth/api 端点，DS Gen1/K2 + SToken Cookie）。
   *  stoken/uid 走 query（reference: ApiEndpoints.csv AuthActionTicket）
   *  参考项目 AuthClient 用 Default 配置（仅 UA + DS + Cookie），不强制带 x-rpc 头。 */
  static async getActionTicket(stokenCookie: string, stoken: string, uid: string): Promise<ApiResponse> {
    const query: Record<string, string> = {
      'action_type': 'game_role',
      'stoken': encodeURIComponent(stoken),
      'uid': uid,
    };
    const sorted: string = DsSigner.sortQuery(query);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen1(AppConstants.DS_SALT_K2, t, r);
    const url: string = `https://api-takumi.mihoyo.com/auth/api/getActionTicketBySToken?${sorted}`;
    const headers: Record<string, string> = {
      'DS': ds,
      'Cookie': stokenCookie,
      'User-Agent': AppConstants.UA_MOBILE,
    };
    return HoyolabClient.client.get(url, headers);
  }

  /** getUserGameRoles（GET 绑定角色列表，需 action_ticket）。无 DS�?*/
  static async getUserGameRoles(actionTicket: string): Promise<ApiResponse> {
    const url: string = 'https://api-takumi.mihoyo.com/binding/api/getUserGameRoles' +
      `?action_ticket=${actionTicket}&game_biz=${AppConstants.GAME_BIZ}`;
    return HoyolabClient.client.get(url, HoyolabClient.baseHeaders());
  }

  /** 合并两个 header Record */
  static merge(base: Record<string, string>, extra: Record<string, string>): Record<string, string> {
    const merged: Record<string, string> = {};
    for (const k of Object.keys(base)) {
      merged[k] = base[k];
    }
    for (const k of Object.keys(extra)) {
      merged[k] = extra[k];
    }
    return merged;
  }
}
