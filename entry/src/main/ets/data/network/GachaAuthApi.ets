/**
 * GachaAuthApi.ets
 * genAuthKey（DS Gen1/K2 + SToken Cookie）+ authkey 信息解析 + 手动 URL 兜底解析。
 */
import { ApiResponse } from '../../model/ApiResponse';
import { HoyolabClient } from './HoyolabClient';
import { AppConstants } from '../../common/Constants';

export class GachaAuthInfo {
  authkey: string = '';
  authkeyVer: string = '1';
  signType: string = '2';
  lang: string = 'zh-cn';
}

export class GachaAuthApi {
  /** 通过 SToken 自动生成 authkey */
  static async genAuthKey(uid: string, region: string, cookie: string): Promise<ApiResponse> {
    const body: Record<string, string> = {
      'auth_appid': AppConstants.GACHA_AUTH_APPID,
      'game_biz': AppConstants.GAME_BIZ,
      'game_uid': uid,
      'region': region,
    };
    return HoyolabClient.genAuthKey(JSON.stringify(body), cookie);
  }

  /** 从 genAuthKey 响应 data 解析 authkey 信息 */
  static parseAuthInfo(data: Object): GachaAuthInfo {
    const info: GachaAuthInfo = new GachaAuthInfo();
    const obj = data as Record<string, Object>;
    info.authkey = String(obj['authkey'] ?? '');
    info.authkeyVer = String(obj['authkey_ver'] ?? '1');
    info.signType = String(obj['sign_type'] ?? '2');
    return info;
  }

  /** 校验手动 URL 是否本应用祈愿接口并提取 query 参数 */
  static parseUrlToQuery(url: string): Record<string, string> {
    const map: Record<string, string> = {};
    let u: string = url.trim();
    // 去除尾部 #/log 等锚点
    const hashIdx: number = u.indexOf('#');
    if (hashIdx >= 0) {
      u = u.substring(0, hashIdx);
    }
    const qIdx: number = u.indexOf('?');
    if (qIdx < 0) {
      return map;
    }
    const queryPart: string = u.substring(qIdx + 1);
    const segs: string[] = queryPart.split('&');
    for (let i = 0; i < segs.length; i++) {
      const seg: string = segs[i];
      const eq: number = seg.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key: string = seg.substring(0, eq);
      let val: string = seg.substring(eq + 1);
      try {
        val = decodeURIComponent(val);
      } catch (e) {
        // 保留原文
      }
      map[key] = val;
    }
    return map;
  }

  /** 从 URL 提取手动导入所需的 GachaAuthInfo（authkey 必须存在） */
  static parseAuthFromUrl(url: string): GachaAuthInfo | undefined {
    const q: Record<string, string> = GachaAuthApi.parseUrlToQuery(url);
    const authkey: string = q['authkey'] ?? '';
    if (authkey.length === 0) {
      return undefined;
    }
    const info: GachaAuthInfo = new GachaAuthInfo();
    info.authkey = authkey;
    info.authkeyVer = q['authkey_ver'] ?? '1';
    info.signType = q['sign_type'] ?? '2';
    info.lang = q['lang'] ?? 'zh-cn';
    return info;
  }
}
