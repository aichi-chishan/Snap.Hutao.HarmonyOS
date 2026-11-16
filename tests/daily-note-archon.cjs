const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const metadata = path.join(root, '../resources/rawfile/metadata');
const readJson = name => JSON.parse(fs.readFileSync(path.join(metadata, name), 'utf8'));
const canonical = readJson('Chapter.json');
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const request = (id = 1705) => ({ archon_quest_progress: { list: [
  { id, status: 'Ongoing', chapter_num: '接口章名', chapter_title: '接口标题' },
] } });

function harness() {
  const state = { locale: 'zh-Hans', note: undefined, missing: false, legacyArchon: '', gates: new Map(), reads: [],
    current: { id: 1 }, uid: '100000001' };
  const modules = new Map();
  const boundaries = {
    'service/GameDataService': { GameDataService: {
      async readMetadataFile(name) {
        state.reads.push(name); if (state.missing) throw Error('optional metadata unavailable');
        return fs.readFileSync(path.join(metadata, name), 'utf8');
      },
      async readLanguageFiles(name) {
        const pack = readJson(name);
        const gate = state.gates.get(pack.locale); if (gate) await gate.promise;
        return [JSON.stringify({ schema: 1, locale: pack.locale, files: { 'Chapter.json': pack.files['Chapter.json'] } })];
      },
    } },
    'service/AppLocaleService': { AppLocaleService: { current: () => state.locale } },
    'service/DailyNoteService': { NotifyFlags: { ALL: 31 }, KEY_NOTE_VERSION: 'dailyNoteVersion', DailyNoteService: {
      getInstance: () => ({ isTimerRunning: () => false, trackedEntries: async () => [{ userId: 1, uid: state.uid,
        nickname: '角色', region: 'cn_gf01', level: 60, record: state.note ? { note: state.note } : undefined }] }),
    } },
    'data/repo/DailyNoteRepo': { DailyNoteRepo: { get: async () => state.note ? { note: state.note } : undefined } },
    'service/UserService': { UserService: { getInstance: () => ({ getCurrentUser: () => state.current }) } },
    'data/prefs/PreferencesStore': { PreferencesStore: { getString: () => state.legacyArchon, getCurrentUid: () => state.uid } },
    '@kit.ArkData': { relationalStore: {} }, 'data/db/RelationalStoreHelper': {},
    'data/repo/UserRepo': {}, 'model/User': {}, 'model/BackgroundTask': {},
    'service/DailyNoteReminderService': {},
    'common/Logger': { Logger: { warn() {} } },
  };
  function load(name, production = false) {
    if (!production && boundaries[name]) return boundaries[name];
    if (modules.has(name)) return modules.get(name);
    const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
    const code = ts.transpileModule(source, { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true,
    }, reportDiagnostics: true });
    assert.equal(code.diagnostics.length, 0, name);
    const module = { exports: {} };
    vm.runInNewContext(code.outputText, { module, exports: module.exports, Observed: type => type,
      require: id => {
        if (boundaries[id]) return boundaries[id];
        assert.ok(id.startsWith('.'), `unexpected platform dependency: ${id}`);
        return load(path.posix.normalize(path.posix.join(path.posix.dirname(name), id)));
      } });
    modules.set(name, module.exports); return module.exports;
  }
  const model = load('model/DailyNote');
  const { DailyNoteViewModel } = load('viewmodel/DailyNoteViewModel');
  const record = columns => load('data/repo/DailyNoteRepo', true).DailyNoteRepo.rowToRecord({
    getColumnIndex: name => name,
    getString: name => String(columns[name] ?? ''),
    getLong: name => Number(columns[name] ?? 0),
  });
  return { state, ...model, view: new DailyNoteViewModel(), record };
}

test('real AQ order gives chapter 1705 exactly 52/54 and retains the unnamed 2015 entry', async () => {
  const { state, view, DailyNote, DailyNoteChapterMetadata } = harness();
  const chapters = DailyNoteChapterMetadata.fromJson(canonical);
  assert.equal(chapters.length, 54); assert.equal(chapters[52].id, 1705);
  assert.equal(chapters[53].id, 2015); assert.equal(chapters[53].title, '');
  state.note = DailyNote.fromJson(request()); await view.load(state.uid);
  const entry = view.buildCardEntries()[0];
  assert.equal(entry.archonProgress, 52); assert.equal(entry.archonTotal, 54);
  assert.equal(entry.archonChapterText, '第七章 第六幕 寄自彼岸的昨日');
  assert.equal(state.current.id, 1); assert.equal(entry.uid, state.uid);
});

test('empty list is complete; unknown IDs and old cached text never acquire an estimated value', async () => {
  const { state, view, DailyNote, record } = harness();
  state.note = DailyNote.fromJson({ archon_quest_progress: { list: [] } });
  await view.load(state.uid);
  let entry = view.buildCardEntries()[0];
  assert.equal(entry.archonProgress, 54); assert.equal(entry.archonTotal, 54);
  state.note = DailyNote.fromJson(request(999999)); await view.load(state.uid);
  entry = view.buildCardEntries()[0];
  assert.equal(entry.archonProgress, -1); assert.equal(entry.archonTotal, 54); assert.equal(entry.archonChapterText, '');
  assert.equal(entry.note.archonQuestSubText(), '接口章名 接口标题');

  state.note = record({ archon_json: JSON.stringify([
    { status: 'Ongoing', chapterNum: '第七章 第六幕', chapterTitle: '寄自彼岸的昨日' },
  ]) }).note;
  await view.load(state.uid); entry = view.buildCardEntries()[0];
  assert.equal(entry.note.archonQuests[0].id, 0); assert.equal(entry.archonProgress, -1, 'a matching title is not an ID');
  assert.equal(entry.note.archonQuestSubText(), '第七章 第六幕 寄自彼岸的昨日');
});

test('chapter IDs survive both raw payload and archived chapter JSON round trips', () => {
  const { DailyNote, record } = harness();
  const fresh = DailyNote.fromJson(request());
  assert.equal(fresh.archonQuests[0].id, 1705);
  const fromRaw = record({ raw_json: fresh.rawJson }).note;
  assert.equal(fromRaw.archonQuests[0].id, 1705);
  assert.equal(fromRaw.hasArchonQuestProgress, true);
  const fromArchive = record({ archon_json: JSON.stringify(fresh.archonQuests) }).note;
  assert.equal(fromArchive.hasArchonQuestProgress, true);
  assert.equal(fromArchive.archonQuests[0].id, 1705); assert.equal(fromArchive.archonQuests[0].chapterTitle, '接口标题');
});

test('missing task data and ambiguous legacy empty arrays do not claim completion', async () => {
  const { state, view, DailyNote, record } = harness();
  const missing = [{}, { archon_quest_progress: null }, { archon_quest_progress: {} },
    { archon_quest_progress: { list: null } }].map(payload => DailyNote.fromJson(payload));
  const legacy = ['', '[]', '{broken'].map(archon_json => record({ archon_json }).note);
  for (const note of [...missing, ...legacy]) {
    state.note = note; await view.load(state.uid);
    assert.equal(note.hasArchonQuestProgress, false);
    assert.equal(note.archonQuestFinished(), false); assert.equal(note.archonQuestMainText(), '暂无任务进度');
    assert.equal(view.buildCardEntries()[0].archonProgress, -1);
  }
  state.note = record({ raw_json: JSON.stringify({ archon_quest_progress: { list: [] } }) }).note;
  await view.load(state.uid);
  assert.equal(state.note.archonQuestFinished(), true); assert.equal(view.buildCardEntries()[0].archonProgress, 54);
});

test('legacy preferences restore available chapter text while an empty copy remains unknown', async () => {
  const { state, view, DailyNote } = harness();
  for (const [cached, expected] of [
    ['[]', -1],
    [JSON.stringify([{ status: 'Ongoing', chapterNum: '旧章名', chapterTitle: '旧标题' }]), -1],
    [JSON.stringify([{ id: 1705, status: 'Ongoing', chapterNum: '旧章名', chapterTitle: '旧标题' }]), 52],
  ]) {
    state.note = new DailyNote(); state.legacyArchon = cached; await view.load(state.uid);
    const entry = view.buildCardEntries()[0];
    assert.equal(entry.archonProgress, expected);
    if (cached !== '[]') assert.equal(entry.note.archonQuestSubText(), '旧章名 旧标题');
  }
});

test('language overlays change chapter text while retaining the 54/52 numeric projection', async () => {
  const { state, view, DailyNote } = harness(); state.note = DailyNote.fromJson(request());
  for (const [locale, expected] of [
    ['en', 'Chapter VII: Act VI A Yesterday Sent From Beyond'],
    ['ja', '第七章 第六幕 彼岸より届けられし昨日'],
    ['zh-Hant', '第七章 第六幕 寄自彼岸的昨日'],
  ]) {
    state.locale = locale; await view.loadTracked(); const entry = view.buildCardEntries()[0];
    assert.equal(entry.archonProgress, 52); assert.equal(entry.archonTotal, 54); assert.equal(entry.archonChapterText, expected);
  }
  assert.ok(state.reads.every(name => name === 'Chapter.json'), 'no MainQuest table or new metadata cache is required');
});

test('late locale reads cannot replace the latest display projection', async () => {
  const { state, view, DailyNote } = harness(); state.note = DailyNote.fromJson(request()); state.locale = 'en';
  const gate = deferred(); state.gates.set('en', gate);
  const older = view.loadTracked(); await flush();
  state.locale = 'zh-Hans'; await view.loadTracked();
  gate.resolve(); await older;
  assert.equal(view.buildCardEntries()[0].archonChapterText, '第七章 第六幕 寄自彼岸的昨日');
});

test('missing optional metadata and unfetched notes keep their truthful display without a fabricated bar', async () => {
  const { state, view, DailyNote } = harness(); state.note = DailyNote.fromJson(request()); state.missing = true;
  await view.load(state.uid); let entry = view.buildCardEntries()[0];
  assert.equal(entry.archonProgress, -1); assert.equal(entry.archonTotal, 0);
  assert.equal(entry.note.archonQuestSubText(), '接口章名 接口标题');
  state.note = undefined; await view.load(''); entry = view.buildCardEntries()[0];
  assert.equal(entry.note, undefined); assert.equal(entry.archonProgress, -1);
});
