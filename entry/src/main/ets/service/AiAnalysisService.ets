import { localChatModel } from '@kit.DataAugmentationKit';
import { util } from '@kit.ArkTS';
import { PreferencesStore } from '../data/prefs/PreferencesStore';

export enum AiProvider {
  System = 0,
  Custom = 1
}

export class AiAnalysisResult {
  content: string = '';
}

let nextQuestionId: number = 1;

export class AiAnalysisService {
  private static instance: AiAnalysisService = new AiAnalysisService();

  static getInstance(): AiAnalysisService { return AiAnalysisService.instance; }

  static provider(): AiProvider {
    return PreferencesStore.getNumber('ai.provider', AiProvider.System) === AiProvider.Custom
      ? AiProvider.Custom : AiProvider.System;
  }

  static setProvider(provider: AiProvider): void {
    PreferencesStore.setNumber('ai.provider', provider);
  }

  async analyzeSystem(fullSnapshot: string, compactSnapshot: string): Promise<AiAnalysisResult> {
    const result: AiAnalysisResult = new AiAnalysisResult();
    let available: boolean = false;
    try { available = await localChatModel.init(); } catch (_) {}
    if (!available) {
      result.content = '设备未能初始化端侧问答模型。可在 AI 设置切换自定义 API。';
      return result;
    }

    const instruction: string = '你是原神数据分析师。依据匿名账号历史数据，分析活跃趋势、祈愿消耗、深渊、剧诗和幽战，' +
      '给出 2–3 条可执行建议。用简明中文回答，缺失数据为未知。\n\n';
    const full: string = instruction + fullSnapshot;
    const prompt: string = util.TextEncoder.create().encodeInto(full).byteLength > 4500
      ? instruction + compactSnapshot : full;
    const question: localChatModel.QuestionInfo = { questionId: nextQuestionId++ & 0xFFFF, content: prompt };
    const options: localChatModel.Config = { isStream: false };
    return new Promise<AiAnalysisResult>((resolve, reject) => {
      localChatModel.chat(question, options, (error, answer) => {
        if (error) { reject(new Error('端侧模型执行失败')); return; }
        if (answer.isFinished) {
          result.content = answer.content.trim() || '端侧模型未返回内容';
          resolve(result);
        }
      }).catch(() => reject(new Error('端侧模型调用失败')));
    });
  }
}
