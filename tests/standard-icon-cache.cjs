// Execute the production service with host sandbox files and deterministic HTTP doubles.
// Native API contracts were checked against official OpenHarmony file.fs/http references;
// this is not an ArkTS compiler, live-network, PNG decoder, or device-rendering test.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const file = path.resolve(__dirname, '../entry/src/main/ets/data/remote/StandardIconService.ets');
const source = fs.readFileSync(file, 'utf8');
const compiled = ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
}, reportDiagnostics: true });
assert.equal(compiled.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
const png = () => Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aC4kAAAAASUVORK5CYII=', 'base64');
const buffer = value => Uint8Array.from(value).buffer;
const success = () => ({ responseCode: 200, result: buffer(png()) });
const deferred = () => { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; }); return { promise, resolve, reject }; };
function harness() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hutao-standard-icon-'));
  const cache = path.join(root, 'cache'); fs.mkdirSync(cache);
  const state = { fail: '', shortRead: false, cleanFailure: false };
  const requests = [], clients = [], opens = [], writes = [], renames = [], cleanups = [], temps = [], logs = [];
  const handles = new Set();
  const modes = { READ_ONLY: fs.constants.O_RDONLY, READ_WRITE: fs.constants.O_RDWR,
    CREATE: fs.constants.O_CREAT, NOFOLLOW: fs.constants.O_NOFOLLOW };
  const io = {
    OpenMode: modes,
    lstatSync: p => fs.lstatSync(p),
    mkdirSync: p => fs.mkdirSync(p),
    openSync: (p, flags) => { if (state.fail === 'open' && (flags & modes.CREATE)) throw Error('open failed');
      const fd = fs.openSync(p, flags); handles.add(fd); opens.push({ path: p, flags }); return { fd }; },
    closeSync: f => { fs.closeSync(f.fd); handles.delete(f.fd); if (state.fail === 'close') throw Error('close failed'); },
    readSync: (fd, bytes) => fs.readSync(fd, Buffer.from(bytes), 0, state.shortRead ? bytes.byteLength - 1 : bytes.byteLength, null),
    writeSync: (fd, bytes) => {
      if (state.fail === 'write') throw Error('write failed');
      const payload = Buffer.from(bytes); const count = state.fail === 'short' ? payload.length - 1 : payload.length;
      writes.push(Buffer.from(payload)); return fs.writeSync(fd, payload, 0, count, null);
    },
    fsyncSync: fd => { if (state.fail === 'sync') throw Error('sync failed'); fs.fsyncSync(fd); },
    mkdtempSync: prefix => { assert.ok(prefix.endsWith('XXXXXX')); const p = fs.mkdtempSync(prefix.slice(0, -6)); temps.push(p); return p; },
    renameSync: (from, to) => { if (state.fail === 'rename') throw Error('rename failed');
      assert.ok(temps.some(tmp => from === path.join(tmp, 'image.png'))); assert.equal(handles.size, 0, 'close staged file before publication');
      renames.push({ from, to }); fs.renameSync(from, to); },
    rmdirSync: p => {
      assert.ok(temps.includes(p), 'cleanup must target only an OS-created directory owned by this invocation');
      cleanups.push(p); if (state.cleanFailure) throw Error('cleanup failed'); fs.rmSync(p, { recursive: true });
    },
  };
  const mocks = {
    '@kit.CoreFileKit': { fileIo: io },
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 1 }, ResponseCode: { OK: 200 },
      createHttp: () => {
        if (state.fail === 'create') throw Error('create failed');
        const client = { destroyed: 0, request: (url, options) => { const d = deferred(); requests.push({ url, options, ...d }); return d.promise; },
          destroy: () => { client.destroyed++; } }; clients.push(client); return client;
      } } },
    '../../common/AppContext': { AppContextProvider: { getCacheDir: () => cache } },
    '../../common/Logger': { Logger: { warn: (...args) => logs.push(args) } },
  };
  const module = { exports: {} };
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`, { ArrayBuffer, Uint8Array })(
    id => { assert.ok(Object.hasOwn(mocks, id), id); return mocks[id]; }, module, module.exports);
  const Service = module.exports.StandardIconService;
  const cleanup = () => { for (const fd of handles) fs.closeSync(fd); fs.rmSync(root, { recursive: true }); };
  return { root, cache, state, Service, requests, clients, opens, writes, renames, cleanups, temps, logs, cleanup };
}
async function withHarness(work) { const h = harness(); try { await work(h); } finally { h.cleanup(); } }
const ensure = h => h.Service.ensure('AvatarIcon', 'UI_AvatarIcon_Test');
const destination = h => h.Service.localPath('AvatarIcon', 'UI_AvatarIcon_Test');
const prepare = h => fs.mkdirSync(path.dirname(destination(h)), { recursive: true });

test('invalid path segments fail before filesystem/network work', () => withHarness(async h => {
  for (const [category, name] of [['../outside', 'A'], ['AvatarIcon', '../outside'], ['AvatarIcon', 'A/B'], ['', 'A'],
    ['AvatarIcon', 'https://host/A'], ['AvatarIcon', 'a'.repeat(252)], ['AvatarIcon', '%2e%2e'], ['AvatarIcon', 'a\\b']]) {
    assert.equal(h.Service.localPath(category, name), ''); assert.equal(await h.Service.ensure(category, name), '');
  }
  assert.equal(h.requests.length, 0); assert.equal(h.opens.length, 0); assert.deepEqual(fs.readdirSync(h.cache), []);
}));

test('cold concurrent calls share one bounded HTTP request and publish complete PNG once', () => withHarness(async h => {
  const a = ensure(h), b = ensure(h); assert.equal(h.requests.length, 1);
  const request = h.requests[0];
  assert.equal(request.url, 'https://api.snaphutaorp.org/static/raw/AvatarIcon/UI_AvatarIcon_Test.png');
  assert.equal(request.options.maxLimit, 8 * 1024 * 1024); assert.equal(request.options.maxRedirects, 0);
  assert.equal(request.options.readTimeout, 20000); assert.equal(request.options.connectTimeout, 10000); assert.equal(request.options.usingCache, false);
  request.resolve(success()); assert.deepEqual(await Promise.all([a, b]), [destination(h), destination(h)]);
  assert.deepEqual(fs.readFileSync(destination(h)), png()); assert.equal(h.renames.length, 1); assert.equal(h.writes.length, 1);
  assert.equal(h.temps.length, 1); assert.equal(fs.existsSync(h.temps[0]), false); assert.equal(h.clients[0].destroyed, 1);
  assert.ok(h.opens.filter(o => o.flags & fs.constants.O_CREAT).every(o => o.path.startsWith(h.temps[0] + '/')));
  assert.equal(await ensure(h), destination(h)); assert.equal(h.requests.length, 1, 'valid cache needs no HTTP');
}));

test('evicted positive cache is downloaded again and parent directories are created on first use', () => withHarness(async h => {
  assert.equal(fs.existsSync(path.dirname(destination(h))), false);
  let p = ensure(h); h.requests[0].resolve(success()); await p;
  assert.equal(fs.existsSync(path.dirname(destination(h))), true);
  fs.unlinkSync(destination(h)); p = ensure(h); assert.equal(h.requests.length, 2); h.requests[1].resolve(success());
  assert.equal(await p, destination(h)); assert.deepEqual(fs.readFileSync(destination(h)), png());
}));

for (const failure of ['http', 'network', 'create']) {
  test(`${failure} failure is retryable and clears admission`, () => withHarness(async h => {
    if (failure === 'create') h.state.fail = 'create';
    let p = ensure(h);
    if (failure === 'http') h.requests[0].resolve({ responseCode: 503, result: buffer([]) });
    if (failure === 'network') h.requests[0].reject(Error('network unavailable'));
    assert.equal(await p, ''); h.state.fail = '';
    p = ensure(h); h.requests.at(-1).resolve(success()); assert.equal(await p, destination(h));
    assert.ok(h.clients.every(c => c.destroyed === 1));
  }));
}

test('a blocked parent can recover; symlink directories are never followed', () => withHarness(async h => {
  const remote = path.join(h.cache, 'remote'); fs.writeFileSync(remote, 'blocked');
  assert.equal(await ensure(h), ''); assert.equal(h.requests.length, 0); fs.unlinkSync(remote);
  const outside = path.join(h.root, 'outside'); fs.mkdirSync(outside); fs.symlinkSync(outside, remote);
  assert.equal(await ensure(h), ''); assert.equal(h.requests.length, 0); assert.deepEqual(fs.readdirSync(outside), []);
  fs.unlinkSync(remote); const p = ensure(h); h.requests[0].resolve(success()); assert.equal(await p, destination(h));
}));

for (const malformed of ['empty', 'truncated', 'html', 'string', 'typed-array', 'oversized']) {
  test(`${malformed} response cannot publish a cache file`, () => withHarness(async h => {
    let payload;
    if (malformed === 'empty') payload = new ArrayBuffer(0);
    if (malformed === 'truncated') payload = buffer(png().subarray(0, 8));
    if (malformed === 'html') payload = buffer(Buffer.from('<html>' + 'invalid'.repeat(15)));
    if (malformed === 'string') payload = 'not binary';
    if (malformed === 'typed-array') payload = new Uint8Array(png());
    if (malformed === 'oversized') { const bytes = new Uint8Array(h.Service.MAX_BYTES + 1); bytes.set(png()); payload = bytes.buffer; }
    const p = ensure(h); h.requests[0].resolve({ responseCode: 200, result: payload }); assert.equal(await p, '');
    assert.equal(fs.existsSync(destination(h)), false); assert.equal(h.temps.length, 0); assert.equal(h.clients[0].destroyed, 1);
    const retry = ensure(h); h.requests[1].resolve(success()); assert.equal(await retry, destination(h));
  }));
}

for (const failure of ['open', 'write', 'short', 'sync', 'close', 'rename']) {
  test(`${failure} during publication preserves old destination and cleans only owned temporary output`, () => withHarness(async h => {
    prepare(h); const previous = Buffer.from('previous invalid cache, retained until a replacement is complete');
    fs.writeFileSync(destination(h), previous);
    const foreign = path.join(path.dirname(destination(h)), '.standard-icon-foreign'); fs.mkdirSync(foreign); fs.writeFileSync(path.join(foreign, 'keep'), 'untouched');
    h.state.fail = failure; let p = ensure(h); h.requests[0].resolve(success()); assert.equal(await p, '');
    assert.deepEqual(fs.readFileSync(destination(h)), previous); assert.equal(fs.readFileSync(path.join(foreign, 'keep'), 'utf8'), 'untouched');
    assert.ok(h.temps.every(tmp => !fs.existsSync(tmp))); assert.equal(h.renames.length, 0); h.state.fail = '';
    p = ensure(h); h.requests[1].resolve(success()); assert.equal(await p, destination(h)); assert.deepEqual(fs.readFileSync(destination(h)), png());
  }));
}

test('invalid/symlink cached files are replaced without writing through a link', () => withHarness(async h => {
  prepare(h); const outside = path.join(h.root, 'foreign.png'); fs.writeFileSync(outside, 'must survive'); fs.symlinkSync(outside, destination(h));
  const p = ensure(h); h.requests[0].resolve(success()); assert.equal(await p, destination(h));
  assert.equal(fs.lstatSync(destination(h)).isSymbolicLink(), false); assert.equal(fs.readFileSync(outside, 'utf8'), 'must survive');
}));

test('another valid writer winning during HTTP is retained; unrelated keys remain independent', () => withHarness(async h => {
  const a = ensure(h), b = h.Service.ensure('AvatarIcon', 'Other'); assert.equal(h.requests.length, 2);
  fs.writeFileSync(destination(h), png()); h.requests[0].resolve(success()); assert.equal(await a, destination(h));
  assert.equal(h.temps.length, 0, 'already valid destination is not needlessly overwritten');
  h.requests[1].resolve(success()); assert.equal(await b, h.Service.localPath('AvatarIcon', 'Other')); assert.equal(h.renames.length, 1);
}));

test('cleanup failure cannot delete published data or turn it into a partial file', () => withHarness(async h => {
  h.state.cleanFailure = true; const p = ensure(h); h.requests[0].resolve(success()); assert.equal(await p, destination(h));
  assert.deepEqual(fs.readFileSync(destination(h)), png()); assert.equal(h.temps.length, 1);
  assert.deepEqual(fs.readdirSync(h.temps[0]), [], 'successful rename left only an empty owned directory');
  assert.equal(await ensure(h), destination(h)); assert.equal(h.requests.length, 1);
}));

const flush = async () => { for (let index = 0; index < 12; index++) await Promise.resolve(); };
const apiUrl = 'https://api.snaphutaorp.org/static/raw/AvatarIcon/UI_AvatarIcon_Test.png';
const staticUrl = 'https://static.snaphutaorp.org/static/raw/AvatarIcon/UI_AvatarIcon_Test.png';
const redirect = (location = staticUrl, code = 302) => ({ responseCode: code, header: { location }, result: buffer([]) });

for (const status of [301, 302, 303, 307, 308]) {
  test(`${status} permits exactly the configured api-to-static same-path hop`, () => withHarness(async h => {
    const a = ensure(h), b = ensure(h); assert.equal(h.requests.length, 1); assert.equal(h.requests[0].url, apiUrl);
    h.requests[0].resolve({ responseCode: status, header: { LoCaTiOn: staticUrl }, result: buffer([]) }); await flush();
    assert.equal(h.requests.length, 2); assert.equal(h.requests[1].url, staticUrl); assert.equal(h.clients[0].destroyed, 1);
    const c = ensure(h); assert.equal(h.requests.length, 2, 'single-flight remains held throughout both hops');
    for (const req of h.requests) {
      assert.equal(req.options.maxRedirects, 0); assert.equal(req.options.maxLimit, 8 * 1024 * 1024);
      assert.equal(req.options.connectTimeout, 10000); assert.equal(req.options.readTimeout, 20000);
      assert.equal(req.options.usingCache, false); assert.equal(req.options.method, 'GET');
    }
    h.requests[1].resolve(success()); assert.deepEqual(await Promise.all([a, b, c]), [destination(h), destination(h), destination(h)]);
    assert.deepEqual(fs.readFileSync(destination(h)), png()); assert.equal(h.renames.length, 1);
    assert.ok(h.clients.every(client => client.destroyed === 1));
  }));
}

const aliases = { Anemo: 'Wind', Cryo: 'Ice', Dendro: 'Grass', Electro: 'Electric', Geo: 'Rock', Hydro: 'Water', Pyro: 'Fire' };
for (const [localName, sourceName] of Object.entries(aliases)) {
  test(`IconElement ${localName} uses canonical ${sourceName} across redirect but retains local identity`, () => withHarness(async h => {
    const name = `UI_Icon_Element_${localName}`;
    const relative = `IconElement/UI_Icon_Element_${sourceName}.png`;
    const result = h.Service.ensure('IconElement', name);
    assert.equal(h.requests[0].url, `https://api.snaphutaorp.org/static/raw/${relative}`);
    h.requests[0].resolve(redirect(`https://static.snaphutaorp.org/static/raw/${relative}`)); await flush();
    assert.equal(h.requests[1].url, `https://static.snaphutaorp.org/static/raw/${relative}`);
    h.requests[1].resolve(success()); const file = await result;
    assert.equal(file, h.Service.localPath('IconElement', name)); assert.ok(file.endsWith(`/${name}.png`));
    assert.deepEqual(fs.readFileSync(file), png()); assert.equal(await h.Service.ensure('IconElement', name), file);
    assert.equal(h.requests.length, 2, 'canonical source does not change local cache identity');
  }));
}

test('element aliases apply only to exact IconElement identities; canonical and unrelated names are unchanged', () => withHarness(async h => {
  for (const [category, name] of [['AvatarIcon', 'UI_Icon_Element_Anemo'], ['ItemIcon', 'UI_Icon_Element_Pyro'],
    ['IconElement', 'UI_Icon_Element_Wind'], ['IconElement', 'UI_Icon_Element_Unknown'], ['Bg', 'UI_Icon_None']]) {
    const result = h.Service.ensure(category, name);
    assert.equal(h.requests.at(-1).url, `https://api.snaphutaorp.org/static/raw/${category}/${name}.png`);
    h.requests.at(-1).resolve(success()); assert.equal(await result, h.Service.localPath(category, name));
  }
}));

const refusedLocations = [
  staticUrl.replace('https:', 'http:'),
  staticUrl.replace('static.snaphutaorp.org', 'evil.example'),
  staticUrl.replace('static.snaphutaorp.org', 'static.snaphutaorp.org.evil.example'),
  staticUrl.replace('static.snaphutaorp.org', 'user@static.snaphutaorp.org'),
  staticUrl.replace('static.snaphutaorp.org', 'user:pass@static.snaphutaorp.org'),
  staticUrl.replace('static.snaphutaorp.org', 'static.snaphutaorp.org:443'),
  staticUrl.replace('static.snaphutaorp.org', 'static.snaphutaorp.org:8443'),
  staticUrl.replace('/AvatarIcon/', '/ItemIcon/'),
  staticUrl.replace('/UI_AvatarIcon_Test.png', '/other.png'),
  staticUrl.replace('/static/raw/', '/static/../static/raw/'),
  staticUrl.replace('/AvatarIcon/', '/%41vatarIcon/'),
  staticUrl + '?download=1', staticUrl + '#image', ` ${staticUrl}`, `${staticUrl} `,
  staticUrl.replace('https://', '//'), '/static/raw/AvatarIcon/UI_AvatarIcon_Test.png', '',
  staticUrl.replace('static.snaphutaorp.org', 'htserver.wdg12.work'), apiUrl,
];
for (let index = 0; index < refusedLocations.length; index++) {
  test(`redirect refusal ${index + 1} makes no untrusted or altered-path request`, () => withHarness(async h => {
    const result = ensure(h); h.requests[0].resolve(redirect(refusedLocations[index]));
    assert.equal(await result, ''); assert.equal(h.requests.length, 1); assert.equal(h.temps.length, 0);
    assert.equal(fs.existsSync(destination(h)), false); assert.equal(h.clients[0].destroyed, 1);
  }));
}

for (const header of [undefined, null, {}, [], { location: null }, { location: [staticUrl] },
  { Location: staticUrl, location: staticUrl }, { location: `${staticUrl}, ${staticUrl}` }]) {
  test(`missing or ambiguous redirect header ${JSON.stringify(header)} fails closed`, () => withHarness(async h => {
    const result = ensure(h); h.requests[0].resolve({ responseCode: 302, header, result: buffer([]) });
    assert.equal(await result, ''); assert.equal(h.requests.length, 1); assert.equal(h.temps.length, 0);
  }));
}

for (const next of [apiUrl, staticUrl, 'https://evil.example/again']) {
  test(`second redirect ${next} is refused without a third request`, () => withHarness(async h => {
    const result = ensure(h); h.requests[0].resolve(redirect()); await flush();
    h.requests[1].resolve(redirect(next, 307)); assert.equal(await result, '');
    assert.equal(h.requests.length, 2); assert.equal(h.temps.length, 0); assert.ok(h.clients.every(c => c.destroyed === 1));
  }));
}

for (const invalid of ['html', 'oversized', 'network']) {
  test(`redirected ${invalid} response keeps PNG/budget/failure checks and remains retryable`, () => withHarness(async h => {
    const result = ensure(h); h.requests[0].resolve(redirect()); await flush();
    if (invalid === 'network') h.requests[1].reject(Error('second-hop network failure'));
    else {
      const bytes = invalid === 'html' ? buffer(Buffer.from('<html>' + 'invalid'.repeat(15))) : new ArrayBuffer(h.Service.MAX_BYTES + 1);
      h.requests[1].resolve({ responseCode: 200, result: bytes });
    }
    assert.equal(await result, ''); assert.equal(h.temps.length, 0); assert.equal(fs.existsSync(destination(h)), false);
    assert.ok(h.clients.every(client => client.destroyed === 1));
    const retry = ensure(h); assert.equal(h.requests[2].url, apiUrl); h.requests[2].resolve(success());
    assert.equal(await retry, destination(h));
  }));
}
