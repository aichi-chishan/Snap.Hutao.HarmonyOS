export enum AiProtocol {
  ChatCompletions = 0,
  Responses = 1,
  Anthropic = 2
}

export class AiModelProfile {
  id: string = '';
  name: string = '';
  model: string = '';
  temperature?: number;
  topP?: number;
  maxInputTokens?: number;
  maxContextTokens?: number;
  maxOutputTokens?: number;
  reasoningEffort: string = '';
  /** -1 uses the provider default. */
  thinking: number = -1;
  omitReasoningEffortWhenThinkingDisabled: boolean = true;
}

export class AiProviderProfile {
  id: string = '';
  name: string = '';
  protocol: AiProtocol = AiProtocol.ChatCompletions;
  endpoint: string = '';
  models: AiModelProfile[] = [];
  modelId: string = '';
}

export class AiWorkspaceSettings {
  providers: AiProviderProfile[] = [];
  providerId: string = '';
  userName: string = '';
  systemPrompt: string = '';
  maximumIterations: number = 500;
}

export class AiToolCall {
  id: string = '';
  name: string = '';
  argumentsJson: string = '';
  result?: string;
  rejected: boolean = false;
}

export class AiTokenUsage {
  input: number = 0;
  output: number = 0;
  reasoning: number = 0;
  cached: number = 0;
}

export class AiConversationMessage {
  role: string = 'user';
  text: string = '';
  toolCalls: AiToolCall[] = [];
  usage: AiTokenUsage = new AiTokenUsage();
  /** The originating API may require its signed or encrypted reasoning items on replay. */
  reasoningItems: Object[] = [];
  reasoningText: string = '';

  constructor(role: string = 'user', text: string = '') {
    this.role = role;
    this.text = text;
  }

  static publicReasoning(items: Object[]): string {
    const text: string[] = [];
    for (const item of items) {
      const part: Record<string, Object> = item as Record<string, Object>;
      if (part['type'] === 'thinking' && typeof part['thinking'] === 'string') {
        text.push(part['thinking'] as string);
      } else if (part['type'] === 'reasoning' && Array.isArray(part['summary'])) {
        for (const summary of part['summary'] as Record<string, Object>[]) {
          if (summary['type'] === 'summary_text' && typeof summary['text'] === 'string') {
            text.push(summary['text'] as string);
          }
        }
      }
    }
    return text.filter((part: string): boolean => part.length > 0).join('\n\n');
  }
}

export class AiConversation {
  id: string = '';
  title: string = '';
  updatedAt: number = 0;
  providerId: string = '';
  modelId: string = '';
  snapshot: string = '';
  messages: AiConversationMessage[] = [];
}

export class AiRequestCancellation {
  cancelled: boolean = false;
  private abort?: () => void;

  setAbort(abort?: () => void): void {
    this.abort = abort;
    if (this.cancelled) { abort?.(); }
  }

  cancel(): void {
    this.cancelled = true;
    this.abort?.();
  }
}
