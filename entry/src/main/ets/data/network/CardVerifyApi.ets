/**
 * CardVerifyApi.ets
 * 风控验证（1034）流程用 API：createVerification → 极验 → verifyVerification → 拿 challenge 重放。
 * 参考 Snap Hutao CardClient（国服，DS Gen2/X4）。
 */
import { ApiClient } from './ApiClient';
import { ApiResponse } from '../../model/ApiResponse';
import { AppConstants } from '../../common/Constants';
import { DsSigner } from './DsSigner';
import { Logger } from '../../common/Logger';

const TAG: string = 'CardVerifyApi';
const HOST: string = 'https://api-takumi-record.mihoyo.com/game_record/app/card/wapi';
/** 便笺接口的 challenge_path */
export const DAILY_NOTE_PATH: string =
  'https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/dailyNote';

/** 极验注册结果 */
export class GtChallenge {
  gt: string = '';
  challenge: string = '';
  success: number = 0;
}

/** 极验完成结果（Web 回传） */
export class GeetestValidate {
  geetestChallenge: string = '';
  geetestValidate: string = '';
  geetestSeccode: string = '';
}

export class CardVerifyApi {
  /** 注册极验：GET createVerification?is_high=true */
  static async createVerification(cookie: string, path: string): Promise<GtChallenge> {
    const query: Record<string, string> = { 'is_high': 'true' };
    const sorted: string = DsSigner.sortQuery(query);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, '', sorted);
    const url: string = `${HOST}/createVerification?${sorted}`;
    const headers: Record<string, string> = {
      'DS': ds,
      'Cookie': cookie,
      'x-rpc-challenge_game': '2',
      'x-rpc-challenge_path': path,
      'x-rpc-app_version': AppConstants.APP_VERSION,
      'x-rpc-client_type': AppConstants.X_RPC_CLIENT_TYPE,
      'User-Agent': AppConstants.UA_MOBILE,
      'Referer': 'https://webstatic.mihoyo.com/',
    };
    const resp: ApiResponse = await ApiClient.getInstance().get(url, headers);
    const result: GtChallenge = new GtChallenge();
    if (!resp.success || resp.data === undefined) {
      Logger.warn(TAG, `createVerification fail retcode=${resp.retcode} msg=${resp.message}`);
      result.success = resp.retcode;
      return result;
    }
    const data = resp.data as Record<string, Object>;
    result.gt = String(data['gt'] ?? '');
    result.challenge = String(data['challenge'] ?? '');
    result.success = 1;
    Logger.info(TAG, 'createVerification ok');
    return result;
  }

  /** 提交极验结果换取 challenge：POST verifyVerification */
  static async verifyVerification(cookie: string, validate: GeetestValidate): Promise<string> {
    const body: Record<string, string> = {
      'geetest_challenge': validate.geetestChallenge,
      'geetest_validate': validate.geetestValidate,
      'geetest_seccode': validate.geetestSeccode,
    };
    const bodyJson: string = JSON.stringify(body);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, bodyJson, '');
    const url: string = `${HOST}/verifyVerification`;
    const headers: Record<string, string> = {
      'DS': ds,
      'Cookie': cookie,
      'Content-Type': 'application/json',
      'x-rpc-app_version': AppConstants.APP_VERSION,
      'x-rpc-client_type': AppConstants.X_RPC_CLIENT_TYPE,
      'User-Agent': AppConstants.UA_MOBILE,
      'Referer': 'https://webstatic.mihoyo.com/',
    };
    const resp: ApiResponse = await ApiClient.getInstance().postJson(url, bodyJson, headers);
    if (!resp.success || resp.data === undefined) {
      Logger.warn(TAG, `verifyVerification fail retcode=${resp.retcode} msg=${resp.message}`);
      return '';
    }
    const data = resp.data as Record<string, Object>;
    const challenge: string = String(data['challenge'] ?? '');
    Logger.info(TAG, `verifyVerification ok challenge len=${challenge.length}`);
    return challenge;
  }
}
