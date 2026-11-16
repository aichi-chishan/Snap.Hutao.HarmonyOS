const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const { accepted, boundRole, deferred, flush, harness: accountHarness } = require('./account-session-ownership.cjs');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const DAY = 24 * 60 * 60 * 1000;
const UID = '100000001';
const CHANNEL_UID = '500000002';
const ITEM_ICON = 'UI_AvatarIcon_Item_Circle';
const AVATAR_ICON = 'UI_AvatarIcon_PlayerBoy_Circle';
const COSTUME_ICON = 'UI_AvatarIcon_PlayerBoyCostumeCWXR_Circle';
const catalog = JSON.stringify([
  { Id:31, Icon:ITEM_ICON, UnlockType:1, UnlockParameter:200501 },
  { Id:1, Icon:AVATAR_ICON, UnlockType:2, UnlockParameter:10000005 },
  { Id:11, Icon:COSTUME_ICON, UnlockType:3, UnlockParameter:200501 },
  { Id:999, Icon:'../bad', UnlockType:2, UnlockParameter:10000999 }
]);

function response(picture) {
  return { responseCode:200, result:JSON.stringify({ playerInfo:{ profilePicture:picture } }) };
}

function harness() {
  const state = { now:Date.now(), requests:[], destroyed:0, catalogReads:[], cache:new Map(), cacheWrites:0 };
  state.fetch = async () => response({ id:31 });
  state.readCatalog = async () => catalog;
  const dependencies = {
    '@kit.NetworkKit': {
      http: {
        RequestMethod:{ GET:'GET' },
        HttpDataType:{ STRING:0 },
        ResponseCode:{ OK:200 },
        createHttp:() => ({
          async request(url, options) {
            state.requests.push({ url, options });
            return state.fetch(url, options);
          },
          destroy() { state.destroyed++; }
        })
      }
    },
    GameDataService:{ GameDataService:{
      async readMetadataFile(name) {
        state.catalogReads.push(name);
        return state.readCatalog();
      }
    } },
    PreferencesStore:{ PreferencesStore:{
      getString:(key, fallback) => state.cache.get(key) ?? fallback,
      setString(key, value) {
        state.cacheWrites++;
        state.cache.set(key, value);
      }
    } }
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
    vm.runInNewContext('(function(require,module,exports){' + output.outputText + '\n})', {
      Date:class extends Date { static now() { return state.now; } }
    })(id => {
      const boundary = dependencies[id] ?? dependencies[path.basename(id)];
      if (boundary) return boundary;
      assert.ok(id.startsWith('.'), id);
      return load(path.resolve(path.dirname(file), id));
    }, module, module.exports);
    return module.exports;
  }
  const service = load('service/RoleProfilePictureService').RoleProfilePictureService;
  const model = load('model/RoleProfilePicture').RoleProfilePicture;
  return { state, service, model };
}

const current = () => true;

test('direct Enka request is a credential-free CN-only GET without redirects', async () => {
  const h = harness();
  assert.equal(await h.service.loadIcon(UID, true, current), ITEM_ICON);
  assert.deepEqual(h.state.catalogReads, ['ProfilePicture.json']);
  const [{ url, options }] = h.state.requests;
  assert.equal(url, 'https://enka.network/api/uid/100000001?info');
  assert.equal(options.method, 'GET');
  assert.deepEqual(Object.keys(options.header), ['Accept']);
  assert.equal(options.header.Accept, 'application/json');
  assert.equal(options.maxRedirects, 0);
  assert.equal(options.usingCache, false);
  assert.ok(options.connectTimeout > 0 && options.readTimeout > 0);
  assert.equal(h.state.destroyed, 1);
  assert.equal(await h.service.loadIcon('800000001', true, current), '');
  assert.equal(await h.service.loadIcon(UID + '?redirect', true, current), '');
  assert.equal(h.state.requests.length, 1);
  assert.equal(h.state.catalogReads.length, 1);
});

test('profile icon mapping prefers catalog ID, avatar unlock type, then costume unlock type', () => {
  const h = harness();
  const entries = h.model.readCatalog(catalog);
  const icon = picture => h.model.fromResponse(response(picture).result)?.resolveIcon(entries) ?? '';
  assert.equal(icon({ id:31, avatarId:10000005, costumeId:200501 }), ITEM_ICON);
  assert.equal(icon({ id:700, avatarId:10000005, costumeId:200501 }), AVATAR_ICON);
  assert.equal(icon({ id:700, avatarId:5, costumeId:200501 }), COSTUME_ICON);
  assert.equal(icon({ avatarId:10000999 }), '');
  assert.equal(icon({ id:-1, avatarId:1.2, costumeId:'200501' }), '');
  assert.equal(h.model.fromResponse(JSON.stringify({ playerInfo:{ nickname:'no picture' } })), undefined);
});

test('bundled catalog provides the exact Windows avatar and costume icon names', async () => {
  const h = harness();
  const file = path.resolve(root, '../resources/rawfile/metadata/ProfilePicture.json');
  h.state.readCatalog = async () => fs.readFileSync(file, 'utf8');
  h.state.fetch = async () => response({ avatarId:10000005 });
  assert.equal(await h.service.loadIcon(UID, true, current), AVATAR_ICON);
  h.state.fetch = async () => response({ costumeId:200501 });
  assert.equal(await h.service.loadIcon(UID, true, current), COSTUME_ICON);
});

test('fresh avatar cache is per UID for 15 days and manual refresh bypasses it', async () => {
  const h = harness();
  assert.equal(await h.service.loadIcon(UID, false, current), ITEM_ICON);
  assert.equal(h.service.cachedIcon(UID), ITEM_ICON);
  assert.equal(h.service.cachedIcon(CHANNEL_UID), '');
  h.state.fetch = async () => response({ avatarId:10000005 });
  h.state.now += 15 * DAY - 1;
  assert.equal(await h.service.loadIcon(UID, false, current), ITEM_ICON);
  assert.equal(h.state.requests.length, 1);
  assert.equal(await h.service.loadIcon(CHANNEL_UID, false, current), AVATAR_ICON);
  h.state.now++;
  assert.equal(h.service.cachedIcon(UID), '');
  assert.equal(await h.service.loadIcon(UID, false, current), AVATAR_ICON);
  h.state.fetch = async () => response({ costumeId:200501 });
  assert.equal(await h.service.loadIcon(UID, true, current), COSTUME_ICON);
  assert.equal(h.service.cachedIcon(UID), COSTUME_ICON);
  assert.equal(h.service.cachedIcon(CHANNEL_UID), AVATAR_ICON);
  assert.equal(h.state.requests.length, 4);
  assert.equal(h.state.cacheWrites, 4);
  assert.equal(h.state.destroyed, 4);
});

test('missing catalog avoids a UID request and failed refresh preserves an existing icon', async () => {
  const h = harness();
  h.state.readCatalog = async () => { throw Error('fixture metadata missing'); };
  assert.equal(await h.service.loadIcon(UID, true, current), '');
  h.state.readCatalog = async () => '[]';
  assert.equal(await h.service.loadIcon(UID, true, current), '');
  assert.equal(h.state.requests.length, 0);
  h.state.readCatalog = async () => catalog;
  assert.equal(await h.service.loadIcon(UID, true, current), ITEM_ICON);
  for (const unavailable of [
    { responseCode:302, result:response({ id:31 }).result },
    { responseCode:429, result:'' },
    { responseCode:200, result:'malformed' },
    { responseCode:200, result:'{}' },
    response({ id:700 })
  ]) {
    h.state.fetch = async () => unavailable;
    assert.equal(await h.service.loadIcon(UID, true, current), '');
  }
  h.state.fetch = async () => { throw Error('fixture offline'); };
  assert.equal(await h.service.loadIcon(UID, true, current), '');
  assert.equal(h.service.cachedIcon(UID), ITEM_ICON);
  assert.equal(h.state.cacheWrites, 1);
  assert.equal(h.state.destroyed, 7);
});

test('stale role lookup cannot send after metadata or write cache after HTTP', async () => {
  const h = harness();
  let active = true;
  const metadata = deferred();
  h.state.readCatalog = () => metadata.promise;
  const beforeRequest = h.service.loadIcon(UID, true, () => active);
  active = false;
  metadata.resolve(catalog);
  assert.equal(await beforeRequest, '');
  assert.equal(h.state.requests.length, 0);

  active = true;
  h.state.readCatalog = async () => catalog;
  const network = deferred();
  h.state.fetch = () => network.promise;
  const pending = h.service.loadIcon(UID, true, () => active);
  await flush();
  assert.equal(h.state.requests.length, 1);
  active = false;
  network.resolve(response({ id:31 }));
  assert.equal(await pending, '');
  assert.equal(h.state.cacheWrites, 0);
  assert.equal(h.state.destroyed, 1);
});

test('auto and manual loads share public HTTP while each caller retains its own ownership', async () => {
  const h = harness();
  const network = deferred();
  h.state.fetch = () => network.promise;
  let oldOwner = true;
  const first = h.service.loadIcon(UID, false, () => oldOwner);
  const second = h.service.loadIcon(UID, true, current);
  await flush();
  assert.equal(h.state.requests.length, 1);
  oldOwner = false;
  network.resolve(response({ id:31 }));
  assert.equal(await first, '');
  assert.equal(await second, ITEM_ICON);
  assert.equal(h.state.cacheWrites, 1);
  assert.equal(h.state.destroyed, 1);
});

async function accountView(profile) {
  const account = accountHarness();
  account.state.rolePictures.cachedIcon = (uid) => profile.service.cachedIcon(uid);
  account.state.rolePictures.loadIcon = (uid, force, owner) => profile.service.loadIcon(uid, force, owner);
  await account.seed();
  const Model = account.load('viewmodel/UserViewModel').UserViewModel;
  return { account, view:new Model() };
}

test('account rows load the current avatar and keep it if the manual refresh is unavailable', async () => {
  const profile = harness();
  const { view } = await accountView(profile);
  await view.load();
  await flush();
  assert.equal(view.roles[0].avatarIcon, ITEM_ICON);
  assert.equal(view.roles[0].canRefreshAvatar, true);
  const oldKey = view.roles[0].key();
  profile.state.fetch = async () => response({ costumeId:200501 });
  assert.equal(await view.refreshRoleAvatar(UID, 1), true);
  assert.equal(view.roles[0].avatarIcon, COSTUME_ICON);
  assert.notEqual(view.roles[0].key(), oldKey);
  profile.state.fetch = async () => response({ id:700 });
  assert.equal(await view.refreshRoleAvatar(UID, 1), false);
  assert.equal(view.roles[0].avatarIcon, COSTUME_ICON);
});

for (const change of ['account switch', 'role replacement', 'view disposal']) {
  test('late avatar result is discarded after ' + change, async () => {
    const profile = harness();
    const { account, view } = await accountView(profile);
    await view.load();
    await flush();
    const network = deferred();
    profile.state.fetch = url => url.includes(UID) ? network.promise : Promise.resolve(response({ avatarId:10000005 }));
    const manual = view.refreshRoleAvatar(UID, 1);
    const rejected = assert.rejects(manual, /账号或角色已变化/);
    await flush();
    if (change === 'account switch') {
      account.user(2);
      await view.switchUser(2);
    } else if (change === 'role replacement') {
      account.state.network = async () => accepted({ list:[boundRole('100000009')] });
      await view.refreshRoles();
    } else {
      view.dispose();
    }
    network.resolve(response({ costumeId:200501 }));
    await rejected;
    assert.equal(profile.service.cachedIcon(UID), ITEM_ICON);
    assert.ok(view.roles.every(role => role.avatarIcon !== COSTUME_ICON));
  });
}
