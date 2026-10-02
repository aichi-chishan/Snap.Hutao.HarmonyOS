// Offline cloud wire-contract tests. Synthetic credentials, no remote requests.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const base = path.resolve(__dirname, '../entry/src/main/ets');
const sent = [];
let payload = '{"retcode":0,"data":{}}';
let status = 200;
const prefs = new Map();
const cache = new Map();
function load(name) {
  const file = path.resolve(base, name.endsWith('.ets') ? name : `${name}.ets`);
  if (cache.has(file)) return cache.get(file);
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const module = { exports: {} };
  const req = id => {
    if (id.endsWith('/PreferencesStore')) return { PreferencesStore: {
      getString: (key, fallback) => prefs.get(key) || fallback, setString: (key, value) => prefs.set(key, value)
    } };
    if (id === '@kit.ArkTS') return { util: { TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } }, generateRandomUUID: () => 'fixture-device-id',
      Base64Helper: class { decodeSync(s) { return Buffer.from(s, 'base64'); } encodeToStringSync(b) { return Buffer.from(b).toString('base64'); } }
    } };
    if (id === '@kit.CryptoArchitectureKit') return { cryptoFramework: {
      CryptoMode: { ENCRYPT_MODE: 1 },
      createAsyKeyGenerator: spec => { assert.equal(spec, 'RSA2048'); return { convertKey: async blob => ({ pubKey: crypto.createPublicKey({ key: blob.data, type: 'spki', format: 'der' }) }) }; },
      createCipher: spec => { assert.equal(spec, 'RSA2048|PKCS1_OAEP|SHA1|MGF1_SHA1'); let key; return { init: async (mode, pub) => { key = pub; }, doFinal: async blob => ({ data: crypto.publicEncrypt({ key, oaepHash: 'sha1', padding: crypto.constants.RSA_PKCS1_OAEP_PADDING }, blob.data) }) }; },
    } };
    if (id === '@kit.NetworkKit') return { http: {
      RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 0 },
      createHttp: () => ({ request: async (url, options) => { sent.push({ url, options }); return { responseCode: status, result: payload }; }, destroy() {} })
    } };
    return load(path.relative(base, path.resolve(path.dirname(file), id)));
  };
  vm.runInNewContext(`(function(require,module,exports){${output}\n})`, {})(req, module, module.exports);
  cache.set(file, module.exports);
  return module.exports;
}
(async () => {
  const { HutaoCloudJson } = load('model/HutaoCloud');
  const { HutaoCloudGacha } = load('model/HutaoCloudGacha');
  const { GachaItem } = load('model/GachaItem');
  const { HutaoCloudClient } = load('data/network/HutaoCloudClient');
  const maxId = '9223372036854775807';
  assert.equal(JSON.parse(HutaoCloudJson.preserveIds(`{"Id":${maxId},"301":${maxId}}`)).Id, maxId);
  assert.equal(HutaoCloudJson.validId('9223372036854775808'), false);
  const item = new GachaItem();
  item.gachaId = '1740733076123456789'; item.gachaType = 400; item.itemId = 10000035; item.time = '2026-10-02 12:34:56';
  const body = HutaoCloudGacha.uploadBody('600000001', [item]);
  assert.ok(body.includes('"Id":1740733076123456789'));
  assert.ok(body.includes('"QueryType":301'));
  assert.ok(body.includes('2026-10-02T12:34:56-05:00'));
  assert.equal(HutaoCloudGacha.localTime('2026-10-02T12:34:56-05:00', '600000001'), item.time);
  assert.equal(HutaoCloudGacha.localTime('2026-10-02T12:34:56+08:00', '1800000001'), item.time);
  const roundTrip = HutaoCloudGacha.parseItem(JSON.parse(HutaoCloudJson.preserveIds(body)).Items[0], '600000001');
  assert.equal(roundTrip.gachaId, item.gachaId); assert.equal(roundTrip.time, item.time);
  const older = new GachaItem(); older.gachaType = 301; older.gachaId = '1740733076123456780';
  assert.equal(HutaoCloudGacha.endIds([item, older])['301'], older.gachaId);
  assert.ok(HutaoCloudGacha.retrieveBody('600000001', [item, older]).includes('"301":1740733076123456780'));
  item.gachaId = '1,"Cookie":"fixture"';
  assert.throws(() => HutaoCloudGacha.uploadBody('600000001', [item]), /无效/);
  await assert.rejects(HutaoCloudClient.request('https://evil.test/'), /无效/);
  await assert.rejects(HutaoCloudClient.request('//evil.test/'), /无效/);
  const ciphertext = await HutaoCloudClient.encrypt('synthetic-password');
  assert.equal(Buffer.from(ciphertext, 'base64').length, 256);
  await assert.rejects(HutaoCloudClient.encrypt('X'.repeat(215)), /长度/);
  payload = `{"retcode":0,"data":[{"Id":${maxId}}]}`;
  const data = await HutaoCloudClient.request('/GachaLog/Entries', '', 'fixture-cloud-token');
  assert.equal(data[0].Id, maxId);
  const request = sent.at(-1);
  assert.equal(request.url, 'https://homa.snaphutaorp.org/GachaLog/Entries');
  assert.equal(request.options.header.Authorization, 'Bearer fixture-cloud-token');
  assert.equal(request.options.header.Cookie, undefined);
  assert.equal(request.options.maxRedirects, 0);
  assert.equal(request.options.usingCache, false);
  await HutaoCloudClient.request('/Statistics/Overview?Last=false');
  assert.equal(sent.at(-1).options.header.Authorization, undefined);
  payload = '{"retcode":-100,"message":"Login required"}';
  await assert.rejects(HutaoCloudClient.request('/GachaLog/Entries'), /Login required/);
  payload = '{"data":{}}';
  await assert.rejects(HutaoCloudClient.request('/GachaLog/Entries'), /请求失败/);
  status = 503;
  await assert.rejects(HutaoCloudClient.request('/Statistics/Overview'), /503/);
  console.log('cloud-protocol: PASS (Int64, merged pool cursors, server timezones, RSA wire parameters, isolated bearer transport, error propagation)');
})().catch(error => { console.error(error); process.exitCode = 1; });
