const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const modules = new Map();
function load(name) {
  const filename = path.resolve(root, `${name}.ets`);
  if (modules.has(filename)) { return modules.get(filename); }
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    reportDiagnostics: true,
  });
  assert.equal(compiled.diagnostics.length, 0, filename);
  const module = { exports: {} };
  const requireLocal = (specifier) => {
    assert(specifier.startsWith('.'), `Unexpected runtime dependency ${specifier}`);
    return load(path.relative(root, path.resolve(path.dirname(filename), specifier)));
  };
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`)(requireLocal, module, module.exports);
  modules.set(filename, module.exports);
  return module.exports;
}

const { WikiAvatarGuide } = load('service/WikiAvatarGuide');
const { AvatarGuideReference } = load('model/AvatarGuideReference');
const snapshot = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../scripts/data/wiki-avatar-guides.json'), 'utf8'));
const avatars = JSON.parse(fs.readFileSync(path.resolve(root, '../resources/rawfile/metadata/avatar_meta.json'), 'utf8'));

test('Chinese guide IDs match the official role tree and preserve both travelers', () => {
  assert.equal(AvatarGuideReference.chinese.size, 124);
  const byTitle = new Map(snapshot.mys.rows.map((row) => [row.title, row.id]));
  for (const avatar of avatars) {
    const expectedId = byTitle.get(avatar.name);
    assert(expectedId > 0, `${avatar.id}: missing publisher source`);
    const url = WikiAvatarGuide.url('mys', avatar.id, avatar.name, 'en');
    assert.equal(url, `https://baike.mihoyo.com/ys/strategy/channel/map/39/${expectedId}?bbs_presentation_style=no_header`);
  }
  assert.equal(AvatarGuideReference.chinese.get(10000005), 90);
  assert.equal(AvatarGuideReference.chinese.get(10000007), 90);
  assert.match(WikiAvatarGuide.url('mys', 10000136, '米提亚', 'en'), /\/39\/535\?/);
  assert.match(WikiAvatarGuide.url('mys', 10000137, '瓦列里', 'zh-Hans'), /\/39\/536\?/);
});

test('HoYoLAB uses verified guide group IDs and leaves absent characters unavailable', () => {
  const expected = new Map([[10000002, 188], [10000063, 195], [10000071, 179], [10000079, 246], [10000080, 402]]);
  assert.equal(AvatarGuideReference.hoyolab.size, expected.size);
  const sourceIds = new Set(snapshot.hoyolab.rows.map((row) => row.id));
  for (const [avatarId, guideId] of expected) {
    assert(sourceIds.has(guideId));
    assert.equal(WikiAvatarGuide.url('hoyolab', avatarId, 'irrelevant translated display name', 'en'),
      `https://www.hoyolab.com/guidelist?game_id=2&guide_id=${guideId}`);
  }
  for (const avatarId of [10000005, 10000046, 10000136, 10000137, 19999999]) {
    assert.equal(WikiAvatarGuide.url('hoyolab', avatarId, '胡桃', 'en'), '');
  }
  assert.equal(WikiAvatarGuide.url('mys', 19999999, '胡桃', 'zh-Hans'), '');
});

test('Bilibili encodes the canonical name and follows Windows simplified-Chinese visibility', () => {
  for (const locale of ['zh-Hans', 'zh-CN', 'zh_Hans_CN']) {
    const url = new URL(WikiAvatarGuide.url('bili', 10000046, ' 胡桃 ', locale));
    assert.equal(url.hostname, 'wiki.biligame.com');
    assert.equal(decodeURIComponent(url.pathname), '/ys/胡桃/攻略');
  }
  const encoded = WikiAvatarGuide.url('bili', 10000046, '名字/带?参数#&', 'zh-Hans');
  assert.equal(new URL(encoded).search, '');
  assert.equal(new URL(encoded).hash, '');
  for (const locale of ['en', 'zh-Hant', 'zh-TW', 'ja', 'ar']) {
    assert.equal(WikiAvatarGuide.url('bili', 10000046, '胡桃', locale), '');
  }
  assert.equal(WikiAvatarGuide.url('bili', 10000046, '   ', 'zh-Hans'), '');
});

test('Invalid avatar identities and unknown targets never produce a guide URL', () => {
  for (const avatarId of [NaN, Infinity, -1, 0, 9999999, 100000000, 10000046.5]) {
    for (const target of ['mys', 'bili', 'hoyolab']) {
      assert.equal(WikiAvatarGuide.url(target, avatarId, '胡桃', 'zh-Hans'), '');
    }
  }
  assert.equal(WikiAvatarGuide.url('unknown', 10000046, '胡桃', 'en'), '');
});

test('All fifteen sets of captions match the four exact Windows resource keys', () => {
  const locales = ['zh-Hans', 'zh-Hant', 'de', 'en', 'es', 'fr', 'id', 'it', 'ja', 'ko', 'pt', 'ru', 'th', 'tr', 'vi'];
  const keys = ['ViewPageWiKiAvatarStrategyChineseButtonLabel', 'ViewPageWiKiAvatarStrategyBilibiliButtonLabel',
    'ViewPageWiKiAvatarStrategyOverseaButtonLabel', 'ViewModelWikiAvatarStrategyNotFound'];
  const labels = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../scripts/data/wiki-avatar-labels.json'), 'utf8'));
  const positions = keys.map((key) => {
    const index = labels.keys.indexOf(key);
    assert(index >= 0, `Missing shared caption ${key}`);
    return index;
  });
  assert.equal(AvatarGuideReference.labels.size, locales.length);
  for (const locale of locales) {
    assert.equal(labels.locales[locale].length, labels.keys.length, locale);
    const source = positions.map((index) => labels.locales[locale][index]);
    assert.equal(WikiAvatarGuide.label('mys', locale), source[0]);
    assert.equal(WikiAvatarGuide.label('bili', locale), source[1]);
    assert.equal(WikiAvatarGuide.label('hoyolab', locale), source[2]);
    assert.equal(WikiAvatarGuide.unavailable(locale), source[3]);
  }
  assert.equal(WikiAvatarGuide.label('unknown', 'en'), '');
  assert.equal(WikiAvatarGuide.unavailable('ar'), WikiAvatarGuide.unavailable('en'));
});
