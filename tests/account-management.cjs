const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const { accepted, boundRole, boundRoles, defaultNetwork, deferred, flush, harness, selected } =
  require('./account-session-ownership.cjs');

const expired = { success:false, retcode:-100, message:'fixture expired' };
const root = path.resolve(__dirname, '../entry/src/main/ets');

test('account action menu follows the active material mode and level', () => {
  const source = fs.readFileSync(path.join(root, 'pages/UserPage.ets'), 'utf8');
  assert.match(source, /\.bindMenu\(this\.accountMenu\(user\),\s*\{\s*systemMaterial:\s*UiSurface\.dialogMaterial\(this\.surfaceMode,\s*this\.surfaceLevel\)\s*\}\)/);
});

test('shared account controls use existing localized resources', () => {
  const source = fs.readFileSync(path.join(root, 'pages/UserPage.ets'), 'utf8');
  const names = [...source.matchAll(/\$r\('app\.string\.([^']+)'\)/g)].map(match => match[1]);
  for (const key of ['ui_section_account', 'ui_settings_not_logged_in', 'page_title_login', 'common_cancel',
    'ui_user_copy_cookie_action', 'ui_account_insights_delete', 'ui_setting_control_material_default',
    'ui_setting_hutao_passport_logout_action', 'ui_content_dialog_complete_primary_button_text']) {
    assert.ok(names.includes(key), key);
  }
  for (const locale of ['base', 'en']) {
    const files = ['ui_strings.json', 'ui_labels.json', ...(locale === 'base' ? ['string.json'] : [])];
    const resources = files.flatMap(file => JSON.parse(fs.readFileSync(
      path.resolve(root, '../resources', locale, 'element', file), 'utf8')).string);
    assert.ok(names.every(name => resources.some(resource => resource.name === name)), locale);
  }
});

test('the sidebar account view reads saved accounts and cached role icons without starting profile requests', async () => {
  const h = harness();
  h.user(1); h.user(2);
  await h.seed();
  let profileRequests = 0;
  h.state.rolePictures.loadIcon = async () => { profileRequests++; return ''; };
  const { UserViewModel } = h.load('viewmodel/UserViewModel');
  const sidebar = new UserViewModel(false);
  const requests = h.state.requests.length;
  await sidebar.load();
  assert.equal(sidebar.users.length, 2);
  assert.equal(profileRequests, 0);
  assert.equal(h.state.requests.length, requests);
  await sidebar.switchUser(2);
  selected(h, 2, '100000002');
  assert.equal(profileRequests, 0, 'switch completion keeps the local-only view policy');
  assert.equal(h.state.requests.length, requests, 'switching valid saved credentials performs no profile fetch');
  const accountPage = new UserViewModel();
  await accountPage.load();
  await flush();
  assert.ok(profileRequests > 0, 'the complete account page retains its existing missing-avatar behavior');
  sidebar.dispose(); accountPage.dispose();
});

test('copied credentials keep Cookie names, IDs and v2 values and can update the same account', async () => {
  const h = harness();
  const user = h.user(1);
  const raw = 'stuid=11; stoken=fixture-v1; stuid_v2=11; stoken_v2=fixture=v2; mid=fixture-mid-1; account_id_v2=11; cookie_token_v2=fixture-cookie; ltuid_v2=11; ltoken_v2=fixture-ltoken';
  assert.equal(user.applyCookie(raw), true);
  h.state.rows.set(1, h.copy(user));
  await h.seed();
  const view = new (h.load('viewmodel/UserViewModel').UserViewModel)();
  await view.load();
  const cookie = view.cookieForClipboard();
  const copied = h.service.parseCookie(cookie);
  assert.equal(copied.stokenV2, 'fixture=v2');
  assert.equal(copied.stuidV2, '11');
  assert.equal(copied.mid, 'fixture-mid-1');
  assert.equal(copied.cookieTokenV2, 'fixture-cookie');
  assert.equal(copied.ltokenV2, 'fixture-ltoken');
  assert.equal(Object.keys(view.users[0]).some(key => /token|cookie/i.test(key)), false);
  const readded = await h.service.loginWithCookie(cookie, 'updated', 'avatar');
  assert.equal(readded.id, 1);
  assert.equal(h.state.rows.size, 1);
  assert.deepEqual(h.state.ticketRequests[0], {
    cookie:'stoken_v2=fixture=v2; stuid_v2=11; mid=fixture-mid-1', token:'fixture=v2', uid:'11'
  });
  selected(h, 1, '100000001');
});

test('copying an unselected account uses its saved credentials without switching and drops deleted reads', async () => {
  const h = harness();
  const current = await h.seed();
  const other = h.user(2);
  const view = new (h.load('viewmodel/UserViewModel').UserViewModel)();
  await view.load();
  assert.equal(await view.savedCookieForClipboard(2), other.fullCookie());
  assert.equal(h.service.getCurrentUser(), current);
  assert.equal(h.state.requests.length, 0);
  selected(h, 1, '100000001');
  const gate = h.gate('read', 2);
  const copy = view.savedCookieForClipboard(2);
  const rejected = assert.rejects(copy, /账号状态已变化/);
  await flush();
  await h.service.deleteUser(2);
  gate.resolve();
  await rejected;
  selected(h, 1, '100000001');
});

test('moving account rows persists order, appends new rows and controls deletion fallback', async () => {
  const h = harness();
  const owner = await h.seed();
  h.user(2);
  h.user(3);
  h.state.order = [99, 3, 1];
  const Model = h.load('viewmodel/UserViewModel').UserViewModel;
  const view = new Model();
  const ids = rows => Array.from(rows, user => user.id);
  await view.load();
  assert.deepEqual(ids(view.users), [3,1,2]);
  assert.equal(view.users[0].canMoveUp, false);
  assert.equal(view.users[2].canMoveDown, false);
  const revision = h.service.sessionRevision();
  await view.moveUser(2, -1);
  assert.deepEqual(h.state.order, [3,2,1]);
  assert.deepEqual(ids(view.users), [3,2,1]);
  assert.equal(h.service.sessionRevision(), revision);
  assert.equal(h.service.getCurrentUser(), owner);
  selected(h, 1, '100000001');
  h.user(4);
  const reopened = new Model();
  await reopened.load();
  assert.deepEqual(ids(reopened.users), [3,2,1,4]);
  await reopened.moveUser(3, 1);
  await reopened.deleteUser(1);
  assert.deepEqual(ids(reopened.users), [2,3,4]);
  selected(h, 2, '100000002');
});

test('CN login fails before publication on missing SToken, failed exchange, failed roles, or no bound CN roles', async () => {
  const h = harness();
  const owner = await h.seed();
  const before = owner.fullCookie();
  await assert.rejects(h.service.loginWithCookie('account_id=21; cookie_token=fixture; ltuid=21', '', ''), /SToken/);
  assert.equal(h.state.requests.length, 0);
  h.state.network = async url => url.includes('getCookieAccountInfo') ? expired : accepted({ ltoken:'fixture' });
  await assert.rejects(h.service.loginWithSession('22','fixture','other-mid','name'), /完整登录凭证/);
  h.state.network = async (url, headers) => url === 'fixture-roles' ? expired : defaultNetwork(url, headers);
  await assert.rejects(h.service.loginWithSession('22','fixture','other-mid','name'), /登录态已失效/);
  h.state.network = async (url, headers) => url === 'fixture-roles'
    ? accepted({ list:[{ ...boundRole('800000001'), region:'os_asia' }] }) : defaultNetwork(url, headers);
  await assert.rejects(h.service.loginWithSession('22','fixture','other-mid','name'), /没有绑定国服/);
  assert.equal(h.state.rows.size, 1);
  assert.equal(h.service.getCurrentUser(), owner);
  assert.equal(h.state.rows.get(1).fullCookie(), before);
  selected(h, 1, '100000001');
});

test('same-MID re-add keeps wholly omitted complete groups and replaces only SToken', async () => {
  const h = harness();
  const previous = await h.seed();
  const exchangeTime = h.state.cookieTimes.get(1);
  h.state.network = async url => url === 'fixture-roles' ? boundRoles() : expired;
  const updated = await h.service.loginWithSession('11', 'fixture-replaced-stoken', 'fixture-mid-1', 'name');
  assert.equal(updated.id, 1);
  assert.equal(updated.stoken, 'fixture-replaced-stoken');
  assert.equal(updated.cookieToken, previous.cookieToken);
  assert.equal(updated.ltoken, previous.ltoken);
  assert.equal(h.state.cookieTimes.get(1), exchangeTime);
  assert.deepEqual(h.state.requests.map(request => request.url), ['fixture-roles']);
  selected(h, 1, '100000001');

  await assert.rejects(h.service.loginWithSession('11', 'fixture-no-mid', '', 'name'), /完整登录凭证/);
  assert.equal(h.service.getCurrentUser(), updated);
  assert.equal(h.state.rows.get(1).stoken, 'fixture-replaced-stoken');
});

test('explicit partial token groups renew as a pair and never inherit a missing member', async () => {
  const cases = [
    ['account_id=11', 'getCookieAccountInfoBySToken'],
    ['cookie_token=fixture-partial', 'getCookieAccountInfoBySToken'],
    ['account_id=11; cookie_token_v2=fixture-partial', 'getCookieAccountInfoBySToken'],
    ['ltuid=77', 'getLTokenBySToken'],
    ['ltoken=', 'getLTokenBySToken'],
    ['ltuid=77; ltoken_v2=fixture-partial', 'getLTokenBySToken']
  ];
  for (const [group, endpoint] of cases) {
    const h = harness();
    const previous = await h.seed();
    h.state.network = async () => expired;
    const raw = `stuid=11; stoken=fixture-replaced-stoken; mid=fixture-mid-1; ${group}`;
    await assert.rejects(h.service.loginWithCookie(raw, '', ''), /完整登录凭证/);
    assert.equal(h.state.requests.length, 1);
    assert.ok(h.state.requests[0].url.endsWith(endpoint));
    assert.equal(h.state.rows.get(1).fullCookie(), previous.fullCookie());
    selected(h, 1, '100000001');
  }

  const h = harness();
  await h.seed();
  const repaired = await h.service.loginWithCookie('stuid=11; stoken=fixture; mid=fixture-mid-1; ltuid=77', '', '');
  assert.equal(repaired.ltuid, '11');
  assert.equal(repaired.ltoken, 'fixture-ltoken-rotated');
  assert.equal(repaired.cookieToken, 'fixture-cookie-1');
});

test('local restore precedes deferred CookieToken renewal and preserves durable freshness', async () => {
  for (const initial of [undefined, Date.now() - 25 * 60 * 60 * 1000]) {
    const h = harness();
    h.user(1);
    h.state.prefsId = 1;
    if (initial === undefined) h.state.cookieTimes.delete(1);
    else h.state.cookieTimes.set(1, initial);
    const start = Date.now();
    assert.equal(await h.service.restoreSession(), true);
    assert.equal(h.state.requests.length, 0, 'first screen does not wait for token exchange');
    await h.service.refreshSession();
    assert.equal(h.state.requests.length, 1);
    assert.ok(h.state.requests[0].url.endsWith('getCookieAccountInfoBySToken'));
    assert.equal(h.state.rows.get(1).cookieToken, 'fixture-rotated');
    assert.equal(h.state.rows.get(1).ltoken, 'fixture-ltoken-1');
    assert.ok(h.state.cookieTimes.get(1) >= start);
    selected(h, 1, '100000001');
    assert.equal(await h.service.restoreSession(), true);
    await h.service.refreshSession();
    assert.equal(h.state.requests.length, 1);
  }
});

test('offline restore keeps valid saved credentials and failed persistence does not mark freshness', async () => {
  const h = harness();
  const previous = h.user(1);
  h.state.prefsId = 1;
  h.state.cookieTimes.delete(1);
  h.state.network = async () => { throw Error('fixture offline'); };
  assert.equal(await h.service.restoreSession(), true);
  assert.equal(h.state.requests.length, 0);
  await h.service.refreshSession();
  assert.equal(h.state.requests.length, 1);
  assert.equal(h.state.rows.get(1).fullCookie(), previous.fullCookie());
  assert.equal(h.state.cookieTimes.has(1), false);
  selected(h, 1, '100000001');

  h.state.network = undefined;
  h.state.fail = 'cookie';
  assert.equal(await h.service.restoreSession(), true);
  await assert.rejects(h.service.refreshSession());
  assert.equal(h.state.rows.get(1).fullCookie(), previous.fullCookie());
  assert.equal(h.state.cookieTimes.has(1), false);
  selected(h, 1, '100000001');
});

test('deferred startup credentials cannot overwrite a later selected account', async () => {
  const h = harness();
  h.user(1); h.user(2); h.state.prefsId = 1; h.state.cookieTimes.delete(1);
  await h.service.restoreSession();
  const gate = deferred();
  h.state.network = async () => gate.promise;
  const updating = h.service.refreshSession();
  await flush();
  selected(h, 1, '100000001');
  assert.equal(h.service.isSessionTransitionPending(), false, 'local account is usable during renewal');
  await h.service.switchUser(2);
  gate.resolve(accepted({ uid: '11', cookie_token: 'fixture-late-cookie' }));
  await assert.rejects(updating, /账号状态已变化/);
  selected(h, 2, '100000002');
  assert.notEqual(h.state.rows.get(1).cookieToken, 'fixture-late-cookie');
  assert.equal(h.state.cookieTimes.has(1), false);
});

test('startup and ordinary completion share the selected account exchange and publish to every caller', async () => {
  for (const startupFirst of [true, false]) {
    const h = harness();
    const owner = await h.seed();
    const stored = h.state.rows.get(1);
    owner.ltoken = '';
    stored.ltoken = '';
    if (startupFirst) {
      owner.cookieToken = '';
      stored.cookieToken = '';
      owner.aid = '';
      stored.aid = '';
    } else {
      h.state.cookieTimes.set(1, Date.now() - 25 * 60 * 60 * 1000);
    }
    const firstCopy = h.copy(owner);
    const lateCopy = h.copy(owner);
    const revision = h.service.sessionRevision();
    const exchange = deferred();
    const saving = h.gate('cookie', 1);
    h.state.network = (url, headers) => url.includes('getCookieAccountInfo') ? exchange.promise : defaultNetwork(url, headers);
    const first = startupFirst ? h.service.refreshSession() : h.service.completeTokenChainPublic(firstCopy);
    await flush();
    const second = startupFirst ? h.service.completeTokenChainPublic(firstCopy) : h.service.refreshSession();
    await flush();
    assert.equal(h.state.requests.length, 1);
    assert.ok(h.state.requests[0].url.endsWith('getCookieAccountInfoBySToken'));
    exchange.resolve(accepted({ uid: '11', cookie_token: 'fixture-shared-cookie' }));
    await flush();
    const late = h.service.completeTokenChainPublic(lateCopy);
    await flush();
    assert.equal(h.state.requests.length, 2);
    assert.ok(h.state.requests[1].url.endsWith('getLTokenBySToken'));
    assert.equal(h.state.calls.filter(call => call === 'cookie:1').length, 1);
    saving.resolve();
    await Promise.all([first, second, late]);
    for (const user of [owner, firstCopy, lateCopy, h.state.rows.get(1)]) {
      assert.equal(user.cookieToken, 'fixture-shared-cookie');
      assert.equal(user.ltoken, 'fixture-ltoken-rotated');
      assert.equal(user.aid, '11');
    }
    assert.equal(h.service.sessionRevision(), revision);
    selected(h, 1, '100000001');
  }
});

test('settled shared completion permits a retry after an exchange or vault failure', async () => {
  for (const failure of ['exchange', 'vault']) {
    const h = harness();
    const owner = await h.seed();
    owner.cookieToken = '';
    h.state.rows.get(1).cookieToken = '';
    const copy = h.copy(owner);
    const exchange = deferred();
    h.state.network = async () => exchange.promise;
    if (failure === 'vault') h.state.fail = 'cookie';
    const completion = h.service.completeTokenChainPublic(copy);
    const startup = h.service.refreshSession();
    const settled = Promise.allSettled([completion, startup]);
    await flush();
    assert.equal(h.state.requests.length, 1);
    exchange.resolve(failure === 'exchange' ? expired : accepted({ uid: '11', cookie_token: 'fixture-uncommitted' }));
    const results = await settled;
    assert.ok(results.every(result => result.status === (failure === 'exchange' ? 'fulfilled' : 'rejected')));
    assert.equal(copy.cookieToken, '');
    assert.equal(owner.cookieToken, '');
    h.state.network = undefined;
    await h.service.completeTokenChainPublic(copy);
    assert.equal(h.state.requests.length, 2);
    assert.equal(copy.cookieToken, 'fixture-rotated');
    assert.equal(owner.cookieToken, 'fixture-rotated');
    selected(h, 1, '100000001');
  }
});

test('a Cookie expiry during a missing-LToken completion is rechecked after the shared request', async () => {
  const h = harness();
  const owner = await h.seed();
  owner.ltoken = '';
  h.state.rows.get(1).ltoken = '';
  const exchange = deferred();
  h.state.network = (url, headers) => url.includes('getLToken') ? exchange.promise : defaultNetwork(url, headers);
  const first = h.service.completeTokenChainPublic(h.copy(owner));
  await flush();
  assert.equal(h.state.requests.length, 1);
  assert.ok(h.state.requests[0].url.endsWith('getLTokenBySToken'));
  h.state.cookieTimes.set(1, Date.now() - 25 * 60 * 60 * 1000);
  const startup = h.service.refreshSession();
  await flush();
  assert.equal(h.state.requests.length, 1);
  exchange.resolve(accepted({ ltoken: 'fixture-new-ltoken' }));
  await Promise.all([first, startup]);
  assert.equal(h.state.requests.length, 2);
  assert.ok(h.state.requests[1].url.endsWith('getCookieAccountInfoBySToken'));
  assert.equal(owner.cookieToken, 'fixture-rotated');
  assert.equal(owner.ltoken, 'fixture-new-ltoken');
});

test('a late shared request from a previous revision cannot publish or clear the new selected request', async () => {
  const h = harness();
  const oldOwner = await h.seed();
  h.user(2);
  oldOwner.cookieToken = '';
  h.state.rows.get(1).cookieToken = '';
  const oldCopy = h.copy(oldOwner);
  const previous = deferred();
  const current = deferred();
  let requests = 0;
  h.state.network = async () => (++requests === 1 ? previous.promise : current.promise);
  const old = Promise.allSettled([h.service.refreshSession(), h.service.completeTokenChainPublic(oldCopy)]);
  await flush();
  assert.equal(requests, 1);
  await h.service.switchUser(2);
  await h.service.switchUser(1);
  const owner = h.service.getCurrentUser();
  const copy = h.copy(owner);
  const renewed = h.service.completeTokenChainPublic(copy);
  await flush();
  assert.equal(requests, 2);
  previous.resolve(accepted({ uid: '11', cookie_token: 'fixture-old-revision' }));
  for (const result of await old) {
    assert.equal(result.status, 'rejected');
    assert.match(result.reason.message, /账号状态已变化/);
  }
  assert.equal(oldCopy.cookieToken, '');
  assert.equal(oldOwner.cookieToken, '');
  const secondCopy = h.copy(owner);
  const joined = h.service.completeTokenChainPublic(secondCopy);
  await flush();
  assert.equal(requests, 2);
  current.resolve(accepted({ uid: '11', cookie_token: 'fixture-current-revision' }));
  await Promise.all([renewed, joined]);
  assert.equal(copy.cookieToken, 'fixture-current-revision');
  assert.equal(secondCopy.cookieToken, 'fixture-current-revision');
  assert.equal(h.state.rows.get(1).cookieToken, 'fixture-current-revision');
  selected(h, 1, '100000001');
});

test('role refresh preserves preference, uses a server-chosen fallback and keeps cache on failures', async () => {
  const h = harness();
  await h.seed();
  const view = new (h.load('viewmodel/UserViewModel').UserViewModel)();
  await view.load();
  const originalKey = view.roles[0].key();
  const channel = { ...boundRole('500000002'), region:'cn_qd01', is_chosen:true, level:55 };
  h.state.network = async () => accepted({ list:[channel, { ...boundRole(), nickname:'changed' }, boundRole('800000001')] });
  assert.equal(await view.refreshRoles(), 2);
  selected(h, 1, '100000001');
  assert.notEqual(view.roles.find(role => role.isDefault).key(), originalKey);
  assert.equal(view.roles.find(role => role.gameUid === '100000001').nickname, 'changed');
  assert.equal(h.state.rows.get(1).roles.filter(role => role.isChosen).length, 1);

  h.state.network = async () => expired;
  const before = h.state.calls.length;
  await assert.rejects(view.refreshRoles(), /登录态已失效/);
  assert.equal(h.state.calls.length, before);
  selected(h, 1, '100000001');
  assert.equal(view.roles.length, 2);

  h.state.network = async () => accepted({ list:[boundRole('100000009'), channel] });
  assert.equal(await view.refreshRoles(), 2);
  selected(h, 1, '500000002');
  assert.match(view.roles.find(role => role.isDefault).description, /渠道服.*Lv\.55/);

  h.state.network = async () => accepted({ list:[] });
  assert.equal(await view.refreshRoles(), 0);
  selected(h, 1, '');
});

test('selected-account deletion chooses a remaining usable CN account and logout keeps accounts saved', async () => {
  const h = harness();
  await h.seed();
  const overseas = h.user(2, '800000001');
  overseas.isOversea = true;
  overseas.roles[0].region = 'os_asia';
  h.state.rows.set(2, h.copy(overseas));
  const invalid = h.user(3);
  invalid.applyCookie('stuid=13');
  h.state.rows.set(3, h.copy(invalid));
  h.user(4);
  h.user(5);
  const view = new (h.load('viewmodel/UserViewModel').UserViewModel)();
  await view.load();
  const previousKey = view.users.find(user => user.id === 4).key();
  await view.deleteUser(1);
  selected(h, 4, '100000004');
  assert.notEqual(view.users.find(user => user.id === 4).key(), previousKey);
  assert.deepEqual(Array.from(view.users.filter(user => user.isSelected), user => user.id), [4]);
  await view.deleteUser(5);
  selected(h, 4, '100000004');
  await view.logout();
  selected(h, 0, '');
  assert.equal(h.state.rows.has(4), true);
  await view.switchUser(4);
  await view.deleteUser(4);
  selected(h, 0, '');
});

test('legacy overseas records remain saved without permitting login, switching, restore or token requests', async () => {
  const h = harness();
  const user = h.user(1, '800000001');
  user.isOversea = true;
  user.roles[0].region = 'os_asia';
  h.state.rows.set(1, h.copy(user));
  h.state.prefsId = 1;
  assert.equal(await h.service.restoreSession(), false);
  selected(h, 0, '');
  await assert.rejects(h.service.switchUser(1), /国服/);
  await assert.rejects(h.service.loginWithCookie(user.fullCookie(), '', '', true), /国服/);
  assert.equal(await h.service.refreshCookieTokenForced(user), false);
  await assert.rejects(h.service.completeTokenChainPublic(user), /国服/);
  assert.equal(h.state.requests.length, 0);
  assert.equal(h.state.rows.get(1).fullCookie(), user.fullCookie());
  assert.equal(h.state.rows.get(1).roles[0].gameUid, '800000001');
});

test('account view observes a committed same-UID re-login and rejects a stale role action', async () => {
  const h = harness();
  await h.seed();
  h.user(2, '100000001');
  const view = new (h.load('viewmodel/UserViewModel').UserViewModel)();
  await view.load();
  const old = view.roles[0];
  let updates = 0;
  const stop = view.watchSession(() => { updates++; void view.load(); });
  await h.service.switchUser(2);
  await flush();
  await assert.rejects(view.setDefaultUid(old.gameUid, old.userId), /当前账号已变化/);
  await h.service.loginWithCookie(h.service.getCurrentUser().fullCookie(), 'new name', 'avatar');
  await flush();
  assert.equal(updates, 2);
  assert.equal(view.currentAccount.displayName, 'new name');
  assert.equal(view.currentUid, '100000001');
  stop();
  await h.service.logout();
  assert.equal(updates, 2);
});

test('detaching account view invalidates reads and user actions still complete in the service', async () => {
  const h = harness();
  await h.seed();
  h.user(2);
  const view = new (h.load('viewmodel/UserViewModel').UserViewModel)();
  await view.load();
  assert.equal(view.canOpenTravelTools(), true);
  const gate = h.gate('all', 0);
  const pending = view.load();
  await flush();
  view.dispose();
  await view.switchUser(2);
  gate.resolve();
  await pending;
  selected(h, 2, '100000002');
  assert.equal(view.currentAccount.id, 1);
  view.activate();
  await view.load();
  assert.equal(view.currentAccount.id, 2);
  await view.logout();
  assert.equal(view.canOpenTravelTools(), false);
});

for (const phase of ['network', 'vault write']) {
  test(`leaving a login during ${phase} preserves the committed account`, async () => {
    const h = harness();
    const owner = await h.seed();
    const gate = phase === 'network' ? deferred() : h.gate('cookie', 10);
    if (phase === 'network') {
      h.state.network = async (url, headers) => url === 'fixture-roles' ? gate.promise : defaultNetwork(url, headers);
    }
    const pending = h.service.loginWithSession('22','fixture-stoken','other-mid','new');
    const revision = h.service.sessionRevision();
    const rejected = assert.rejects(pending, /状态已变化/);
    await flush();
    assert.ok(phase === 'network' ? h.state.requests.some(request => request.url === 'fixture-roles') : h.state.calls.includes('cookie:10'));
    h.service.cancelPendingLogin(revision - 1);
    assert.equal(h.service.isSessionTransitionPending(), true);
    h.service.cancelPendingLogin(revision);
    assert.equal(h.service.isSessionTransitionPending(), false);
    let accountReadFinished = false;
    const accountList = h.service.getSavedUsers().then(users => { accountReadFinished = true; return users; });
    await flush();
    if (phase === 'vault write') { assert.equal(accountReadFinished, false); }
    gate.resolve(boundRoles());
    await rejected;
    assert.deepEqual(Array.from(await accountList, user => user.id), [1]);
    assert.equal(h.service.getCurrentUser(), owner);
    assert.equal(h.state.rows.has(10), false);
    selected(h, 1, '100000001');
  });
}

test('login cancellation does not interrupt a switch with a matching non-login revision', async () => {
  const h = harness();
  await h.seed();
  h.user(2);
  const gate = h.gate('read', 2);
  const pending = h.service.switchUser(2);
  h.service.cancelPendingLogin(h.service.sessionRevision());
  assert.equal(h.service.isSessionTransitionPending(), true);
  gate.resolve();
  await pending;
  selected(h, 2, '100000002');
});

test('failed CookieToken exchange leaves the old credentials untouched and cannot retry as success', async () => {
  const h = harness();
  const user = await h.seed();
  const before = user.fullCookie();
  h.state.network = async url => url.includes('getCookieAccountInfo') ? expired : accepted({ ltoken:'fixture-new-ltoken' });
  assert.equal(await h.service.refreshCookieTokenForced(user), false);
  const UserService = h.load('service/UserService').UserService;
  const result = await UserService.retryWithRefreshedCookie(user, async () => assert.fail('must not resend'));
  assert.equal(result.success, false);
  assert.equal(h.state.rows.get(1).fullCookie(), before);
  assert.equal(h.state.cookie, before);
  assert.equal(h.state.calls.some(call => call.startsWith('cookie:')), false);
});

for (const phase of ['network', 'vault write']) {
  test(`disabling guarded nonselected refresh during ${phase} keeps both accounts' credentials`, async () => {
    const h = harness();
    const owner = await h.seed();
    const user = h.user(2);
    const before = user.fullCookie();
    const gate = phase === 'network' ? deferred() : h.gate('cookie', 2);
    let active = true;
    if (phase === 'network') { h.state.network = async () => gate.promise; }
    const pending = h.service.refreshCookieTokenForced(user, async () => active);
    const rejected = assert.rejects(pending, /任务已停止/);
    await flush();
    assert.ok(phase === 'network' ? h.state.requests.length === 1 : h.state.calls.includes('cookie:2'));
    active = false;
    gate.resolve(accepted({ uid:'12', cookie_token:'fixture-late' }));
    await rejected;
    assert.equal(h.state.rows.get(2).fullCookie(), before);
    assert.equal(user.fullCookie(), before);
    assert.equal(h.service.getCurrentUser(), owner);
    selected(h, 1, '100000001');

  });
}

test('guarded nonselected renewal saves fresh CookieToken and LToken only to its own account', async () => {
  const h = harness();
  const owner = await h.seed();
  const user = h.user(2);
  const revision = h.service.sessionRevision();
  const checks = [];
  assert.equal(await h.service.refreshCookieTokenForced(user, async () => {
    checks.push(h.state.rows.has(user.id));
    return checks.at(-1);
  }), true);
  assert.ok(checks.length >= 4);
  assert.equal(h.state.rows.get(2).cookieToken, 'fixture-rotated');
  assert.equal(h.state.rows.get(2).ltoken, 'fixture-ltoken-rotated');
  assert.equal(user.cookieToken, 'fixture-rotated');
  assert.equal(user.ltoken, 'fixture-ltoken-rotated');
  assert.equal(h.service.getCurrentUser(), owner);
  assert.equal(h.service.sessionRevision(), revision);
  assert.equal(h.state.rows.get(1).cookieToken, 'fixture-cookie-1');
  assert.equal(h.state.requests.length, 2);
  assert.ok(h.state.requests.every(({ url }) => /\/account\/auth\/api\/get(CookieAccountInfo|LToken)BySToken$/.test(url)));
  selected(h, 1, '100000001');
});

test('guarded refresh stops without restoring a nonselected account removed during exchange', async () => {
  const h = harness();
  const owner = await h.seed();
  const user = h.user(2);
  const before = user.fullCookie();
  const gate = deferred();
  h.state.network = async () => gate.promise;
  const pending = h.service.refreshCookieTokenForced(user, async () => h.state.rows.has(user.id));
  const rejected = assert.rejects(pending, /任务已停止/);
  await flush();
  assert.equal(h.state.requests.length, 1);
  h.state.rows.delete(2);
  gate.resolve(accepted({ uid:'12', cookie_token:'fixture-late' }));
  await rejected;
  assert.equal(h.state.rows.has(2), false);
  assert.equal(h.state.calls.includes('cookie:2'), false);
  assert.equal(user.fullCookie(), before);
  assert.equal(h.service.getCurrentUser(), owner);
  selected(h, 1, '100000001');
});

test('guarded refresh cleans the dispatched vault write of a nonselected account removed meanwhile', async () => {
  const h = harness();
  const owner = await h.seed();
  const user = h.user(2);
  const before = user.fullCookie();
  const gate = h.gate('cookie', 2);
  const pending = h.service.refreshCookieTokenForced(user, async () => h.state.rows.has(user.id));
  const rejected = assert.rejects(pending, /任务已停止/);
  await flush();
  assert.equal(h.state.calls.includes('cookie:2'), true);
  h.state.rows.delete(2);
  gate.resolve();
  await rejected;
  assert.equal(h.state.calls.filter(call => call === 'cookie:2').length, 1);
  assert.equal(h.state.calls.includes('remove-cookie:2'), true);
  assert.equal(user.fullCookie(), before);
  assert.equal(h.service.getCurrentUser(), owner);
  selected(h, 1, '100000001');
});

function persistenceHarness(t) {
  const db = new DatabaseSync(':memory:');
  t.after(() => db.close());
  db.exec(`CREATE TABLE user_accounts (id INTEGER PRIMARY KEY, is_selected INTEGER);
    CREATE TABLE user_game_roles (user_id INTEGER, game_uid TEXT, region TEXT, nickname TEXT, level INTEGER,
      is_default INTEGER, is_chosen INTEGER);
    CREATE TABLE daily_notes (user_id INTEGER, uid TEXT);
    CREATE TABLE sign_in_info (user_id INTEGER, act_id TEXT);
    CREATE TABLE gacha_archives (id INTEGER PRIMARY KEY, uid TEXT);
    INSERT INTO user_accounts VALUES (1,1),(2,0);
    INSERT INTO user_game_roles VALUES (1,'100000001','cn_gf01','first',60,1,1),(2,'100000002','cn_gf01','second',45,1,1);
    INSERT INTO daily_notes VALUES (1,'100000001'),(2,'100000002');
    INSERT INTO sign_in_info VALUES (1,'sign-1'),(2,'sign-2');
    INSERT INTO gacha_archives VALUES (1,'100000001');`);

  class Predicates {
    constructor(table) { this.table = table; }
    equalTo(column, value) { this.column = column; this.value = value; }
  }
  const state = { id:1, uid:'100000001', fault:'', assets:new Map() };
  const store = {
    async executeSql(sql, values) { db.prepare(sql).run(...values); },
    async createTransaction() {
      db.exec('BEGIN IMMEDIATE');
      return {
        async delete(pred) { return db.prepare(`DELETE FROM ${pred.table} WHERE ${pred.column}=?`).run(pred.value).changes; },
        async insert(table, row) {
          if (state.fault === 'insert') throw Error('fixture insert failed');
          const columns = Object.keys(row);
          return Number(db.prepare(`INSERT INTO ${table} (${columns.join(',')}) VALUES (${columns.map(() => '?').join(',')})`)
            .run(...Object.values(row)).lastInsertRowid);
        },
        async commit() {
          if (state.fault === 'commit') throw Error('fixture commit failed');
          db.exec('COMMIT');
        },
        async rollback() { db.exec('ROLLBACK'); }
      };
    }
  };
  const alias = query => Buffer.from(query.get('alias')).toString('utf8');
  const notFound = () => Object.assign(Error('fixture missing asset'), { code:24000002 });
  const asset = {
    Tag:{ ALIAS:'alias', SECRET:'secret', ACCESSIBILITY:'accessibility', CONFLICT_RESOLUTION:'conflict', RETURN_TYPE:'return' },
    Accessibility:{ DEVICE_FIRST_UNLOCKED:1 }, ConflictResolution:{ OVERWRITE:1 }, ReturnType:{ ALL:1 },
    async add(attrs) { state.assets.set(alias(attrs), attrs.get('secret')); },
    async query(query) {
      if (state.fault === 'read') throw Object.assign(Error('fixture read failed'), { code:24000001 });
      const secret = state.assets.get(alias(query));
      if (secret === undefined) throw notFound();
      return [new Map([['secret', secret]])];
    },
    async remove(query) {
      if (state.fault === 'remove') throw Object.assign(Error('fixture remove failed'), { code:24000001 });
      if (!state.assets.delete(alias(query))) throw notFound();
    }
  };
  const util = {
    TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
    TextDecoder: { create: () => ({ decodeToString: value => new TextDecoder().decode(value) }) }
  };
  const boundaries = {
    '@kit.ArkData':{ relationalStore:{ RdbPredicates:Predicates, TransactionType:{ IMMEDIATE:1 } } },
    '@kit.AssetStoreKit':{ asset }, '@kit.ArkTS':{ util }, '@kit.BasicServicesKit':{},
    RelationalStoreHelper:{ RelationalStoreHelper:{ getStore:() => store } },
    PreferencesStore:{ PreferencesStore:{ getCurrentUserId:() => state.id, setCurrentUserId:id => { state.id = id; },
      setCurrentUid:uid => { state.uid = uid; } } },
    Logger:{ Logger:{ info(){}, warn(){} } }
  };
  const modules = new Map();
  function load(relative) {
    const file = path.resolve(root, relative + '.ets');
    if (modules.has(file)) return modules.get(file).exports;
    const source = fs.readFileSync(file, 'utf8');
    const output = ts.transpileModule(source, { fileName:file.replace(/\.ets$/, '.ts'),
      compilerOptions:{ module:ts.ModuleKind.CommonJS, target:ts.ScriptTarget.ES2022 }, reportDiagnostics:true });
    assert.equal(output.diagnostics.length, 0, relative);
    const module = { exports:{} };
    modules.set(file, module);
    vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`, { Error })(id => {
      const boundary = boundaries[id] ?? boundaries[path.basename(id)];
      if (boundary) return boundary;
      assert.ok(id.startsWith('.'), id);
      return load(path.resolve(path.dirname(file), id));
    }, module, module.exports);
    return module.exports;
  }
  const UserRepo = load('data/repo/UserRepo').UserRepo;
  const TokenVault = load('data/local/TokenVault').TokenVault;
  const UserGameRole = load('model/UserGameRole').UserGameRole;
  const count = table => db.prepare(`SELECT COUNT(*) AS count FROM ${table}`).get().count;
  return { db, state, UserRepo, TokenVault, UserGameRole, count };
}

test('SQLite account deletion rolls back on vault or commit failure, then removes only account-owned data', async t => {
  const h = persistenceHarness(t);
  const cookie = 'stuid=11; stoken=fixture';
  await h.TokenVault.saveCookie(1, cookie);
  await h.TokenVault.saveCookie(2, 'stuid=12; stoken=other');
  for (const failure of ['read', 'remove', 'commit']) {
    h.state.fault = failure;
    await assert.rejects(h.UserRepo.deleteUser(1), /登录凭证失败|commit failed/);
    h.state.fault = '';
    assert.equal(await h.TokenVault.loadCookie(1, true), cookie);
    for (const table of ['user_accounts','user_game_roles','daily_notes','sign_in_info']) assert.equal(h.count(table), 2);
    assert.equal(h.state.id, 1);
  }
  await h.UserRepo.deleteUser(1);
  await h.UserRepo.deleteUser(1);
  assert.equal(await h.TokenVault.loadCookie(1, true), '');
  assert.equal(await h.TokenVault.loadCookie(2, true), 'stuid=12; stoken=other');
  for (const table of ['user_accounts','user_game_roles','daily_notes','sign_in_info','gacha_archives']) {
    assert.equal(h.count(table), 1);
  }
  assert.equal(h.state.id, 0);
  assert.equal(h.state.uid, '');
  assert.equal(h.db.prepare('SELECT uid FROM gacha_archives').get().uid, '100000001');
});

test('SQLite selection and role replacement commit together with their own row changes', async t => {
  const h = persistenceHarness(t);
  await h.UserRepo.selectUser(2);
  assert.deepEqual(h.db.prepare('SELECT is_selected FROM user_accounts ORDER BY id').all().map(row => row.is_selected), [0,1]);
  assert.equal(h.state.id, 2);
  const role = h.UserGameRole.of('100000003','cn_gf01','new',55);
  h.state.fault = 'insert';
  await assert.rejects(h.UserRepo.upsertRoles(2,[role]), /insert failed/);
  assert.equal(h.db.prepare('SELECT game_uid FROM user_game_roles WHERE user_id=2').get().game_uid, '100000002');
  h.state.fault = '';
  await h.UserRepo.upsertRoles(2,[role]);
  assert.equal(h.db.prepare('SELECT game_uid FROM user_game_roles WHERE user_id=2').get().game_uid, '100000003');
  assert.equal(h.count('user_game_roles'), 2);
});
