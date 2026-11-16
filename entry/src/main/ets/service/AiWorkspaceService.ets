import { util } from '@kit.ArkTS';
import { AiWorkspaceStore } from '../data/local/AiWorkspaceStore';
import { AiAvailableModel, AiChatClient } from '../data/network/AiChatClient';
import { AppLocaleService } from './AppLocaleService';
import {
  AiConversation, AiConversationMessage, AiModelProfile, AiProtocol, AiProviderProfile, AiRequestCancellation,
  AiToolCall, AiWorkspaceSettings
} from '../model/AiWorkspace';

export class AiWorkspaceService {
  private readonly client: AiChatClient = new AiChatClient();

  static newId(): string { return AiWorkspaceStore.newId(); }
  loadSettings(): Promise<AiWorkspaceSettings> { return AiWorkspaceStore.loadSettings(); }
  saveSettings(settings: AiWorkspaceSettings): void { AiWorkspaceStore.saveSettings(settings); }
  loadKey(id: string): Promise<string> { return AiWorkspaceStore.loadKey(id); }
  saveKey(id: string, key: string): Promise<void> { return AiWorkspaceStore.saveKey(id, key); }
  deleteKey(id: string): Promise<void> { return AiWorkspaceStore.deleteKey(id); }
  loadConversations(uid: string): AiConversation[] { return AiWorkspaceStore.loadConversations(uid); }
  saveConversation(uid: string, conversation: AiConversation): void { AiWorkspaceStore.saveConversation(uid, conversation); }
  deleteConversation(uid: string, id: string): void { AiWorkspaceStore.deleteConversation(uid, id); }

  static validateEndpoint(protocol: AiProtocol, endpoint: string): void {
    AiChatClient.baseUrl(protocol, endpoint);
  }

  async testConnection(provider: AiProviderProfile, model: AiModelProfile, key: string): Promise<boolean> {
    return await this.client.test(provider, model, key);
  }

  async refreshModels(provider: AiProviderProfile, key: string): Promise<AiModelProfile[]> {
    const fetched: AiAvailableModel[] = await this.client.listModels(provider, key);
    const models: AiModelProfile[] = [];
    const seen: Set<string> = new Set<string>();
    for (const available of fetched) {
      if (seen.has(available.model)) { continue; }
      seen.add(available.model);
      const existing: AiModelProfile | undefined = provider.models.find((model: AiModelProfile): boolean => model.model === available.model);
      if (existing !== undefined) {
        models.push(existing);
      } else {
        const model: AiModelProfile = new AiModelProfile();
        model.id = AiWorkspaceService.newId();
        model.model = available.model;
        model.name = available.name;
        models.push(model);
      }
    }
    for (const model of provider.models) {
      if (!models.includes(model) && (model.model.length > 0 || model.name.length > 0)) { models.push(model); }
    }
    return models;
  }

  async send(provider: AiProviderProfile, model: AiModelProfile, settings: AiWorkspaceSettings,
    conversation: AiConversation, onText: (delta: string) => void, cancellation: AiRequestCancellation,
    onReasoning: (delta: string) => void): Promise<AiConversationMessage> {
    const key: string = await AiWorkspaceStore.loadKey(provider.id);
    const prompt: string = AiWorkspaceService.instructions(conversation.snapshot, settings.systemPrompt);
    const messages: AiConversationMessage[] = AiWorkspaceService.requestHistory(conversation.messages, provider.protocol, model, prompt);
    return await this.client.stream(provider, model, key, prompt, messages, onText, cancellation, onReasoning);
  }

  private static instructions(snapshot: string, customPrompt: string): string {
    let instructions: string = `Use the application's interface language (${AppLocaleService.current()}) for your answer. ` +
      '你是原神账号数据分析师。跟进问题直接回答相关数据。完整分析按祈愿各卡池、深境螺旋、' +
      '幻想真境剧诗、幽境危战和下一步计划组织，结合已有数字说明趋势与局限。时间序列与分类分布分别解读。' +
      '缺失的祈愿或期次为未知。只依据匿名历史数据，勿推测账号身份、角色配装或未提供的活动。';
    if (customPrompt.trim().length > 0) { instructions += '\n\n用户偏好\n' + customPrompt.trim(); }
    if (snapshot.length > 0) { instructions += '\n\n本会话的匿名统计数据\n' + snapshot; }
    return instructions;
  }

  /** The estimate affects request context only; the local transcript keeps all turns. */
  static requestHistory(messages: AiConversationMessage[], protocol: AiProtocol, model: AiModelProfile,
    instructions: string): AiConversationMessage[] {
    const output: number = model.maxOutputTokens ?? (protocol === AiProtocol.Anthropic ? 4096 : 0);
    const context: number = model.maxContextTokens === undefined ? Number.MAX_SAFE_INTEGER : model.maxContextTokens - output;
    const limit: number = Math.min(model.maxInputTokens ?? Number.MAX_SAFE_INTEGER, context);
    if (limit === Number.MAX_SAFE_INTEGER) { return messages; }
    const encoder: util.TextEncoder = util.TextEncoder.create();
    const sizes: number[] = messages.map((message: AiConversationMessage): number =>
      Math.ceil(encoder.encodeInto(JSON.stringify(message)).byteLength / 4));
    let total: number = Math.ceil(encoder.encodeInto(instructions).byteLength / 4);
    for (const size of sizes) { total += size; }
    let start: number = 0;
    for (let index: number = 1; index < messages.length && total > limit; index++) {
      if (messages[index].role !== 'user') { continue; }
      while (start < index) { total -= sizes[start++]; }
    }
    if (total > limit) { throw new Error('最新一轮对话和账号摘要超出模型的输入 token 设置'); }
    return messages.slice(start);
  }

  static approvalText(call: AiToolCall): string | undefined {
    let args: Record<string, Object>;
    try { args = JSON.parse(call.argumentsJson || '{}') as Record<string, Object>; }
    catch (_) { return undefined; }
    if (args === null || typeof args !== 'object' || Array.isArray(args)) { return undefined; }
    if (call.name === 'GetCurrentTime' && Object.keys(args).length === 0) { return '读取设备当前本地时间'; }
    if (call.name === 'ShowSummary' && typeof args['summary'] === 'string') { return args['summary']; }
    return undefined;
  }

  static answerTool(call: AiToolCall, approved: boolean): void {
    const description: string | undefined = AiWorkspaceService.approvalText(call);
    call.rejected = !approved || description === undefined;
    if (description === undefined) { call.result = 'Unsupported tool or invalid arguments'; }
    else if (!approved) { call.result = 'Rejected by user'; }
    else if (call.name === 'ShowSummary') { call.result = description; }
    else { call.result = AiWorkspaceService.localTime(new Date()); }
  }

  private static localTime(date: Date): string {
    const offset: number = -date.getTimezoneOffset();
    const magnitude: number = Math.abs(offset);
    const hours: string = String(Math.floor(magnitude / 60)).padStart(2, '0');
    const minutes: string = String(magnitude % 60).padStart(2, '0');
    return new Date(date.getTime() + offset * 60000).toISOString().slice(0, -1) +
      `${offset < 0 ? '-' : '+'}${hours}:${minutes}`;
  }
}
