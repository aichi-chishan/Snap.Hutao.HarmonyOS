// Execute page-owned view/dispatch handlers. Native layout is checked by the shared HAP/device pass.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/pages/CharacterPage.ets', 'utf8').replace(/\r\n/g, '\n');

function method(name) {
  const start = source.search(new RegExp('  private (?:async )?' + name + '\\('));
  assert(start >= 0, name);
  let depth = 0;
  for (let i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw Error('Unclosed handler: ' + name);
}

// Run the page's actual MenuItem enablement and click callbacks without the native Menu container.
function menuMethod(name) {
  const start = source.indexOf('  ' + name + '(');
  const menu = source.indexOf('    Menu() {', start);
  const end = source.indexOf('\n    }', menu);
  assert.ok(start >= 0 && menu > start && end > menu, name);
  return source.slice(start, menu) + source.slice(menu + '    Menu() {'.length, end) + '\n  }';
}

function buttonMethod(name) {
  const start = source.indexOf('  ' + name + '() {');
  const end = source.indexOf('\n  }', start);
  assert.ok(start >= 0 && end > start, name);
  return source.slice(start, end + '\n  }'.length);
}
function harness() {
  const calls = [], preferences = new Map();
  const state = { networkGate: undefined, clipboard: [], messages: [], menu: new Map() };
  function control(label) {
    const item = {
      available: true,
      enabled(value) { this.available = value; return this; },
      onClick(action) { this.action = action; return this; },
      attributeModifier() { return this; }, fontSize() { return this; }, height() { return this; },
    };
    state.menu.set(label, item);
    return item;
  }
  class CharacterModel {
    constructor() { this.items = []; this.detailMap = new Map(); this.selectedId = 0; this.scoreLoads = 0; }
    activate(onUpdated) { this.onUpdated = onUpdated; }
    dispose() { this.onUpdated = undefined; }
    async load() {
      this.selectedId = this.selectedId || this.items[0]?.id || 0;
      this.onUpdated?.();
      if (state.networkGate) {
        await state.networkGate.promise;
        this.items = this.items.map(item => ({ ...item, level: 90 }));
        this.onUpdated?.();
      }
    }
    filteredItems(tokens, sort) {
      const visible = this.items.filter(item => !tokens.length || tokens.some(token => item.name.includes(token.value)));
      return sort === 1 ? visible.sort((left, right) => right.level - left.level) : visible;
    }
    async select(uid, id) { calls.push(['select', uid, id]); this.selectedId = id; }
    detailOfSelected() { return this.items.find(item => item.id === this.selectedId); }
    loadScoreOptions() { this.scoreLoads++; }
    scoreWeights() { return undefined; }
  }
  class DraftModel {
    busy = false;
    cancel() {}
    characters(uid, items, weaponOnly) { calls.push(['single', uid, items, weaponOnly]); return Promise.resolve(); }
    characterAndWeapon(uid, item) { calls.push(['combined', uid, item]); return Promise.resolve(); }
    batchCharacters(uid, items) { calls.push(['batch', uid, items]); return Promise.resolve(); }
  }
  const dependencies = {
    CharacterViewModel: { CharacterViewModel: CharacterModel, CharacterSortKind: { Default: 0, Level: 1 } },
    CharacterExportService: { CharacterExportService: { buildExportText: detail => detail.name } },
    '@kit.BasicServicesKit': { pasteboard: { MIMETYPE_TEXT_PLAIN: 'text/plain', createData: (_type, text) => text,
      getSystemPasteboard: () => ({ setData: async text => { state.clipboard.push(text); } }) } },
    CultivationDraftViewModel: { CultivationDraftViewModel: DraftModel },
    BackpackScore: { BackpackScoreEdit: class {} },
    PreferencesStore: { PreferencesStore: { setNumber: (key, value) => preferences.set(key, value),
      getNumber: (key, fallback) => preferences.get(key) ?? fallback } },
    Logger: { Logger: { info() {}, warn() {} } },
    RiskUiHelper: { RiskUiHelper: { hasPendingChallenge: () => false } },
    WikiMetaService: { WikiMetaService: { avatarOf: () => undefined, ensureIconMaps: async () => {} } },
    LocalizedGameDataService: { LocalizedGameDataService: { names: async () => new Map() } },
    SkillLevelService: { SkillLevelService: {} },
    UiSurface: { UiSurface: { dialogMaterial: () => undefined }, AppButtonModifier: class {} },
  };
  const text = source.slice(0, source.indexOf('  @Builder'))
    .replace(/@Entry\s*@Component\s*export struct CharacterPage/, 'export class CharacterPage') +
    ['addCurrentToPlan', 'openCharacterDraft', 'addCurrentWithWeapon', 'openBatchCharacterDraft',
      'exportDetailText', 'exportAllText'].map(method).join('\n') +
    ['exportMenu', 'cultivationMenu', 'rosterActions'].map(menuMethod).join('\n') +
    buttonMethod('planSelectionActions') + '\n}';
  const output = ts.transpileModule(text, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true
  }, reportDiagnostics: true });
  assert.equal(output.diagnostics.filter(entry => entry.category === ts.DiagnosticCategory.Error).length, 0);
  const module = { exports: {} };
  const decorator = () => () => {};
  vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`, {
    State() {}, Prop() {}, StorageProp: decorator, StorageLink: decorator, Watch: decorator,
    Scroller: class { scrollEdge() {} }, Edge: { Top: 0 },
    $r: key => key, ButtonType: { Normal: 0 },
    MenuItem: ({ content }) => control(content), Button: label => control(label),
  })(id => {
    const key = id.slice(id.lastIndexOf('/') + 1);
    if (dependencies[key]) return dependencies[key];
    throw Error('Unexpected runtime dependency: ' + id);
  }, module, module.exports);
  const page = new module.exports.CharacterPage();
  page.attached = true; page.currentUid = '100000001';
  page.toast = message => state.messages.push(message);
  page.vm.items = [{ id: 10000021, name: 'Alpha', level: 60 }, { id: 10000046, name: 'Beta', level: 80 }];
  return { page, calls, preferences, state };
}
const flush = async () => { for (let i = 0; i < 5; i++) await Promise.resolve(); };
function deferred() { let resolve; const promise = new Promise(yes => { resolve = yes; }); return { promise, resolve }; }

test('page subscribes before loading and publishes cached detail without waiting for network completion', async () => {
  const h = harness(); h.state.networkGate = deferred();
  h.page.aboutToAppear();
  assert.equal(h.page.currentDetail.level, 60, 'cached detail reaches the page immediately');
  assert.equal(h.page.vm.scoreLoads, 1);
  h.state.networkGate.resolve(); await flush();
  assert.equal(h.page.currentDetail.level, 90, 'the successful background result replaces visible detail');
  assert.equal(h.page.vm.scoreLoads, 1, 'same-role refresh does not reparse score settings per batch');
});

test('page detachment releases the progress callback and ignores a retained callback after a late response', async () => {
  const h = harness(); h.state.networkGate = deferred();
  h.page.aboutToAppear();
  const callback = h.page.vm.onUpdated;
  const previous = h.page.currentDetail;
  h.page.aboutToDisappear(); h.state.networkGate.resolve(); await flush();
  callback();
  assert.equal(h.page.vm.onUpdated, undefined);
  assert.equal(h.page.currentDetail, previous);
});

test('view mode starts as list and changes only its dedicated Windows layout preference', () => {
  const h = harness(); assert.equal(h.page.showGrid, false);
  h.page.selectView(true); assert.equal(h.page.showGrid, true);
  assert.equal(h.preferences.get('Control.PanelSelector.AvatarPropertyPage.Summary.Avatars'), 1);
  h.page.selectView(false); assert.equal(h.preferences.size, 1);
  assert.equal(h.preferences.get('Control.PanelSelector.AvatarPropertyPage.Summary.Avatars'), 0);
});

test('filtering selects a visible character without opening phone detail; multi-selection preserves inspection state', async () => {
  const h = harness(); h.page.selectedId = 10000021;
  h.page.currentDetail = h.page.vm.items[0]; h.page.charTokens = [{ kind: 0, value: 'Beta', label: 'Beta' }];
  h.page.keepFilteredSelection(); await flush();
  assert.equal(h.page.selectedId, 10000046); assert.equal(h.page.currentDetail.name, 'Beta');
  assert.equal(h.page.showMobileDetail, false);
  h.page.selectingForPlan = true; h.page.activateRosterItem(h.page.vm.items[0]);
  assert.equal(h.page.planSelectedIds.length, 1); assert.equal(h.page.selectedId, 10000046);
  h.page.selectingForPlan = false; h.page.activateRosterItem(h.page.vm.items[0]); await flush();
  assert.equal(h.page.showMobileDetail, true); assert.equal(h.page.onBackPress(), true);
  assert.equal(h.page.showMobileDetail, false); assert.equal(h.page.onBackPress(), false);
});

test('single, weapon-only, combined and common-target actions dispatch distinct existing draft APIs', async () => {
  const h = harness(); h.page.selectedId = 10000021;
  h.page.addCurrentToPlan(); h.page.addCurrentToPlan(true); h.page.addCurrentWithWeapon();
  h.page.openBatchCharacterDraft(h.page.vm.items); await flush();
  assert.deepEqual(h.calls.map(call => call[0]), ['single', 'single', 'combined', 'batch']);
  assert.equal(h.calls[0][3], false); assert.equal(h.calls[1][3], true);
  assert.equal(h.calls[2][2].id, 10000021);
  assert.notEqual(h.calls[3][2], h.page.vm.items); assert.equal(h.calls[3][2].length, 2);
  assert.equal(h.page.showPlanSheet, true);
  h.page.draftVm.busy = true; h.page.addCurrentWithWeapon(); h.page.openBatchCharacterDraft(h.page.vm.items);
  assert.equal(h.calls.length, 4, 'an in-progress draft is not replaced by a repeat action');
});

test('changing the sort persists the Windows preference and selects the first visible result', async () => {
  const h = harness();
  h.page.charTokens = [{ kind: 0, value: 'a', label: 'a' }];
  h.page.selectSort(1);
  await flush();
  assert.equal(h.preferences.get('Snap::Hutao::AvatarProperty::SortDescriptionKind'), 1);
  assert.equal(h.page.selectedId, h.page.vm.items[1].id);
  assert.equal(h.page.showMobileDetail, false);
  h.page.charSort = 0;
  h.page.aboutToAppear();
  assert.equal(h.page.charSort, 1);
});

test('the clipboard menu exports the current role or the complete sorted filter result', async () => {
  const h = harness();
  const [alpha, beta] = h.page.vm.items;
  const another = { id: 10000048, name: 'Alpha Prime', level: 90 };
  h.page.vm.items.push(another);
  for (const item of [alpha, beta, another]) { h.page.vm.detailMap.set(item.id, item); }
  h.page.currentDetail = alpha;
  h.page.charTokens = [{ kind: 0, value: 'Alpha', label: 'Alpha' }];
  h.page.charSort = 1;
  h.page.exportMenu();
  assert.deepEqual(h.state.clipboard, [], 'opening the menu must wait for an explicit export choice');
  assert.equal(h.state.menu.get('导出当前角色').available, true);
  await h.state.menu.get('导出当前角色').action();
  await h.state.menu.get('导出所有角色').action();
  assert.deepEqual(h.state.clipboard, ['Alpha', 'Alpha Prime\n\nAlpha']);
  h.page.vm.detailMap.delete(another.id);
  await h.state.menu.get('导出所有角色').action();
  assert.equal(h.state.clipboard.length, 2, 'incomplete visible details must not replace the previous clipboard');
  assert.match(h.state.messages.at(-1), /缺少详情/);
});

test('the cultivation menu offers the current pair, a manual selection, and the full roster', async () => {
  const h = harness();
  h.page.charTokens = [{ kind: 0, value: 'Beta', label: 'Beta' }];
  h.page.selectedId = h.page.vm.items[1].id;
  h.page.cultivationMenu();
  h.state.menu.get('当前角色与武器').action();
  assert.equal(h.calls[0][0], 'combined');
  assert.equal(h.calls[0][2].id, h.page.selectedId);
  h.state.menu.get('部分角色与武器').action();
  assert.equal(h.page.selectingForPlan, true);
  assert.equal(h.page.planSelectedIds.length, 0);
  h.state.menu.get('所有角色与武器').action();
  assert.deepEqual(Array.from(h.calls.at(-1)[2], item => item.id), h.page.vm.items.map(item => item.id));
});

test('confirming a partial plan opens one editable draft for exactly the checked roles; cancel opens none', () => {
  const h = harness();
  const [a, b] = h.page.vm.items;
  const c = { id: 10000048, name: 'Gamma', level: 70 };
  h.page.vm.items.push(c);
  h.page.selectedId = b.id;
  h.page.cultivationMenu();
  const partial = h.state.menu.get('部分角色与武器');
  partial.action();
  h.page.planSelectionActions();
  assert.equal(h.state.menu.get('规划所选角色').available, false);
  h.page.activateRosterItem(a);
  h.page.activateRosterItem(c);
  h.page.charTokens = [{ kind: 0, value: 'Gamma', label: 'Gamma' }];
  h.page.planSelectionActions();
  const confirm = h.state.menu.get('规划所选角色');
  assert.equal(confirm.available, true);
  confirm.action();
  assert.equal(h.calls.length, 1);
  assert.deepEqual(h.calls[0].slice(0, 2), ['batch', '100000001']);
  assert.deepEqual(Array.from(h.calls[0][2], item => item.id), [a.id, c.id]);
  assert.equal(h.page.selectedId, b.id, 'planning selection is independent of inspecting a role');
  assert.equal(h.page.showPlanSheet, true);
  assert.equal(h.page.selectingForPlan, false);
  confirm.action();
  assert.equal(h.calls.length, 1, 'the consumed selection cannot be dispatched twice');
  h.page.showPlanSheet = false;
  partial.action();
  h.page.activateRosterItem(b);
  h.page.planSelectionActions();
  h.state.menu.get('app.string.common_cancel').action();
  assert.equal(h.calls.length, 1);
  assert.equal(h.page.planSelectedIds.length, 0);
  assert.equal(h.page.showPlanSheet, false);
});

test('the row menu prepares the clicked role, its weapon or both, independently of the inspected role', () => {
  const h = harness();
  const [inspected, clicked] = h.page.vm.items;
  h.page.selectedId = inspected.id;
  h.page.rosterActions(clicked);
  h.state.menu.get('添加角色到养成计划').action();
  h.state.menu.get('添加武器到养成计划').action();
  h.state.menu.get('添加角色与武器到养成计划').action();
  assert.deepEqual(h.calls.map(call => call[0]), ['single', 'single', 'combined']);
  assert.deepEqual(h.calls.slice(0, 2).map(call => [call[2][0].id, call[3]]),
    [[clicked.id, false], [clicked.id, true]]);
  assert.equal(h.calls[2][2].id, clicked.id);
  assert.equal(h.page.selectedId, inspected.id);
  assert.equal(h.page.showPlanSheet, true);
});
