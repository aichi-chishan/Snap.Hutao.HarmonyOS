const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/pages/SettingPage.ets', 'utf8');
function method(name) {
  const match = new RegExp('^  (?:(?:private|async)\\s+)*' + name + '\\([^\\n]*', 'm').exec(source); assert(match, name);
  const start = match.index; let at = source.indexOf('{', start), depth = 0, quote = '', line = false, block = false;
  for (let i = at; i < source.length; i++) {
    const c = source[i], n = source[i + 1];
    if (line) { if (c === '\n') line = false; continue; }
    if (block) { if (c === '*' && n === '/') { block = false; i++; } continue; }
    if (quote) { if (c === '\\') { i++; continue; } if (c === quote) quote = ''; continue; }
    if (c === '/' && n === '/') { line = true; i++; continue; }
    if (c === '/' && n === '*') { block = true; i++; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth++;
    if (c === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw Error(name);
}
const names = ['attachDataUpdates', 'applyDataUpdateStatus', 'dataActionBlocked', 'refreshDataState', 'checkDataUpdate',
  'updateGameData', 'cancelGameData', 'applyDataUrl', 'changeSavedData', 'aboutToDisappear'];
const code = ts.transpileModule('export class Page {\n' + names.map(method).join('\n') + '\n}', {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, reportDiagnostics: true,
}); assert.equal(code.diagnostics.length, 0);
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const idle = () => ({ id: 0, state: 'idle', done: 0, total: 0, current: '', bytes: 0, activeFiles: 0, error: '', canCancel: false, settled: true });
function harness() {
  const check = deferred(), update = deferred(), dialog = deferred(), rollback = deferred(), cancel = deferred();
  const state = { active: 'v1', pending: 'none', next: 'v2', canRollback: true, checks: 0, updates: 0, resets: 0,
    rollbacks: 0, dialogs: 0, source: 'trusted', cancellations: [], status: idle(), listeners: new Set() };
  const emit = values => { state.status = { ...state.status, ...values }; for (const listener of [...state.listeners]) listener({ ...state.status }); };
  const svc = { remoteVersion: () => state.active, pendingState: () => state.pending, pendingVersion: () => state.next,
    canRollback: () => state.canRollback, checkUpdateAvailable: () => { state.checks++; return check.promise; },
    updateAll: () => { state.updates++; if (state.admissionError) return Promise.reject(Error('another writer owns admission')); emit({ ...idle(), id: state.status.id + 1, state: 'preparing', settled: false, canCancel: true }); return update.promise; } };
  const G = { getInstance: () => svc, updateStatus: () => ({ ...state.status }),
    subscribeUpdate: listener => { state.listeners.add(listener); listener({ ...state.status }); return () => state.listeners.delete(listener); },
    cancelUpdate: id => { state.cancellations.push(id); if (id !== state.status.id || state.status.settled) return Promise.resolve({ ...state.status });
      emit({ state: 'cancelling', canCancel: false }); return cancel.promise; },
    clearRemote: () => { state.resets++; state.pending = 'bundled'; }, rollbackRemote: () => { state.rollbacks++; return rollback.promise; } };
  const U = { setManifestUrl: url => { if (url !== 'trusted-new') throw Error('untrusted source'); state.source = url; }, manifestUrl: () => state.source };
  const m = { exports: {} }; vm.runInNewContext(`(function(exports){${code.outputText}\n})`, { GameDataService: G, GameDataUpdater: U, $r: x => x })(m.exports);
  const toasts = [], writes = [];
  const page = new m.exports.Page();
  Object.assign(page, { dataViewActive: false, dataGeneration: 0, dataOperationId: 0, dataCheckPending: false, dataUpdatePending: false,
    dataConfirmationPending: false, dataCancelPending: false, dataBusy: false, dataChecking: false, dataVersion: 'v1', dataPending: '',
    dataHasUpdate: '', dataDone: 0, dataTotal: 0, dataUrl: 'trusted', dataCanCancel: false, dataCancelling: false, dataPhase: '',
    urlInput: '', showUrlEdit: true, toast: t => toasts.push(t),
    getUIContext: () => ({ getPromptAction: () => ({ showDialog: () => { state.dialogs++; return dialog.promise; } }) }) });
  // Detect @State writes after disappearance, including late Promise/finally callbacks.
  const stateNames = [...source.matchAll(/@State\s+(\w+):/g)].map(match => match[1]);
  for (const name of stateNames) {
    let value = page[name]; Object.defineProperty(page, name, { get: () => value, set: next => { if (!page.dataViewActive) writes.push(name); value = next; }, configurable: true });
  }
  page.attachDataUpdates();
  return { page, state, toasts, writes, emit, check, update, dialog, rollback, cancel,
    finish: (kind = 'completed') => { state.pending = kind === 'completed' ? 'remote' : state.pending;
      emit({ state: kind, settled: true, canCancel: false, activeFiles: 0 });
      if (kind === 'completed') update.resolve('v2'); else update.reject(Error(kind));
      cancel.resolve({ ...state.status }); } };
}
let count = 0;
async function test(name, run) { await run(); console.log(`PASS ${++count}: ${name}`); }
(async () => {
  await test('duplicate actions stay blocked and whole-update success is restart-only', async () => {
    const h = harness(), pending = h.page.updateGameData(); await h.page.updateGameData(); await h.page.checkDataUpdate();
    assert.equal(h.state.updates, 1); assert.equal(h.state.checks, 0);
    h.emit({ state: 'downloading', done: 2, total: 9, activeFiles: 4 }); assert.equal(h.page.dataDone, 2); assert.match(h.page.dataPhase, /4.*2\/9/);
    h.finish(); await pending; assert.equal(h.page.dataVersion, 'v1'); assert.match(h.page.dataPending, /v2/);
    assert.match(h.page.dataHasUpdate, /重启/); assert.equal(h.page.dataBusy, false);
  });
  await test('a pre-admission rejection cannot be overwritten by an older completed status', async () => {
    const h = harness(); h.emit({ id: 3, state: 'completed', settled: true }); h.state.admissionError = true;
    await h.page.updateGameData(); assert.match(h.page.dataHasUpdate, /更新未完成.*another writer/); assert.equal(h.page.dataBusy, false);
  });
  await test('detach removes observer and late update completion never writes torn-down State', async () => {
    const h = harness(), pending = h.page.updateGameData(); h.page.aboutToDisappear();
    assert.equal(h.state.listeners.size, 0); h.emit({ done: 8, total: 9 }); h.finish(); await pending;
    assert.equal(h.toasts.length, 0); assert.deepEqual(h.writes, []); assert.equal(h.page.dataUpdatePending, false);
  });
  await test('reopening catches up to active work and receives terminal state without the original callback', async () => {
    const h = harness(), pending = h.page.updateGameData(); h.page.aboutToDisappear(); h.emit({ state: 'downloading', done: 5, total: 9, activeFiles: 3 });
    h.page.attachDataUpdates(); assert.equal(h.page.dataBusy, true); assert.equal(h.page.dataDone, 5); assert.equal(h.state.listeners.size, 1);
    h.page.attachDataUpdates(); assert.equal(h.state.listeners.size, 1); h.finish(); await pending;
    assert.equal(h.page.dataBusy, false); assert.match(h.page.dataHasUpdate, /已完成/); assert.equal(h.toasts.length, 0);
  });
  await test('a check finishing after detach neither publishes text nor writes State', async () => {
    const h = harness(), pending = h.page.checkDataUpdate(); await h.page.checkDataUpdate(); assert.equal(h.state.checks, 1);
    h.page.aboutToDisappear(); h.check.resolve(true); await pending; assert.equal(h.page.dataHasUpdate, ''); assert.deepEqual(h.writes, []);
  });
  await test('source validation errors stay visible and an active external updater blocks edits', async () => {
    const h = harness(); h.page.urlInput = 'http://bad'; h.page.applyDataUrl(); assert.equal(h.state.source, 'trusted'); assert.match(h.toasts[0], /未更改/);
    h.page.urlInput = 'trusted-new'; h.page.applyDataUrl(); assert.equal(h.page.dataUrl, 'trusted-new');
    h.emit({ id: 1, state: 'preparing', settled: false, canCancel: true }); h.page.urlInput = 'blocked'; h.page.applyDataUrl(); assert.equal(h.state.source, 'trusted-new');
  });
  await test('reset confirmation is duplicate-safe and detached confirmation does not act', async () => {
    const h = harness(), pending = h.page.changeSavedData(false); await h.page.changeSavedData(false); assert.equal(h.state.dialogs, 1);
    h.page.aboutToDisappear(); h.dialog.resolve({ index: 1 }); await pending; assert.equal(h.state.resets, 0); assert.deepEqual(h.writes, []);
  });
  await test('declined reset is inert, confirmed reset remains next-launch only', async () => {
    for (const index of [0, 1]) {
      const h = harness(), pending = h.page.changeSavedData(false); h.dialog.resolve({ index }); await pending;
      assert.equal(h.state.resets, index); assert.equal(h.page.dataVersion, 'v1'); assert.equal(h.page.dataConfirmationPending, false);
      if (index) assert.match(h.page.dataPending, /内置.*重启/);
    }
  });
  await test('rollback without a verified candidate reports unavailable and releases page busy state', async () => {
    const h = harness(), pending = h.page.changeSavedData(true); h.dialog.resolve({ index: 1 }); await new Promise(setImmediate); h.rollback.resolve(false); await pending;
    assert.match(h.toasts[0], /没有可用/); assert.equal(h.page.dataBusy, false);
  });
  await test('an updater starting while a reset dialog is open prevents the reset call', async () => {
    const h = harness(), pending = h.page.changeSavedData(false); h.emit({ id: 1, state: 'preparing', settled: false });
    h.dialog.resolve({ index: 1 }); await pending; assert.equal(h.state.resets, 0); assert.equal(h.page.dataBusy, true);
  });
  await test('repeated cancel is ID-bound and busy stays true until all work settles', async () => {
    const h = harness(), running = h.page.updateGameData(); h.emit({ state: 'downloading', done: 3, total: 9, activeFiles: 4 });
    const stop = h.page.cancelGameData(); await h.page.cancelGameData(); assert.equal(h.state.dialogs, 1);
    h.dialog.resolve({ index: 1 }); await new Promise(setImmediate); assert.deepEqual(h.state.cancellations, [1]);
    assert.equal(h.page.dataBusy, true); assert.equal(h.page.dataCanCancel, false); assert.match(h.page.dataPhase, /等待/);
    h.finish('cancelled'); await running; await stop; assert.equal(h.page.dataBusy, false); assert.match(h.page.dataHasUpdate, /已取消/);
    assert.ok(h.toasts.some(text => text === '本次更新已取消'));
  });
  await test('failed and cancelled-but-unsettled observations retain busy admission', async () => {
    for (const state of ['failed', 'cancelled']) {
      const h = harness(); h.emit({ id: 1, state, settled: false, error: 'fault' });
      await h.page.updateGameData(); await h.page.checkDataUpdate(); assert.equal(h.page.dataBusy, true); assert.equal(h.state.updates + h.state.checks, 0);
      h.emit({ settled: true }); assert.equal(h.page.dataBusy, false);
    }
  });
  await test('ambiguous publication failure preserves the restart-verification warning without claiming rollback', () => {
    const h = harness(); h.emit({ id: 1, state: 'failed', settled: true, error: '更新提交结果未确认，请重启后核验' });
    assert.match(h.page.dataHasUpdate, /结果未确认.*重启/); assert.ok(!h.page.dataHasUpdate.includes('未切换'));
    assert.equal(h.page.dataBusy, false);
  });
  await test('publication winning the cancel dialog reports completion truthfully', async () => {
    const h = harness(), running = h.page.updateGameData(), stop = h.page.cancelGameData(); h.finish(); await running;
    h.dialog.resolve({ index: 1 }); await stop; assert.deepEqual(h.state.cancellations, [1]);
    assert.match(h.toasts.at(-1), /不会撤销/); assert.match(h.page.dataHasUpdate, /已完成/);
  });
  await test('a stale cancel confirmation cannot affect or clear a newer invocation', async () => {
    const h = harness(), running = h.page.updateGameData(), stop = h.page.cancelGameData(); h.finish(); await running;
    h.emit({ ...idle(), id: 2, state: 'downloading', settled: false, canCancel: true, total: 8 });
    h.dialog.resolve({ index: 1 }); await stop; assert.deepEqual(h.state.cancellations, [1]);
    assert.equal(h.page.dataOperationId, 2); assert.equal(h.page.dataBusy, true); assert.equal(h.page.dataCanCancel, true);
    assert.ok(!h.toasts.includes('本次更新已取消'));
  });
  await test('old update completion cannot replace a newer invocation status', async () => {
    const h = harness(), running = h.page.updateGameData(); h.emit({ ...idle(), id: 2, state: 'downloading', settled: false, canCancel: true, done: 2, total: 8 });
    h.update.reject(Error('old request')); await running; assert.equal(h.page.dataBusy, true); assert.equal(h.page.dataDone, 2); assert.equal(h.toasts.length, 0);
    h.page.applyDataUpdateStatus({ ...idle(), id: 1, state: 'completed' }); assert.equal(h.page.dataOperationId, 2); assert.equal(h.page.dataBusy, true);
  });
  await test('cancel drain completion after disappearance has no State writes or toast', async () => {
    const h = harness(), running = h.page.updateGameData(), stop = h.page.cancelGameData(); h.dialog.resolve({ index: 1 }); await new Promise(setImmediate);
    h.page.aboutToDisappear(); h.finish('cancelled'); await running; await stop;
    assert.equal(h.state.listeners.size, 0); assert.deepEqual(h.writes, []); assert.equal(h.toasts.length, 0);
  });
  await test('cancel dialog after detach never issues cancellation', async () => {
    const h = harness(), running = h.page.updateGameData(), stop = h.page.cancelGameData(); h.page.aboutToDisappear();
    h.dialog.resolve({ index: 1 }); await stop; assert.deepEqual(h.state.cancellations, []); h.finish(); await running; assert.deepEqual(h.writes, []);
  });
  await test('bootstrap ordering and UI phase/cancel affordances remain connected', () => {
    const bootstrap = fs.readFileSync('entry/src/main/ets/entryability/EntryAbility.ets', 'utf8');
    const recovery = bootstrap.indexOf('await BackupService.getInstance().recoverInterruptedRestore()'), pin = bootstrap.indexOf('await GameDataService.initializeSnapshot()'), notify = bootstrap.indexOf('await NotificationHelper.init()');
    assert(recovery < pin && pin < notify); assert.match(method('aboutToAppear'), /this\.attachDataUpdates\(\)/);
    assert.match(source, /Button\(this\.dataCancelling \? '正在取消…' : '取消更新'\)/); assert.match(source, /Text\(this\.dataPhase\)/);
    assert(!source.includes('直连失败自动回退 ghfast/ghproxy'));
  });
  console.log(`game-data-page-integration: PASS ${count} production method cases (host UI boundary mocks)`);
})().catch(error => { console.error(error); process.exitCode = 1; });
