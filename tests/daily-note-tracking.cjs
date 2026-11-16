const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

function harness() {
  const state = { user: { id: 1, displayName: 'fixture' }, uid: '100000001', tracked: [],
    events: [], record: undefined, fail: false, wait: undefined };
  const storage = new Map();
  const prefs = {
    getCurrentUid: () => state.uid,
    getTrackedUids: () => [...state.tracked],
    setTrackedUids: (_owner, ids) => { state.events.push('track'); state.tracked = [...ids]; },
    getString: (_key, fallback) => fallback,
    setString() {}, getAutoRefreshEnabled: () => false,
  };
  const daily = {
    isTimerRunning: () => false,
    trackedEntries: async () => state.tracked.map(uid => ({ userId: 1, uid, nickname: 'fixture',
      region: 'cn_gf01', level: 60, record: state.record })),
    refresh: async () => {
      state.events.push('fetch');
      if (state.wait) await state.wait;
      if (state.fail) throw new Error('fixture network failure');
      const note = { rawJson: '{}', archonQuests: [], refreshTime: 10 };
      state.record = { note, resinNotifyThreshold: 120, homeCoinNotifyThreshold: 1800, notifyFlags: 0 };
      return note;
    },
  };
  const modules = {
    '../service/LocalizedGameDataService': { LocalizedGameDataService: { current: () => 'zh-Hans', readJson: async () => [] } },
    '../model/DailyNote': { DailyNoteChapterMetadata: { fromJson: () => [] } },
    '../service/DailyNoteService': { DailyNoteService: { getInstance: () => daily }, NotifyFlags: { ALL: 31 }, KEY_NOTE_VERSION: 'dailyNoteVersion' },
    '../data/repo/DailyNoteRepo': { DailyNoteRepo: { get: async () => state.record } },
    '../service/UserService': { UserService: { getInstance: () => ({ getCurrentUser: () => state.user }) } },
    '../data/prefs/PreferencesStore': { PreferencesStore: prefs },
    '../model/BackgroundTask': { BackgroundTaskPolicy: { owns: () => true } },
    '../common/Constants': { RegionUtil: { regionOfUid: () => 'cn_gf01' } },
    '../service/DailyNoteReminderService': { DailyNoteReminderService: { cancelUid: async () => {} } },
    '../common/Logger': { Logger: { warn() {} } },
  };
  const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/viewmodel/DailyNoteViewModel.ets'), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: {
    target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, experimentalDecorators: true,
  } }).outputText;
  const exports = {};
  vm.runInNewContext(`(function(require,exports){${code}\n})`, {
    Observed: type => type,
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  })(name => modules[name] || {}, exports);
  return { state, model: new exports.DailyNoteViewModel() };
}

test('adding fetches data before tracking and removing hides even a cached current-role card', async () => {
  const { state, model } = harness();
  await model.load(state.uid);
  assert.equal(await model.trackCurrent(), true);
  assert.deepEqual(state.events, ['fetch', 'track']);
  assert.equal(model.buildCardEntries().length, 1);
  assert.equal(await model.trackCurrent(), false);
  assert.equal(state.events.filter(x => x === 'fetch').length, 1);
  await model.untrack(1, state.uid);
  assert.ok(model.note, 'cache remains available for later tracking');
  assert.equal(model.buildCardEntries().length, 0);
});

test('a failed initial request retains the tracking entry, matching Windows AddDailyNoteAsync', async () => {
  const { state, model } = harness();
  await model.load(state.uid); state.fail = true;
  assert.equal(await model.trackCurrent(), true);
  assert.equal(model.buildCardEntries().length, 1);
  assert.equal(model.buildCardEntries()[0].note, undefined);
  assert.match(model.message, /network failure/);
});

test('changing accounts during the initial request cannot add a tracking preference for either owner', async () => {
  const { state, model } = harness();
  await model.load(state.uid);
  let release;
  state.wait = new Promise(resolve => { release = resolve; });
  const pending = model.trackCurrent();
  state.user = { id: 2, displayName: 'next' }; state.uid = '200000002'; release();
  assert.equal(await pending, false);
  assert.deepEqual(state.tracked, []);
  assert.deepEqual(state.events, ['fetch']);
});
