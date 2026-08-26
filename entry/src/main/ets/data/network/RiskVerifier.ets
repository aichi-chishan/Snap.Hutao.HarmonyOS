/**
 * RiskVerifier.ets
 * 统一风控处理（对齐 Windows RetryIf1034Async 链路）：
 *   1034 → createVerification（challenge_game=2 + 具体接口 path）
 *        → 抛 RiskControlError（页面捕获后跳极验页）
 *        → 极验通过 → verifyVerification 换 challenge → 写入 pendingRiskChallenge
 *        → 来源页重放（x-rpc-challenge）。
 */
import { ApiResponse } from '../../model/ApiResponse';
import { ApiClient } from './ApiClient';
import { AppConstants } from '../../common/Constants';
import { DsSigner } from './DsSigner';
import { Logger } from '../../common/Logger';

const TAG: string = 'RiskVerifier';

/** createVerification 结果 */
export class GtChallengeData {
  gt: string = '';
  challenge: string = '';
}

/** verifyVerification 入参（极验页回传） */
export class GeetestValidateInput {
  geetestChallenge: string = '';
  geetestValidate: string = '';
  geetestSeccode: string = '';
}

/** 风控需人机验证的异常（页面捕获后路由至 GeetestVerifyPage） */
export class RiskControlError extends Error {
  /** 极验 gt */
  gt: string = '';
  /** 极验 challenge（初始） */
  challenge: string = '';
  /** 触发风控的接口 path（createVerification 用） */
  path: string = '';

  constructor(gt: string, challenge: string, path: string) {
    super('当前操作触发了风控，需要完成人机验证');
    this.name = 'RiskControlError';
    this.gt = gt;
    this.challenge = challenge;
    this.path = path;
  }
}

export class RiskVerifier {
  /** 默认重放键（GeetestVerifyPage 完成时写入） */
  static readonly KEY_PENDING: string = 'pendingRiskChallenge';

  /** 执行请求；若 1034 则注册极验并抛 RiskControlError。 */
  static async checkForRisk(resp: ApiResponse, cookie: string, path: string): Promise<boolean> {
    if (!resp.isRiskControl()) {
      return false;
    }
    const gtChallenge: GtChallengeData = await RiskVerifier.createVerification(cookie, path);
    if (gtChallenge.gt.length > 0 && gtChallenge.challenge.length > 0) {
      throw new RiskControlError(gtChallenge.gt, gtChallenge.challenge, path);
    }
    Logger.warn(TAG, `risk control but createVerification failed retcode=${resp.retcode}`);
    throw new Error('被风控拦截，且未能发起人机验证，请稍后再试');
  }

  /** 注册极验（createVerification?is_high=true，头带 challenge_game/path） */
  static async createVerification(cookie: string, path: string): Promise<GtChallengeData> {
    const query: Record<string, string> = { 'is_high': 'true' };
    const sorted: string = DsSigner.sortQuery(query);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, '', sorted);
    const url: string = `https://api-takumi-record.mihoyo.com/game_record/app/card/wapi/createVerification?${sorted}`;
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
    const result: GtChallengeData = new GtChallengeData();
    if (!resp.success || resp.data === undefined) {
      Logger.warn(TAG, `createVerification fail retcode=${resp.retcode} msg=${resp.message}`);
      return result;
    }
    const data = resp.data as Record<string, Object>;
    result.gt = String(data['gt'] ?? '');
    result.challenge = String(data['challenge'] ?? '');
    Logger.info(TAG, `createVerification ok gt=${result.gt.length > 0}`);
    return result;
  }

  /** 极验通过后换 x-rpc-challenge（POST verifyVerification） */
  static async verifyXrpcChallenge(cookie: string, gv: GeetestValidateInput): Promise<string> {
    const body: Record<string, string> = {
      'geetest_challenge': gv.geetestChallenge,
      'geetest_validate': gv.geetestValidate,
      'geetest_seccode': gv.geetestSeccode,
    };
    const bodyJson: string = JSON.stringify(body);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, bodyJson, '');
    const url: string = 'https://api-takumi-record.mihoyo.com/game_record/app/card/wapi/verifyVerification';
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
