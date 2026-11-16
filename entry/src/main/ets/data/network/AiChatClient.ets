import { http } from '@kit.NetworkKit';
import { url, util } from '@kit.ArkTS';
import { AiConversationMessage, AiModelProfile, AiProtocol, AiProviderProfile, AiRequestCancellation } from '../../model/AiWorkspace';
import { AiChatProtocol, AiChatStream, AiSseReader } from './AiChatProtocol';

export class AiAvailableModel {
  model: string = '';
  name: string = '';
}

export class AiChatClient {
  static baseUrl(protocol: AiProtocol, endpoint: string): string {
    const value: string = endpoint.trim() || (protocol === AiProtocol.Anthropic
      ? 'https://api.anthropic.com/v1' : 'https://api.openai.com/v1');
    const parsed: url.URL = url.URL.parseURL(value);
    const local: boolean = parsed.hostname === 'localhost' || parsed.hostname === '[::1]' ||
      parsed.hostname === '::1' || /^127(?:\.\d{1,3}){3}$/.test(parsed.hostname);
    if ((parsed.protocol !== 'https:' && !(parsed.protocol === 'http:' && local)) ||
      parsed.username.length > 0 || parsed.password.length > 0 || parsed.search.length > 0 || parsed.hash.length > 0) {
      throw new Error('AI 接口须使用 HTTPS 或本机回环 HTTP，并填写服务基址');
    }
    const base: string = parsed.href.replace(/\/+$/, '');
    return protocol === AiProtocol.Anthropic && !base.endsWith('/v1') ? base + '/v1' : base;
  }

  private static endpoint(provider: AiProviderProfile): string {
    const base: string = AiChatClient.baseUrl(provider.protocol, provider.endpoint);
    if (provider.protocol === AiProtocol.Responses) { return base + '/responses'; }
    return base + (provider.protocol === AiProtocol.Anthropic ? '/messages' : '/chat/completions');
  }

  private static headers(protocol: AiProtocol, key: string): Record<string, string> {
    if (key.trim().length === 0) { throw new Error('请在 AI 设置填写 API 密钥'); }
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (protocol === AiProtocol.Anthropic) {
      headers['x-api-key'] = key;
      headers['anthropic-version'] = '2023-06-01';
    } else {
      headers['Authorization'] = `Bearer ${key}`;
    }
    return headers;
  }

  async stream(provider: AiProviderProfile, model: AiModelProfile, key: string, instructions: string,
    messages: AiConversationMessage[], onText: (delta: string) => void,
    cancellation: AiRequestCancellation, onReasoning?: (delta: string) => void): Promise<AiConversationMessage> {
    const endpoint: string = AiChatClient.endpoint(provider);
    const headers: Record<string, string> = AiChatClient.headers(provider.protocol, key);
    headers['Accept'] = 'text/event-stream';
    const body: string = JSON.stringify(AiChatProtocol.request(provider.protocol, model, instructions, messages));
    const request: http.HttpRequest = http.createHttp();
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const reader: AiSseReader = new AiSseReader();
    const result: AiChatStream = new AiChatStream(provider.protocol, onText, onReasoning);
    let fallback: string = '';
    let released: boolean = false;
    let finishData: () => void = (): void => {};
    const accept: (data: string) => void = (data: string): void => {
      result.event(data);
      fallback = '';
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: headers,
      extraData: body,
      usingCache: false,
      maxRedirects: 0,
      connectTimeout: 15000,
      readTimeout: 120000
    };
    try {
      return await new Promise<AiConversationMessage>((resolve, reject) => {
        cancellation.setAbort((): void => reject(new Error('已停止生成')));
        if (cancellation.cancelled) { return; }
        const ended: Promise<void> = new Promise<void>((end) => { finishData = end; });
        request.on('dataEnd', (): void => { finishData(); });
        request.on('dataReceive', (data: ArrayBuffer): void => {
          if (released || cancellation.cancelled) { return; }
          try {
            const text: string = decoder.decodeToString(new Uint8Array(data), { stream: true });
            if (!result.receivedEvents) { fallback += text; }
            reader.push(text, accept);
          } catch (error) {
            reject(error as Error);
          }
        });
        request.requestInStream(endpoint, options).then(async (code: number): Promise<void> => {
          if (code < 200 || code >= 300) { throw new Error(`AI 接口返回 HTTP ${code}`); }
          await ended;
          if (released || cancellation.cancelled) { return; }
          const tail: string = decoder.decodeToString(new Uint8Array(0));
          if (!result.receivedEvents) { fallback += tail; }
          reader.push(tail, accept);
          reader.finish(accept);
          if (!result.receivedEvents) {
            result.fullResponse(JSON.parse(fallback) as Record<string, Object>);
          }
          resolve(result.finish());
        }).catch((error: Error): void => reject(error));
      });
    } finally {
      released = true;
      finishData();
      cancellation.setAbort();
      request.off('dataReceive');
      request.off('dataEnd');
      request.destroy();
    }
  }

  async test(provider: AiProviderProfile, model: AiModelProfile, key: string): Promise<boolean> {
    const probe: AiModelProfile = new AiModelProfile();
    probe.model = model.model;
    probe.maxOutputTokens = 64;
    const prompt: AiConversationMessage = new AiConversationMessage('user', 'Reply only OK. This is a connection test without account data.');
    const body: string = JSON.stringify(AiChatProtocol.request(provider.protocol, probe, '', [prompt], false, false));
    const response: Record<string, Object> = await this.json(AiChatClient.endpoint(provider),
      AiChatClient.headers(provider.protocol, key), body);
    const parsed: AiChatStream = new AiChatStream(provider.protocol, (_delta: string): void => {});
    parsed.fullResponse(response);
    return parsed.finish().text.trim().length > 0;
  }

  async listModels(provider: AiProviderProfile, key: string): Promise<AiAvailableModel[]> {
    const endpoint: string = AiChatClient.baseUrl(provider.protocol, provider.endpoint) + '/models';
    const headers: Record<string, string> = AiChatClient.headers(provider.protocol, key);
    const models: AiAvailableModel[] = [];
    let cursor: string = '';
    do {
      let query: string = '';
      if (provider.protocol === AiProtocol.Anthropic) {
        query = cursor.length > 0 ? `?limit=1000&after_id=${encodeURIComponent(cursor)}` : '?limit=1000';
      }
      const payload: Record<string, Object> = await this.json(endpoint + query, headers);
      const data: Object | undefined = payload['data'];
      if (!Array.isArray(data)) { throw new Error('模型列表缺少 data'); }
      for (const entry of data as Record<string, Object>[]) {
        if (typeof entry['id'] !== 'string' || String(entry['id']).trim().length === 0) { continue; }
        const model: AiAvailableModel = new AiAvailableModel();
        model.model = String(entry['id']).trim();
        model.name = String(entry['display_name'] ?? model.model);
        models.push(model);
      }
      const next: string = String(payload['last_id'] ?? '');
      cursor = provider.protocol === AiProtocol.Anthropic && payload['has_more'] === true && next !== cursor ? next : '';
    } while (cursor.length > 0);
    return models;
  }

  private async json(endpoint: string, headers: Record<string, string>, body?: string): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: body === undefined ? http.RequestMethod.GET : http.RequestMethod.POST,
      header: headers,
      usingCache: false,
      maxRedirects: 0,
      connectTimeout: 15000,
      readTimeout: 30000,
      expectDataType: http.HttpDataType.STRING
    };
    if (body !== undefined) { options.extraData = body; }
    try {
      const response: http.HttpResponse = await request.request(endpoint, options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`AI 接口返回 HTTP ${response.responseCode}`);
      }
      return JSON.parse(response.result as string) as Record<string, Object>;
    } finally {
      request.destroy();
    }
  }
}
