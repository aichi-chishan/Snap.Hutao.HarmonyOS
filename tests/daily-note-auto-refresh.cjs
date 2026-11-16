const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const sourceRoot = path.join(__dirname, '../entry/src/main/ets');
const compiled = new Map();
const SECOND = 1000;
const MINUTE = 60 * SECOND;
const INTERVAL = 4 * MINUTE;
const REGION = 'cn_gf01';
const CURRENT = '100000001';
const SHARED = '100000002';
const OTHER = '100000003';
const FRESH = '100000004';
const flush = () => new Promise(resolve => setImmediate(resolve));

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function virtualClock() {
  let now = Date.UTC(2026, 10, 12, 1);
  let nextId = 0;
  const tasks = new Map();

  class ClockDate extends Date {
    constructor(...args) { super(...(args.length > 0 ? args : [now])); }
    static now() { return now; }
  }

  function add(callback, delay, interval = 0) {
    const id = ++nextId;
    tasks.set(id, { callback, at: now + delay, interval });
    return id;
  }

  return {
    Date: ClockDate,
    now: () => now,
    setTimeout: (callback, delay) => add(callback, delay),
    setInterval: (callback, delay) => add(callback, delay, delay),
    clearTimer: id => tasks.delete(id),
    intervals: () => [...tasks.values()].filter(task => task.interval > 0).map(task => task.interval),
    hasTimeout: () => [...tasks.values()].some(task => task.interval === 0),
    async advance(ms) {
      await flush();
      const end = now + ms;
      while (true) {
        const next = [...tasks.entries()].filter(([, task]) => task.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        const [id, task] = next;
        now = task.at;
        if (task.interval > 0) task.at += task.interval;
        else tasks.delete(id);
        task.callback();
        await flush();
      }
      now = end;
      await flush();
    },
  };
}

function fixture() {
  const clock = virtualClock();
  const state = {
    ready: true, enabled: true, intervalMinutes: 4, userId: 1, uid: CURRENT, revision: 0,
    sessionPending: false, backupJournal: '',
  };
  const hooks = {};
  const calls = {
    requests: [], reads: [], upserts: [], writes: [], notices: [], reminders: [], webhooks: [],
    snapshots: [], forms: [], trackingWrites: [], verification: [], credentialRefresh: [],
  };
  const users = new Map();
  const tracked = new Map();
  const notes = new Map();
  const storage = new Map([['currentUid', CURRENT], ['isLoggedIn', true]]);
  const key = (owner, uid) => `${owner}/${uid}`;
  let selectedUser;
  let snapshot = { userId: 0, uid: '', epoch: -1 };
  let snapshotData = {};

  function record(note, previous) {
    return { note, resinNotifyThreshold: previous?.resinNotifyThreshold ?? 120,
      homeCoinNotifyThreshold: previous?.homeCoinNotifyThreshold ?? 1800, notifyFlags: previous?.notifyFlags ?? 1 };
  }

  const mocks = {
    '@kit.FormKit': {
      formProvider: {
        getPublishedRunningFormInfos: async () => [{ formId: 'fixture-form' }],
        updateForm: async (id, data) => { calls.forms.push({ id, data }); },
      },
      formBindingData: { createFormBindingData: data => ({ ...data }) },
    },
    'common/AppContext': { AppContextProvider: { getAppContext: () => ({}) } },
    'common/Logger': { Logger: { info() {}, warn() {}, error() {} } },
    'data/prefs/PreferencesStore': { PreferencesStore: {
      isReady: () => state.ready,
      getAutoRefreshEnabled() { assert.ok(state.ready); return state.enabled; },
      getRefreshIntervalMinutes() { assert.ok(state.ready); return state.intervalMinutes; },
      getCurrentUid: () => state.uid,
      getBackupJournal: () => state.backupJournal,
      getTrackedUids: id => [...(tracked.get(id) ?? [])],
      setTrackedUids(id, uids) { calls.trackingWrites.push({ id, uids }); tracked.set(id, [...uids]); },
      getString: (name, fallback) => name === 'dailynote.webhook_url' ? 'https://example.invalid/note' : fallback,
    } },
    'data/repo/UserRepo': { UserRepo: {
      getAllUsers: async () => [...users.values()].map(user => user.clone()),
      getUserById: async id => users.get(id)?.clone(),
      getSelectedUserId: async () => state.userId,
      getDefaultRole: async id => users.get(id)?.roles.find(role => role.gameUid === state.uid),
    } },
    'data/repo/BackgroundTaskRepo': { BackgroundTaskRepo: { init: async () => {}, get: async () => ({ epoch: 1 }) } },
    'service/UserService': { UserService: {
      getInstance: () => ({
        getCurrentUser: () => selectedUser,
        sessionRevision: () => state.revision,
        isSessionTransitionPending: () => state.sessionPending,
        completeTokenChainPublic: async user => { calls.credentialRefresh.push(user.id); },
      }),
      isCookieAuthError: response => response.isAuthExpired(),
      async retryWithRefreshedCookie(user, request) {
        calls.credentialRefresh.push(user.id);
        return request();
      },
    } },
    'data/network/HoyolabClient': { HoyolabClient: {
      async fetchDailyNote(uid, region, cookie, headers) {
        const owner = [...users.values()].find(user => user.gameRecordCookie() === cookie);
        assert.ok(owner, 'request must use an actual fixture owner’s cookie');
        const request = { owner: owner.id, uid, region, headers: { ...headers } };
        calls.requests.push(request);
        return hooks.fetch ? hooks.fetch(request) : response();
      },
    } },
    'data/repo/DailyNoteRepo': { DailyNoteRepo: {
      async get(owner, uid) {
        const entry = key(owner, uid);
        calls.reads.push(entry);
        if (hooks.read) await hooks.read(entry);
        return notes.get(entry);
      },
      async upsert(owner, uid, note, guard) {
        const entry = key(owner, uid);
        calls.upserts.push(entry);
        if (hooks.beforeCommit) await hooks.beforeCommit(entry);
        if (guard !== undefined && !await guard()) return;
        notes.set(entry, record(note, notes.get(entry)));
        calls.writes.push(entry);
      },
    } },
    'data/local/NotificationHelper': { NotificationHelper: {
      isEnabled: () => true,
      publish: async (title, text, id) => { calls.notices.push({ title, text, id }); },
    } },
    'service/DailyNoteReminderService': { DailyNoteReminderService: {
      ERROR_KEY: 'fixtureReminderError',
      sync: async (owner, uid) => { calls.reminders.push(key(owner, uid)); },
    } },
    'data/local/FormSnapshot': { FormSnapshot: {
      empty: () => ({}),
      owner: () => ({ ...snapshot }),
      load: () => ({ ...snapshotData }),
      save(resin, _max, _expedition, _daily, _coin, _nickname, _time, _recovery, userId, uid, epoch) {
        snapshot = { userId, uid, epoch };
        snapshotData = { resin };
        calls.snapshots.push(key(userId, uid));
      },
      clear() { snapshot = { userId: 0, uid: '', epoch: -1 }; snapshotData = {}; },
    } },
    'data/network/DailyNoteWebhookClient': { DailyNoteWebhookClient: {
      send: async (_url, uid) => { calls.webhooks.push(uid); },
    } },
    'data/network/CardVerifyApi': { DAILY_NOTE_PATH: '/fixture/daily-note' },
    'data/network/RiskVerifier': { RiskVerifier: {
      async tryResolveRisk() { calls.verification.push('prompt'); return 'fixture-result'; },
    } },
  };

  const modules = new Map();
  const math = Object.create(Math);
  math.random = () => 0;
  const context = vm.createContext({
    Date: clock.Date, Math: math,
    setTimeout: clock.setTimeout, clearTimeout: clock.clearTimer,
    setInterval: clock.setInterval, clearInterval: clock.clearTimer,
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
  });

  function load(name) {
    if (Object.hasOwn(mocks, name)) return mocks[name];
    if (modules.has(name)) return modules.get(name).exports;
    let code = compiled.get(name);
    if (!code) {
      const file = path.join(sourceRoot, name + '.ets');
      const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
        fileName: file.replace(/\.ets$/, '.ts'), reportDiagnostics: true,
        compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
      });
      assert.equal(output.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0, name);
      code = new vm.Script(`(function (require, module, exports) { ${output.outputText}\n})`, { filename: file });
      compiled.set(name, code);
    }
    const module = { exports: {} };
    modules.set(name, module);
    code.runInContext(context)(id => {
      if (id.startsWith('.')) return load(path.posix.join(path.posix.dirname(name), id));
      assert.ok(Object.hasOwn(mocks, id), `unexpected platform dependency ${id}`);
      return mocks[id];
    }, module, module.exports);
    return module.exports;
  }

  const { User } = load('model/User');
  const { UserGameRole } = load('model/UserGameRole');
  const { DailyNote } = load('model/DailyNote');
  const { ApiResponse } = load('model/ApiResponse');
  const { DailyNoteService, KEY_NOTE_VERSION, KEY_NOTE_ERROR } = load('service/DailyNoteService');
  const service = DailyNoteService.getInstance();

  function response(retcode = 0, data = {
    current_resin: 160, max_resin: 200, is_extra_task_reward_received: true,
  }) {
    return ApiResponse.fromJson(JSON.stringify({ retcode, data }));
  }

  function account(id, ...uids) {
    const user = new User();
    user.id = id;
    user.aid = String(id);
    user.mid = `owner-${id}`;
    user.createdAt = id;
    user.accountId = String(id);
    user.cookieToken = `fixture-cookie-${id}`;
    user.ltuid = String(id);
    user.ltoken = `fixture-ltoken-${id}`;
    user.displayName = `Fixture ${id}`;
    user.roles = uids.map(uid => UserGameRole.of(uid, REGION, `Role ${uid}`, 60));
    users.set(id, user);
    if (id === state.userId) selectedUser = user.clone();
    return user;
  }

  function seed(owner, uid, age) {
    const note = DailyNote.fromJson({ current_resin: 10, max_resin: 200 });
    note.refreshTime = clock.now() - age;
    notes.set(key(owner, uid), record(note));
  }

  function select(owner, uid) {
    state.userId = owner;
    state.uid = uid;
    state.revision++;
    selectedUser = users.get(owner)?.clone();
    storage.set('currentUid', uid);
  }

  return {
    clock, state, hooks, calls, service, account, seed, select, response, tracked, notes,
    selectedUser: () => selectedUser,
    requestOwners: () => calls.requests.map(request => key(request.owner, request.uid)),
    version: () => storage.get(KEY_NOTE_VERSION) ?? 0,
    error: () => storage.get(KEY_NOTE_ERROR) ?? '',
    track: (owner, ...uids) => tracked.set(owner, uids),
    foreground(value) { storage.set('appForeground', value); service.setForeground(value); },
  };
}

function noPublishedRefresh(h) {
  assert.deepEqual(h.calls.writes, []);
  assert.equal(h.version(), 0);
  assert.deepEqual(h.calls.snapshots, []);
  assert.deepEqual(h.calls.forms, []);
  assert.deepEqual(h.calls.notices, []);
  assert.deepEqual(h.calls.reminders, []);
  assert.deepEqual(h.calls.webhooks, []);
}

test('automatic scheduling requires readiness, foreground and opt-in', async () => {
  const h = fixture();
  const persistedOwner = h.account(1, CURRENT);
  assert.notEqual(h.selectedUser(), persistedOwner, 'selected session and database read use separate instances');
  h.track(1, CURRENT);

  await h.service.bootstrapAutoRefresh();
  h.service.startAutoRefresh(4);
  assert.equal(h.service.isTimerRunning(), false, 'cold service starts outside the foreground');

  h.foreground(true);
  h.state.ready = false;
  await h.service.bootstrapAutoRefresh();
  h.service.startAutoRefresh(4);
  assert.deepEqual(h.clock.intervals(), []);

  h.state.ready = true;
  h.state.enabled = false;
  await h.service.bootstrapAutoRefresh();
  h.service.startAutoRefresh(4);
  await h.clock.advance(INTERVAL);
  assert.deepEqual(h.clock.intervals(), []);
  assert.deepEqual(h.calls.requests, []);

  h.state.enabled = true;
  const initial = h.service.bootstrapAutoRefresh();
  await h.clock.advance(SECOND);
  await initial;
  assert.deepEqual(h.clock.intervals(), [INTERVAL]);
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);
  assert.deepEqual(h.calls.snapshots, [`1/${CURRENT}`]);
  assert.equal(h.calls.forms.length, 1);
  assert.equal(h.calls.forms[0].data.resin, '160');

  h.foreground(false);
  assert.equal(h.service.isTimerRunning(), false);
  assert.deepEqual(h.clock.intervals(), []);
});

test('foreground catch-up evaluates freshness per owner and never adds or fetches untracked current UID', async () => {
  const h = fixture();
  h.account(1, CURRENT, SHARED, OTHER);
  h.account(2, SHARED, FRESH);
  h.track(1, SHARED, OTHER);
  h.track(2, SHARED, FRESH);
  h.seed(1, SHARED, INTERVAL / 2);
  h.seed(1, OTHER, INTERVAL);
  h.seed(2, FRESH, INTERVAL / 2);

  h.foreground(true);
  const catchUp = h.service.bootstrapAutoRefresh();
  await h.clock.advance(3 * SECOND);
  await catchUp;
  assert.deepEqual(h.requestOwners(), [`1/${OTHER}`, `2/${SHARED}`]);
  assert.deepEqual(h.calls.writes, [`1/${OTHER}`, `2/${SHARED}`]);
  assert.equal(h.notes.get(`1/${SHARED}`).note.currentResin, 10, 'same UID under another owner remains untouched');
  assert.deepEqual(h.calls.trackingWrites, []);
  assert.deepEqual(h.tracked.get(1), [SHARED, OTHER]);
  assert.deepEqual(h.calls.snapshots, [], 'neither refreshed role owns the current widget');
  assert.equal(h.version(), 2);
  assert.equal(h.calls.notices.length, 2);
  assert.equal(h.calls.reminders.length, 2);
  assert.equal(h.calls.webhooks.length, 2);
});

test('the interval polls a shared UID separately for both owners once their records expire', async () => {
  const h = fixture();
  h.account(1, CURRENT, SHARED);
  h.account(2, SHARED);
  h.track(1, SHARED);
  h.track(2, SHARED);
  h.seed(1, SHARED, INTERVAL / 2);
  h.seed(2, SHARED, INTERVAL / 2);

  h.foreground(true);
  await h.service.bootstrapAutoRefresh();
  assert.deepEqual(h.calls.requests, []);
  await h.clock.advance(INTERVAL - SECOND);
  h.service.startAutoRefresh(4);
  await h.service.bootstrapAutoRefresh();
  await h.clock.advance(3 * SECOND);
  assert.deepEqual(h.requestOwners(), [`1/${SHARED}`, `2/${SHARED}`], 'same-interval start does not reset the due tick');
  assert.deepEqual(h.calls.writes, [`1/${SHARED}`, `2/${SHARED}`]);
});

test('a cache read failure reports the first error and does not skip other roles or owners', async () => {
  const h = fixture();
  h.account(1, CURRENT, OTHER);
  h.account(2, SHARED);
  h.track(1, CURRENT, OTHER);
  h.track(2, SHARED);
  const message = 'fixture cache read failed for the first role';
  h.hooks.read = entry => {
    if (entry === `1/${CURRENT}`) throw new Error(message);
  };

  h.foreground(true);
  const catchUp = h.service.bootstrapAutoRefresh();
  await h.clock.advance(3 * SECOND);
  await catchUp;
  assert.deepEqual(h.requestOwners(), [`1/${OTHER}`, `2/${SHARED}`]);
  assert.deepEqual(h.calls.writes, [`1/${OTHER}`, `2/${SHARED}`]);
  assert.equal(h.version(), 2);
  assert.equal(h.error(), message, 'later successes do not clear the first failure in the batch');
});

test('reopening the session or backup gate admits one deferred foreground catch-up', async () => {
  for (const [field, closed, open] of [
    ['sessionPending', true, false],
    ['backupJournal', 'fixture-pending-backup', ''],
  ]) {
    const h = fixture();
    h.account(1, CURRENT);
    h.track(1, CURRENT);
    h.hooks.fetch = () => h.response(1034);
    h.state[field] = closed;
    h.foreground(true);
    await h.service.bootstrapAutoRefresh();
    assert.deepEqual(h.clock.intervals(), [INTERVAL], field);
    assert.deepEqual(h.calls.reads, [], field);
    assert.deepEqual(h.calls.requests, [], field);

    h.state[field] = open;
    const catchUp = h.service.bootstrapAutoRefresh();
    const duplicate = h.service.bootstrapAutoRefresh();
    await h.clock.advance(3 * SECOND);
    await Promise.all([catchUp, duplicate]);
    assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`], field);
    assert.ok(h.error().length > 0, field);

    const repeated = h.service.bootstrapAutoRefresh();
    await h.clock.advance(3 * SECOND);
    await repeated;
    assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`], field);
    assert.deepEqual(h.clock.intervals(), [INTERVAL], field);
  }
});

test('backgrounding during request delay prevents network access and stops the timer immediately', async () => {
  const h = fixture();
  h.account(1, CURRENT, OTHER);
  h.track(1, CURRENT, OTHER);
  h.foreground(true);
  const initial = h.service.bootstrapAutoRefresh();
  await flush();
  assert.ok(h.clock.hasTimeout(), 'the first request is waiting for its delay');
  assert.deepEqual(h.calls.requests, []);

  h.foreground(false);
  assert.deepEqual(h.clock.intervals(), []);
  const late = h.service.bootstrapAutoRefresh();
  await h.clock.advance(INTERVAL + 3 * SECOND);
  await Promise.all([initial, late]);
  assert.deepEqual(h.clock.intervals(), [], 'a late bootstrap cannot restart the timer in the background');
  assert.deepEqual(h.calls.requests, []);
  noPublishedRefresh(h);
});

test('backgrounding while HTTP is pending suppresses writeback, publication and the next role', async () => {
  const h = fixture();
  h.account(1, CURRENT, OTHER);
  h.track(1, CURRENT, OTHER);
  const request = deferred();
  h.hooks.fetch = () => request.promise;
  h.foreground(true);
  const initial = h.service.bootstrapAutoRefresh();
  await h.clock.advance(SECOND);
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);

  h.foreground(false);
  assert.deepEqual(h.clock.intervals(), []);
  request.resolve(h.response());
  await h.clock.advance(3 * SECOND);
  await initial;
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);
  assert.deepEqual(h.calls.upserts, []);
  assert.equal(h.error(), '');
  noPublishedRefresh(h);
});

test('backgrounding while a cache read is pending leaves the network untouched', async () => {
  const h = fixture();
  h.account(1, CURRENT);
  h.track(1, CURRENT);
  const reading = deferred();
  h.hooks.read = () => reading.promise;
  h.foreground(true);
  const initial = h.service.bootstrapAutoRefresh();
  await flush();
  assert.deepEqual(h.calls.reads, [`1/${CURRENT}`]);

  h.foreground(false);
  reading.resolve();
  await h.clock.advance(3 * SECOND);
  await initial;
  assert.deepEqual(h.calls.requests, []);
  noPublishedRefresh(h);
});

test('disabling during guarded persistence invalidates the in-flight write and skips later roles', async () => {
  const h = fixture();
  h.account(1, CURRENT, OTHER);
  h.track(1, CURRENT, OTHER);
  const saving = deferred();
  h.hooks.beforeCommit = () => saving.promise;
  h.foreground(true);
  const initial = h.service.bootstrapAutoRefresh();
  await h.clock.advance(SECOND);
  assert.deepEqual(h.calls.upserts, [`1/${CURRENT}`]);

  h.state.enabled = false;
  h.service.stopAutoRefresh();
  assert.deepEqual(h.clock.intervals(), []);
  saving.resolve();
  await h.clock.advance(3 * SECOND);
  await initial;
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);
  noPublishedRefresh(h);
});

for (const [label, cancel] of [
  ['changing the interval', h => { h.state.intervalMinutes = 8; h.service.startAutoRefresh(8); }],
  ['removing the tracked role', h => h.track(1)],
  ['switching to another account with the same UID', h => h.select(2, CURRENT)],
]) {
  test(`${label} invalidates the old automatic request`, async () => {
    const h = fixture();
    h.account(1, CURRENT, OTHER);
    h.account(2, CURRENT);
    h.track(1, CURRENT, OTHER);
    const request = deferred();
    h.hooks.fetch = () => request.promise;
    h.foreground(true);
    const initial = h.service.bootstrapAutoRefresh();
    await h.clock.advance(SECOND);
    assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);

    cancel(h);
    request.resolve(h.response());
    await h.clock.advance(3 * SECOND);
    await initial;
    assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);
    noPublishedRefresh(h);
    assert.deepEqual(h.clock.intervals(), [h.state.intervalMinutes * MINUTE]);
  });
}

test('concurrent bootstraps and an overlapping tick do not retry a failed noninteractive batch', async () => {
  const h = fixture();
  h.account(1, CURRENT);
  h.track(1, CURRENT);
  const request = deferred();
  h.hooks.fetch = () => request.promise;
  h.foreground(true);
  const initial = h.service.bootstrapAutoRefresh();
  const duplicate = h.service.bootstrapAutoRefresh();
  await h.clock.advance(INTERVAL + SECOND);
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);

  request.resolve(h.response(1034));
  await h.clock.advance(3 * SECOND);
  await Promise.all([initial, duplicate]);
  await h.service.bootstrapAutoRefresh();
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);
  assert.deepEqual(h.calls.verification, []);
  assert.deepEqual(h.calls.credentialRefresh, []);
  assert.ok(h.error().length > 0, 'failure remains visible while the foreground batch is current');
  noPublishedRefresh(h);
});

test('automatic catch-up does not replenish missing credentials or renew an expired cookie', async () => {
  const h = fixture();
  const missingToken = h.account(1, CURRENT);
  missingToken.ltoken = '';
  h.select(1, CURRENT);
  h.account(2, OTHER);
  h.track(1, CURRENT);
  h.track(2, OTHER);
  h.hooks.fetch = () => h.response(-100);

  h.foreground(true);
  const initial = h.service.bootstrapAutoRefresh();
  await h.clock.advance(3 * SECOND);
  await initial;
  assert.deepEqual(h.requestOwners(), [`2/${OTHER}`]);
  assert.deepEqual(h.calls.credentialRefresh, []);
  assert.deepEqual(h.calls.verification, []);
  noPublishedRefresh(h);
});

test('rapid return to foreground waits for a cancelled batch and runs exactly one catch-up', async () => {
  const h = fixture();
  h.account(1, CURRENT);
  h.track(1, CURRENT);
  const oldRequest = deferred();
  h.hooks.fetch = () => h.calls.requests.length === 1 ? oldRequest.promise : h.response();
  h.foreground(true);
  const oldBatch = h.service.bootstrapAutoRefresh();
  await h.clock.advance(SECOND);
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);

  h.foreground(false);
  h.foreground(true);
  const resumed = h.service.bootstrapAutoRefresh();
  const duplicate = h.service.bootstrapAutoRefresh();
  await h.clock.advance(INTERVAL + SECOND);
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`], 'the replacement cannot overlap the unsettled request');

  oldRequest.resolve(h.response());
  await h.clock.advance(3 * SECOND);
  await Promise.all([oldBatch, resumed, duplicate]);
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`, `1/${CURRENT}`]);
  assert.deepEqual(h.calls.writes, [`1/${CURRENT}`]);
  assert.equal(h.version(), 1);
  assert.deepEqual(h.calls.snapshots, [`1/${CURRENT}`]);
});

for (const manualSucceeded of [true, false]) {
  test(`foreground catch-up waits for manual refresh ${manualSucceeded ? 'success' : 'failure'}`, async () => {
    const h = fixture();
    h.account(1, CURRENT);
    h.account(2, OTHER);
    h.track(2, OTHER);
    const manualRequest = deferred();
    h.hooks.fetch = request => request.uid === CURRENT ? manualRequest.promise : h.response();
    h.foreground(true);
    const manual = h.service.refresh(CURRENT);
    const manualResult = manualSucceeded ? manual.then(note => assert.equal(note.currentResin, 160))
      : assert.rejects(manual, /过于频繁/);
    await h.clock.advance(SECOND);
    assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);

    h.foreground(false);
    h.foreground(true);
    const resumed = h.service.bootstrapAutoRefresh();
    const duplicate = h.service.bootstrapAutoRefresh();
    await h.clock.advance(INTERVAL + SECOND);
    assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`]);

    manualRequest.resolve(h.response(manualSucceeded ? 0 : 429));
    await h.clock.advance(3 * SECOND);
    await Promise.all([manualResult, resumed, duplicate]);
    assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`, `2/${OTHER}`]);
    assert.deepEqual(h.calls.writes, manualSucceeded ? [`1/${CURRENT}`, `2/${OTHER}`] : [`2/${OTHER}`]);
    assert.deepEqual(h.calls.trackingWrites, []);
  });
}

test('manual tracked refresh force-refreshes fresh records and keeps current-owner verification interactive', async () => {
  const h = fixture();
  h.account(1, CURRENT);
  h.account(2, CURRENT);
  h.track(1, CURRENT);
  h.track(2, CURRENT);
  h.seed(1, CURRENT, SECOND);
  h.seed(2, CURRENT, SECOND);
  h.state.enabled = false;
  h.hooks.fetch = () => h.calls.requests.length === 1 ? h.response(1034) : h.response();

  const manual = h.service.refreshTrackedList();
  await h.clock.advance(3 * SECOND);
  const result = await manual;
  assert.equal(result.total, 2);
  assert.equal(result.succeeded, 2);
  assert.deepEqual(h.requestOwners(), [`1/${CURRENT}`, `1/${CURRENT}`, `2/${CURRENT}`]);
  assert.deepEqual(h.calls.verification, ['prompt']);
  assert.deepEqual(h.calls.writes, [`1/${CURRENT}`, `2/${CURRENT}`]);
  assert.deepEqual(h.clock.intervals(), []);
});

test('explicit background refresh works when foreground auto-refresh is off', async () => {
  const h = fixture();
  const owner = h.account(2, OTHER);
  h.state.enabled = false;
  const result = await h.service.refreshBackground(owner, OTHER, REGION, { isActive: async () => true });
  assert.equal(result.status, 'success');
  assert.deepEqual(h.requestOwners(), [`2/${OTHER}`]);
  assert.deepEqual(h.calls.writes, [`2/${OTHER}`]);
  assert.equal(h.version(), 1);
  assert.deepEqual(h.clock.intervals(), []);
});
