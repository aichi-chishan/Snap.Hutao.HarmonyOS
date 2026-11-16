const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function harness() {
  const state = { uid: '100000001', revision: 1, cookies: [], tickets: [], downloads: [], clipboard: [], writes: [] };
  const preferences = new Map();
  const pixel = { release: async () => {} };
  const responses = {
    'service/UserService': { UserService: { getInstance: () => ({
      getCurrentUser: () => state.user, sessionRevision: () => state.revision,
      refreshCookieTokenForced: async (user, active) => {
        state.tokenEntered?.();
        if (state.tokenGate) { await state.tokenGate; }
        if (!await active()) { return false; }
        user.cookieToken = 'refreshed-fixture';
        return true;
      },
    }) } },
    'data/prefs/PreferencesStore': { PreferencesStore: {
      getCurrentUid: () => state.uid, getDeviceId: () => 'device-fixture', getDeviceFp: () => 'fingerprint-fixture',
      getString: (key, fallback) => preferences.get(key) ?? fallback, setString: (key, value) => preferences.set(key, value),
    } },
    'data/network/ApiClient': { ApiClient: { getInstance: () => ({
      get: async () => ({ success: true, data: { user_info: { uid: 1, nickname: 'fixture', gender: 2 } } }),
    }) } },
    'data/network/HoyolabClient': { HoyolabClient: {
      getActionTicket: async (...params) => {
        state.tickets.push(params);
        return { retcode: 0, success: true, data: { action_ticket: 'ticket-fixture' } };
      },
    } },
    'data/network/DsSigner': { DsSigner: {
      nowTimestamp: () => 1, randomNumber: () => '123456', randomLowerAlphaNumeric: () => 'abc123',
      signGen1: async () => 'ds1', signGen2: async (salt, t, r, body, query) => `${body}:${query}`,
    } },
    'service/AppLocaleService': { AppLocaleService: { current: () => 'zh-Hans' } },
    '@kit.ArkTS': { url: { URL: { parseURL: value => new URL(value) } },
      util: { Base64Helper: class { decodeSync(value) { return Uint8Array.from(Buffer.from(value, 'base64')); } } } },
    '@kit.ArkWeb': { webview: { WebCookieManager: { configCookieSync: (...args) => state.cookies.push(args) } } },
    '@kit.BasicServicesKit': { pasteboard: { MIMETYPE_PIXELMAP: 'pixelMap', createData: (type, value) => ({ type, value }),
      getSystemPasteboard: () => ({ setData: async data => { state.clipboard.push(data); } }) } },
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 'buffer' },
      createHttp: () => ({ request: async (url, options) => {
        state.downloads.push({ url, options });
        return { responseCode: 200, result: new ArrayBuffer(8) };
      }, destroy() {} }) } },
    '@kit.ImageKit': { image: { createImageSource: () => ({ getImageInfo: async () => ({ size: { width: 2, height: 2 } }),
      createPixelMap: async () => pixel, release: async () => {} }),
      createImagePacker: () => ({ packToData: async (_pixel, options) => {
        assert.equal(options.format, 'image/png');
        return new ArrayBuffer(8);
      }, release: async () => {} }) } },
    '@kit.AbilityKit': {},
    '@kit.CoreFileKit': { picker: { DocumentViewPicker: class {
      async save(options) {
        assert.equal(options.newFileNames[0], 'share.png');
        state.pickerEntered?.();
        if (state.pickerGate) { await state.pickerGate; }
        return ['file://picked-share.png'];
      }
    } }, fileIo: { OpenMode: { WRITE_ONLY: 1, TRUNC: 2, CREATE: 4 },
      open: async uri => { state.writes.push(uri); return { fd: 1 }; },
      write: async (_fd, bytes) => bytes.byteLength, close: async () => {} } },
  };
  const cache = new Map();
  function load(name) {
    if (responses[name]) return responses[name];
    if (cache.has(name)) return cache.get(name);
    const source = fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
    const result = ts.transpileModule(source, { reportDiagnostics: true,
      compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } });
    assert.equal(result.diagnostics.length, 0, name);
    const module = { exports: {} };
    vm.runInNewContext(result.outputText, { module, exports: module.exports, ArrayBuffer,
      require: id => load(id.startsWith('@') ? id : path.posix.normalize(path.posix.join(path.posix.dirname(name), id))) });
    cache.set(name, module.exports);
    return module.exports;
  }
  const { User } = load('model/User');
  const user = new User();
  user.roles = [{ gameUid: state.uid, region: 'cn_gf01' }];
  user.aid = '1'; user.accountId = '1'; user.cookieToken = 'cookie-fixture'; user.ltuid = '1'; user.ltoken = 'login-fixture';
  user.stuid = '1'; user.stoken = 'native-only-fixture';
  state.user = user;
  return { load, state, pixel };
}

test('the official route and native proxy are limited to the registered pages', () => {
  const h = harness();
  const { OfficialWebBridgeService: Bridge, OfficialWebKind: Kind } = h.load('service/OfficialWebBridgeService');
  for (const kind of Object.values(Kind)) assert.equal(Bridge.allowsPage(new Bridge(kind, h.state.uid).source()), true);
  assert.match(new Bridge(Kind.DailyNote, h.state.uid).source(), /role_id=100000001&server=cn_gf01$/);
  assert.equal(Bridge.allowsPage('https://webstatic.mihoyo.com.evil.invalid/bbs/event/e20200511toolbox/index.html'), false);
  assert.equal(Bridge.allowsPage('https://webstatic.mihoyo.com:444/app/community-game-records/index.html'), false);
  assert.equal(Bridge.allowsPage('https://webstatic.mihoyo.com/app/community-game-records-other/index.html'), false);
  assert.equal(Bridge.navigationTarget('mihoyobbs://webview?link=https%3A%2F%2Fevil.invalid'), '');
  assert.equal(Bridge.navigationTarget('mihoyobbs://article/123'), 'https://m.miyoushe.com/ys/#/article/123');
  assert.equal(JSON.parse(Bridge.PERMISSION).javascriptProxyPermission.urlPermissionList.length, 3);
  const page = fs.readFileSync(path.join(root, 'pages/OfficialWebPage.ets'), 'utf8');
  assert.match(page, /incognitoMode: true/);
  assert.match(page, /registerJavaScriptProxy\(.*OfficialWebBridgeService\.PERMISSION\)/);
});

test('the bridge installs only game-record cookies and handles registered commands in the current session', async () => {
  const h = harness();
  const { OfficialWebBridgeService: Bridge, OfficialWebKind: Kind } = h.load('service/OfficialWebBridgeService');
  const bridge = new Bridge(Kind.SignIn, h.state.uid);
  await bridge.prepare(() => true);
  assert.equal(h.state.cookies.length, 4);
  assert.ok(h.state.cookies.every(cookie => cookie[2] === true && cookie[3] === true));
  assert.ok(h.state.cookies.every(cookie => !cookie[1].includes('native-only-fixture')));
  const shared = [];
  const actions = { closePage() {}, openPage() {}, share: async request => { shared.push(request); return true; } };
  async function call(method, payload) {
    const callback = await bridge.receive(JSON.stringify({ method, payload, callback: 'reply' }), actions, () => true);
    return callback && JSON.parse(callback.result);
  }
  assert.equal((await call('getHTTPRequestHeaders')).data['x-rpc-client_type'], '2');
  assert.equal((await call('getCurrentLocale')).data.language, 'zh-cn');
  assert.equal((await call('getDS2', { body: '{}', query: { z: 2, a: 1 } })).data.DS, '{}:1&2');
  assert.equal((await call('getActionTicket', { action_type: 'game_role' })).data.action_ticket, 'ticket-fixture');
  assert.equal(h.state.tickets[0][3], 'game_role');
  assert.equal((await call('getActionTicket', { action_type: 'invalid/type' })).retcode, -1);
  assert.equal(h.state.tickets.length, 1);
  assert.equal(await call('genAppAuthKey'), undefined);
  assert.equal((await call('share', { type: 'image', content: { image_base64: 'AQID' } })).data.type, 'image');
  assert.equal(shared[0].imageBase64, 'AQID');

  let unblock;
  h.state.tokenGate = new Promise(resolve => { unblock = resolve; });
  const tokenEntered = new Promise(resolve => { h.state.tokenEntered = resolve; });
  const pending = call('getCookieToken', { forceRefresh: true });
  await tokenEntered;
  h.state.revision++;
  unblock();
  assert.equal(await pending, undefined, 'switching accounts suppresses the stale bridge callback');
  assert.equal(h.state.cookies.length, 4);
});

test('share images use the native bitmap clipboard and write only the picked PNG destination', async () => {
  const h = harness();
  const { OfficialWebShareMode: Mode, OfficialWebShareService: Share } = h.load('service/OfficialWebShareService');
  const { OfficialWebViewModel } = h.load('viewmodel/OfficialWebViewModel');
  assert.equal(new OfficialWebViewModel().shareMode(), Mode.Copy);
  Share.setShareMode(Mode.SavePng);
  assert.equal(new OfficialWebViewModel().shareMode(), Mode.SavePng);
  Share.setShareMode(Mode.Copy);
  assert.equal(Share.shareMode(), Mode.Copy);
  const picture = await Share.imageFor({ imageUrl: 'https://upload-bbs.mihoyo.com/share.png', imageBase64: '' });
  assert.equal(h.state.downloads[0].options.maxRedirects, 0);
  assert.equal(h.state.downloads[0].options.header, undefined, 'image requests do not forward account credentials');
  await assert.rejects(Share.imageFor({ imageUrl: 'https://mihoyo.com.evil.invalid/share.png' }), /来源/);
  assert.equal(h.state.downloads.length, 1);
  assert.equal(await Share.imageFor({ imageUrl: '', imageBase64: 'data:image/png;base64,AQID' }), h.pixel);
  await Share.copy(picture);
  assert.equal(h.state.clipboard[0].type, 'pixelMap');
  assert.equal(h.state.clipboard[0].value, h.pixel);
  assert.equal(await Share.save(picture, {}, () => true), true);
  assert.deepEqual(h.state.writes, ['file://picked-share.png']);
  let active = true;
  let unblock;
  h.state.pickerGate = new Promise(resolve => { unblock = resolve; });
  const pickerEntered = new Promise(resolve => { h.state.pickerEntered = resolve; });
  const pending = Share.save(picture, {}, () => active);
  await pickerEntered;
  active = false; unblock();
  assert.equal(await pending, false);
  assert.equal(h.state.writes.length, 1);
  assert.equal(await Share.screenshot({ webPageSnapshot(options, callback) {
    assert.equal(options.size.height, '1200px');
    callback(undefined, { status: true, imagePixelMap: h.pixel });
  } }, 500, 1200), h.pixel);
});
