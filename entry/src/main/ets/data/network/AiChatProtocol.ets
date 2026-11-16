import { AiConversationMessage, AiModelProfile, AiProtocol, AiToolCall, AiTokenUsage } from '../../model/AiWorkspace';

type AiJson = Record<string, Object>;

export class AiSseReader {
  private remainder: string = '';
  private lines: string[] = [];

  push(text: string, onEvent: (data: string) => void): void {
    this.remainder += text;
    let end: number = this.remainder.indexOf('\n');
    while (end >= 0) {
      this.readLine(this.remainder.substring(0, end).replace(/\r$/, ''), onEvent);
      this.remainder = this.remainder.substring(end + 1);
      end = this.remainder.indexOf('\n');
    }
  }

  finish(onEvent: (data: string) => void): void {
    this.readLine(this.remainder.replace(/\r$/, ''), onEvent);
    this.readLine('', onEvent);
  }

  private readLine(line: string, onEvent: (data: string) => void): void {
    if (line.startsWith('data:')) {
      this.lines.push(line.substring(5).replace(/^ /, ''));
    } else if (line.length === 0 && this.lines.length > 0) {
      const data: string = this.lines.join('\n');
      this.lines = [];
      onEvent(data);
    }
  }
}

export class AiChatProtocol {
  static request(protocol: AiProtocol, model: AiModelProfile, instructions: string, messages: AiConversationMessage[],
    streaming: boolean = true, enableTools: boolean = true): AiJson {
    const body: AiJson = { 'model': model.model, 'stream': streaming };
    if (model.temperature !== undefined) { body['temperature'] = model.temperature; }
    if (model.topP !== undefined) { body['top_p'] = model.topP; }
    if (enableTools) { body['tools'] = AiChatProtocol.tools(protocol); }
    const sendEffort: boolean = model.reasoningEffort.length > 0 &&
      (model.thinking !== 0 || model.omitReasoningEffortWhenThinkingDisabled === false);
    if (protocol === AiProtocol.Responses) {
      if (instructions.length > 0) { body['instructions'] = instructions; }
      body['input'] = AiChatProtocol.responsesInput(messages);
      body['store'] = false;
      body['include'] = ['reasoning.encrypted_content'];
      if (model.maxOutputTokens !== undefined) { body['max_output_tokens'] = model.maxOutputTokens; }
      if (sendEffort) {
        const reasoning: AiJson = { 'effort': model.reasoningEffort };
        body['reasoning'] = reasoning;
      }
    } else if (protocol === AiProtocol.Anthropic) {
      if (instructions.length > 0) { body['system'] = instructions; }
      body['messages'] = AiChatProtocol.anthropicMessages(messages);
      body['max_tokens'] = model.maxOutputTokens ?? 4096;
    } else {
      body['messages'] = AiChatProtocol.chatMessages(instructions, messages);
      if (model.maxOutputTokens !== undefined) { body['max_completion_tokens'] = model.maxOutputTokens; }
      if (sendEffort) { body['reasoning_effort'] = model.reasoningEffort; }
      if (model.thinking >= 0) {
        const thinking: AiJson = { 'type': model.thinking === 1 ? 'enabled' : 'disabled' };
        body['thinking'] = thinking;
      }
    }
    return body;
  }

  private static tools(protocol: AiProtocol): AiJson[] {
    const result: AiJson[] = [];
    for (const name of ['GetCurrentTime', 'ShowSummary']) {
      const summary: boolean = name === 'ShowSummary';
      const properties: AiJson = {};
      if (summary) {
        const field: AiJson = { 'type': 'string' };
        properties['summary'] = field;
      }
      const parameters: AiJson = {
        'type': 'object', 'properties': properties, 'required': summary ? ['summary'] : [], 'additionalProperties': false
      };
      const description: string = summary ? 'Show a summary of the conversation or context.' : 'Get the current local time.';
      const definition: AiJson = { 'name': name, 'description': description };
      if (protocol === AiProtocol.Anthropic) {
        definition['input_schema'] = parameters;
        result.push(definition);
      } else {
        definition['parameters'] = parameters;
        if (protocol === AiProtocol.Responses) {
          definition['type'] = 'function';
          result.push(definition);
        } else {
          const tool: AiJson = { 'type': 'function', 'function': definition };
          result.push(tool);
        }
      }
    }
    return result;
  }

  private static chatMessages(instructions: string, messages: AiConversationMessage[]): AiJson[] {
    const result: AiJson[] = [];
    if (instructions.length > 0) { result.push(AiChatProtocol.textMessage('system', instructions)); }
    for (const message of messages) {
      const row: AiJson = AiChatProtocol.textMessage(message.role, message.text);
      if (message.toolCalls.length > 0) {
        const calls: AiJson[] = [];
        for (const call of message.toolCalls) {
          const fn: AiJson = { 'name': call.name, 'arguments': call.argumentsJson };
          const value: AiJson = { 'type': 'function', 'id': call.id, 'function': fn };
          calls.push(value);
        }
        row['tool_calls'] = calls;
        if (message.reasoningText.length > 0) { row['reasoning_content'] = message.reasoningText; }
      }
      result.push(row);
      for (const call of message.toolCalls) {
        if (call.result === undefined) { continue; }
        const output: AiJson = { 'role': 'tool', 'tool_call_id': call.id, 'content': call.result };
        result.push(output);
      }
    }
    return result;
  }

  private static responsesInput(messages: AiConversationMessage[]): AiJson[] {
    const result: AiJson[] = [];
    for (const message of messages) {
      for (const item of message.reasoningItems) {
        const reasoning: AiJson = item as AiJson;
        if (reasoning['type'] === 'reasoning') { result.push(reasoning); }
      }
      if (message.text.length > 0) { result.push(AiChatProtocol.textMessage(message.role, message.text)); }
      for (const call of message.toolCalls) {
        const item: AiJson = {
          'type': 'function_call', 'call_id': call.id, 'name': call.name, 'arguments': call.argumentsJson
        };
        result.push(item);
      }
      for (const call of message.toolCalls) {
        if (call.result === undefined) { continue; }
        const item: AiJson = { 'type': 'function_call_output', 'call_id': call.id, 'output': call.result };
        result.push(item);
      }
    }
    return result;
  }

  private static anthropicMessages(messages: AiConversationMessage[]): AiJson[] {
    const result: AiJson[] = [];
    for (const message of messages) {
      const blocks: AiJson[] = [];
      for (const item of message.reasoningItems) {
        const reasoning: AiJson = item as AiJson;
        if (reasoning['type'] === 'thinking' || reasoning['type'] === 'redacted_thinking') { blocks.push(reasoning); }
      }
      if (message.text.length > 0) {
        const text: AiJson = { 'type': 'text', 'text': message.text };
        blocks.push(text);
      }
      const outputs: AiJson[] = [];
      for (const call of message.toolCalls) {
        let input: AiJson;
        try { input = JSON.parse(call.argumentsJson) as AiJson; }
        catch (_) { input = {}; }
        const use: AiJson = { 'type': 'tool_use', 'id': call.id, 'name': call.name, 'input': input };
        blocks.push(use);
        if (call.result !== undefined) {
          const output: AiJson = { 'type': 'tool_result', 'tool_use_id': call.id, 'content': call.result, 'is_error': call.rejected };
          outputs.push(output);
        }
      }
      const messageItem: AiJson = { 'role': message.role, 'content': blocks };
      result.push(messageItem);
      if (outputs.length > 0) {
        const resultItem: AiJson = { 'role': 'user', 'content': outputs };
        result.push(resultItem);
      }
    }
    return result;
  }

  private static textMessage(role: string, text: string): AiJson {
    const item: AiJson = { 'role': role, 'content': text };
    return item;
  }
}

export class AiChatStream {
  readonly message: AiConversationMessage = new AiConversationMessage('assistant');
  receivedEvents: boolean = false;
  private completed: boolean = false;
  private readonly calls: Map<number, AiToolCall> = new Map<number, AiToolCall>();
  private readonly thinking: Map<number, AiJson> = new Map<number, AiJson>();

  private readonly protocol: AiProtocol;
  private readonly onText: (delta: string) => void;
  private readonly onReasoning?: (delta: string) => void;

  constructor(protocol: AiProtocol, onText: (delta: string) => void, onReasoning?: (delta: string) => void) {
    this.protocol = protocol;
    this.onText = onText;
    this.onReasoning = onReasoning;
  }

  event(data: string): void {
    this.receivedEvents = true;
    if (data === '[DONE]') { this.completed = true; return; }
    const obj: AiJson = JSON.parse(data) as AiJson;
    const type: string = AiChatStream.string(obj['type']);
    if ((obj['error'] !== undefined && obj['error'] !== null) || type === 'error' || type === 'response.failed') {
      throw new Error('模型返回生成错误');
    }
    if (this.protocol === AiProtocol.Responses) {
      this.responsesEvent(type, obj);
    } else if (this.protocol === AiProtocol.Anthropic) {
      this.anthropicEvent(type, obj);
    } else {
      this.chatChunk(obj);
    }
  }

  fullResponse(obj: AiJson): void {
    if (obj['error'] !== undefined && obj['error'] !== null) { throw new Error('模型返回生成错误'); }
    if (this.protocol === AiProtocol.Responses) {
      this.responsesResult(obj);
    } else if (this.protocol === AiProtocol.Anthropic) {
      const blocks: AiJson[] = AiChatStream.rows(obj['content']);
      for (let index: number = 0; index < blocks.length; index++) { this.anthropicBlock(index, blocks[index]); }
      this.readUsage(AiChatStream.object(obj['usage']));
    } else {
      this.chatChunk(obj);
    }
    this.completed = true;
  }

  finish(): AiConversationMessage {
    const indexes: number[] = Array.from(this.calls.keys()).sort((a: number, b: number): number => a - b);
    if (indexes.length > 0 && !this.completed) { throw new Error('模型的工具请求未完整返回'); }
    this.message.toolCalls = indexes.map((index: number): AiToolCall => this.tool(index));
    if (this.message.toolCalls.some((call: AiToolCall): boolean => call.id.length === 0 || call.name.length === 0)) {
      throw new Error('模型的工具请求缺少编号或名称');
    }
    for (const part of this.thinking.values()) { this.message.reasoningItems.push(part); }
    return this.message;
  }

  private text(text: string): void {
    if (text.length === 0) { return; }
    this.message.text += text;
    this.onText(text);
  }

  private reasoning(text: string): void {
    if (text.length === 0) { return; }
    this.message.reasoningText += text;
    this.onReasoning?.(text);
  }

  private tool(index: number): AiToolCall {
    const existing: AiToolCall | undefined = this.calls.get(index);
    if (existing !== undefined) { return existing; }
    const call: AiToolCall = new AiToolCall();
    this.calls.set(index, call);
    return call;
  }

  private chatChunk(obj: AiJson): void {
    this.readUsage(AiChatStream.object(obj['usage']));
    const choice: AiJson | undefined = AiChatStream.rows(obj['choices'])[0];
    if (choice === undefined) { return; }
    const delta: AiJson = AiChatStream.object(choice['delta'] ?? choice['message']);
    this.reasoning(AiChatStream.string(delta['reasoning_content']));
    this.text(AiChatStream.string(delta['content']));
    const calls: AiJson[] = AiChatStream.rows(delta['tool_calls']);
    for (let index: number = 0; index < calls.length; index++) {
      const item: AiJson = calls[index];
      const call: AiToolCall = this.tool(Number(item['index'] ?? index));
      const fn: AiJson = AiChatStream.object(item['function']);
      call.id = AiChatStream.string(item['id']) || call.id;
      call.name += AiChatStream.string(fn['name']);
      call.argumentsJson += AiChatStream.string(fn['arguments']);
    }
    if (typeof choice['finish_reason'] === 'string' && choice['finish_reason'] !== 'length') { this.completed = true; }
  }

  private responsesEvent(type: string, obj: AiJson): void {
    if (type === 'response.output_text.delta' || type === 'response.refusal.delta') {
      this.text(AiChatStream.string(obj['delta']));
    } else if (type === 'response.reasoning_summary_text.delta') {
      this.reasoning(AiChatStream.string(obj['delta']));
    } else if (type === 'response.output_item.added' || type === 'response.output_item.done') {
      this.responseCall(Number(obj['output_index'] ?? 0), AiChatStream.object(obj['item']));
    } else if (type === 'response.function_call_arguments.delta') {
      this.tool(Number(obj['output_index'] ?? 0)).argumentsJson += AiChatStream.string(obj['delta']);
    } else if (type === 'response.function_call_arguments.done') {
      this.tool(Number(obj['output_index'] ?? 0)).argumentsJson = AiChatStream.string(obj['arguments']);
    } else if (type === 'response.completed' || type === 'response.incomplete') {
      this.responsesResult(AiChatStream.object(obj['response']));
      this.completed = type === 'response.completed';
    }
  }

  private responseCall(index: number, item: AiJson): void {
    if (item['type'] !== 'function_call') { return; }
    const call: AiToolCall = this.tool(index);
    call.id = AiChatStream.string(item['call_id']) || call.id;
    call.name = AiChatStream.string(item['name']) || call.name;
    call.argumentsJson = AiChatStream.string(item['arguments']) || call.argumentsJson;
  }

  private responsesResult(obj: AiJson): void {
    this.readUsage(AiChatStream.object(obj['usage']));
    const rows: AiJson[] = AiChatStream.rows(obj['output']);
    const publicReasoning: string = AiConversationMessage.publicReasoning(rows);
    if (this.message.reasoningText.length === 0) {
      this.reasoning(publicReasoning);
    } else if (publicReasoning.length > 0) {
      this.message.reasoningText = publicReasoning;
    }
    const needsText: boolean = this.message.text.length === 0;
    for (let index: number = 0; index < rows.length; index++) {
      const item: AiJson = rows[index];
      if (item['type'] === 'reasoning' && typeof item['encrypted_content'] === 'string') {
        this.message.reasoningItems.push(item);
      } else if (item['type'] === 'message' && needsText) {
        for (const part of AiChatStream.rows(item['content'])) {
          this.text(AiChatStream.string(part['text'] ?? part['refusal']));
        }
      } else { this.responseCall(index, item); }
    }
  }

  private anthropicEvent(type: string, obj: AiJson): void {
    const index: number = Number(obj['index'] ?? 0);
    if (type === 'message_start') {
      this.readUsage(AiChatStream.object(AiChatStream.object(obj['message'])['usage']));
    } else if (type === 'content_block_start') {
      this.anthropicBlock(index, AiChatStream.object(obj['content_block']));
    } else if (type === 'content_block_delta') {
      const delta: AiJson = AiChatStream.object(obj['delta']);
      if (delta['type'] === 'text_delta') { this.text(AiChatStream.string(delta['text'])); }
      if (delta['type'] === 'input_json_delta') { this.tool(index).argumentsJson += AiChatStream.string(delta['partial_json']); }
      const part: AiJson | undefined = this.thinking.get(index);
      if (part !== undefined && delta['type'] === 'thinking_delta') {
        const text: string = AiChatStream.string(delta['thinking']);
        part['thinking'] = AiChatStream.string(part['thinking']) + text;
        this.reasoning(text);
      }
      if (part !== undefined && delta['type'] === 'signature_delta') { part['signature'] = delta['signature']; }
    } else if (type === 'message_delta') {
      this.readUsage(AiChatStream.object(obj['usage']));
    } else if (type === 'message_stop') {
      this.completed = true;
    }
  }

  private anthropicBlock(index: number, item: AiJson): void {
    if (item['type'] === 'text') {
      this.text(AiChatStream.string(item['text']));
    } else if (item['type'] === 'tool_use') {
      const call: AiToolCall = this.tool(index);
      call.id = AiChatStream.string(item['id']);
      call.name = AiChatStream.string(item['name']);
      const input: AiJson = AiChatStream.object(item['input']);
      if (Object.keys(input).length > 0) { call.argumentsJson = JSON.stringify(input); }
    } else if (item['type'] === 'thinking' || item['type'] === 'redacted_thinking') {
      this.thinking.set(index, item);
      if (item['type'] === 'thinking') { this.reasoning(AiChatStream.string(item['thinking'])); }
    }
  }

  private readUsage(obj: AiJson): void {
    const usage: AiTokenUsage = this.message.usage;
    usage.input = Number(obj['prompt_tokens'] ?? obj['input_tokens'] ?? usage.input);
    usage.output = Number(obj['completion_tokens'] ?? obj['output_tokens'] ?? usage.output);
    const input: AiJson = AiChatStream.object(obj['prompt_tokens_details'] ?? obj['input_tokens_details']);
    const output: AiJson = AiChatStream.object(obj['completion_tokens_details'] ?? obj['output_tokens_details']);
    usage.cached = Number(input['cached_tokens'] ?? obj['cache_read_input_tokens'] ?? usage.cached);
    usage.reasoning = Number(output['reasoning_tokens'] ?? usage.reasoning);
  }

  private static object(value: Object | undefined): AiJson {
    return (value as AiJson | undefined) ?? {};
  }

  private static rows(value: Object | undefined): AiJson[] {
    return Array.isArray(value) ? value as AiJson[] : [];
  }

  private static string(value: Object | undefined): string {
    return typeof value === 'string' ? value : '';
  }
}
