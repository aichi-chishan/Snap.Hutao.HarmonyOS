const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };

function harness() {
  const state = { owner: 1, pending: false, listeners: new Set(), uid: '100000001',
    archives: [{ id: 1, uid: '100000001', isSelected: true }], reads: [], calls: [], logs: [] };
  const owners = new Map([[1, { id: 1, mid: 'initial' }], [2, { id: 2, mid: 'second' }]]);
  const records = [
    { gachaType: 301, rankType: 5, time: '2026-01-01 00:00:00' },
    { gachaType: 400, rankType: 4, time: '2026-01-01 00:00:01' },
    { gachaType: 301, rankType: 3, time: '2026-01-01 00:00:02' },
    { gachaType: 200, rankType: 3, time: '2026-01-01 00:00:03' },
    { gachaType: 20011, rankType: 5, time: '2026-01-01 00:00:04' },
  ];
  const repo = {
    getAllArchives: async () => {
      const snapshot = state.archives.slice();
      if (state.archiveGate) await state.archiveGate.promise;
      return snapshot;
    },
    getOrCreateArchive: async uid => state.archives.find(a => a.uid === uid),
    getItemsByArchive: async id => { state.reads.push(id); return records.slice(); },
    getItemsByType() { assert.fail('Home must read an archive once rather than once per pool'); },
  };
  const remote = async (name, result) => { state.calls.push(name); const gate = state.gate; if (gate) await gate.promise; return result; };
  const announcementGroups = [
    { typeId: 2, label: '游戏公告', items: [] },
    { typeId: 1, label: '活动公告', items: [1, 2, 3, 4, 5].map(id => ({ id })) },
  ];
  const mocks = {
    GachaRepo: { GachaRepo: repo },
    UserService: { UserService: { getInstance: () => ({
      getCurrentUser: () => state.pending ? undefined : owners.get(state.owner),
      isSessionTransitionPending: () => state.pending,
      addSessionRevisionListener(listener) { state.listeners.add(listener); return () => state.listeners.delete(listener); },
    }) } },
    DailyNoteService: { DailyNoteService: { getInstance: () => ({ trackedEntries: async () => [] }) } },
    SignInService: { SignInService: { getInstance: () => ({ fetchInfo: () => remote('sign-in', { isSign: true, owner: state.owner }) }) } },
    CalendarService: { CalendarEntryOrder: { Home: 1 }, CalendarService: { getInstance: () => ({ fetchCalendar: () => remote('calendar', [{ id: 'activity' }]) }) } },
    RegionalContent: { AnnouncementContext: { forUid: () => ({ region: 'cn_gf01', level: 60, language: 'zh-cn' }) } },
    AnnouncementService: { AnnouncementService: { getInstance: () => ({ fetchGroups: () => remote('announcement', announcementGroups) }) } },
    Logger: { Logger: { warn() {} } },
  };
  const cache = new Map();
  function load(name) {
    if (cache.has(name)) return cache.get(name);
    const text = fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
    const code = ts.transpileModule(text, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true } }).outputText;
    const module = { exports: {} };
    vm.runInNewContext(code, { module, exports: module.exports, Observed: type => type, require: id => {
      const short = id.split('/').at(-1);
      if (short === 'GachaType') return load('model/GachaType');
      if (short === 'GachaHomeStatService') return load('service/GachaHomeStatService');
      return mocks[short] ?? {};
    } });
    cache.set(name, module.exports);
    return module.exports;
  }
  const home = new (load('viewmodel/HomeViewModel').HomeViewModel)();
  const pages = load('service/GachaHomeStatService').GachaHomeStatService;
  return { state, repo, home, pages, index: () => loadIndex(home, pages, state), replaceOwner: user => owners.set(user.id, user),
    publishSession: () => { for (const listener of [...state.listeners]) listener(); } };
}

function loadIndex(home, pages, state) {
  const source = fs.readFileSync(path.join(root, 'pages/Index.ets'), 'utf8');
  const methods = ['aboutToAppear', 'aboutToDisappear', 'reloadHome', 'loadGachaPages'].map(name => {
    const start = source.indexOf(`    ${name}(`);
    const end = source.indexOf('\n    }', start);
    assert.ok(start >= 0 && end > start, name);
    return source.slice(start, end + 6);
  });
  const code = ts.transpileModule(`class Index { static detectWideScreen() { return true; } static pickGreeting() { return ''; }
    loadDashCards() {} ${methods.join('\n')} } result = Index;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2022 },
  }).outputText;
  const globals = {
    AppStorage: { get: key => key === 'currentUid' ? state.uid : undefined, setOrCreate() {} },
    AppLocaleService: { initialize() {} }, AppUpdateService: { skippedTag: () => '', startupCheck() {} },
    PreferencesStore: { getBackgroundImageType: () => 'none', getHomeActCalendar: () => true,
      getHomeActPreview: () => false, getBackgroundFolderPath: () => '' },
    GachaHomeStatService: pages, Logger: { info: (_, message) => state.logs.push(message), warn() {} },
    result: undefined,
  };
  vm.runInNewContext(code, globals);
  return Object.assign(new globals.result(), { homeVm: home, homeRequestSequence: 0, gachaPagesSequence: 0,
    homeReloading: false, gachaPages: [] });
}

test('Home publishes local statistics while network is pending and requests only displayed remote domains', async () => {
  const h = harness(); h.state.gate = deferred();
  const pending = h.home.load('100000001'); await flush();
  assert.equal(h.home.loading, true);
  assert.equal(h.home.gachaLoaded, true);
  assert.equal(h.home.gachaTotal, 4, 'beyond pools remain outside the ordinary home summary');
  assert.deepEqual(h.state.reads, [1]);
  const character = h.home.gachaPools.find(pool => pool.gachaType === 301);
  assert.equal(character.totalCount, 3, 'stored 400 records join pool 301');
  assert.equal(character.sinceLastFive, 2); assert.equal(character.sinceLastFour, 1);
  assert.deepEqual(h.state.calls, ['sign-in', 'calendar', 'announcement']);
  h.state.gate.resolve(); await pending;
  assert.equal(h.home.loading, false); assert.equal(h.home.signInfo.isSign, true);
  assert.deepEqual(Array.from(h.home.announcementGroups, group => group.typeId), [1, 2]);
  assert.equal(h.home.announcementGroups[0].items.length, 5);
});

test('returning to Home keeps current cards until refreshed and clears them immediately for another account', async () => {
  const h = harness(); await h.home.load('100000001');
  const signInfo = h.home.signInfo, activities = h.home.acts, announcements = h.home.announcementGroups;
  const older = deferred(); h.state.gate = older;
  const refreshing = h.home.load('100000001');
  assert.equal(h.home.signInfo, signInfo); assert.equal(h.home.acts, activities);
  assert.equal(h.home.announcementGroups, announcements);
  assert.equal(h.home.gachaTotal, 4);
  h.state.owner = 2; const newer = deferred(); h.state.gate = newer;
  const replacing = h.home.load('100000001');
  assert.equal(h.home.signInfo, undefined); assert.equal(h.home.acts.length, 0);
  assert.equal(h.home.announcementGroups.length, 0);
  assert.equal(h.home.gachaTotal, 0);
  older.resolve(); await refreshing;
  assert.equal(h.home.signInfo, undefined, 'older network results never fill a newer account');
  assert.equal(h.home.announcementGroups.length, 0);
  newer.resolve(); await replacing;
  assert.equal(h.home.signInfo.isSign, true);
});

test('Home archive pager skips a single archive and reads each displayed archive only once', async () => {
  const h = harness();
  assert.equal((await h.pages.loadArchivePages()).length, 0);
  assert.deepEqual(h.state.reads, []);
  h.state.archives.push({ id: 2, uid: '100000002' }, { id: 3, uid: '' });
  h.repo.getOrCreateArchive = () => assert.fail('archive pager is read-only');
  const pages = await h.pages.loadArchivePages();
  assert.deepEqual(h.state.reads, [1, 2]);
  assert.equal(pages.length, 2); assert.equal(pages[0].totalCount(), 4);
  const character = pages[0].pools.find(pool => pool.gachaType === 301);
  assert.equal(character.totalCount, 3); assert.equal(character.sinceLastFive, 2); assert.equal(character.sinceLastFour, 1);
});

test('Index waits for committed identity and reloads the same UID even while the prior account is in flight', async () => {
  const h = harness(), index = h.index();
  const old = deferred(), current = deferred();
  h.state.gate = old;
  index.aboutToAppear();
  await flush();
  assert.equal(h.state.listeners.size, 1);
  assert.equal(index.homeReloading, true);
  assert.equal(h.home.gachaLoaded, true, 'local data is visible before authenticated sources finish');
  assert.deepEqual(h.state.calls, ['sign-in', 'calendar', 'announcement']);

  h.state.pending = true;
  h.publishSession();
  assert.equal(await h.home.load(h.state.uid), false);
  assert.equal(h.state.calls.length, 3, 'an identity still being published cannot start Home requests');
  h.state.owner = 2;
  h.state.gate = current;
  h.state.pending = false;
  h.publishSession();
  assert.equal(h.home.signInfo, undefined);
  assert.equal(h.state.calls.length, 6, 'a committed account reloads even at the same UID');
  old.resolve();
  await flush();
  assert.equal(h.home.signInfo, undefined);
  assert.equal(index.homeReloading, true);
  assert.deepEqual(h.state.logs, []);
  current.resolve();
  await flush();
  assert.equal(h.home.signInfo.owner, 2);
  assert.equal(index.homeReloading, false);
  assert.deepEqual(h.state.logs, ['home data loaded']);
  index.aboutToDisappear();
  assert.equal(h.state.listeners.size, 0);
});

test('Index detach rejects old callbacks and an older archive pager read cannot overwrite a newer result', async () => {
  const h = harness(), index = h.index();
  h.state.archives.push({ id: 2, uid: '100000002' });
  index.aboutToAppear();
  await flush();
  assert.equal(index.gachaPages.length, 2);

  const oldArchive = deferred();
  h.state.archiveGate = oldArchive;
  index.loadGachaPages();
  h.state.archives.pop();
  h.state.archiveGate = undefined;
  index.loadGachaPages();
  await flush();
  assert.equal(index.gachaPages.length, 0);
  oldArchive.resolve();
  await flush();
  assert.equal(index.gachaPages.length, 0);

  h.state.archives.push({ id: 2, uid: '100000002' });
  h.state.archiveGate = deferred();
  h.state.gate = deferred();
  index.reloadHome(true);
  const copied = [...h.state.listeners];
  const loads = h.state.calls.length;
  index.aboutToDisappear();
  for (const listener of copied) listener();
  h.state.archiveGate.resolve();
  h.state.gate.resolve();
  await flush();
  assert.equal(h.state.listeners.size, 0);
  assert.equal(h.state.calls.length, loads);
  assert.equal(index.gachaPages.length, 0);
  assert.deepEqual(h.state.logs, ['home data loaded']);
});

test('Home clears prior cards when a backup replaces the User at the same row ID and UID', async () => {
  const h = harness(), index = h.index();
  index.aboutToAppear();
  await flush();
  assert.ok(h.home.signInfo);
  assert.ok(h.home.acts.length > 0);
  h.state.pending = true;
  h.publishSession();
  h.replaceOwner({ id: 1, mid: 'replaced' });
  h.state.gate = deferred();
  h.state.pending = false;
  h.publishSession();
  assert.equal(h.state.owner, 1);
  assert.equal(h.home.currentUid, h.state.uid);
  assert.equal(h.home.signInfo, undefined);
  assert.equal(h.home.acts.length, 0);
  h.state.gate.resolve();
  await flush();
  assert.ok(h.home.signInfo);
  index.aboutToDisappear();
});

test('deleting the last offline archive publishes an empty result for the same signed-out owner', async () => {
  const h = harness();
  h.state.owner = 0;
  await h.home.load('');
  assert.equal(h.home.gachaTotal, 4);
  h.state.archives = [];
  await h.home.reloadGacha('');
  assert.equal(h.home.gachaLoaded, true);
  assert.equal(h.home.gachaTotal, 0);
  assert.equal(h.home.gachaPools.length, 0);
  assert.equal(h.home.signLoaded, true);
  assert.equal(h.home.signInfo, undefined);
  assert.ok(!h.state.calls.includes('sign-in'));
});
