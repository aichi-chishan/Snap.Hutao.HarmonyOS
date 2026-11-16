const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const UID_A = '100000001';
const UID_B = '100000002';
const ALPHA = 10000021;
const BETA = 10000046;
const GAMMA = 10000049;

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((success, failure) => { resolve = success; reject = failure; });
  return { promise, resolve, reject };
}

const turn = () => new Promise(resolve => setImmediate(resolve));

function harness() {
  const listCache = new Map();
  const detailCache = new Map();
  const lists = [];
  const batches = [];
  const individual = [];
  const account = {
    id: 1,
    isOversea: false,
    hasCookie: () => true,
    roles: [UID_A, UID_B].map(gameUid => ({ gameUid, region: 'cn_gf01', userId: 1 })),
  };
  const session = { revision: 1, pending: false, account };
  const sessionListeners = new Set();
  const users = {
    sessionRevision: () => session.revision,
    isSessionTransitionPending: () => session.pending,
    getCurrentUser: () => session.pending ? undefined : session.account,
    addSessionRevisionListener(listener) {
      sessionListeners.add(listener);
      return () => { sessionListeners.delete(listener); };
    },
  };
  const service = {
    getCachedList: uid => listCache.get(uid) ?? [],
    getCachedDetails: uid => detailCache.get(uid) ?? [],
    fetchList(uid, _challenge, isCurrent) {
      const result = deferred();
      lists.push({ uid, isCurrent, ...result });
      return result.promise;
    },
    fetchDetailBatches(uid, ids, onBatch, isCurrent) {
      const result = deferred();
      batches.push({ uid, ids: Array.from(ids), onBatch, isCurrent, ...result });
      return result.promise;
    },
    async fetchDetail(uid, ids) {
      individual.push({ uid, ids: Array.from(ids) });
      return [];
    },
  };
  const dependencies = {
    CharacterService: { CharacterService: { getInstance: () => service } },
    UserService: { UserService: { getInstance: () => users } },
    BackpackScoreService: { BackpackScoreService: { characterOptions: () => [] } },
    WikiMetaService: { WikiMetaService: { avatarOf: () => undefined, weaponOf: () => undefined } },
    RiskVerifier: { RiskControlError: class extends Error {} },
    RiskUiHelper: { RiskUiHelper: { consumePendingChallenge: () => '' } },
    Logger: { Logger: { info() {}, warn() {} } },
  };
  const modules = new Map();
  function load(file) {
    if (modules.has(file)) return modules.get(file).exports;
    const result = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      fileName: file.replace(/\.ets$/, '.ts'),
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true },
      reportDiagnostics: true,
    });
    assert.equal(result.diagnostics.length, 0, file);
    const module = { exports: {} };
    modules.set(file, module);
    const requireLocal = id => dependencies[id.split('/').at(-1)] ??
      load(path.resolve(path.dirname(file), id + '.ets'));
    vm.runInNewContext(`(function(require,module,exports){${result.outputText}\n})`, { Observed: value => value })(
      requireLocal, module, module.exports);
    return module.exports;
  }

  const { CharacterViewModel } = load(path.join(root, 'viewmodel/CharacterViewModel.ets'));
  const { CharacterListItem, CharacterDetail } = load(path.join(root, 'model/CharacterData.ets'));
  const model = new CharacterViewModel();
  return {
    model, listCache, detailCache, lists, batches, individual,
    item: id => Object.assign(new CharacterListItem(), { id }),
    detail: (id, name) => Object.assign(new CharacterDetail(), { id, name }),
    transition(pending) {
      session.pending = pending;
      session.revision++;
      for (const listener of Array.from(sessionListeners)) { listener(session.revision); }
    },
    activate() {
      const updates = [];
      model.activate(() => updates.push({
        roster: Array.from(model.items, item => item.id),
        selected: model.selectedId,
        detail: model.detailOfSelected()?.name,
      }));
      return updates;
    },
  };
}

test('cached roster and selected detail publish before fetchList; same-UID refresh prioritizes the selected ID', async () => {
  const h = harness();
  const roster = [h.item(ALPHA), h.item(BETA)];
  h.listCache.set(UID_A, roster);
  h.detailCache.set(UID_A, [h.detail(ALPHA, 'cached alpha'), h.detail(BETA, 'cached beta')]);
  const updates = h.activate();
  const firstLoad = h.model.load(UID_A);
  await turn();
  assert.equal(h.lists.length, 1);
  assert.ok(updates.some(update => update.selected === ALPHA && update.detail === 'cached alpha' &&
    update.roster.join(',') === `${ALPHA},${BETA}`));
  await h.model.select(UID_A, BETA);
  assert.equal(h.model.detailOfSelected()?.name, 'cached beta');
  assert.deepEqual(h.individual, []);
  h.lists[0].resolve(roster);
  await turn();
  assert.deepEqual(h.batches[0].ids, [BETA, ALPHA]);
  h.batches[0].onBatch([h.detail(BETA, 'fresh beta')]);
  h.batches[0].resolve();
  await firstLoad;

  const refresh = h.model.load(UID_A);
  await turn();
  assert.equal(h.model.selectedId, BETA);
  assert.ok(h.model.detailOfSelected());
  h.lists[1].resolve(roster);
  await turn();
  assert.deepEqual(h.batches[1].ids, [BETA, ALPHA]);
  h.batches[1].onBatch([h.detail(BETA, 'refreshed beta')]);
  h.batches[1].resolve();
  await refresh;
  assert.equal(h.model.detailOfSelected()?.name, 'refreshed beta');
});

test('each successful batch publishes before bulk completion; selecting an uncached row joins bulk loading', async () => {
  const h = harness();
  const updates = h.activate();
  const load = h.model.load(UID_A);
  await turn();
  h.lists[0].resolve([h.item(ALPHA), h.item(BETA), h.item(GAMMA)]);
  await turn();
  const bulk = h.batches[0];
  bulk.onBatch([h.detail(ALPHA, 'first batch')]);
  await turn();
  assert.ok(updates.some(update => update.selected === ALPHA && update.detail === 'first batch'));

  const selecting = h.model.select(UID_A, BETA);
  await turn();
  assert.equal(h.model.selectedId, BETA);
  assert.deepEqual(h.individual, []);
  bulk.onBatch([h.detail(BETA, 'second batch')]);
  await turn();
  assert.ok(updates.some(update => update.selected === BETA && update.detail === 'second batch'));

  bulk.reject(new Error('fixture later batch failed'));
  await Promise.all([load, selecting]);
  await turn();
  assert.match(h.model.message, /fixture later batch failed/);
  assert.equal(h.model.detailOfSelected()?.name, 'second batch');
  assert.deepEqual(h.individual, []);
});

test('a UID change discards a late roster and never starts bulk loading for the old UID', async () => {
  const h = harness();
  h.listCache.set(UID_B, [h.item(BETA)]);
  h.detailCache.set(UID_B, [h.detail(BETA, 'cached replacement')]);
  const updates = h.activate();
  const old = h.model.load(UID_A);
  await turn();
  const current = h.model.load(UID_B);
  await turn();
  assert.equal(h.lists[0].isCurrent(), false);
  assert.equal(h.lists[1].isCurrent(), true);
  const updatesBefore = updates.length;
  h.lists[0].resolve([h.item(ALPHA)]);
  await old;
  assert.equal(updates.length, updatesBefore);
  assert.deepEqual(h.batches, []);
  assert.equal(h.model.detailOfSelected()?.name, 'cached replacement');

  h.lists[1].resolve([h.item(BETA)]);
  await turn();
  assert.deepEqual(h.batches.map(request => request.uid), [UID_B]);
  h.batches[0].onBatch([h.detail(BETA, 'fresh replacement')]);
  h.batches[0].resolve();
  await current;
  assert.equal(h.model.detailOfSelected()?.name, 'fresh replacement');
});

test('re-entering the same UID discards late callbacks from the previous attachment', async () => {
  const h = harness();
  const priorUpdates = h.activate();
  const old = h.model.load(UID_A);
  await turn();
  h.lists[0].resolve([h.item(ALPHA)]);
  await turn();
  const prior = h.batches[0];
  h.model.dispose();
  const currentUpdates = h.activate();
  const current = h.model.load(UID_A);
  await turn();
  h.lists[1].resolve([h.item(ALPHA)]);
  await turn();
  const recent = h.batches[1];
  recent.onBatch([h.detail(ALPHA, 'current attachment')]);
  await turn();

  assert.equal(prior.isCurrent(), false);
  assert.equal(recent.isCurrent(), true);
  const oldCount = priorUpdates.length;
  const newCount = currentUpdates.length;
  prior.onBatch([h.detail(ALPHA, 'old attachment')]);
  prior.resolve();
  await old;
  assert.equal(priorUpdates.length, oldCount);
  assert.equal(currentUpdates.length, newCount);
  assert.equal(h.model.detailOfSelected()?.name, 'current attachment');

  recent.resolve();
  await current;
});

test('disposing during a roster request prevents follow-up HTTP and late notifications', async () => {
  const h = harness();
  const updates = h.activate();
  const pending = h.model.load(UID_A);
  await turn();
  h.model.dispose();
  const count = updates.length;
  assert.equal(h.lists[0].isCurrent(), false);
  h.lists[0].resolve([h.item(ALPHA)]);
  await pending;
  assert.equal(updates.length, count);
  assert.deepEqual(h.batches, []);

  const detached = h.model.load(UID_A);
  await turn();
  assert.equal(h.lists.length, 1);
  await detached;
  await h.model.select(UID_A, ALPHA);
  h.transition(false);
  await turn();
  assert.equal(h.lists.length, 1);
  assert.deepEqual(h.individual, []);
});

test('an account transition fences the same UID until the committed session can refresh', async () => {
  const h = harness();
  const updates = h.activate();
  const pending = h.model.load(UID_A);
  await turn();
  h.transition(true);
  const count = updates.length;
  assert.equal(h.lists[0].isCurrent(), false);
  h.lists[0].resolve([h.item(ALPHA)]);
  await pending;
  assert.equal(updates.length, count);
  assert.deepEqual(h.batches, []);

  const waiting = h.model.load(UID_A);
  await turn();
  assert.equal(h.lists.length, 1);
  await waiting;
  h.transition(false);
  await turn();
  assert.deepEqual(h.lists.map(request => request.uid), [UID_A, UID_A]);
  h.lists[1].resolve([h.item(ALPHA)]);
  await turn();
  h.batches[0].onBatch([h.detail(ALPHA, 'committed session')]);
  h.batches[0].resolve();
  await turn();
  assert.equal(h.model.detailOfSelected()?.name, 'committed session');
});
