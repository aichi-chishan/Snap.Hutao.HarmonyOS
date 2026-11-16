// Production Wiki tokens under host execution, with the real roster and Windows resource vocabulary.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const ets = path.join(root, 'entry/src/main/ets');
const metadata = path.join(root, 'entry/src/main/resources/rawfile/metadata');
const labels = JSON.parse(fs.readFileSync(path.join(root, 'scripts/data/wiki-avatar-labels.json'), 'utf8'));
const modules = new Map();

function load(relative) {
  const filename = path.resolve(ets, relative + '.ets');
  if (modules.has(filename)) return modules.get(filename).exports;
  const source = fs.readFileSync(filename, 'utf8');
  const compiled = ts.transpileModule(source, { reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } });
  assert.equal(compiled.diagnostics.length, 0, relative);
  const module = { exports: {} };
  modules.set(filename, module);
  vm.runInThisContext(`(function(require,module,exports){${compiled.outputText}\n})`, { filename })(specifier => {
    assert.ok(specifier.startsWith('.'), 'Unexpected platform dependency ' + specifier);
    return load(path.relative(ets, path.resolve(path.dirname(filename), specifier)));
  }, module, module.exports);
  return module.exports;
}

const { WikiAvatarFilter: Filter, WikiAvatarToken: Token, WikiAvatarTokenKind: Kind } = load('service/WikiAvatarFilter');
const { CultivationFilterToken } = load('model/CultivationFilterToken');
const { LocalePolicy } = load('model/LocalePolicy');
const read = filename => JSON.parse(fs.readFileSync(path.join(metadata, filename), 'utf8'));
const raw = read('avatar_meta.json');
const associations = read('avatar_associations.json');
const ids = rows => rows.map(row => row.id);
const token = (kind, value, label = value, alias = '') => new Token(kind, value, label, alias);
const choice = (catalog, kind, value) => {
  const found = catalog.find(entry => entry.kind === kind && entry.value === value);
  assert.ok(found, `Missing ${kind}:${value}`);
  return found;
};
const makeAvatar = (id, name, quality, weapon, vision, association, body, canonicalName = name) =>
  ({ id, name, canonicalName, quality, weapon, vision, association, body, title: 'Name only should exclude this title' });
const mixed = [
  makeAvatar(1, 'Alpha', 5, 1, '火', 4, 1, '甲'),
  makeAvatar(2, 'Beta', 4, 12, '水', 15, 2, '乙'),
  makeAvatar(3, 'Gamma', 105, 11, '火', 1, 3, '丙'),
  makeAvatar(4, 'Delta', 5, 1, '雷', 15, 2, '丁'),
  makeAvatar(5, 'Epsilon', 4, 10, '冰', 14, 5, '戊'),
];

function roster(locale) {
  const names = new Map(read(`locale_${locale}.json`).files['avatar_meta.json'].map(row => [row.id, row.name]));
  return raw.filter(row => row.id !== 10000005 && row.id !== 10000007).map(row => ({ ...row,
    canonicalName: row.name, name: names.get(row.id) || row.name,
    association: row.association ?? associations[String(row.id)] ?? 0 }));
}

test('adding tokens enforces the shared five-token limit and deduplicates stable keys', () => {
  assert.equal(Filter.LIMIT, CultivationFilterToken.LIMIT);
  assert.equal(Filter.LIMIT, 5);
  const selected = [token(Kind.Text, ' ALPHA ', 'ALPHA')];
  assert.deepEqual(Filter.add(selected, token(Kind.Text, 'alpha')), selected);
  const english = token(Kind.Quality, '5', '5 Stars');
  const japanese = token(Kind.Quality, '5', '星5');
  assert.deepEqual(Filter.add([english], japanese), [english]);
  let current = selected;
  for (const entry of [english, token(Kind.Weapon, '1'), token(Kind.Element, '火'), token(Kind.Body, '1'), token(Kind.Avatar, '1')]) {
    current = Filter.add(current, entry);
  }
  assert.equal(current.length, 5);
  assert.equal(selected.length, 1, 'The caller owns its original array');
  assert.deepEqual(Filter.add(current, token(Kind.Text, '  ')), current);
  assert.equal(Filter.add(current.concat(token(Kind.Text, 'sixth')), english).length, 5);
  assert.deepEqual(Filter.suggestions(Filter.catalog(mixed, 'en'), current, ''), []);
});

test('catalog and suggestions use Windows category and enum order while retaining roster order', () => {
  const catalog = Filter.catalog([mixed[3], mixed[0]], 'en');
  const suggestions = Filter.suggestions(catalog, [], '');
  assert.deepEqual(suggestions.map(entry => entry.kind), catalog.map(entry => entry.kind));
  assert.deepEqual(suggestions.filter(entry => entry.kind === Kind.Quality).map(entry => entry.value), ['4', '5', '105']);
  assert.deepEqual(suggestions.filter(entry => entry.kind === Kind.Weapon).map(entry => entry.value), ['1', '10', '11', '12', '13']);
  assert.deepEqual(suggestions.filter(entry => entry.kind === Kind.Element).map(entry => entry.value), ['火', '水', '草', '雷', '风', '冰', '岩']);
  assert.deepEqual(suggestions.filter(entry => entry.kind === Kind.Body).map(entry => entry.value), ['1', '2', '3', '4', '5']);
  assert.deepEqual(suggestions.filter(entry => entry.kind === Kind.Avatar).map(entry => entry.value), ['4', '1']);
  assert.ok(suggestions.every((entry, index) => index === 0 || suggestions[index - 1].kind <= entry.kind));
  assert.equal(new Set(catalog.map(entry => entry.key())).size, catalog.length);
  const selected = [choice(catalog, Kind.Quality, '5')];
  assert.ok(!Filter.suggestions(catalog, selected, '').some(entry => entry.key() === selected[0].key()));
  assert.equal(catalog.length, suggestions.length, 'Suggestion filtering must keep the catalog intact');
});

test('exact entry resolves localized or canonical names, and partial text keeps name-only substring semantics', () => {
  const catalog = Filter.catalog(mixed, 'en');
  assert.equal(Filter.fromText(catalog, '   '), undefined);
  assert.equal(Filter.fromText(catalog, '  ALPHA ').key(), choice(catalog, Kind.Avatar, '1').key());
  assert.equal(Filter.fromText(catalog, '甲').key(), choice(catalog, Kind.Avatar, '1').key());
  assert.equal(Filter.fromText(catalog, '四星').key(), choice(catalog, Kind.Quality, '4').key());
  const partial = Filter.fromText(catalog, '  aLp  ');
  assert.equal(partial.kind, Kind.Text);
  assert.equal(partial.value, 'aLp');
  assert.equal(partial.label, 'aLp');
  assert.deepEqual(ids(Filter.filter(mixed, [partial])), [1]);
  assert.deepEqual(ids(Filter.filter(mixed, [token(Kind.Text, 'Name only')])), []);
  assert.deepEqual(ids(Filter.filter(mixed, [token(Kind.Text, '甲'), token(Kind.Text, 'EPS')])), [1, 5]);
});

test('same-category conditions OR together and different categories AND together', () => {
  const quality = [token(Kind.Quality, '4'), token(Kind.Quality, '5')];
  assert.deepEqual(ids(Filter.filter(mixed, quality)), [1, 2, 4, 5]);
  const sword = quality.concat(token(Kind.Weapon, '1'));
  assert.deepEqual(ids(Filter.filter(mixed, sword)), [1, 4]);
  assert.deepEqual(ids(Filter.filter(mixed, sword.concat(token(Kind.Element, '火')))), [1]);
  assert.deepEqual(ids(Filter.filter(mixed, sword.concat(token(Kind.Element, '火'), token(Kind.Element, '雷')))), [1, 4]);
  assert.deepEqual(ids(Filter.filter(mixed, [token(Kind.Quality, '105')])), [3], '105 is distinct from ordinary five-star');
  assert.deepEqual(ids(Filter.filter(mixed, [token(Kind.Body, '2'), token(Kind.Association, '15')])), [2, 4]);
  assert.deepEqual(ids(Filter.filter(mixed, [token(Kind.Avatar, '1'), token(Kind.Avatar, '2'), token(Kind.Element, '水')])), [2]);
  assert.deepEqual(Filter.filter(mixed, []), mixed);
  assert.deepEqual(ids(Filter.filter(mixed, [token(Kind.Weapon, '999')])), []);
});

test('same localized avatar name never replaces exact numeric avatar identity', () => {
  const travelers = [makeAvatar(10000005, 'Traveler', 5, 1, '风', 0, 1, '旅行者'),
    makeAvatar(10000007, 'Traveler', 5, 1, '风', 0, 2, '旅行者')];
  const catalog = Filter.catalog(travelers.concat(travelers[0]), 'en');
  const names = catalog.filter(entry => entry.kind === Kind.Avatar);
  assert.equal(names.length, 2);
  assert.notEqual(names[0].key(), names[1].key());
  assert.deepEqual(ids(Filter.filter(travelers, [names[1]])), [10000007]);
  assert.deepEqual(ids(Filter.filter(travelers, [token(Kind.Text, 'Traveler')])), [10000005, 10000007]);
});

test('shared Fatui labels cover both 4 and 15, while Thai choices preserve their separate scopes', () => {
  const english = Filter.catalog(mixed, 'en');
  const shared = choice(english, Kind.Association, '4,15');
  assert.equal(shared.label, 'Fatui');
  assert.equal(Filter.fromText(english, '愚人众').key(), shared.key());
  assert.deepEqual(ids(Filter.filter(mixed, [shared])), [1, 2, 4]);
  const thai = Filter.catalog(mixed, 'th');
  const originalFatui = choice(thai, Kind.Association, '4');
  const newFatui = choice(thai, Kind.Association, '15');
  assert.equal(originalFatui.label, 'Fatui');
  assert.equal(newFatui.label, '愚人众', 'Retain the actual Windows Thai resource');
  assert.deepEqual(ids(Filter.filter(mixed, [originalFatui])), [1]);
  assert.deepEqual(ids(Filter.filter(mixed, [newFatui])), [2, 4]);
  assert.ok(!Filter.suggestions(thai, [shared], '').some(entry => entry.kind === Kind.Association && ['4', '15'].includes(entry.value)));
  assert.deepEqual(Filter.add([shared], originalFatui), [shared]);
  assert.deepEqual(Filter.add([originalFatui, newFatui], shared), [originalFatui, newFatui]);
});

test('language changes relabel chips and preserve selected numeric scope and literal text', () => {
  const english = Filter.catalog(mixed, 'en');
  const japanese = Filter.catalog(mixed.map(row => ({ ...row, name: `日本語${row.id}` })), 'ja');
  const literal = token(Kind.Text, 'AlP');
  const selected = [choice(english, Kind.Quality, '5'), choice(english, Kind.Avatar, '1'), literal];
  const relabeled = Filter.relabel(japanese, selected);
  assert.deepEqual(relabeled.map(entry => entry.key()), selected.map(entry => entry.key()));
  assert.equal(relabeled[0].label, '星5');
  assert.equal(relabeled[1].label, '日本語1');
  assert.equal(relabeled[2], literal);
  const thai = Filter.catalog(mixed, 'th');
  const shared = choice(english, Kind.Association, '4,15');
  const expanded = Filter.relabel(thai, [shared]);
  assert.equal(expanded[0].value, '4,15');
  assert.equal(expanded[0].label, 'Fatui / 愚人众');
  assert.deepEqual(ids(Filter.filter(mixed, expanded)), [1, 2, 4]);
  const narrow = Filter.relabel(english, [choice(thai, Kind.Association, '15')]);
  assert.equal(narrow[0].value, '15');
  assert.equal(narrow[0].label, 'Fatui');
  assert.deepEqual(ids(Filter.filter(mixed, narrow)), [2, 4]);
  const unknown = token(Kind.Avatar, '99999999', 'Removed metadata entry');
  assert.equal(Filter.relabel(english, [unknown])[0], unknown);
});

test('real 122-avatar roster supports mixed filters, canonical suggestions and names across languages', () => {
  const avatars = roster('en');
  assert.equal(avatars.length, 122);
  const catalog = Filter.catalog(avatars, 'en');
  const huTao = Filter.fromText(catalog, '胡桃');
  assert.equal(huTao.kind, Kind.Avatar);
  assert.equal(huTao.value, '10000046');
  assert.equal(huTao.label, 'Hu Tao');
  assert.equal(Filter.suggestions(catalog, [], '胡桃')[0].key(), huTao.key());
  assert.deepEqual(ids(Filter.filter(avatars, [huTao, Filter.fromText(catalog, '火'), Filter.fromText(catalog, 'Polearm')])), [10000046]);
  assert.deepEqual(ids(Filter.filter(avatars, [Filter.fromText(catalog, '雪霁梅香')])), [], 'Character title is outside free-text names');
  const selected = [choice(catalog, Kind.Quality, '4'), choice(catalog, Kind.Quality, '5'),
    choice(catalog, Kind.Association, '4,15'), choice(catalog, Kind.Element, '雷')];
  const expected = avatars.filter(row => [4, 5].includes(row.quality) && [4, 15].includes(row.association) && row.vision === '雷');
  assert.ok(expected.length > 0);
  assert.deepEqual(ids(Filter.filter(avatars, selected)), ids(expected));
  const japanese = roster('ja');
  assert.deepEqual(ids(Filter.filter(japanese, Filter.relabel(Filter.catalog(japanese, 'ja'), selected))), ids(expected));
});

function sourceLabels(locale) {
  return new Map(labels.keys.map((key, index) => [key, labels.locales[locale][index]]));
}

test('bundled Windows source snapshot pins the 37 filter and guide labels for all fifteen languages', () => {
  assert.equal(labels.source, 'SnapHutaoRemasteringProject/Snap.Hutao.Remastered');
  assert.equal(labels.revision, '3b7475ed3eca4aedf9cb81d94741bfbe6fa189f5');
  assert.equal(labels.keys.length, 37);
  assert.equal(new Set(labels.keys).size, 37);
  assert.deepEqual(Object.keys(labels.locales).sort(), LocalePolicy.locales().sort());
  for (const values of Object.values(labels.locales)) {
    assert.equal(values.length, labels.keys.length);
    assert.ok(values.every(value => typeof value === 'string' && value.trim().length > 0));
  }
  assert.equal(sourceLabels('zh-Hans').get('ViewPageWiKiAvatarStrategyChineseButtonLabel'), '米游社角色攻略');
  assert.equal(sourceLabels('en').get('ViewPageWiKiAvatarStrategyBilibiliButtonLabel'), 'Bilibili Game Wiki Character Guide');
  assert.equal(sourceLabels('ja').get('ViewPageWiKiAvatarStrategyOverseaButtonLabel'), 'HoYoLAB キャラクター攻略');
  assert.equal(sourceLabels('en').get('ViewModelWikiAvatarStrategyNotFound'), 'No character guides found');
});

test('all fifteen enum vocabularies match the pinned source snapshot including locale fallback', () => {
  const groups = [
    [Kind.Quality, [['4', 'ItemQualityPurple'], ['5', 'ItemQualityOrange'], ['105', 'ItemQualityRed']]],
    [Kind.Weapon, [['1', 'WeaponTypeSwordOneHand'], ['10', 'WeaponTypeCatalyst'], ['11', 'WeaponTypeClaymore'], ['12', 'WeaponTypeBow'], ['13', 'WeaponTypePole']]],
    [Kind.Element, [['火', 'ElementNameFire'], ['水', 'ElementNameWater'], ['草', 'ElementNameGrass'], ['雷', 'ElementNameElec'], ['风', 'ElementNameWind'], ['冰', 'ElementNameIce'], ['岩', 'ElementNameRock']]],
    [Kind.Association, [['1', 'AssociationTypeMondstadt'], ['2', 'AssociationTypeLiyue'], ['4', 'AssociationTypeFatui'], ['5', 'AssociationTypeInazuma'],
      ['6', 'AssociationTypeRanger'], ['7', 'AssociationTypeSumeru'], ['8', 'AssociationTypeFontaine'], ['9', 'AssociationTypeNatlan'],
      ['10', 'AssociationTypeSnezhnaya'], ['11', 'AssociationTypeOmniScourge'], ['12', 'AssociationTypeNodkrai'], ['14', 'AssociationTypeHVision'], ['15', 'AssociationTypeSnezhnayaStar']]],
    [Kind.Body, [['1', 'BodyTypeBoy'], ['2', 'BodyTypeGirl'], ['3', 'BodyTypeLady'], ['4', 'BodyTypeMale'], ['5', 'BodyTypeLoli']]],
  ];
  const chinese = sourceLabels('zh-Hans');
  for (const locale of LocalePolicy.locales()) {
    const resource = sourceLabels(locale);
    const catalog = Filter.catalog([], locale);
    for (const [kind, labels] of groups) {
      for (const [value, suffix] of labels) {
        const key = 'ModelIntrinsic' + suffix;
        const selected = catalog.find(entry => entry.kind === kind && entry.value.split(',').includes(value));
        assert.ok(selected, `${locale} ${key}`);
        assert.equal(selected.label, resource.get(key) || chinese.get(key), `${locale} ${key}`);
      }
    }
    assert.equal(new Set(catalog.map(entry => entry.key())).size, catalog.length, locale);
  }
  assert.deepEqual(Filter.catalog([], 'en-US'), Filter.catalog([], 'en'));
  assert.deepEqual(Filter.catalog([], 'unsupported'), Filter.catalog([], 'en'));
  assert.deepEqual(Filter.catalog([], 'zh_TW'), Filter.catalog([], 'zh-Hant'));
});

test('both Wiki generators reproduce their output from the files shipped with the app repository', () => {
  const candidates = [process.env.PYTHON, 'python3', 'python', path.join(os.homedir(),
    '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')].filter(Boolean);
  let python;
  for (const candidate of candidates) {
    const result = spawnSync(candidate, ['-c', 'import sys; print(sys.executable)'], { encoding: 'utf8' });
    if (result.status === 0) { python = result.stdout.trim(); break; }
  }
  assert.ok(python, 'Python 3 is required for the offline generator check');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hutao-wiki-avatar-'));
  try {
    const generators = ['scripts/generate-wiki-avatar-filter-labels.py', 'scripts/generate-avatar-guide-reference.py'];
    const inputs = ['scripts/data/wiki-avatar-labels.json', 'scripts/data/wiki-avatar-guides.json',
      'entry/src/main/resources/rawfile/metadata/avatar_meta.json', 'entry/src/main/resources/rawfile/metadata/locale_en.json'];
    const outputs = ['entry/src/main/ets/service/WikiAvatarFilterVocabulary.ets', 'entry/src/main/ets/model/AvatarGuideReference.ets'];
    for (const filename of [...generators, ...inputs, ...outputs]) {
      const target = path.join(directory, filename);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.copyFileSync(path.join(root, filename), target);
    }
    const environment = { ...process.env };
    for (const name of Object.keys(environment)) {
      if (name.toLowerCase() === 'path') delete environment[name];
    }
    environment.PATH = '';
    for (const generator of generators) {
      const result = spawnSync(python, [generator, '--check'], { cwd: directory, env: environment, encoding: 'utf8' });
      assert.equal(result.status, 0, `${generator}\n${result.stdout}${result.stderr}`);
    }
  } finally {
    assert.equal(path.dirname(directory), path.resolve(os.tmpdir()));
    assert.ok(path.basename(directory).startsWith('hutao-wiki-avatar-'));
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
