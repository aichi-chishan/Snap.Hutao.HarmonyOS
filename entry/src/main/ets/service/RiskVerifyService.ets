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
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
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

/** 极验解题结果（challenge 为重放应使用的值：弹窗路径=原 challenge，自定义接口=返回的新 challenge） */
export class GeetestSolveResult {
  challenge: string = '';
  validate: string = '';
}

type ValidateCallback = (validate: string) => void;

export class RiskVerifyService {
  private static instance: RiskVerifyService = new RiskVerifyService();
  static getInstance(): RiskVerifyService {
    return RiskVerifyService.instance;
  }

  /** 兜底超时：UI 未响应（应用后台/无窗口，如桌面卡片进程）时不永久挂起，避免阻塞后续验证 */
  private static readonly VERIFY_TIMEOUT_MS: number = 180000;

  private seq: number = 0;
  private pendingResolve: ValidateCallback | undefined = undefined;
  /** 当前请求（保存 challenge/sessionId 供结果组装） */
  private currentReq: RiskVerifyRequest | undefined = undefined;

  /**
   * 发起 gt 极验（1034/签到体内）。返回 geetest_validate；用户关闭或失败返回 ''。
   * 配置了自定义组合接口时先尝试自动过验（对齐 Windows GeetestService.TryVerifyGtChallengeAsync 的
   * CustomGeetestClient 前置尝试），失败仍走弹窗。
   */
  verifyGt(gt: string, challenge: string): Promise<string> {
    const req: RiskVerifyRequest = new RiskVerifyRequest();
    req.kind = 'gt';
    req.gt = gt;
    req.challenge = challenge;
    return this.show(req, (validate: string): string => validate);
  }

  /**
   * 发起 gt 极验并返回完整解题结果（challenge + validate）。
   * 自定义接口成功时 challenge 为接口返回的新 challenge（重放须用它，对齐 Windows GeetestData.Challenge）；
   * 弹窗路径 challenge 为原始值。
   */
  async verifyGtFull(gt: string, challenge: string): Promise<GeetestSolveResult> {
    const solved: GeetestSolveResult | undefined = await this.tryCustomSolve(gt, challenge);
    if (solved !== undefined) {
      return solved;
    }
    const req: RiskVerifyRequest = new RiskVerifyRequest();
    req.kind = 'gt';
    req.gt = gt;
    req.challenge = challenge;
    const validate: string = await this.show(req, (v: string): string => v);
    const result: GeetestSolveResult = new GeetestSolveResult();
    result.challenge = challenge;
    result.validate = validate;
    return result;
  }

  /**
   * 解析 aigis 响应头并弹窗验证。返回组装好的 x-rpc-aigis 重放头值；无需验证/取消返回 ''。
   * 配置自定义组合接口时先尝试自动过验，成功直接组装返回（不弹窗）。
   */
  async verifyAigis(rawHeader: string): Promise<string> {
    const session: AigisChallenge | undefined = AigisSession.parse(rawHeader);
    if (session === undefined) {
      return '';
    }
    const solved: GeetestSolveResult | undefined = await this.tryCustomSolve(session.gt, session.challenge);
    if (solved !== undefined) {
      return AigisSession.buildAigisHeader(session.sessionId, solved.challenge, solved.validate);
    }
    const req: RiskVerifyRequest = new RiskVerifyRequest();
    req.kind = 'aigis';
    req.gt = session.gt;
    req.challenge = session.challenge;
    req.sessionId = session.sessionId;
    const validate: string = await this.show(req, (v: string): string => {
      if (v.length === 0) {
        return '';
      }
      return AigisSession.buildAigisHeader(session.sessionId, session.challenge, v);
    });
    return validate;
  }

  /** 用户配置的极验自定义组合接口模板（空串禁用） */
  static getCustomCompositeUrl(): string {
    try {
      return PreferencesStore.getString(PreferencesStore.KEY_GEETEST_CUSTOM_URL, '');
    } catch (e) {
      return '';
    }
  }

  /**
   * 尝试自定义组合接口自动过验（对齐 Windows CustomGeetestClient.VerifyAsync）。
   * 模板含 {0}=gt {1}=challenge；响应 {code:0, data:{challenge, validate}} 视为成功。
   */
  private async tryCustomSolve(gt: string, challenge: string): Promise<GeetestSolveResult | undefined> {
    const template: string = RiskVerifyService.getCustomCompositeUrl();
    if (template.length === 0 || template.indexOf('{0}') < 0 || template.indexOf('{1}') < 0) {
      return undefined;
    }
    const url: string = template.replace('{0}', encodeURIComponent(gt))
      .replace('{1}', encodeURIComponent(challenge));
    try {
      const resp: ApiResponse = await ApiClient.getInstance().get(url, {});
      if (!resp.success || resp.data === undefined) {
        Logger.info(TAG, `custom geetest solve fail retcode=${resp.retcode}`);
        return undefined;
      }
      const data = resp.data as Record<string, Object>;
      const outChallenge: string = String(data['challenge'] ?? '');
      const validate: string = String(data['validate'] ?? '');
      if (outChallenge.length === 0 || validate.length === 0) {
        Logger.info(TAG, 'custom geetest solve: empty challenge/validate');
        return undefined;
      }
      Logger.info(TAG, `custom geetest solve ok challenge=${outChallenge.substring(0, 8)}...`);
      const r: GeetestSolveResult = new GeetestSolveResult();
      r.challenge = outChallenge;
      r.validate = validate;
      return r;
    } catch (e) {
      Logger.warn(TAG, `custom geetest solve error: ${(e as Error).message}`);
      return undefined;
    }
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
      const seq: number = this.seq;
      const guard: number = setTimeout(() => {
        // 仅当仍是本次请求且尚未有人作答时才判超时（避免误杀后续验证）
        if (this.seq === seq && this.pendingResolve !== undefined) {
          Logger.warn(TAG, 'verify timeout, auto cancel');
          this.submitValidate('');
        }
      }, RiskVerifyService.VERIFY_TIMEOUT_MS);
      this.pendingResolve = (validate: string): void => {
        clearTimeout(guard);
        this.pendingResolve = undefined;
        this.currentReq = undefined;
        AppStorage.setOrCreate<boolean>(KEY_RISK_SHOW, false);
        resolve(mapResult(validate));
      };
    });
  }
}
