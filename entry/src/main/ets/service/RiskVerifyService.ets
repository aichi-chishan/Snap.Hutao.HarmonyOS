/**
 * RiskVerifyService.ets
 * 统一人机验证服务（服务层 ↔ UI 桥）：
 *   - game_record 1034 极验（gt/challenge）
 *   - passport 登录 aigis 会话（x-rpc-aigis 响应头）
 *   - luna 签到体内极验（gt/challenge）
 * Service 层调用 verifyGt/verifyAigis 返回 Promise；UI 挂载 RiskVerifyModal 后
 * 通过 submitValidate/cancel 完成回传。Promise 结果：
 *   verifyGt   → geetest_validate（取消/失败为 ''）
 *   verifyAigis→ 组装好的 x-rpc-aigis 重放头值（取消/失败为 ''）
 */
import { AigisSession, AigisChallenge } from '../data/network/AigisSession';
import { Logger } from '../common/Logger';

const TAG: string = 'RiskVerifyService';

/** AppStorage 键：弹窗显示开关 */
export const KEY_RISK_SHOW: string = 'riskVerifyShow';
/** AppStorage 键：当前验证请求对象 */
export const KEY_RISK_REQ: string = 'riskVerifyReq';

/** 验证请求（UI 弹窗数据源；kind: 'gt'=极验 gt/challenge，'aigis'=登录会话） */
export class RiskVerifyRequest {
  kind: string = 'gt';
  gt: string = '';
  challenge: string = '';
  /** aigis 会话 id（kind='aigis' 时有效） */
  sessionId: string = '';
  /** 请求序号（同参数重复弹出时强制刷新） */
  seq: number = 0;
}

type ValidateCallback = (validate: string) => void;

export class RiskVerifyService {
  private static instance: RiskVerifyService = new RiskVerifyService();
  static getInstance(): RiskVerifyService {
    return RiskVerifyService.instance;
  }

  private seq: number = 0;
  private pendingResolve: ValidateCallback | undefined = undefined;
  /** 当前请求（保存 challenge/sessionId 供结果组装） */
  private currentReq: RiskVerifyRequest | undefined = undefined;

  /**
   * 发起 gt 极验（1034/签到体内）。返回 geetest_validate；用户关闭或失败返回 ''。
   */
  verifyGt(gt: string, challenge: string): Promise<string> {
    const req: RiskVerifyRequest = new RiskVerifyRequest();
    req.kind = 'gt';
    req.gt = gt;
    req.challenge = challenge;
    return this.show(req, (validate: string): string => validate);
  }

  /**
   * 解析 aigis 响应头并弹窗验证。返回组装好的 x-rpc-aigis 重放头值；无需验证/取消返回 ''。
   */
  verifyAigis(rawHeader: string): Promise<string> {
    const session: AigisChallenge | undefined = AigisSession.parse(rawHeader);
    if (session === undefined) {
      return Promise.resolve('');
    }
    const req: RiskVerifyRequest = new RiskVerifyRequest();
    req.kind = 'aigis';
    req.gt = session.gt;
    req.challenge = session.challenge;
    req.sessionId = session.sessionId;
    return this.show(req, (validate: string): string => {
      if (validate.length === 0) {
        return '';
      }
      return AigisSession.buildAigisHeader(session.sessionId, session.challenge, validate);
    });
  }

  /** UI 弹窗完成：传入 geetest_validate（空串表示取消/失败） */
  submitValidate(validate: string): void {
    if (this.pendingResolve === undefined) {
      return;
    }
    Logger.info(TAG, `verify done validate=${validate.length > 0}`);
    const resolve: ValidateCallback = this.pendingResolve;
    this.pendingResolve = undefined;
    resolve(validate);
  }

  /** 用户关闭弹窗 */
  cancel(): void {
    Logger.info(TAG, 'verify cancelled by user');
    this.submitValidate('');
  }

  /** 是否有进行中的验证 */
  hasPending(): boolean {
    return this.pendingResolve !== undefined;
  }

  /** 当前请求快照（弹窗初始化读取） */
  snapshot(): RiskVerifyRequest | undefined {
    return this.currentReq;
  }

  /** 内部：弹窗（同一时刻仅一个；并发请求直接返回 ''） */
  private show(req: RiskVerifyRequest, mapResult: (validate: string) => string): Promise<string> {
    if (this.pendingResolve !== undefined) {
      Logger.warn(TAG, 'another verify in progress, reject new request');
      return Promise.resolve('');
    }
    this.seq += 1;
    req.seq = this.seq;
    this.currentReq = req;
    AppStorage.setOrCreate<RiskVerifyRequest>(KEY_RISK_REQ, req);
    AppStorage.setOrCreate<boolean>(KEY_RISK_SHOW, true);
    return new Promise<string>((resolve: (value: string) => void) => {
      this.pendingResolve = (validate: string): void => {
        this.pendingResolve = undefined;
        this.currentReq = undefined;
        AppStorage.setOrCreate<boolean>(KEY_RISK_SHOW, false);
        resolve(mapResult(validate));
      };
    });
  }
}
