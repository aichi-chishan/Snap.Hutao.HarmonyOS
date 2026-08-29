/**
 * SignInService.ets
 * 米游社每日签到：luna/sign（DS Gen1/LK2 + Cookie）+ luna/home（奖励列表与状态）。返回码 -5003 已签等映射。
 */
import { UserService } from './UserService';
import { RiskVerifyService } from './RiskVerifyService';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { ApiResponse } from '../model/ApiResponse';
import { SignInInfo } from '../model/SignInInfo';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { RegionUtil, RetCodes } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'SignInService';

export class SignInResult {
  ok: boolean = false;
  message: string = '';
  alreadySigned: boolean = false;
}

export class SignInService {
  private static instance: SignInService = new SignInService();

  static getInstance(): SignInService {
    return SignInService.instance;
  }

  /** 拉取奖励列表与本月签到状态（luna/home + luna/info） */
  async fetchInfo(uid: string): Promise<SignInInfo> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    // 缺 cookie_token/ltoken 时先用 SToken 补齐
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(user);
    }
    const region: string = RegionUtil.regionOfUid(uid);
    const cookie: string = user.gameRecordCookie();
    // 奖励列表（luna/home），失败也保留错误消息继续拿状态
    const homeResp: ApiResponse = await HoyolabClient.fetchSignHome(region, cookie);
    const info: SignInInfo = new SignInInfo();
    if (homeResp.success && homeResp.data !== undefined) {
      info.merge(SignInInfo.fromHome(homeResp.data));
    } else {
      info.message = homeResp.userFriendlyMessage();
    }
    // 已签状态（luna/info）
    try {
      const infoResp: ApiResponse = await HoyolabClient.fetchSignInfo(uid, region, cookie);
      if (infoResp.success && infoResp.data !== undefined) {
        const state: SignInInfo = SignInInfo.fromInfo(infoResp.data);
        info.signedDays = state.signedDays;
      } else if (info.message.length === 0) {
        info.message = infoResp.userFriendlyMessage();
      }
    } catch (e) {
      Logger.warn(TAG, `fetch sign info fail ${(e as Error).message}`);
    }
    Logger.info(TAG, `sign info signedDays=${info.signedDays} rewards=${info.rewards.length}`);
    return info;
  }

  /** 执行签到（含风控极验自动重放，对齐 Windows SignInClient.SignAsync） */
  async sign(uid: string): Promise<SignInResult> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      const r: SignInResult = new SignInResult();
      r.ok = false;
      r.message = '请先登录';
      return r;
    }
    const region: string = RegionUtil.regionOfUid(uid);
    const cookie: string = user.gameRecordCookie();
    // 缺 cookie_token/ltoken 时先补齐
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(user);
    }
    let resp: ApiResponse = await HoyolabClient.signIn(uid, region, cookie);
    resp = await SignInService.resolveSignRisk(uid, region, cookie, resp);
    const result: SignInResult = new SignInResult();
    if (resp.retcode === RetCodes.ALREADY_SIGNED) {
      result.ok = false;
      result.alreadySigned = true;
      result.message = '今日已签到';
      return result;
    }
    if (resp.success) {
      result.ok = true;
      result.message = '签到成功';
      return result;
    }
    if (resp.isRiskControl()) {
      result.ok = false;
      result.message = '被风控拦截，请稍后再试';
      return result;
    }
    result.ok = false;
    result.message = resp.userFriendlyMessage();
    Logger.warn(TAG, `sign fail retcode=${resp.retcode} msg=${resp.message}`);
    return result;
  }

  /**
   * 签到风控处理（重放一轮）：
   *   a) 响应体内极验 data{success:1, gt, challenge} → 弹窗验证 → challenge+validate+seccode 重放
   *      （对齐 Windows SignInClient：SignAsync 体内 GeetestWebResponse 路径）；
   *   b) retcode 1034 → createVerification 统一链路 → challenge 重放。
   */
  private static async resolveSignRisk(uid: string, region: string, cookie: string,
    resp: ApiResponse): Promise<ApiResponse> {
    // a) 体内极验：成功 HTTP 但 data 携带 gt/challenge
    if (resp.success && resp.data !== undefined) {
      const data = resp.data as Record<string, Object>;
      const inBodySuccess: boolean = Boolean(data['success'] ?? false);
      const gt: string = String(data['gt'] ?? '');
      const challenge: string = String(data['challenge'] ?? '');
      if (inBodySuccess && gt.length > 0 && challenge.length > 0) {
        Logger.info(TAG, 'sign hit in-body geetest, launching verify');
        const validate: string = await RiskVerifyService.getInstance().verifyGt(gt, challenge);
        if (validate.length > 0) {
          const replay: Record<string, string> = RiskUiHelper.riskReplayHeaders(challenge, validate);
          return HoyolabClient.signIn(uid, region, cookie, replay);
        }
        const cancelled: ApiResponse = ApiResponse.fail(RetCodes.RISK_CONTROL, '人机验证未完成，签到已取消');
        return cancelled;
      }
      return resp;
    }
    // b) retcode 1034：走 createVerification 统一链路
    if (resp.isRiskControl()) {
      const challenge: string = await RiskVerifier.resolveGtChallenge(cookie, 'event/luna/sign');
      if (challenge.length > 0) {
        Logger.info(TAG, 'sign 1034 verified, replaying');
        return HoyolabClient.signIn(uid, region, cookie, RiskUiHelper.riskReplayHeaders(challenge));
      }
    }
    return resp;
  }
}
