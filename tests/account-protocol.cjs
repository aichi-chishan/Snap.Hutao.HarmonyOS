// Offline contract tests: no real credentials or network access.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const base = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
const sent = [];
const network = { http: {
  RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 0 }, ResponseCode: { OK: 200 },
  createHttp: () => ({ request: async (url, options) => { sent.push({ url, options }); return { responseCode: 200, result: '{"retcode":0,"data":{}}', header: {} }; }, destroy() {} })
} };
function load(name) {
  const file = path.resolve(base, name.endsWith('.ets') ? name : `${name}.ets`);
  if (cache.has(file)) return cache.get(file);
  const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const module = { exports: {} };
  const req = id => {
    if (id === '@kit.NetworkKit') return network;
    if (id.endsWith('/Logger')) return { Logger: { warn() {}, info() {}, error() {} } };
    return load(path.relative(base, path.resolve(path.dirname(file), id)));
  };
  vm.runInNewContext(`(function(require,module,exports){${output}\n})`, {})(req, module, module.exports);
  cache.set(file, module.exports);
  return module.exports;
}
(async () => {
  const { CredentialPolicy } = load('common/CredentialPolicy');
  const { RegionUtil } = load('common/Constants');
  const { HoyolabEndpoints } = load('common/HoyolabEndpoints');
  const { User } = load('model/User');
  const { ApiClient } = load('data/network/ApiClient');
  for (const bad of [
    'http://api-takumi.mihoyo.com/path', 'https://api-takumi.mihoyo.com.evil.test/path',
    'https://api-takumi.mihoyo.com@evil.test/path', 'https://evil.test/?https://api-takumi.mihoyo.com',
    'https://api-takumi.mihoyo.com:444/path', 'https://api.github.com/repos/a/b',
    'https://api.snaphutaorp.org/Passport/v2/Login',
  ]) assert.equal(CredentialPolicy.accountRegion(bad), '', bad);
  assert.equal(CredentialPolicy.accountRegion('HTTPS://API-TAKUMI.MIHOYO.COM:443/path'), 'cn');
  assert.equal(CredentialPolicy.allowsSessionCookie('https://bbs-api-os.hoyolab.com/', false), false);
  assert.equal(CredentialPolicy.logUrl('https://api-takumi.mihoyo.com/auth?stoken=fixture#private'), 'https://api-takumi.mihoyo.com/auth');
  assert.equal(CredentialPolicy.logUrl('https://user:password@host/path'), '[redacted-url]');
  for (const [uid, region] of Object.entries({ '100000001': 'cn_gf01', '500000001': 'cn_qd01', '600000001': 'os_usa', '700000001': 'os_euro', '800000001': 'os_asia', '900000001': 'os_cht', '1800000001': 'os_asia', '1100000001': 'cn_gf01' })) {
    assert.equal(RegionUtil.regionOfUid(uid), region);
    assert.equal(RegionUtil.isCnUid(uid), region.startsWith('cn_'));
  }
  for (const bad of ['', '1', '012345678', '2800000001', '80000000X', '12345678901']) assert.equal(RegionUtil.regionOfUid(bad), '');
  assert.equal(HoyolabEndpoints.gameRecordUrl('hard_challenge/popularity', 'os_asia'), 'https://sg-public-api.hoyolab.com/event/game_record/genshin/api/hard_challenge/popularity');
  assert.equal(HoyolabEndpoints.signActId('os_euro'), 'e202102251931481');
  const user = new User(); user.isOversea = true;
  const cookie = 'stuid_v2=42; stoken_v2=fixture-stoken; account_id_v2=42; account_mid_v2=fixture-mid; cookie_token_v2=fixture-cookie; ltuid_v2=42; ltmid_v2=fixture-mid; ltoken_v2=fixture-ltoken';
  assert.equal(user.applyCookie(cookie), true);
  assert.equal(user.accountId, '42'); assert.equal(user.mid, 'fixture-mid');
  const copy = user.clone(); assert.equal(copy.isOversea, true);
  for (const field of ['stuidV2', 'stokenV2', 'accountMidV2', 'cookieTokenV2', 'ltuidV2', 'ltmidV2', 'ltokenV2']) assert.equal(copy[field], user[field]);
  assert.ok(copy.gameRecordCookie().includes('account_mid_v2=fixture-mid'));
  assert.ok(copy.fullCookie().includes('stoken_v2=fixture-stoken'));
  const client = ApiClient.getInstance(); client.setCookie('fixture-secret', false);
  await client.get('https://api.github.com/repos/test/test', {});
  assert.equal(sent.at(-1).options.header.Cookie, undefined);
  await client.get('https://api.github.com/repos/test/test', { cookie: 'fixture-secret' });
  assert.equal(sent.at(-1).options.header.Cookie, undefined);
  await client.get('https://api-takumi.mihoyo.com/path', {});
  assert.equal(sent.at(-1).options.header.Cookie, 'fixture-secret');
  assert.equal(sent.at(-1).options.maxRedirects, 0);
  assert.equal(sent.at(-1).options.usingCache, false);
  await client.get('https://bbs-api-os.hoyolab.com/path', {});
  assert.equal(sent.at(-1).options.header.Cookie, undefined);
  client.setCookie('fixture-os-secret', true);
  await client.get('https://bbs-api-os.hoyolab.com/path', {});
  assert.equal(sent.at(-1).options.header.Cookie, 'fixture-os-secret');
  await client.get('https://api-takumi.mihoyo.com/path', {});
  assert.equal(sent.at(-1).options.header.Cookie, undefined);
  console.log('account-protocol: PASS (UID, endpoint, v2 cookie, cross-region/cross-domain transport and redirect contracts)');
})().catch(error => { console.error(error); process.exitCode = 1; });
