// F08: execute production scoring/settings/VM, mocking only storage and archive I/O boundaries.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const preferences = new Map();
const archives = [{ id: 1, name: 'first', uid: '100000001', isSelected: true }, { id: 2, name: 'second', uid: '100000002' }];
let items = [];
const mocks = {
  PreferencesStore: { getString: (key, fallback) => preferences.get(key) ?? fallback,
    setString: (key, value) => preferences.set(key, value) },
  BackpackService: { getArchives: async () => archives, getProjects: async () => [], getItems: async () => items },
};
const cache = new Map();
function load(relative) {
  const file = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (cache.has(file)) return cache.get(file).exports;
  const source = fs.readFileSync(file, 'utf8').replace(/^@Observed\s*$/gm, '');
  const compiled = ts.transpileModule(source, { fileName: file.replace(/\.ets$/, '.ts'), reportDiagnostics: true,
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
  assert.equal(compiled.diagnostics.length, 0, file);
  const module = { exports: {} }; cache.set(file, module);
  const requireLocal = name => mocks[path.basename(name)] ? { [path.basename(name)]: mocks[path.basename(name)] } : load(path.resolve(path.dirname(file), name));
  vm.runInThisContext('(function(require,module,exports){' + compiled.outputText + '\n})', { filename: file })(requireLocal, module, module.exports);
  return module.exports;
}
const { BackpackScoreProfile: Profile, BackpackScoring: Scoring } = load('model/BackpackScore');
const { BackpackScoreService: Settings } = load('service/BackpackScoreService');
const { BackpackItem, BackpackFilter } = load('model/BackpackData');
const { BackpackCatalog } = load('model/BackpackCatalog');
const { ReliquaryAffixReference } = load('model/ReliquaryAffixReference');
const { BackpackViewModel } = load('viewmodel/BackpackViewModel');
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-10, `${actual} != ${expected}`);
function relic(instance, ids) {
  const item = new BackpackItem(); item.archiveId = 1; item.instanceId = instance;
  item.itemId = 75543; item.kind = 'reliquary'; item.category = 1; item.name = 'same relic';
  item.appendPropIds = ids; item.rawJson = JSON.stringify({ appendPropIdList: ids, exact: '18446744073709551615' });
  item.score = Scoring.calculate(ids, Profile.create(0)); return item;
}

test('all five Windows presets retain exact weights, including crit in EM', () => {
  for (const [preset, expected] of [
    [0, [1, 1, .2, .2, .2, 0, 0]], [1, [1, 1, 1, 0, 0, 0, 0]],
    [2, [1, 1, 0, 0, 0, 1, 0]], [3, [1, 1, 0, 0, 0, 0, 1]], [4, [1, 1, 0, 0, 1, 0, 0]],
  ]) assert.deepEqual(Profile.create(preset).weights, expected);
  assert.equal(ReliquaryAffixReference.rows.length, 350);
  assert.equal(new Set(ReliquaryAffixReference.rows.map(row => row[0])).size, 350);
});
test('decimal percentages normalize once, repeated IDs add rolls, flat values have zero weight', () => {
  const ids = [501202, 501202, 501222, 501062, 501232, 501242, 501021];
  const result = Scoring.calculate(ids, Profile.create(0));
  assert.equal(result.available, true);
  close(result.value, 6.22 * 2 + 6.22 + 4.66 * 1.33 * .2 + 5.18 * 1.1979 * .2 + 18.65 * .33 * .2);
  assert.equal(result.stats[0].property, 20); close(result.stats[0].rawValue, .0622); assert.equal(result.stats[0].rolls, 2);
  assert.match(Scoring.statLabel(result.stats[0]), /6\.2%.*强化 1 次/);
  const copy = [...ids]; Scoring.calculate(ids, Profile.create(1)); assert.deepEqual(ids, copy);
  const zero = Profile.create(5); zero.weights = [0, 0, 0, 0, 0, 0, 0];
  const emptyScore = Scoring.calculate(ids, zero); assert.equal(emptyScore.available, true); assert.equal(emptyScore.value, 0);
  assert.match(Scoring.label(emptyScore), /^0\.0 分/);
});
test('every scaling preset uses the expected coefficient and unknown affixes never masquerade as zero', () => {
  close(Scoring.calculate([501064], Profile.create(1)).value, 5.83 * 1.33);
  close(Scoring.calculate([501034], Profile.create(2)).value, 5.83 * 1.33);
  close(Scoring.calculate([501094], Profile.create(3)).value, 7.29 * 1.06);
  close(Scoring.calculate([501244], Profile.create(4)).value, 23.31 * .33);
  const missing = Scoring.calculate([501202, 99999999], Profile.create(0));
  assert.equal(missing.available, false); assert.deepEqual(missing.unknownIds, [99999999]);
  assert.equal(missing.stats.length, 1); assert.match(Scoring.label(missing), /评分不可用/);
  assert.equal(Scoring.calculate([], Profile.create(0)).available, false);
  for (const bad of [NaN, Infinity, -1, 1.1]) {
    const profile = Profile.create(0); profile.weights[0] = bad; assert.throws(() => Scoring.calculate([501202], profile));
  }
});
test('local profile save/clone/reload/delete enforces one active choice and safe fallback', () => {
  preferences.clear();
  const profile = Profile.create(2); profile.name = 'HP build';
  let state = Settings.save(profile, 0);
  assert.equal(state.profiles.length, 1); assert.ok(state.activeId.length > 0);
  const id = state.activeId; assert.equal(Settings.active(Settings.load()).name, 'HP build');
  const draft = Settings.active(state); draft.weights[0] = .3;
  assert.equal(Settings.active(Settings.load()).weights[0], 1);
  state = Settings.save(draft, state.revision); assert.equal(state.activeId, id); assert.equal(state.profiles.length, 1);
  assert.throws(() => Settings.save(draft, 0), /已改变/);
  state = Settings.save(Profile.create(4), state.revision); assert.equal(state.profiles.length, 2);
  state = Settings.remove(state.activeId, state.revision); assert.equal(state.activeId, '');
  assert.deepEqual(Settings.active(Settings.load()).weights, Profile.create(0).weights);
  assert.equal(state.profiles[0].id, id);
  assert.throws(() => Settings.remove('missing', state.revision), /不存在/);
});
test('corrupt or unsupported settings remain unchanged and disable writes', () => {
  for (const raw of ['{bad', '{"version":2,"revision":0,"activeId":"","profiles":[]}',
    '{"version":1,"revision":0,"activeId":"missing","profiles":[]}']) {
    preferences.set(Settings.KEY, raw);
    const state = Settings.load(); assert.match(state.warning, /损坏或版本不支持/);
    assert.deepEqual(Settings.active(state).weights, Profile.create(0).weights);
    assert.throws(() => Settings.save(Profile.create(0), state.revision), /原设置未覆盖/);
    assert.equal(preferences.get(Settings.KEY), raw);
  }
  preferences.clear();
});
test('score ordering is stable by instance, zero is known, unknowns last, filters preserved', () => {
  const high = relic('high', [501202, 501222]);
  const low = relic('low', [501202]);
  const twin = relic('twin', [501202]);
  const unknown = relic('unknown', [999]);
  const zero = relic('zero', [501021]); zero.isLocked = true;
  const all = [unknown, twin, zero, high, low];
  const before = all.map(item => item.rawJson);
  const filter = new BackpackFilter(); filter.sort = 'score';
  assert.deepEqual(BackpackCatalog.filter(all, filter).map(item => item.instanceId), ['high', 'low', 'twin', 'zero', 'unknown']);
  filter.lockedOnly = true; assert.deepEqual(BackpackCatalog.filter(all, filter).map(item => item.instanceId), ['zero']);
  filter.lockedOnly = false; filter.keyword = 'twin'; assert.equal(BackpackCatalog.filter(all, filter)[0].instanceId, 'twin');
  assert.deepEqual(all.map(item => item.rawJson), before);
});
test('editor writes are bound to archive/generation; cancel and stale saves cannot change presets or UIIF', async () => {
  preferences.clear(); items = [relic('one', [501202, 501064])];
  const model = new BackpackViewModel(); await model.load(1);
  let edit = model.beginScoreEdit(); edit.profile.name = 'unsaved';
  assert.equal(preferences.size, 0); // Closing the editor never calls save.
  const before = items[0].rawJson;
  model.currentId = 2;
  assert.throws(() => model.saveScore(edit, Profile.create(1)), /档案或页面已改变/); assert.equal(preferences.size, 0);
  await model.load(1); edit = model.beginScoreEdit(); await model.load(1);
  assert.throws(() => model.saveScore(edit, Profile.create(1)), /档案或页面已改变/);
  edit = model.beginScoreEdit(); model.saveScore(edit, Profile.create(1));
  close(model.allItems[0].score.value, 3.11 * 2 + 5.83 * 1.33);
  assert.equal(model.allItems[0].rawJson, before);
  assert.throws(() => model.saveScore(edit, Profile.create(2)), /已改变/);
  edit = model.beginScoreEdit(); model.invalidate();
  assert.throws(() => model.deleteScore(edit, model.scoreSettings.activeId), /档案或页面已改变/);
});
test('UI exposes configuration, zero/unavailable score, and score-aware list keys', () => {
  const source = fs.readFileSync(path.join(root, 'pages/BackpackPage.ets'), 'utf8');
  assert.match(source, /Button\('评分设置'\)/); assert.match(source, /Slider\(\{ value: this\.scoreDraft\.weights\[index\], min: 0, max: 1, step: 0\.1 \}\)/);
  assert.match(source, /this\.vm\.scoreSettings\.revision/); assert.match(source, /BackpackScoring\.label\(item\.score\)/);
  assert.match(source, /this\.vm\.saveScore\(this\.scoreEdit, this\.scoreDraft\)/);
});
