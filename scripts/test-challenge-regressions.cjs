/* Host regressions for API payloads and service/repository behavior.
 * This executes transpiled production ArkTS with mocked OS/network boundaries;
 * it does not replace an ArkTS compiler or on-device tests.
 * TYPESCRIPT_PATH=/path/to/typescript/lib/typescript.js node scripts/test-challenge-regressions.cjs
 */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
const mocks = new Map();
const noLog = { info() {}, warn() {}, error() {} };
const storage = new Map();
function mock(relative, exports) { mocks.set(path.resolve(root, relative + '.ets'), exports); }
function load(relative) {
  const file = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (mocks.has(file)) return mocks.get(file);
  if (cache.has(file)) return cache.get(file).exports;
  const source = fs.readFileSync(file, 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: {
    target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, experimentalDecorators: true,
  }, fileName: file.replace(/\.ets$/, '.ts'), reportDiagnostics: true });
  assert.equal((output.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0, file);
  const module = { exports: {} };
  cache.set(file, module);
  const req = name => name.startsWith('.') ? load(path.resolve(path.dirname(file), name)) :
    (mocks.get(name) || (() => { throw new Error('Unexpected dependency ' + name); })());
  vm.runInThisContext('(function(require,module,exports,AppStorage,Observed){' + output.outputText + '\n})', { filename: file })(
    req, module, module.exports, { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) }, cls => cls);
  return module.exports;
}
mock('common/Logger', { Logger: noLog });
mock('common/Constants', { RegionUtil: { regionOfUid: () => 'cn_gf01' }, RetCodes: { ALREADY_SIGNED: -5003, RISK_CONTROL: 1034 } });

async function main() {
  const { SpiralAbyssData } = load('model/SpiralAbyss');
  const payload = { schedule_id: 42, total_star: 36, start_time: '100', floors: [{ index: 12, star: 9,
    levels: [{ index: 1, star: 3, battles: [{ index: 1, timestamp: '101', avatars: [{ id: 10000046, level: 90 }] }] }] }] };
  for (const raw of [payload, { retcode: 0, data: payload }]) {
    const abyss = SpiralAbyssData.fromJson(raw);
    assert.equal(abyss.scheduleId, 42);
    assert.equal(abyss.totalStar, 36);
    assert.equal(abyss.floors[0].levels[0].battles[0].avatars[0].id, 10000046);
  }
  const { HardChallengeRoot } = load('model/HardChallenge');
  const avatar = { avatar_id: 10000046, level: 90, rank: 2, is_plus: true };
  const period = id => ({ schedule: { schedule_id: id, start_time: '100' }, single: { has_data: true,
    challenge: [{ name: 'Boss', teams: [avatar] }] }, mp: { has_data: false }, blings: [avatar] });
  const hard = HardChallengeRoot.fromJson({ is_unlock: true, data: [period(7), period(6)] });
  assert.equal(hard.periods.length, 2);
  assert.equal(hard.periods[1].schedule[0].scheduleId, 6);
  assert.equal(hard.data.single.challenges[0].teams[0].avatars[0].level, 90);
  assert.equal(hard.data.single.challenges[0].teams[0].avatars[0].rank, 2);
  assert.equal(HardChallengeRoot.fromJson(JSON.parse(hard.itemRawJson[1])).data.schedule[0].scheduleId, 6);
  assert.equal(HardChallengeRoot.fromJson({ is_unlock: true, data: [] }).periods.length, 0);
  const legacy = period(8);
  legacy.single.challenge[0].teams = [{ avatars: [avatar] }];
  assert.equal(HardChallengeRoot.fromJson({ is_unlock: true, data: legacy }).data.single.challenges[0].teams[0].avatars[0].avatarId, avatar.avatar_id);

  // Run production migration statements against real SQLite for both fresh and v5 databases.
  const { DatabaseSync } = require('node:sqlite');
  let sqlite = new DatabaseSync(':memory:');
  const sqlStore = {
    async executeSql(sql) { sqlite.exec(sql); },
    get version() { return sqlite.prepare('PRAGMA user_version').get().user_version; },
    set version(value) { sqlite.exec('PRAGMA user_version=' + Number(value)); },
    beginTransaction() { sqlite.exec('BEGIN'); }, commit() { sqlite.exec('COMMIT'); }, rollBack() { sqlite.exec('ROLLBACK'); },
  };
  mocks.set('@kit.ArkData', { relationalStore: { getRdbStore: async () => sqlStore, SecurityLevel: { S1: 1 } } });
  const { RelationalStoreHelper } = load('data/db/RelationalStoreHelper');
  for (const oldVersion of [0, 5]) {
    sqlite = new DatabaseSync(':memory:');
    if (oldVersion === 5) {
      sqlite.exec("CREATE TABLE abyss_history (schedule_id INTEGER PRIMARY KEY,start_time INTEGER,end_time INTEGER,total_star INTEGER,raw_json TEXT,record_time INTEGER)");
      sqlite.exec("INSERT INTO abyss_history VALUES(7,100,200,36,'unattributed',1)");
      sqlite.exec('PRAGMA user_version=5');
    }
    RelationalStoreHelper.rdbStore = undefined;
    await RelationalStoreHelper.init({});
    assert.equal(sqlStore.version, 7);
    for (const table of ['challenge_records', 'cultivate_inventory', 'backup_recovery']) {
      assert.equal(sqlite.prepare("SELECT count(*) AS n FROM sqlite_master WHERE type='table' AND name=?").get(table).n, 1);
    }
    assert.ok(sqlite.prepare('PRAGMA table_info(daily_notes)').all().some(c => c.name === 'raw_json'));
    assert.ok(sqlite.prepare('PRAGMA table_info(achievement_entries)').all().some(c => c.name === 'status'));
    if (oldVersion === 5) assert.equal(sqlite.prepare('SELECT raw_json FROM abyss_history WHERE schedule_id=7').get().raw_json, 'unattributed');
    const put = sqlite.prepare('INSERT OR REPLACE INTO challenge_records(kind,uid,region,schedule_id,raw_json,record_time) VALUES(?,?,?,?,?,?)');
    put.run('abyss', '100000001', 'cn_gf01', 7, 'a', 1);
    put.run('abyss', '100000002', 'cn_gf01', 7, 'b', 1);
    put.run('abyss', '100000001', 'os_asia', 7, 'c', 1);
    put.run('abyss', '100000001', 'cn_gf01', 7, 'updated', 2);
    assert.equal(sqlite.prepare('SELECT count(*) AS n FROM challenge_records').get().n, 3);
    sqlite.close();
  }

  // Execute actual repositories against a small in-memory Rdb boundary.
  const rows = [];
  class Predicates {
    constructor(table) { this.table = table; this.filters = []; }
    equalTo(key, value) { this.filters.push([key, value]); return this; }
    orderByDesc() { return this; }
    limitAs() { return this; }
    accepts(row) { return this.filters.every(([key, value]) => row[key] === value); }
  }
  function query(pred) {
    const selected = rows.filter(row => pred.accepts(row));
    let index = -1;
    return { goToFirstRow() { index = 0; return selected.length > 0; }, goToNextRow() { return ++index < selected.length; },
      getColumnIndex(key) { return key; }, getLong(key) { return selected[index][key]; }, getString(key) { return selected[index][key] || ''; }, close() {} };
  }
  const store = { async insert(table, row) { rows.push({ ...row }); return 1; } };
  mock('data/db/RelationalStoreHelper', { RelationalStoreHelper: {
    query: async pred => query(pred), getStore: () => store,
    update: async (table, values, pred) => rows.forEach(row => { if (pred.accepts(row)) Object.assign(row, values); }),
    insert: store.insert,
  } });
  mocks.set('@kit.ArkData', { relationalStore: { RdbPredicates: Predicates, ConflictResolution: { ON_CONFLICT_REPLACE: 1 } } });
  for (const name of ['SpiralAbyss', 'RoleCombat', 'HardChallenge']) {
    const repo = load(`data/repo/${name}Repo`)[`${name}Repo`];
    const save = (uid, region, raw) => name === 'SpiralAbyss' ? repo.saveHistory(uid, region, 7, 100, 200, 36, raw) : repo.saveHistory(uid, region, 7, 100, 200, raw);
    await save('10001', 'cn_gf01', 'first');
    await save('10002', 'cn_gf01', 'second');
    await save('10001', 'os_usa', 'third');
    await save('10001', 'cn_gf01', 'updated');
    assert.equal(await repo.getRawJson('10001', 'cn_gf01', 7), 'updated');
    assert.equal(await repo.getRawJson('10002', 'cn_gf01', 7), 'second');
    assert.equal(await repo.getRawJson('10001', 'os_usa', 7), 'third');
    assert.equal((await repo.listHistory('10002', 'cn_gf01')).length, 1);
    assert.equal((await repo.listHistory('', 'cn_gf01')).length, 0);
  }
  assert.equal(rows.length, 9);

  const { SignInInfo } = load('model/SignInInfo');
  const signed = SignInInfo.fromInfo({ total_sign_day: 1, is_sign: true, today: '2026-10-29' });
  assert.equal(signed.signedDays, 1, 'A late first sign-in must not imply 29 rewards');
  assert.equal(signed.isTodaySigned(29), true);
  assert.equal(SignInInfo.fromInfo({ total_sign_day: 29, is_sign: false }).isTodaySigned(29), false);

  const { DailyNote } = load('model/DailyNote');
  const notePayload = { current_resin: 130, max_resin: 200, current_expedition_num: 5, max_expedition_num: 5,
    expeditions: [{ status: 'Ongoing' }], transformer: { obtained: true, recovery_time: { Day: 0, reached: false } },
    daily_task: { status: 2 }, archon_quest_progress: { list: [{ status: 'Ongoing', chapter_title: 'Chapter' }] } };
  const note = DailyNote.fromJson(notePayload);
  assert.equal(note.allExpeditionsFinished(), false);
  assert.equal(DailyNote.fromJson({ expeditions: [] }).allExpeditionsFinished(), false);
  const complete = DailyNote.fromJson(JSON.parse(note.rawJson));
  assert.equal(complete.transformer.obtained, true);
  assert.equal(complete.dailyTask.status, 2);
  assert.equal(complete.archonQuests[0].chapterTitle, 'Chapter');

  const { DailyNoteReminderPlan } = load('model/DailyNoteReminderPlan');
  const planned = DailyNote.fromJson({ current_resin: 100, max_resin: 200, resin_recovery_time: '48000',
    current_home_coin: 1000, max_home_coin: 2400, home_coin_recovery_time: '14000',
    expeditions: [{ status: 'Ongoing', remained_time: '3600' }, { status: 'Finished', remained_time: '0' }] });
  const timers = DailyNoteReminderPlan.build(planned, 19, 120, 1800);
  assert.equal(timers.find(p => p.kind === 0).seconds, 9600);
  assert.equal(timers.find(p => p.kind === 1).seconds, 3600);
  assert.equal(timers.find(p => p.kind === 4).seconds, 8000);
  assert.equal(DailyNoteReminderPlan.build(planned, 0, 120, 1800).length, 0);
  assert.equal(DailyNoteReminderPlan.build(planned, 1, 300, 1800).length, 0);

  const notices = [];
  let previous = { note: DailyNote.fromJson({ current_resin: 110, max_resin: 200 }), notifyFlags: 1, resinNotifyThreshold: 120 };
  const user = { id: 1, displayName: 'User', cookieToken: 'token', ltoken: 'ltoken', hasCookie: () => true, gameRecordCookie: () => 'cookie' };
  // System reminder rejection is observable; replacing one UID leaves unrelated reminders intact.
  globalThis.canIUse = () => true;
  let agentEnabled = false;
  let rejectReminder = false;
  const scheduled = [{ reminderId: 99, reminderReq: { groupId: 'other-feature' } }];
  let nextReminder = 100;
  mocks.set('@kit.NotificationKit', { notificationManager: { isNotificationEnabled: async () => true, SlotType: { SERVICE_INFORMATION: 1 } },
    reminderAgentManager: { ReminderType: { REMINDER_TYPE_TIMER: 0 }, getAllValidReminders: async () => [...scheduled],
      cancelReminder: async id => { const index = scheduled.findIndex(r => r.reminderId === id); if (index >= 0) scheduled.splice(index, 1); },
      publishReminder: async request => { if (rejectReminder) throw { code: 1700002, message: 'quota' };
        const id = nextReminder++; scheduled.push({ reminderId: id, reminderReq: request }); return id; } } });
  mocks.set('@kit.BackgroundTasksKit', { reminderAgentManager: mocks.get('@kit.NotificationKit').reminderAgentManager });
  mock('data/prefs/PreferencesStore', { PreferencesStore: { getBool: () => agentEnabled, setBool: (key, value) => { agentEnabled = value; } } });
  const reminderService = load('service/DailyNoteReminderService').DailyNoteReminderService;
  await reminderService.setEnabled(true);
  await reminderService.sync(1, '100000001', planned, { notifyFlags: 19, resinNotifyThreshold: 120, homeCoinNotifyThreshold: 1800 });
  assert.equal(scheduled.length, 4);
  await reminderService.sync(1, '100000001', planned, { notifyFlags: 19, resinNotifyThreshold: 120, homeCoinNotifyThreshold: 1800 });
  assert.equal(scheduled.length, 4, 'Replacing a snapshot must cancel previous predictions');
  rejectReminder = true;
  await assert.rejects(() => reminderService.sync(1, '100000001', planned), /数量已达上限/);
  await reminderService.setEnabled(false);
  assert.equal(scheduled.length, 1);
  assert.equal(scheduled[0].reminderReq.groupId, 'other-feature');
  mock('service/DailyNoteReminderService', { DailyNoteReminderService: { sync: async () => {} } });
  mock('data/repo/UserRepo', { UserRepo: { getAllUsers: async () => [] } });
  mock('service/UserService', { UserService: { getInstance: () => ({ getCurrentUser: () => user }), isCookieAuthError: () => false } });
  mock('data/network/HoyolabClient', { HoyolabClient: { fetchDailyNote: async () => ({ success: true, data: notePayload, isRiskControl: () => false }) } });
  mock('data/network/RiskVerifier', { RiskVerifier: {} });
  mock('data/network/DailyNoteWebhookClient', { DailyNoteWebhookClient: { send: async () => {} } });
  mock('data/network/CardVerifyApi', { DAILY_NOTE_PATH: 'dailyNote' });
  mock('data/repo/DailyNoteRepo', { DailyNoteRepo: { get: async () => previous, upsert: async (id, uid, next) => { previous = { ...previous, note: next }; } } });
  mock('data/local/NotificationHelper', { NotificationHelper: { isEnabled: () => true, publish: async (...args) => notices.push(args) } });
  mock('data/local/FormSnapshot', { FormSnapshot: { save() {}, load() { return {}; } } });
  mock('data/prefs/PreferencesStore', { PreferencesStore: { getCurrentUid: () => 'other', getString: () => '' } });
  mocks.set('@kit.FormKit', {});
  const { DailyNoteService } = load('service/DailyNoteService');
  DailyNoteService.delay = async () => {};
  await DailyNoteService.getInstance().refresh('10001');
  assert.equal(notices.length, 1, 'Crossing 120 resin must emit a notification');
  await DailyNoteService.getInstance().refresh('10001');
  assert.equal(notices.length, 1, 'Same above-threshold snapshot must not emit again');
  const allDone = DailyNote.fromJson({ expeditions: [{ status: 'Finished' }, { status: 'Finished' }] });
  await DailyNoteService.getInstance().evalAndNotify(1, '10001', allDone, { note, notifyFlags: 2 });
  assert.equal(notices.length, 2);
  await DailyNoteService.getInstance().evalAndNotify(1, '10002', allDone, { note, notifyFlags: 2 });
  assert.notEqual(notices[1][2], notices[2][2], 'Notifications from separate UIDs must not replace each other');
  console.log('PASS: challenge payloads, account isolation, sign-in truth, note persistence and notification transitions');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
