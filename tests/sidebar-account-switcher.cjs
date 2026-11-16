const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'components/SidebarAccountSwitcher.ets'), 'utf8').replaceAll('\r\n', '\n');
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};

function harness() {
  const state = { constructors: [], listeners: new Set(), loads: 0, calls: [], routes: [], openedAccounts: 0,
    selected: 1, loadGate: undefined, actionGate: undefined };
  class AccountModel {
    constructor(autoLoadRoleAvatars) {
      state.constructors.push(autoLoadRoleAvatars);
      this.roles = []; this.users = []; this.message = ''; this.active = true;
    }
    async load() {
      state.loads++;
      if (state.loadGate) await state.loadGate.promise;
      if (!this.active) return;
      this.currentUser = { id: state.selected };
      this.currentAccount = { id: state.selected, canSwitch: true };
    }
    watchSession(listener) { state.listeners.add(listener); return () => state.listeners.delete(listener); }
    dispose() { this.active = false; }
    async switchUser(id) {
      state.calls.push(['user', id]);
      if (state.actionGate) await state.actionGate.promise;
      state.selected = id;
      for (const listener of [...state.listeners]) listener();
    }
    async setDefaultUid(uid, userId) {
      if (userId !== state.selected) throw new Error('当前账号已变化，请重试');
      state.calls.push(['role', userId, uid]);
    }
    async refreshCredentials() {
      state.calls.push(['cookie', state.selected]);
      if (state.actionGate) await state.actionGate.promise;
      return true;
    }
    canOpenTravelTools() { return this.currentUser !== undefined; }
  }
  const methods = source.slice(0, source.indexOf('  @Builder')) +
    source.slice(source.indexOf('  private actionLabel('), source.indexOf('  @Builder\n  actionButton(')) + '}';
  const compiled = ts.transpileModule(methods.replace('@Component\n', '').replace('export struct ', 'export class '), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, experimentalDecorators: true },
    reportDiagnostics: true,
  });
  assert.equal(compiled.diagnostics.length, 0);
  const module = { exports: {} };
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports,
    Prop() {}, State() {}, StorageProp: () => () => {}, Watch: () => () => {},
    require: id => id.endsWith('/UserViewModel') ? { UserViewModel: AccountModel }
      : id.endsWith('/Constants') ? { RegionUtil: { isCnUid: uid => /^[125][0-9]{8}$/.test(uid) } } : {},
  });
  const panel = new module.exports.SidebarAccountSwitcher();
  panel.onOpenAccounts = () => { state.openedAccounts++; };
  panel.getUIContext = () => ({ getRouter: () => ({ pushUrl: async options => { state.routes.push(options); } }) });
  panel.aboutToAppear();
  return { panel, state };
}

test('opening and dismissing the popup bounds local loads and subscriptions independently of native lifecycle', async () => {
  const { panel, state } = harness();
  assert.equal(state.loads, 0);
  assert.equal(state.listeners.size, 0);
  panel.open();
  await tick();
  assert.equal(panel.popupVisible, true);
  assert.equal(state.loads, 1);
  assert.equal(state.listeners.size, 1);
  panel.open();
  assert.equal(panel.popupVisible, false);
  assert.equal(state.listeners.size, 0);
  panel.open();
  await tick();
  assert.equal(state.listeners.size, 1);
  panel.appForeground = false; panel.foregroundChanged();
  assert.equal(panel.popupVisible, false);
  assert.equal(state.listeners.size, 0);
  panel.aboutToDisappear();
  assert.ok(state.constructors.every(value => value === false));
});

test('a closed popup cannot publish an old read into the next opening', async () => {
  const { panel, state } = harness();
  const old = deferred();
  state.loadGate = old;
  panel.open();
  const previous = panel.vm;
  panel.dismiss();
  const current = deferred();
  state.loadGate = current;
  panel.open();
  old.resolve();
  await tick();
  assert.equal(panel.loading, true);
  assert.equal(previous.currentUser, undefined);
  current.resolve();
  await tick();
  assert.equal(panel.loading, false);
  assert.equal(panel.vm.currentUser.id, 1);
  panel.aboutToDisappear();
});

test('selection uses the existing account and role commands and blocks duplicate or unsupported actions', async () => {
  const { panel, state } = harness();
  panel.open(); await tick();
  panel.selectUser({ id: 1, canSwitch: true, isSelected: true });
  panel.selectUser({ id: 2, canSwitch: false, isSelected: false });
  panel.selectUser({ id: 3, canSwitch: true, isSelected: false, isOversea: true });
  panel.selectRole({ userId: 1, gameUid: '800000001', canRefreshAvatar: false, isDefault: false });
  assert.equal(state.calls.length, 0);
  state.actionGate = deferred();
  panel.selectUser({ id: 2, canSwitch: true, isSelected: false });
  panel.selectUser({ id: 3, canSwitch: true, isSelected: false });
  panel.refreshCookie();
  assert.equal(panel.busy, true);
  assert.equal(panel.actionEnabled(0), false);
  assert.deepEqual(state.calls, [['user', 2]]);
  state.actionGate.resolve(); await tick();
  assert.equal(panel.busy, false);
  assert.equal(panel.vm.currentUser.id, 2);
  panel.selectRole({ userId: 2, gameUid: '100000002', canRefreshAvatar: true, isDefault: false });
  await tick();
  assert.deepEqual(state.calls.at(-1), ['role', 2, '100000002']);
  const count = state.calls.length;
  panel.selectRole({ userId: 1, gameUid: '100000001', canRefreshAvatar: true, isDefault: false });
  await tick();
  assert.equal(state.calls.length, count, 'a stale row cannot change another account');
  panel.aboutToDisappear();
});

test('cookie refresh stays explicit and a late result cannot report into a reopened panel', async () => {
  const { panel, state } = harness();
  assert.equal(panel.actionEnabled(1), false);
  panel.open(); await tick();
  assert.equal(state.calls.length, 0);
  state.actionGate = deferred();
  panel.refreshCookie();
  assert.deepEqual(state.calls, [['cookie', 1]]);
  panel.dismiss(); panel.open(); await tick();
  panel.refreshCookie();
  assert.equal(state.calls.length, 1);
  state.actionGate.resolve(); await tick();
  assert.equal(panel.message, '');
  assert.equal(panel.busy, false);
  panel.refreshCookie(); await tick();
  assert.equal(panel.message, 'Cookie 已刷新');
  panel.aboutToDisappear();
});

test('toolbox, login and the complete account page close the popup before navigating', async () => {
  const { panel, state } = harness();
  panel.open(); await tick();
  panel.openToolbox();
  assert.equal(panel.popupVisible, false);
  assert.equal(state.listeners.size, 0);
  assert.equal(state.routes[0].url, 'pages/OfficialWebPage');
  assert.equal(state.routes[0].params.kind, 'toolbox');
  panel.open(); await tick();
  panel.openAccounts();
  assert.equal(state.openedAccounts, 1);
  assert.equal(state.listeners.size, 0);
  panel.open(); await tick();
  panel.openLogin();
  assert.equal(state.routes[1].url, 'pages/LoginPage');
  panel.aboutToDisappear();
});

test('the footer stays outside navigation scrolling with one settings entry and observable avatar rendering', () => {
  const index = fs.readFileSync(path.join(root, 'pages/Index.ets'), 'utf8');
  const navigation = index.slice(index.indexOf('  sideNav()'), index.indexOf('  navItemHome(', index.indexOf('  sideNav()')));
  assert.equal((navigation.match(/this\.navItem\(13,/g) ?? []).length, 1);
  assert.ok(navigation.indexOf('SidebarAccountSwitcher(') > navigation.indexOf('.scrollBar(BarState.Off)'));
  assert.match(navigation, /onOpenAccounts: \(\): void => \{ this\.switchTo\(12\); \}/);
  assert.match(source, /\.bindPopup\(this\.popupVisible,/);
  assert.match(source, /systemMaterial: UiSurface\.dialogMaterial\(this\.surfaceMode, this\.surfaceLevel\)/);
  assert.match(source, /\.accessibilitySelected\(role\.isDefault\)/);
  assert.match(source, /\.accessibilitySelected\(user\.isSelected\)/);
  assert.match(source, /this\.footerAvatar\(\)/);
  assert.doesNotMatch(source, /this\.avatar\(this\.currentUserAvatar,/);
});
