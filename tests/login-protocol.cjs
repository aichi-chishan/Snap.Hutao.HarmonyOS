// Windows HoyoPlay + CN passport request contracts, using fixtures only.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
function load(file, requireMock) {
  const source = fs.readFileSync(`entry/src/main/ets/${file}.ets`, 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022
  } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(`(function(require,module,exports){${output}\n})`, {})(requireMock, module, module.exports);
  return module.exports;
}
const constants = load('common/Constants', () => { throw Error('Unexpected constants import'); });
const responseModel = load('model/ApiResponse', () => constants);
const requests = [], responses = [], encryptions = [], signatures = [], verifications = [];
let solved = 'fixture-aigis-proof';
let onVerification = () => {};
const { PassportClient } = load('data/network/PassportClient', id => {
  if (id === '@kit.NetworkKit') return { http: {
    RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 0 }, ResponseCode: { OK: 200 },
    createHttp: () => ({ destroy() {}, request: async (url, options) => {
      requests.push({ url, options });
      const reply = responses.shift(); assert(reply, 'unplanned network call');
      if (reply.beforeReply) reply.beforeReply();
      return { responseCode: 200, result: JSON.stringify(reply.body), header: reply.headers || {} };
    } })
  } };
  if (id.endsWith('/Constants')) return constants;
  if (id.endsWith('/ApiResponse')) return responseModel;
  if (id.endsWith('/DsSigner')) return { DsSigner: {
    nowTimestamp: () => 1000, randomLowerAlphaNumeric: () => 'abc123',
    signGen2: async (...args) => { signatures.push(args); return 'fixture-ds'; }
  } };
  if (id.endsWith('/RsaEncryptor')) return { RsaEncryptor: {
    encrypt: async value => { encryptions.push(value); return `encrypted(${value})`; }
  } };
  if (id.endsWith('/PreferencesStore')) return { PreferencesStore: { getBbsDeviceId: () => 'fixture-persisted-device' } };
  if (id.endsWith('/RiskVerifyService')) return { RiskVerifyService: { getInstance: () => ({
    verifyAigis: async value => { verifications.push(value); onVerification(); return solved; }
  }) } };
  if (id.endsWith('/ApiClient')) return { ApiClient: { normalizeHeaders: headers => {
    const normalized = {}; for (const key of Object.keys(headers)) normalized[key.toLowerCase()] = headers[key];
    return normalized;
  } } };
  if (id.endsWith('/CredentialPolicy')) return { CredentialPolicy: { logUrl: url => url } };
  if (id.endsWith('/Logger')) return { Logger: { info() {}, warn() {} } };
  throw Error(`Unexpected passport dependency ${id}`);
});
const ok = data => ({ body: { retcode: 0, data } });
const risk = () => ({ body: { retcode: -1, message: 'verify' }, headers: { 'X-Rpc-Aigis': 'fixture-risk' } });
(async () => {
  responses.push(ok({ url: 'https://fixture.test/qr', ticket: 'fixture-ticket' }));
  const qr = await PassportClient.createQrLogin();
  responses.push(ok({ status: 'Confirmed', tokens: [
    { token_type: 2, token: 'other' }, { token_type: 1, token: 'fixture-stoken' }
  ], user_info: { aid: '42', mid: 'fixture-mid', account_name: 'Fixture' } }));
  const result = await PassportClient.queryQrLoginStatus(qr.ticket);
  const session = PassportClient.extractQrSession(result);
  assert.equal(session.stoken, 'fixture-stoken'); assert.equal(session.stuid, '42');
  assert.equal(session.mid, 'fixture-mid'); assert.equal(session.accountName, 'Fixture');
  assert.match(requests[0].url, /^https:\/\/passport-api\.mihoyo\.com\/.*createQRLogin$/);
  assert.match(requests[1].url, /^https:\/\/passport-api\.mihoyo\.com\/.*queryQRLoginStatus$/);
  assert.match(requests[0].options.header['x-rpc-device_id'], /^[a-z0-9]{53}$/);
  assert.equal(requests[0].options.header['x-rpc-device_id'], requests[1].options.header['x-rpc-device_id']);
  assert.equal(requests[0].options.header['x-rpc-app_id'], 'ddxf5dufpuyo');
  assert.equal(requests[0].options.header.DS, undefined, 'HoyoPlay QR requests do not use BBS DS');
  assert.equal(JSON.parse(requests[1].options.extraData).ticket, 'fixture-ticket');

  responses.push(risk(), ok({ sent_new: true, countdown: 60, action_type: 'login' }));
  const captcha = await PassportClient.createLoginCaptcha('13800000000');
  assert.equal(captcha.actionType, 'login'); assert.equal(captcha.countdown, 60);
  assert.deepEqual(encryptions, ['13800000000', '+86']);
  assert.deepEqual(verifications, ['fixture-risk']);
  const send = requests[2], replay = requests[3];
  assert.deepEqual(JSON.parse(send.options.extraData), { area_code: 'encrypted(+86)', mobile: 'encrypted(13800000000)' });
  assert.equal(replay.options.extraData, send.options.extraData, 'aigis retry preserves the signed body');
  assert.equal(replay.options.header['x-rpc-aigis'], 'fixture-aigis-proof');
  assert.equal(replay.options.header['x-rpc-device_id'], 'fixture-persisted-device');
  assert.equal(replay.options.header['x-rpc-app_id'], 'bll8iq97cem8');
  for (const signed of signatures) {
    assert.equal(signed[0], constants.AppConstants.DS_SALT_PROD);
    assert.equal(signed[3], send.options.extraData); assert.equal(signed[4], '');
  }
  responses.push(ok({ token: { token_type: 1, token: 'fixture-login-token' },
    user_info: { aid: '42', mid: 'fixture-mid', account_name: 'Fixture' } }));
  const login = await PassportClient.loginByMobileCaptcha('13800000000', '123456', captcha.actionType);
  assert.equal(login.stoken, 'fixture-login-token'); assert.equal(login.stuid, '42');
  assert.deepEqual(JSON.parse(requests[4].options.extraData), {
    area_code: 'encrypted(+86)', action_type: 'login', captcha: '123456', mobile: 'encrypted(13800000000)'
  });
  solved = ''; responses.push(risk());
  await assert.rejects(PassportClient.createLoginCaptcha('13800000000'), /已取消/);
  assert.equal(requests.length, 6, 'cancelled verification does not replay the login request');
  let active = true;
  const late = risk(); late.beforeReply = () => { active = false; }; responses.push(late);
  const verifiesBefore = verifications.length;
  await assert.rejects(PassportClient.createLoginCaptcha('13800000000', () => active), /登录已取消/);
  assert.equal(verifications.length, verifiesBefore, 'a late aigis response cannot open verification after detach');
  active = true; solved = 'fixture-aigis-proof'; responses.push(risk());
  onVerification = () => { active = false; };
  await assert.rejects(PassportClient.loginByMobileCaptcha('13800000000', '123456', 'login', () => active), /登录已取消/);
  assert.equal(requests.length, 8, 'verification completion cannot replay after detach');
  assert.equal(responses.length, 0);
  for (const request of requests) {
    assert.equal(request.options.maxRedirects, 0); assert.equal(request.options.usingCache, false);
  }
  console.log('login-protocol: PASS (CN QR device/payload, token selection, RSA fields, DS body and aigis replay/cancellation)');
})().catch(error => { console.error(error); process.exitCode = 1; });
