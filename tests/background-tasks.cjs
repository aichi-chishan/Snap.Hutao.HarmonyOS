// Production ArkTS + OS/network mocks and a real SQLite operational database. No device/account/network use.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
let now = Date.UTC(2026, 9, 5, 10);
class Clock extends Date { static now() { return now; } }
const db = new DatabaseSync(':memory:');
let opened = 0, selected = 1, selectedUid = '100000001', autoSign = true, interval = 10, supported = true;
let revision = 0, transitionPending = false;
let journal = '';
let failInit = false;
let registrationError = false, getCount = 0, postCount = 0, refreshCount = 0, uiCalls = 0;
let infoResponse, signResponse, fetchHook, noteHook;
const budgetTimers = new Map();
const tasks = new Map(), starts = [], stops = [], appStorage = new Map(), users = new Map(), cache = new Map();
function resultSet(rows) {
  let index = -1;
  return { goToFirstRow() { index = 0; return rows.length > 0; }, goToNextRow() { return ++index < rows.length; },
    getColumnIndex(name) { return name; }, getString(name) { return String(rows[index][name] ?? ''); },
    getLong(name) { return Number(rows[index][name] ?? 0); }, close() {} };
}
const store = {
  get version() { return db.prepare('PRAGMA user_version').get().user_version; },
  set version(v) { db.exec('PRAGMA user_version=' + v); },
  async executeSql(sql, binds = []) { db.prepare(sql).run(...binds); },
  async querySql(sql, binds = []) { return resultSet(db.prepare(sql).all(...binds)); },
  async createTransaction() {
    db.exec('BEGIN IMMEDIATE');
    return { execute: async (sql, args) => { if (failInit) throw new Error('fixture init failure'); return store.executeSql(sql, args); }, querySql: store.querySql, async commit() { db.exec('COMMIT'); },
      async rollback() { db.exec('ROLLBACK'); } };
  },
};
const userService = { getCurrentUser: () => users.get(selected), sessionRevision: () => revision, isSessionTransitionPending: () => transitionPending,
  completeTokenChainPublic() { uiCalls++; throw new Error('No background auth refresh'); } };
const repos = { UserRepo: {
  getCurrentUser: async () => users.get(selected), getUserById: async id => users.get(id),
  getSelectedUserId: async () => selected,
  getDefaultRole: async id => users.get(id)?.roles.find(role => role.gameUid === selectedUid),
} };
const scheduler = {
  NetworkType: { NETWORK_TYPE_ANY: 0 },
  async obtainAllWorks() { return [...tasks.values()]; },
  startWork(work) { if (registrationError) throw new Error('OS rejected');
    if (tasks.has(work.workId)) throw new Error('duplicate task');
    tasks.set(work.workId, work); starts.push(work); },
  stopWork(work, cancel) { stops.push({ work, cancel }); if (cancel) tasks.delete(work.workId); },
};
const mocks = new Map([
  ['@kit.ArkData', { relationalStore: { getRdbStore: async () => { opened++; return store; }, SecurityLevel: { S1: 1 }, TransactionType: { IMMEDIATE: 1 } } }],
  ['@kit.AbilityKit', {}], ['@kit.BackgroundTasksKit', { workScheduler: scheduler, WorkSchedulerExtensionAbility: class {} }],
  ['common/AppContext', { AppContextProvider: { init() {}, getAppContext: () => ({}), getFilesDir: () => '/fixture/private' } }],
  ['common/Logger', { Logger: { info() {}, warn() {}, error() {} } }],
  ['data/db/RelationalStoreHelper', { RelationalStoreHelper: { init: async () => {} } }],
  ['data/prefs/PreferencesStore', { PreferencesStore: { init: async () => {}, getCurrentUid: () => selectedUid, getCurrentUserId: () => selected,
    getAutoSignInEnabled: () => autoSign, getBackupJournal: () => journal, getRefreshIntervalMinutes: () => interval } }],
  ['data/repo/UserRepo', repos], ['service/UserService', { UserService: { getInstance: () => userService } }],
  ['data/network/HoyolabClient', { HoyolabClient: {
    fetchSignInfo: async () => { getCount++; if (fetchHook) await fetchHook(); return infoResponse; },
    signIn: async () => { postCount++; return signResponse; },
    fetchDailyNote: async () => { refreshCount++; if (noteHook) await noteHook(); return infoResponse; },
  } }],
]);
function load(relative) {
  const name = relative.replace(/\.ets$/, '');
  if (mocks.has(name)) return mocks.get(name);
  if (cache.has(name)) return cache.get(name).exports;
  const file = path.join(root, name + '.ets');
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }, reportDiagnostics: true,
    fileName: file.replace(/\.ets$/, '.ts'),
  });
  assert.equal(output.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0, name);
  const module = { exports: {} }; cache.set(name, module);
  const requireMock = id => id.startsWith('.') ? load(path.posix.normalize(path.posix.join(path.posix.dirname(name), id))) :
    (mocks.get(id) || (() => { throw new Error('Unexpected dependency ' + id); })());
  const AppStorage = { get: key => appStorage.get(key), setOrCreate: (key, val) => appStorage.set(key, val) };
  vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`, {
    Date: Clock, setTimeout: (callback, delay) => {
      const timer = setTimeout(callback, delay); if (delay === 80000) budgetTimers.set(timer, callback); return timer;
    }, clearTimeout: timer => { budgetTimers.delete(timer); clearTimeout(timer); }, AppStorage, canIUse: () => supported, console,
  })(requireMock, module, module.exports);
  return module.exports;
}
const { User } = load('model/User');
const { UserGameRole } = load('model/UserGameRole');
const { ApiResponse } = load('model/ApiResponse');
const { BackgroundTaskKind: K, BackgroundTaskPolicy: Policy, BackgroundTaskResult: Outcome } = load('model/BackgroundTask');
function response(code = 0, data = {}) { return ApiResponse.fromJson(JSON.stringify({ retcode: code, data })); }
function account(id, uid) {
  const u = new User(); u.id = id; u.aid = 'fixture-' + id; u.mid = 'fixture-mid-' + id;
  u.createdAt = id; u.accountId = 'fixture'; u.cookieToken = 'fixture';
  const role = new UserGameRole(); role.gameUid = uid; role.region = 'cn_gf01'; u.roles = [role]; return u;
}
users.set(1, account(1, selectedUid)); users.set(2, account(2, '100000002'));
// Load the actual noninteractive DailyNote method; mock unrelated foreground-only imports.
for (const [name, value] of [
  ['@kit.FormKit', { formProvider: {}, formBindingData: {}, formInfo: {} }],
  ['data/repo/DailyNoteRepo', { DailyNoteRepo: { upsert: async (id, uid, note, guard) => {
    if (await guard()) persisted.push({ id, uid, note });
  } } }],
  ['data/local/NotificationHelper', { NotificationHelper: {} }],
  ['data/local/FormSnapshot', { FormSnapshot: {} }],
  ['data/network/DailyNoteWebhookClient', { DailyNoteWebhookClient: { send() { uiCalls++; } } }],
  ['data/network/RiskVerifier', { RiskVerifier: { tryResolveRisk() { uiCalls++; } } }],
  ['service/DailyNoteReminderService', { DailyNoteReminderService: {} }],
  ['data/network/CardVerifyApi', { DAILY_NOTE_PATH: '' }],
]) mocks.set(name, value);
const persisted = [], cards = [];
const { DailyNoteService } = load('service/DailyNoteService');
const originalSnapshotUpdate = DailyNoteService.getInstance().updateCardSnapshot;
DailyNoteService.getInstance().updateCardSnapshot = async note => cards.push(note);
const { BackgroundTaskRepo: Repo } = load('data/repo/BackgroundTaskRepo');
const { BackgroundTaskService: Service } = load('service/BackgroundTaskService');
const { AutoSignInService } = load('service/AutoSignInService');
const work = kind => tasks.get(kind === K.DAILY_NOTE ? 19001 : 20001);
const tick = () => new Promise(resolve => setImmediate(resolve));
async function setup(kind = K.SIGN_IN) {
  await Service.reset(); selected = 1; selectedUid = '100000001'; autoSign = true;
  infoResponse = response(0, { is_sign: false, today: Policy.day('cn_gf01').split(':')[1] });
  signResponse = response(); fetchHook = undefined; noteHook = undefined; registrationError = false; supported = true;
  await Service.setEnabled(kind, true);
}
(async () => {
  failInit = true;
  const failedInits = await Promise.allSettled([Service.init({}), Service.init({})]);
  assert.ok(failedInits.every(result => result.status === 'rejected'));
  assert.equal(opened, 1); assert.equal(Repo.store, undefined); assert.equal(store.version, 0);
  assert.equal(db.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type='table'").get().n, 0);
  failInit = false;
  await Promise.all([Service.init({}), Service.init({})]);
  assert.equal(opened, 2); assert.equal(store.version, 1);
  for (const kind of [K.DAILY_NOTE, K.SIGN_IN]) {
    const state = await Service.getState(kind); assert.equal(state.enabled, false); assert.equal(state.queued, false);
  }
  assert.equal(tasks.size, 0, 'init never registers default opt-in');
  assert.equal(Policy.interval(2), 20); assert.equal(Policy.interval(NaN), 30);
  assert.equal(Policy.day('cn_gf01', Date.UTC(2026, 9, 4, 15, 59)), 'cn_gf01:2026-10-04');
  assert.equal(Policy.day('cn_gf01', Date.UTC(2026, 9, 4, 16)), 'cn_gf01:2026-10-05');
  assert.equal(Policy.day('os_usa', Date.UTC(2026, 9, 5, 4, 59)), 'os_usa:2026-10-04');
  await setup(K.DAILY_NOTE);
  assert.equal(work(K.DAILY_NOTE).repeatCycleTime, 1200000);
  assert.equal(work(K.DAILY_NOTE).isPersisted, true);
  assert.deepEqual(Object.keys(work(K.DAILY_NOTE).parameters), ['epoch']);
  const initialStarts = starts.length;
  await Promise.all([Service.reconcile(), Service.reconcile()]);
  assert.equal(starts.length, initialStarts, 'startup reconciliation is idempotent');
  infoResponse = response(0, { current_resin: 80, max_resin: 200 });
  await Service.onWorkStart(work(K.DAILY_NOTE));
  assert.equal(persisted.length, 1); assert.equal(cards.length, 1);
  assert.equal((await Service.getState(K.DAILY_NOTE)).status, 'success');
  await Service.onWorkStart(work(K.DAILY_NOTE));
  assert.equal(persisted.length, 1, 'interval cooldown prevents duplicate cache refresh');

  await setup();
  const gets = getCount, posts = postCount;
  let release; fetchHook = () => new Promise(resolve => { release = resolve; });
  const first = Service.onWorkStart(work(K.SIGN_IN));
  while (!release) await tick();
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(getCount, gets + 1, 'duplicate native starts share persistent lease');
  const foreground = AutoSignInService.getInstance().runOnce(selectedUid);
  await foreground;
  assert.equal(getCount, gets + 1, 'foreground auto sign shares same per-UID operation lease');
  release(); await first;
  assert.equal(postCount, posts + 1);
  assert.equal((await Service.getState(K.SIGN_IN)).status, 'success');
  fetchHook = undefined;
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(postCount, posts + 1, 'one successful sign per server day');
  now += 86400000; infoResponse = response(0, { is_sign: false, today: Policy.day('cn_gf01').split(':')[1] });
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(postCount, posts + 2, 'new server day is eligible without process restart');

  await setup(); infoResponse = response(0, { is_sign: true });
  const signedPosts = postCount;
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(postCount, signedPosts, 'server idempotency check skips already signed POST');
  assert.equal((await Service.getState(K.SIGN_IN)).status, 'already_signed');

  await setup(); signResponse = response(0, { gt: 'fixture', challenge: 'fixture' });
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal((await Service.getState(K.SIGN_IN)).status, 'captcha');
  const blockedGets = getCount;
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(getCount, blockedGets, 'captcha remains blocked for the current server day until explicit retry');
  await Service.retryBlocked(K.SIGN_IN); signResponse = response(); infoResponse = response(0, { is_sign: true });
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(getCount, blockedGets + 1);

  await setup(); signResponse = response(0, { gt: 'fixture', challenge: 'fixture' });
  await Service.onWorkStart(work(K.SIGN_IN)); const previousDayGets = getCount;
  now += 86400000; infoResponse = response(0, { is_sign: true });
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(getCount, previousDayGets + 1, 'manual block is per server day, not permanent');

  await setup(); infoResponse = response(-100);
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal((await Service.getState(K.SIGN_IN)).status, 'login_required');
  const retried = await AutoSignInService.getInstance().retryCurrent();
  assert.equal(retried.status, 'login_required', 'typed explicit startup retry does not imply success');
  await setup(); transitionPending = true; const pendingGets = getCount;
  await Service.onWorkStart(work(K.SIGN_IN)); assert.equal(getCount, pendingGets);
  assert.equal((await Service.getState(K.SIGN_IN)).enabled, true, 'in-progress cold restore pauses but does not erase consent');
  transitionPending = false;
  await setup(); journal = 'fixture-pending-restore'; const restoreGets = getCount;
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(getCount, restoreGets, 'pending backup journal blocks background network');
  journal = '';
  await setup(); infoResponse = response(0, {}); const malformedPosts = postCount;
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(postCount, malformedPosts, 'unknown sign state never authorizes another POST');
  await setup(); infoResponse = response(0, { is_sign: false, today: '2020-01-01' });
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal((await Service.getState(K.SIGN_IN)).status, 'manual');

  await setup(); const oldWork = work(K.SIGN_IN); const beforeCancelPosts = postCount;
  release = undefined; fetchHook = () => new Promise(resolve => { release = resolve; });
  const cancelled = Service.onWorkStart(oldWork); while (!release) await tick();
  await Service.setEnabled(K.SIGN_IN, false); release(); await cancelled;
  assert.equal(postCount, beforeCancelPosts, 'disable during GET prevents sign mutation');
  assert.equal((await Service.getState(K.SIGN_IN)).status, 'disabled');
  assert.equal(tasks.has(20001), false);

  await setup(K.DAILY_NOTE); release = undefined;
  noteHook = () => new Promise(resolve => { release = resolve; });
  const beforeNotes = persisted.length;
  const cancelRefresh = Service.onWorkStart(work(K.DAILY_NOTE)); while (!release) await tick();
  await Service.reset(); release(); await cancelRefresh;
  assert.equal(persisted.length, beforeNotes, 'reset fences late native refresh persistence');
  assert.equal(db.prepare('SELECT count(*) AS n FROM background_operations').get().n, 0);

  await setup(); release = undefined;
  fetchHook = () => new Promise(resolve => { release = resolve; });
  const timeoutPosts = postCount;
  const timedOut = Service.onWorkStart(work(K.SIGN_IN)); while (!release) await tick();
  assert.equal(budgetTimers.size, 1); [...budgetTimers.values()][0](); await timedOut;
  assert.equal((await Service.getState(K.SIGN_IN)).status, 'timeout');
  release(); await tick(); await tick();
  assert.equal(postCount, timeoutPosts, 'expired bounded task cannot resume mutation after late GET');

  await setup(); selected = 2; selectedUid = '100000002';
  const otherGets = getCount;
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(getCount, otherGets, 'binding never follows another selected account');
  assert.equal((await Service.getState(K.SIGN_IN)).enabled, false);
  await setup(); users.get(1).roles = [];
  await Service.onWorkStart(work(K.SIGN_IN));
  assert.equal(getCount, otherGets, 'removed UID fails closed before network');
  users.get(1).roles = account(1, '100000001').roles;

  await setup();
  const binding = Service.captureBinding(); selected = 2; selectedUid = '100000002'; revision++;
  await assert.rejects(() => Service.setEnabled(K.DAILY_NOTE, true, binding), /已变化/);
  selected = 1; selectedUid = '100000001'; revision++;
  await assert.rejects(() => Service.setEnabled(K.DAILY_NOTE, true, binding), /已变化/, 'A-to-B-to-A cannot reuse old consent');
  const savedGet = Repo.get;
  let finishAdmission;
  Repo.get = async kind => { await new Promise(resolve => { finishAdmission = resolve; }); return savedGet.call(Repo, kind); };
  const admission = Service.setEnabled(K.DAILY_NOTE, true);
  const admissionRejected = assert.rejects(() => admission, /已变化/);
  while (!finishAdmission) await tick();
  selected = 2; selectedUid = '100000002'; revision++; finishAdmission();
  await admissionRejected; Repo.get = savedGet;
  assert.equal((await Service.getState(K.DAILY_NOTE)).enabled, false, 'switch during admission cannot bind the new account');

  await setup(); const state = await Repo.get(K.SIGN_IN);
  assert.equal(await Repo.claim(state, 'old-process', now), true);
  now += Policy.BUDGET_MS + 1;
  assert.equal((await Service.getState(K.SIGN_IN)).status, 'interrupted', 'expired process is not presented as running');
  assert.equal(await Repo.claim(state, 'new-process', now), true);
  await Repo.finish(state, 'old-process', Outcome.of('success', 'stale', Policy.day('cn_gf01')));
  assert.equal((await Repo.get(K.SIGN_IN)).lease, 'new-process', 'stale process cannot finish replacement lease');
  const staleEpoch = state.epoch;
  await Service.setEnabled(K.SIGN_IN, false); await Service.setEnabled(K.SIGN_IN, true);
  const newer = await Repo.get(K.SIGN_IN); assert.ok(newer.epoch > staleEpoch);
  const beforeOld = getCount; await Service.onWorkStart({ ...work(K.SIGN_IN), parameters: { epoch: staleEpoch } });
  assert.equal(getCount, beforeOld, 'stale persisted OS generation is ignored');

  await Service.reset(); registrationError = true;
  await Service.setEnabled(K.SIGN_IN, true);
  const rejected = await Service.getState(K.SIGN_IN);
  assert.equal(rejected.enabled, true, 'intent retained separately from OS acceptance');
  assert.equal(rejected.queued, false); assert.equal(rejected.status, 'blocked');
  registrationError = false; await Service.retryBlocked(K.SIGN_IN);
  assert.equal((await Service.getState(K.SIGN_IN)).queued, true);
  const opted = await Service.getState(K.SIGN_IN);
  await Service.stopAndInvalidate();
  const fenced = await Service.getState(K.SIGN_IN);
  assert.equal(fenced.enabled, true, 'cold-start/session fence preserves original opt-in');
  assert.equal(fenced.uid, opted.uid); assert.ok(fenced.epoch > opted.epoch); assert.equal(fenced.queued, false);
  await Service.reconcile(); assert.equal((await Service.getState(K.SIGN_IN)).queued, true);
  supported = false;
  await assert.rejects(() => Service.setEnabled(K.DAILY_NOTE, true), /不支持/);
  supported = true; await Service.invalidateAccount(1);
  assert.equal((await Service.getState(K.SIGN_IN)).enabled, false);
  assert.equal((await Service.getState(K.SIGN_IN)).uid, '', 'account invalidation clears stale binding identity');
  assert.equal(uiCalls, 0, 'no background verification, auth exchange, permission or webhook');

  // Pending extension initialization cannot resurrect a task after onWorkStop.
  const Extension = load('background/HutaoWorkSchedulerExtensionAbility').default;
  const extension = new Extension(); extension.context = {};
  const originalInit = Service.init, originalStart = Service.onWorkStart, originalStop = Service.onWorkStop;
  let finishInit, extensionStarts = 0;
  Service.init = () => new Promise(resolve => { finishInit = resolve; });
  Service.onWorkStart = async () => { extensionStarts++; };
  Service.onWorkStop = () => {};
  const extensionWork = { workId: 20001, bundleName: 'com.example.snaphutaoharmonyos',
    abilityName: 'HutaoWorkSchedulerExtensionAbility', parameters: { epoch: 50 } };
  extension.onWorkStart(extensionWork); extension.onWorkStop(extensionWork); finishInit(); await tick();
  assert.equal(extensionStarts, 0);
  extension.onWorkStart({ ...extensionWork, parameters: { epoch: 51 } });
  extension.onWorkStop(extensionWork); finishInit(); await tick();
  assert.equal(extensionStarts, 1, 'stale extension-stop callback cannot cancel newer configuration');
  const initializations = [];
  Service.init = () => new Promise(resolve => initializations.push(resolve));
  const dailyExtensionWork = { ...extensionWork, workId: 19001, parameters: { epoch: 52 } };
  const signExtensionWork = { ...extensionWork, parameters: { epoch: 52 } };
  extension.onWorkStart(dailyExtensionWork); extension.onWorkStart(signExtensionWork);
  extension.onWorkStop(dailyExtensionWork);
  for (const initialized of initializations) initialized(); await tick();
  assert.equal(extensionStarts, 2, 'different work IDs have independent pending initialization/stop fences');
  Service.init = originalInit; Service.onWorkStart = originalStart; Service.onWorkStop = originalStop;

  // An expired process lease and a rolled-back device clock cannot suppress future jobs forever.
  const operation = await Repo.operation(K.SIGN_IN, 1, '100000001', 'cn_gf01');
  operation.lease = 'dead-process'; operation.leaseUntil = now - 1;
  operation.retryAt = now - 1; operation.status = ''; operation.completedDay = '';
  assert.equal(Policy.due(operation, Policy.day('cn_gf01'), now, true), true);
  operation.leaseUntil = now + 2 * 86400000;
  assert.equal(Policy.due(operation, Policy.day('cn_gf01'), now, true), true);
  operation.lease = ''; operation.retryAt = now + 2 * 86400000;
  assert.equal(Policy.due(operation, Policy.day('cn_gf01'), now, true), true);
  operation.retryAt = now + 600000;
  assert.equal(Policy.due(operation, Policy.day('cn_gf01'), now, true), false);

  // Explicit widget reads share operation leases/epoch fences, without periodic consent or session restoration.
  await Service.reset(); selected = 1; selectedUid = '100000001';
  infoResponse = response(0, { current_resin: 80, max_resin: 200 }); noteHook = undefined;
  const widgetPosts = postCount, widgetTasks = tasks.size;
  const widgetResult = await Service.refreshWidget();
  assert.equal(widgetResult.status, 'success'); assert.equal(postCount, widgetPosts); assert.equal(tasks.size, widgetTasks);
  assert.equal((await Service.getState(K.DAILY_NOTE)).enabled, false);
  release = undefined; noteHook = () => new Promise(resolve => { release = resolve; });
  const widgetPending = Service.refreshWidget(); while (!release) await tick();
  assert.equal((await Service.refreshWidget()).status, 'cooldown', 'simultaneous widgets share durable read lease');
  const widgetSaved = persisted.length; await Service.reset(); release(); await widgetPending;
  assert.equal(persisted.length, widgetSaved, 'reset fences widget response before persistence'); noteHook = undefined;

  // Run actual file snapshot and publication code with an in-memory file boundary and delayed OS update.
  let snapshotText = '', failSnapshotWrite = false, closeCount = 0;
  mocks.set('@kit.CoreFileKit', { fileIo: { OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
    openSync: () => ({ fd: 1 }), writeSync: (fd, text) => { if (failSnapshotWrite) throw new Error('fixture storage failure'); snapshotText = text; },
    readTextSync: () => snapshotText, closeSync: () => closeCount++ } });
  const snapshotExports = mocks.get('data/local/FormSnapshot'); mocks.delete('data/local/FormSnapshot');
  const actualSnapshot = load('data/local/FormSnapshot'); Object.assign(snapshotExports, actualSnapshot);
  mocks.set('data/local/FormSnapshot', snapshotExports);
  const Snapshot = actualSnapshot.FormSnapshot;
  const kit = mocks.get('@kit.FormKit'); const published = [];
  let releasePublish, delayFirstPublish = false;
  kit.formBindingData.createFormBindingData = data => JSON.parse(JSON.stringify(data));
  kit.formProvider.getPublishedRunningFormInfos = async () => [{ formId: 'fixture-form' }];
  kit.formProvider.updateForm = async (id, data) => {
    if (delayFirstPublish) { delayFirstPublish = false; await new Promise(resolve => { releasePublish = resolve; }); }
    published.push(data);
  };
  DailyNoteService.getInstance().updateCardSnapshot = originalSnapshotUpdate;
  await Service.reset(); infoResponse = response(0, { current_resin: 80, max_resin: 200 });
  assert.equal((await Service.refreshWidget()).status, 'success');
  assert.equal((await DailyNoteService.getInstance().cardDataForCurrentOwner()).resin, '80');
  assert.equal(published.at(-1)._uid, undefined, 'local ownership metadata is never sent in form display data');
  const owner = Snapshot.owner(); assert.equal(owner.userId, 1); assert.equal(owner.uid, selectedUid);
  delayFirstPublish = true;
  const latePublish = DailyNoteService.getInstance().publishCard('fixture-form');
  while (!releasePublish) await tick();
  await Service.stopAndInvalidate(); await DailyNoteService.getInstance().clearCardSnapshot();
  releasePublish(); await latePublish;
  assert.equal(published.at(-1).resin, '--', 'a late old OS form publication is corrected after reset');
  assert.equal(Snapshot.owner().userId, 0);
  snapshotText = '{"nickname":"old-unowned-cache","resin":"200"}';
  assert.equal((await DailyNoteService.getInstance().cardDataForCurrentOwner()).resin, '--', 'legacy unbound snapshots cannot display');
  failSnapshotWrite = true;
  await assert.rejects(() => DailyNoteService.getInstance().clearCardSnapshot(), /storage failure/);
  assert.ok(closeCount > 0, 'file handle closes even when write fails'); failSnapshotWrite = false;

  // System widget update is cache-only; repeated taps and removal never launch a second or detached refresh.
  kit.FormExtensionAbility = class {}; kit.formInfo.FormParam = { IDENTITY_KEY: 'fixture-id-key' };
  const Widget = load('widgets/DailyNoteFormExtensionAbility').default;
  const widget = new Widget(); widget.context = {};
  const widgetInit = Service.init, widgetRefresh = Service.refreshWidget, cardPublish = DailyNoteService.getInstance().publishCard;
  let tappedReads = 0, widgetPublished = 0, finishWidget;
  Service.init = async () => {};
  DailyNoteService.getInstance().publishCard = async () => { widgetPublished++; };
  Service.refreshWidget = async (timeout, cancelled) => {
    tappedReads++; await new Promise(resolve => { finishWidget = resolve; });
    return Outcome.of(cancelled() ? 'cancelled' : 'success', '');
  };
  assert.equal(widget.onAddForm({ parameters: { private: 'fixture' } }).resin, '--');
  widget.onUpdateForm('fixture-form'); await tick(); assert.equal(tappedReads, 0);
  widget.onFormEvent('fixture-form', '{"method":"refresh"}');
  widget.onFormEvent('fixture-form', '{"method":"refresh"}');
  while (!finishWidget) await tick(); assert.equal(tappedReads, 1);
  widget.onRemoveForm('fixture-form'); const beforeDetached = widgetPublished; finishWidget(); await tick();
  assert.equal(widgetPublished, beforeDetached, 'removed form cannot republish a late response');
  const widgetFinishes = [];
  Service.refreshWidget = async (timeout, cancelled) => {
    tappedReads++; await new Promise(resolve => widgetFinishes.push(resolve));
    return Outcome.of(cancelled() ? 'cancelled' : 'success', '');
  };
  widget.onFormEvent('reused-form', 'refresh'); while (widgetFinishes.length < 1) await tick();
  widget.onRemoveForm('reused-form'); widget.onFormEvent('reused-form', 'refresh');
  while (widgetFinishes.length < 2) await tick();
  const readdedReads = tappedReads; widgetFinishes[0](); await tick();
  widget.onFormEvent('reused-form', 'refresh'); await tick();
  assert.equal(tappedReads, readdedReads, 'old cleanup cannot release a reused form ID newer refresh');
  widgetFinishes[1](); await tick();
  assert.equal(widget.generations.size, 0, 'completed/removed IDs are not retained');
  widget.onFormEvent('fixture-form', 'x'.repeat(1025)); await tick();
  assert.equal(tappedReads, readdedReads, 'oversize events are dropped before parsing');
  Service.init = widgetInit; Service.refreshWidget = widgetRefresh; DailyNoteService.getInstance().publishCard = cardPublish;
  const widgetSource = fs.readFileSync(path.join(root, 'widgets/DailyNoteFormExtensionAbility.ets'), 'utf8');
  assert.doesNotMatch(widgetSource, /restoreSession|completeTokenChain|refreshForCard|Logger|JSON.stringify\(want/);

  // OS identifiers and parameters remain opaque; no service/module privileged background mode.
  for (const task of starts) {
    assert.equal(JSON.stringify(task).includes('100000001'), false);
    assert.equal(JSON.stringify(task).includes('fixture'), false);
  }
  const moduleText = fs.readFileSync(path.join(root, '../module.json5'), 'utf8');
  assert.match(moduleText, /"type": "workScheduler"/); assert.doesNotMatch(moduleText, /KEEP_BACKGROUND_RUNNING/);
  console.log('background-tasks: PASS (real SQLite leases, duplicate jobs, server day, opt-in, bounded ownership, disable/reset, risk/auth/manual, registration failures and no interactive auth)');
})().catch(error => { console.error(error); process.exitCode = 1; });
