/**
 * RiskUiHelper.ets
 * 页面层通用风控跳转：捕获 RiskControlError → 携带 gt/challenge/replayKey 路由到 GeetestVerifyPage。
 * 完成后 GeetestVerifyPage 写 AppStorage(KEY_PENDING)；来源页用 consumePendingChallenge 读取并重放。
 */
import { router } from '@kit.ArkUI';
import { RiskControlError, RiskVerifier } from '../data/network/RiskVerifier';

/** 极验页路由参数 */
export interface RiskVerifyParams {
  gt: string;
  challenge: string;
  path: string;
  replayKey: string;
}

export class RiskUiHelper {
  /** 默认重放键（与 RiskVerifier.KEY_PENDING 一致） */
  static readonly KEY_PENDING: string = 'pendingRiskChallenge';

  /** 页面 catch RiskControlError 时调用：跳转极验页 */
  static routeToVerify(err: RiskControlError): void {
    const params: RiskVerifyParams = {
      gt: err.gt,
      challenge: err.challenge,
      path: err.path,
      replayKey: RiskUiHelper.KEY_PENDING,
    };
    router.pushUrl({ url: 'pages/GeetestVerifyPage', params: params });
  }

  /** 读取并消费暂存的 challenge（验证完成后重放用）；无则返回 '' */
  static consumePendingChallenge(): string {
    const c: string = AppStorage.get<string>(RiskUiHelper.KEY_PENDING) ?? '';
    if (c.length > 0) {
      AppStorage.setOrCreate<string>(RiskUiHelper.KEY_PENDING, '');
    }
    return c;
  }

  static hasPendingChallenge(): boolean {
    const c: string = AppStorage.get<string>(RiskUiHelper.KEY_PENDING) ?? '';
    return c.length > 0;
  }
}
