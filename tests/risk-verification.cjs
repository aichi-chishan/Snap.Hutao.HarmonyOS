const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const deferred = () => { let resolve; const promise = new Promise(r => resolve = r); return { promise, resolve }; };
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };

function harness(solve, serviceMocks = {}) {
  const storage = new Map(), modules = new Map(), sent = [], html = [], timers = new Map();
  const mocks = {
    '@kit.ArkWeb': { webview: { WebviewController: class {
      registerJavaScriptProxy() {}
      loadData(content) { html.push(content); }
    } } },
    '@kit.ArkUI': {}, '@kit.BasicServicesKit': { deviceInfo: { apiAvailable: () => true } },
    'common/Logger': { Logger: { info() {}, warn() {}, error() {} } },
    'common/UiSurface': { UiSurface: { material: () => undefined }, SurfaceClass: {} },
    'common/Constants': { AppConstants: {}, RetCodes: { OK: 0, RISK_CONTROL: 1034 } },
    'data/prefs/PreferencesStore': { PreferencesStore: { getString: () => '' } },
    'data/network/DsSigner': { DsSigner: { nowTimestamp: () => 1, randomNumber: () => '1',
      sortQuery: () => 'is_high=true', signGen2: async () => 'ds' } },
    'data/network/AigisSession': { AigisSession: { parse: text => JSON.parse(text),
      buildAigisHeader: (sessionId, challenge, validate) => JSON.stringify({ sessionId, challenge, validate }) } },
    'data/network/ApiClient': { ApiClient: { getInstance: () => ({
      get: async (_url, headers) => ({ success: true, data: { gt: 'gt', challenge: headers['x-rpc-challenge_path'] } }),
      postJson: async (_url, body, headers) => {
        sent.push({ body: JSON.parse(body), headers });
        return { success: true, data: { challenge: headers['x-rpc-challenge_path'] + ':accepted' } };
      },
    }) } },
    ...serviceMocks,
  };
  if (solve) mocks['service/RiskVerifyService'] = { RiskVerifyService: { getInstance: () => ({ verifyGtFull: solve }) } };
  const globals = { AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    StorageProp: () => () => {}, StorageLink: () => () => {}, Watch: () => () => {}, State: () => {},
    setTimeout: callback => { const id = timers.size + 1; timers.set(id, callback); return id; },
    clearTimeout: id => timers.delete(id),
  };
  function load(name) {
    if (mocks[name]) return mocks[name];
    if (modules.has(name)) return modules.get(name);
    let source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8').replaceAll('\r\n', '\n');
    if (name === 'components/RiskVerifyModal') {
      source = source.slice(0, source.indexOf('  build() {')) + '}';
      source = source.replace(/@Builder\s+export function buildRiskVerifyOverlay\(\) \{[\s\S]*?\n\}/, '')
        .replace('@Component\n', '').replace('export struct RiskVerifyModal', 'export class RiskVerifyModal');
    }
    const compiled = ts.transpileModule(source, { reportDiagnostics: true,
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true } });
    assert.equal(compiled.diagnostics.length, 0, name);
    const module = { exports: {} };
    vm.runInNewContext(compiled.outputText, { ...globals, module, exports: module.exports, require: id =>
      load(id.startsWith('@') ? id : path.posix.normalize(path.posix.join(path.posix.dirname(name), id))) });
    modules.set(name, module.exports);
    return module.exports;
  }
  return { load, storage, sent, html, timers };
}

test('custom verification checks its own code before accepting challenge and validate', async () => {
  let code = 0;
  const data = { challenge: 'custom-challenge', validate: 'custom-valid' };
  const h = harness(undefined, {
    'data/prefs/PreferencesStore': { PreferencesStore: { getString: () => 'https://solver.example/?gt={0}&challenge={1}' } },
    'data/network/ApiClient': { ApiClient: { getInstance: () => ({
      get: async () => ({ success: true, data, raw: JSON.stringify({ code, data }) }),
    }) } },
  });
  const service = h.load('service/RiskVerifyService').RiskVerifyService.getInstance();
  assert.equal((await service.verifyGtFull('gt', 'initial')).challenge, 'custom-challenge');
  assert.equal(service.hasPending(), false);
  code = 9;
  const pending = service.verifyGtFull('gt', 'initial'); await flush();
  assert.equal(service.hasPending(), true);
  service.submitValidate('manual', 'manual-challenge', service.snapshot().seq);
  assert.equal((await pending).validate, 'manual');
});

test('browser challenge and validate reach the original game-record request', async () => {
  const h = harness();
  const service = h.load('service/RiskVerifyService').RiskVerifyService.getInstance();
  const pending = service.verifyGtFull('gt', 'initial'); await flush();
  service.submitValidate('solution', 'browser-challenge', service.snapshot().seq);
  const result = await pending;
  assert.equal(result.challenge, 'browser-challenge');
  assert.equal(result.validate, 'solution');
  assert.equal(h.timers.size, 0);
  const aigis = service.verifyAigis(JSON.stringify({ sessionId: 'session', gt: 'gt', challenge: 'aigis-initial' }));
  await flush(); service.submitValidate('aigis-solution', 'aigis-browser', service.snapshot().seq);
  assert.deepEqual(JSON.parse(await aigis), { sessionId: 'session', challenge: 'aigis-browser', validate: 'aigis-solution' });
});

test('sign-in body verification replays the solved values and a superseded session cannot replay', async () => {
  let live = true;
  const result = deferred();
  const h = harness((_gt, challenge) => challenge === 'initial' ? result.promise : Promise.resolve({ challenge: '', validate: '' }), {
    'service/UserService': { UserService: {} },
    'service/ChallengeSession': { ChallengeSession: {} },
    'data/network/HoyolabClient': { HoyolabClient: {} },
  });
  const { ApiResponse } = h.load('model/ApiResponse');
  const { SignInService } = h.load('service/SignInService');
  const owner = { uid: '100000001', region: 'cn_gf01', assertCurrent() { if (!live) throw Error('session switched'); } };
  const original = ApiResponse.fromJson(JSON.stringify({ retcode: 0, data: { success: 1, gt: 'gt', challenge: 'initial' } }));
  const sends = [];
  const replay = async (uid, region, cookie, headers) => {
    sends.push({ uid, region, cookie, headers });
    return ApiResponse.fromJson('{"retcode":0}');
  };
  const pending = SignInService.resolveSignRisk(owner, 'owner-cookie', original, 'event/luna/sign', replay);
  result.resolve({ challenge: 'solved-challenge', validate: 'solved-validate' });
  await pending;
  assert.equal(sends.length, 1);
  assert.equal(sends[0].headers['x-rpc-challenge'], 'solved-challenge');
  assert.equal(sends[0].headers['x-rpc-validate'], 'solved-validate');
  assert.equal(sends[0].headers['x-rpc-seccode'], 'solved-validate|jordan');
  const superseded = SignInService.resolveSignRisk(owner, 'owner-cookie', original, 'event/luna/sign', replay);
  live = false;
  await assert.rejects(superseded, /session switched/);
  assert.equal(sends.length, 1);
});

test('a closed captcha cannot resolve the following request', async () => {
  const h = harness();
  const service = h.load('service/RiskVerifyService').RiskVerifyService.getInstance();
  const first = service.verifyGt('gt', 'one'); const old = service.snapshot().seq;
  service.cancel(); assert.equal(await first, '');
  const second = service.verifyGt('gt', 'two'); const current = service.snapshot().seq;
  service.submitValidate('stale', 'old-challenge', old);
  service.cancel(old);
  assert.equal(service.hasPending(), true);
  assert.equal(service.snapshot().challenge, 'two');
  service.submitValidate('current', 'current-challenge', current);
  assert.equal(await second, 'current');
});

test('concurrent 1034 verification keeps each path, cookie and result together', async () => {
  const a = deferred(), b = deferred();
  const h = harness((_gt, challenge) => challenge === '/a' ? a.promise : b.promise);
  const verifier = h.load('data/network/RiskVerifier').RiskVerifier;
  const first = verifier.resolveGtChallenge('cookie-a', '/a');
  const second = verifier.resolveGtChallenge('cookie-b', '/b');
  await flush();
  b.resolve({ challenge: 'b-new', validate: 'b-valid' });
  assert.equal(await second, '/b:accepted');
  a.resolve({ challenge: 'a-new', validate: 'a-valid' });
  assert.equal(await first, '/a:accepted');
  assert.deepEqual(h.sent.map(row => [row.headers['x-rpc-challenge_path'], row.headers.Cookie,
    row.body.geetest_challenge, row.body.geetest_seccode]),
  [['/b', 'cookie-b', 'b-new', 'b-valid|jordan'], ['/a', 'cookie-a', 'a-new', 'a-valid|jordan']]);
});

test('overlay loads each request after controller attachment and fits narrow windows', async () => {
  const h = harness();
  const service = h.load('service/RiskVerifyService').RiskVerifyService.getInstance();
  const Modal = h.load('components/RiskVerifyModal').RiskVerifyModal;
  const modal = new Modal();
  modal.availW = 360; assert.equal(modal.panelWidth(), 336);
  modal.availW = 240; assert.equal(modal.panelWidth(), 216);
  modal.availW = 1000; assert.equal(modal.panelWidth(), 480);
  const first = service.verifyGt('gt', 'one');
  modal.req = service.snapshot(); modal.isShow = true; modal.onVerifyStateChanged();
  assert.equal(h.html.length, 0, 'no Web API call before the controller binds');
  modal.webAttached = true; modal.startLoad(); assert.equal(h.html.length, 1);
  const old = modal.loadedSequence;
  service.cancel(); await first;
  const second = service.verifyGtFull("gt'</script>", 'two'); await flush();
  modal.req = service.snapshot(); modal.onVerifyStateChanged();
  assert.equal(h.html.length, 1, 'next request waits for its own Web controller');
  modal.webAttached = true; modal.startLoad();
  assert.equal(h.html.length, 2);
  assert.ok(!h.html[1].includes("gt'</script>"));
  modal.onVerifyStateChanged(); assert.equal(h.html.length, 2);
  modal.handleValidate(JSON.stringify({ request_seq: old, geetest_validate: 'stale' }));
  assert.equal(service.hasPending(), true);
  modal.handleValidate(JSON.stringify({ request_seq: modal.loadedSequence, geetest_validate: 'valid', geetest_challenge: 'returned' }));
  assert.equal((await second).challenge, 'returned');
});

test('captcha fitting includes its offset and restores full size after the window grows', () => {
  const h = harness();
  const Modal = h.load('components/RiskVerifyModal').RiskVerifyModal;
  const content = new Modal().buildHtml('gt', 'challenge');
  const functions = content.slice(content.indexOf('  function measure()'), content.indexOf('  var fitTimer'));
  const body = { style: { zoom: '1' } };
  const web = { innerWidth: 400, innerHeight: 260, getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }) };
  const element = { getBoundingClientRect: () => {
    const z = Number(body.style.zoom);
    return { left: 0, right: 344 * z, top: 12 * z, bottom: 267 * z, width: 344 * z, height: 255 * z };
  } };
  const scope = { window: web, document: { body, querySelectorAll: () => [element] } };
  vm.createContext(scope); vm.runInContext(functions, scope);
  scope.fit(); assert.ok(element.getBoundingClientRect().bottom <= web.innerHeight);
  web.innerWidth = 200; web.innerHeight = 200; scope.fit();
  assert.ok(element.getBoundingClientRect().right <= 200);
  web.innerWidth = 400; web.innerHeight = 430; scope.fit();
  assert.equal(Number(body.style.zoom), 1);
});
