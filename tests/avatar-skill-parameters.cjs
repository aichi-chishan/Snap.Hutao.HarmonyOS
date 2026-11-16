// Production query and parser with only the locale, logging and metadata-reader boundaries stubbed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const source = path.resolve(__dirname, '../entry/src/main/ets');
const metadata = path.resolve(__dirname, '../entry/src/main/resources/rawfile/metadata');
const locales = ['zh-Hans', 'zh-Hant', 'en', 'de', 'es', 'fr', 'id', 'it', 'ja', 'ko', 'pt', 'ru', 'th', 'tr', 'vi'];

function harness(beforeRead) {
  let locale = 'zh-Hans';
  const reads = [];
  const modules = new Map();
  const boundaries = {
    'common/Logger': { Logger: { warn() {} } },
    'service/AppLocaleService': { AppLocaleService: { current: () => locale } },
    'service/GameDataService': { GameDataService: { async readMetadataFile(name) {
      reads.push(name);
      if (beforeRead) await beforeRead(name);
      return fs.readFileSync(path.join(metadata, name), 'utf8');
    } } },
  };
  function load(name) {
    if (boundaries[name]) return boundaries[name];
    if (modules.has(name)) return modules.get(name);
    const filename = path.join(source, name + '.ets');
    const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { reportDiagnostics: true,
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } });
    assert.equal(result.diagnostics.length, 0, name);
    const mod = { exports: {} };
    vm.runInThisContext(`(function(require,module,exports){${result.outputText}\n})`, { filename })(
      specifier => load(path.posix.normalize(path.posix.join(path.posix.dirname(name), specifier))), mod, mod.exports);
    modules.set(name, mod.exports);
    return mod.exports;
  }
  return { reads, setLocale: value => { locale = value; },
    model: load('model/AvatarWikiSkill'), service: load('service/AvatarSkillParameterService').AvatarSkillParameterService };
}

test('all 15 shipped languages preserve ordered skill identities and actual level ranges', () => {
  const { model: { AvatarWikiSkillCatalog: catalog } } = harness();
  let expected;
  for (const locale of locales) {
    const rows = catalog.parse(fs.readFileSync(path.join(metadata, catalog.fileName(locale)), 'utf8'), locale);
    assert.equal(Object.keys(rows).length, 122);
    const ids = Object.entries(rows).map(([id, skills]) => [id, skills.map(skill => [skill.id, skill.kind, skill.levels])]);
    assert.equal(Object.values(rows).flat().length, 783);
    if (expected === undefined) expected = ids;
    assert.deepEqual(ids, expected, locale);
  }
});

test('in-flight skill reads share the captured locale without replacing a newer locale cache', async () => {
  let entered;
  let release;
  const started = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  let blockEnglish = true;
  const h = harness(async name => {
    if (name === 'avatar_skill_en.json' && blockEnglish) {
      blockEnglish = false;
      entered();
      await gate;
    }
  });
  h.setLocale('en');
  const first = h.service.forAvatar(10000002);
  const duplicate = h.service.forAvatar(10000002);
  await started;
  assert.deepEqual(h.reads, ['avatar_skill_en.json']);
  let japanese;
  try {
    h.setLocale('ja');
    japanese = await h.service.forAvatar(10000002);
    assert.equal(japanese[0].name, '神里流・傾き');
  } finally {
    release();
  }
  const [english, shared] = await Promise.all([first, duplicate]);
  assert.equal(english[0].name, 'Kamisato Art: Kabuki');
  assert.equal(english, shared);
  assert.equal(await h.service.forAvatar(10000002), japanese);
  assert.deepEqual(h.reads, ['avatar_skill_en.json', 'avatar_skill_ja.json']);
  h.setLocale('en');
  assert.equal((await h.service.forAvatar(10000002))[0].name, 'Kamisato Art: Kabuki');
  assert.deepEqual(h.reads, ['avatar_skill_en.json', 'avatar_skill_ja.json', 'avatar_skill_en.json']);
});

test('Mitya defaults to level 10 and matches the Windows screenshot and pinned source values', async () => {
  const { service, reads } = harness();
  const [skills, ayaka] = await Promise.all([service.forAvatar(10000136), service.forAvatar(10000002)]);
  assert.deepEqual(reads, ['avatar_skill_zh-Hans.json']);
  assert.deepEqual(skills.map(skill => skill.name), ['链式反应', '律定·变量侦测', '解析·递变之理',
    '基准承压测验', '超限易爆试剂', '星耀祝礼·极密协议', '能源活性催化']);
  const normal = skills[0];
  assert.equal(normal.defaultLevel, 10);
  assert.deepEqual(normal.levels, Array.from({ length: 15 }, (_, index) => index + 1));
  for (const [level, expected] of [[1, '58.8%'], [10, '105.8%'], [15, '139.6%']]) {
    assert.equal(service.rows(normal, level)[0].label, '一段伤害');
    assert.equal(service.rows(normal, level)[0].value, expected);
  }
  assert.deepEqual(service.rows(normal, 16), []);
  assert.equal(ayaka[2].name, '神里流·霰步');
  assert.deepEqual(ayaka[2].levels, [1]);
  assert.equal(service.rows(ayaka[2], 1)[1].value, '每秒15.0点');
  assert.equal(ayaka[4].name, '天罪国罪镇词');
  assert.deepEqual(ayaka[4].levels, []);
  assert.deepEqual(service.rows(ayaka[4], 1), []);
  assert.deepEqual(await service.forAvatar(10000005), []);
});

test('special skills retain their source order and only special-exclusive rows are marked', async () => {
  const { service, model: { AvatarWikiSkillKind: kind } } = harness();
  const venti = await service.forAvatar(10000022);
  assert.deepEqual(venti.map(skill => skill.kind), [kind.Skill, kind.Skill, kind.Energy,
    kind.Special, kind.Inherent, kind.Inherent, kind.Inherent]);
  assert.equal(venti[3].name, '魔女的前夜礼·颂时风若');
  assert.deepEqual(venti[3].levels, []);
  assert.ok(venti[0].specialDescription.length > 0);
  const rows = service.rows(venti[0], 10);
  assert.equal(rows[0].value, '40.3%+40.3%');
  assert.equal(rows[0].isSpecial, false);
  assert.deepEqual(rows.filter(row => row.isSpecial).map(row => [row.label, row.value]),
    [['飓风箭伤害', '250.0%普通攻击伤害']]);
});

test('the current locale selects original labels, percent placement, decimal separators and literal units', async () => {
  const { service, setLocale, reads } = harness();
  for (const [locale, name, healing] of [
    ['en', 'Kamisato Art: Kabuki', '19.01% ATK+148'],
    ['fr', 'École Kamisato : Sveltesse', '19,01 % ATQ + 148 PV'],
    ['ja', '神里流・傾き', '攻撃力19.01%+148'],
    ['tr', 'Kamisato Sanatı: Kabuki', '%19,01 Saldırı+148'],
    ['de', 'Kamisato-Stil – Naname', '19,01 % ANG + 148'],
  ]) {
    setLocale(locale);
    const ayaka = await service.forAvatar(10000002);
    assert.equal(ayaka[0].name, name);
    const qiqi = await service.forAvatar(10000035);
    assert.equal(service.rows(qiqi[1], 10)[1].value, healing);
    if (locale === 'de') assert.equal(service.rows(ayaka[2], 1)[1].value, '15,0 Punkte pro\u00a0s');
  }
  assert.deepEqual(reads, ['en', 'fr', 'ja', 'tr', 'de'].map(locale => `avatar_skill_${locale}.json`));
});
