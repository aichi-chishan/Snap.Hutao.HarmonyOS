// Execute the production ArkTS service logic with platform I/O replaced by deterministic doubles.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const base = path.resolve(__dirname, '../entry/src/main/ets');
const values = new Map();
const currentUser = { id: 1 };
const sent = [];
let launchError = 0;
let nativeLanguage = 'default';
const signWaits = new Map();
const archives = [];
const announcementWaits = new Map();
const announcementRequests = [];
const calendarEntries = new Map();
const calendarCalls = [];
const trackedUids = new Map();
const noteRefreshRequests = [];
let waitForNoteRefresh;
const trackedNoteEntries = () => Array.from(trackedUids, ([userId, uids]) =>
  [...new Set(uids)].map(uid => ({ userId, uid, record: { note: { uid, refreshTime: 0 },
    resinNotifyThreshold: 100, homeCoinNotifyThreshold: 1400 } }))).flat();
const prefs = {
  isReady: () => true,
  getString: (key, fallback) => values.get(key) ?? fallback,
  getBool: (key, fallback) => values.get(key) ?? fallback,
  getNumber: (key, fallback) => values.get(key) ?? fallback,
  getTrackedUids: userId => trackedUids.get(userId) ?? [],
  setString: (key, value) => values.set(key, value),
  setBool: (key, value) => values.set(key, value),
  setNumber: (key, value) => values.set(key, value),
};
const mocks = {
  '@kit.LocalizationKit': { i18n: { System: {
    getSystemLanguage: () => 'zh-Hans', getAppPreferredLanguage: () => nativeLanguage,
    setAppPreferredLanguage: language => { nativeLanguage = language; },
  } } },
  PreferencesStore: { PreferencesStore: prefs },
  AppContext: { AppContextProvider: { getFilesDir: () => '/sandbox', getAppContext: () => ({ startAbility: async want => { sent.push(want); if (launchError) throw { code: launchError }; } }) } },
  Logger: { Logger: { warn() {}, info() {} } },
  GameDataService: { GameDataService: {
    readMetadataFile: async name => fs.readFileSync(path.resolve(base, '../resources/rawfile/metadata', name), 'utf8'),
    readLanguageFiles: async name => [fs.readFileSync(path.resolve(base, '../resources/rawfile/metadata', name), 'utf8')],
  } },
  BaseValueService: { Curve3: class {} },
  GachaType: { GachaType: { QUERY_ORDER: [] } },
  GachaRepo: { GachaRepo: { getOrCreateArchive: async uid => { archives.push(uid); return { id: 1 }; } } },
  DailyNoteRepo: { DailyNoteRepo: { get: async (_, uid) => ({ note: { uid, refreshTime: 0 }, resinNotifyThreshold: 100,
    homeCoinNotifyThreshold: 1400 }) } },
  DailyNoteService: { DailyNoteService: { getInstance: () => ({ trackedEntries: async () => trackedNoteEntries(),
    refreshTrackedList: async () => {
    const entries = trackedNoteEntries();
    noteRefreshRequests.push(...entries.map(({ userId, uid }) => ({ userId, uid })));
    if (waitForNoteRefresh) { await waitForNoteRefresh; }
    return { total: entries.length, succeeded: entries.length, firstError: '' };
  } }) } },
  SignInService: { SignInService: { getInstance: () => ({ fetchInfo: uid => signWaits.get(uid) || Promise.resolve({ uid }) }) } },
  CalendarService: { CalendarEntryOrder: { Home: 1 }, CalendarService: { getInstance: () => ({
    fetchCalendar: async (uid, current, order) => {
      calendarCalls.push({ uid, current: current(), order });
      return calendarEntries.get(uid) ?? [{ uid, startTime: 0, endTime: Date.now() + 100000 }];
    },
  }) } },
  AnnouncementService: { AnnouncementService: { getInstance: () => ({ fetchGroups: async (region, level, language) => {
    announcementRequests.push({region, level, language});
    return announcementWaits.get(region) ?? [];
  } }) } },
  UserService: { UserService: { getInstance: () => ({ getCurrentUser: () => currentUser, sessionRevision: () => 0,
    isSessionTransitionPending: () => false }) } },
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
  vm.runInNewContext(`(function(require,module,exports){${output}\n})`, { Observed: value => value,
    AppStorage: { get: key => values.get(key), setOrCreate: (k, v) => values.set(k, v) } })(requireDouble, mod, mod.exports);
  return mod.exports;
}
function loadComponentState(name, scope, firstDeclaration = 'export struct') {
  const source = fs.readFileSync(path.resolve(base, `${name}.ets`), 'utf8');
  const methods = source.slice(source.indexOf(firstDeclaration), source.search(/^  (?:@Builder|build\(\))/m))
    .replace(/@Entry\s*@Component\s*/g, '') + '}';
  const { outputText, diagnostics } = ts.transpileModule(methods.replace('export struct', 'export class'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true },
    reportDiagnostics: true,
  });
  assert.equal(diagnostics.length, 0);
  const exports = {};
  vm.runInNewContext(outputText, { exports, ...scope, Prop() {}, State() {},
    StorageProp: () => () => {}, Watch: () => () => {} });
  return new exports[name.split('/').at(-1)]();
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
  const avatars = await wiki.getAvatars();
  assert.equal(wiki.associationName(avatars.find(avatar => avatar.id === 10000002).association), '稻妻');
  assert.equal(wiki.associationName(avatars.find(avatar => avatar.id === 10000021).association), '蒙德');
  assert.equal(wiki.qualityName(105), '限定五星');
  const { BaseValueService: baseValues } = load('service/BaseValueService');
  const harbinger = weapons.find(weapon => weapon.id === 11302);
  assert.equal(baseValues.weaponMaxLevel(harbinger.rankLevel), 90);
  assert.equal(baseValues.promoteLevel(70, 70, true), 4);
  const weaponStats = await baseValues.weaponBaseValues(harbinger.growCurves, harbinger.promoteId, 90, 90, true);
  assert.equal(weaponStats.attack, 401);
  assert.equal(weaponStats.secondary, '暴击伤害 +46.9%');
  assert.equal(baseValues.fightPropName(28), '元素精通');
  assert.equal(baseValues.fightPropText(28, 115.2), '115');
  assert.equal(baseValues.fightPropName(23), '元素充能效率');
  assert.equal(baseValues.fightPropText(23, 0.096), '+9.6%');

  const materialLoads = [];
  const signCard = loadComponentState('components/HomeSignInCard', { Scroller: class {}, WikiMetaService: {
    getMaterials: () => new Promise(resolve => materialLoads.push(resolve)),
  }, Scroller: class { scrollToIndex() {} } });
  signCard.aboutToAppear();
  signCard.localeVersion = 1;
  signCard.loadRewardIcons();
  materialLoads[1](new Map([[201, { n: 'Primogem', canonicalName: '原石', i: 'UI_ItemIcon_201' }]]));
  await Promise.resolve();
  assert.equal(signCard.rewardIcons.get('原石'), 'UI_ItemIcon_201');
  assert.equal(signCard.rewardIcons.get('Primogem'), 'UI_ItemIcon_201');
  materialLoads[0](new Map([[201, { n: '原石', canonicalName: '原石', i: 'older' }]]));
  await Promise.resolve();
  assert.equal(signCard.rewardIcons.get('原石'), 'UI_ItemIcon_201');
  signCard.aboutToDisappear();
  signCard.loadRewardIcons();
  assert.equal(materialLoads.length, 2);

  const achievementModel = load('model/AchievementData');
  const achievementReads = [];
  let achievementName = 'A Friend';
  const achievementPage = loadComponentState('pages/AchievementPage', {
    ...achievementModel,
    SimpleDataSource: class {
      notifyDataReload(rows) { this.rows = rows; }
    },
    AchievementService: {
      getArchives: async () => [{ id: 7, isSelected: true }],
      getRecords: async id => {
        achievementReads.push(id);
        return new Map([[81234, { status: 2, timestamp: 12345 }]]);
      },
      getCategoryStats: async () => [{ category: { id: 5, name: 'Test category', entries: [81234, 81235].map(id =>
        Object.assign(new achievementModel.AchievementEntry(), { id, name: achievementName, canonicalName: '一位朋友' })) },
      stats: { total: 2, done: 1, primogemsTotal: 10, primogemsEarned: 5 } }],
    },
  }, 'class AchievementRow');
  achievementPage.categoryFilter = 5;
  achievementPage.statusFilter = 1;
  achievementPage.keyword = '一位朋友';
  achievementPage.attached = true;
  await achievementPage.reload();
  assert.equal(achievementPage.entrySource.rows[0].entry.name, 'A Friend');
  achievementName = '友人';
  achievementPage.localeVersion = 1;
  achievementPage.onLocaleChanged();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(achievementReads, [7, 7]);
  assert.equal(achievementPage.currentArchiveId, 7);
  assert.equal(achievementPage.categoryFilter, 5);
  assert.equal(achievementPage.statusFilter, 1);
  assert.equal(achievementPage.keyword, '一位朋友');
  assert.equal(achievementPage.visibleCount, 1);
  assert.equal(achievementPage.entrySource.rows[0].entry.id, 81234);
  assert.equal(achievementPage.entrySource.rows[0].entry.name, '友人');

  const { BackgroundMediaService: media } = load('service/BackgroundMediaService');
  assert.equal(media.officialVideo({ game_info_list: [{ game: { biz: 'hk4e_cn' }, backgrounds: [{ type: 'BACKGROUND_TYPE_VIDEO', video: { url: 'https://example.test/video.mp4' } }] }] }), 'https://example.test/video.mp4');
  assert.equal(media.officialVideo({ game_info_list: [{ game: { biz: 'hkrpg_cn' }, backgrounds: [{ type: 'BACKGROUND_TYPE_VIDEO', video: { url: 'https://example.test/wrong.mp4' } }] }] }), '');
  assert.equal(media.officialVideo({ game_info_list: [] }), '');

  const { HomeViewModel } = load('viewmodel/HomeViewModel');
  const home = new HomeViewModel();
  trackedUids.set(1, ['A', 'B']);
  let finishA; signWaits.set('A', new Promise(resolve => { finishA = resolve; }));
  const first = home.load('A');
  await home.load('B');
  assert.deepEqual(Array.from(home.noteEntries, entry => [entry.userId, entry.uid]), [[1, 'A'], [1, 'B']]);
  assert.equal(home.signInfo.uid, 'B');
  finishA({ uid: 'A' }); await first;
  assert.equal(home.currentUid, 'B'); assert.equal(home.signInfo.uid, 'B'); assert.equal(home.acts[0].uid, 'B');
  const now = Date.now();
  const allActivities = [
    { name: '待公布', startTime: 0, endTime: 0 },
    { name: '已排期', startTime: now + 60000, endTime: now + 120000 },
    ...Array.from({ length: 7 }, (_, index) => ({ name: `活动${index}`, startTime: now - 120000, endTime: now - 60000 })),
  ];
  calendarEntries.set('B', allActivities);
  await home.load('B');
  assert.deepEqual(Array.from(home.acts), allActivities);
  assert.deepEqual(calendarCalls.at(-1), { uid: 'B', current: true, order: 1 });
  calendarEntries.clear();
  trackedUids.set(1, ['B', 'C', 'C']);
  await home.reloadNote('B');
  assert.deepEqual(Array.from(home.noteEntries, entry => [entry.uid, entry.resinThreshold, entry.homeCoinThreshold]),
    [['B', 100, 1400], ['C', 100, 1400]]);
  assert.equal(await home.refreshNotes(), '已刷新 2/2 个 UID 的便笺');
  assert.deepEqual(noteRefreshRequests, [{ userId: 1, uid: 'B' }, { userId: 1, uid: 'C' }]);
  let finishNoteRefresh;
  waitForNoteRefresh = new Promise(resolve => { finishNoteRefresh = resolve; });
  const staleRefresh = home.refreshNotes();
  await home.load('A');
  finishNoteRefresh();
  assert.equal(await staleRefresh, '');
  assert.deepEqual(noteRefreshRequests.slice(2), [{ userId: 1, uid: 'B' }, { userId: 1, uid: 'C' }],
    'the service retains the whole owned refresh batch; the Home VM only suppresses stale presentation');
  waitForNoteRefresh = undefined;
  trackedUids.clear();
  await home.load('');
  assert.equal(home.noteEntries.length, 0); assert.equal(home.signInfo, undefined); assert.equal(home.acts.length, 0); assert.equal(home.gachaTotal, 0);
  assert.ok(!archives.includes(''), 'logout must not create an empty archive');
  let finishUs, finishAsia;
  announcementWaits.set('os_usa', new Promise(resolve => { finishUs = resolve; }));
  announcementWaits.set('os_asia', new Promise(resolve => { finishAsia = resolve; }));
  const usLoad = home.load('600000001');
  const asiaLoad = home.load('800000001');
  assert.equal(home.announcementGroups.length, 0, 'old region preview clears before async work');
  assert.equal(home.announcementsLoaded, false);
  const asiaEntry = id => ({ id, sourceRegion: 'os_asia', sourceLanguage: 'zh-cn', sourceLevel: 55 });
  const game = { typeId: 2, label: '游戏公告', items: [] };
  const activity = { typeId: 1, label: '活动公告', items: [2, 3, 4, 5, 6].map(asiaEntry) };
  const beyond = { typeId: 5, label: '千星奇域', items: [asiaEntry(7)] };
  finishAsia([game, activity, beyond]); await asiaLoad;
  finishUs([{ typeId: 1, label: '活动公告', items: [{ id: 1, sourceRegion: 'os_usa' }] }]); await usLoad;
  assert.deepEqual(Array.from(home.announcementGroups, group => group.typeId), [1, 2, 5]);
  assert.equal(home.announcementGroups[0].items[0].sourceRegion, 'os_asia', 'late region never replaces active preview');
  assert.deepEqual(Array.from(home.announcementGroups[0].items, item => item.id), [2, 3, 4, 5, 6]);
  assert.deepEqual(announcementRequests.slice(-2), [
    {region:'os_usa',level:55,language:'zh-cn'}, {region:'os_asia',level:55,language:'zh-cn'}]);
  const scrolls = [];
  const card = loadComponentState('components/HomeAnnouncementCard', {
    Scroller: class { scrollTo(options) { scrolls.push(options.yOffset); } },
  });
  card.groups = home.announcementGroups;
  card.aboutToAppear();
  assert.equal(card.selectedTypeId, 1);
  assert.equal(card.selectedItems()[4].id, 6, 'the fifth item in a category remains available');
  card.selectCategory(5);
  assert.deepEqual(scrolls, [0]);
  assert.equal(card.selectedItems()[0].sourceRegion, 'os_asia');
  card.groups = [beyond, game, { ...activity, items: [...activity.items, asiaEntry(8)] }];
  card.onGroupsChanged();
  assert.equal(card.selectedTypeId, 5, 'refresh retains the selected type after a reordering');
  card.groups = [game, activity];
  card.onGroupsChanged();
  assert.equal(card.selectedTypeId, 2, 'removed category falls back to the first official group');
  assert.equal(card.selectedItems().length, 0);
  for (const [width, columns] of [[600, 1], [840, 2], [1200, 4]]) {
    card.contentWidth = width;
    assert.equal(card.columns(), columns);
  }

  let finishSameOwner;
  announcementWaits.set('os_asia', new Promise(resolve => { finishSameOwner = resolve; }));
  const sameOwner = home.load('800000001');
  assert.equal(home.announcementGroups.length, 3, 'same-owner reload keeps old tabs until the result arrives');
  finishSameOwner([activity]); await sameOwner;
  assert.deepEqual(Array.from(home.announcementGroups, group => group.typeId), [1], 'one source group is a valid response');
  console.log('ui-platform-contracts: PASS (server dates, native routing, metadata enums, localized achievements and reward icons, video source, account races)');
})().catch(error => { console.error(error); process.exitCode = 1; });
