// Executes the production cache service against asynchronous file-I/O boundaries.
// No files are deleted on the host. Native signatures: API 26 file.fs.d.ts.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/service/MediaCacheService.ets'), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  reportDiagnostics: true,
});
assert.equal(compiled.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);

function harness() {
  const entries = new Map();
  const removed = [];
  const errors = new Map();
  const logs = [];
  const versions = [];
  const missing = () => Object.assign(new Error('Missing'), { code: 13900002 });
  function entry(at) { if (errors.has(at)) throw errors.get(at); if (!entries.has(at)) throw missing(); return entries.get(at); }
  const fileIo = {
    async lstat(at) {
      const item = entry(at);
      return { size: item.bytes, isFile: () => item.type === 'file',
        isDirectory: () => item.type === 'dir', isSymbolicLink: () => item.type === 'link' };
    },
    async listFile(at, options) {
      assert.equal(options.recursion, false);
      assert.equal(entry(at).type, 'dir');
      return [...entries.keys()].filter(k => k.startsWith(at + '/') && !k.slice(at.length + 1).includes('/'))
        .map(k => k.slice(at.length + 1));
    },
    async unlink(at) { assert.equal(entry(at).type, 'file'); entries.delete(at); removed.push(at); },
  };
  const module = { exports: {} };
  const mocks = {
    '@kit.CoreFileKit': { fileIo },
    '@kit.BasicServicesKit': {},
    '@kit.ArkTS': {},
    '@kit.CryptoArchitectureKit': {},
    '@kit.RemoteCommunicationKit': {},
    '../common/AppContext': { AppContextProvider: { getCacheDir: () => '/sandbox/cache' } },
    '../common/Logger': { Logger: { warn: (...args) => logs.push(args) } },
  };
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports,
    AppStorage: { setOrCreate: (key, value) => { assert.equal(key, 'mediaCacheVersion'); versions.push(value); } },
    require: id => { assert.ok(id in mocks, id); return mocks[id]; } });
  function add(at, type = 'file', bytes = 10) { entries.set(at, { type, bytes }); }
  return { service: module.exports.MediaCacheService, entries, errors, removed, logs, versions, add };
}

test('clears ordinary files and nested icon files, preserving directories and non-cache user data', async () => {
  const h = harness();
  for (const root of ['wallpaper', 'remoteimg', 'remote', 'rawicons']) {
    h.add('/sandbox/cache/' + root, 'dir');
    h.add('/sandbox/cache/' + root + '/image.png');
  }
  h.add('/sandbox/cache/remote/AvatarIcon', 'dir');
  h.add('/sandbox/cache/remote/AvatarIcon/portrait.png', 'file', 25);
  h.add('/sandbox/cache/not-allowlisted', 'dir');
  h.add('/sandbox/cache/not-allowlisted/keep.png', 'file', 1000);
  h.add('/sandbox/files/background-video/movie.mp4', 'file', 9000);
  h.add('/sandbox/files/Userdata.db', 'file', 9000);
  assert.equal(await h.service.size(), 65);
  assert.equal(await h.service.clear(), true);
  assert.equal(h.removed.length, 5);
  assert.equal(await h.service.size(), 0);
  assert.ok(h.entries.has('/sandbox/cache/remote/AvatarIcon'));
  assert.ok(h.entries.has('/sandbox/cache/not-allowlisted/keep.png'));
  assert.ok(h.entries.has('/sandbox/files/background-video/movie.mp4'));
  assert.ok(h.entries.has('/sandbox/files/Userdata.db'));
});

test('does not follow linked roots or linked children', async () => {
  const h = harness();
  h.add('/sandbox/cache/wallpaper', 'link');
  h.add('/sandbox/cache/wallpaper/other-user.png', 'file', 500);
  h.add('/sandbox/cache/remote', 'dir');
  h.add('/sandbox/cache/remote/linked', 'link');
  h.add('/sandbox/cache/remote/linked/other-user.png', 'file', 500);
  h.add('/sandbox/cache/remote/cache.png', 'file', 12);
  assert.equal(await h.service.size(), 12);
  assert.equal(await h.service.clear(), true);
  assert.deepEqual(h.removed, ['/sandbox/cache/remote/cache.png']);
  assert.ok(h.entries.has('/sandbox/cache/wallpaper/other-user.png'));
  assert.ok(h.entries.has('/sandbox/cache/remote/linked/other-user.png'));
});

test('missing caches succeed, but unreadable roots and files report partial failure and allow retry', async () => {
  const h = harness();
  assert.equal(await h.service.clear(), true);
  h.errors.set('/sandbox/cache/wallpaper', Object.assign(new Error('Denied'), { code: 13900012 }));
  h.add('/sandbox/cache/remoteimg', 'dir');
  h.add('/sandbox/cache/remoteimg/busy.png');
  h.add('/sandbox/cache/remoteimg/ready.png');
  h.errors.set('/sandbox/cache/remoteimg/busy.png', Object.assign(new Error('Busy'), { code: 13900014 }));
  assert.equal(await h.service.clear(), false);
  assert.deepEqual(h.versions, [1, 2]);
  assert.deepEqual(h.removed, ['/sandbox/cache/remoteimg/ready.png']);
  assert.equal(h.logs.length, 2);
  h.errors.clear();
  assert.equal(await h.service.clear(), true);
  assert.equal(await h.service.size(), 0);
});
