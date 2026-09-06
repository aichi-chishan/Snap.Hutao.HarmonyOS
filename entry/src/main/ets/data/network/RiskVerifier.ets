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
import { RiskVerifyService, GeetestSolveResult } from '../../service/RiskVerifyService';
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

  /**
   * 一站式解决 game_record 1034 风控（对齐 Windows GeetestService.TryVerifyXrpcChallengeAsync）：
   * 弹出统一验证窗 → 极验 → verifyVerification 换 challenge。
   * 成功返回新 challenge；用户关闭/失败返回 ''。
   */
  static async resolveGtChallenge(cookie: string, path: string): Promise<string> {
    RiskVerifier.currentChallengePath = path;
    const gtChallenge: GtChallengeData = await RiskVerifier.createVerification(cookie, path);
    if (gtChallenge.gt.length === 0 || gtChallenge.challenge.length === 0) {
      Logger.warn(TAG, 'resolveGtChallenge: createVerification empty');
      return '';
    }
    // verifyGtFull 先尝试自定义组合接口（成功时返回新 challenge），失败弹统一验证窗
    const solved: GeetestSolveResult = await RiskVerifyService.getInstance()
      .verifyGtFull(gtChallenge.gt, gtChallenge.challenge);
    if (solved.validate.length === 0) {
      return '';
    }
    const input: GeetestValidateInput = new GeetestValidateInput();
    input.geetestChallenge = solved.challenge;
    input.geetestValidate = solved.validate;
    input.geetestSeccode = '';
    return RiskVerifier.verifyXrpcChallenge(cookie, input);
  }

  /**
   * 服务层统一入口：命中 1034 时自动弹统一验证窗并换 challenge。
   * 返回重放用 challenge（用户取消/验证失败为 ''）；未命中风控也返回 ''（不抛异常，调用方自行重放）。
   */
  static async tryResolveRisk(resp: ApiResponse, cookie: string, path: string): Promise<string> {
    if (!resp.isRiskControl()) {
      return '';
    }
    return RiskVerifier.resolveGtChallenge(cookie, path);
  }

  /** 注册极验（createVerification?is_high=true，头带 challenge_game/path） */
  static async createVerification(cookie: string, path: string): Promise<GtChallengeData> {
    RiskVerifier.currentChallengePath = path;
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

  /** 极验通过后换 x-rpc-challenge（POST verifyVerification，带 challenge_game/path 头，对齐 Windows CardClient.VerifyVerificationAsync） */
  static async verifyXrpcChallenge(cookie: string, gv: GeetestValidateInput): Promise<string> {
    const validate: string = gv.geetestValidate;
    const seccode: string = gv.geetestSeccode.length > 0 ? gv.geetestSeccode : `${validate}|jordan`;
    const body: Record<string, string> = {
      'geetest_challenge': gv.geetestChallenge,
      'geetest_validate': validate,
      'geetest_seccode': seccode,
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
      'x-rpc-challenge_game': '2',
      'x-rpc-challenge_path': RiskVerifier.currentChallengePath,
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

  /** createVerification/verifyVerification 需带触发风控的接口 path（checkForRisk 时记录） */
  private static currentChallengePath: string = '';
}
