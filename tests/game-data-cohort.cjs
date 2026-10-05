// Production ETS under host filesystem/HTTP/taskpool boundaries. No native scheduling claim.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const sourceRoot = path.join(root, 'entry/src/main/ets');
const remoteRoot = path.join(sourceRoot, 'data/remote');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const encode = text => Uint8Array.from(Buffer.from(text));
const compiled = new Map();
function loader(boundaries = {}) {
  const modules = new Map();
  function load(file) {
    file = path.resolve(file);
    if (modules.has(file)) return modules.get(file).exports;
    const name = path.basename(file, '.ets');
    if (boundaries[name]) return boundaries[name];
    if (!compiled.has(file)) compiled.set(file, ts.transpileModule(fs.readFileSync(file, 'utf8').replaceAll('@Concurrent\n', ''), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
    }).outputText);
    const module = { exports: {} }; modules.set(file, module);
    const code = compiled.get(file);
    vm.runInThisContext(`(function(require,module,exports){${code}\n})`, { filename: file })(specifier => {
      if (boundaries[specifier]) return boundaries[specifier];
      assert.ok(specifier.startsWith('.'), 'unmocked platform import: ' + specifier);
      return load(path.resolve(path.dirname(file), specifier) + '.ets');
    }, module, module.exports);
    return module.exports;
  }
  return name => load(path.join(remoteRoot, name + '.ets'));
}
const pure = loader();
const { GameDataManifestPolicy: P, ItemType } = pure('GameDataManifestPolicy');
const { GameDataSnapshotStore: Store } = pure('GameDataSnapshotStore');
const raw = new Map(P.METADATA.map(name => ['metadata/' + name, fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/metadata', name))]));
raw.set('icons/Test/sample.png', fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/icons/NameCardIcon/UI_NameCardIcon_Eula.png')));
const A = 'a'.repeat(40), B = 'b'.repeat(40), C = 'c'.repeat(40);
function manifest(revision = A, version = 'one', schema = 1, files = raw) {
  return { schema, channel: 'hutao-cn', channelVersion: version,
    ...(schema === 2 ? { upstreamSha: 'e'.repeat(40) } : {}),
    items: [...files].map(([name, bytes]) => ({ type: name.startsWith('metadata/') ? 'text' : 'icon', path: name,
      url: `${P.RAW_ROOT}main/${name}`, version: 1, ...(schema === 2 ? { size: bytes.length, sha256: sha(bytes) } : {}) })) };
}
function parsed(revision = A, version = 'one', schema = 1, files = raw) {
  return P.parse(JSON.stringify(manifest(revision, version, schema, files)), P.source(P.RAW_ROOT + 'main/manifest-hutao.json'), revision);
}
class MemoryIo {
  files = new Map(); dirs = new Set(); fail = ''; after = false; writes = [];
  encode = encode; decode = bytes => new TextDecoder('utf-8', { fatal: true }).decode(bytes); sha256 = sha;
  read(file, limit) { const bytes = this.files.get(file); if (!bytes || bytes.length > limit) throw new Error('missing/oversize'); return bytes.slice(); }
  write(file, bytes) { if (this.fail === 'write:' + file) throw new Error('fault'); this.files.set(file, bytes.slice()); this.writes.push(file); }
  mkdir(file) { this.dirs.add(file); }
  exists(file) { return this.files.has(file) || this.dirs.has(file) || [...this.files.keys()].some(key => key.startsWith(file + '/')); }
  rename(from, to) {
    if (this.fail === 'rename:' + to && !this.after) throw new Error('fault');
    if (this.files.has(from)) { this.files.set(to, this.files.get(from)); this.files.delete(from); }
    else for (const [name, bytes] of [...this.files]) if (name.startsWith(from + '/')) { this.files.set(to + name.slice(from.length), bytes); this.files.delete(name); }
    if (this.fail === 'rename:' + to && this.after) throw new Error('fault');
  }
}
function initialize(io) { const store = new Store('/data', io); store.adoptSelection(new Store('/data', io).prepare('selection'), true); return store; }
function stage(store, io, revision = A, version = 'one') {
  const id = revision + '-1791190000000-00000001', value = parsed(revision, version), directory = store.begin(id);
  for (const item of value.items) { const bytes = raw.get(item.path); item.size = bytes.length; item.sha256 = sha(bytes); io.write(directory + '/' + item.path, bytes); }
  io.write(directory + '/complete.json', encode(JSON.stringify(value)));
  return { id, value, prepared: new Store('/data', io).prepare('stage', id) };
}
function install(store, io, revision = A, version = 'one') { const s = stage(store, io, revision, version); store.publish(s.id, s.value, s.prepared, () => {}); return s; }
let count = 0;
async function test(name, fn) { await fn(); console.log('PASS ' + (++count) + ': ' + name); }

const sandboxes = [];
function environment() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hutao-cohort-')); sandboxes.push(directory);
  const state = { directory, prefs: new Map(), revision: A, version: 'one', schema: 1, files: new Map(raw), requests: [],
    free: 10 * 1024 ** 3, failUrl: '', requestGate: null, requestHook: null, workerFailure: '', workerGate: null,
    workerHook: null, workerResultHook: null, late: null, ioHook: null, uriCalls: [] };
  const handles = new Map(), locks = new Map(); let executing;
  const fileIo = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 2, CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC, NOFOLLOW: fs.constants.O_NOFOLLOW },
    openSync(file, flags) {
      state.ioHook?.('open', file);
      const fd = fs.openSync(file, flags), handle = { fd, file, locked: false,
        tryLock() { if (locks.has(file)) throw Object.assign(new Error('busy'), { code: 13900034 }); locks.set(file, this); this.locked = true; } };
      handles.set(fd, handle); return handle;
    },
    closeSync(handle) { if (handle.locked && locks.get(handle.file) === handle) locks.delete(handle.file); handles.delete(handle.fd); fs.closeSync(handle.fd); },
    lstatSync(file) { return fs.lstatSync(file); }, statSync(file) { return typeof file === 'number' ? fs.fstatSync(file) : fs.statSync(file); },
    readSync(fd, bytes) { state.ioHook?.('read', handles.get(fd).file); return fs.readSync(fd, Buffer.from(bytes), 0, bytes.byteLength, null); },
    writeSync(fd, bytes) { const result = state.ioHook?.('write', handles.get(fd).file); if (typeof result === 'number') return result; return fs.writeSync(fd, Buffer.from(bytes)); },
    fsyncSync(fd) { state.ioHook?.('fsync', handles.get(fd).file); fs.fsyncSync(fd); },
    mkdirSync(file) { state.ioHook?.('mkdir', file); fs.mkdirSync(file); },
    renameSync(from, to) { state.ioHook?.('rename', to); fs.renameSync(from, to); },
    listFileSync(file, options) { return fs.readdirSync(file, { recursive: options.recursion }).slice(0, options.listNum); },
  };
  const taskpool = {
    Task: class { constructor(fn, ...args) { this.fn = fn; this.args = args; } static isCanceled() { return false; } },
    async execute(task, configs) {
      assert.ok(configs.timeout > 0 && configs.timeout <= 60000);
      state.workerHook?.(task);
      if (state.workerGate) await state.workerGate;
      if (state.workerFailure === task.args[1]) { state.late = task; throw new Error('worker timed out'); }
      executing = task; let result; try { result = structuredClone(task.fn(...task.args)); } finally { executing = undefined; }
      return state.workerResultHook ? state.workerResultHook(result, task) : result;
    }
  };
  const http = { RequestMethod: { GET: 1 }, HttpDataType: { ARRAY_BUFFER: 1 }, ResponseCode: { OK: 200 }, createHttp() {
    return { destroy() {}, async request(url, options) {
      state.requests.push(url); assert.equal(options.maxRedirects, 0); assert.equal(options.usingCache, false); assert.ok(options.maxLimit <= P.MAX_FILE_BYTES);
      state.requestHook?.(url); if (state.requestGate) await state.requestGate;
      if (state.failUrl && url.endsWith(state.failUrl)) return { responseCode: 500, result: new ArrayBuffer(0) };
      let bytes;
      if (url.startsWith('https://api.github.com/repos/')) bytes = encode(JSON.stringify([{ sha: state.revision }]));
      else if (url === `${P.RAW_ROOT}${state.revision}/manifest-hutao.json`) bytes = encode('\uFEFF' + JSON.stringify(manifest(state.revision, state.version, state.schema, state.files)));
      else { const prefix = P.RAW_ROOT + state.revision + '/'; assert.ok(url.startsWith(prefix), 'unpinned URL: ' + url); bytes = state.files.get(url.slice(prefix.length)); assert.ok(bytes, url); }
      return { responseCode: 200, result: Uint8Array.from(bytes).buffer };
    } };
  } };
  const boundaries = {
    '@kit.CoreFileKit': { fileIo, fileUri: { getUriFromPath(file) { state.uriCalls.push(file); return 'file://bundle/' + encodeURIComponent(file); } }, statfs: { getFreeSizeSync: () => state.free } },
    '@kit.ArkTS': { taskpool, util: { TextEncoder: class { encodeInto(text) { return encode(text); } }, TextDecoder: { create: (_, options) => ({ decodeToString: bytes => new TextDecoder('utf-8', options).decode(bytes) }) } } },
    '@kit.NetworkKit': { http },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd() { const hash = crypto.createHash('sha256'); return { updateSync(blob) { hash.update(blob.data); }, digestSync() { return { data: hash.digest() }; }, async update(blob) { hash.update(blob.data); }, async digest() { return { data: hash.digest() }; } }; } } },
    AppContext: { AppContextProvider: { getFilesDir: () => directory, getResourceManager: () => ({ async getRawFileContent(name) { return Uint8Array.from(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile', name))); } }) } },
    PreferencesStore: { PreferencesStore: { getString: (key, fallback) => state.prefs.get(key) ?? fallback, setString: (key, value) => state.prefs.set(key, value) } },
    Logger: { Logger: { info() {}, warn() {} } },
  };
  state.runtime = () => loader(boundaries);
  state.updater = async () => { const U = state.runtime()('GameDataUpdater').GameDataUpdater; await U.initializeSnapshot(); return U; };
  return state;
}
(async () => {
  await test('trusted v1 BOM and v2 manifests pin every item to one immutable commit', () => {
    const source = P.source(P.RAW_ROOT + 'main/manifest-hutao.json');
    const value = P.parse('\uFEFF' + JSON.stringify(manifest()), source, A);
    assert.equal(value.items.length, 18); assert.ok(value.items.every(item => item.url.startsWith(P.RAW_ROOT + A + '/')));
    assert.equal(parsed(A, 'two', 2).items[0].sha256.length, 64);
    assert.equal(P.parse(JSON.stringify(manifest()), P.source(P.RAW_ROOT + A + '/manifest-hutao.json'), A).sourceRevision, A);
  });
  await test('untrusted source protocols, hosts, credentials, ports and URL suffixes fail closed', () => {
    for (const url of ['http://raw.githubusercontent.com/aichi-chishan/snap-hutao-data/main/manifest-hutao.json',
      'https://evil@raw.githubusercontent.com/aichi-chishan/snap-hutao-data/main/manifest-hutao.json',
      P.RAW_ROOT.replace('.com/', '.com.evil/') + 'main/manifest-hutao.json',
      P.RAW_ROOT + 'main/manifest-hutao.json?x=1', P.RAW_ROOT + '../manifest-hutao.json',
      P.RAW_ROOT + 'main\n/manifest-hutao.json', P.RAW_ROOT + 'main/manifest-other.json']) assert.throws(() => P.source(url), url);
    assert.equal(P.isRevision(A + '\n'), false); assert.equal(P.validId(A + '-1-00000001\n'), false);
  });
  await test('traversal, unknown types, duplicates, case collisions and foreign item URLs are rejected', () => {
    for (const mutate of [m => { m.items[0].path = '../outside'; }, m => { m.items[0].type = 'executable'; },
      m => m.items.push(m.items[0]), m => { m.items[0].url = 'https://example.com/data'; },
      m => { m.items[0].url = P.RAW_ROOT + B + '/' + m.items[0].path; },
      m => { m.items.push({ ...m.items.at(-1), path: 'icons/Test/Sample.png', url: P.RAW_ROOT + 'main/icons/Test/Sample.png' }); }]) {
      const m = manifest(); mutate(m); assert.throws(() => P.parse(JSON.stringify(m), P.source(P.RAW_ROOT + 'main/manifest-hutao.json'), A));
    }
    for (const file of ['icons/Test/../x.png', 'icons/Test/%2e.png', 'icons/Test/x.png\n', 'icons/Test/x.png?y', '/icons/Test/x.png']) assert.throws(() => P.validatePath(file, 'icon'));
  });
  await test('full required metadata and valid paired publisher hashes/sizes are mandatory', () => {
    for (const mutate of [m => m.items.shift(), m => { m.items[0].size = 10; }, m => { m.items[0].sha256 = 'a'.repeat(64); },
      m => { m.schema = 2; }, m => { m.channel = 'other'; }, m => { m.channelVersion = 'bad\n'; },
      m => { m.items[0].size = P.MAX_FILE_BYTES + 1; m.items[0].sha256 = 'a'.repeat(64); }]) {
      const m = manifest(); mutate(m); assert.throws(() => P.parse(JSON.stringify(m), P.source(P.RAW_ROOT + 'main/manifest-hutao.json'), A));
    }
    assert.throws(() => P.parse('null', P.source(P.RAW_ROOT + 'main/manifest-hutao.json'), A));
  });
  await test('bundled graph validates while broken identities, skill text and references are rejected', () => {
    const texts = new Map([...raw].filter(([file]) => file.startsWith('metadata/')).map(([file, bytes]) => [file, bytes.toString()]));
    P.validateModels(texts);
    for (const [name, mutate] of [['avatar_meta.json', x => { x.find(row => row.skills.length > 0).skills[0].d = 3; }],
      ['Achievement.json', x => { x[0].Goal = 999999; }], ['TowerSchedule.json', x => { x[0].FloorIds = [999999]; }],
      ['GachaEvent.json', x => { x[0].UpOrangeList = [999999]; }], ['WeaponCurve.json', x => { x[0].Curves[0].Value = 'bad'; }]]) {
      const copy = new Map(texts), data = JSON.parse(copy.get('metadata/' + name)); mutate(data);
      copy.set('metadata/' + name, JSON.stringify(data)); assert.throws(() => P.validateModels(copy), name);
    }
  });
  await test('PNG validation requires valid structure, CRCs, pixels and terminal IEND', () => {
    const item = parsed().items.at(-1), valid = Uint8Array.from(raw.get(item.path));
    P.validateBytes(item, valid, sha(valid));
    const headerOnly = new Uint8Array(24); headerOnly.set([137, 80, 78, 71, 13, 10, 26, 10]);
    const corrupt = valid.slice(); corrupt[30] ^= 1;
    for (const bytes of [headerOnly, valid.slice(0, -1), corrupt, Buffer.concat([valid, Buffer.from('extra')]), Buffer.from('<html>nginx 404</html>')]) assert.throws(() => P.validateBytes(item, bytes, sha(bytes)));
  });
  await test('publisher size/hash checks never accept actual mismatches', () => {
    const item = parsed(A, 'one', 2).items[0], bytes = raw.get(item.path);
    assert.throws(() => P.validateBytes(item, bytes.slice(1), sha(bytes.slice(1))));
    assert.throws(() => P.validateBytes(item, bytes, '0'.repeat(64)));
    assert.throws(() => P.validateBytes(item, new Uint8Array(0), sha(new Uint8Array(0))));
  });
  await test('publication preserves process pins and only a restarted selection sees the complete new cohort', () => {
    const io = new MemoryIo(), first = initialize(io); install(first, io);
    assert.equal(first.current(), undefined); assert.equal(first.pendingState(), 'remote');
    const reader = initialize(io), pinned = reader.current(); install(reader, io, B, 'two');
    assert.equal(reader.current(), pinned); assert.equal(reader.pendingVersion(), 'two');
    assert.equal(initialize(io).current().manifest.channelVersion, 'two');
  });
  await test('partial staged metadata never replaces a previously verified selection', () => {
    const io = new MemoryIo(), first = initialize(io); const old = install(first, io);
    const reader = initialize(io), staged = stage(reader, io, B, 'two');
    io.files.delete('/data/staging/' + staged.id + '/metadata/weapon_meta.json');
    assert.throws(() => new Store('/data', io).prepare('stage', staged.id)); assert.equal(initialize(io).current().id, old.id);
  });
  await test('all publication write/rename fault positions recover old or complete new without mixed files', () => {
    for (const operation of ['rename:/data/snapshots/' + B + '-1791190000000-00000001', 'write:/data/active.previous.json.next',
      'rename:/data/active.previous.json', 'write:/data/active.json.next', 'rename:/data/active.json']) {
      for (const after of [false, true]) {
        const io = new MemoryIo(), initial = initialize(io), old = install(initial, io), reader = initialize(io), s = stage(reader, io, B, 'two');
        io.fail = operation; io.after = after;
        assert.throws(() => reader.publish(s.id, s.value, s.prepared, () => {})); io.fail = '';
        const selected = initialize(io).current(); assert.ok([old.id, s.id].includes(selected.id));
        assert.equal(selected.metadata.size, 17); assert.ok(io.files.has('/data/snapshots/' + old.id + '/complete.json'));
      }
    }
  });
  await test('bad current bytes or complete receipt fall back to verified previous', () => {
    for (const file of ['metadata/avatar_meta.json', 'complete.json']) {
      const io = new MemoryIo(), first = initialize(io), old = install(first, io), reader = initialize(io), newer = install(reader, io, B, 'two');
      io.files.set('/data/snapshots/' + newer.id + '/' + file, encode('corrupt'));
      assert.equal(initialize(io).current().id, old.id);
    }
  });
  await test('corrupt pointers, orphan directories and unknown legacy files cannot self-activate', () => {
    const io = new MemoryIo(), reader = initialize(io), orphan = stage(reader, io);
    io.rename('/data/staging/' + orphan.id, '/data/snapshots/' + orphan.id);
    io.files.set('/data/legacy.json', encode('legacy')); assert.equal(initialize(io).current(), undefined);
    io.files.set('/data/active.json', encode('{bad')); assert.equal(initialize(io).current(), undefined);
    assert.equal(io.decode(io.files.get('/data/legacy.json')), 'legacy');
  });
  await test('reset tombstone dominates an old backup even when the second reset write fails', () => {
    const io = new MemoryIo(), first = initialize(io), old = install(first, io), reader = initialize(io);
    io.fail = 'write:/data/active.previous.json.next'; assert.throws(() => reader.reset()); io.fail = '';
    assert.equal(initialize(io).current(), undefined); assert.equal(reader.current().id, old.id);
    assert.equal(reader.pendingState(), 'bundled');
    assert.ok(io.files.has('/data/snapshots/' + old.id + '/complete.json'));
  });
  await test('rollback is verified, leaves current readers pinned and reports future bundled resets distinctly', () => {
    const io = new MemoryIo(), first = initialize(io), old = install(first, io), writer = initialize(io); install(writer, io, B, 'two');
    const reader = initialize(io); assert.equal(reader.canRollback(), true);
    const result = new Store('/data', io).prepare('rollback', reader.rollbackId()); assert.equal(reader.rollback(result), true);
    assert.equal(reader.current().manifest.channelVersion, 'two'); assert.equal(initialize(io).current().id, old.id);
    reader.reset(); assert.equal(reader.pendingState(), 'bundled'); assert.equal(reader.pendingVersion(), '');
  });
  await test('stale and malformed worker results are never admitted', () => {
    const io = new MemoryIo(), first = initialize(io); install(first, io); const result = new Store('/data', io).prepare('selection');
    const altered = result.slice(); altered[1] = '/other'; assert.throws(() => new Store('/data', io).adoptSelection(altered, true));
    const writer = initialize(io); writer.reset(); assert.throws(() => new Store('/data', io).adoptSelection(result, true));
    const current = initialize(io), s = stage(current, io, B, 'two'); const bad = s.prepared.slice(); bad.pop();
    assert.throws(() => current.publish(s.id, s.value, bad, () => {})); assert.equal(initialize(io).current(), undefined);
  });
  await test('final publication fence can stop after full validation without replacing live pointer', () => {
    const io = new MemoryIo(), first = initialize(io), old = install(first, io), reader = initialize(io), s = stage(reader, io, B, 'two');
    let checks = 0; assert.throws(() => reader.publish(s.id, s.value, s.prepared, () => { if (++checks === 3) throw new Error('source changed'); }));
    assert.equal(initialize(io).current().id, old.id);
  });
  await test('production updater stages full v1, preserves legacy files and uses native URI conversion after restart', async () => {
    const env = environment(); const legacy = path.join(env.directory, 'gamedata/metadata/metadata/avatar_meta.json');
    fs.mkdirSync(path.dirname(legacy), { recursive: true }); fs.writeFileSync(legacy, 'unverified legacy'); env.prefs.set('gamedata_manifest_version', 'fake-old');
    const U = await env.updater(); assert.equal(U.localVersion(), ''); const progress = [];
    const result = await U.update(p => progress.push(p.done)); assert.equal(result.items.length, 18); assert.equal(progress.at(-1), 18);
    assert.equal(U.localVersion(), ''); assert.equal(U.pendingVersion(), 'one'); assert.equal(fs.readFileSync(legacy, 'utf8'), 'unverified legacy');
    const next = await env.updater(); assert.equal(next.localVersion(), 'one');
    assert.equal(next.readMetadata('avatar_meta.json'), next.readMetadata('metadata/avatar_meta.json'));
    assert.ok(next.readImage('icons/Test/sample.png').startsWith('file://bundle/')); assert.equal(env.uriCalls.length, 1);
    assert.equal(next.readImage('icons/Test/missing.png'), ''); assert.equal(next.isItemLocal({ type: 'icon', path: 'icons/Test/missing.png' }), false);
    await assert.rejects(next.ensureItem({ type: 'icon', path: 'icons/Test/missing.png' }), /完整/);
  });
  await test('default branch resolves again on each operation and never fetches moving-branch payloads', async () => {
    const env = environment(), U = await env.updater(); await U.update(); env.revision = B; env.version = 'two';
    await U.update(); assert.equal(U.pendingVersion(), 'two'); assert.equal((await env.updater()).localVersion(), 'two');
    assert.equal(env.requests.filter(url => url.startsWith('https://api.github.com/')).length, 2);
    assert.equal(env.requests.filter(url => url.startsWith(P.RAW_ROOT + 'main/')).length, 0);
  });
  await test('explicit trusted commit source needs no branch lookup and still accepts v1 main URL hints', async () => {
    const env = environment(), U = await env.updater(); U.setManifestUrl(P.RAW_ROOT + A + '/manifest-hutao.json'); await U.update();
    assert.equal(env.requests.some(url => url.startsWith('https://api.github.com/')), false);
    assert.equal((await env.updater()).localVersion(), 'one');
  });
  await test('partial HTTP failure preserves disk/current version and whole cached metadata', async () => {
    const env = environment(), U = await env.updater(); await U.update(); const reader = await env.updater(), before = reader.readMetadata('avatar_meta.json');
    env.revision = B; env.version = 'two'; env.files.set('metadata/avatar_meta.json', Buffer.concat([raw.get('metadata/avatar_meta.json'), Buffer.from('\n')]));
    env.failUrl = 'metadata/weapon_meta.json'; await assert.rejects(reader.update(), /HTTP 500/);
    assert.equal(reader.readMetadata('avatar_meta.json'), before); assert.equal(reader.localVersion(), 'one');
    assert.equal((await env.updater()).localVersion(), 'one');
  });
  await test('malformed JSON and producer HTML masquerading as PNG fail before publication', async () => {
    for (const file of ['metadata/avatar_meta.json', 'icons/Test/sample.png']) {
      const env = environment(), U = await env.updater(); env.files.set(file, Buffer.from('<html>404</html>'));
      await assert.rejects(U.update()); assert.equal((await env.updater()).localVersion(), '');
    }
  });
  await test('short writes and fsync failures preserve the old cohort and never publish the failed one', async () => {
    for (const failure of ['short', 'fsync']) {
      const env = environment(), U = await env.updater(); await U.update(); env.revision = B; env.version = 'two';
      env.ioHook = (operation, file) => { if (file.includes('/staging/') && file.endsWith('/metadata/avatar_meta.json')) {
        if (failure === 'short' && operation === 'write') return 1;
        if (failure === 'fsync' && operation === 'fsync') throw new Error('sync failed');
      } };
      await assert.rejects(U.update()); env.ioHook = null; assert.equal((await env.updater()).localVersion(), 'one');
    }
  });
  await test('low free space and retained abandoned staging count against admission without deletion', async () => {
    const env = environment(), U = await env.updater(); env.free = 1; await assert.rejects(U.update(), /空间不足/);
    assert.equal(env.requests.filter(url => url.includes('/metadata/')).length, 0);
    env.free = 10 * 1024 ** 3;
    const large = path.join(env.directory, 'gamedata/cohort-v1/staging/retained.bin'); fs.mkdirSync(path.dirname(large), { recursive: true });
    const fd = fs.openSync(large, 'w'); fs.ftruncateSync(fd, 3 * P.MAX_SNAPSHOT_BYTES); fs.closeSync(fd);
    await assert.rejects(U.update(), /空间不足/); assert.equal(fs.statSync(large).size, 3 * P.MAX_SNAPSHOT_BYTES);
  });
  await test('duplicate update, source/reset reentrancy and another runtime writer are fenced', async () => {
    const env = environment(), U = await env.updater(), other = await env.updater();
    let release; env.requestGate = new Promise(resolve => { release = resolve; }); const running = U.update();
    while (env.requests.length === 0) await new Promise(resolve => setTimeout(resolve, 1));
    await assert.rejects(U.update(), /重复/); assert.throws(() => U.clearAll(), /正在更新/); assert.throws(() => U.setManifestUrl(P.RAW_ROOT + B + '/manifest-hutao.json'), /正在更新/);
    await assert.rejects(other.update(), /另一任务/); env.requestGate = null; release(); await running;
    env.revision = B; env.version = 'two'; let checked = false;
    await U.update(() => { if (!checked) { checked = true; assert.throws(() => U.clearAll(), /正在更新/); assert.throws(() => U.setManifestUrl(P.RAW_ROOT + 'main/manifest-hutao.json'), /正在更新/); } });
    assert.equal(checked, true);
  });
  await test('startup worker failure pins bundled data and disallows mutation rather than adopting late results', async () => {
    const env = environment(); env.workerFailure = 'selection'; const U = await env.updater(), late = env.late;
    assert.equal(U.localVersion(), ''); assert.equal(U.snapshotState(), 'unavailable');
    await assert.rejects(U.update(), /重启/); assert.throws(() => U.clearAll(), /重启/);
    env.workerFailure = ''; late.fn(...late.args); assert.equal(U.localVersion(), '');
    assert.equal((await env.updater()).snapshotState(), 'bundled');
  });
  await test('final-worker timeout leaves inert staging; a later read-only worker cannot publish over a new update', async () => {
    const env = environment(), U = await env.updater(); env.workerFailure = 'stage'; await assert.rejects(U.update(), /timed out/);
    const late = env.late; assert.equal(U.localVersion(), ''); env.workerFailure = ''; env.revision = B; env.version = 'two';
    await U.update(); const active = fs.readFileSync(path.join(env.directory, 'gamedata/cohort-v1/active.json'));
    late.fn(...late.args); assert.deepEqual(fs.readFileSync(path.join(env.directory, 'gamedata/cohort-v1/active.json')), active);
    assert.equal((await env.updater()).localVersion(), 'two');
  });
  await test('a source change through restored preferences or before final commit fences publication', async () => {
    for (const when of ['download', 'validated']) {
      const env = environment(), U = await env.updater();
      const change = () => env.prefs.set('gamedata_manifest_url', P.RAW_ROOT + B + '/manifest-hutao.json');
      if (when === 'download') env.requestHook = url => { if (url.endsWith('/metadata/avatar_meta.json')) change(); };
      else env.workerResultHook = (result, task) => { if (task.args[1] === 'stage') change(); return result; };
      await assert.rejects(U.update(), /数据源/); assert.equal((await env.updater()).localVersion(), '');
    }
  });
  await test('symlink pointer temporary files and staging ancestors never clobber unrelated sandbox bytes', async () => {
    const env = environment(), U = await env.updater(); const outside = path.join(env.directory, 'keep.txt'); fs.writeFileSync(outside, 'keep');
    const next = path.join(env.directory, 'gamedata/cohort-v1/active.json.next');
    env.workerResultHook = (result, task) => { if (task.args[1] === 'stage') fs.symlinkSync(outside, next); return result; };
    await assert.rejects(U.update()); assert.equal(fs.readFileSync(outside, 'utf8'), 'keep'); assert.equal(U.localVersion(), '');
    fs.unlinkSync(next); env.workerResultHook = null; const staging = path.join(env.directory, 'gamedata/cohort-v1/staging');
    fs.renameSync(staging, staging + '-retained'); fs.symlinkSync(env.directory, staging);
    await assert.rejects(U.update(), /不安全/); assert.equal(fs.readFileSync(outside, 'utf8'), 'keep');
  });
  await test('reset and rollback are next-launch choices and all existing files remain present', async () => {
    const env = environment(), U = await env.updater(); await U.update(); env.revision = B; env.version = 'two'; await U.update();
    const reader = await env.updater(); assert.equal(reader.canRollback(), true); assert.equal(await reader.rollback(), true);
    assert.equal(reader.localVersion(), 'two'); assert.equal((await env.updater()).localVersion(), 'one');
    reader.clearAll(); assert.equal(reader.pendingState(), 'bundled'); assert.equal(reader.localVersion(), 'two');
    assert.equal((await env.updater()).localVersion(), '');
    assert.equal(fs.readdirSync(path.join(env.directory, 'gamedata/cohort-v1/snapshots')).length, 2);
  });
  await test('GameDataService coalesces startup, preserves raw fallback and rejects unsafe metadata names', async () => {
    const env = environment(), load = env.runtime();
    const service = load('../../service/GameDataService').GameDataService;
    const a = service.initializeSnapshot(), b = service.initializeSnapshot(); assert.equal(a, b); await a;
    assert.equal(await service.readMetadataFile('avatar_meta.json'), raw.get('metadata/avatar_meta.json').toString());
    await assert.rejects(service.readMetadataFile('../other.json'), /未知|不安全/);
    assert.equal(service.getInstance().remoteVersion(), '');
  });
  await test('whole-cohort graph failure after all downloads leaves previous snapshot and version intact', async () => {
    const env = environment(), U = await env.updater(); await U.update(); env.revision = B; env.version = 'two';
    const achievements = JSON.parse(raw.get('metadata/Achievement.json')); achievements[0].Goal = 999999;
    env.files.set('metadata/Achievement.json', Buffer.from(JSON.stringify(achievements)));
    await assert.rejects(U.update(), /目标/); assert.equal((await env.updater()).localVersion(), 'one');
    assert.equal(U.pendingVersion(), 'one');
  });
  await test('prepared output identity corruption and UTF-8 corruption fail closed', async () => {
    const env = environment(), U = await env.updater();
    env.workerResultHook = (result, task) => { if (task.args[1] === 'stage') result[4] = B + '-1-00000001'; return result; };
    await assert.rejects(U.update(), /失效/); assert.equal(U.localVersion(), '');
    env.workerResultHook = null; env.files.set('metadata/avatar_meta.json', Buffer.from([0xFF, 0xFE, 0xFF]));
    await assert.rejects(U.update()); assert.equal((await env.updater()).localVersion(), '');
  });
  await test('per-file worker receipts are invocation-bound and late timed-out file workers cannot publish', async () => {
    const env = environment(), U = await env.updater(); env.workerFailure = 'file';
    await assert.rejects(U.update(), /timed out/); const late = env.late; env.workerFailure = '';
    env.revision = B; env.version = 'two'; await U.update();
    const active = fs.readFileSync(path.join(env.directory, 'gamedata/cohort-v1/active.json'));
    late.fn(...late.args); assert.deepEqual(fs.readFileSync(path.join(env.directory, 'gamedata/cohort-v1/active.json')), active);
    env.revision = C; env.version = 'three';
    env.workerResultHook = (result, task) => { if (task.args[1] === 'file') result[2] = A + '-1-00000001'; return result; };
    await assert.rejects(U.update(), /收据/); env.workerResultHook = null;
    assert.equal((await env.updater()).localVersion(), 'two');
  });
  console.log(`game-data-cohort: PASS ${count} production policy/store/updater tests (host boundaries only)`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  for (const directory of sandboxes) fs.rmSync(directory, { recursive: true, force: true }); // exclusively this test's mkdtemp roots
});
