// Canonical recovery test name retained. This older baseline has SplashArtView only;
// CostumeArtView/Service and their model are absent. Host handlers are not device rendering evidence.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const filename = path.resolve(__dirname, '../entry/src/main/ets/pages/WikiAvatarPage.ets');
const original = fs.readFileSync(filename, 'utf8');
const splash = original.slice(0, original.indexOf('\n@Entry'));
const methods = (splash.slice(0, splash.indexOf('  build() {')) + '}')
  .replace('@Component\n', '').replace('export struct SplashArtView', 'export class SplashArtView');
const compiled = ts.transpileModule(methods, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true },
  reportDiagnostics: true,
});
assert.equal(compiled.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
const deferred = () => { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; }); return { promise, resolve, reject }; };
const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve(); };
const raw = () => new Uint8Array([137, 80, 78, 71]);
const uri = value => `native-file-uri:${encodeURIComponent(value)}`;
const fullPath = name => `/sandbox/cache/rawicons/GachaAvatarImg/UI_Gacha_AvatarImg_${name}.png`;
function harness() {
  const local = [], remote = [], writes = [], mkdirs = [], uriCalls = [];
  const state = { cacheDir: '/sandbox/cache' };
  const files = new Map(), handles = new Map(), dirs = new Set(['/', '/sandbox', '/sandbox/cache']);
  let nextFd = 1;
  const fileIo = {
    OpenMode: { READ_WRITE: 1, CREATE: 2, TRUNC: 4 },
    accessSync: file => files.has(file) || dirs.has(file),
    mkdirSync: dir => {
      mkdirs.push(dir);
      if (dirs.has(dir)) throw Error('already exists');
      if (!dirs.has(path.posix.dirname(dir))) throw Error('missing parent');
      dirs.add(dir);
    },
    openSync: file => {
      assert.ok(dirs.has(path.posix.dirname(file)), `missing cache directory: ${file}`);
      const fd = nextFd++; handles.set(fd, file); return { fd };
    },
    writeSync: (fd, bytes) => { const file = handles.get(fd); assert.ok(file); files.set(file, new Uint8Array(bytes)); writes.push(file); return bytes.byteLength; },
    closeSync: file => handles.delete(file.fd),
  };
  const mocks = {
    '@kit.CoreFileKit': { fileIo, fileUri: { getUriFromPath: value => { uriCalls.push(value); return uri(value); } } },
    '../common/AppContext': { AppContextProvider: {
      getCacheDir: () => state.cacheDir,
      getResourceManager: () => ({ getRawFileContent: name => { const d = deferred(); local.push({ name, ...d }); return d.promise; } }),
    } },
    '../data/remote/StandardIconService': { StandardIconService: {
      ensure: (category, name) => { const d = deferred(); remote.push({ category, name, ...d }); return d.promise; },
    } },
  };
  const module = { exports: {} };
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`, {
    Prop: () => {}, Watch: () => () => {}, State: () => {},
  })(id => { assert.ok(Object.hasOwn(mocks, id), `Unexpected production dependency: ${id}`); return mocks[id]; }, module, module.exports);
  const art = new module.exports.SplashArtView();
  return { art, local, remote, files, writes, mkdirs, handles, state, uriCalls };
}
(async () => {
  assert.match(splash, /@Prop @Watch\('onIconChanged'\) icon/);
  assert.doesNotMatch(splash, /Logger\.info/, 'do not log individual image names for every recycled component');
  // Cached content needs no raw resource read or network request.
  {
    const h = harness(); h.art.icon = 'UI_AvatarIcon_Cached'; h.files.set(fullPath('Cached'), raw());
    h.art.onIconChanged(); assert.equal(h.local.length, 0); assert.equal(h.art.src, '');
    h.art.aboutToAppear(); await flush(); assert.equal(h.art.src, uri(fullPath('Cached')));
    assert.equal(h.local.length, 0); assert.equal(h.remote.length, 0);
  }
  // First offline read creates absolute parent directories and publishes only after writing.
  {
    const h = harness(); h.art.icon = 'UI_AvatarIcon_Offline'; h.art.aboutToAppear();
    assert.equal(h.local[0].name, 'icons/GachaAvatarImg/UI_Gacha_AvatarImg_Offline.png');
    h.local[0].resolve(raw()); await flush();
    assert.equal(h.art.src, uri(fullPath('Offline'))); assert.deepEqual(h.writes, [fullPath('Offline')]);
    assert.ok(h.mkdirs.length > 1); assert.ok(h.mkdirs.every(dir => dir.startsWith('/')), 'directory fallback preserves leading slash');
    assert.equal(h.handles.size, 0); assert.equal(h.remote.length, 0);
  }
  // Replacement clears immediately; superseded local success/failure cannot write or start CDN work.
  for (const oldFails of [false, true]) {
    const h = harness(); h.art.icon = 'UI_AvatarIcon_Old'; h.art.aboutToAppear(); h.art.src = 'file:///previous';
    h.art.icon = 'UI_AvatarIcon_New'; h.art.onIconChanged(); assert.equal(h.art.src, '');
    if (oldFails) h.local[0].reject(Error('old missing')); else h.local[0].resolve(raw());
    await flush(); assert.equal(h.writes.length, 0); assert.equal(h.remote.length, 0); assert.equal(h.art.src, '');
    h.local[1].resolve(raw()); await flush(); assert.equal(h.art.src, uri(fullPath('New')));
  }
  // A superseded primary CDN miss cannot enqueue the old portrait fallback.
  for (const oldPath of ['', '/downloaded/old.png']) {
    const h = harness(); h.art.icon = 'UI_AvatarIcon_Old'; h.art.aboutToAppear();
    h.local[0].reject(Error('missing')); await flush(); assert.equal(h.remote.length, 1);
    h.art.icon = 'UI_AvatarIcon_New'; h.art.onIconChanged();
    h.remote[0].resolve(oldPath); await flush(); assert.equal(h.local.length, 2); assert.equal(h.art.src, '');
    h.local[1].resolve(raw()); await flush(); assert.equal(h.art.src, uri(fullPath('New')));
  }
  // Detached local completions do no cache work; detached prop notifications do no I/O; remount retries.
  for (const lateFails of [false, true]) {
    const h = harness(); h.art.icon = 'UI_AvatarIcon_Remount'; h.art.aboutToAppear(); h.art.aboutToDisappear();
    h.art.onIconChanged(); assert.equal(h.local.length, 1);
    if (lateFails) h.local[0].reject(Error('late missing')); else h.local[0].resolve(raw());
    await flush(); assert.equal(h.remote.length, 0); assert.equal(h.writes.length, 0); assert.equal(h.art.src, '');
    h.art.aboutToAppear(); assert.equal(h.local.length, 2); h.local[1].resolve(raw()); await flush();
    assert.equal(h.art.src, uri(fullPath('Remount')));
  }
  // Closing during network work cannot publish or enqueue a later local fallback.
  {
    const h = harness(); h.art.icon = 'UI_AvatarIcon_Close'; h.art.aboutToAppear(); h.local[0].reject(Error('missing')); await flush();
    h.art.aboutToDisappear(); h.remote[0].resolve(''); await flush();
    assert.equal(h.local.length, 1); assert.equal(h.art.src, '');
  }
  // Primary miss falls back to the packaged portrait, then to portrait CDN when needed.
  for (const portraitLocal of [false, true]) {
    const h = harness(); h.art.icon = 'UI_AvatarIcon_Fallback'; h.art.aboutToAppear();
    h.local[0].reject(Error('no full art')); await flush(); h.remote[0].resolve(''); await flush();
    assert.equal(h.local[1].name, 'icons/GachaAvatarIcon/UI_Gacha_AvatarIcon_Fallback.png');
    if (portraitLocal) {
      h.local[1].resolve(raw()); await flush(); assert.equal(h.art.src, uri('/sandbox/cache/rawicons/GachaAvatarIcon/UI_Gacha_AvatarIcon_Fallback.png'));
      assert.equal(h.remote.length, 1);
    } else {
      h.local[1].reject(Error('no portrait')); await flush(); assert.equal(h.remote[1].category, 'GachaAvatarIcon');
      h.remote[1].resolve('/downloaded/portrait.png'); await flush(); assert.equal(h.art.src, uri('/downloaded/portrait.png'));
    }
  }
  // Unexpected adapter errors settle at a placeholder and the next mount remains retryable.
  {
    const h = harness(); h.art.icon = 'UI_AvatarIcon_Retry'; h.art.aboutToAppear();
    h.local[0].reject(Error('cache')); await flush(); h.remote[0].reject(Error('network')); await flush();
    h.local[1].reject(Error('fallback cache')); await flush(); h.remote[1].reject(Error('fallback network')); await flush();
    assert.equal(h.art.src, ''); h.art.aboutToDisappear(); h.art.aboutToAppear(); h.local[2].resolve(raw()); await flush();
    assert.equal(h.art.src, uri(fullPath('Retry')));
  }
  // Typed-array views must write only their own range, independent of backing-buffer layout.
  {
    const h = harness(); h.art.icon = 'UI_AvatarIcon_Subview'; h.art.aboutToAppear();
    const backing = new Uint8Array([99, 98, 137, 80, 78, 71, 97]);
    h.local[0].resolve(backing.subarray(2, 6)); await flush();
    assert.deepEqual(Array.from(h.files.get(fullPath('Subview'))), [137, 80, 78, 71]);
    assert.equal(h.art.src, uri(fullPath('Subview')));
  }
  // Cache, newly written rawfile and CDN sources all use the native URI converter.
  {
    const h = harness(); h.state.cacheDir = '/sandbox/cache #example'; h.art.icon = 'UI_AvatarIcon_Uri';
    const destination = `${h.state.cacheDir}/rawicons/GachaAvatarImg/UI_Gacha_AvatarImg_Uri.png`;
    h.art.aboutToAppear(); h.local[0].resolve(raw()); await flush();
    assert.equal(h.art.src, uri(destination)); assert.deepEqual(h.uriCalls, [destination]);
    h.art.aboutToDisappear(); h.art.aboutToAppear(); await flush();
    assert.equal(h.local.length, 1); assert.deepEqual(h.uriCalls, [destination, destination]);
    h.art.icon = 'UI_AvatarIcon_UriRemote'; h.art.onIconChanged();
    h.local[1].reject(Error('not bundled')); await flush(); h.remote[0].resolve('/downloaded/icon #2.png'); await flush();
    assert.equal(h.art.src, uri('/downloaded/icon #2.png')); assert.equal(h.uriCalls.at(-1), '/downloaded/icon #2.png');
  }
  // Untrusted icon metadata cannot become a rawfile/cache traversal or CDN request.
  for (const icon of ['', 'UI_AvatarIcon_', '../UI_AvatarIcon_A', 'UI_AvatarIcon_../../other', 'UI_AvatarIcon_A/B']) {
    const h = harness(); h.art.icon = icon; h.art.aboutToAppear(); await flush();
    assert.equal(h.local.length, 0, icon); assert.equal(h.remote.length, 0, icon); assert.equal(h.art.src, '');
  }
  console.log('costume-art-lifecycle: PASS (existing SplashArtView only: watched replacement, cached/offline/CDN fallback, detach/remount/stale-stage guards, absolute mkdir, exact typed-array range, native file URIs, invalid icon rejection; costume feature absent in this baseline; host-only)');
})().catch(error => { console.error(error); process.exitCode = 1; });
