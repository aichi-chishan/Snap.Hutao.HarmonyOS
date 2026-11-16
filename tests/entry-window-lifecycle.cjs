const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };

function fixture() {
  const storage = new Map(), contents = [], warnings = [], timers = new Map();
  const retryListeners = new Map();
  const prefs = { ready: true };
  let timerId = 0;
  const kit = {
    UIAbility: class {}, ConfigurationConstant: { ColorMode: { COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1, COLOR_MODE_NOT_SET: -1 } },
    bundleManager: { BundleFlag: { GET_BUNDLE_INFO_DEFAULT: 0 }, getBundleInfoForSelfSync: () => ({ versionName: 'test' }) },
    window: { AvoidAreaType: { TYPE_SYSTEM: 0, TYPE_NAVIGATION_INDICATOR: 1 }, PixelUnit: { PX: 0, VP: 1 } },
    hilog: { info() {}, warn(...args) { warnings.push(args); }, error() {} },
    ComponentContent: class {
      disposed = 0;
      constructor() { contents.push(this); }
      dispose() { this.disposed++; }
    },
  };
  const globals = {
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    wrapBuilder: builder => builder,
    setTimeout: callback => { const id = ++timerId; timers.set(id, callback); return id; },
    clearTimeout: id => timers.delete(id),
  };
  function load(name, resolve) {
    const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', name + '.ets'), 'utf8');
    const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
    const module = { exports: {} };
    vm.runInNewContext(`(function(require, module, exports) { ${compiled.outputText}\n})`, globals)(resolve, module, module.exports);
    return module.exports;
  }
  const { RiskVerifyService } = load('service/RiskVerifyService', id => {
    if (id.endsWith('/PreferencesStore')) return { PreferencesStore: { getString: () => '' } };
    if (id.endsWith('/Logger')) return { Logger: { ...kit.hilog, flush: async () => {} } };
    if (id.endsWith('/AigisSession')) return { AigisSession: { parse: JSON.parse,
      buildAigisHeader: (sessionId, challenge, validate) => JSON.stringify({ sessionId, challenge, validate }) } };
    return {};
  });
  const { default: EntryAbility } = load('entryability/EntryAbility', id => {
    if (id.startsWith('@kit.')) return kit;
    if (id.endsWith('/Logger')) return { Logger: { ...kit.hilog, flush: async () => {} } };
    if (id.endsWith('/PreferencesStore')) return { PreferencesStore: {
      isReady: () => prefs.ready,
      getThemeMode: () => { assert.ok(prefs.ready, 'unavailable preferences must not be read'); return 'system'; },
      getReduceMotionEnabled: () => false,
    } };
    if (id.endsWith('/Motion')) return { Motion: { setReducedMotion() {} } };
    if (id.endsWith('/AppLocaleService')) return { AppLocaleService: { initialize() {}, onConfigurationUpdate() {} } };
    if (id.endsWith('/DailyNoteService')) return { DailyNoteService: { getInstance: () => ({ setForeground() {} }) } };
    if (id.endsWith('/AutoSignInService')) return { AutoSignInService: { getInstance: () => ({ setForeground() {} }) } };
    if (id.endsWith('/RiskVerifyModal')) return { buildRiskVerifyOverlay() {} };
    if (id.endsWith('/RiskVerifyService')) return { RiskVerifyService };
    return {};
  });
  EntryAbility.initializeRuntime = async () => {};
  EntryAbility.startDeferredServices = () => {};
  const ability = new EntryAbility();
  ability.context = { config: { colorMode: 1 }, getApplicationContext: () => ({ setColorMode() {} }), eventHub: {
    on(event, listener) { if (!retryListeners.has(event)) retryListeners.set(event, new Set()); retryListeners.get(event).add(listener); },
    off(event, listener) { assert.ok(listener); retryListeners.get(event)?.delete(listener); },
    emit(event) { for (const listener of retryListeners.get(event) ?? []) listener(); },
  } };
  return { EntryAbility, ability, storage, contents, warnings, risk: RiskVerifyService.getInstance(), timers, retryListeners, prefs };
}

function windowStage({ scale = 3, failRemove = false, failAdd = false, rejectLimits = false } = {}) {
  const layout = deferred(), listeners = new Map(), calls = [], removed = [];
  let alive = true;
  const overlay = {
    addComponentContent(content) { if (failAdd) throw Error('mount failed'); calls.push(['add', content]); },
    removeComponentContent(content) { assert.ok(alive, 'overlay removal must precede native window destruction'); removed.push(content); if (failRemove) throw Error('window gone'); },
  };
  const window = {
    on(name, handler) { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(handler); },
    off(name, handler) { assert.ok(alive, 'off must precede native window destruction'); assert.ok(handler, 'teardown must keep unrelated subscriptions'); listeners.get(name)?.delete(handler); },
    getUIContext: () => ({ vp2px: value => value * scale, px2vp: value => value / scale, getOverlayManager: () => overlay }),
    setWindowLimits(limits) { calls.push(['limits', limits]); return rejectLimits ? Promise.reject(Error('unsupported')) : Promise.resolve(limits); },
    setWindowDecorHeight() {}, setWindowDecorVisible() {},
    getTitleButtonRect: () => ({ right: 25, width: 240 }),
    setWindowLayoutFullScreen: () => layout.promise,
    setWindowSystemBarProperties() { calls.push(['bars']); return Promise.resolve(); },
    setWindowBackgroundColor() { calls.push(['backdrop']); },
    getWindowAvoidArea: type => ({ topRect: { height: type === 0 ? 90 : 0 }, bottomRect: { height: type === 1 ? 60 : 0 } }),
  };
  const stage = { getMainWindowSync: () => window, loadContent(page) {
    calls.push(['load', page]);
    const pending = deferred();
    stage.loaded = error => error.code ? pending.reject(error) : pending.resolve();
    return pending.promise;
  } };
  return { stage, window, layout, listeners, calls, removed, destroy() { alive = false; }, setScale(value) { scale = value; } };
}

test('window geometry uses current UI density and releases only owned listeners and overlay', async () => {
  const { ability, storage, contents } = fixture(); const win = windowStage();
  const foreign = () => {};
  win.window.on('avoidAreaChange', foreign);
  ability.onWindowStageCreate(win.stage); await flush(); win.stage.loaded({ code: 0 }); await flush();
  assert.equal(storage.get('titleBtnWidthVp'), 265, 'title button values are already vp and must not be capped');
  const limits = win.calls.find(call => call[0] === 'limits')[1];
  assert.equal(limits.minWidth, 360); assert.equal(limits.pixelUnit, 1, 'native VP limits follow density changes');
  assert.equal(win.calls.some(call => call[0] === 'backdrop'), false, 'backdrop waits for fullscreen layout');
  win.layout.resolve(); await flush();
  assert.equal(storage.get('topAvoidVp'), 30); assert.equal(storage.get('bottomAvoidVp'), 20);
  win.setScale(2);
  for (const listener of win.listeners.get('avoidAreaChange')) listener({});
  assert.equal(storage.get('topAvoidVp'), 45); assert.equal(storage.get('bottomAvoidVp'), 30);
  const oldListener = [...win.listeners.get('windowTitleButtonRectChange')][0];
  ability.onWindowStageWillDestroy(win.stage);
  assert.equal(contents[0].disposed, 1, 'native resources are released while the window is still alive');
  win.destroy(); ability.onWindowStageDestroy(); ability.onDestroy();
  assert.equal(win.listeners.get('avoidAreaChange').size, 1); assert.ok(win.listeners.get('avoidAreaChange').has(foreign));
  assert.equal(win.listeners.get('windowTitleButtonRectChange').size, 0);
  assert.equal(contents[0].disposed, 1); assert.equal(win.removed.length, 1);
  oldListener({ right: 5, width: 180 }); assert.equal(storage.get('titleBtnWidthVp'), 0);
  assert.equal(ability.mainWindow, undefined); assert.equal(ability.windowStage, undefined);
});

test('late initialization, content and fullscreen callbacks cannot revive old windows', async () => {
  const { EntryAbility, ability, contents } = fixture(); const init = deferred();
  EntryAbility.initializeRuntime = () => init.promise;
  const old = windowStage(), current = windowStage();
  ability.onWindowStageCreate(old.stage); ability.onWindowStageWillDestroy(old.stage);
  old.destroy(); ability.onWindowStageDestroy(); ability.onWindowStageCreate(current.stage);
  init.resolve(); await flush();
  assert.equal(old.calls.length, 0); assert.equal(current.calls[0][0], 'load');
  current.stage.loaded({ code: 0 }); await flush();
  ability.onWindowStageWillDestroy(current.stage); current.destroy(); ability.onWindowStageDestroy();
  current.layout.resolve(); await flush();
  assert.equal(current.calls.some(call => call[0] === 'backdrop'), false);
  current.stage.loaded({ code: 0 }); assert.equal(contents.length, 1);
  assert.equal(contents[0].disposed, 1);
});

test('overlay removal and mount failures still dispose content; window limit rejection is handled', async () => {
  for (const options of [{ failRemove: true, rejectLimits: true }, { failAdd: true }]) {
    const { ability, contents, warnings } = fixture(); const win = windowStage(options);
    ability.onWindowStageCreate(win.stage); await flush(); win.stage.loaded({ code: 0 }); await flush();
    ability.onWindowStageWillDestroy(win.stage); win.destroy(); ability.onWindowStageDestroy();
    assert.equal(contents[0].disposed, 1);
    assert.equal(ability.riskVerifyContent, undefined); assert.equal(ability.overlayManager, undefined);
    if (options.rejectLimits) assert.ok(warnings.some(args => String(args[2]).includes('setWindowLimits')));
  }
});

test('closing a window resolves pending verification and clears its timer before rebuilding', async () => {
  const { ability, risk, storage, timers } = fixture(); const old = windowStage();
  ability.onWindowStageCreate(old.stage); await flush(); old.stage.loaded({ code: 0 }); await flush();
  const pending = risk.verifyGtFull('gt', 'old-challenge'); await flush();
  const oldSequence = risk.snapshot().seq;
  assert.equal(risk.hasPending(), true); assert.equal(timers.size, 1);
  ability.onWindowStageWillDestroy(old.stage);
  assert.equal(risk.hasPending(), false); assert.equal(risk.snapshot(), undefined);
  assert.equal(storage.get('riskVerifyShow'), false); assert.equal(timers.size, 0);
  assert.equal((await pending).validate, '');
  old.destroy(); ability.onWindowStageDestroy();

  const replacement = windowStage();
  ability.onWindowStageCreate(replacement.stage); await flush(); replacement.stage.loaded({ code: 0 }); await flush();
  const next = risk.verifyGt('gt', 'new-challenge'); const newSequence = risk.snapshot().seq;
  ability.onWindowStageWillDestroy(old.stage);
  risk.submitValidate('late-result', 'old-challenge', oldSequence);
  assert.equal(risk.hasPending(), true, 'old window teardown and old Web callbacks keep the new request pending');
  risk.submitValidate('accepted', 'new-challenge', newSequence);
  assert.equal(await next, 'accepted'); assert.equal(timers.size, 0);
  ability.onWindowStageWillDestroy(replacement.stage); replacement.destroy(); ability.onWindowStageDestroy();
});

test('early window teardown cancels aigis even before an overlay exists; repeated cleanup is harmless', async () => {
  const { ability, risk, timers } = fixture(); const first = windowStage();
  ability.onWindowStageCreate(first.stage); await flush();
  const pending = risk.verifyAigis(JSON.stringify({ sessionId: 'session', gt: 'gt', challenge: 'challenge' }));
  await flush(); assert.equal(risk.hasPending(), true);
  ability.onWindowStageWillDestroy(first.stage); assert.equal(await pending, ''); assert.equal(timers.size, 0);
  first.destroy(); ability.onWindowStageDestroy();

  const next = risk.verifyGt('gt', 'next'); const nextSequence = risk.snapshot().seq;
  ability.onWindowStageDestroy();
  assert.equal(risk.hasPending(), true, 'a repeated cleanup without an owned window does not cancel a new request');
  const replacement = windowStage(); ability.onWindowStageCreate(replacement.stage); await flush();
  assert.equal(risk.hasPending(), true, 'initial cleanup for a new stage does not cancel its initial request');
  risk.submitValidate('accepted', '', nextSequence); assert.equal(await next, 'accepted');
  ability.onWindowStageWillDestroy(replacement.stage); replacement.destroy(); ability.onWindowStageDestroy();
});

test('failed initialization shows only the error page; retry is single flight and enters Index after success', async () => {
  const { EntryAbility, ability, storage, contents, retryListeners } = fixture();
  const win = windowStage(); const retry = deferred(); let attempts = 0;
  EntryAbility.initializeRuntime = async () => { if (++attempts === 1) throw Error('database unavailable'); await retry.promise; };
  ability.onWindowStageCreate(win.stage); await flush();
  assert.deepEqual(win.calls, [['load', 'pages/StartupErrorPage']]);
  assert.equal(contents.length, 0); assert.equal(storage.get('startupRetrying'), true);
  win.stage.loaded({ code: 0 }); await flush(); assert.equal(storage.get('startupRetrying'), false);
  assert.equal(retryListeners.get('hutao.startup.retry').size, 1);

  ability.context.eventHub.emit('hutao.startup.retry'); ability.context.eventHub.emit('hutao.startup.retry');
  assert.equal(attempts, 2); assert.equal(storage.get('startupRetrying'), true);
  assert.equal(win.calls.length, 1, 'no normal page is mounted while retry is pending');
  retry.resolve(); await flush(); assert.deepEqual(win.calls.at(-1), ['load', 'pages/Index']);
  assert.equal(contents.length, 0, 'overlay waits for successful Index content loading');
  win.stage.loaded({ code: 0 }); await flush();
  assert.equal(contents.length, 1); assert.equal(storage.get('startupRetrying'), false);
  assert.equal(retryListeners.get('hutao.startup.retry').size, 0);
  ability.context.eventHub.emit('hutao.startup.retry'); assert.equal(attempts, 2);
  ability.onWindowStageWillDestroy(win.stage);
});

test('failed retries keep one retry handler and a destroyed window cannot publish late failure', async () => {
  const { EntryAbility, ability, storage, retryListeners } = fixture(); const win = windowStage();
  const late = deferred(); let attempts = 0;
  EntryAbility.initializeRuntime = async () => { if (++attempts < 3) throw Error('still unavailable'); await late.promise; };
  ability.onWindowStageCreate(win.stage); await flush(); win.stage.loaded({ code: 0 }); await flush();
  ability.context.eventHub.emit('hutao.startup.retry'); await flush();
  assert.equal(win.calls.length, 1, 'a failed core retry keeps the existing error UI and its retry button');
  assert.equal(retryListeners.get('hutao.startup.retry').size, 1);
  const oldListener = [...retryListeners.get('hutao.startup.retry')][0];
  ability.context.eventHub.emit('hutao.startup.retry'); assert.equal(attempts, 3);
  ability.onWindowStageWillDestroy(win.stage); win.destroy(); ability.onWindowStageDestroy();
  storage.set('startupRetrying', 'new-window-state');
  late.reject(Error('old attempt failed')); await flush();
  assert.equal(storage.get('startupRetrying'), 'new-window-state');
  assert.equal(win.calls.length, 1); assert.equal(retryListeners.get('hutao.startup.retry').size, 0);
  oldListener(); assert.equal(attempts, 3, 'a stale retry handler cannot restart a destroyed stage');
});

test('configuration changes before preferences are ready keep system appearance without reading the store', () => {
  const { ability, storage, prefs } = fixture(); prefs.ready = false;
  ability.onConfigurationUpdate({ colorMode: 0 });
  assert.equal(storage.get('isDarkMode'), true);
});

test('failed Index content loading restores the error page after the old content was replaced', async () => {
  const { EntryAbility, ability, contents, storage } = fixture(); const win = windowStage(); let attempts = 0;
  EntryAbility.initializeRuntime = async () => { if (++attempts === 1) throw Error('initial failure'); };
  ability.onWindowStageCreate(win.stage); await flush(); win.stage.loaded({ code: 0 }); await flush();
  ability.context.eventHub.emit('hutao.startup.retry'); await flush();
  assert.deepEqual(win.calls.at(-1), ['load', 'pages/Index']);
  win.stage.loaded({ code: 1300002 }); await flush();
  assert.deepEqual(win.calls.at(-1), ['load', 'pages/StartupErrorPage']);
  win.stage.loaded({ code: 0 }); await flush();
  assert.equal(ability.startupErrorLoaded, true); assert.equal(storage.get('startupRetrying'), false);
  assert.equal(contents.length, 0);
  ability.onWindowStageWillDestroy(win.stage);
});

test('startup error route and localized strings are included in the application', () => {
  const resources = path.join(__dirname, '../entry/src/main/resources');
  const pages = JSON.parse(fs.readFileSync(path.join(resources, 'base/profile/main_pages.json'), 'utf8')).src;
  assert.equal(pages.filter(route => route === 'pages/StartupErrorPage').length, 1);
  const keys = ['ui_startup_failed_title', 'ui_startup_failed_body'];
  const locales = fs.readdirSync(resources).filter(locale => fs.existsSync(path.join(resources, locale, 'element/ui_labels.json')));
  for (const locale of locales) {
    const strings = JSON.parse(fs.readFileSync(path.join(resources, locale, 'element/startup_strings.json'), 'utf8')).string;
    for (const key of keys) {
      const entries = strings.filter(entry => entry.name === key);
      assert.equal(entries.length, 1, `${locale}: ${key}`);
      assert.ok(entries[0].value.trim().length > 0, `${locale}: ${key} must be visible`);
    }
  }
});

test('wide shell keeps controls below the system bar and shared tabs apply the top inset exactly once', () => {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/Index.ets'), 'utf8').replaceAll('\r\n', '\n');
  const section = (name, next) => {
    const begin = source.indexOf(`  ${name}() {`);
    const end = source.indexOf(`  ${next}() {`, begin + 1);
    assert.ok(begin >= 0 && end > begin);
    return source.slice(begin, end);
  };
  const shell = section('wideShell', 'topBar');
  // The inset belongs to the foreground Column, outside the fixed-height toolbar;
  // the wallpaper remains the first Stack sibling and continues behind the system bar.
  const contentPadding = shell.match(/Column\(\) \{\s*\/\/[^\n]*\n\s*this\.topBar\(\)[\s\S]*?\n {6}\}\n {6}\.width\('100%'\)\n {6}\.height\('100%'\)\s*(?:\/\/[^\n]*\n\s*)?\.padding\((\{[^}]*\})\)/);
  assert.ok(contentPadding, 'the complete foreground Column must consume the dynamic system top inset');
  assert.ok(shell.indexOf('WallpaperLayer(') < shell.indexOf('Column()'));
  assert.equal((shell.match(/\.padding\(/g) ?? []).length, 1, 'the background Stack must not inherit the content inset');
  assert.match(section('topBar', 'sideNav'), /\.height\(40\)/, 'padding must not shrink the 36vp toolbar buttons');
  const evaluate = (expression, state) => Function(`return (${expression});`).call(state);
  const tabPaddings = [section('gachaTab', 'noteTab'), section('noteTab', 'mineTab')]
    .map(tab => { const match = tab.match(/\.padding\((\{[^}]*\})\)/); assert.ok(match); return match[1]; });
  for (const inset of [0, 24, 40, 48]) {
    const wide = { topAvoidVp: inset, isWide: true };
    const phone = { topAvoidVp: inset, isWide: false };
    assert.equal(evaluate(contentPadding[1], wide).top, inset);
    for (const padding of tabPaddings) {
      assert.equal(evaluate(contentPadding[1], wide).top + evaluate(padding, wide).top, inset);
      assert.equal(evaluate(padding, phone).top, inset, 'phone tabs keep their existing inset');
    }
  }
});
