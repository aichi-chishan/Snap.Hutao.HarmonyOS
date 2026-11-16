const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const A = '100000001';
const B = '100000002';
const key = 'local-test-key';
const event = payload => `data: ${JSON.stringify(payload)}\r\n\r\n`;
const completion = text => event({ choices: [{ delta: { content: text }, finish_reason: 'stop' }] }) + 'data: [DONE]\n\n';
const plain = value => JSON.parse(JSON.stringify(value));
const { parseMarkdown } = require(path.join(root, 'data/markdown/parseMarkdown.js'));

function harness() {
  const files = new Map();
  const directories = new Set();
  const secrets = new Map();
  const prefs = new Map([['ai.provider', 1]]);
  const appStorage = new Map();
  let nativeLanguage = 'default';
  const requests = [];
  const responses = [];
  let localPrompt = '';
  const fileIo = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    accessSync: file => files.has(file) || directories.has(file),
    mkdirSync: dir => directories.add(dir),
    listFileSync: dir => [...files.keys()].filter(name => name.startsWith(dir + '/')).map(name => name.slice(dir.length + 1)),
    readTextSync: file => files.get(file),
    openSync: file => ({ fd: file }),
    writeSync(fd, data) {
      const bytes = Buffer.from(data);
      files.set(fd, bytes.toString('utf8'));
      return bytes.length;
    },
    fsyncSync() {},
    closeSync() {},
    renameSync(from, to) { files.set(to, files.get(from)); files.delete(from); },
    unlinkSync: file => files.delete(file),
  };
  const asset = {
    Tag: { ALIAS: 'alias', SECRET: 'secret', ACCESSIBILITY: 'access', CONFLICT_RESOLUTION: 'conflict', RETURN_TYPE: 'return' },
    Accessibility: { DEVICE_FIRST_UNLOCKED: 1 }, ConflictResolution: { OVERWRITE: 0 },
    ReturnType: { ALL: 0 }, ErrorCode: { NOT_FOUND: 24000002 },
    async add(attrs) { secrets.set(Buffer.from(attrs.get('alias')).toString(), attrs.get('secret')); },
    async query(attrs) {
      const secret = secrets.get(Buffer.from(attrs.get('alias')).toString());
      if (secret === undefined) { throw Object.assign(new Error('asset missing'), { code: 24000002 }); }
      return [new Map([['secret', secret]])];
    },
    async remove(attrs) { secrets.delete(Buffer.from(attrs.get('alias')).toString()); },
  };
  const http = {
    RequestMethod: { POST: 'POST', GET: 'GET' }, HttpDataType: { STRING: 'string' },
    createHttp() {
      const listeners = new Map();
      const log = { released: false };
      function record(url, options) {
        Object.assign(log, { url, options, body: options.extraData && JSON.parse(options.extraData) });
        requests.push(log);
        assert.ok(responses.length > 0, 'unmocked network request');
        return responses.shift();
      }
      return {
        on(name, listener) { listeners.set(name, listener); },
        off(name) { listeners.delete(name); },
        destroy() { log.released = true; assert.equal(listeners.size, 0); },
        async requestInStream(url, options) {
          const fixture = record(url, options);
          const buffer = Buffer.from(fixture.stream);
          // Exercise both Unicode boundaries and partial SSE lines.
          for (let index = 0; index < buffer.length; index += 7) {
            const bytes = buffer.subarray(index, index + 7);
            listeners.get('dataReceive')?.(Uint8Array.from(bytes).buffer);
          }
          if (fixture.wait) { await fixture.wait; }
          listeners.get('dataEnd')?.();
          return fixture.code ?? 200;
        },
        async request(url, options) {
          const fixture = record(url, options);
          return { responseCode: fixture.code ?? 200, result: JSON.stringify(fixture.json) };
        },
      };
    },
  };
  const mocks = {
    '@kit.ArkTS': {
      url: { URL: { parseURL: input => new URL(input) } },
      util: {
        generateRandomUUID: randomUUID,
        TextEncoder: { create: () => ({ encodeInto: value => new TextEncoder().encode(value) }) },
        TextDecoder: { create: (encoding, options) => {
          const decoder = new TextDecoder(encoding, options);
          return { decodeToString: (data, options) => decoder.decode(data, options) };
        } },
      },
    },
    '@kit.NetworkKit': { http },
    '@kit.LocalizationKit': { i18n: { System: {
      getSystemLanguage: () => 'zh-Hans', getAppPreferredLanguage: () => nativeLanguage,
      setAppPreferredLanguage: language => { nativeLanguage = language; },
    } } },
    '@kit.CoreFileKit': { fileIo },
    '@kit.AssetStoreKit': { asset },
    '@kit.DataAugmentationKit': { localChatModel: {
      async init() { return true; },
      async chat(question, config, callback) {
        localPrompt = question.content;
        assert.equal(config.isStream, false);
        callback(undefined, { isFinished: true, content: '端侧结果' });
      },
    } },
    'common/AppContext': { AppContextProvider: { getFilesDir: () => '/sandbox' } },
    'common/Logger': { Logger: { warn() {} } },
    'data/prefs/PreferencesStore': { PreferencesStore: {
      isReady: () => true,
      getString: (name, value) => prefs.get(name) ?? value,
      setString: (name, value) => prefs.set(name, value),
      getNumber: (name, value) => prefs.get(name) ?? value,
      setNumber: (name, value) => prefs.set(name, value),
    } },
  };
  const modules = new Map();
  function load(name) {
    if (mocks[name]) { return mocks[name]; }
    if (modules.has(name)) { return modules.get(name); }
    const source = readFileSync(path.join(root, name + '.ets'), 'utf8').replace(/^@Observed\r?\n/gm, '');
    const module = { exports: {} };
    const compiled = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, reportDiagnostics: true,
    });
    assert.equal(compiled.diagnostics.length, 0, name);
    runInNewContext(compiled.outputText, {
      module, exports: module.exports, require: dependency => load(dependency.startsWith('.')
        ? path.posix.normalize(path.posix.join(path.posix.dirname(name), dependency)) : dependency),
      AppStorage: { get: name => appStorage.get(name), setOrCreate: (name, value) => appStorage.set(name, value) },
    }, { filename: name + '.ets' });
    modules.set(name, module.exports);
    return module.exports;
  }
  const model = load('model/AiWorkspace');
  const { AiWorkspaceStore } = load('data/local/AiWorkspaceStore');
  async function configure(protocol) {
    const provider = new model.AiProviderProfile();
    provider.id = randomUUID();
    provider.name = '自定义';
    provider.endpoint = 'https://example.invalid/v1';
    provider.protocol = protocol;
    const selected = new model.AiModelProfile();
    selected.id = randomUUID();
    selected.model = 'test-model';
    provider.models = [selected];
    provider.modelId = selected.id;
    const settings = new model.AiWorkspaceSettings();
    settings.providers = [provider];
    settings.providerId = provider.id;
    AiWorkspaceStore.saveSettings(settings);
    await AiWorkspaceStore.saveKey(provider.id, key);
    return { provider, selected };
  }
  return { files, prefs, secrets, requests, responses, mocks, load, model, AiWorkspaceStore, configure, localPrompt: () => localPrompt };
}

test('migrates the old model and moves its credential out of JSON and preferences', async () => {
  const h = harness();
  h.prefs.set('ai.custom.baseUrl', 'https://example.invalid/v1');
  h.prefs.set('ai.custom.model', 'previous-model');
  h.prefs.set('ai.custom.apiKey', key);
  const [first, second] = await Promise.all([h.AiWorkspaceStore.loadSettings(), h.AiWorkspaceStore.loadSettings()]);
  assert.equal(first.providers[0].id, second.providers[0].id);
  assert.equal(first.providers[0].models[0].model, 'previous-model');
  assert.equal(await h.AiWorkspaceStore.loadKey(first.providers[0].id), key);
  assert.equal(h.prefs.get('ai.custom.apiKey'), '');
  assert.ok([...h.files.values()].every(value => !value.includes(key)));
});

test('streaming requests use the effective cached application language', async () => {
  const h = harness();
  await h.configure(h.model.AiProtocol.ChatCompletions);
  const locale = h.load('service/AppLocaleService').AppLocaleService;
  assert.equal(locale.select('ja'), true);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const workspace = new AiWorkspaceViewModel();
  await workspace.load(A, '{"series":[]}');
  h.responses.push({ stream: completion('分析結果') });
  workspace.input = '分析';
  await workspace.send();
  assert.equal(workspace.error, '');
  assert.equal(h.requests.length, 1);
  assert.match(h.requests[0].body.messages[0].content, /interface language \(ja\)/);
  assert.equal(locale.select('system'), true);
  assert.equal(locale.current(), 'ja');
  assert.equal(locale.restartRequired(), true);
});

test('Chat Completions resumes approvals after reload and only runs an approved built-in tool', async () => {
  const h = harness();
  await h.configure(h.model.AiProtocol.ChatCompletions);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const vm = new AiWorkspaceViewModel();
  await vm.load(A, '{"series":[]}');
  h.responses.push({ stream: event({ choices: [{ delta: { content: '确认' } }] }) +
    event({ choices: [{ delta: { tool_calls: [
      { index: 0, id: 'clock', function: { name: 'GetCurrentTime', arguments: '{}' } },
      { index: 1, id: 'summary', function: { name: 'ShowSummary', arguments: '{"sum' } },
    ] } }] }) +
    event({ choices: [{ delta: { tool_calls: [
      { index: 1, function: { arguments: 'mary":"模型摘要"}' } },
    ] }, finish_reason: 'tool_calls' }] }) + 'data: [DONE]\n\n' });
  vm.input = '请分析';
  await vm.send();
  assert.equal(vm.approvalName, 'GetCurrentTime');
  assert.equal(h.requests.length, 1);
  assert.ok(h.requests[0].released);
  assert.equal(h.requests[0].options.header.Authorization, 'Bearer ' + key);
  assert.doesNotMatch(JSON.stringify(h.requests[0].body), new RegExp(A + '|' + key));
  assert.equal(h.AiWorkspaceStore.loadConversations(B).length, 0);

  const resumed = new AiWorkspaceViewModel();
  await resumed.load(A, '{"series":[]}');
  await resumed.answerApproval(true);
  assert.equal(resumed.approvalText, '模型摘要');
  assert.equal(h.requests.length, 1);
  h.responses.push({ stream: completion('完成分析') });
  await resumed.answerApproval(false);
  assert.equal(resumed.error, '');
  assert.equal(resumed.rows.at(-1).text, '完成分析');
  const results = h.requests[1].body.messages.filter(message => message.role === 'tool');
  assert.match(results[0].content, /^\d{4}-\d{2}-\d{2}T.*[+-]\d{2}:\d{2}$/);
  assert.equal(results[1].content, 'Rejected by user');
  assert.equal(h.AiWorkspaceStore.loadConversations(A)[0].messages.length, 3);
});

test('Responses sends function_call_output with call_id and encrypted reasoning replay', async () => {
  const h = harness();
  const { provider, selected } = await h.configure(h.model.AiProtocol.Responses);
  const { AiChatClient } = h.load('data/network/AiChatClient');
  const { AiChatProtocol } = h.load('data/network/AiChatProtocol');
  const { AiWorkspaceService } = h.load('service/AiWorkspaceService');
  const call = { type: 'function_call', call_id: 'call_1', name: 'ShowSummary', arguments: '' };
  let visibleReasoning = '';
  h.responses.push({ stream: event({ type: 'response.reasoning_summary_text.delta', delta: '**公开摘要**' }) +
    event({ type: 'response.output_text.delta', delta: '回应' }) +
    event({ type: 'response.output_item.added', output_index: 1, item: call }) +
    event({ type: 'response.function_call_arguments.delta', output_index: 1, delta: '{"summary":"文本"}' }) +
    event({ type: 'response.completed', response: { output: [
      { type: 'reasoning', id: 'rs_1', encrypted_content: 'opaque', summary: [{ type: 'summary_text', text: '**公开摘要**' }] },
      { ...call, arguments: '{"summary":"文本"}' },
    ], usage: { input_tokens: 5, output_tokens: 3 } } }) });
  const history = [new h.model.AiConversationMessage('user', '你好')];
  const reply = await new AiChatClient().stream(provider, selected, key, 'context', history, () => {},
    new h.model.AiRequestCancellation(), delta => { visibleReasoning += delta; });
  assert.equal(reply.text, '回应');
  assert.equal(reply.reasoningText, '**公开摘要**');
  assert.equal(visibleReasoning, reply.reasoningText);
  assert.equal(reply.usage.input, 5);
  AiWorkspaceService.answerTool(reply.toolCalls[0], true);
  const body = plain(AiChatProtocol.request(provider.protocol, selected, 'context', [...history, reply]));
  assert.equal(body.store, false);
  assert.deepEqual(body.input.find(item => item.type === 'function_call_output'),
    { type: 'function_call_output', call_id: 'call_1', output: '文本' });
  assert.equal(body.input.find(item => item.type === 'reasoning').encrypted_content, 'opaque');
});

test('Anthropic streams public thinking and preserves signed and redacted blocks on tool replay', async () => {
  const h = harness();
  const { provider, selected } = await h.configure(h.model.AiProtocol.Anthropic);
  const { AiChatClient } = h.load('data/network/AiChatClient');
  const { AiChatProtocol } = h.load('data/network/AiChatProtocol');
  const { AiWorkspaceService } = h.load('service/AiWorkspaceService');
  selected.maxOutputTokens = 120;
  selected.topP = 0.9;
  h.responses.push({ stream: event({ type: 'message_start', message: { usage: { input_tokens: 12 } } }) +
    event({ type: 'content_block_start', index: 0, content_block: { type: 'thinking', thinking: '', signature: '' } }) +
    event({ type: 'content_block_delta', index: 0, delta: { type: 'thinking_delta', thinking: '公开思考' } }) +
    event({ type: 'content_block_delta', index: 0, delta: { type: 'signature_delta', signature: 'signed' } }) +
    event({ type: 'content_block_start', index: 1, content_block: { type: 'redacted_thinking', data: 'opaque' } }) +
    event({ type: 'content_block_start', index: 2, content_block: { type: 'tool_use', id: 'toolu_1', name: 'ShowSummary', input: {} } }) +
    event({ type: 'content_block_delta', index: 2, delta: { type: 'input_json_delta', partial_json: '{"summary":"摘要"}' } }) +
    event({ type: 'message_delta', usage: { output_tokens: 4 } }) + event({ type: 'message_stop' }) });
  const request = new h.model.AiConversationMessage('user', '汇总');
  const reply = await new AiChatClient().stream(provider, selected, key, 'system', [request], () => {}, new h.model.AiRequestCancellation());
  assert.equal(h.requests[0].url, 'https://example.invalid/v1/messages');
  assert.equal(h.requests[0].options.header['x-api-key'], key);
  assert.equal(h.requests[0].options.header['anthropic-version'], '2023-06-01');
  assert.equal(h.requests[0].body.max_tokens, 120);
  assert.equal(h.requests[0].body.top_p, 0.9);
  assert.equal(reply.usage.output, 4);
  assert.equal(reply.reasoningText, '公开思考');
  AiWorkspaceService.answerTool(reply.toolCalls[0], true);
  const body = plain(AiChatProtocol.request(provider.protocol, selected, 'system', [request, reply]));
  assert.deepEqual(body.messages.at(-1).content[0],
    { type: 'tool_result', tool_use_id: 'toolu_1', content: '摘要', is_error: false });
  assert.deepEqual(body.messages.at(-2).content.slice(0, 2), [
    { type: 'thinking', thinking: '公开思考', signature: 'signed' },
    { type: 'redacted_thinking', data: 'opaque' },
  ]);
});

test('reasoning effort respects the Windows omit setting and the extra effort values', () => {
  const h = harness();
  const { AiChatProtocol } = h.load('data/network/AiChatProtocol');
  const model = new h.model.AiModelProfile();
  model.reasoningEffort = 'xhigh';
  model.thinking = 0;
  const disabled = AiChatProtocol.request(h.model.AiProtocol.ChatCompletions, model, '', []);
  assert.equal(disabled.thinking.type, 'disabled');
  assert.equal(disabled.reasoning_effort, undefined);
  model.omitReasoningEffortWhenThinkingDisabled = false;
  const forced = AiChatProtocol.request(h.model.AiProtocol.ChatCompletions, model, '', []);
  assert.equal(forced.reasoning_effort, 'xhigh');
  model.thinking = -1;
  model.reasoningEffort = 'none';
  const responses = AiChatProtocol.request(h.model.AiProtocol.Responses, model, '', []);
  assert.equal(responses.reasoning.effort, 'none');
  assert.equal(responses.thinking, undefined);
});

test('public reasoning is visible while streaming and restored without changing the text transcript', async () => {
  const h = harness();
  await h.configure(h.model.AiProtocol.ChatCompletions);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const vm = new AiWorkspaceViewModel();
  await vm.load(A, '{}');
  let finish;
  h.responses.push({ stream: event({ choices: [{ delta: { reasoning_content: '**可展开推理**' } }] }) + completion('公开回答'),
    wait: new Promise(resolve => { finish = resolve; }) });
  vm.input = '问题';
  const pending = vm.send();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(vm.previewReasoning, '**可展开推理**');
  assert.equal(vm.preview, '公开回答');
  finish();
  await pending;
  const reopened = new AiWorkspaceViewModel();
  await reopened.load(A, '{}');
  assert.equal(reopened.rows.at(-1).reasoning, '**可展开推理**');
  assert.equal(reopened.rows.at(-1).text, '公开回答');
  assert.doesNotMatch(reopened.transcript(), /可展开推理/);
});

test('model refresh preserves existing options and connection probe has no account snapshot', async () => {
  const h = harness();
  const { provider, selected } = await h.configure(h.model.AiProtocol.Responses);
  selected.temperature = 0.5;
  h.responses.push({ json: { data: [{ id: selected.model }, { id: 'other' }] } },
    { json: { error: null, output: [{ type: 'message', content: [{ text: 'OK' }] }] } });
  const { AiWorkspaceService } = h.load('service/AiWorkspaceService');
  const service = new AiWorkspaceService();
  const models = await service.refreshModels(provider, key);
  assert.equal(models[0].id, selected.id);
  assert.equal(models[0].temperature, 0.5);
  assert.equal(models[1].model, 'other');
  assert.equal(await service.testConnection(provider, selected, key), true);
  assert.equal(h.requests[0].options.method, 'GET');
  assert.equal(h.requests[1].body.stream, false);
  assert.equal(h.requests[1].body.max_output_tokens, 64);
  assert.equal(h.requests[1].body.instructions, undefined);
  assert.equal(h.requests[1].body.tools, undefined);
  assert.throws(() => AiWorkspaceService.validateEndpoint(provider.protocol, 'http://127.example.invalid/v1'), /HTTPS/);
});

test('stopping releases the request and retains partial output on the owning account', async () => {
  const h = harness();
  await h.configure(h.model.AiProtocol.ChatCompletions);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const vm = new AiWorkspaceViewModel();
  await vm.load(A, '{}');
  let resume;
  h.responses.push({ stream: event({ choices: [{ delta: { content: '部分' } }] }),
    wait: new Promise(resolve => { resume = resolve; }) });
  vm.input = '请求';
  const running = vm.send();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(vm.preview, '部分');
  await vm.load(B, '{}');
  await running;
  resume();
  assert.ok(h.requests[0].released);
  assert.equal(vm.rows.length, 0);
  assert.equal(h.AiWorkspaceStore.loadConversations(A)[0].messages.at(-1).text, '部分');
});

test('two conversations generate independently, preserve drafts and stop only the selected request', async () => {
  const h = harness();
  await h.configure(h.model.AiProtocol.ChatCompletions);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const vm = new AiWorkspaceViewModel();
  await vm.load(A, '{}');
  const firstId = vm.conversationId;
  let finishFirst;
  h.responses.push({ stream: completion('第一条回复'), wait: new Promise(resolve => { finishFirst = resolve; }) });
  vm.input = '第一条问题';
  const first = vm.send();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(vm.preview, '第一条回复');

  vm.newConversation();
  const secondId = vm.conversationId;
  assert.notEqual(secondId, firstId);
  assert.equal(vm.busy, false);
  vm.input = '第二条草稿';
  vm.selectConversation(firstId);
  assert.equal(vm.busy, true);
  assert.equal(vm.preview, '第一条回复');
  assert.equal(vm.input, '');
  vm.selectConversation(secondId);
  assert.equal(vm.input, '第二条草稿');

  let finishSecond;
  h.responses.push({ stream: event({ choices: [{ delta: { content: '第二条部分' } }] }),
    wait: new Promise(resolve => { finishSecond = resolve; }) });
  const second = vm.send();
  await new Promise(resolve => setImmediate(resolve));
  finishFirst();
  await first;
  assert.equal(vm.conversationId, secondId);
  assert.equal(vm.busy, true);
  assert.equal(vm.preview, '第二条部分');
  assert.equal(vm.rows.at(-1).text, '第二条草稿');
  vm.selectConversation(firstId);
  assert.equal(vm.busy, false);
  assert.equal(vm.rows.at(-1).text, '第一条回复');
  vm.selectConversation(secondId);
  vm.stop();
  await second;
  finishSecond();
  assert.ok(h.requests.every(request => request.released));
  assert.match(vm.error, /停止/);
  assert.equal(vm.rows.at(-1).text, '第二条部分');
  vm.selectConversation(firstId);
  assert.equal(vm.error, '');
  assert.equal(vm.rows.at(-1).text, '第一条回复');
});

test('a background tool approval belongs to its original conversation and resumes its own history', async () => {
  const h = harness();
  await h.configure(h.model.AiProtocol.ChatCompletions);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const vm = new AiWorkspaceViewModel();
  await vm.load(A, '{}');
  const firstId = vm.conversationId;
  let finishFirst;
  h.responses.push({ stream: event({ choices: [{ delta: { tool_calls: [
    { index: 0, id: 'call_one', function: { name: 'ShowSummary', arguments: '{"summary":"原会话摘要"}' } },
  ] }, finish_reason: 'tool_calls' }] }) + 'data: [DONE]\n\n', wait: new Promise(resolve => { finishFirst = resolve; }) });
  vm.input = '先汇总这一条';
  const first = vm.send();
  await new Promise(resolve => setImmediate(resolve));
  vm.newConversation();
  const secondId = vm.conversationId;
  h.responses.push({ stream: completion('另一个会话的回复') });
  vm.input = '另一个会话的问题';
  await vm.send();
  finishFirst();
  await first;
  assert.equal(vm.conversationId, secondId);
  assert.equal(vm.approvalName, '');
  assert.equal(vm.rows.at(-1).text, '另一个会话的回复');
  vm.selectConversation(firstId);
  assert.equal(vm.approvalName, 'ShowSummary');
  assert.equal(vm.approvalText, '原会话摘要');
  h.responses.push({ stream: completion('已处理原会话') });
  await vm.answerApproval(true);
  assert.equal(vm.rows.at(-1).text, '已处理原会话');
  assert.equal(h.requests[2].body.messages.at(-1).content, '原会话摘要');
  assert.doesNotMatch(JSON.stringify(h.requests[2].body.messages), /另一个会话/);
});

test('closing a workspace flushes each active conversation before same-owner reopening', async () => {
  const h = harness();
  await h.configure(h.model.AiProtocol.ChatCompletions);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const vm = new AiWorkspaceViewModel();
  await vm.load(A, '{}');
  const ids = [vm.conversationId];
  const running = [];
  const finish = [];
  for (const text of ['第一项', '第二项']) {
    h.responses.push({ stream: event({ choices: [{ delta: { reasoning_content: '推理' + text, content: text } }] }),
      wait: new Promise(resolve => { finish.push(resolve); }) });
    vm.input = '问题' + text;
    running.push(vm.send());
    await new Promise(resolve => setImmediate(resolve));
    if (ids.length === 1) {
      vm.newConversation();
      ids.push(vm.conversationId);
    }
  }

  const reopening = vm.load(A, '{}');
  const saved = h.AiWorkspaceStore.loadConversations(A);
  assert.deepEqual(ids.map(id => saved.find(record => record.id === id).messages.at(-1).text), ['第一项', '第二项']);
  await reopening;
  await Promise.all(running);
  finish.forEach(resolve => resolve());
  assert.ok(h.requests.every(request => request.released));
  for (const [index, id] of ids.entries()) {
    vm.selectConversation(id);
    assert.equal(vm.busy, false);
    assert.equal(vm.rows.length, 2);
    assert.equal(vm.rows.at(-1).reasoning, index === 0 ? '推理第一项' : '推理第二项');
  }
  assert.deepEqual(plain(h.AiWorkspaceStore.loadConversations(A)).map(record => record.messages.length), [2, 2]);
  assert.equal(h.AiWorkspaceStore.loadConversations(B).length, 0);
});

test('regeneration replaces the latest response without duplicating the last prompt', async () => {
  const h = harness();
  await h.configure(h.model.AiProtocol.ChatCompletions);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const vm = new AiWorkspaceViewModel();
  await vm.load(A, '{}');
  h.responses.push({ stream: completion('旧轮回答') }, { stream: completion('将被替换') }, { stream: completion('重生成回答') });
  vm.input = '旧轮问题';
  await vm.send();
  vm.input = '最近的问题';
  await vm.send();
  await vm.regenerate();
  assert.deepEqual(plain(vm.rows.map(row => row.text)), ['旧轮问题', '旧轮回答', '最近的问题', '重生成回答']);
  const sent = h.requests[2].body.messages.slice(1).map(message => message.content);
  assert.deepEqual(sent, ['旧轮问题', '旧轮回答', '最近的问题']);
  assert.deepEqual(plain(h.AiWorkspaceStore.loadConversations(A)[0].messages.map(message => message.text)),
    ['旧轮问题', '旧轮回答', '最近的问题', '重生成回答']);
});

test('conversation removal selects the nearest entry and keeps an unsaved blank workspace when empty', async () => {
  const h = harness();
  await h.configure(h.model.AiProtocol.ChatCompletions);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const vm = new AiWorkspaceViewModel();
  await vm.load(A, '{}');
  const draft = vm.conversationId;
  vm.newConversation();
  const oldest = vm.conversationId;
  vm.newConversation();
  const middle = vm.conversationId;
  vm.newConversation();
  const newest = vm.conversationId;
  vm.selectConversation(middle);
  vm.deleteConversation();
  assert.equal(vm.conversationId, oldest);
  assert.deepEqual(plain(vm.conversations.map(conversation => conversation.id)), [newest, oldest, draft]);
  vm.selectConversation(draft);
  vm.deleteConversation();
  assert.equal(vm.conversationId, oldest);
  vm.deleteConversation();
  assert.equal(vm.conversationId, newest);
  vm.deleteConversation();
  assert.equal(vm.conversations.length, 1);
  assert.notEqual(vm.conversationId, newest);
  assert.equal(vm.rows.length, 0);
  assert.equal(h.AiWorkspaceStore.loadConversations(A).length, 0);
});

test('Markdown handles chat formatting and keeps incomplete streamed fences as code', () => {
  const markdown = [
    '# Heading', '', '**Bold**, _italic_, ~~old~~, ==mark==, and `a < b`.', '',
    '> Quote', '', '- [x] Done', '- [ ] Next', '',
    '| Item | Count |', '| --- | ---: |', '| **A** | 2 |', '', '---', '',
    '  ```text', '# Code heading', '  indented', '',
  ].join('\n');
  const blocks = JSON.parse(parseMarkdown(markdown, '#aabbcc'));
  assert.deepEqual(blocks.map(block => block.kind), ['rich', 'rich', 'quote', 'rich', 'table', 'rule', 'code']);
  assert.match(blocks[0].html, /<h1>Heading<\/h1>/);
  assert.match(blocks[1].html, /<strong>Bold<\/strong>.*<em>italic<\/em>.*<del>old<\/del>/);
  assert.match(blocks[1].html, /background-color:#aabbcc.*mark.*font-family:monospace.*a &lt; b/);
  assert.match(blocks[3].html, /☑ Done[\s\S]*☐ Next/);
  assert.match(blocks[4].rows[1][0].html, /<strong>A<\/strong>/);
  assert.equal(blocks[4].rows[1][1].alignment, 'right');
  assert.equal(blocks.at(-1).language, 'text');
  assert.match(blocks.at(-1).text, /^# Code heading\nindented/);
  const complete = JSON.parse(parseMarkdown(markdown + '  ```\n\n## After code', '#aabbcc'));
  assert.deepEqual(complete.slice(0, 6), blocks.slice(0, 6));
  assert.equal(complete.at(-2).kind, 'code');
  assert.match(complete.at(-1).html, /<h2>After code<\/h2>/);
});

test('model Markdown only activates web links and never turns images or raw HTML into markup', () => {
  const markdown = [
    '![Image label](https://example.invalid/a.png)',
    '[link](https://example.invalid/?a=1&b=2)',
    '[file](file:///private)',
    '[script](javascript:alert%281%29)',
    'x <pre><img src=https://example.invalid/tracking.png></pre>',
    '<a href="https://example.invalid/hidden">raw HTML</a>',
  ].join('\n\n');
  const html = JSON.parse(parseMarkdown(markdown, '')).map(block => block.html).join('');
  assert.equal([...html.matchAll(/<a href=/g)].length, 2);
  assert.match(html, /<a href="https:\/\/example.invalid\/a.png">Image label<\/a>/);
  assert.match(html, /\?a=1&amp;b=2/);
  assert.match(html, /&lt;img src=/);
  assert.match(html, /&lt;a href=/);
  assert.doesNotMatch(html, /<(?:img|pre|script)\b|href="(?:file|javascript):/);
});

test('system analysis uses the compact snapshot for over-limit UTF-8 and sends no remote request', async () => {
  const h = harness();
  h.prefs.set('ai.provider', 0);
  const { AiWorkspaceViewModel } = h.load('viewmodel/AiWorkspaceViewModel');
  const vm = new AiWorkspaceViewModel();
  await vm.load(A, '长'.repeat(1800), '{"summary":"端侧"}');
  await vm.runSystemAnalysis();
  assert.equal(vm.localContent, '端侧结果');
  assert.match(h.localPrompt(), /"summary":"端侧"/);
  assert.equal(h.requests.length, 0);
});

test('anonymous snapshot reuses observed pull intervals and metadata-backed featured history', async () => {
  const h = harness();
  const warnings = [];
  const wish = (index, gachaType, rankType, itemId, name) => ({ gachaId: String(index), gachaType, rankType, itemId, name,
    time: `2026-10-05 10:00:0${index}`, itemType: '角色' });
  const items = [wish(1,301,3,11001,'素材'),wish(2,301,5,10000001,'常驻角色'),wish(3,400,4,10000003,'四星角色'),
    wish(4,400,3,11001,'素材'),wish(5,400,5,10000002,'活动角色'),wish(6,301,3,11001,'素材'),wish(7,20011,1,250013,'衣饰')];
  const banner = type => ({ type, from: Date.parse('2026-10-05T00:00:00Z'), to: Date.parse('2026-10-06T00:00:00Z'),
    version: 'fixture', name: '活动', upOrange: [10000002], upPurple: [], banner: '' });
  Object.assign(h.mocks, {
    'data/repo/GachaRepo': { GachaRepo: { getAllArchives: async () => [{ id: 1, uid: A }], getItemsByArchive: async () => items } },
    'data/repo/SpiralAbyssRepo': { SpiralAbyssRepo: { listHistory: async () => [] } },
    'data/repo/RoleCombatRepo': { RoleCombatRepo: { listHistory: async () => [] } },
    'data/repo/HardChallengeRepo': { HardChallengeRepo: { listHistory: async () => [] } },
    'model/RoleCombat': {}, 'model/HardChallenge': {},
    'common/Constants': { RegionUtil: { regionOfUid: () => 'cn_gf01' } },
    'common/Logger': { Logger: { info() {}, warn(_tag, message) { warnings.push(message); } } },
    'service/UigfService': { UigfService: { timezoneOfUid: () => 8,
      normalizeTime: time => new Date(time.replace(' ', 'T') + '+08:00').toISOString().slice(0, 19).replace('T', ' ') } },
    'service/WishHistoryService': { WishHistoryService: { dateText: time => new Date(time).toISOString().slice(0, 10) } },
    'service/WikiMetaService': { WikiMetaService: { getGachaEvents: async () => [banner(301), banner(400)],
      getAvatars: async () => [{ id: 10000002, name: '活动角色', icon: '' }], getWeapons: async () => [] } },
    'service/GameDataService': { GameDataService: { getInstance: () => ({ remoteVersion: () => '' }) } },
    'service/LocalizedGameDataService': { LocalizedGameDataService: { names: async () => new Map() } },
  });
  const { AccountInsightsService } = h.load('service/AccountInsightsService');
  const bundle = await AccountInsightsService.getInstance().build(A);
  assert.deepEqual(warnings, []);
  const text = AccountInsightsService.anonymousJson(bundle);
  assert.ok(!text.includes(A));
  const output = JSON.parse(text);
  const stats = output.hu_tao_computed_gacha_statistics;
  assert.equal(stats.pools.length, 7);
  const avatar = stats.pools.find(pool => pool.pool === 'avatar_event');
  assert.equal(avatar.total_wishes, 6);
  assert.equal(avatar.average_wishes_per_five_star, 2.5);
  assert.equal(avatar.current_wishes_since_last_five_star, 1);
  assert.deepEqual(avatar.recorded_five_star_obtains.map(row => [row.name, row.is_featured, row.is_guaranteed]),
    [['活动角色', true, true], ['常驻角色', false, null]]);
  assert.equal(stats.pools.find(pool => pool.pool === 'beyond_event').total_wishes, 1);
  assert.ok(stats.recent_banner_featured_characters_and_weapons.some(banner =>
    banner.featured_five_stars.some(wish => wish.name === '活动角色' && wish.recorded_obtain_count === 1)));
  assert.deepEqual(plain(bundle.featuredChart.points), [{ period: '活动角色', value: 1 }]);
  assert.equal(JSON.parse(AccountInsightsService.anonymousJson(bundle, false)).hu_tao_computed_gacha_statistics, undefined);
});
