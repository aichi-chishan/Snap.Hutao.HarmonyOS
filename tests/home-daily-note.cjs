const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };

function note(resin = 50) {
  return { currentResin: resin, maxResin: 200, currentHomeCoin: 100, maxHomeCoin: 2400,
    finishedTaskNum: 1, totalTaskNum: 4, resinDiscountNumLimit: 3, refreshTime: 10,
    currentExpeditionNum: 0, maxExpeditionNum: 5, expeditions: [],
    resinDiscountUsedNum: () => 1, resinReached: threshold => resin >= threshold,
    homeCoinReached: threshold => 100 >= threshold, dailyTask: { isAllFinished: () => false },
    formattedHomeCoin: () => '100/2400',
    formattedTask: () => '1/4', formattedResinDiscount: () => '1/3',
    resinRecoveryTargetText: () => '将于 11.16 18:00 全部恢复',
    transformerMainText: () => '冷却中', transformerSubText: () => '3 天后可再次使用',
    transformer: { hasTransformer: () => true, text: () => '3 天', isReady: () => false } };
}

function harness() {
  const state = { tracked: [], readGate: undefined, refreshGate: undefined, reads: 0, refreshes: 0,
    selectedUserId: 1, selectedUid: '100000001', revision: 1,
    summary: { total: 3, succeeded: 3, firstError: '' } };
  const owners = [{ id: 1 }, { id: 2 }];
  const userService = {
    sessionRevision: () => state.revision,
    isSessionTransitionPending: () => false,
    getCurrentUser: () => owners.find(user => user.id === state.selectedUserId),
    switchUser() { assert.fail('Home must not switch the selected account'); },
  };
  const dailyService = {
    async trackedEntries() {
      state.reads++; const snapshot = state.tracked.slice(); const gate = state.readGate;
      if (gate) await gate.promise;
      return snapshot;
    },
    async refreshTrackedList() {
      state.refreshes++;
      if (state.refreshGate) await state.refreshGate.promise;
      return state.summary;
    },
    refresh() { assert.fail('Home must not refresh foreign UIDs using the current-account endpoint'); },
  };
  const mocks = {
    DailyNoteService: { DailyNoteService: { getInstance: () => dailyService } },
    UserService: { UserService: { getInstance: () => userService } },
    Logger: { Logger: { warn() {} } },
  };
  function load(name, component = false) {
    let source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8').replaceAll('\r\n', '\n');
    if (component) {
      source = source.slice(0, source.indexOf('  @Builder')) + '}';
      source = source.replace('@Component\n', '').replace('export struct HomeDailyNoteCard', 'export class HomeDailyNoteCard');
    }
    const compiled = ts.transpileModule(source, { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true,
    }, reportDiagnostics: true });
    assert.equal(compiled.diagnostics.length, 0, name);
    const module = { exports: {} };
    vm.runInNewContext(compiled.outputText, { module, exports: module.exports, Observed: type => type,
      Prop() {}, State() {}, Watch: () => () => {}, StorageProp: () => () => {},
      $r: name => name,
      require: id => mocks[id.split('/').at(-1)] ?? {} });
    return module.exports;
  }
  const { HomeViewModel, HomeNoteEntry } = load('viewmodel/HomeViewModel');
  const home = new HomeViewModel(); home.currentUid = state.selectedUid;
  // Other Home domains are irrelevant to these note ownership/presentation tests.
  for (const method of ['loadGacha', 'loadSignIn', 'loadActs', 'loadAnnouncements', 'loadChallenges']) home[method] = async () => {};
  mocks.DateUtil = load('common/DateUtil');
  const { DailyNote } = load('model/DailyNote');
  const { HomeDailyNoteCard } = load('components/HomeDailyNoteCard', true);
  return { state, home, HomeNoteEntry, DailyNote, Card: HomeDailyNoteCard, card: new HomeDailyNoteCard() };
}

test('Home includes all tracked account-role pairs, keeps thresholds and includes uncached roles', async () => {
  const { state, home } = harness();
  state.tracked = [
    { userId: 1, uid: '100000001', record: { note: note(), resinNotifyThreshold: 100, homeCoinNotifyThreshold: 1000 } },
    { userId: 2, uid: '100000001', record: { note: note(80), resinNotifyThreshold: 160, homeCoinNotifyThreshold: 2200 } },
    { userId: 2, uid: '100000002' },
  ];
  await home.reloadNote(state.selectedUid);
  assert.deepEqual(Array.from(home.noteEntries, row => [row.userId, row.uid, row.resinThreshold, row.homeCoinThreshold]),
    [[1, '100000001', 100, 1000], [2, '100000001', 160, 2200], [2, '100000002', 120, 1800]]);
  assert.equal(home.noteEntries[2].note, undefined); assert.equal(home.noteLoaded, true);
  assert.equal(state.selectedUserId, 1); assert.equal(state.selectedUid, '100000001');
  state.selectedUserId = 0; await home.load('');
  assert.equal(home.noteEntries.length, 3, 'saved tracked roles remain visible without selecting their account');
  state.tracked = []; await home.load('100000009');
  assert.equal(home.noteEntries.length, 0, 'an untracked current UID is not silently added');
});

test('card selection and rendering keys distinguish equal UIDs owned by different accounts', () => {
  const { HomeNoteEntry, Card, card } = harness();
  const first = new HomeNoteEntry(); first.userId = 1; first.uid = '100000001';
  const second = new HomeNoteEntry(); second.userId = 2; second.uid = first.uid;
  assert.notEqual(Card.entryKey(first), Card.entryKey(second));
  first.note = note(); second.note = note();
  assert.notEqual(Card.entryKey(first), Card.entryKey(second));
  card.entries = [first, second]; card.aboutToAppear(); card.selectPage(1);
  card.entries = []; card.onEntriesChanged();
  card.entries = [second, first]; card.onEntriesChanged();
  assert.equal(card.entries[card.pageIndex].userId, 2, 'a cache reload/reorder preserves the displayed owner');
  const key = Card.entryKey(second); second.note.currentResin = 99;
  assert.notEqual(Card.entryKey(second), key, 'changed values still rebuild multi-argument Builder output');
  card.entries = [first]; card.onEntriesChanged();
  assert.equal(card.pageIndex, 0); assert.equal(card.displayedKey, '1:100000001');
});

test('note card title follows the displayed account-role and its own refresh timestamp', () => {
  const { HomeNoteEntry, card } = harness();
  assert.equal(card.heading(), 'app.string.card_daily_note_title');
  assert.equal(card.refreshTimeText(), '尚未刷新');
  const first = new HomeNoteEntry();
  first.userId = 1; first.uid = '100000001'; first.note = note();
  first.note.refreshTime = new Date(2026, 10, 16, 18, 19, 37).getTime();
  const second = new HomeNoteEntry();
  second.userId = 2; second.uid = '100000002'; second.note = note(140);
  second.note.refreshTime = new Date(2026, 10, 16, 19, 20, 38).getTime();
  card.entries = [first, second]; card.aboutToAppear();
  assert.equal(card.heading(), first.uid);
  assert.equal(card.refreshTimeText(), '刷新于 11.16 18:19:37');
  card.selectPage(1);
  assert.equal(card.heading(), second.uid);
  assert.equal(card.refreshTimeText(), '刷新于 11.16 19:20:38');
  card.entries = [second, first]; card.onEntriesChanged();
  assert.equal(card.heading(), second.uid);
  assert.equal(card.refreshTimeText(), '刷新于 11.16 19:20:38');
});

test('note card preserves threshold dots and uses compact transformer and locked-home states', () => {
  const { HomeNoteEntry, DailyNote, Card } = harness();
  const entry = new HomeNoteEntry();
  entry.userId = 1; entry.uid = '100000001'; entry.resinThreshold = 120; entry.homeCoinThreshold = 1800;
  entry.note = DailyNote.fromJson({ current_resin: 119, max_resin: 200, current_home_coin: 1800, max_home_coin: 2400,
    finished_task_num: 4, total_task_num: 4, resin_discount_num_limit: 3, remain_resin_discount_num: 2,
    transformer: { obtained: true, recovery_time: { day: 3, reached: false } } });
  assert.equal(Card.value(entry, 0), '119/200');
  assert.equal(Card.value(entry, 1), '1800/2400');
  assert.equal(Card.value(entry, 2), '4/4');
  assert.equal(Card.value(entry, 3), '1/3');
  assert.equal(Card.value(entry, 4), '冷却中');
  assert.equal(Card.hasDot(entry, 0), false);
  assert.equal(Card.hasDot(entry, 1), true);
  assert.equal(Card.hasDot(entry, 2), true);
  assert.equal(Card.hasDot(entry, 4), false);
  const beforeThreshold = Card.entryKey(entry);
  entry.resinThreshold = 100;
  assert.equal(Card.hasDot(entry, 0), true);
  assert.notEqual(Card.entryKey(entry), beforeThreshold);
  entry.note.transformer.reached = true;
  assert.equal(Card.value(entry, 4), '可使用');
  assert.equal(Card.hasDot(entry, 4), true);
  entry.note.transformer.obtained = false; entry.note.transformer.reached = false; entry.note.transformer.day = 0;
  assert.equal(Card.value(entry, 4), '尚未获得');
  entry.note.maxHomeCoin = 0;
  assert.equal(Card.value(entry, 1), '尚未解锁洞天');
  entry.note = undefined;
  assert.equal(Card.value(entry, 0), '');
  assert.equal(Card.hasDot(entry, 0), false);
});

test('refresh uses the existing owned all-role operation once and reports partial failures', async () => {
  const { state, home } = harness(); state.tracked = [{ userId: 2, uid: '100000002' }];
  await home.reloadNote(state.selectedUid);
  state.summary = { total: 3, succeeded: 2, firstError: '另一个账号需要重新登录' };
  state.refreshGate = deferred();
  const pending = home.refreshNotes();
  assert.equal(home.noteRefreshing, true); assert.equal(await home.refreshNotes(), '');
  assert.equal(state.refreshes, 1);
  state.refreshGate.resolve(); const message = await pending;
  assert.match(message, /2\/3/); assert.match(message, /需要重新登录/);
  assert.equal(state.reads, 2); assert.equal(home.noteRefreshing, false);
  assert.equal(state.selectedUserId, 1); assert.equal(state.selectedUid, '100000001');
});

test('a later cache read wins over an older tracked-list snapshot', async () => {
  const { state, home } = harness(); state.tracked = [{ userId: 1, uid: '100000001' }];
  state.readGate = deferred(); const oldGate = state.readGate;
  const older = home.reloadNote(state.selectedUid);
  state.tracked = [{ userId: 2, uid: '100000002' }]; state.readGate = undefined;
  await home.reloadNote(state.selectedUid);
  oldGate.resolve(); await older;
  assert.equal(home.noteEntries[0].userId, 2); assert.equal(home.noteEntries[0].uid, '100000002');
});

test('account or Home replacement suppresses old refresh presentation without changing the selected account', async () => {
  for (const change of ['session', 'home']) {
    const { state, home } = harness(); state.tracked = [{ userId: 1, uid: '100000001' }];
    await home.reloadNote(state.selectedUid); state.refreshGate = deferred();
    const pending = home.refreshNotes();
    if (change === 'session') { state.selectedUserId = 2; state.revision++; }
    else { await home.load('100000002'); }
    const reads = state.reads;
    state.refreshGate.resolve(); assert.equal(await pending, '');
    assert.equal(state.reads, reads, 'stale work does not start another cache read for a new Home context');
    assert.equal(home.noteRefreshing, false);
    assert.equal(state.selectedUserId, change === 'session' ? 2 : 1);
  }
});
