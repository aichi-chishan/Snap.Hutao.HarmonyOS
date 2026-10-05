// StandardIconService 远端回退的平台行为：API24 客户端在 maxRedirects=0 时对 3xx 直接抛 2300047，
// 拿不到 Location。本用例在内存 POSIX 沙箱里执行真实服务代码，确定性覆盖：
//   - 平台拒绝重定向 → 只按硬编码 static 主机同路径重试一次并成功发布；
//   - 平台返回 3xx 但 Location 不可信 → fail closed，不发起第二次请求；
//   - 真实网络错误 → 不触发 static 重试；
//   - 正常 302 → 校验 Location 后走 static。
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const file = path.resolve(__dirname, '../entry/src/main/ets/data/remote/StandardIconService.ets');
const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
}, reportDiagnostics: true });
assert.equal(compiled.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0, 'production source must transpile');
const png = () => Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aC4kAAAAASUVORK5CYII=', 'base64');
const buffer = value => Uint8Array.from(value).buffer;
const API = 'https://api.snaphutaorp.org/static/raw/AvatarIcon/UI_AvatarIcon_Test.png';
const STATIC = 'https://static.snaphutaorp.org/static/raw/AvatarIcon/UI_AvatarIcon_Test.png';
const DEST = '/cache/remote/AvatarIcon/UI_AvatarIcon_Test.png';

/** 内存 POSIX 沙箱：只实现 StandardIconService 实际调用的 fileIo 子集 */
function sandbox() {
  const dirs = new Set(['/cache', '/cache/remote', '/cache/remote/AvatarIcon']);
  const files = new Map();
  const stats = p => {
    if (dirs.has(p)) { return { isDirectory: () => true, isSymbolicLink: () => false, isFile: () => false, size: 0 }; }
    const bytes = files.get(p);
    if (bytes === undefined) { const error = new Error('ENOENT'); error.code = 'ENOENT'; throw error; }
    return { isDirectory: () => false, isSymbolicLink: () => false, isFile: () => true, size: bytes.byteLength };
  };
  const handles = new Map();
  const tempDirs = new Set();
  let nextFd = 1;
  const io = {
    OpenMode: { READ_ONLY: 1, READ_WRITE: 2, CREATE: 4, TRUNC: 8, NOFOLLOW: 16 },
    lstatSync: stats,
    mkdirSync: p => { if (dirs.has(p)) { throw new Error('EEXIST'); } dirs.add(p); },
    mkdtempSync: prefix => { const dir = prefix.replace('XXXXXX', 'stage' + nextFd++); dirs.add(dir); tempDirs.add(dir); return dir; },
    openSync: (p, flags) => { if (!dirs.has(p.substring(0, p.lastIndexOf('/')))) { throw new Error('ENOENT'); } const fd = nextFd++; handles.set(fd, p); return { fd }; },
    writeSync: (fd, bytes) => { const p = handles.get(fd); assert.ok(p, 'write requires an open handle'); const copy = new Uint8Array(bytes); files.set(p, copy); return copy.byteLength; },
    readSync: (fd, into) => { const p = handles.get(fd); const bytes = files.get(p); assert.ok(bytes, 'read requires an existing file'); new Uint8Array(into).set(bytes); return bytes.byteLength; },
    fsyncSync: () => {},
    closeSync: handle => { assert.ok(handles.has(handle.fd), 'close requires an open handle'); handles.delete(handle.fd); },
    renameSync: (from, to) => { assert.ok(files.has(from), 'rename source must exist'); files.set(to, files.get(from)); files.delete(from); },
    rmdirSync: p => { assert.ok(tempDirs.has(p), 'cleanup may only remove an OS-created staging directory'); tempDirs.delete(p); dirs.delete(p); },
  };
  return { io, dirs, files, handles, tempDirs };
}

/** 依次消费预设响应；每项为 {response} 或 {error} */
function harness(responses) {
  const box = sandbox();
  const requests = [];
  const logs = [];
  const http = {
    RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 1 }, ResponseCode: { OK: 200 },
    createHttp: () => ({ destroy() {}, request: async (url, options) => {
      requests.push({ url, options });
      const step = responses[requests.length - 1];
      assert.ok(step, 'unexpected extra HTTP request: ' + url);
      if (step.error) { throw step.error; }
      return step.response;
    } }),
  };
  const mocks = {
    '@kit.CoreFileKit': { fileIo: box.io },
    '@kit.NetworkKit': { http },
    '@kit.BasicServicesKit': { BusinessError: class BusinessError extends Error {} },
    '../../common/AppContext': { AppContextProvider: { getCacheDir: () => '/cache' } },
    '../../common/Logger': { Logger: { info: () => {}, warn: (tag, message) => logs.push(String(message)), error: () => {} } },
  };
  const module = { exports: {} };
  // 同 realm 执行：production 用 instanceof ArrayBuffer 做类型闸门，跨 realm 会误判
  vm.runInThisContext('(function(require,module,exports){' + compiled.outputText + '\n})')
    (id => { assert.ok(Object.hasOwn(mocks, id), 'unexpected production dependency: ' + id); return mocks[id]; }, module, module.exports);
  return { Service: module.exports.StandardIconService, requests, logs, box };
}

const businessError = (code, message) => { const error = new Error(message); error.code = code; return error; };
const redirect = (location, code = 302) => ({ response: { responseCode: code, header: { location }, result: buffer([]) } });
const ok = () => ({ response: { responseCode: 200, result: buffer(png()) } });

(async () => {
  // 1) 平台拒绝跟随重定向（真机 API24 行为）：只按固定 static 同路径重试一次并发布
  {
    const h = harness([
      { error: businessError(2300047, 'The number of redirections reaches the maximum allowed') },
      ok(),
    ]);
    assert.equal(await h.Service.ensure('AvatarIcon', 'UI_AvatarIcon_Test'), DEST);
    assert.equal(h.requests.length, 2, 'api attempt plus exactly one pinned retry');
    assert.equal(h.requests[0].url, API);
    assert.equal(h.requests[1].url, STATIC, 'retry must use the hard-coded static host and identical path');
    assert.equal(h.requests[0].options.maxRedirects, 0);
    assert.deepEqual(Array.from(h.box.files.get(DEST)), Array.from(png()));
    assert.equal(h.box.handles.size, 0, 'no handle may leak');
    assert.equal(h.box.tempDirs.size, 0, 'staging directory must be removed');
  }
  // 2) 平台返回 3xx 但 Location 不可信：fail closed，不发起第二次请求
  {
    const h = harness([redirect('https://evil.example/static/raw/AvatarIcon/UI_AvatarIcon_Test.png')]);
    assert.equal(await h.Service.ensure('AvatarIcon', 'UI_AvatarIcon_Test'), '');
    assert.equal(h.requests.length, 1, 'an untrusted location must not trigger any further request');
    assert.equal(h.box.files.size, 0);
  }
  // 3) 真实网络错误：不得用 static 重试掩盖
  {
    const h = harness([{ error: businessError(2300006, "Couldn't resolve host name") }]);
    assert.equal(await h.Service.ensure('AvatarIcon', 'UI_AvatarIcon_Test'), '');
    assert.equal(h.requests.length, 1, 'a transport failure is not a redirect refusal');
  }
  // 4) 正常 302：校验 Location 完全一致后走 static
  {
    const h = harness([redirect(STATIC), ok()]);
    assert.equal(await h.Service.ensure('AvatarIcon', 'UI_AvatarIcon_Test'), DEST);
    assert.equal(h.requests.length, 2);
    assert.equal(h.requests[1].url, STATIC);
  }
  // 5) 第二次响应仍是重定向：不得出现第三次请求
  {
    const h = harness([redirect(STATIC), redirect(API, 307)]);
    assert.equal(await h.Service.ensure('AvatarIcon', 'UI_AvatarIcon_Test'), '');
    assert.equal(h.requests.length, 2, 'redirect chains must stay bounded');
  }
  console.log('standard-icon-redirect-fallback: PASS (platform refusal retry, fail-closed location, transport errors, bounded chain)');
})().catch(error => { console.error(error); process.exitCode = 1; });
