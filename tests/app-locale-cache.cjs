// Production locale service with counted preference/native boundaries; no resource-pack or device I/O.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
function harness(options = {}) {
  const state = { preference: 'system', system: 'zh-Hans', native: 'default', ready: true,
    nativeFollowing: true, resourceLanguage: 'zh-Hans', readyReads: 0, preferenceReads: 0,
    preferenceWrites: 0, systemReads: 0, nativeReads: 0, nativeWrites: [], version: 0,
    failPreference: false, failNative: false, failSystem: false, ...options };
  const modules = new Map();
  const boundaries = {
    '@kit.LocalizationKit': { i18n: { System: {
      getSystemLocaleInstance() { state.systemReads++; if (state.failSystem) throw Error('system unavailable'); return { toString: () => state.system }; },
      getSystemLanguage() { state.systemReads++; if (state.failSystem) throw Error('system unavailable'); return state.system; },
      getAppPreferredLanguage() { state.nativeReads++; return state.native; },
      setAppPreferredLanguage(language) {
        if (state.failNative) throw Error('native language unavailable');
        state.nativeWrites.push(language); state.native = language;
        if (language !== 'default') { state.nativeFollowing = false; state.resourceLanguage = language; }
      },
    } } },
    '../data/prefs/PreferencesStore': { PreferencesStore: {
      isReady() { state.readyReads++; return state.ready; },
      getString() { state.preferenceReads++; return state.preference; },
      setString(key, value) { if (state.failPreference) throw Error('preference unavailable'); state.preferenceWrites++; state.preference = value; },
    } },
  };
  function load(name) {
    if (modules.has(name)) return modules.get(name);
    const filename = path.join(root, name + '.ets');
    const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { reportDiagnostics: true,
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
    assert.equal(compiled.diagnostics.length, 0, name);
    const module = { exports: {} };
    vm.runInNewContext(compiled.outputText, { module, exports: module.exports,
      require: specifier => boundaries[specifier] || load(path.posix.normalize(path.posix.join(path.posix.dirname(name), specifier))),
      AppStorage: { get: () => state.version, setOrCreate: (_key, value) => { state.version = value; } },
    }, { filename });
    modules.set(name, module.exports); return module.exports;
  }
  const service = load('service/AppLocaleService').AppLocaleService;
  const policy = load('model/LocalePolicy').LocalePolicy;
  return { service, policy, state };
}
function reads(state) { return [state.readyReads, state.preferenceReads, state.systemReads, state.nativeReads]; }

test('10,000 warm lookup batches perform zero preference or NAPI reads', () => {
  const { service, state } = harness(); service.initialize();
  const before = reads(state);
  for (let index = 0; index < 10000; index++) {
    assert.equal(service.current(), 'zh-Hans'); assert.equal(service.preference(), 'system');
    assert.equal(service.requested(), 'zh-Hans'); assert.equal(service.usingFallback(), false);
    assert.equal(service.apiLanguageCode(), 'zh-cn'); assert.equal(service.restartRequired(), false);
  }
  assert.deepEqual(reads(state), before); assert.equal(state.preferenceReads, 1); assert.equal(state.systemReads, 1);
  service.initialize(); assert.deepEqual(reads(state), before);
});

test('an early read is cached, and explicit startup initialization applies preferences once ready', () => {
  const { service, state } = harness({ ready: false, preference: 'ja' });
  assert.equal(service.current(), 'zh-Hans'); const before = reads(state);
  for (let index = 0; index < 100; index++) service.current();
  assert.deepEqual(reads(state), before); assert.equal(state.preferenceReads, 0);
  state.ready = true; service.initialize();
  assert.equal(service.current(), 'ja'); assert.equal(service.preference(), 'ja');
  assert.equal(state.resourceLanguage, 'ja'); assert.deepEqual(state.nativeWrites, ['ja']);
});

test('all fifteen explicit choices refresh the same effective resource/metadata language', () => {
  const { service, policy, state } = harness(); service.initialize();
  for (const locale of policy.locales()) {
    assert.equal(service.select(locale), true); assert.equal(service.current(), locale);
    assert.equal(service.current(), policy.resourceLocale(state.resourceLanguage));
    assert.equal(service.preference(), locale); assert.equal(service.apiLanguageCode(), policy.apiLanguageCode(locale));
    assert.equal(service.restartRequired(), false);
  }
  assert.equal(state.version, 15); const before = reads(state);
  for (let index = 0; index < 1000; index++) service.current();
  assert.deepEqual(reads(state), before);
  assert.equal(service.select('en-US'), false); assert.equal(service.select('not-a-language'), false);
});

test('reset to system preserves the active language until a cold start', () => {
  const { service, state } = harness(); service.initialize(); service.select('ja');
  assert.equal(service.select('system'), true);
  assert.equal(service.preference(), 'system'); assert.equal(service.current(), 'ja');
  assert.equal(service.current(), state.resourceLanguage); assert.equal(service.restartRequired(), true);
  state.system = 'fr-FR'; const before = reads(state);
  assert.equal(service.onConfigurationUpdate('fr-FR'), false); assert.deepEqual(reads(state), before);
  assert.equal(service.current(), 'ja'); assert.deepEqual(state.nativeWrites, ['ja', 'default']);
  const cold = harness({ preference: state.preference, system: state.system, resourceLanguage: state.system });
  cold.service.initialize(); assert.equal(cold.service.current(), 'fr'); assert.equal(cold.service.restartRequired(), false);
});

test('following-system configuration notifications read once and notify only for full-tag changes', () => {
  const { service, state } = harness(); service.initialize(); const before = reads(state);
  for (const language of [undefined, '']) assert.equal(service.onConfigurationUpdate(language), false);
  assert.deepEqual(reads(state), before); assert.equal(state.version, 0);
  assert.equal(service.onConfigurationUpdate('zh-Hans'), false); assert.equal(state.systemReads, before[2] + 1);
  state.system = 'fr-CA'; state.resourceLanguage = 'fr-CA';
  assert.equal(service.onConfigurationUpdate('fr-CA'), true);
  assert.equal(service.current(), 'fr'); assert.equal(state.systemReads, before[2] + 2); assert.equal(state.version, 1);
  const after = reads(state); assert.equal(service.onConfigurationUpdate('fr-CA'), false);
  assert.equal(state.systemReads, after[2] + 1); assert.equal(state.version, 1);
  service.select('ja'); state.system = 'de-DE';
  const explicitReads = reads(state); assert.equal(service.onConfigurationUpdate('de-DE'), false);
  assert.deepEqual(reads(state), explicitReads); assert.equal(service.current(), 'ja');
});

test('en-GB to en-US refreshes the requested culture even when configuration only says en', () => {
  const { service, state } = harness({ system: 'en-GB', resourceLanguage: 'en-GB' });
  service.initialize(); assert.equal(service.current(), 'en'); assert.equal(service.requested(), 'en-GB');
  state.system = 'en-US'; state.resourceLanguage = 'en-US';
  assert.equal(service.onConfigurationUpdate('en'), true);
  assert.equal(service.current(), 'en'); assert.equal(service.requested(), 'en-US'); assert.equal(state.version, 1);
  const before = reads(state);
  for (let index = 0; index < 10000; index++) { service.current(); service.requested(); }
  assert.deepEqual(reads(state), before);
  state.system = 'en_us'; assert.equal(service.onConfigurationUpdate('en'), false); assert.equal(state.version, 1);
});

test('fallback state and API language refresh at configuration boundaries', () => {
  const { service, state } = harness(); service.initialize();
  state.system = 'ar-SA'; assert.equal(service.onConfigurationUpdate('ar-SA'), true);
  assert.equal(service.current(), 'en'); assert.equal(service.usingFallback(), true); assert.equal(service.apiLanguageCode(), 'zh-cn');
  state.system = 'en-US'; assert.equal(service.onConfigurationUpdate('en-US'), true);
  assert.equal(service.current(), 'en'); assert.equal(service.usingFallback(), false); assert.equal(service.apiLanguageCode(), 'en-us');
  state.system = 'fr-FR'; state.failSystem = true;
  assert.equal(service.onConfigurationUpdate('fr-FR'), true); assert.equal(service.current(), 'fr');
});

test('committed backup restore refreshes cached preferences without rewriting them', () => {
  const { service, state } = harness(); service.initialize();
  state.preference = 'de'; assert.equal(service.applyCurrentPreference(), true);
  assert.equal(service.current(), 'de'); assert.equal(state.preferenceWrites, 0); assert.equal(state.resourceLanguage, 'de');
  state.preference = 'system'; assert.equal(service.applyCurrentPreference(), true);
  assert.equal(service.preference(), 'system'); assert.equal(service.current(), 'de'); assert.equal(service.restartRequired(), true);
  assert.equal(state.preferenceWrites, 0); assert.equal(state.version, 2);
  state.preference = 'fr'; state.failNative = true;
  assert.equal(service.applyCurrentPreference(), false); assert.equal(service.preference(), 'fr');
  assert.equal(service.current(), 'de'); assert.equal(state.resourceLanguage, 'de');
});

test('failed persistence or native application leaves the effective language intact', () => {
  const { service, state } = harness(); service.initialize();
  state.failPreference = true; assert.equal(service.select('ja'), false);
  assert.equal(state.nativeWrites.length, 0); assert.equal(service.current(), 'zh-Hans'); assert.equal(state.version, 0);
  state.failPreference = false; state.failNative = true; assert.equal(service.select('ja'), false);
  assert.equal(state.preference, 'system'); assert.equal(service.preference(), 'system');
  assert.equal(service.current(), 'zh-Hans'); assert.equal(state.resourceLanguage, 'zh-Hans'); assert.equal(state.version, 0);
});
