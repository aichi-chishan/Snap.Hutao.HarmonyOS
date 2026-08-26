/**
 * SignInService.ets
 * 米游社每日签到：luna/sign（DS Gen1/LK2 + Cookie）+ luna/home（奖励列表与状态）。返回码 -5003 已签等映射。
 */
import { UserService } from './UserService';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { ApiResponse } from '../model/ApiResponse';
import { SignInInfo } from '../model/SignInInfo';
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

  /** 执行签到 */
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
    const resp: ApiResponse = await HoyolabClient.signIn(uid, region, cookie);
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
}
