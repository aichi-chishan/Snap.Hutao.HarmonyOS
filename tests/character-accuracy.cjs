// Production ArkTS resolver, parser, exporter and calculator with mocked network/OS only.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const fixtures = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/character-skill-reference.json'), 'utf8'));
const preferences = new Map();
const fixtureUser = { hasCookie: () => true, roles: [{ gameUid:'100000049', region:'cn_gf01' }] };
const wiki = {
  iconOfAvatar: () => '', cleanText: value => value, nameOfWeapon: id => `weapon ${id}`,
  avatarOf: id => id === 10000062 ? { quality: 105 } : undefined,
  weaponOf: id => id === 15501 ? { weaponType: 12 } : undefined,
  getWeapons: async () => [{ id: 11501, rankLevel: 5 }, { id: 11101, rankLevel: 1 }],
};
const mocks = {
  ApiClient: {}, ApiResponse: class {}, HoyolabClient: {}, DsSigner: {},
  RiskVerifier: {}, RiskControlError: class extends Error {},
  UserService: { getInstance: () => ({ getCurrentUser: () => fixtureUser, sessionRevision: () => 1 }) },
  Constants: { RegionUtil: { regionOfUid: () => 'cn_gf01' }, AppConstants: {} },
  HoyolabEndpoints: { gameRecordUrl: path => path }, Logger: { info() {}, warn() {} },
  PreferencesStore: { getString: (key, value) => preferences.get(key) ?? value,
    setString: (key, value) => preferences.set(key, value) },
  WikiMetaService: wiki, RiskUiHelper: {},
};
const cache = new Map();
function load(relative) {
  const file = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (cache.has(file)) return cache.get(file).exports;
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8').replace(/^@Observed\s*$/gm, ''), {
    fileName: file.replace(/\.ets$/, '.ts'), compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
    }, reportDiagnostics: true,
  });
  assert.equal(compiled.diagnostics.length, 0, file);
  const module = { exports: {} }; cache.set(file, module);
  const requireLocal = name => {
    const key = path.basename(name);
    if (key === 'Constants') return mocks.Constants;
    if (key === 'RiskVerifier') return { RiskVerifier: mocks.RiskVerifier, RiskControlError: mocks.RiskControlError };
    if (mocks[key]) return { [key]: mocks[key] };
    return load(path.resolve(path.dirname(file), name));
  };
  vm.runInThisContext('(function(require,module,exports){' + compiled.outputText + '\n})', { filename: file })(requireLocal, module, module.exports);
  return module.exports;
}
const { CharacterService } = load('service/CharacterService');
const { SkillLevelService: skills } = load('service/SkillLevelService');
const { AvatarSkillCatalog } = load('model/AvatarSkillReference');
const { PromoteState } = load('model/PromoteState');
const { CharacterExportService } = load('service/CharacterExportService');
const { ReliquaryScore } = load('common/ReliquaryScore');
const { CharacterListItem } = load('model/CharacterData');
const { CharacterViewModel, CharacterSortKind } = load('viewmodel/CharacterViewModel');
const { CharacterFilterKind, CharacterFilterToken } = load('viewmodel/CharacterFilter');
const { CalculateService, CalAvatarDelta } = load('service/CalculateService');
const service = CharacterService.getInstance();
const parse = raw => service.parseDetail(raw);
const reference = id => fixtures.avatars.find(avatar => avatar.id === id);
function character(id, count, levels) {
  const ref = reference(id);
  return parse({ base: { id, name: ref.name, level: 80, actived_constellation_num: count },
    skills: ref.skills.map((skill, index) => ({ skill_id: skill.id, skill_type: 1, level: levels[index] })),
    constellations: ref.talents.map((talent, index) => ({ id: talent.id, is_actived: index < count })),
    weapon: { id: 11501, level: 80, rarity: 5, affix_level: 1, promote_level: 6 },
  });
}

test('pinned catalog preserves all 118 source identities, group IDs and constellation rules', () => {
  assert.equal(fixtures.commit, 'b3aef3dbe0299e512654bb296930b3b6571fc87f');
  assert.equal(AvatarSkillCatalog.profiles.length, 118);
  for (const ref of fixtures.avatars) {
    assert.match(ref.sha, /^[a-f0-9]{40}$/);
    const profile = AvatarSkillCatalog.profiles.find(value => value.avatarId === ref.id);
    assert.deepEqual(profile.skills.map(value => [value.skillId, value.groupId, value.kind]),
      ref.skills.map(value => [value.id, value.group, value.kind]));
    assert.deepEqual(profile.constellations.map(value => [value.id, value.extraLevel]),
      ref.talents.map(value => [value.id, value.level]));
    assert.equal(profile.normalAttackExtra, ref.bonus);
  }
});
test('reordered combat skills and extra sprint do not change identity or base/extra split', () => {
  const detail = character(10000002, 3, [6, 9, 11]);
  detail.skills = [detail.skills[2], { skillId: 10013, level: 1, skillType: 1 }, detail.skills[0], detail.skills[1]];
  detail.constellations.reverse();
  assert.deepEqual(skills.resolve(detail).map(value => [value.skillId, value.baseLevel, value.extraLevel, value.displayLevel]),
    [[10024, 6, 0, 6], [10018, 9, 0, 9], [10019, 8, 3, 11]]);
  assert.equal(skills.forMetaSkill(detail, { n: '神里流·霜灭', i: 'Skill_E_Ayaka', k: 'Q' }).skillId, 10019);
  const translated = { n: 'Kamisato Art: Soumetsu', canonicalName: '神里流·霜灭', i: 'Skill_E_Ayaka', k: 'Q' };
  assert.equal(skills.forMetaSkill(detail, translated).skillId, 10019);
  assert.equal(skills.kindOfMetaSkill(detail, translated), 'Q');
  assert.equal(skills.forMetaSkill(detail, { ...translated, canonicalName: 'unrelated' }), undefined);
  assert.equal(skills.forMetaSkill(detail, { n: 'unrelated', i: 'Skill_E_Ayaka', k: 'Q' }), undefined);
});
test('old compact jump ordering cannot shift Ororon/Citlali A/E identity', () => {
  const metadata = JSON.parse(fs.readFileSync(path.join(root, '../resources/rawfile/metadata/avatar_meta.json'), 'utf8'));
  for (const id of [10000105, 10000107]) {
    const detail = character(id, 0, [6, 9, 8]);
    const rows = metadata.find(avatar => avatar.id === id).skills;
    assert.equal(skills.kindOfMetaSkill(detail, rows[0]), 'X');
    assert.equal(skills.forMetaSkill(detail, rows[0]), undefined);
    assert.equal(skills.kindOfMetaSkill(detail, rows[1]), 'A');
    assert.equal(skills.forMetaSkill(detail, rows[1]).baseLevel, 6);
    assert.equal(skills.kindOfMetaSkill(detail, rows[2]), 'E');
    assert.equal(skills.forMetaSkill(detail, rows[2]).baseLevel, 9);
  }
});
test('C3/C5 normal-attack, skill, burst variants and Tartaglia passive follow metadata', () => {
  for (const [id, count, levels, expected] of [
    [10000002, 5, [6, 12, 11], [0, 3, 3]],
    [10000033, 3, [7, 12, 8], [1, 3, 0]],
    [10000033, 5, [7, 12, 11], [1, 3, 3]],
    [10000087, 3, [9, 9, 8], [3, 0, 0]],
    [10000087, 5, [9, 9, 11], [3, 0, 3]],
    [10000084, 5, [9, 9, 11], [3, 0, 3]],
  ]) {
    const result = skills.resolve(character(id, count, levels));
    assert.deepEqual(result.map(value => value.extraLevel), expected);
    assert.deepEqual(result.map(value => value.baseLevel), [6, 9, 8]);
  }
});
test('unknown IDs, traveler variants, duplicate talents and conflicting activation stay unknown', () => {
  for (const id of [10000005, 10000007, 19999999]) {
    assert.deepEqual(skills.referenceSkills(id), []);
    assert.deepEqual(skills.resolve(parse({ base: { id, skill_depot_id: 504 }, skills: [{ skill_id: 1, level: 9 }] })), []);
  }
  assert.deepEqual(skills.referenceSkills(10000002, 999), []);
  assert.deepEqual(skills.resolve(parse({ base: { id: 10000002, skill_depot_id: 'invalid' } })), []);
  assert.equal(skills.resolve(parse({ base: { id: 10000002 }, skills: [{ skill_id: 10024, level: true }] }))[0].displayLevel, -1);
  const detail = character(10000002, 3, [6, 9, 11]);
  detail.skills.push(detail.skills[0]);
  assert.equal(skills.resolve(detail)[0].displayLevel, -1);
  detail.constellations[2].isActived = false;
  assert.equal(skills.resolve(detail)[2].baseLevel, -1);
  detail.constellations[2].id = 999;
  assert.equal(skills.resolve(detail)[2].extraLevel, -1);
  const unknown = parse({ base: { id: 10000002 }, skills: [{ skill_id: 10019, level: 11 }] });
  assert.equal(skills.resolve(unknown)[2].displayLevel, 11);
  assert.equal(skills.resolve(unknown)[2].baseLevel, -1);
  assert.match(skills.formatSkill(skills.resolve(unknown)[2]), /基础\/加成未知/);
});
test('weapon ascension parsing preserves absence, strict boundaries and low-rarity caps', () => {
  for (const raw of [undefined, null, '', ' ', false, -1, 7, 'NaN', 1.5]) assert.equal(PromoteState.parse(raw), -1);
  for (const [level, promotes] of [[20, [0, 1]], [40, [1, 2]], [50, [2, 3]], [60, [3, 4]], [70, [4, 5]], [80, [5, 6]], [90, [6]]]) {
    for (const promote of promotes) assert.equal(parse({ base: { id: 1 }, weapon: { id: 1, level, rarity: 5, promote_level: promote } }).weapon.promoteLevel, promote);
    assert.equal(parse({ base: { id: 1 }, weapon: { id: 1, level, rarity: 5 } }).weapon.promoteLevel, -1);
  }
  assert.equal(PromoteState.validWeapon(70, 4, 1), true);
  assert.equal(PromoteState.validWeapon(70, 5, 1), false);
  assert.equal(PromoteState.validWeapon(81, 5, 5), false);
  assert.equal(PromoteState.validWeapon(1, 1, 5), false);
  assert.equal(parse({ base: { id: 1 } }).weapon.equipmentState, 'unknown');
  assert.equal(parse({ base: { id: 1 }, weapon: null }).weapon.equipmentState, 'unequipped');
});
test('text export labels base plus bonus, exact promotion and unknown equipment without inventing stats', () => {
  const detail = character(10000002, 3, [6, 9, 11]);
  let text = CharacterExportService.buildExportText(detail, type => type);
  assert.match(text, /A Lv\.6, E Lv\.9, Q Lv\.8\+3/);
  assert.match(text, /突破6/);
  assert.doesNotMatch(text, /Lv\.14/);
  detail.weapon.promoteLevel = -1;
  assert.match(CharacterExportService.buildExportText(detail, type => type), /突破未知/);
  text = CharacterExportService.buildExportText(parse({ base: { id: 10000005 }, weapon: null }), type => type);
  assert.match(text, /C\?/); assert.match(text, /天赋映射未知/); assert.match(text, /武器：未装备/);
  assert.match(CharacterExportService.buildExportText(parse({ base: { id: 10000005 } }), type => type), /装备信息未知/);
});
test('character scoring sums unrounded relics and the export uses the selected weights', () => {
  const sub_property_list = [{ property_type: 28, value: '1' }, { property_type: 20, value: '3.1%' }];
  const detail = parse({ base: { id: 10000002 }, relics: [{ id: 1, sub_property_list }, { id: 2, sub_property_list }] });
  const weights = [0, 0, 0, 0, .2, 0, 0];
  assert.equal(ReliquaryScore.totalForCharacter(detail, weights).toFixed(1), '0.1');
  assert.match(CharacterExportService.buildExportText(detail, type => type, weights), /评分: 0\.1 分/);
  assert.match(CharacterExportService.buildExportText(detail, type => type), /评分: 6\.2 分/);
});
test('recommended scoring reads the special energy of Mavuika and Skirk', () => {
  const relics = [{ sub_property_list: [{ property_type: 'FIGHT_PROP_CHARGE_EFFICIENCY', value: '5.2%' }] }];
  for (const id of [10000106, 10000114]) {
    const detail = parse({ base: { id }, relics });
    assert.equal(ReliquaryScore.totalForCharacter(detail), 0);
  }
  const detail = parse({ base: { id: 10000002 }, relics });
  assert.ok(ReliquaryScore.totalForCharacter(detail) > 0);
});
test('detail fetch and cache retain all recommendation slots, relic set ID and raw roll counts', async () => {
  const uid = '100000049';
  const id = 10000049;
  const raw = {
    base: { id, name: '宵宫' },
    recommend_relic_property: {
      recommend_properties: {
        sand_main_property_list: [6, 'FIGHT_PROP_ELEMENT_MASTERY'],
        goblet_main_property_list: [40],
        circlet_main_property_list: ['FIGHT_PROP_CRITICAL_HURT'],
        sub_property_list: [20, 'FIGHT_PROP_CRITICAL_HURT', 6],
      },
      special_energy_type: 'NONE',
    },
    relics: [{
      id: 88543, pos: 1, set: { id: '15019', name: '追忆之注连' },
      sub_property_list: [
        { property_type: 20, value: '11.7%', times: 2 },
        { property_type: 5, value: '19', times: 0 },
      ],
    }],
  };
  const fixturesService = new CharacterService();
  fixturesService.postJson = async () => ({ success: true, retcode: 0, data: { list: [raw] } });
  const [fresh] = await fixturesService.fetchDetail(uid, [id]);
  const [cached] = new CharacterService().getCachedDetails(uid);
  for (const detail of [fresh, cached]) {
    assert.deepEqual(detail.recommend.sandMainProperties, ['6', 'FIGHT_PROP_ELEMENT_MASTERY']);
    assert.deepEqual(detail.recommend.gobletMainProperties, ['40']);
    assert.deepEqual(detail.recommend.circletMainProperties, ['FIGHT_PROP_CRITICAL_HURT']);
    assert.deepEqual(detail.recommend.subProperties, ['20', 'FIGHT_PROP_CRITICAL_HURT', '6']);
    assert.equal(detail.recommend.energyType, 'NONE');
    assert.equal(detail.reliquaries[0].setId, 15019);
    assert.equal(detail.reliquaries[0].setName, '追忆之注连');
    assert.deepEqual(detail.reliquaries[0].subProperties.map(property => property.times), [2, 0]);
  }
  preferences.set('character.details.100000048', JSON.stringify([{
    base: { id: 10000048 }, relics: [{ id: 88543, set: { name: '追忆之注连' } }],
  }]));
  const [legacy] = fixturesService.getCachedDetails('100000048');
  assert.deepEqual(legacy.recommend.sandMainProperties, []);
  assert.deepEqual(legacy.recommend.gobletMainProperties, []);
  assert.deepEqual(legacy.recommend.circletMainProperties, []);
  assert.equal(legacy.reliquaries[0].setId, 0);
  assert.equal(legacy.reliquaries[0].setName, '追忆之注连');
});
test('character tokens parse only Windows presets, suggest in Windows order and exclude committed selections', () => {
  const all = CharacterFilterToken.suggestions('', []);
  assert.equal(CharacterFilterToken.LIMIT, 5);
  assert.deepEqual(all.map(token => [token.kind, token.value, token.label]), [
    [CharacterFilterKind.Quality, '4', '四星'], [CharacterFilterKind.Quality, '5', '五星'],
    [CharacterFilterKind.Quality, '105', '限定五星'],
    [CharacterFilterKind.Weapon, '1', '单手剑'], [CharacterFilterKind.Weapon, '10', '法器'],
    [CharacterFilterKind.Weapon, '11', '双手剑'], [CharacterFilterKind.Weapon, '12', '弓'],
    [CharacterFilterKind.Weapon, '13', '长柄武器'],
    [CharacterFilterKind.Element, 'Pyro', '火'], [CharacterFilterKind.Element, 'Hydro', '水'],
    [CharacterFilterKind.Element, 'Dendro', '草'], [CharacterFilterKind.Element, 'Electro', '雷'],
    [CharacterFilterKind.Element, 'Anemo', '风'], [CharacterFilterKind.Element, 'Cryo', '冰'],
    [CharacterFilterKind.Element, 'Geo', '岩'],
  ]);
  for (const token of all) {
    const parsed = CharacterFilterToken.fromText(`  ${token.label}\t`);
    assert.deepEqual(parsed, token);
  }
  assert.deepEqual(CharacterFilterToken.suggestions(' 星 ', [new CharacterFilterToken(CharacterFilterKind.Quality, '5', 'translated label')])
    .map(token => token.value), ['4', '105']);
  assert.deepEqual(CharacterFilterToken.suggestions('剑', []).map(token => token.value), ['1', '11']);
  assert.deepEqual(CharacterFilterToken.suggestions('Kamisato', []), []);
  assert.equal(CharacterFilterToken.fromText(' \t\n '), undefined);
  for (const text of ['三星', '5星', 'Pyro', 'ayAKA', '元素精通']) {
    const parsed = CharacterFilterToken.fromText(text);
    assert.deepEqual([parsed.kind, parsed.value, parsed.label], [CharacterFilterKind.Name, text, text]);
  }
  const fresh = CharacterFilterToken.suggestions('', []);
  fresh.shift();
  assert.equal(CharacterFilterToken.suggestions('', [])[0].label, '四星');
});
test('character list combines committed name tokens with OR and separate filter groups with AND', () => {
  const model = new CharacterViewModel();
  const amber = Object.assign(new CharacterListItem(), { id: 10000021, name: 'Amber', element: 'Pyro', level: 80, rarity: 4 });
  const aloy = Object.assign(new CharacterListItem(), { id: 10000062, name: 'Aloy', element: 'Cryo', level: 70, rarity: 5, weaponType: 12 });
  const barbara = Object.assign(new CharacterListItem(), { id: 10000014, name: 'Barbara', element: 'Hydro', level: 80, rarity: 4, weaponType: 10 });
  amber.weapon.id = 15501;
  model.items = [amber, aloy, barbara];
  const tokens = labels => labels.map(label => CharacterFilterToken.fromText(label));
  assert.deepEqual(model.filteredItems(tokens(['a', '火', '水', '弓', '法器', '四星']), CharacterSortKind.Default), [amber, barbara]);
  assert.deepEqual(model.filteredItems(tokens(['AL', '弓', '限定五星']), CharacterSortKind.Default), [aloy]);
  assert.deepEqual(model.filteredItems(tokens(['Amber', 'BARBA']), CharacterSortKind.Default), [amber, barbara]);
  assert.deepEqual(model.filteredItems(tokens(['Amber', 'BARBA', '水']), CharacterSortKind.Default), [barbara]);
  assert.deepEqual(model.filteredItems(tokens(['a', '五星']), CharacterSortKind.Default), []);
  assert.deepEqual(model.filteredItems([], CharacterSortKind.Default), [aloy, amber, barbara]);
  assert.deepEqual(model.filteredItems([], CharacterSortKind.Level), [barbara, amber, aloy]);
  assert.deepEqual(model.filteredItems([], CharacterSortKind.Quality), [aloy, barbara, amber]);
  assert.deepEqual(model.items, [amber, aloy, barbara]);

  model.detailMap.set(amber.id, parse({ base: { id: amber.id }, selected_properties: [
    { property_type: '2000', base: '5000', add: '8000', final: '5000' },
    { property_type: 'FIGHT_PROP_CUR_ATTACK', base: '600', add: '900' },
  ], constellations: [{ is_actived: true }, { is_actived: false }, { is_actived: true }] }));
  model.detailMap.set(barbara.id, parse({ base: { id: barbara.id }, selected_properties: [
    { property_type: 'FIGHT_PROP_MAX_HP', base: '7000', add: '5000' },
    { property_type: '2001', base: '600', add: '1000' },
  ], constellations: [{ is_actived: true }, { is_actived: true }] }));
  assert.deepEqual(model.filteredItems([], CharacterSortKind.MaxHp), [amber, barbara, aloy]);
  assert.deepEqual(model.filteredItems([], CharacterSortKind.Attack), [barbara, amber, aloy]);
  assert.deepEqual(model.filteredItems([], CharacterSortKind.Constellations), [barbara, amber, aloy]);
  model.detailMap.get(amber.id).constellations.reverse();
  assert.deepEqual(model.filteredItems([], CharacterSortKind.Constellations), [barbara, amber, aloy]);
});
test('character name tokens match localized display and canonical names while raw-only mode uses server names', () => {
  const model = new CharacterViewModel();
  const ayaka = Object.assign(new CharacterListItem(), { id: 10000002, name: '神里绫华', element: 'Cryo', rarity: 5 });
  const barbara = Object.assign(new CharacterListItem(), { id: 10000014, name: '芭芭拉', element: 'Hydro', rarity: 4 });
  model.items = [ayaka, barbara];
  const avatarOf = wiki.avatarOf;
  wiki.avatarOf = id => id === ayaka.id ? { name: 'Kamisato Ayaka', canonicalName: '绫华', quality: 5 }
    : id === barbara.id ? { name: 'Barbara', canonicalName: '芭芭拉', quality: 4 } : undefined;
  try {
    const typed = ['ayAKA', 'BARBA'].map(text => CharacterFilterToken.fromText(text));
    assert.deepEqual(model.filteredItems(typed, CharacterSortKind.Default), [ayaka, barbara]);
    assert.deepEqual(model.filteredItems(typed, CharacterSortKind.Default, false), []);
    assert.deepEqual(model.filteredItems([CharacterFilterToken.fromText('绫华')], CharacterSortKind.Default), [ayaka]);
    assert.deepEqual(model.filteredItems([CharacterFilterToken.fromText('神里')], CharacterSortKind.Default, false), [ayaka]);
  } finally { wiki.avatarOf = avatarOf; }
});
test('default sorting uses ascending element and weapon type, then descending friendship without an ID tiebreak', () => {
  const model = new CharacterViewModel();
  const row = (id, element, weaponType, fetter, level = 80, rarity = 4) =>
    Object.assign(new CharacterListItem(), { id, name: String(id), element, weaponType, fetter, level, rarity });
  const fireBow = row(21, 'Pyro', 12, 10);
  const water = row(14, 'Hydro', 1, 10);
  const fireSword = row(41, 'Pyro', 1, 1);
  const fireSwordFriend = row(31, 'Pyro', 1, 10);
  const stableA = row(11, 'Pyro', 1, 10);
  const stableB = row(51, 'Pyro', 1, 10);
  const lower = row(61, 'Pyro', 1, 10, 70);
  const fiveStar = row(71, 'Geo', 13, 0, 1, 5);
  model.items = [water, fireBow, fireSword, fireSwordFriend, stableA, stableB, lower, fiveStar];
  assert.deepEqual(model.filteredItems([], CharacterSortKind.Default),
    [fiveStar, fireSwordFriend, stableA, stableB, fireSword, fireBow, water, lower]);
  assert.deepEqual(model.filteredItems([], CharacterSortKind.Level),
    [water, stableB, fireSword, fireSwordFriend, fireBow, stableA, lower, fiveStar]);
  model.items = [lower, fiveStar];
  assert.deepEqual(model.filteredItems([], CharacterSortKind.Quality), [fiveStar, lower]);
});
test('calculator supplements exact weapon ascension from fresh UID/avatar/weapon/level and commits atomically', async () => {
  const calculator = CalculateService.getInstance();
  const delta = new CalAvatarDelta(); delta.avatarId = 10000002;
  const raw = { skill_list: [{ id: 10019, group_id: 239, level_current: 8 }, { id: 10024, group_id: 231, level_current: 6 }, { id: 10018, group_id: 232, level_current: 9 }],
    weapon: { id: 11501, level_current: 80, max_level: 90 } };
  calculator.requestCalculator = async () => structuredClone(raw);
  let calls = 0;
  service.fetchDetail = async (uid, ids) => {
    calls++; assert.equal(uid, '100000001'); assert.deepEqual(ids, [10000002]);
    return [character(10000002, 3, [6, 9, 11])];
  };
  await calculator.fillSyncedDetails('100000001', delta, 10, 90);
  assert.equal(calls, 1); assert.equal(delta.weapon.weaponPromoteLevel, 6);
  assert.deepEqual(delta.skills.map(value => value.id), [239, 231, 232]);
  const before = JSON.stringify(delta);
  service.fetchDetail = async () => { const changed = character(10000002, 3, [6, 9, 11]); changed.weapon.id = 11502; return [changed]; };
  await assert.rejects(calculator.fillSyncedDetails('100000001', delta, 10, 90), /突破状态未知或装备已变化/);
  assert.equal(JSON.stringify(delta), before);
  service.fetchDetail = async () => { const stale = character(10000002, 3, [6, 9, 11]); stale.weapon.level = 90; return [stale]; };
  await assert.rejects(calculator.fillSyncedDetails('100000001', delta, 10, 90), /突破状态未知/);
  raw.weapon.promote_level = 5;
  service.fetchDetail = async () => { throw Error('must not fetch when exact calculator state exists'); };
  await calculator.fillSyncedDetails('100000001', delta, 10, 90);
  assert.equal(delta.weapon.weaponPromoteLevel, 5);
  const firstGroup = raw.skill_list[0].group_id;
  delete raw.skill_list[0].group_id;
  await assert.rejects(calculator.fillSyncedDetails('100000001', delta, 10, 90), /技能标识不完整/);
  raw.skill_list[0].group_id = firstGroup;
  raw.skill_list.pop();
  await assert.rejects(calculator.fillSyncedDetails('100000001', delta, 10, 90), /准确天赋等级/);
});
