const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const pageSource = fs.readFileSync(path.join(root, 'pages/DailyNotePage.ets'), 'utf8').replaceAll('\r\n', '\n');

function compile(source, dependencies = {}) {
  const compiled = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true,
  }, reportDiagnostics: true });
  assert.equal(compiled.diagnostics.length, 0);
  const module = { exports: {} };
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports, Observed: type => type,
    require: name => dependencies[name.split('/').at(-1)] ?? {} });
  return module.exports;
}

function page() {
  const method = name => {
    const begin = pageSource.indexOf(`  private ${name}(`);
    const end = pageSource.indexOf('\n  }', begin) + 4;
    assert.ok(begin >= 0 && end > begin, name);
    return pageSource.slice(begin, end);
  };
  const constants = [...pageSource.matchAll(/  private static readonly (?:EXP_MIN_ITEM|EXP_GAP|CARD_WIDTH|CARD_PADDING|ROW_RADIUS|TRANSFORMER_MAX): number = \d+;/g)]
    .map(match => match[0]).join('\n');
  const rowType = pageSource.slice(pageSource.indexOf('class NoteRowData {'), pageSource.indexOf('\n}', pageSource.indexOf('class NoteRowData {')) + 2);
  return compile(`${rowType}\nexport class DailyNotePage {
    ${constants}
    expGridW: number = 0;
    ${method('expTemplate')}
    ${method('cardHeadText')}
    ${method('cardKey')}
    ${method('makeRow')}
    ${method('cardRows')}
  }`).DailyNotePage;
}

test('current and other-account cards project each game role without crossing equal UIDs', () => {
  const { DailyNoteViewModel } = compile(fs.readFileSync(path.join(root, 'viewmodel/DailyNoteViewModel.ets'), 'utf8'), {
    DailyNoteService: { NotifyFlags: { ALL: 31 } },
  });
  const model = new DailyNoteViewModel();
  const latest = { refreshTime: 200 };
  const otherSnapshot = { refreshTime: 100 };
  model.currentUserId = 1; model.currentUid = '100000001'; model.note = latest;
  model.trackedEntries = [
    { userId: 2, uid: '100000001', nickname: '角色乙', region: 'cn_qd01', level: 55, record: { note: otherSnapshot } },
    { userId: 1, uid: '100000001', nickname: '角色甲', region: 'cn_gf01', level: 60, record: { note: { refreshTime: 90 } } },
  ];
  const entries = model.buildCardEntries();
  assert.deepEqual(Array.from(entries, entry => [entry.userId, entry.nickname, entry.region, entry.level]),
    [[1, '角色甲', 'cn_gf01', 60], [2, '角色乙', 'cn_qd01', 55]]);
  assert.equal(entries[0].note, latest); assert.equal(entries[1].note, otherSnapshot);
  const Page = page(); const view = new Page();
  assert.equal(view.cardHeadText(entries[0]), '角色甲 | 天空岛 | Lv.60');
  assert.equal(view.cardHeadText(entries[1]), '角色乙 | 世界树 | Lv.55');
  model.trackedEntries = [model.trackedEntries[0]];
  const remaining = model.buildCardEntries();
  assert.equal(remaining.length, 1, 'removing the current role must still hide its cached card');
  assert.equal(remaining[0].userId, 2); assert.equal(remaining[0].note, otherSnapshot);
});

test('missing role details use the real UID; changed header metadata invalidates the card render key', () => {
  const Page = page(); const view = new Page();
  const entry = { userId: 2, uid: '100000001', nickname: '', region: '', level: 0, isCurrent: false, tracked: true };
  assert.equal(view.cardHeadText(entry), 'UID 100000001');
  const before = view.cardKey(entry);
  entry.nickname = '昵称更新'; entry.region = 'cn_gf01'; entry.level = 60;
  assert.notEqual(view.cardKey(entry), before);
  assert.equal(view.cardHeadText(entry), '昵称更新 | 天空岛 | Lv.60');
});

test('native card width leaves two expedition columns after padding and borders, while narrow cards adapt', () => {
  const Page = page(); const view = new Page();
  const contentWidth = Page.CARD_WIDTH - 2 * Page.CARD_PADDING - 2; // 1vp border on each side.
  assert.ok(contentWidth >= 2 * Page.EXP_MIN_ITEM + Page.EXP_GAP);
  view.expGridW = contentWidth; assert.equal(view.expTemplate(), '1fr 1fr');
  view.expGridW = 285; assert.equal(view.expTemplate(), '1fr');
  view.expGridW = 286; assert.equal(view.expTemplate(), '1fr 1fr');
  view.expGridW = 0; assert.equal(view.expTemplate(), '1fr');
  assert.match(pageSource, /repeat\(auto-fill,\$\{DailyNotePage\.CARD_WIDTH\}vp\)/);
  assert.match(pageSource, /\.padding\(DailyNotePage\.CARD_PADDING\)/);
  assert.match(pageSource, /this\.expGridW = Number\(newValue\.width\)/);
});

test('both native linear progress fills use the reference small corner instead of half-height round ends', () => {
  const Page = page();
  const styles = [...pageSource.matchAll(/\.style\((\{ strokeWidth: (?:48|40), strokeRadius: DailyNotePage\.ROW_RADIUS \})\)/g)];
  assert.equal(styles.length, 2);
  for (const match of styles) {
    const options = Function('DailyNotePage', `return (${match[1]});`)(Page);
    assert.equal(options.strokeRadius, 4);
    assert.ok(options.strokeRadius < options.strokeWidth / 2);
  }
});

test('an explicitly completed archon status fills its row without guessing progress for an ongoing chapter', () => {
  const Page = page(); const view = new Page(); let complete = true;
  const note = {
    archonQuestFinished: () => complete, archonQuestMainText: () => complete ? '全部完成' : '进行中',
    archonQuestSubText: () => complete ? '所有魔神任务已完成' : '接口返回的当前章节',
    formattedResin: () => '', resinRecoveryTargetText: () => '', currentResin: 0, maxResin: 200,
    formattedHomeCoin: () => '', homeCoinRecoveryTargetText: () => '', currentHomeCoin: 0, maxHomeCoin: 2400,
    formattedTask: () => '', extraTaskRewardDescription: () => '', finishedTaskNum: 0, totalTaskNum: 4,
    formattedResinDiscount: () => '', resinDiscountUsedNum: () => 0, resinDiscountNumLimit: 3,
    transformerMainText: () => '', transformerSubText: () => '', transformerElapsedSecond: () => 0,
  };
  const finished = view.cardRows({ note, archonProgress: 54, archonTotal: 54, archonChapterText: '' })[0];
  assert.equal(finished.main, '全部完成'); assert.equal(finished.progress, finished.max);
  assert.equal(finished.showProgress, true);
  complete = false;
  const ongoing = view.cardRows({ note, archonProgress: 52, archonTotal: 54, archonChapterText: '元数据章节名' })[0];
  assert.equal(ongoing.main, '进行中'); assert.equal(ongoing.sub, '元数据章节名');
  assert.equal(ongoing.progress, 52); assert.equal(ongoing.max, 54); assert.equal(ongoing.showProgress, true);
  const unknown = view.cardRows({ note, archonProgress: -1, archonTotal: 54, archonChapterText: '' })[0];
  assert.equal(unknown.sub, '接口返回的当前章节'); assert.equal(unknown.showProgress, false);
});
