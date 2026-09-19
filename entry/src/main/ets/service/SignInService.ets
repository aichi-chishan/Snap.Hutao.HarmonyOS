/**
 * SignInService.ets
 * 米游社每日签到：luna/sign（DS Gen1/LK2 + Cookie）+ luna/home（奖励列表与状态）。
 * 补签：luna/resign_info（配额/米游币）+ luna/resign（对齐 Windows SignInClient.ReSignAsync）。返回码 -5003 已签等映射。
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
  /** 签到/补签成功后本次获得的奖励文案（如「获得 原石 ×60」，对齐 Windows InfoBar 奖励展示） */
  rewardText: string = '';
}

/** 补签信息（对齐 Windows SignInRewardReSignInfo） */
export class ResignInfo {
  /** 本月漏签天数 */
  missedDays: number = 0;
  /** 本月已补签次数 */
  usedCount: number = 0;
  /** 本月补签上限 */
  limitCount: number = 0;
  /** 米游币余额 */
  coinCount: number = 0;
  /** 每次补签花费（米游币） */
  coinCost: number = 0;

  /** 剩余补签次数 */
  leftCount(): number {
    return Math.max(0, this.limitCount - this.usedCount);
  }

  /** 是否可补签（有漏签且有配额且有米游币） */
  canResign(): boolean {
    return this.missedDays > 0 && this.leftCount() > 0 && this.coinCount >= this.coinCost;
  }
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
    resp = await SignInService.resolveSignRisk(uid, region, cookie, resp,
      (u: string, reg: string, ck: string, extra?: Record<string, string>): Promise<ApiResponse> => {
        return HoyolabClient.signIn(u, reg, ck, extra);
      });
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
      result.rewardText = await SignInService.awardTextOfNewestDay(uid);
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

  /** 拉取补签信息（漏签/配额/米游币；失败抛错由调用方提示） */
  async fetchResignInfo(uid: string): Promise<ResignInfo> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(user);
    }
    const region: string = RegionUtil.regionOfUid(uid);
    const cookie: string = user.gameRecordCookie();
    const resp: ApiResponse = await HoyolabClient.fetchResignInfo(uid, region, cookie);
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const d = resp.data as Record<string, Object>;
    const info: ResignInfo = new ResignInfo();
    info.missedDays = Number(d['sign_cnt_missed'] ?? 0);
    info.usedCount = Number(d['resign_cnt_monthly'] ?? 0);
    info.limitCount = Number(d['resign_limit_monthly'] ?? 0);
    info.coinCount = Number(d['coin_cnt'] ?? 0);
    info.coinCost = Number(d['coin_cost'] ?? 0);
    return info;
  }

  /** 执行补签（服务端自动补最近漏签日；风控/返回码处理对齐 Windows ClaimResignInRewardAsync） */
  async resign(uid: string): Promise<SignInResult> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      const r: SignInResult = new SignInResult();
      r.ok = false;
      r.message = '请先登录';
      return r;
    }
    const region: string = RegionUtil.regionOfUid(uid);
    const cookie: string = user.gameRecordCookie();
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(user);
    }
    let resp: ApiResponse = await HoyolabClient.resignSign(uid, region, cookie);
    resp = await SignInService.resolveSignRisk(uid, region, cookie, resp,
      (u: string, reg: string, ck: string, extra?: Record<string, string>): Promise<ApiResponse> => {
        return HoyolabClient.resignSign(u, reg, ck, extra);
      });
    const result: SignInResult = new SignInResult();
    if (resp.success) {
      result.ok = true;
      result.message = '补签成功';
      result.rewardText = await SignInService.awardTextOfNewestDay(uid);
      return result;
    }
    switch (resp.retcode) {
      case RetCodes.RESIGN_QUOTA_USED_UP:
        result.ok = false;
        result.message = '本月补签次数已用完';
        return result;
      case RetCodes.PLEASE_SIGN_IN_FIRST:
        result.ok = false;
        result.message = '请先完成今日签到再补签';
        return result;
      case RetCodes.NO_AVAILABLE_RESIGN_DATE:
        result.ok = false;
        result.message = '本月没有可补签的日期';
        return result;
      case RetCodes.NOT_ENOUGH_COIN:
        result.ok = false;
        result.message = '米游币不足，无法补签';
        return result;
      default:
        break;
    }
    if (resp.isRiskControl()) {
      result.ok = false;
      result.message = '被风控拦截，请稍后再试';
      return result;
    }
    result.ok = false;
    result.message = resp.userFriendlyMessage();
    Logger.warn(TAG, `resign fail retcode=${resp.retcode} msg=${resp.message}`);
    return result;
  }

  /** 最新已签那天的奖励文案（对齐 Windows InfoBar「获得 xx ×n」；取不到返回空串） */
  private static async awardTextOfNewestDay(uid: string): Promise<string> {
    try {
      const info: SignInInfo = await SignInService.getInstance().fetchInfo(uid);
      if (info.signedDays <= 0) {
        return '';
      }
      for (let i = 0; i < info.rewards.length; i++) {
        const r = info.rewards[i];
        if (r.day === info.signedDays) {
          return `获得 ${r.name} ×${r.count}`;
        }
      }
    } catch (e) {
      Logger.warn(TAG, `award lookup fail ${(e as Error).message}`);
    }
    return '';
  }

  /**
   * 签到/补签风控处理（重放一轮，重放目标由 replayFn 指定）：
   *   a) 响应体内极验 data{success:1, gt, challenge} → 弹窗验证 → challenge+validate+seccode 重放
   *      （对齐 Windows SignInClient：SignAsync 体内 GeetestWebResponse 路径）；
   *   b) retcode 1034 → createVerification 统一链路 → challenge 重放。
   */
  private static async resolveSignRisk(uid: string, region: string, cookie: string, resp: ApiResponse,
    replayFn: (u: string, reg: string, ck: string, extra?: Record<string, string>) => Promise<ApiResponse>):
    Promise<ApiResponse> {
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
          return replayFn(uid, region, cookie, replay);
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
        return replayFn(uid, region, cookie, RiskUiHelper.riskReplayHeaders(challenge));
      }
    }
    return resp;
  }
}
