// Real service -> manifest policy -> resource-manager boundary, using the bundled production files.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const ets = path.join(root, 'entry/src/main/ets');
const rawfile = path.join(root, 'entry/src/main/resources/rawfile');
const json = name => JSON.parse(fs.readFileSync(path.join(rawfile, 'metadata', name), 'utf8'));
const compiled = new Map();

function harness(locale = 'en') {
  const state = { locale, remote: new Map(), missing: new Set(), reads: [], beforeRead: null, beforeRemote: null, records: new Map() };
  const modules = new Map();
  const storage = new Map();
  const boundaries = {
    'service/AppLocaleService': { AppLocaleService: { current: () => state.locale } },
    'common/Logger': { Logger: { info() {}, warn() {} } },
    'common/AppContext': { AppContextProvider: { getResourceManager: () => ({ async getRawFileContent(name) {
      state.reads.push(name);
      if (state.beforeRead) await state.beforeRead(name);
      if (state.missing.has(name)) throw Error('missing fixture');
      return Uint8Array.from(fs.readFileSync(path.join(rawfile, name)));
    } }) } },
    'data/remote/GameDataUpdater': { GameDataUpdater: {
      initializeSnapshot: async () => {}, localVersion: () => '',
      readMetadata: name => state.remote.get(name) || '',
      readLanguageMetadata: async name => {
        const text = state.remote.get(name) || '';
        if (state.beforeRemote) await state.beforeRemote(name);
        return text;
      },
    } },
    'data/repo/AchievementRepo': { AchievementRepo: { getRecords: async () => state.records } },
    'data/network/ApiClient': { ApiClient: {} },
    'data/network/HoyolabClient': { HoyolabClient: {} },
    'data/network/DsSigner': { DsSigner: {} },
    'data/network/RiskVerifier': { RiskVerifier: {} },
    'service/UserService': { UserService: {} },
    'service/ChallengeSession': { ChallengeSession: {} },
    'common/HoyolabEndpoints': { HoyolabEndpoints: {} },
    '@kit.ArkTS': { util: { TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) } } },
  };
  function load(name) {
    if (boundaries[name]) return boundaries[name];
    if (modules.has(name)) return modules.get(name).exports;
    const filename = path.join(ets, name + '.ets');
    if (!compiled.has(name)) {
      const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { reportDiagnostics: true,
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
      assert.equal(result.diagnostics.length, 0, name);
      compiled.set(name, result.outputText);
    }
    const module = { exports: {} }; modules.set(name, module);
    const code = compiled.get(name);
    vm.runInThisContext(`(function(require,module,exports,AppStorage){${code}\n})`, { filename })(specifier => {
      if (boundaries[specifier]) return boundaries[specifier];
      assert.ok(specifier.startsWith('.'), 'unmocked platform boundary: ' + specifier);
      return load(path.posix.normalize(path.posix.join(path.posix.dirname(name), specifier)));
    }, module, module.exports, { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) });
    return module.exports;
  }
  return { state, load, wiki: load('service/WikiMetaService').WikiMetaService,
    localized: load('service/LocalizedGameDataService').LocalizedGameDataService,
    data: load('service/GameDataService').GameDataService };
}

let count = 0;
async function test(name, fn) { await fn(); console.log(`PASS ${++count}: ${name}`); }
const baseAvatar = json('avatar_meta.json').find(row => row.id === 10000046);
const baseWeapon = json('weapon_meta.json').find(row => row.id === 13501);
const baseMonster = json('monster_meta.json').find(row => row.id > 0);
const baseChapters = json('Chapter.json');
const locales = ['zh-Hans', 'zh-Hant', 'de', 'en', 'es', 'fr', 'id', 'it', 'ja', 'ko', 'pt', 'ru', 'th', 'tr', 'vi'];
const specialPlaceholders = {
  nickname: '{NICKNAME}',
  realName: '{REALNAME[ID(1)]}',
  timeZone: '{TIMEZONE}',
  heShe: '{PLAYERAVATAR#SEXPRO[INFO_MALE_PRONOUN_HE|INFO_FEMALE_PRONOUN_SHE]}',
  firstPerson: '{MATEAVATAR#SEXPRO[INFO_MALE_PRONOUN_BOYFIRST|INFO_FEMALE_PRONOUN_GIRLFIRST]}',
  princePrincess: '{MATEAVATAR#SEXPRO[INFO_MALE_PRONOUN_BOYD|INFO_FEMALE_PRONOUN_GIRLD]}',
};

(async () => {
  await test('all 15 languages reach real Wiki and achievement production parsers', async () => {
    const h = harness();
    for (const locale of locales) {
      h.state.locale = locale;
      const pack = json(`locale_${locale}.json`);
      const chapterText = pack.files['Chapter.json'];
      assert.deepEqual(chapterText.map(row => row.Id), baseChapters.map(row => row.Id), locale);
      assert.deepEqual(chapterText.at(-1), { Id: 2015, Number: '', Title: '' }, locale);
      const avatar = (await h.wiki.getAvatars()).find(row => row.id === baseAvatar.id);
      const expected = pack.files['avatar_meta.json'].find(row => row.id === baseAvatar.id);
      assert.equal(avatar.name, expected.name, locale);
      assert.equal(avatar.canonicalName, baseAvatar.name);
      assert.equal(avatar.icon, baseAvatar.icon);
      assert.equal(avatar.vision, baseAvatar.vision, 'element identity');
      assert.equal(avatar.birth, baseAvatar.birth, 'M/D identity');
      assert.equal(avatar.visionName, expected.vision || baseAvatar.vision);
      assert.deepEqual(avatar.cultivationItems, baseAvatar.cultivationItems);
      assert.equal(avatar.hpBase, baseAvatar.hpBase);
      assert.equal(avatar.skills[0].canonicalName, baseAvatar.skills[0].n);
      assert.equal(avatar.skills[0].n, expected.skills.find(row => row.i === baseAvatar.skills[0].i).n);
      assert.equal(avatar.fetters[0].t, h.wiki.cleanText(expected.fetters[0].t));
      assert.equal(avatar.stories[0].c, h.wiki.cleanText(expected.stories[0].c));
      for (const [name, placeholder] of Object.entries(specialPlaceholders)) {
        const plainText = pack.specialNames[name].replace(/<\/?color[^>]*>/g, '').trim();
        assert.equal(h.wiki.cleanText(placeholder), plainText, `${locale} ${name}`);
      }
      const weapon = (await h.wiki.getWeapons()).find(row => row.id === baseWeapon.id);
      assert.equal(weapon.name, pack.files['weapon_meta.json'].find(row => row.id === baseWeapon.id).name);
      assert.equal(weapon.canonicalName, baseWeapon.name);
      assert.deepEqual(weapon.growCurves.map(row => [row.i, row.t, row.v]), baseWeapon.growCurves.map(row => [row.i, row.t, row.v]));
      const monster = (await h.wiki.getMonsters()).find(row => row.describeId === baseMonster.describeId);
      assert.equal(monster.name, pack.files['monster_meta.json'].find(row => row.describeId === baseMonster.describeId).name);
      assert.deepEqual(monster.subHurts, baseMonster.subHurts);
      const materials = await h.wiki.getMaterials();
      assert.equal(materials.get(202).n, pack.files['material_meta.json'].find(row => row.id === 202).n);
      const cards = await h.wiki.getNameCards();
      for (const suffix of ['Mitya', 'Valeriy', 'Vodyanitsa', 'Vesna']) {
        const expectedCard = pack.files['NameCard.json'].find(row => row.Icon === `UI_NameCardIcon_${suffix}`);
        assert.ok(expectedCard, `${locale} ${suffix} namecard translation`);
        const card = cards.find(row => row.icon === expectedCard.Icon);
        assert.equal(card.name, expectedCard.Name);
        assert.equal(card.description, h.wiki.cleanText(expectedCard.Description));
      }
      const achievements = h.load('service/AchievementService').AchievementService;
      const categories = await achievements.getCategories();
      const translated = pack.files['Achievement.json'].find(row => row.Id === 80101);
      const entry = categories.flatMap(row => row.entries).find(row => row.id === translated.Id);
      assert.equal(entry.name, translated.Title);
      assert.equal(entry.canonicalName, json('Achievement.json').find(row => row.Id === entry.id).Title);
    }
    assert.equal((await h.data.readMetadataFile('avatar_meta.json')).includes('胡桃'), true, 'raw reader stays Chinese');
    assert.ok(h.state.reads.includes('metadata/locale_th.json'));
  });

  await test('Chinese legacy names still resolve icons, skills and display projections after switching', async () => {
    const h = harness('en');
    await h.wiki.ensureIconMaps();
    await h.wiki.getMonsters();
    await h.wiki.ensureBeyondItemMaps();
    assert.equal(h.wiki.nameOfAvatarId(baseAvatar.id), 'Hu Tao');
    assert.equal(h.wiki.iconOfAvatarName('胡桃'), baseAvatar.icon);
    assert.equal(h.wiki.iconOfAvatarName('Hu Tao'), baseAvatar.icon);
    assert.equal(h.wiki.iconOfWeaponName(baseWeapon.name), baseWeapon.icon);
    assert.equal(h.wiki.iconOfMonsterName(baseMonster.name), baseMonster.icon);
    assert.ok(h.wiki.skillsOfAvatar('胡桃').length > 0);
    assert.equal(h.wiki.nameCardPicOf('胡桃'), baseAvatar.nameCardPic);
    assert.equal(h.wiki.displayNameOfItem(0, '胡桃', '角色'), 'Hu Tao');
    for (const type of ['Weapon', '']) {
      assert.equal(h.wiki.displayNameOfItem(baseWeapon.id, baseWeapon.name, type), 'Staff of Homa');
    }
    const beyond = json('BeyondItem.json')[0];
    assert.equal(h.wiki.iconOfBeyondName(beyond.Name), beyond.Icon, 'BeyondItem passes actual manifest path validation');
    assert.notEqual(h.wiki.nameOfBeyondId(beyond.Id), '');
    h.state.locale = 'ja';
    await h.wiki.ensureIconMaps();
    assert.equal(h.wiki.nameOfAvatarId(baseAvatar.id), '胡桃');
    assert.equal(h.wiki.iconOfAvatarName('胡桃'), baseAvatar.icon);
  });

  await test('old remote cohort without language files falls back to bundle; new IDs retain Chinese', async () => {
    const h = harness('en');
    const avatars = json('avatar_meta.json');
    const added = { ...baseAvatar, id: 10000999, name: '未来角色', hpBase: 123, skills: [], talents: [] };
    avatars.push(added);
    h.state.remote.set('metadata/avatar_meta.json', JSON.stringify(avatars));
    const loaded = await h.wiki.getAvatars();
    assert.equal(loaded.find(row => row.id === baseAvatar.id).name, 'Hu Tao');
    assert.equal(loaded.find(row => row.id === added.id).name, '未来角色');
    assert.equal(loaded.find(row => row.id === added.id).hpBase, 123);
    assert.ok(h.state.reads.includes('metadata/locale_en.json'));
    const missing = harness('en'); missing.state.missing.add('metadata/locale_en.json');
    assert.equal((await missing.wiki.getAvatars()).find(row => row.id === baseAvatar.id).name, '胡桃');
  });

  await test('remote translated text wins and cannot replace numeric data, icons or relations', async () => {
    const h = harness('en');
    const pack = json('locale_en.json');
    const translated = pack.files['avatar_meta.json'].find(row => row.id === baseAvatar.id);
    Object.assign(translated, { name: 'Updated Hu Tao', icon: 'wrong', hpBase: 0, cultivationItems: [999] });
    h.state.remote.set('metadata/locale_en.json', JSON.stringify(pack));
    const avatar = (await h.wiki.getAvatars()).find(row => row.id === baseAvatar.id);
    assert.equal(avatar.name, 'Updated Hu Tao'); assert.equal(avatar.canonicalName, '胡桃');
    assert.equal(avatar.hpBase, baseAvatar.hpBase); assert.equal(avatar.icon, baseAvatar.icon);
    assert.deepEqual(avatar.cultivationItems, baseAvatar.cultivationItems);
    assert.ok(h.state.reads.includes('metadata/locale_en.json'));
  });

  await test('sparse remote locale keeps bundled rows, fields, tokens and name tables', async () => {
    const h = harness('en');
    const pack = json('locale_en.json');
    const huTao = pack.files['avatar_meta.json'].find(row => row.id === baseAvatar.id);
    const furniture = pack.files['Furniture.json'][0];
    h.state.remote.set('metadata/locale_en.json', JSON.stringify({
      schema: 1, locale: 'en', specialNames: { nickname: 'Visitor' },
      files: { 'avatar_meta.json': [{ id: baseAvatar.id, name: 'Updated Hu Tao',
        stories: [{ id: 2, sourceTitle: huTao.stories[2].sourceTitle, c: 'Updated story' }] }] },
    }));
    const avatars = await h.wiki.getAvatars();
    const avatar = avatars.find(row => row.id === baseAvatar.id);
    assert.equal(avatar.name, 'Updated Hu Tao');
    assert.equal(avatar.canonicalName, baseAvatar.name);
    assert.equal(avatar.stories[2].t, h.wiki.cleanText(huTao.stories[2].t));
    assert.equal(avatar.stories[2].c, 'Updated story');
    assert.equal(avatars.find(row => row.id === 10000003).name, 'Jean');
    assert.equal((await h.wiki.getWeapons()).find(row => row.id === baseWeapon.id).name, 'Staff of Homa');
    assert.equal((await h.localized.names('Furniture.json')).get(furniture.Id), furniture.Name);
    assert.equal(h.wiki.cleanText('{NICKNAME} / {REALNAME[ID(1)]}'), 'Visitor / Wanderer');
  });

  await test('malformed remote table rows are rejected and the bundled Wiki remains usable', async () => {
    const h = harness('en');
    const invalid = JSON.stringify({ schema: 1, locale: 'en', files: { 'avatar_meta.json': [null] } });
    const { GameDataManifestPolicy } = h.load('data/remote/GameDataManifestPolicy');
    assert.throws(() => GameDataManifestPolicy.validateLanguageText('metadata/locale_en.json', invalid), /语言/);
    h.state.remote.set('metadata/locale_en.json', invalid);
    const avatars = await h.wiki.getAvatars();
    assert.equal(avatars.length, json('avatar_meta.json').length);
    assert.equal(avatars.find(row => row.id === baseAvatar.id).name, 'Hu Tao');
  });

  await test('sparse credit and refinement arrays preserve their positions and fallback text', async () => {
    const h = harness('en');
    const pack = json('locale_en.json');
    const expectedAvatar = pack.files['avatar_meta.json'].find(row => row.id === baseAvatar.id);
    const expectedWeapon = pack.files['weapon_meta.json'].find(row => row.id === baseWeapon.id);
    h.state.remote.set('metadata/locale_en.json', JSON.stringify({
      schema: 1, locale: 'en', files: {
        'avatar_meta.json': [{ id: baseAvatar.id, cv: ['Updated Chinese credit', '', '', ''], vision: '', birth: '' }],
        'weapon_meta.json': [{ id: baseWeapon.id, affixDesc: ['Updated first rank'] }],
      },
    }));
    const avatar = (await h.wiki.getAvatars()).find(row => row.id === baseAvatar.id);
    assert.deepEqual(avatar.cv, ['Updated Chinese credit', ...expectedAvatar.cv.slice(1)]);
    assert.equal(avatar.visionName, expectedAvatar.vision);
    assert.equal(avatar.birthText, expectedAvatar.birth);
    const weapon = (await h.wiki.getWeapons()).find(row => row.id === baseWeapon.id);
    assert.deepEqual(weapon.affixDesc, ['Updated first rank', ...expectedWeapon.affixDesc.slice(1).map(h.wiki.cleanText)]);
  });

  await test('official English voice-over replaces character name placeholders in content', async () => {
    const h = harness('en');
    const avatars = await h.wiki.getAvatars();
    const ningguang = avatars.find(row => row.id === 10000027);
    const wanderer = avatars.find(row => row.id === 10000075);
    const voiceOver = ningguang.fetters.find(row => row.t === 'About Xianyun');
    assert.match(voiceOver.c, /Would you be interested, Traveler\?$/);
    assert.doesNotMatch(voiceOver.c, /\{NICKNAME\}|旅行者/);
    assert.ok(wanderer.fetters.some(row => row.t === 'About Wanderer: Puppet'));
  });

  await test('non-text remote inventory names cannot replace bundled names', async () => {
    const h = harness('en');
    const furniture = json('locale_en.json').files['Furniture.json'][0];
    h.state.remote.set('metadata/locale_en.json', JSON.stringify({ schema: 1, locale: 'en',
      files: { 'Furniture.json': [{ Id: furniture.Id, Name: 7 }] } }));
    assert.equal((await h.localized.names('Furniture.json')).get(furniture.Id), furniture.Name);
  });

  await test('same-title voice entries from a different base order keep their original content', async () => {
    const h = harness('en');
    const avatars = json('avatar_meta.json');
    let changed;
    for (const avatar of avatars) {
      for (let left = 0; left < avatar.fetters.length; left++) {
        const right = avatar.fetters.findIndex((row, index) => index > left
          && row.t === avatar.fetters[left].t && row.c !== avatar.fetters[left].c);
        if (right >= 0) { changed = { avatar, left, right }; break; }
      }
      if (changed) break;
    }
    assert.ok(changed, 'current source contains duplicate titles with distinct dialogue');
    const { avatar, left, right } = changed;
    [avatar.fetters[left], avatar.fetters[right]] = [avatar.fetters[right], avatar.fetters[left]];
    h.state.remote.set('metadata/avatar_meta.json', JSON.stringify(avatars));
    const loaded = (await h.wiki.getAvatars()).find(row => row.id === avatar.id);
    assert.equal(loaded.fetters[left].c, h.wiki.cleanText(avatar.fetters[left].c));
    assert.equal(loaded.fetters[right].c, h.wiki.cleanText(avatar.fetters[right].c));
  });

  await test('in-flight old language cannot overwrite current Wiki cache', async () => {
    const h = harness('en'); let release; let entered;
    const blocked = new Promise(resolve => { entered = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    let first = true;
    h.state.beforeRead = async name => {
      if (name === 'metadata/avatar_meta.json' && first) { first = false; entered(); await gate; }
    };
    const old = h.wiki.getAvatars(); await blocked;
    h.state.locale = 'ja';
    const current = await h.wiki.getAvatars(); release();
    assert.equal((await old).find(row => row.id === baseAvatar.id).name, '胡桃');
    assert.equal(await h.wiki.getAvatars(), current);
  });

  await test('rapid EN to JA to EN switch fills the active icon cache', async () => {
    const h = harness('en'); let release; let entered;
    const blocked = new Promise(resolve => { entered = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    let first = true;
    h.state.beforeRead = async name => {
      if (name === 'metadata/avatar_meta.json' && first) { first = false; entered(); await gate; }
    };
    const pending = h.wiki.ensureIconMaps();
    await blocked;
    try {
      h.state.locale = 'ja';
      await h.wiki.getMaterials();
      h.state.locale = 'en';
    } finally { release(); }
    await pending;
    assert.equal(h.wiki.iconOfAvatar(baseAvatar.id), baseAvatar.icon);
    assert.equal(h.wiki.iconOfWeapon(baseWeapon.id), baseWeapon.icon);
    assert.equal(h.wiki.nameOfAvatarId(baseAvatar.id), 'Hu Tao');
  });

  await test('concurrent Wiki metadata reads share one parse and array per locale', async () => {
    const h = harness('en');
    const loads = [
      ['avatar_meta.json', () => h.wiki.getAvatars()],
      ['weapon_meta.json', () => h.wiki.getWeapons()],
      ['monster_meta.json', () => h.wiki.getMonsters()],
    ];
    for (const [file, load] of loads) {
      const rows = await Promise.all(Array.from({ length: 8 }, load));
      assert.ok(rows[0].length > 0, file);
      assert.ok(rows.every(row => row === rows[0]), file);
      assert.equal(h.state.reads.filter(name => name === `metadata/${file}`).length, 1, file);
    }
  });

  await test('late catalog from a previous EN visit cannot replace active placeholder tokens', async () => {
    const h = harness('en'); let release; let entered;
    const blocked = new Promise(resolve => { entered = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    const remote = nickname => JSON.stringify({ schema: 1, locale: 'en', specialNames: { nickname }, files: {} });
    h.state.remote.set('metadata/locale_en.json', remote('Old visitor'));
    let first = true;
    h.state.beforeRemote = async name => {
      if (name === 'metadata/locale_en.json' && first) { first = false; entered(); await gate; }
    };
    const old = h.localized.names('Furniture.json'); await blocked;
    h.state.locale = 'ja'; await h.localized.names('Furniture.json');
    h.state.remote.set('metadata/locale_en.json', remote('Current visitor'));
    h.state.locale = 'en'; await h.localized.names('Furniture.json');
    assert.equal(h.wiki.cleanText('{NICKNAME}'), 'Current visitor');
    release(); await old;
    assert.equal(h.wiki.cleanText('{NICKNAME}'), 'Current visitor');
  });

  await test('a stale explicit-locale reader cannot evict the current display catalog', async () => {
    const h = harness('ja');
    await h.localized.names('Furniture.json');
    const nickname = json('locale_ja.json').specialNames.nickname;
    assert.equal(h.wiki.cleanText('{NICKNAME}'), nickname);
    const stale = await h.localized.readJson('ProfilePicture.json', 'en');
    assert.equal(stale.find(row => row.Id === 100).Name, 'Amber');
    assert.equal(h.localized.current(), 'ja');
    assert.equal(h.wiki.cleanText('{NICKNAME}'), nickname);
  });

  await test('queued achievement readers share the new language load after an old request completes', async () => {
    const h = harness('en');
    const service = h.load('service/AchievementService').AchievementService;
    let release; let entered;
    const blocked = new Promise(resolve => { entered = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    let first = true;
    h.state.beforeRead = async name => {
      if (name === 'metadata/Achievement.json' && first) { first = false; entered(); await gate; }
    };
    const firstRead = service.getCategories(); await blocked;
    const secondRead = service.getCategories();
    h.state.locale = 'ja'; release();
    const [left, right] = await Promise.all([firstRead, secondRead]);
    assert.equal(left, right);
    assert.equal(h.state.reads.filter(name => name === 'metadata/Achievement.json').length, 2);
    const entry = left.flatMap(row => row.entries).find(row => row.id === 80101);
    assert.equal(entry.name, json('locale_ja.json').files['Achievement.json'].find(row => row.Id === 80101).Title);
    h.state.locale = 'en';
    const current = (await service.getCategories()).flatMap(row => row.entries).find(row => row.id === 80101);
    assert.equal(current.name, json('locale_en.json').files['Achievement.json'].find(row => row.Id === 80101).Title);
    assert.equal(h.state.reads.filter(name => name === 'metadata/Achievement.json').length, 3);
  });

  await test('gacha and challenge text overlays leave schedule identities and wave data untouched', async () => {
    const h = harness('en');
    for (const name of ['GachaEvent.json', 'TowerSchedule.json', 'TowerFloor.json', 'HardChallengeSchedule.json']) {
      const original = json(name); const rows = await h.localized.readJson(name);
      assert.equal(rows.length, original.length);
      for (let index = 0; index < rows.length; index++) {
        const before = { ...original[index] }, after = { ...rows[index] };
        for (const field of ['Name', 'BuffName', 'Descriptions', 'canonicalName']) { delete before[field]; delete after[field]; }
        assert.deepEqual(after, before, name);
      }
    }
    assert.notEqual((await h.localized.readJson('TowerSchedule.json'))[0].BuffName, json('TowerSchedule.json')[0].BuffName);
    for (const table of ['material_meta.json', 'Reliquary.json', 'ReliquarySet.json', 'Furniture.json']) {
      assert.ok((await h.localized.names(table)).size > 0, table);
    }
    const records = new Map([[80101, { achId: 80101, status: 3, current: 1, timestamp: 123 }]]);
    h.state.records = records;
    const service = h.load('service/AchievementService').AchievementService;
    const before = await service.getOverallStats(1);
    h.state.locale = 'ja';
    const after = await service.getOverallStats(1);
    assert.deepEqual(after, before);
    assert.equal(h.state.records, records);
  });
  await test('profile metadata raw reader preserves icon mappings while display names follow locale', async () => {
    const h = harness('en');
    const pictures = JSON.parse(await h.data.readMetadataFile('ProfilePicture.json'));
    assert.equal(pictures.length, 191);
    assert.equal(pictures.find(row => row.Id === 1).Icon, 'UI_AvatarIcon_PlayerBoy_Circle');
    assert.equal(pictures.find(row => row.Id === 11).UnlockParameter, 200501);
    assert.equal(pictures.find(row => row.Id === 900004).Icon, '');
    const localized = await h.localized.readJson('ProfilePicture.json');
    const expected = json('locale_en.json').files['ProfilePicture.json'];
    for (let index = 0; index < pictures.length; index++) {
      const before = pictures[index], after = localized[index];
      assert.equal(after.Name, expected.find(row => row.Id === before.Id).Name || before.Name);
      assert.equal(after.canonicalName, before.Name);
      assert.equal(after.Icon, before.Icon);
      assert.equal(after.UnlockType, before.UnlockType);
      assert.equal(after.UnlockParameter, before.UnlockParameter);
    }
  });
  await test('Archon Quest chapter text follows canonical IDs and leaves progress data untouched', async () => {
    assert.equal(baseChapters.length, 54);
    assert.equal(baseChapters.findIndex(row => row.Id === 1705), 52);
    assert.deepEqual(baseChapters.at(-1), { Id: 2015, QuestType: 0, Number: '', Title: '' });
    const h = harness('en');
    const canonical = [baseChapters[52], baseChapters[0], baseChapters.at(-1)];
    h.state.remote.set('metadata/Chapter.json', JSON.stringify(canonical));
    h.state.remote.set('metadata/locale_en.json', JSON.stringify({ schema: 1, locale: 'en', files: {
      'Chapter.json': [
        { Id: 1001, Title: 'Updated Prologue' },
        { Id: 1705, id: 1001, QuestType: 7, Number: '', Title: 'Updated Act VI' },
        { Id: 9999, QuestType: 0, Number: 'Unrecognized', Title: 'Unrecognized' },
      ],
    } }));
    const localized = await h.localized.readJson('Chapter.json');
    assert.deepEqual(localized, [
      { Id: 1705, QuestType: 0, Number: 'Chapter VII: Act VI', Title: 'Updated Act VI' },
      { Id: 1001, QuestType: 0, Number: 'Prologue: Act I', Title: 'Updated Prologue' },
      canonical[2],
    ]);
    assert.deepEqual(JSON.parse(await h.data.readMetadataFile('Chapter.json')), canonical);
  });
  await test('both travelers use their correct portraits and official empty English fields', async () => {
    const h = harness('en');
    h.state.remote.set('metadata/locale_en.json', JSON.stringify({ schema: 1, locale: 'en', files: {
      'avatar_meta.json': [{ id: baseAvatar.id, title: '', native: '' }],
    } }));
    await h.wiki.ensureIconMaps();
    for (const [id, gender] of [[10000005, 'PlayerBoy'], [10000007, 'PlayerGirl']]) {
      const avatar = h.wiki.avatarOf(id);
      assert.equal(avatar.name, 'Traveler');
      assert.equal(avatar.canonicalName, '旅行者');
      assert.equal(avatar.title, '');
      assert.equal(avatar.native, '');
      assert.equal(avatar.detail, 'A traveler from another world who had their only kin taken away, forcing them to embark on a journey to find The Seven.');
      assert.equal(h.wiki.iconOfAvatar(id), `UI_AvatarIcon_${gender}`);
      assert.ok(fs.existsSync(path.join(rawfile, 'icons/AvatarIcon', `${avatar.icon}.png`)));
    }
    const expected = json('locale_en.json').files['avatar_meta.json'].find(row => row.id === baseAvatar.id);
    assert.equal(h.wiki.avatarOf(baseAvatar.id).title, expected.title, 'ordinary sparse empty fields keep fallback text');
    assert.equal(h.wiki.avatarOf(baseAvatar.id).native, expected.native);
  });
  await test('7.2 identities and wish UP lists are available through production metadata', async () => {
    const h = harness('en');
    await h.wiki.ensureIconMaps();
    for (const [id, name] of [[10000136, '米提亚'], [10000137, '瓦列里'], [10000140, '沃雅妮莎'], [10000143, '薇斯纳']]) {
      const avatar = h.wiki.avatarOf(id);
      assert.equal(avatar.canonicalName, name);
      assert.ok(avatar.skills.length >= 3);
      assert.ok(h.wiki.iconOfAvatarName(name).length > 0);
      assert.ok(fs.existsSync(path.join(rawfile, 'icons/AvatarIcon', `${avatar.icon}.png`)));
    }
    for (const id of [11437, 11438, 11522, 14437, 14524, 14525, 15437]) {
      const weapon = h.wiki.weaponOf(id);
      assert.ok(weapon?.name);
      assert.ok(fs.existsSync(path.join(rawfile, 'icons/EquipIcon', `${weapon.icon}.png`)));
    }
    assert.equal(h.wiki.displayNameOfItem(10000136, '米提亚', '角色'), 'Mitya');
    assert.equal(h.wiki.displayNameOfItem(10000137, '瓦列里', '角色'), 'Valeriy');
    const periods = (await h.wiki.getGachaEvents()).filter(row => row.version === '7.2' && row.order === 1);
    assert.deepEqual(periods.find(row => row.type === 301).upOrange, [10000136]);
    assert.ok(periods.find(row => row.type === 301).upPurple.includes(10000137));
    assert.deepEqual(periods.find(row => row.type === 400).upOrange, [10000089]);
    assert.deepEqual(periods.find(row => row.type === 302).upOrange, [11513, 14525]);
  });
  await test('published 2026-11-12 challenge periods load through real offline consumers', async () => {
    const h = harness('zh-Hans');
    const tower = h.load('service/TowerMetadataService').TowerMetadataService;
    await tower.preload();
    const now = Date.parse('2026-11-12T12:00:00+08:00');
    const abyss = tower.publishedPeriods().find(row => row.scheduleId === 124);
    assert.equal(abyss.name, '骇星之月');
    assert.equal(abyss.startTime, Date.parse('2026-10-16T04:00:00+08:00'));
    assert.equal(abyss.endTime, Date.parse('2026-11-16T03:59:59+08:00'));
    assert.ok(abyss.startTime < now && now < abyss.endTime);
    assert.equal(abyss.hasRecord, false);
    const preview = tower.preview(abyss);
    assert.deepEqual(preview.floors.map(row => row.index), [12, 11, 10, 9]);
    assert.ok(preview.floors.every(row => row.levels.length === 3));
    const { SpiralAbyssFloor } = h.load('model/SpiralAbyss');
    const played = SpiralAbyssFloor.fromJson({ index: 12, star: 2, levels: [{ index: 1, star: 2, battles: [] }] });
    const merged = tower.periodFloors(abyss.scheduleId, [played]);
    assert.deepEqual(merged.map(row => row.index), [12, 11, 10, 9]);
    assert.equal(merged[0].star, 2);
    assert.equal(merged[0].levels[0], played.levels[0]);
    assert.equal(merged[0].levels[1].hasRecord, false);
    assert.equal(merged[1].hasRecord, false);
    assert.equal(played.levels.length, 1, 'displaying published rooms must preserve the API record');
    assert.match(tower.buffOf(124).description, /每2秒/);
    assert.deepEqual(tower.floorDisorders(124, 12, 1), ['角色的星烁反应造成的伤害提升75%。']);
    const waves = tower.wavesOf(124, 12, 1);
    assert.equal(waves.monsterLevel, 94);
    assert.equal(waves.upper[0].monsters[0].icon, 'UI_MonsterIcon_Volkodlak_Greyhound_Furiosa');
    assert.equal(waves.lower[0].monsters[0].icon, 'UI_MonsterIcon_Invoker_Archdeacon');
    assert.equal(waves.lower.flatMap(row => row.monsters).length, 3);
    const theater = (await h.wiki.getRoleCombatSchedules()).find(row => row.id === 31);
    assert.deepEqual(theater.elements, [2, 4, 8]);
    assert.deepEqual(theater.specialAvatars, [10000035, 10000150, 10000143, 10000124]);
    assert.deepEqual(theater.initialAvatars, [10000060, 10000121, 10000120, 10000031, 10000030, 10000100]);
    assert.ok(theater.begin < now && now < theater.end);
    const hard = h.load('service/HardChallengeService').HardChallengeService;
    const stygian = (await hard.publishedPeriods()).find(row => row.scheduleId === 5269013);
    assert.equal(stygian.name, '鲸波之役');
    assert.equal(stygian.startTime, Date.parse('2026-11-11T10:00:00+08:00'));
    assert.equal(stygian.endTime, Date.parse('2026-12-23T09:59:59+08:00'));
    assert.ok(stygian.startTime < now && now < stygian.endTime);
    assert.equal(stygian.hasRecord, false);
  });
  await test('7.2 achievements add real IDs without changing existing archive progress', async () => {
    const h = harness('zh-Hans');
    const service = h.load('service/AchievementService').AchievementService;
    const record = { achId: 80101, status: 3, current: 1, timestamp: 123 };
    h.state.records.set(record.achId, record);
    const categories = await service.getCategories();
    const entries = categories.flatMap(row => row.entries);
    assert.equal(entries.length, 1909);
    assert.equal(new Set(entries.map(row => row.id)).size, 1909);
    assert.equal(entries.filter(row => row.ver === '7.2').length, 55);
    assert.equal(categories.find(row => row.id === 73).name, '至冬·冰与苍星的圣都·其之二');
    assert.equal(categories.find(row => row.id === 74).name, '浮涌的阴影之地·其之二');
    assert.equal(categories.find(row => row.id === 70).name, '浮涌的阴影之地·其之一');
    assert.equal((await service.getOverallStats(1)).done, 1);
    assert.equal(h.state.records.get(80101), record);
  });
  await test('monster resistances use display order for both legacy and refreshed compact storage', async () => {
    const h = harness('zh-Hans');
    const monsters = await h.wiki.getMonsters();
    assert.equal(monsters.length, 572);
    const cryo = monsters.find(row => row.describeId === 60201);
    assert.deepEqual(cryo.subHurts, [0.1, 0.1, 0.1, 0.1, 0.7, 0.1, 0.1, 0.3]);
    for (const id of [901, 51329, 51330, 51331, 51346, 51352, 51354, 51371, 51372, 63107, 63108, 80218]) {
      const monster = monsters.find(row => row.describeId === id);
      assert.ok(monster?.name && monster.icon && monster.growCurves.length > 0);
    }
    const tower = h.load('service/TowerMetadataService').TowerMetadataService;
    await tower.preload();
    const normalized = tower.toWaveViews([{ Type: 1, Monsters: [
      { Id: 30606, Count: 1 }, { Id: 40632, Count: 1 }, { Id: 60404, Count: 1 }, { Id: 28021302, Count: 1 },
    ] }], 90)[0].monsters;
    assert.equal(normalized.length, 4);
    assert.equal(normalized[0].icon, 'UI_MonsterIcon_Fatuus_Escadron_Wind');
    assert.equal(normalized[1].icon, 'UI_MonsterIcon_MachinaIustitia_Pylon');
    assert.ok(normalized.every(row => row.icon.length > 0));
  });
  await test('monster DisplayItem drops use real relic-set names in all languages without entering the material catalog', async () => {
    const h = harness();
    const optional = json('monster_drop_meta.json');
    assert.equal(optional.length, 21);
    for (const locale of locales) {
      h.state.locale = locale;
      const materials = await h.wiki.getMaterials();
      const drops = await h.wiki.getMonsterDrops();
      const names = await h.localized.names('ReliquarySet.json');
      for (const row of optional) {
        const item = drops.get(row.Id);
        assert.equal(item.n, names.get(row.SetId) || row.Name, `${locale}: ${row.Id}`);
        assert.equal(item.i, row.Icon);assert.equal(item.r, row.RankLevel);assert.equal(item.canonicalName,row.Name);
        assert.equal(materials.has(row.Id),false);
        assert.ok(fs.existsSync(path.join(rawfile,'icons/RelicIcon',item.i+'.png')));
      }
      const monsters = await h.wiki.getMonsters();
      for (const id of new Set(monsters.flatMap(row => row.drops))) assert.ok(drops.get(id)?.n, `${locale}: drop ${id}`);
    }
    assert.ok(h.state.reads.includes('metadata/monster_drop_meta.json'));
  });
  await test('optional monster display table uses bundled data for old snapshots and material drops survive a missing optional file', async () => {
    const h = harness('en');
    const drops = await h.wiki.getMonsterDrops();
    assert.equal(drops.get(400089).n, "Gladiator's Finale");
    const missing = harness('en');missing.state.missing.add('metadata/monster_drop_meta.json');
    const fallback = await missing.wiki.getMonsterDrops();
    assert.equal(fallback.get(202).n,'Mora');assert.equal(fallback.has(400089),false);
    assert.equal((await missing.wiki.getMaterials()).has(400089),false);
  });
  await test('monster level 110 uses the packaged curve and reproduces the reference slime stats', async () => {
    const h=harness('zh-Hans');const monster=(await h.wiki.getMonsters()).find(row=>row.describeId===101);
    const values=await h.load('service/BaseValueService').BaseValueService.monsterBaseValues(
      monster.growCurves,monster.hpBase,monster.attackBase,monster.defenseBase,110);
    assert.deepEqual([values.hp,values.atk,values.def],[42802,1742,1050]);
  });
  console.log(`PASS: ${count} game metadata localization suites`);
})().catch(error => { console.error(error); process.exitCode = 1; });
