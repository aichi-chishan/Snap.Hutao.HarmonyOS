// Deterministic login lifecycle regressions; no real credentials, network or clock sleeps.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
async function flush() { for (let i = 0; i < 12; i++) await Promise.resolve(); }
function compile(file, requireMock, globals = {}, transform = source => source) {
  const source = transform(fs.readFileSync(file, 'utf8'));
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true }
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(`(function(require,module,exports){${output}\n})`, globals)(requireMock, module, module.exports);
  return module.exports;
}
function harness() {
  let now = 100000, timerId = 0, revision = 0, completed = 0;
  const timeouts = new Map(), intervals = new Map();
  const calls = { create: [], query: [], captcha: [], mobile: [], login: [], cancel: [] };
  function request(kind, args) {
    const gate = deferred(); calls[kind].push({ args, gate }); return gate.promise;
  }
  function login(kind, args) { revision++; return request('login', [kind, ...args]); }
  const service = {
    createQrLogin: () => request('create', []),
    queryQrLoginStatus: ticket => request('query', [ticket]),
    createLoginCaptcha: mobile => request('captcha', [mobile]),
    requestMobileLogin: (...args) => request('mobile', args),
    loginWithQrResult: result => login('qr', [result]),
    loginWithSession: (...args) => login('session', args),
    loginWithCookie: (...args) => login('cookie', args),
    sessionRevision: () => revision,
    cancelPendingLogin: value => calls.cancel.push(value),
  };
  const exports = compile('entry/src/main/ets/viewmodel/LoginViewModel.ets', id => {
    if (id.endsWith('/UserService')) return { UserService: { getInstance: () => service } };
    throw Error(`Unexpected runtime dependency ${id}`);
  }, {
    Observed: target => target,
    Date: { now: () => now },
    setTimeout: callback => { const id = ++timerId; timeouts.set(id, callback); return id; },
    clearTimeout: id => timeouts.delete(id),
    setInterval: callback => { const id = ++timerId; intervals.set(id, callback); return id; },
    clearInterval: id => intervals.delete(id),
  });
  const model = new exports.LoginViewModel();
  return {
    model, mode: exports.LoginMode, calls, timeouts, intervals,
    activate: () => model.activate(() => { completed++; }),
    completed: () => completed,
    firePoll: async () => {
      assert.equal(timeouts.size, 1, 'only the current QR owns a poll timer');
      const [id, callback] = timeouts.entries().next().value;
      timeouts.delete(id); callback(); await flush();
    },
    advance: async ms => { now += ms; for (const callback of [...intervals.values()]) callback(); await flush(); },
  };
}
const qr = ticket => ({ url: `https://fixture.test/${ticket}`, ticket });
const captcha = { actionType: 'login', countdown: 3 };
const session = { stuid: 'fixture-id', stoken: 'fixture-token', mid: 'fixture-mid', accountName: 'Fixture' };

async function qrOwnership() {
  const h = harness(); h.activate();
  assert.equal(h.calls.create.length, 1, 'opening the page starts QR creation');
  const refresh = h.model.refreshQr();
  h.calls.create[1].gate.resolve(qr('new')); await refresh;
  h.calls.create[0].gate.resolve(qr('old')); await flush();
  assert.equal(h.model.qrUrl, qr('new').url);
  await h.firePoll();
  assert.deepEqual(h.calls.query[0].args, ['new']);
  const next = h.model.refreshQr();
  h.calls.query[0].gate.resolve({ status: 'Confirmed' }); await flush();
  assert.equal(h.calls.login.length, 0, 'old confirmation cannot log in after refresh');
  h.calls.create[2].gate.resolve(qr('latest')); await next;
  h.model.selectMode(h.mode.MobileCaptcha);
  assert.equal(h.timeouts.size, 0);
  h.model.selectMode(h.mode.Qr);
  h.model.deactivate();
  h.calls.create[3].gate.resolve(qr('detached')); await flush();
  assert.notEqual(h.model.qrUrl, qr('detached').url);
  assert.equal(h.timeouts.size, 0, 'late create response cannot restart a disposed timer');
}

async function qrStatusesAndCancel() {
  const h = harness(); h.activate();
  h.calls.create[0].gate.resolve(qr('first')); await flush();
  await h.firePoll(); h.calls.query[0].gate.resolve({ status: 'Created' }); await flush();
  assert.match(h.model.qrHint, /请使用/);
  await h.firePoll(); h.calls.query[1].gate.resolve({ status: 'Scanned' }); await flush();
  assert.match(h.model.qrHint, /已扫码/);
  await h.firePoll(); h.calls.query[2].gate.resolve({ status: 'Expired' }); await flush();
  assert.equal(h.calls.create.length, 2, 'expiry creates a new QR without message matching');
  assert.equal(h.timeouts.size, 0);
  h.calls.create[1].gate.resolve(qr('replacement')); await flush();
  await h.firePoll(); h.calls.query[3].gate.reject(Error('offline')); await flush();
  assert.equal(h.timeouts.size, 1, 'temporary query failure retains one polling loop');
  await h.firePoll(); h.calls.query[4].gate.resolve({ status: 'Confirmed' }); await flush();
  assert.equal(h.calls.login.length, 1);
  await h.model.refreshQr(); h.model.selectMode(h.mode.Manual);
  assert.equal(h.calls.create.length, 2, 'accepted login cannot be refreshed or submitted twice');
  assert.equal(h.model.mode, h.mode.Qr);
  h.model.deactivate();
  assert.deepEqual(h.calls.cancel, [1]);
  h.calls.login[0].gate.resolve({ displayName: 'Old page' }); await flush();
  assert.equal(h.completed(), 0, 'closing before account synchronization finishes cannot navigate');
}

async function captchaOwnership() {
  const h = harness(); h.model.mode = h.mode.MobileCaptcha; h.activate();
  h.model.updateMobile('abcdefghijk'); await h.model.sendCaptcha();
  assert.equal(h.calls.captcha.length, 0, 'length alone is not a phone number');
  h.model.updateMobile('13800000000');
  const send = h.model.sendCaptcha(); await h.model.sendCaptcha();
  h.model.selectMode(h.mode.Manual);
  assert.equal(h.calls.captcha.length, 1);
  assert.equal(h.model.mode, h.mode.MobileCaptcha);
  h.model.deactivate(); h.calls.captcha[0].gate.resolve(captcha); await send;
  assert.equal(h.intervals.size, 0, 'late SMS response cannot create a timer after detach');
  h.activate();
  const sent = h.model.sendCaptcha(); h.calls.captcha[1].gate.resolve(captcha); await sent;
  assert.equal(h.model.countdown, 3);
  await h.advance(2100); assert.equal(h.model.countdown, 1, 'countdown follows elapsed time');
  h.model.updateMobile('13900000000'); h.model.captchaInput = '123456';
  await h.model.submitCaptcha();
  assert.equal(h.calls.mobile.length, 0, 'a captcha action belongs to its original mobile number');
  await h.advance(1000); assert.equal(h.intervals.size, 0);
  const resend = h.model.sendCaptcha(); h.calls.captcha[2].gate.resolve(captcha); await resend;
  h.model.captchaInput = '123456';
  const submit = h.model.submitCaptcha(); await h.model.submitCaptcha();
  assert.equal(h.calls.mobile.length, 1);
  h.model.deactivate();
  assert.equal(h.intervals.size, 0, 'page disposal clears the active SMS countdown');
  h.calls.mobile[0].gate.resolve(session); await submit;
  assert.equal(h.calls.login.length, 0, 'a stale SMS login result is not saved');
}

async function cookieSubmission() {
  const h = harness(); h.model.mode = h.mode.Manual; h.activate();
  const pending = h.model.loginWithCookie('fixture'); await h.model.loginWithCookie('again');
  assert.equal(h.calls.login.length, 1);
  h.model.deactivate();
  assert.deepEqual(h.calls.cancel, [1]);
  h.activate();
  const current = h.model.loginWithCookie('current');
  h.calls.login[0].gate.reject(Error('cancelled')); await pending;
  assert.equal(h.model.busy, true, 'an older completion cannot unlock a newer submission');
  h.calls.login[1].gate.resolve({ displayName: 'Current' }); await current;
  assert.equal(h.completed(), 1);
  assert.equal(h.timeouts.size, 0, 'success has no delayed router callback');
  await h.model.loginWithCookie('third');
  assert.equal(h.calls.login.length, 2);
}

async function expiryProtocol() {
  const exports = compile('entry/src/main/ets/data/network/PassportClient.ets', id => {
    if (id.endsWith('/Constants')) return { AppConstants: {} };
    if (id.endsWith('/Logger')) return { Logger: { info() {}, warn() {} } };
    return {};
  });
  exports.PassportClient.postJsonRaw = async () => ({ retcode: -3501, success: false, message: 'QR expired' });
  assert.equal((await exports.PassportClient.queryQrLoginStatus('fixture')).status, 'Expired');
  exports.PassportClient.postJsonRaw = async () => ({ retcode: -2, success: false, userFriendlyMessage: () => 'offline' });
  await assert.rejects(exports.PassportClient.queryQrLoginStatus('fixture'), /offline/);
}

function pageNavigation() {
  class LoginModel {
    activate(callback) { this.callback = callback; this.active = true; }
    deactivate() { this.active = false; }
    hasCompleted() { return this.completed === true; }
    complete() { if (this.active) { this.completed = true; this.callback(); } }
  }
  const exports = compile('entry/src/main/ets/pages/LoginPage.ets', id => {
    if (id === '@kit.ArkWeb') return { webview: { WebviewController: class {} } };
    if (id.endsWith('/LoginViewModel')) return { LoginViewModel: LoginModel };
    if (id.endsWith('/UiSurface')) return { UiSurface: { dialogMaterial: () => undefined } };
    return {};
  }, { State: () => {}, StorageProp: () => () => {} }, source => {
    const prefix = source.slice(0, source.indexOf('  @Builder'));
    return prefix.replace(/@Entry\s*@Component\s*struct LoginPage/, 'export class LoginPage') + '}';
  });
  let backs = 0, toasts = 0;
  const page = new exports.LoginPage();
  page.getUIContext = () => ({
    getRouter: () => ({ back: () => { backs++; page.onPageHide(); } }),
    getPromptAction: () => ({ showToast: () => { toasts++; } }),
  });
  page.aboutToAppear(); page.onPageShow(); page.onPageHide();
  assert.equal(page.vm.active, true, 'backgrounding to scan keeps the current request alive');
  page.vm.complete();
  assert.equal(backs, 0, 'a covered/background login page cannot pop another page');
  assert.equal(toasts, 0);
  page.onPageShow();
  assert.equal(backs, 1, 'returning to the completed login page finishes its own navigation');
  page.aboutToDisappear(); page.vm.complete();
  assert.equal(backs, 1, 'a destroyed page never returns later');
}

(async () => {
  await qrOwnership(); await qrStatusesAndCancel(); await captchaOwnership(); await cookieSubmission(); await expiryProtocol();
  pageNavigation();
  const page = fs.readFileSync('entry/src/main/ets/pages/LoginPage.ets', 'utf8');
  assert(!/PassportClient|UserService|isOversea|hoyolab\.com|setTimeout/.test(page));
  assert(page.includes('this.vm.activate(') && page.includes('this.vm.deactivate()'));
  console.log('login-lifecycle: PASS (QR ownership/expiry, SMS phone ownership/timers, duplicate submission, detach and navigation)');
})().catch(error => { console.error(error); process.exitCode = 1; });
