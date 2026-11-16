const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const plain = value => JSON.parse(JSON.stringify(value));

function harness() {
  const state = { items: [], events: [], avatars: [], weapons: [] };
  const modules = new Map();
  function load(name) {
    if (modules.has(name)) return modules.get(name);
    if (name === 'service/WikiMetaService') return { WikiMetaService: {
      getGachaEvents: async () => state.events, getAvatars: async () => state.avatars,
      getWeapons: async () => state.weapons,
    } };
    if (name === 'data/repo/GachaRepo') return { GachaRepo: {
      getAllArchives: async () => [{ id: 1, uid: '100000001' }], getItemsByArchive: async () => state.items,
    } };
    if (name === 'service/GameDataService') return { GameDataService: { getInstance: () => ({ remoteVersion: () => '' }) } };
    if (name === 'service/LocalizedGameDataService') return { LocalizedGameDataService: { names: async () => new Map() } };
    if (name === 'common/Logger') return { Logger: { info() {} } };
    if (name === 'service/UigfService') return { UigfService: {
      timezoneOfUid: () => 8,
      normalizeTime: time => new Date(time.replace(' ', 'T') + '+08:00').toISOString().slice(0, 19).replace('T', ' '),
    } };
    const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
    const result = ts.transpileModule(source, { reportDiagnostics: true,
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
    assert.equal(result.diagnostics.length, 0, name);
    const module = { exports: {} };
    vm.runInNewContext(result.outputText, { module, exports: module.exports, require: id =>
      load(path.posix.normalize(path.posix.join(path.posix.dirname(name), id))) });
    modules.set(name, module.exports);
    return module.exports;
  }
  return { state, counter: load('service/GachaCollectionService').GachaCollectionService,
    history: load('service/GachaHistoryService').GachaHistoryService.getInstance() };
}
const avatar = (id, name, quality) => ({ id, name, quality, icon: 'a' + id });
const weapon = (id, name, rankLevel) => ({ id, name, rankLevel, icon: 'w' + id });
const item = (itemId, name, rankType, gachaType, count = 1) =>
  ({ itemId, name, rankType, gachaType, count, itemType: itemId >= 10000000 ? '角色' : '武器', time: '2026-09-01 12:00:00' });

test('all pools contribute exactly once, including three-star weapons; UGC is a separate collection', () => {
  const h = harness();
  const rows = [item(10000002, '甲', 5, 301), item(10000003, '乙', 4, 400), item(10000003, '乙', 4, 200),
    item(11301, '剑', 3, 301), item(11301, '剑', 3, 302, 99), item(11401, '弓', 4, 100),
    item(250013, '颂愿物品', 2, 20011)];
  const before = JSON.stringify(rows);
  const result = h.counter.count(rows, [avatar(10000002, '甲', 5), avatar(10000003, '乙', 4)],
    [weapon(11301, '剑', 3), weapon(11401, '弓', 4)], [], false);
  assert.deepEqual(plain(result.avatars.map(x => [x.name, x.count])), [['甲', 1], ['乙', 2]]);
  assert.deepEqual(plain(result.weapons.map(x => [x.name, x.count])), [['弓', 1], ['剑', 2]]);
  assert.equal(JSON.stringify(rows), before);
});

test('unobtained catalog follows Windows rarity and standard/event weapon sets, ordered by count', () => {
  const h = harness();
  const avatars = [avatar(10000002, '甲', 5), avatar(10000003, '乙', 5), avatar(10000004, '丙', 4), avatar(10000005, '联动', 105)];
  const weapons = [weapon(11301, '三星祈愿', 3), weapon(11399, '三星宝箱', 3), weapon(11401, '四星常驻', 4),
    weapon(11499, '四星限定', 4), weapon(11498, '四星锻造', 4), weapon(11599, '五星', 5)];
  const events = [{ type: 302, upPurple: [11499] }, { type: 301, upPurple: [11498] }];
  const result = h.counter.count([item(10000003, '乙', 5, 301), item(10000003, '乙', 5, 400)], avatars, weapons, events, true);
  assert.deepEqual(plain(result.avatars.map(x => [x.itemId, x.count])), [[10000003, 2], [10000002, 0], [10000004, 0]]);
  assert.deepEqual(plain(result.weapons.map(x => x.itemId)), [11599, 11401, 11499, 11301]);
  assert.equal(h.counter.count([], avatars, weapons, events, false).avatars.length, 0);
  assert.equal(avatars[0].count, undefined);
});

test('known item identity unifies old name-only records while unknown IDs stay distinct', () => {
  const h = harness();
  const old = item(0, '甲', 5, 301); old.itemType = '角色';
  const result = h.counter.count([old, item(10000002, '甲', 5, 400), item(11991, '同名', 4, 302), item(11992, '同名', 4, 302)],
    [avatar(10000002, '甲', 5)], [], [], false);
  assert.equal(result.avatars[0].count, 2);
  assert.equal(result.weapons.length, 2);
});

test('name-only records still match featured items after a language change', async () => {
  const h = harness();
  h.state.avatars = [{ ...avatar(10000002, 'Featured', 5), canonicalName: '活动角色' }];
  h.state.weapons = [{ ...weapon(11599, 'Blade', 5), canonicalName: '长剑' }];
  const oldAvatar = item(0, '活动角色', 5, 301);
  oldAvatar.itemType = '角色';
  h.state.items = [oldAvatar, item(10000002, 'Featured', 5, 301), item(0, '长剑', 5, 302)];
  const result = h.counter.count(h.state.items, h.state.avatars, h.state.weapons, [], false);
  assert.deepEqual(plain(result.avatars.map(entry => [entry.itemId, entry.name, entry.count])), [[10000002, 'Featured', 2]]);
  assert.deepEqual(plain(result.weapons.map(entry => [entry.itemId, entry.name, entry.count])), [[11599, 'Blade', 1]]);
  const from = Date.parse('2026-09-01T00:00:00+08:00');
  const to = Date.parse('2026-09-02T00:00:00+08:00');
  h.state.events = [{ type: 301, from, to, upOrange: [10000002], upPurple: [] },
    { type: 302, from, to, upOrange: [11599], upPurple: [] }];
  const history = await h.history.buildHistory(1);
  assert.deepEqual(plain(history.map(entry => [entry.orangeUps[0].name, entry.orangeUps[0].count])), [['Featured', 2], ['Blade', 1]]);
});

test('empty history switch preserves separate 301/400 periods and Windows ordering', async () => {
  const h = harness();
  const from = Date.parse('2026-09-01T00:00:00+08:00');
  const to = Date.parse('2026-09-10T23:59:59+08:00');
  h.state.events = [302, 400, 301].map(type => ({ type, from, to, name: String(type), version: '6.0',
    banner: '', upOrange: [10000002], upPurple: [] }));
  h.state.avatars = [avatar(10000002, '甲', 5)];
  assert.equal((await h.history.buildHistory(1)).length, 0);
  assert.deepEqual(plain((await h.history.buildHistory(1, true)).map(x => x.type)), [301, 400, 302]);
  h.state.items = [item(10000002, '甲', 5, 400)];
  const nonempty = await h.history.buildHistory(1);
  assert.deepEqual(plain(nonempty.map(x => [x.type, x.totalCount, x.orangeUps[0].count])), [[400, 1, 1]]);
  assert.deepEqual(plain((await h.history.buildHistory(1, true)).map(x => x.totalCount)), [0, 1, 0]);
});
