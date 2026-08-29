/**
 * ApiResponse.ets
 * 米哈游统一响应封装：{ retcode, message, data } 解析 + 成功/失败判定 + 已知返回码友好映射。
 */
import { RetCodes } from '../common/Constants';

export class ApiResponse {
  retcode: number = 0;
  message: string = '';
  data: Object | undefined = undefined;
  success: boolean = true;
  /** 原始响应文本（兜底排查） */
  raw: string = '';
  /** 响应头（小写键；x-rpc-aigis 极验会话等风控链路依赖） */
  respHeaders: Record<string, string> = {};

  /** 读取指定响应头（大小写不敏感），无则返回 '' */
  header(name: string): string {
    const lower: string = name.toLowerCase();
    for (const k of Object.keys(this.respHeaders)) {
      if (k.toLowerCase() === lower) {
        return this.respHeaders[k];
      }
    }
    return '';
  }

  /** 从原始响应字符串解析 */
  static fromJson(text: string): ApiResponse {
    const resp: ApiResponse = new ApiResponse();
    resp.raw = text;
    try {
      const obj = JSON.parse(text) as Record<string, Object>;
      const rawRet: Object = obj['retcode'];
      resp.retcode = rawRet === undefined ? 0 : Number(rawRet);
      const rawMsg: Object = obj['message'];
      resp.message = rawMsg === undefined ? '' : rawMsg as string;
      const rawData: Object = obj['data'];
      resp.data = (rawData === undefined || rawData === null) ? undefined : rawData;
      resp.success = resp.retcode === RetCodes.OK;
    } catch (e) {
      resp.success = false;
      resp.retcode = -1;
      resp.message = '响应解析失败';
    }
    return resp;
  }

  /** 构建一个失败响应（本地错误归一化使用） */
  static fail(code: number, message: string): ApiResponse {
    const resp: ApiResponse = new ApiResponse();
    resp.success = false;
    resp.retcode = code;
    resp.message = message;
    resp.data = undefined;
    return resp;
  }

  /** 是否风控拦截 */
  isRiskControl(): boolean {
    return this.retcode === RetCodes.RISK_CONTROL;
  }

  /** 是否 Cookie 失效 / 未登录 */
  isAuthExpired(): boolean {
    return this.retcode === RetCodes.COOKIE_EXPIRED || this.retcode === RetCodes.NOT_LOGGED_IN;
  }

  /** 已知返回码 → 用户友好文案 */
  userFriendlyMessage(): string {
    switch (this.retcode) {
      case RetCodes.OK:
        return this.message.length > 0 ? this.message : '成功';
      case RetCodes.COOKIE_EXPIRED:
        return '登录态已失效，请重新登录';
      case RetCodes.NOT_LOGGED_IN:
        return '需要重新登录';
      case RetCodes.RISK_CONTROL:
        return '操作被风控拦截，请稍后再试';
      case RetCodes.ALREADY_SIGNED:
        return '今日已签到';
      case RetCodes.NOT_STARTED:
        return '签到活动未开始';
      case RetCodes.DAILY_LIMIT:
        return '已达到当日签到次数上限';
      case RetCodes.ACCOUNT_RISK:
        return '当前账号存在风控风险，暂无数据。可在米游社 App 内完成人机验证后重试';
      case RetCodes.NOTE_BANNED:
        return '实时便笺服务暂不可用（账号可能被限制），请稍后再试';
      case 410:
        return '祈愿接口已失效或鉴权过期，请重新登录后刷新；若仍失败请升级应用';
      case 403:
        return '请求被拒绝（403），可能被风控或访问频率限制，请稍后再试';
      case 429:
        return '请求过于频繁（429），请稍后重试';
      default:
        if (this.message && this.message.length > 0) {
          // 米哈游常见英文通用错误 → 友好化
          const m: string = this.message.toLowerCase();
          if (m.includes('something went wrong')) {
            return '角色数据获取失败，多为风控或登录态问题。请到米游社 App 完成一次人机验证，或稍后重试';
          }
          if (m.includes('too many requests') || m.includes('frequency')) {
            return '请求过于频繁，请稍后再试';
          }
          if (m.includes('login') || m.includes('auth')) {
            return '登录态已失效，请重新登录';
          }
          return this.message;
        }
        return `请求失败（${this.retcode}）`;
    }
  }
}
