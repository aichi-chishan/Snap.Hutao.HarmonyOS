// Production preference, startup and Motion logic with deterministic platform doubles.
// This checks application-level reduction only, not OS preferences or native rendering.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const base = path.resolve(__dirname, '../entry/src/main/ets');
const read = name => fs.readFileSync(path.join(base, `${name}.ets`), 'utf8');
const modules = new Map();
const appValues = new Map();
let disk = new Map();
let live = new Map();
let flushes = 0;
let failInit = false;
let failDatabase = false;
let recoveryValue;
let apiAvailable = false;
let apiThrows = false;
const store = {
  getSync: (key, fallback) => live.has(key) ? live.get(key) : fallback,
  putSync: (key, value) => live.set(key, value),
  getAllSync: () => Object.fromEntries(live),
  deleteSync: key => live.delete(key),
  flush: async () => { disk = new Map(live); flushes++; },
};
const AppStorage = { get: key => appValues.get(key), setOrCreate: (key, value) => { appValues.set(key, value); } };
class Effect {
  constructor(type, value, children = []) { this.type = type; this.value = value; this.children = children; }
  combine(other) { return new Effect('combine', undefined, [this, other]); }
  animation(options) { this.options = options; return this; }
}
const TransitionEffect = {
  get IDENTITY() { return new Effect('identity'); },
  get OPACITY() { return new Effect('opacity'); },
  translate: value => new Effect('translate', value), scale: value => new Effect('scale', value),
  asymmetric: (enter, exit) => new Effect('asymmetric', undefined, [enter, exit]),
};
const curves = {
  springMotion: (response, damping) => ({ type: 'spring', response, damping }),
  stepsCurve: (count, end) => ({ type: 'steps', count, end }),
};
const logger = { info() {}, warn() {}, error() {} };
const mocks = {
  Logger: { Logger: logger },
  '@kit.ArkData': { preferences: { getPreferences: async () => {
    if (failInit) throw Error('preference init failure');
    live = new Map(disk);
    return store;
  } } },
  '@kit.ArkUI': { curves },
  '@kit.BasicServicesKit': { deviceInfo: { apiAvailable: version => {
    assert.equal(version, '26.0.0');
    if (apiThrows) throw Error('unsupported');
    return apiAvailable;
  } } },
  '@kit.AbilityKit': { UIAbility: class {}, ConfigurationConstant: {
    ColorMode: { COLOR_MODE_LIGHT: 1, COLOR_MODE_DARK: 0, COLOR_MODE_NOT_SET: -1 },
  } },
  '@kit.PerformanceAnalysisKit': { hilog: logger },
  AppContext: { AppContextProvider: { init() {} } },
  RelationalStoreHelper: { RelationalStoreHelper: { init: async () => {
    if (failDatabase) throw Error('database failure');
  } } },
  BackupService: { BackupService: { getInstance: () => ({ recoverInterruptedRestore: async () => {
    if (recoveryValue !== undefined) live.set('app.reduce_motion', recoveryValue);
  } }) } },
  GameDataService: { GameDataService: { initializeSnapshot: async () => {} } },
  BackgroundTaskService: { BackgroundTaskService: { init: async () => {}, reconcile: async () => {}, reset: async () => {}, stopAndInvalidate: async () => true } },
  NotificationHelper: { NotificationHelper: { init: async () => {} } },
  UserService: { UserService: { getInstance: () => ({ setSessionInvalidationHook() {}, restoreSession: async () => true }) } },
  AutoSignInService: { AutoSignInService: { getInstance: () => ({ bootstrapAutoSignIn: async () => {} }) } },
  DailyNoteService: { DailyNoteService: { getInstance: () => ({ bootstrapAutoRefresh: async () => {}, clearCardSnapshot: async () => {} }) } },
  RiskVerifyModal: {},
};
function compile(text, name, resolve) {
  const compiled = ts.transpileModule(text, { compilerOptions: {
    target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS,
  }, reportDiagnostics: true });
  assert.equal(compiled.diagnostics.filter(item => item.category === ts.DiagnosticCategory.Error).length, 0, name);
  const mod = { exports: {} };
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`, {
    AppStorage, TransitionEffect, Curve: { Friction: 'friction', Sharp: 'sharp' },
  })(resolve, mod, mod.exports);
  return mod.exports;
}
function load(name) {
  if (modules.has(name)) return modules.get(name);
  const result = compile(read(name), name, id => {
    const key = id.split('/').at(-1);
    if (mocks[id]) return mocks[id];
    if (mocks[key]) return mocks[key];
    return load(path.relative(base, path.resolve(base, path.dirname(name), id)));
  });
  modules.set(name, result);
  return result;
}

(async () => {
  const { PreferencesStore: prefs } = load('data/prefs/PreferencesStore');
  const { Motion } = load('common/Motion');
  const { BackupSnapshotValidator } = load('model/BackupSnapshot');
  const { default: EntryAbility } = load('entryability/EntryAbility');
  assert.equal(Motion.isReducedMotion(), false, 'unset app storage preserves existing motion');
  await prefs.init({});
  assert.equal(prefs.getReduceMotionEnabled(), false);
  prefs.setReduceMotionEnabled(true);
  assert.equal(prefs.getReduceMotionEnabled(), true);
  assert.equal(disk.get('app.reduce_motion'), true);
  assert.equal(flushes, 1, 'writes use the existing persistent PreferencesStore flush path');
  assert.equal(BackupSnapshotValidator.portableKey(prefs.KEY_REDUCE_MOTION), true);
  assert.equal(prefs.exportPortable()['app.reduce_motion'], true, 'the setting travels with ordinary preference backups');

  // Run the real startup method, including restore ordering, before observing loadContent.
  const startupValues = [];
  const ability = { context: { config: { colorMode: 1 },
    getApplicationContext: () => ({ setColorMode() {} }) } };
  const stage = { loadContent: route => {
    assert.equal(route, 'pages/Index');
    startupValues.push(Motion.isReducedMotion());
  } };
  prefs.prefs = undefined;
  appValues.clear();
  EntryAbility.runtimeInitialization = undefined; // A new process, not another window in the same runtime.
  await EntryAbility.bootstrap(ability, stage);
  assert.equal(startupValues.at(-1), true, 'persisted preference is restored before the first page loads');
  recoveryValue = false;
  EntryAbility.runtimeInitialization = undefined; // A new process, not another window in the same runtime.
  await EntryAbility.bootstrap(ability, stage);
  assert.equal(startupValues.at(-1), false, 'interrupted backup recovery wins over the earlier preference');
  recoveryValue = undefined;
  live.set('app.reduce_motion', true);
  failDatabase = true;
  EntryAbility.runtimeInitialization = undefined; // A new process, not another window in the same runtime.
  await EntryAbility.bootstrap(ability, stage);
  assert.equal(startupValues.at(-1), true, 'an unrelated database failure does not lose the preference');
  failDatabase = false;
  failInit = true;
  prefs.prefs = undefined;
  EntryAbility.runtimeInitialization = undefined; // A new process, not another window in the same runtime.
  await EntryAbility.bootstrap(ability, stage);
  assert.equal(startupValues.at(-1), false, 'a missing preference store has a safe deterministic fallback');
  failInit = false;
  await prefs.init({});
  live.set('app.reduce_motion', 'false');
  assert.equal(prefs.getReduceMotionEnabled(), false, 'corrupt non-boolean preferences cannot enable motion reduction');

  // Compile the actual small settings handler without interpreting ArkUI build syntax.
  const settings = read('pages/SettingPage');
  const start = settings.indexOf('  private applyReduceMotion(');
  const end = settings.indexOf('\n  applyTheme(', start);
  assert.ok(start > 0 && end > start);
  const { SettingProbe } = compile(`import { PreferencesStore } from './PreferencesStore';
    import { Motion } from './Motion';
    export class SettingProbe { ${settings.slice(start, end)} }`, 'settings handler', id =>
    id === './PreferencesStore' ? { PreferencesStore: prefs } : { Motion });
  const setting = new SettingProbe();
  for (const enabled of [false, true, false, true]) {
    setting.applyReduceMotion(enabled);
    assert.equal(Motion.isReducedMotion(), enabled, 'toggle publishes immediately');
    assert.equal(disk.get('app.reduce_motion'), enabled, 'toggle persists in both directions');
  }

  for (const method of ['spring', 'springFast', 'springSoft']) {
    assert.equal(Motion[method]().type, 'steps');
    assert.equal(Motion[method]().count, 1);
    assert.equal(Motion[method]().end, false, 'reduced curves jump at the start instead of delaying until the end');
  }
  assert.equal(Motion.easeOut(250).duration, 0);
  for (const effect of [Motion.pageSwitch(), Motion.pageSwitch(false), Motion.riseIn(40)]) {
    assert.equal(effect.type, 'identity', 'reduced transitions contain no translation, scale or opacity');
    assert.equal(effect.options.duration, 0);
    assert.equal(effect.children.length, 0);
  }
  assert.equal(Motion.staggerDelay(10), 0);
  setting.applyReduceMotion(false);
  for (const [method, response, damping] of [['spring', .34, .86], ['springFast', .28, .9], ['springSoft', .42, .82]]) {
    const curve = Motion[method]();
    assert.equal(curve.type, 'spring'); assert.equal(curve.response, response); assert.equal(curve.damping, damping);
  }
  assert.equal(Motion.easeOut(250).duration, 250);
  assert.equal(Motion.pageSwitch().type, 'asymmetric');
  assert.equal(Motion.riseIn().type, 'asymmetric');
  assert.equal(Motion.staggerDelay(-1), 0); assert.equal(Motion.staggerDelay(3), 120);
  assert.equal(Motion.staggerDelay(20), 320);
  assert.equal(Motion.pageSwitch(true).type, 'identity', 'a caller can also request a reduced transition');

  apiAvailable = true; assert.equal(Motion.detectImmersive(), true);
  apiAvailable = false; assert.equal(Motion.detectImmersive(), false);
  apiThrows = true; assert.equal(Motion.detectImmersive(), false, 'API 26 availability remains runtime guarded');
  assert.match(settings, /@StorageProp\('reduceMotion'\) reduceMotion: boolean/);
  assert.match(settings, /Toggle\(\{ type: ToggleType.Switch, isOn: this.reduceMotion \}\)/);
  assert.match(settings, /\.accessibilityText\('减少动态效果'\)/);
  assert.match(settings, /\.constraintSize\(\{ minWidth: 44, minHeight: 44 \}\)/);
  const container = read('components/PageContainer');
  assert.match(container, /@StorageProp\('reduceMotion'\)/);
  assert.match(container, /\.transition\(Motion.pageSwitch\(this.reduceMotion\)\)/,
    'mounted page transitions explicitly depend on the reactive flag');
  console.log('reduce-motion: PASS (persisted app preference, settings handler, startup/recovery ordering and failure fallback, central helper policy, reactive page contract; host-only, no OS preference integration)');
})().catch(error => { console.error(error); process.exitCode = 1; });
