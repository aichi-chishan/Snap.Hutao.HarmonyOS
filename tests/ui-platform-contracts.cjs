// Execute the production ArkTS service logic with platform I/O replaced by deterministic doubles.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const base = path.resolve(__dirname, '../entry/src/main/ets');
const values = new Map();
const sent = [];
let launchError = 0;
const signWaits = new Map();
const archives = [];
const prefs = {
  getString: (key, fallback) => values.get(key) ?? fallback,
  getBool: (key, fallback) => values.get(key) ?? fallback,
  getNumber: (key, fallback) => values.get(key) ?? fallback,
  setString: (key, value) => values.set(key, value),
  setBool: (key, value) => values.set(key, value),
  setNumber: (key, value) => values.set(key, value),
};
const mocks = {
  PreferencesStore: { PreferencesStore: prefs },
  AppContext: { AppContextProvider: { getFilesDir: () => '/sandbox', getAppContext: () => ({ startAbility: async want => { sent.push(want); if (launchError) throw { code: launchError }; } }) } },
  Logger: { Logger: { warn() {}, info() {} } },
  GameDataService: { GameDataService: { readMetadataFile: async name => fs.readFileSync(path.resolve(base, '../resources/rawfile/metadata', name), 'utf8') } },
  BaseValueService: { Curve3: class {} },
  GachaType: { GachaType: { QUERY_ORDER: [] } },
  GachaRepo: { GachaRepo: { getOrCreateArchive: async uid => { archives.push(uid); return { id: 1 }; } } },
  DailyNoteRepo: { DailyNoteRepo: { get: async (_, uid) => ({ note: { uid, refreshTime: 0 } }) } },
  SignInService: { SignInService: { getInstance: () => ({ fetchInfo: uid => signWaits.get(uid) || Promise.resolve({ uid }) }) } },
  CalendarService: { CalendarService: { getInstance: () => ({ fetchCalendar: async uid => [{ uid, startTime: 0, endTime: Date.now() + 100000 }] }) } },
  AnnouncementService: { AnnouncementService: { getInstance: () => ({ fetchList: async () => [] }) } },
  UserService: { UserService: { getInstance: () => ({ getCurrentUser: () => ({ id: 1 }) }) } },
};
for (const name of ['SpiralAbyssService', 'RoleCombatService', 'HardChallengeService']) mocks[name] = { [name]: { getInstance: () => ({ fetch: async () => undefined }) } };
function load(name) {
  const file = path.resolve(base, `${name}.ets`);
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true } }).outputText;
  const mod = { exports: {} };
  const requireDouble = id => {
    const key = id.split('/').at(-1);
    if (mocks[key]) return mocks[key];
    if (id.startsWith('@kit.')) return {};
    return load(path.relative(base, path.resolve(path.dirname(file), id)));
  };
  vm.runInNewContext(`(function(require,module,exports){${output}\n})`, { Observed: value => value, AppStorage: { setOrCreate: (k, v) => values.set(k, v) } })(requireDouble, mod, mod.exports);
  return mod.exports;
}
(async () => {
  const { GameCalendarRules: calendar } = load('service/GameCalendarRules');
  const start = Date.parse('2026-10-01T18:00:00+08:00');
  const events = [{ type: 301, from: start }];
  assert.equal(calendar.allMaterialsOpen(Date.parse('2026-09-30T23:59:59+08:00'), events), false);
  assert.equal(calendar.allMaterialsOpen(Date.parse('2026-10-01T00:00:00+08:00'), events), true);
  assert.equal(calendar.allMaterialsOpen(Date.parse('2026-10-07T23:59:59+08:00'), events), true);
  assert.equal(calendar.allMaterialsOpen(Date.parse('2026-10-08T00:00:00+08:00'), events), false);
  assert.equal(calendar.allMaterialsOpen(start, [{ type: 302, from: start }]), false);
  assert.equal(calendar.allMaterialsOpen(start, [{ type: 400, from: start }]), true);
  assert.equal(calendar.serverDay(Date.parse('2026-10-01T04:59:59Z'), -5) + 1, calendar.serverDay(Date.parse('2026-10-01T05:00:00Z'), -5));
  assert.equal(calendar.serverOffset('os_euro'), 1);

  const { GameLauncherService: launcher, GamePackage } = load('service/GameLauncherService');
  assert.equal((await launcher.launch()).status, 'unconfigured');
  assert.equal(sent.length, 0, 'never guess a bundle or scan installations');
  const target = new GamePackage(); target.packageName = 'vendor.verified.game'; target.abilityName = 'GameAbility';
  assert.equal(launcher.saveTarget(target), '');
  assert.equal((await launcher.launch()).ok, true);
  assert.equal(sent.at(-1).abilityName, 'GameAbility');
  target.uri = 'vendor-public://play'; assert.equal(launcher.saveTarget(target), '');
  await launcher.launch(); assert.equal(sent.at(-1).uri, target.uri); assert.equal(sent.at(-1).bundleName, undefined);
  target.uri = 'file:///private'; assert.notEqual(launcher.validationMessage(target), '');
  launchError = 16000001; assert.equal((await launcher.launch()).status, 'unavailable');
  launchError = 201; assert.equal((await launcher.launch()).status, 'failed');
  launcher.clearTarget(); assert.equal((await launcher.launch()).status, 'unconfigured');

  const { WikiMetaService: wiki } = load('service/WikiMetaService');
  const weapons = await wiki.getWeapons();
  assert.ok(weapons.length > 200);
  assert.ok(weapons.filter(w => w.secondaryProperty === 22).length > 0);
  for (const type of new Set(weapons.map(w => w.weaponType))) assert.ok(!wiki.weaponTypeName(type).startsWith('类型'), `unknown enum ${type}`);

  const { BackgroundMediaService: media } = load('service/BackgroundMediaService');
  assert.equal(media.officialVideo({ game_info_list: [{ game: { biz: 'hk4e_cn' }, backgrounds: [{ type: 'BACKGROUND_TYPE_VIDEO', video: { url: 'https://example.test/video.mp4' } }] }] }), 'https://example.test/video.mp4');
  assert.equal(media.officialVideo({ game_info_list: [{ game: { biz: 'hkrpg_cn' }, backgrounds: [{ type: 'BACKGROUND_TYPE_VIDEO', video: { url: 'https://example.test/wrong.mp4' } }] }] }), '');
  assert.equal(media.officialVideo({ game_info_list: [] }), '');

  const { HomeViewModel } = load('viewmodel/HomeViewModel');
  const home = new HomeViewModel();
  let finishA; signWaits.set('A', new Promise(resolve => { finishA = resolve; }));
  const first = home.load('A');
  await home.load('B');
  assert.equal(home.note.uid, 'B'); assert.equal(home.signInfo.uid, 'B');
  finishA({ uid: 'A' }); await first;
  assert.equal(home.currentUid, 'B'); assert.equal(home.signInfo.uid, 'B'); assert.equal(home.acts[0].uid, 'B');
  await home.load('');
  assert.equal(home.note, undefined); assert.equal(home.signInfo, undefined); assert.equal(home.acts.length, 0); assert.equal(home.gachaTotal, 0);
  assert.ok(!archives.includes(''), 'logout must not create an empty archive');
  console.log('ui-platform-contracts: PASS (server dates, seven-day boundaries, native routing, metadata enums, video source, account races)');
})().catch(error => { console.error(error); process.exitCode = 1; });
