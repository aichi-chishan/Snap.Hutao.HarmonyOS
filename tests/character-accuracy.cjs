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
const wiki = {
  iconOfAvatar: () => '', cleanText: value => value, nameOfWeapon: id => `weapon ${id}`,
  getWeapons: async () => [{ id: 11501, rankLevel: 5 }, { id: 11101, rankLevel: 1 }],
};
const mocks = {
  ApiClient: {}, ApiResponse: class {}, HoyolabClient: {}, DsSigner: {},
  RiskVerifier: {}, RiskControlError: class extends Error {}, UserService: {},
  Constants: { RegionUtil: { regionOfUid: () => 'cn_gf01' }, AppConstants: {} },
  HoyolabEndpoints: { gameRecordUrl: path => path }, Logger: { info() {}, warn() {} },
  PreferencesStore: { getString: (key, value) => preferences.get(key) ?? value,
    setString: (key, value) => preferences.set(key, value) },
  WikiMetaService: wiki,
  ReliquaryScore: { calculate: () => 0, isCritEffective: () => true },
};
const cache = new Map();
function load(relative) {
  const file = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
  if (cache.has(file)) return cache.get(file).exports;
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
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
