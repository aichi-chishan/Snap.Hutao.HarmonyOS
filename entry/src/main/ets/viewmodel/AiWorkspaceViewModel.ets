import {
  AiConversation, AiConversationMessage, AiModelProfile, AiProviderProfile, AiRequestCancellation,
  AiTokenUsage, AiToolCall, AiWorkspaceSettings
} from '../model/AiWorkspace';
import { AiWorkspaceService } from '../service/AiWorkspaceService';
import { AiAnalysisResult, AiAnalysisService, AiProvider } from '../service/AiAnalysisService';
import { Logger } from '../common/Logger';

export class AiWorkspaceChoice {
  id: string = '';
  label: string = '';

  constructor(id: string, label: string) {
    this.id = id;
    this.label = label;
  }
}

export class AiTranscriptRow {
  id: string = '';
  author: string = '';
  text: string = '';
  reasoning: string = '';

  constructor(id: string, author: string, text: string, reasoning: string = '') {
    this.id = id;
    this.author = author;
    this.text = text;
    this.reasoning = reasoning;
  }
}

class AiConversationRuntime {
  draft: string = '';
  preview: string = '';
  previewReasoning: string = '';
  error: string = '';
  request?: AiRequestCancellation;
}

@Observed
export class AiWorkspaceViewModel {
  loading: boolean = false;
  busy: boolean = false;
  input: string = '';
  preview: string = '';
  previewReasoning: string = '';
  error: string = '';
  rows: AiTranscriptRow[] = [];
  conversations: AiWorkspaceChoice[] = [];
  providers: AiWorkspaceChoice[] = [];
  models: AiWorkspaceChoice[] = [];
  conversationId: string = '';
  providerId: string = '';
  modelId: string = '';
  approvalName: string = '';
  approvalText: string = '';
  usageText: string = '';
  canRetry: boolean = false;
  canContinue: boolean = false;
  systemMode: boolean = true;
  localBusy: boolean = false;
  localContent: string = '';

  private readonly service: AiWorkspaceService = new AiWorkspaceService();
  private readonly runtimes: Map<string, AiConversationRuntime> = new Map<string, AiConversationRuntime>();
  private settings: AiWorkspaceSettings = new AiWorkspaceSettings();
  private records: AiConversation[] = [];
  private uid: string = '';
  private snapshot: string = '';
  private compactSnapshot: string = '';
  private generation: number = 0;

  async load(uid: string, snapshot: string, compactSnapshot: string = snapshot): Promise<void> {
    this.leave();
    const generation: number = this.generation;
    this.uid = uid;
    this.setSnapshot(snapshot, compactSnapshot);
    this.systemMode = AiAnalysisService.provider() === AiProvider.System;
    this.loading = false;
    this.localBusy = false;
    this.localContent = '';
    this.input = '';
    this.error = '';
    this.records = [];
    this.conversationId = '';
    this.providerId = '';
    this.modelId = '';
    this.updateView();
    if (uid.length === 0) { return; }
    this.loading = true;
    try {
      const settings: AiWorkspaceSettings = await this.service.loadSettings();
      if (generation !== this.generation) { return; }
      this.settings = settings;
      this.records = this.service.loadConversations(uid);
      if (this.records.length === 0) { this.records.push(this.createDraft()); }
      this.conversationId = this.records[0].id;
      this.updateView();
    } catch (_) {
      if (generation === this.generation) { this.showError('无法读取 AI 工作区'); }
    } finally {
      if (generation === this.generation) { this.loading = false; }
    }
  }

  setSnapshot(snapshot: string, compactSnapshot: string): void {
    this.snapshot = snapshot;
    this.compactSnapshot = compactSnapshot;
  }

  async reloadSettings(): Promise<void> {
    this.systemMode = AiAnalysisService.provider() === AiProvider.System;
    const generation: number = this.generation;
    try {
      const settings: AiWorkspaceSettings = await this.service.loadSettings();
      if (generation !== this.generation) { return; }
      this.settings = settings;
      this.updateView();
    } catch (_) {
      if (generation === this.generation) { this.showError('无法读取模型设置'); }
    }
  }

  leave(): void {
    this.generation++;
    for (const record of this.records) {
      const runtime: AiConversationRuntime | undefined = this.runtimes.get(record.id);
      const request: AiRequestCancellation | undefined = runtime?.request;
      if (runtime === undefined || request === undefined) { continue; }
      try {
        this.savePartial(this.uid, record, runtime);
      } catch (_) {
        Logger.warn('AiWorkspace', '保存关闭时的生成内容失败');
      } finally {
        request.cancel();
      }
    }
    this.runtimes.clear();
    this.uid = '';
    this.records = [];
    this.setSnapshot('', '');
  }

  async runSystemAnalysis(): Promise<void> {
    if (this.localBusy || this.snapshot.length === 0) { return; }
    const generation: number = this.generation;
    this.localBusy = true;
    this.localContent = '';
    try {
      const result: AiAnalysisResult = await AiAnalysisService.getInstance().analyzeSystem(this.snapshot, this.compactSnapshot);
      if (generation === this.generation) { this.localContent = result.content; }
    } catch (error) {
      if (generation === this.generation) { this.localContent = (error as Error).message || '端侧分析失败'; }
    } finally {
      if (generation === this.generation) { this.localBusy = false; }
    }
  }

  selectConversation(id: string): void {
    if (id === this.conversationId || !this.records.some((record: AiConversation): boolean => record.id === id)) { return; }
    const previous: AiConversationRuntime | undefined = this.runtimes.get(this.conversationId);
    if (previous !== undefined) { previous.draft = this.input; }
    this.conversationId = id;
    this.input = this.runtimeFor(id).draft;
    this.updateView();
  }

  private createDraft(): AiConversation {
    const record: AiConversation = new AiConversation();
    record.id = AiWorkspaceService.newId();
    record.title = '新会话';
    record.snapshot = this.snapshot;
    const provider: AiProviderProfile | undefined = this.selectedProvider();
    const model: AiModelProfile | undefined = this.selectedModel(provider);
    record.providerId = provider?.id ?? '';
    record.modelId = model?.id ?? '';
    return record;
  }

  newConversation(): void {
    if (this.uid.length === 0) { return; }
    const record: AiConversation = this.createDraft();
    try {
      this.save(this.uid, record);
      this.records.unshift(record);
      this.selectConversation(record.id);
    } catch (_) {
      this.showError('无法保存会话');
    }
  }

  deleteConversation(): void {
    if (this.busy) { return; }
    const index: number = this.records.findIndex((record: AiConversation): boolean => record.id === this.conversationId);
    if (index < 0) { return; }
    try {
      this.service.deleteConversation(this.uid, this.conversationId);
      this.runtimes.delete(this.conversationId);
      this.records.splice(index, 1);
      if (this.records.length === 0) { this.records.push(this.createDraft()); }
      this.selectConversation(this.records[Math.min(index, this.records.length - 1)].id);
    } catch (_) {
      this.showError('无法删除会话');
    }
  }

  selectProvider(id: string): void {
    if (this.busy || this.approvalName.length > 0) { return; }
    const provider: AiProviderProfile | undefined = this.settings.providers.find((item: AiProviderProfile): boolean => item.id === id);
    if (provider === undefined) { return; }
    this.selectModelProfile(provider.id, provider.modelId);
  }

  selectModel(id: string): void {
    if (this.busy || this.approvalName.length > 0) { return; }
    this.selectModelProfile(this.providerId, id);
  }

  private selectModelProfile(providerId: string, modelId: string): void {
    const record: AiConversation | undefined = this.current();
    if (record === undefined) {
      this.providerId = providerId;
      this.modelId = modelId;
      this.refreshModels();
      return;
    }
    const previousProvider: string = record.providerId;
    const previousModel: string = record.modelId;
    record.providerId = providerId;
    record.modelId = modelId;
    try {
      this.save(this.uid, record);
    } catch (_) {
      record.providerId = previousProvider;
      record.modelId = previousModel;
      this.showError('无法保存会话的模型选择');
    }
    this.updateView();
  }

  async generate(prompt: string = '请分析我的账号历史，并给出下一步建议。'): Promise<void> {
    if (this.snapshot.length === 0) { return; }
    const previous: string = this.conversationId;
    this.newConversation();
    if (this.conversationId === previous || this.conversationId.length === 0) { return; }
    this.input = prompt;
    await this.send();
  }

  async send(): Promise<void> {
    const text: string = this.input.trim();
    if (this.busy || this.approvalName.length > 0 || text.length === 0) { return; }
    if (!this.hasSelectedModel()) { this.showError('请选择一个已配置的模型'); return; }
    if (this.current() === undefined) {
      this.newConversation();
      this.input = text;
    }
    const record: AiConversation | undefined = this.current();
    if (record === undefined) { return; }
    const oldTitle: string = record.title;
    const oldSnapshot: string = record.snapshot;
    const oldProviderId: string = record.providerId;
    const oldModelId: string = record.modelId;
    if (record.messages.length === 0) {
      record.title = text.slice(0, 32);
      record.snapshot = this.snapshot;
      record.providerId = this.providerId;
      record.modelId = this.modelId;
    }
    record.messages.push(new AiConversationMessage('user', text));
    try {
      this.save(this.uid, record);
    } catch (_) {
      record.messages.pop();
      record.title = oldTitle;
      record.snapshot = oldSnapshot;
      record.providerId = oldProviderId;
      record.modelId = oldModelId;
      this.showError('无法保存发送的消息');
      return;
    }
    this.input = '';
    this.runtimeFor(record.id).draft = '';
    await this.run(record);
  }

  stop(): void { this.runtimes.get(this.conversationId)?.request?.cancel(); }

  async regenerate(): Promise<void> {
    const record: AiConversation | undefined = this.current();
    if (this.busy || this.approvalName.length > 0 || record === undefined) { return; }
    if (!this.hasSelectedModel()) { this.showError('请选择一个已配置的模型'); return; }
    const last: number = this.lastUserIndex(record);
    if (last < 0) { return; }
    const original: AiConversationMessage[] = record.messages;
    record.messages = original.slice(0, last + 1);
    try {
      this.save(this.uid, record);
    } catch (_) {
      record.messages = original;
      this.showError('无法保存重试的会话');
      return;
    }
    await this.run(record);
  }

  async resume(): Promise<void> {
    const record: AiConversation | undefined = this.current();
    if (!this.busy && this.canContinue && record !== undefined) { await this.run(record); }
  }

  async answerApproval(approved: boolean): Promise<void> {
    const record: AiConversation | undefined = this.current();
    if (this.busy || record === undefined) { return; }
    const call: AiToolCall | undefined = this.pending(record);
    if (call === undefined) { return; }
    AiWorkspaceService.answerTool(call, approved);
    try {
      this.save(this.uid, record);
    } catch (_) {
      call.result = undefined;
      call.rejected = false;
      this.showError('无法保存工具决定');
      return;
    }
    this.updateView();
    if (this.pending(record) === undefined) { await this.run(record); }
  }

  transcript(): string {
    return (this.current()?.messages ?? []).map((message: AiConversationMessage): string =>
      `${this.author(message)}\n${message.text}`).join('\n\n');
  }

  private async run(record: AiConversation): Promise<void> {
    const provider: AiProviderProfile | undefined = this.selectedProvider();
    const model: AiModelProfile | undefined = this.selectedModel(provider);
    if (provider === undefined || model === undefined || model.model.length === 0) {
      this.showError('请选择一个已配置的模型');
      return;
    }
    if (record.messages.length - this.lastUserIndex(record) - 1 >= this.settings.maximumIterations) {
      this.showError('已达到本轮模型调用次数设置');
      return;
    }
    const uid: string = this.uid;
    const generation: number = this.generation;
    const runtime: AiConversationRuntime = this.runtimeFor(record.id);
    const request: AiRequestCancellation = new AiRequestCancellation();
    runtime.request = request;
    runtime.preview = '';
    runtime.previewReasoning = '';
    runtime.error = '';
    this.updateView();
    try {
      const reply: AiConversationMessage = await this.service.send(provider, model, this.settings, record,
        (delta: string): void => {
          if (generation !== this.generation || request.cancelled) { return; }
          runtime.preview += delta;
          if (this.conversationId === record.id) { this.preview = runtime.preview; }
        }, request, (delta: string): void => {
          if (generation !== this.generation || request.cancelled) { return; }
          runtime.previewReasoning += delta;
          if (this.conversationId === record.id) { this.previewReasoning = runtime.previewReasoning; }
        });
      if (generation !== this.generation) { return; }
      if (request.cancelled) { throw new Error('已停止生成'); }
      if (reply.text.length === 0 && reply.toolCalls.length === 0 && reply.reasoningText.length === 0) {
        throw new Error('模型未返回文本或工具请求');
      }
      for (const call of reply.toolCalls) {
        if (AiWorkspaceService.approvalText(call) === undefined) { AiWorkspaceService.answerTool(call, false); }
      }
      this.appendReply(uid, record, reply);
    } catch (error) {
      if (generation !== this.generation) { return; }
      runtime.error = request.cancelled ? '已停止生成' : (error as Error).message || '模型调用失败';
      if (request.cancelled) {
        try {
          this.savePartial(uid, record, runtime);
        } catch (_) {
          runtime.error = '无法保存已生成的部分';
        }
      }
    } finally {
      if (generation === this.generation) {
        runtime.request = undefined;
        runtime.preview = '';
        runtime.previewReasoning = '';
        if (this.conversationId === record.id) { this.updateView(); }
      }
    }
  }

  private savePartial(uid: string, record: AiConversation, runtime: AiConversationRuntime): void {
    if (runtime.preview.length === 0 && runtime.previewReasoning.length === 0) { return; }
    const reply: AiConversationMessage = new AiConversationMessage('assistant', runtime.preview);
    reply.reasoningText = runtime.previewReasoning;
    this.appendReply(uid, record, reply);
  }

  private appendReply(uid: string, record: AiConversation, reply: AiConversationMessage): void {
    record.messages.push(reply);
    try { this.save(uid, record); }
    catch (error) { record.messages.pop(); throw error as Error; }
  }

  private save(uid: string, record: AiConversation): void {
    record.updatedAt = Date.now();
    this.service.saveConversation(uid, record);
  }

  private current(): AiConversation | undefined {
    return this.records.find((record: AiConversation): boolean => record.id === this.conversationId);
  }

  private runtimeFor(id: string): AiConversationRuntime {
    const existing: AiConversationRuntime | undefined = this.runtimes.get(id);
    if (existing !== undefined) { return existing; }
    const runtime: AiConversationRuntime = new AiConversationRuntime();
    this.runtimes.set(id, runtime);
    return runtime;
  }

  private showError(message: string): void {
    const runtime: AiConversationRuntime | undefined = this.runtimes.get(this.conversationId);
    if (runtime !== undefined) { runtime.error = message; }
    this.error = message;
  }

  private selectedProvider(): AiProviderProfile | undefined {
    return this.settings.providers.find((provider: AiProviderProfile): boolean => provider.id === this.providerId);
  }

  private selectedModel(provider: AiProviderProfile | undefined): AiModelProfile | undefined {
    return provider?.models.find((model: AiModelProfile): boolean => model.id === this.modelId);
  }

  private hasSelectedModel(): boolean {
    return (this.selectedModel(this.selectedProvider())?.model.length ?? 0) > 0;
  }

  private pending(record: AiConversation): AiToolCall | undefined {
    const last: AiConversationMessage | undefined = record.messages[record.messages.length - 1];
    return last?.toolCalls.find((call: AiToolCall): boolean => call.result === undefined);
  }

  private lastUserIndex(record: AiConversation): number {
    for (let index: number = record.messages.length - 1; index >= 0; index--) {
      if (record.messages[index].role === 'user') { return index; }
    }
    return -1;
  }

  private refreshModels(): void {
    const provider: AiProviderProfile | undefined = this.selectedProvider();
    const models: AiModelProfile[] = provider?.models ?? [];
    this.models = models.map((model: AiModelProfile): AiWorkspaceChoice => new AiWorkspaceChoice(model.id, model.name || model.model || '未命名模型'));
    if (!models.some((model: AiModelProfile): boolean => model.id === this.modelId)) {
      this.modelId = provider?.modelId || models[0]?.id || '';
    }
  }

  private author(message: AiConversationMessage): string {
    return message.role === 'user' ? this.settings.userName || '你' : 'AI';
  }

  private updateView(): void {
    this.conversations = this.records.map((record: AiConversation): AiWorkspaceChoice => new AiWorkspaceChoice(record.id, record.title));
    const record: AiConversation | undefined = this.current();
    const runtime: AiConversationRuntime | undefined = record === undefined ? undefined : this.runtimeFor(record.id);
    this.busy = runtime?.request !== undefined;
    this.preview = runtime?.preview ?? '';
    this.previewReasoning = runtime?.previewReasoning ?? '';
    this.error = runtime?.error ?? '';
    this.providers = this.settings.providers.map((provider: AiProviderProfile): AiWorkspaceChoice =>
      new AiWorkspaceChoice(provider.id, provider.name || '未命名服务商'));
    const preferredId: string = record?.providerId || this.providerId || this.settings.providerId;
    this.providerId = this.providers.some((item: AiWorkspaceChoice): boolean => item.id === preferredId)
      ? preferredId : this.providers[0]?.id ?? '';
    this.modelId = record?.modelId || this.modelId || this.selectedProvider()?.modelId || '';
    this.refreshModels();
    const last: AiConversationMessage | undefined = record?.messages[record.messages.length - 1];
    const pending: AiToolCall | undefined = record === undefined ? undefined : this.pending(record);
    this.approvalName = pending?.name ?? '';
    this.approvalText = pending === undefined ? '' : AiWorkspaceService.approvalText(pending) ?? '';
    this.canRetry = record !== undefined && this.lastUserIndex(record) >= 0;
    this.canContinue = pending === undefined && (last?.toolCalls.length ?? 0) > 0;
    const rows: AiTranscriptRow[] = [];
    const usage: AiTokenUsage = new AiTokenUsage();
    for (const message of record?.messages ?? []) {
      const reasoning: string = message.reasoningText || AiConversationMessage.publicReasoning(message.reasoningItems ?? []);
      if (message.text.length > 0 || reasoning.length > 0) {
        rows.push(new AiTranscriptRow(`${this.conversationId}:${rows.length}`, this.author(message), message.text, reasoning));
      }
      for (const call of message.toolCalls) {
        if (call.result !== undefined) {
          rows.push(new AiTranscriptRow(`${this.conversationId}:${rows.length}`, call.name, call.rejected ? '已拒绝' : call.result));
        }
      }
      usage.input += message.usage.input;
      usage.output += message.usage.output;
      usage.reasoning += message.usage.reasoning;
      usage.cached += message.usage.cached;
    }
    this.rows = rows;
    this.usageText = usage.input + usage.output > 0
      ? `输入 ${usage.input} · 输出 ${usage.output} · 推理 ${usage.reasoning} · 缓存 ${usage.cached}` : '';
  }
}
