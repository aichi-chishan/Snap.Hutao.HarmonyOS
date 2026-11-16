// Run actual service statistics and card lifecycle handlers with database and native storage boundaries replaced.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const turn = () => new Promise(resolve => setImmediate(resolve));

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

// Execute the callbacks bound by the actual ArkUI builders; native layout remains in the SDK checks.
function clickHandlers(source, method, card, page) {
  const start = source.indexOf('  ' + method + '(');
  const end = method === 'archivePage' ? source.indexOf('  build() {', start) : source.length;
  assert.ok(start >= 0 && end > start, method);
  const section = source.slice(start, end);
  const handlers = [];
  let position = section.indexOf('.onClick(');
  while (position >= 0) {
    const callbackStart = position + '.onClick('.length;
    const scanner = ts.createScanner(ts.ScriptTarget.ES2022, true, ts.LanguageVariant.Standard,
      section.slice(callbackStart));
    let depth = 1;
    while (depth > 0) {
      const token = scanner.scan();
      assert.notEqual(token, ts.SyntaxKind.EndOfFileToken);
      if (token === ts.SyntaxKind.OpenParenToken) { depth++; }
      if (token === ts.SyntaxKind.CloseParenToken) { depth--; }
    }
    const callbackEnd = callbackStart + scanner.getTokenPos();
    const callback = section.slice(callbackStart, callbackEnd);
    const code = ts.transpileModule('export function bind(page) { return ' + callback + '; }', {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    }).outputText;
    const module = { exports: {} };
    vm.runInNewContext(code, { module, exports: module.exports });
    handlers.push(module.exports.bind.call(card, page));
    position = section.indexOf('.onClick(', callbackEnd);
  }
  return handlers;
}

function harness() {
  const state = {
    archives: [],
    records: new Map(),
    archiveReads: 0,
    recordReads: [],
    selections: [],
    publications: [],
    archiveGate: undefined,
    navigations: [],
  };
  const values = new Map();
  const storageBindings = new Map();
  const watchBindings = new Map();
  const subscribers = new Set();
  const goals = [{ Id: 1, Name: 'fixture category', Order: 1 }];
  const achievements = [5, 10, 20, 5, 10, 5, 5].map((reward, index) => ({
    Id: 101 + index,
    Title: 'achievement ' + (101 + index),
    Description: '',
    Goal: 1,
    Order: index,
    FinishReward: { Id: 201, Count: reward },
  }));
  const repo = {
    async getAllArchives() {
      state.archiveReads++;
      const snapshot = state.archives.map(archive => ({ ...archive }));
      const gate = state.archiveGate;
      if (gate) { await gate.promise; }
      return snapshot;
    },
    async getRecords(archiveId) {
      state.recordReads.push(archiveId);
      return new Map(Array.from(state.records.get(archiveId) ?? [], ([id, record]) => [id, { ...record }]));
    },
    async selectArchive(id) {
      state.selections.push(id);
      assert.ok(state.archives.some(archive => archive.id === id), 'select an existing archive');
      state.archives = state.archives.map(archive => ({ ...archive, isSelected: archive.id === id }));
    },
    async deleteArchive(id) {
      state.archives = state.archives.filter(archive => archive.id !== id);
      state.records.delete(id);
    },
  };
  const appStorage = {
    get: key => values.get(key),
    setOrCreate(key, value) {
      if (values.get(key) === value) { return; }
      values.set(key, value);
      state.publications.push([key, value]);
      for (const instance of subscribers) {
        for (const [field, storageKey] of storageBindings) {
          if (storageKey !== key) { continue; }
          instance[field] = value;
          const watcher = watchBindings.get(field);
          if (watcher) { instance[watcher](); }
        }
      }
    },
  };
  const mocks = {
    '@kit.ArkTS': { util: {} },
    AppContext: { AppContextProvider: { getResourceManager() { assert.fail('fixture official metadata must be available'); } } },
    AchievementRepo: { AchievementRepo: repo },
    WikiMetaService: { WikiMetaService: { cleanText: text => text } },
    LocalizedGameDataService: { LocalizedGameDataService: {
      current: () => 'zh-Hans',
      readMetadataFile: async name => JSON.stringify(name === 'Achievement.json' ? achievements : goals),
    } },
    GameDataService: { GameDataDomain: { Achievement: 'achievement' }, GameDataService: {
      getInstance: () => ({ remoteVersion: () => 'fixture-v1', readText: async () => '{}' }),
    } },
    Logger: { Logger: { info() {}, warn() {} } },
    PressCard: {},
    NavIcon: {},
  };
  const modules = new Map();
  function load(name) {
    const file = path.resolve(root, name + '.ets');
    if (modules.has(file)) { return modules.get(file).exports; }
    let source = fs.readFileSync(file, 'utf8').replaceAll('\r\n', '\n');
    if (name === 'components/HomeAchievementCard') {
      const builderStart = source.indexOf('  @Builder');
      const buildStart = source.indexOf('  build() {');
      const end = builderStart >= 0 ? Math.min(builderStart, buildStart < 0 ? Infinity : buildStart) : buildStart;
      assert.ok(end > 0, 'native layout starts after card handlers');
      source = source.slice(0, end) + '\n}';
      source = source.replace('@Component\n', '').replace('export struct HomeAchievementCard', 'export class HomeAchievementCard');
    }
    const compiled = ts.transpileModule(source, {
      fileName: file.replace(/\.ets$/, '.ts'),
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true },
      reportDiagnostics: true,
    });
    assert.equal(compiled.diagnostics.length, 0, file);
    const module = { exports: {} };
    modules.set(file, module);
    const requireLocal = id => mocks[id] ?? mocks[id.split('/').at(-1)] ??
      load(path.relative(root, path.resolve(path.dirname(file), id)));
    vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`, {
      AppStorage: appStorage,
      $r: id => ({ id }),
      Observed: type => type,
      Prop() {},
      State() {},
      StorageProp: key => (_target, field) => { storageBindings.set(field, key); },
      Watch: handler => (_target, field) => { watchBindings.set(field, handler); },
    })(requireLocal, module, module.exports);
    return module.exports;
  }

  const { AchievementService: service } = load('service/AchievementService');
  const { HomeAchievementCard: Card } = load('components/HomeAchievementCard');
  const card = new Card();
  subscribers.add(card);
  card.onTap = () => state.navigations.push(state.archives.find(archive => archive.isSelected)?.id ?? 0);
  const cardSource = fs.readFileSync(path.join(root, 'components/HomeAchievementCard.ets'), 'utf8').replaceAll('\r\n', '\n');
  return {
    state, card, service,
    archive(id, isSelected = false, name = 'same name', createdAt = 0) {
      return { id, isSelected, name, createdAt };
    },
    record(archiveId, achId, status, timestamp) {
      return { archiveId, achId, status, timestamp, current: 0 };
    },
    async attach() {
      card.aboutToAppear();
      await turn();
    },
    headerClick: () => clickHandlers(cardSource, 'build', card)[0](),
    emptyClick: () => clickHandlers(cardSource, 'build', card)[1](),
    archiveClick: () => clickHandlers(cardSource, 'archivePage', card, card.pages[card.pageIndex])[0](),
    displayedId: () => card.pages[card.pageIndex]?.archive.id ?? 0,
  };
}

test('archive summaries count known completions and rewards once per archive and rank recent valid times first', async () => {
  const h = harness();
  h.state.archives = [h.archive(11, true), h.archive(22), h.archive(33)];
  h.state.records.set(11, new Map([
    [101, h.record(11, 101, 3, 1700000010)],
    [102, h.record(11, 102, 2, 1700000030)],
    [103, h.record(11, 103, 1, 1700001000)],
    [104, h.record(11, 104, 3, 0)],
    [105, h.record(11, 105, 3, -62135596800)],
    [106, h.record(11, 106, 3, 253402300799)],
    [107, h.record(11, 107, 0, 1700000090)],
    [999, h.record(11, 999, 3, 1700009999)],
  ]));
  h.state.records.set(22, new Map([[101, h.record(22, 101, 1, 1700009999)]]));
  h.state.records.set(33, new Map([
    [104, h.record(33, 104, 3, 0)],
    [105, h.record(33, 105, 3, -1)],
    [106, h.record(33, 106, 3, 253402271999)],
  ]));

  const summaries = await h.service.getArchiveSummaries();
  assert.deepEqual(h.state.recordReads, [11, 22, 33]);
  assert.deepEqual(Array.from(summaries, page => page.archive.id), [11, 22, 33]);
  assert.equal(summaries[0].stats.total, 7);
  assert.equal(summaries[0].stats.done, 5);
  assert.equal(summaries[0].stats.primogemsTotal, 60);
  assert.equal(summaries[0].stats.primogemsEarned, 35);
  assert.deepEqual(Array.from(summaries[0].recent, completion => [completion.entry.id, completion.timestamp]),
    [[102, 1700000030], [101, 1700000010]]);
  assert.equal(summaries[1].stats.done, 0);
  assert.equal(summaries[1].recent.length, 0);
  assert.equal(summaries[2].recent.length, 2);
  assert.ok(summaries[2].recent.every(completion => completion.timestamp === 0));

  const snapshot = new Map([[101, h.record(11, 101, 3, 1700000010)]]);
  const stats = await h.service.getOverallStats(11, snapshot);
  assert.equal(stats.done, 1);
  assert.equal(stats.primogemsEarned, 5);
  assert.deepEqual(h.state.recordReads, [11, 22, 33], 'the supplied record snapshot avoids another database read');
});

test('empty, single and same-name multi-archive cards load without selecting an archive while paging', async () => {
  const h = harness();
  assert.deepEqual(Array.from(await h.service.getArchiveSummaries()), []);
  assert.deepEqual(h.state.recordReads, []);
  await h.attach();
  assert.equal(h.card.loaded, true);
  assert.equal(h.card.pages.length, 0);

  h.state.archives = [h.archive(11, true)];
  h.card.onDataChanged();
  await turn();
  assert.equal(h.card.pages.length, 1);
  assert.equal(h.displayedId(), 11);

  h.state.archives = [h.archive(11), h.archive(22, true), h.archive(33)];
  h.card.onDataChanged();
  await turn();
  assert.equal(h.card.pages.length, 3);
  assert.equal(h.displayedId(), 22);
  const reads = h.state.recordReads.slice();
  const archiveReads = h.state.archiveReads;
  h.card.selectPage(2);
  assert.equal(h.displayedId(), 33, 'equal names keep separate archive identities');
  h.card.selectPage(0);
  assert.equal(h.displayedId(), 11);
  assert.deepEqual(h.state.recordReads, reads);
  assert.equal(h.state.archiveReads, archiveReads);
  assert.deepEqual(h.state.selections, []);
});

test('data reload preserves the browsed identity, follows an external selection and recovers after deletion', async () => {
  const h = harness();
  h.state.archives = [h.archive(11, true), h.archive(22), h.archive(33)];
  await h.attach();
  h.card.selectPage(1);
  assert.equal(h.displayedId(), 22);
  h.state.records.set(22, new Map([[101, h.record(22, 101, 3, 1700000010)]]));
  h.state.archives = [h.archive(33), h.archive(11, true), h.archive(22), h.archive(44)];
  h.card.onDataChanged();
  await turn();
  assert.equal(h.displayedId(), 22, 'reordering and additions preserve the currently browsed ID');
  assert.equal(h.card.pages[h.card.pageIndex].stats.done, 1);

  await h.service.selectArchive(33);
  await turn();
  assert.equal(h.displayedId(), 33, 'a different externally selected archive becomes visible');
  h.card.selectPage(h.card.pages.findIndex(page => page.archive.id === 22));
  await h.service.deleteArchive(22);
  await turn();
  assert.ok(h.card.pages.some(page => page.archive.id === h.displayedId()));
  assert.equal(h.displayedId(), 33);
});

test('a newer reload wins over a late snapshot or error, and detaching blocks previous-attachment updates', async () => {
  for (const lateError of [false, true]) {
    const h = harness();
    const gate = deferred();
    h.state.archives = [h.archive(11, true)];
    h.state.archiveGate = gate;
    h.card.aboutToAppear();
    h.state.archives = [h.archive(22, true)];
    h.state.archiveGate = undefined;
    await h.card.reload();
    assert.equal(h.displayedId(), 22);
    if (lateError) { gate.reject(new Error('old read failed')); } else { gate.resolve(); }
    await turn();
    assert.equal(h.displayedId(), 22);
    assert.equal(h.card.loaded, true);

    const priorGate = deferred();
    h.state.archives = [h.archive(33, true)];
    h.state.archiveGate = priorGate;
    const prior = h.card.reload();
    h.card.aboutToDisappear();
    h.state.archives = [h.archive(44, true)];
    h.state.archiveGate = undefined;
    await h.attach();
    priorGate.resolve();
    await prior;
    assert.equal(h.displayedId(), 44);
  }
});

test('the header and archive body open management with the saved selection after browsing a different page', async () => {
  for (const click of ['headerClick', 'archiveClick']) {
    const h = harness();
    h.state.archives = [h.archive(11, true), h.archive(22)];
    await h.attach();
    h.card.selectPage(1);
    const archiveReads = h.state.archiveReads;
    const recordReads = h.state.recordReads.slice();
    await h[click]();
    assert.deepEqual(h.state.navigations, [11], click);
    assert.deepEqual(h.state.selections, []);
    assert.deepEqual(h.state.publications, []);
    assert.equal(h.state.archiveReads, archiveReads, 'opening management does not query archives');
    assert.deepEqual(h.state.recordReads, recordReads, 'opening management does not query records');
    assert.equal(h.displayedId(), 22, 'the browsed page is a local presentation choice');
    const saved = await h.service.getArchives();
    assert.equal(saved.find(archive => archive.isSelected).id, 11, 'management can restore its previously saved archive');
  }
});

test('the empty state and header both open management without any archive or record lookup', async () => {
  for (const click of ['headerClick', 'emptyClick']) {
    const h = harness();
    await h.attach();
    const reads = h.state.archiveReads;
    await h[click]();
    assert.deepEqual(h.state.navigations, [0], click);
    assert.equal(h.state.archiveReads, reads);
    assert.deepEqual(h.state.recordReads, []);
    assert.deepEqual(h.state.selections, []);
  }
});

test('a stale browsed page still opens management using the current saved archive', async () => {
  for (const reuseId of [false, true]) {
    const h = harness();
    h.state.archives = [h.archive(11, true), h.archive(22, false, 'original', 100)];
    await h.attach();
    h.card.selectPage(1);
    h.state.archives = reuseId
      ? [h.archive(11, true), h.archive(22, false, 'restored replacement', 200)]
      : [h.archive(11, true)];
    const reads = h.state.archiveReads;
    await h.archiveClick();
    assert.deepEqual(h.state.navigations, [11]);
    assert.deepEqual(h.state.selections, []);
    assert.equal(h.state.archiveReads, reads);
  }
});

test('detached header and archive body callbacks do not navigate or query storage', async () => {
  const h = harness();
  h.state.archives = [h.archive(11, true), h.archive(22)];
  await h.attach();
  h.card.selectPage(1);
  h.card.aboutToDisappear();
  const reads = h.state.archiveReads;
  await h.headerClick();
  await h.archiveClick();
  assert.deepEqual(h.state.navigations, []);
  assert.deepEqual(h.state.selections, []);
  assert.equal(h.state.archiveReads, reads);
});

test('the failed empty state retries its existing load action', async () => {
  const h = harness();
  const gate = deferred();
  h.state.archiveGate = gate;
  h.card.aboutToAppear();
  gate.reject(new Error('fixture read failed'));
  await turn();
  assert.equal(h.card.loadFailed, true);
  h.state.archiveGate = undefined;
  h.state.archives = [h.archive(11, true)];
  await h.emptyClick();
  await turn();
  assert.equal(h.displayedId(), 11);
  assert.equal(h.card.loadFailed, false);
  assert.deepEqual(h.state.navigations, []);
});
