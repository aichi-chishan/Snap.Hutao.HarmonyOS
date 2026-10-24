/**
 * AiAnalysisService.ets
 * AI 分析双通道（对齐 Windows 2.0 AI 分析能力，鸿蒙侧按用户决策改为双通道）：
 *   - 系统 AI（默认）：DataAugmentationKit 端侧问答模型 localChatModel（无网络、无 key）
 *   - 自定义 API：OpenAI 兼容 chat/completions 端点（用户自填 base_url + api_key + model）
 * 分析对象为账号洞察匿名 JSON（无 UID/无个人标识）。
 * API key 仅存本机 PreferencesStore，不写日志、不入备份导出之外的任何上报。
 */
import { localChatModel } from '@kit.DataAugmentationKit';
import { http } from '@kit.NetworkKit';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { Logger } from '../common/Logger';

const TAG: string = 'AiAnalysisService';

/** 分析通道（0=系统 AI，1=自定义 API） */
export enum AiProvider {
  System = 0,
  Custom = 1
}

/** 自定义 API 配置（OpenAI 兼容） */
export class AiCustomConfig {
  baseUrl: string = '';
  apiKey: string = '';
  model: string = '';
}

/** 分析结果 */
export class AiAnalysisResult {
  ok: boolean = false;
  content: string = '';
  /** 实际使用的通道（回显给 UI） */
  providerName: string = '';
}

/** 端侧模型单问 ID（同应用内递增唯一） */
let nextQuestionId: number = 1;

export class AiAnalysisService {
  private static instance: AiAnalysisService = new AiAnalysisService();

  static getInstance(): AiAnalysisService {
    return AiAnalysisService.instance;
  }

  /** 当前通道（设置页持久化） */
  static provider(): AiProvider {
    return PreferencesStore.getNumber('ai.provider', AiProvider.System) === AiProvider.Custom
      ? AiProvider.Custom : AiProvider.System;
  }

  static setProvider(provider: AiProvider): void {
    PreferencesStore.setNumber('ai.provider', provider);
  }

  static customConfig(): AiCustomConfig {
    const config: AiCustomConfig = new AiCustomConfig();
    config.baseUrl = PreferencesStore.getString('ai.custom.baseUrl', '');
    config.apiKey = PreferencesStore.getString('ai.custom.apiKey', '');
    config.model = PreferencesStore.getString('ai.custom.model', '');
    return config;
  }

  static saveCustomConfig(config: AiCustomConfig): void {
    PreferencesStore.setString('ai.custom.baseUrl', config.baseUrl.trim());
    PreferencesStore.setString('ai.custom.apiKey', config.apiKey.trim());
    PreferencesStore.setString('ai.custom.model', config.model.trim());
  }

  /** 系统端侧模型是否可用（能力探测，失败提示引导切换自定义 API） */
  static async systemAvailable(): Promise<boolean> {
    try {
      return await localChatModel.init();
    } catch (e) {
      Logger.warn(TAG, `localChatModel init fail: ${(e as Error).message}`);
      return false;
    }
  }

  /**
   * 分析账号洞察匿名 JSON。
   * prompt 按端侧模型的 4500 字节建议裁剪：超限时仅保留 summary（去掉逐期 points）。
   */
  async analyze(insightsJson: string): Promise<AiAnalysisResult> {
    const result: AiAnalysisResult = new AiAnalysisResult();
    const provider: AiProvider = AiAnalysisService.provider();
    if (provider === AiProvider.Custom) {
      const config: AiCustomConfig = AiAnalysisService.customConfig();
      if (config.baseUrl.length === 0 || config.apiKey.length === 0 || config.model.length === 0) {
        result.content = '自定义 API 未配置完整：请在设置 → AI 分析中填写接口地址、模型与密钥';
        return result;
      }
      return this.analyzeByCustomApi(config, insightsJson);
    }
    result.providerName = '系统 AI';
    const available: boolean = await AiAnalysisService.systemAvailable();
    if (!available) {
      result.content = '本机不支持端侧问答模型（或初始化失败）；可在设置 → AI 分析切换为自定义 API';
      return result;
    }
    const prompt: string = AiAnalysisService.buildPrompt(insightsJson, true);
    return new Promise<AiAnalysisResult>((resolve, reject) => {
      const question: localChatModel.QuestionInfo = {
        questionId: nextQuestionId++ & 0xFFFF,
        content: prompt
      };
      const config: localChatModel.Config = { isStream: false };
      localChatModel.chat(question, config, (err, answer) => {
        if (err) {
          Logger.warn(TAG, `localChatModel chat fail: ${JSON.stringify(err)}`);
          reject(new Error('端侧模型执行失败，请稍后重试或切换自定义 API'));
          return;
        }
        if (answer.isFinished) {
          result.ok = answer.content.trim().length > 0;
          result.content = answer.content.trim().length > 0
            ? answer.content : '端侧模型未返回内容，请调整问题后重试';
          resolve(result);
        }
        // 非流式配置下中间回调忽略，等 isFinished
      }).catch((e: Error) => {
        reject(new Error(`端侧模型调用失败：${e.message}`));
      });
    });
  }

  /** 自定义 API（OpenAI 兼容 chat/completions，非流式） */
  private async analyzeByCustomApi(config: AiCustomConfig, insightsJson: string): Promise<AiAnalysisResult> {
    const result: AiAnalysisResult = new AiAnalysisResult();
    result.providerName = `自定义 API · ${config.model}`;
    const prompt: string = AiAnalysisService.buildPrompt(insightsJson, false);
    const url: string = config.baseUrl.replace(/\/+$/, '') + '/chat/completions';
    // ArkTS 禁匿名对象字面量：显式类拼装请求体
    const sysMsg: AiChatMessage = new AiChatMessage();
    sysMsg.role = 'system';
    sysMsg.content = AiAnalysisService.SYSTEM_PROMPT;
    const userMsg: AiChatMessage = new AiChatMessage();
    userMsg.role = 'user';
    userMsg.content = prompt;
    const body: AiChatRequestBody = new AiChatRequestBody();
    body.model = config.model;
    body.messages = [sysMsg, userMsg];
    const client: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${config.apiKey}`
        },
        extraData: JSON.stringify(body),
        connectTimeout: 15000,
        readTimeout: 120000,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode !== 200) {
        result.content = `自定义 API 返回 ${response.responseCode}；请检查接口地址/密钥/模型名`;
        return result;
      }
      const text: string = response.result as string;
      const parsed: AiChatResponseBody = AiChatResponseBody.fromJson(JSON.parse(text));
      const content: string = parsed.firstContent();
      result.ok = content.length > 0;
      result.content = content.length > 0 ? content : '自定义 API 未返回内容（响应缺 choices/message/content）';
      return result;
    } catch (e) {
      result.content = `自定义 API 调用失败：${(e as Error).message}`;
      return result;
    } finally {
      client.destroy();
    }
  }

  static readonly SYSTEM_PROMPT: string = '你是原神数据分析师。根据用户提供的账号历史数据（匿名 JSON，' +
    '含祈愿/颂愿、深境螺旋、幻想真境剧诗、幽境危战的逐期统计与摘要），给出简明的中文分析：' +
    '活跃趋势、深渊/剧诗表现变化、幽战成绩与难度选择建议、祈愿消耗节奏。' +
    '只依据数据说话，不编造；末尾给 2-3 条可执行的下一步建议。控制在 500 字内。';

  /** 组装 prompt；compact=true（端侧 4500 字节建议）超限时仅保留摘要 */
  static buildPrompt(insightsJson: string, compact: boolean): string {
    let payload: string = insightsJson;
    if (compact && payload.length > 3600) {
      // 去掉逐期 points 只留 summary（手工截取，避免正则回溯）
      payload = AiAnalysisService.stripPoints(insightsJson);
    }
    return `${AiAnalysisService.SYSTEM_PROMPT}\n\n账号历史数据（JSON）：\n${payload}`;
  }

  /** 把 "points":[{...},...] 从各序列中移除，仅保留 summary/元信息 */
  static stripPoints(insightsJson: string): string {
    const key: string = '"points":[';
    let out: string = '';
    let rest: string = insightsJson;
    let index: number = rest.indexOf(key);
    while (index >= 0) {
      out += rest.substring(0, index);
      let depth: number = 1;
      let cursor: number = index + key.length;
      while (cursor < rest.length && depth > 0) {
        const ch: string = rest.charAt(cursor);
        if (ch === '[' || ch === '{') {
          depth++;
        } else if (ch === ']' || ch === '}') {
          depth--;
        }
        cursor++;
      }
      rest = rest.substring(cursor);
      index = rest.indexOf(key);
    }
    return out + rest;
  }
}

/** OpenAI 兼容请求/响应（ArkTS 显式类） */
export class AiChatMessage {
  role: string = 'user';
  content: string = '';
}

export class AiChatRequestBody {
  model: string = '';
  messages: AiChatMessage[] = [];
}

export class AiChatChoiceMessage {
  content: string = '';
}

export class AiChatChoice {
  message: AiChatChoiceMessage = new AiChatChoiceMessage();
}

export class AiChatResponseBody {
  choices: AiChatChoice[] = [];

  static fromJson(obj: Object): AiChatResponseBody {
    const out: AiChatResponseBody = new AiChatResponseBody();
    const o: Record<string, Object> = obj as Record<string, Object>;
    const choices: Object[] = (o['choices'] as Object[]) ?? [];
    for (const choice of choices) {
      const co: Record<string, Object> = choice as Record<string, Object>;
      const message: Record<string, Object> = (co['message'] as Record<string, Object>) ?? {};
      const parsed: AiChatChoice = new AiChatChoice();
      parsed.message.content = String(message['content'] ?? '');
      out.choices.push(parsed);
    }
    return out;
  }

  firstContent(): string {
    return this.choices.length > 0 ? this.choices[0].message.content.trim() : '';
  }
}
