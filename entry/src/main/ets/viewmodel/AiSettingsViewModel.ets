import { AiModelProfile, AiProtocol, AiProviderProfile, AiWorkspaceSettings } from '../model/AiWorkspace';
import { AiAnalysisService, AiProvider } from '../service/AiAnalysisService';
import { AiWorkspaceService } from '../service/AiWorkspaceService';
import { AiWorkspaceChoice } from './AiWorkspaceViewModel';

@Observed
export class AiSettingsViewModel {
  providerMode: number = AiProvider.System;
  providerId: string = '';
  modelId: string = '';
  providers: AiWorkspaceChoice[] = [];
  models: AiWorkspaceChoice[] = [];
  providerName: string = '';
  endpoint: string = '';
  protocol: number = AiProtocol.ChatCompletions;
  apiKey: string = '';
  modelName: string = '';
  modelCode: string = '';
  temperature: string = '';
  topP: string = '';
  maxInputTokens: string = '';
  maxContextTokens: string = '';
  maxOutputTokens: string = '';
  reasoningEffort: string = '';
  thinking: number = -1;
  omitReasoningEffortWhenThinkingDisabled: boolean = true;
  userName: string = '';
  systemPrompt: string = '';
  maximumIterations: string = '';
  busy: boolean = false;
  status: string = '';

  private readonly service: AiWorkspaceService = new AiWorkspaceService();
  private settings: AiWorkspaceSettings = new AiWorkspaceSettings();

  async load(): Promise<void> {
    await this.execute(async (): Promise<void> => {
      this.providerMode = AiAnalysisService.provider();
      this.settings = await this.service.loadSettings();
      this.userName = this.settings.userName;
      this.systemPrompt = this.settings.systemPrompt;
      this.maximumIterations = String(this.settings.maximumIterations);
      this.showProvider(this.settings.providerId || this.settings.providers[0]?.id || '');
    });
  }

  selectMode(mode: number): void {
    this.providerMode = mode;
    AiAnalysisService.setProvider(mode === AiProvider.Custom ? AiProvider.Custom : AiProvider.System);
  }

  selectProvider(id: string): void {
    if (this.busy) { return; }
    this.showProvider(id);
  }

  selectModel(id: string): void {
    if (this.busy) { return; }
    this.showModel(id);
  }

  addProvider(): void {
    if (this.busy) { return; }
    const provider: AiProviderProfile = new AiProviderProfile();
    provider.id = AiWorkspaceService.newId();
    provider.name = '新服务商';
    this.settings.providers.push(provider);
    this.showProvider(provider.id);
    this.addModel();
  }

  async copyProvider(): Promise<void> {
    await this.execute(async (): Promise<void> => {
      const source: AiProviderProfile = this.editedProvider();
      const provider: AiProviderProfile = new AiProviderProfile();
      provider.id = AiWorkspaceService.newId();
      provider.name = source.name + ' 副本';
      provider.protocol = source.protocol;
      provider.endpoint = source.endpoint;
      provider.models = source.models.map((model: AiModelProfile): AiModelProfile => {
        const copy: AiModelProfile = JSON.parse(JSON.stringify(model)) as AiModelProfile;
        copy.id = AiWorkspaceService.newId();
        if (model.id === source.modelId) { provider.modelId = copy.id; }
        return copy;
      });
      const key: string = await this.currentKey(source.id);
      if (key.length > 0) { await this.service.saveKey(provider.id, key); }
      this.persistProvider(provider);
      this.status = '已复制服务商';
    });
  }

  async deleteProvider(): Promise<void> {
    await this.execute(async (): Promise<void> => {
      const previous: string = this.providerId;
      const next: AiWorkspaceSettings = this.copySettings();
      next.providers = next.providers.filter((provider: AiProviderProfile): boolean => provider.id !== previous);
      next.providerId = next.providers[0]?.id ?? '';
      this.service.saveSettings(next);
      this.settings = next;
      this.showProvider(next.providerId);
      await this.service.deleteKey(previous);
      this.status = '已删除服务商';
    });
  }

  addModel(): void {
    const provider: AiProviderProfile | undefined = this.selectedProvider();
    if (this.busy || provider === undefined) { return; }
    const model: AiModelProfile = new AiModelProfile();
    model.id = AiWorkspaceService.newId();
    provider.models.push(model);
    this.showModel(model.id);
  }

  async deleteModels(all: boolean): Promise<void> {
    await this.execute(async (): Promise<void> => {
      const provider: AiProviderProfile = this.editedProvider(false);
      provider.models = all ? [] : provider.models.filter((model: AiModelProfile): boolean => model.id !== this.modelId);
      provider.modelId = provider.models[0]?.id ?? '';
      if (this.apiKey.trim().length > 0) { await this.service.saveKey(provider.id, this.apiKey.trim()); }
      this.persistProvider(provider);
      this.status = all ? '已清空模型列表' : '已删除模型';
    });
  }

  async save(): Promise<void> {
    await this.execute(async (): Promise<void> => {
      if (this.providerId.length === 0) {
        const next: AiWorkspaceSettings = this.copySettings();
        this.service.saveSettings(next);
        this.settings = next;
      } else {
        const provider: AiProviderProfile = this.editedProvider();
        if (this.apiKey.trim().length > 0) { await this.service.saveKey(provider.id, this.apiKey.trim()); }
        this.persistProvider(provider);
      }
      this.status = '已保存 AI 设置';
    });
  }

  async listModels(): Promise<void> {
    await this.execute(async (): Promise<void> => {
      const provider: AiProviderProfile = this.editedProvider();
      const key: string = await this.currentKey(provider.id);
      provider.models = await this.service.refreshModels(provider, key);
      if (!provider.models.some((model: AiModelProfile): boolean => model.id === provider.modelId)) {
        provider.modelId = provider.models[0]?.id ?? '';
      }
      if (this.apiKey.trim().length > 0) { await this.service.saveKey(provider.id, key); }
      this.persistProvider(provider);
      this.status = `已更新模型列表（${provider.models.length} 个）`;
    });
  }

  async test(): Promise<void> {
    await this.execute(async (): Promise<void> => {
      const provider: AiProviderProfile = this.editedProvider();
      const model: AiModelProfile | undefined = provider.models.find((item: AiModelProfile): boolean => item.id === provider.modelId);
      if (model === undefined || model.model.length === 0) { throw new Error('请填写模型 ID'); }
      const reply: boolean = await this.service.testConnection(provider, model, await this.currentKey(provider.id));
      this.status = reply ? '连接测试成功' : '已连接，模型返回空文本';
    });
  }

  private selectedProvider(): AiProviderProfile | undefined {
    return this.settings.providers.find((provider: AiProviderProfile): boolean => provider.id === this.providerId);
  }

  private showProvider(id: string): void {
    this.providerId = id;
    const provider: AiProviderProfile | undefined = this.selectedProvider();
    this.providers = this.settings.providers.map((item: AiProviderProfile): AiWorkspaceChoice =>
      new AiWorkspaceChoice(item.id, item.name || '未命名服务商'));
    this.providerName = provider?.name ?? '';
    this.endpoint = provider?.endpoint ?? '';
    this.protocol = provider?.protocol ?? AiProtocol.ChatCompletions;
    this.apiKey = '';
    this.showModel(provider?.modelId || provider?.models[0]?.id || '');
  }

  private showModel(id: string): void {
    this.modelId = id;
    const models: AiModelProfile[] = this.selectedProvider()?.models ?? [];
    this.models = models.map((model: AiModelProfile): AiWorkspaceChoice =>
      new AiWorkspaceChoice(model.id, model.name || model.model || '新模型'));
    const model: AiModelProfile | undefined = models.find((item: AiModelProfile): boolean => item.id === id);
    this.modelName = model?.name ?? '';
    this.modelCode = model?.model ?? '';
    this.temperature = String(model?.temperature ?? '');
    this.topP = String(model?.topP ?? '');
    this.maxInputTokens = String(model?.maxInputTokens ?? '');
    this.maxContextTokens = String(model?.maxContextTokens ?? '');
    this.maxOutputTokens = String(model?.maxOutputTokens ?? '');
    this.reasoningEffort = model?.reasoningEffort ?? '';
    this.thinking = model?.thinking ?? -1;
    this.omitReasoningEffortWhenThinkingDisabled = model?.omitReasoningEffortWhenThinkingDisabled ?? true;
  }

  private editedProvider(includeModel: boolean = true): AiProviderProfile {
    const old: AiProviderProfile | undefined = this.selectedProvider();
    if (old === undefined) { throw new Error('请先添加服务商'); }
    const provider: AiProviderProfile = new AiProviderProfile();
    provider.id = old.id;
    provider.name = this.providerName.trim() || '未命名服务商';
    provider.protocol = this.protocol as AiProtocol;
    provider.endpoint = this.endpoint.trim();
    provider.models = old.models.slice();
    provider.modelId = this.modelId;
    AiWorkspaceService.validateEndpoint(provider.protocol, provider.endpoint);
    if (includeModel && this.modelId.length > 0) {
      const model: AiModelProfile = this.editedModel();
      const index: number = provider.models.findIndex((item: AiModelProfile): boolean => item.id === model.id);
      if (index >= 0) { provider.models[index] = model; }
    }
    return provider;
  }

  private editedModel(): AiModelProfile {
    const model: AiModelProfile = new AiModelProfile();
    model.id = this.modelId;
    model.name = this.modelName.trim();
    model.model = this.modelCode.trim();
    model.temperature = AiSettingsViewModel.optionalNumber(this.temperature, '温度', 0, 2);
    model.topP = AiSettingsViewModel.optionalNumber(this.topP, 'Top P', 0, 1);
    model.maxInputTokens = AiSettingsViewModel.tokenLimit(this.maxInputTokens, '输入 token 上限');
    model.maxContextTokens = AiSettingsViewModel.tokenLimit(this.maxContextTokens, '上下文 token 上限');
    model.maxOutputTokens = AiSettingsViewModel.tokenLimit(this.maxOutputTokens, '输出 token 上限');
    if (model.maxContextTokens !== undefined && model.maxOutputTokens !== undefined &&
      model.maxOutputTokens >= model.maxContextTokens) { throw new Error('上下文 token 上限须大于输出上限'); }
    model.reasoningEffort = this.reasoningEffort;
    model.thinking = this.thinking;
    model.omitReasoningEffortWhenThinkingDisabled = this.omitReasoningEffortWhenThinkingDisabled;
    return model;
  }

  private persistProvider(provider: AiProviderProfile): void {
    const next: AiWorkspaceSettings = this.copySettings();
    const index: number = next.providers.findIndex((item: AiProviderProfile): boolean => item.id === provider.id);
    if (index < 0) { next.providers.push(provider); }
    else { next.providers[index] = provider; }
    next.providerId = provider.id;
    this.service.saveSettings(next);
    this.settings = next;
    this.showProvider(provider.id);
  }

  private copySettings(): AiWorkspaceSettings {
    const next: AiWorkspaceSettings = new AiWorkspaceSettings();
    next.providers = this.settings.providers.slice();
    next.providerId = this.settings.providerId;
    next.userName = this.userName.trim();
    next.systemPrompt = this.systemPrompt.trim();
    next.maximumIterations = AiSettingsViewModel.tokenLimit(this.maximumIterations, '单轮调用次数') ?? 500;
    return next;
  }

  private currentKey(providerId: string): Promise<string> {
    const key: string = this.apiKey.trim();
    return key.length > 0 ? Promise.resolve(key) : this.service.loadKey(providerId);
  }

  private async execute(action: () => Promise<void>): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.status = '';
    try { await action(); }
    catch (error) { this.status = (error as Error).message || 'AI 设置操作失败'; }
    finally { this.busy = false; }
  }

  private static optionalNumber(text: string, label: string, min: number, max: number): number | undefined {
    if (text.trim().length === 0) { return undefined; }
    const value: number = Number(text);
    if (!Number.isFinite(value) || value < min || value > max) { throw new Error(`${label}须在 ${min}–${max} 之间`); }
    return value;
  }

  private static tokenLimit(text: string, label: string): number | undefined {
    const value: number | undefined = AiSettingsViewModel.optionalNumber(text, label, 1, 2147483647);
    if (value !== undefined && !Number.isInteger(value)) { throw new Error(`${label}须为整数`); }
    return value;
  }
}
