/**
 * AigisSession.ets
 * 米哈游 passport 登录链路人机验证会话（对齐 Windows AigisSession/GeetestService.TryVerifyAigisSessionAsync）：
 *   响应头 x-rpc-aigis = base64(JSON{session_id, mmt_type, data})
 *     其中 data 为 JSON 字符串 {success, gt, challenge, new_captcha}（GeetestVerification）
 *   完成极验后组装重放头 x-rpc-aigis = "{session_id};{base64(JSON{geetest_challenge, geetest_validate, geetest_seccode})}"
 */
import { util } from '@kit.ArkTS';
import { Logger } from '../../common/Logger';

const TAG: string = 'AigisSession';

/** 极验默认 seccode 后缀（对齐 Windows GeetestWebResponse） */
const SECCODE_SUFFIX: string = '|jordan';

/** 解析后的 aigis 会话（含极验参数） */
export class AigisChallenge {
  sessionId: string = '';
  mmtType: number = 0;
  gt: string = '';
  challenge: string = '';

  isValid(): boolean {
    return this.sessionId.length > 0 && this.gt.length > 0 && this.challenge.length > 0;
  }
}

export class AigisSession {
  /** 解析响应头 x-rpc-aigis；失败返回 undefined（即无需验证） */
  static parse(rawHeader: string): AigisChallenge | undefined {
    if (rawHeader.length === 0) {
      return undefined;
    }
    try {
      const decoder: util.Base64Helper = new util.Base64Helper();
      const bytes: Uint8Array = decoder.decodeSync(rawHeader);
      const json: string = util.TextDecoder.create('utf-8').decodeWithStream(bytes);
      const obj = JSON.parse(json) as Record<string, Object>;
      const session: AigisChallenge = new AigisChallenge();
      session.sessionId = String(obj['session_id'] ?? '');
      session.mmtType = Number(obj['mmt_type'] ?? 0);
      const dataText: string = String(obj['data'] ?? '');
      if (dataText.length > 0) {
        const dataObj = JSON.parse(dataText) as Record<string, Object>;
        session.gt = String(dataObj['gt'] ?? '');
        session.challenge = String(dataObj['challenge'] ?? '');
      }
      Logger.info(TAG, `parse ok session=${session.sessionId} gt=${session.gt.length > 0}`);
      return session.isValid() ? session : undefined;
    } catch (e) {
      Logger.warn(TAG, `parse fail: ${(e as Error).message}`);
      return undefined;
    }
  }

  /** 极验结果 → 重放头 x-rpc-aigis 值（session_id;base64(geetest_* 三元组)） */
  static buildAigisHeader(sessionId: string, challenge: string, validate: string): string {
    const seccode: string = `${validate}${SECCODE_SUFFIX}`;
    const payload: string = JSON.stringify({
      'geetest_challenge': challenge,
      'geetest_validate': validate,
      'geetest_seccode': seccode,
    } as Record<string, string>);
    const encoder: util.Base64Helper = new util.Base64Helper();
    const encoded: string = encoder.encodeToStringSync(util.TextEncoder.create('utf-8').encodeInto(payload));
    return `${sessionId};${encoded}`;
  }
}
