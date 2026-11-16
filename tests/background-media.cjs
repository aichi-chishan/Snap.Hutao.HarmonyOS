const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const webm = 'https://launcher-webstatic.mihoyo.com/launcher-public/2026/08/05/8e1c78aaa6e33ed60b88e12a461f8ee5_6759941859929004894.webm';
const mapped = 'https://static.snaphutaorp.org/static/launcher/20260812.mp4';
const official = 'https://launcher-webstatic.mihoyo.com/launcher-public/video.mp4?x=1';
const wallpaper = 'https://static.snaphutaorp.org/example/wallpaper.jpg';
const video = url => ({ type: 'BACKGROUND_TYPE_VIDEO', video: { url } });
const backgrounds = (...items) => ({ game: { biz: 'hk4e_cn' }, backgrounds: items });
const success = data => ({ success: true, data });

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function harness() {
  const files = new Map();
  const directories = new Set(['/cache', '/files']);
  const selected = new Map();
  const open = new Map();
  const prefs = new Map();
  const changed = [];
  const requests = [];
  const downloads = [];
  const closed = [];
  let serial = 0;
  const nativeError = code => Object.assign(new Error(String(code)), { code });
  const fileStat = name => {
    const isDirectory = directories.has(name);
    if (!isDirectory && !files.has(name) && !selected.has(name)) { throw nativeError(13900002); }
    return { isDirectory: () => isDirectory, isFile: () => !isDirectory, isSymbolicLink: () => false,
      size: files.get(name)?.length ?? selected.get(name)?.size ?? 0 };
  };
  const io = {
    OpenMode: { READ_ONLY: 0, WRITE_ONLY: 1, CREATE: 64, NOFOLLOW: 131072 },
    async mkdir(name) {
      if (directories.has(name)) { throw nativeError(13900015); }
      directories.add(name);
    },
    async lstat(name) { return fileStat(name); },
    async stat(fd) { return fileStat(open.get(fd)); },
    async listFile(root) {
      return [...files.keys()].filter(name => path.posix.dirname(name) === root).map(name => path.posix.basename(name));
    },
    async open(name, flags) {
      if ((flags & io.OpenMode.CREATE) !== 0) { files.set(name, Buffer.alloc(0)); }
      fileStat(name);
      const fd = ++serial;
      open.set(fd, name);
      return { fd, name: selected.get(name)?.name ?? path.posix.basename(name) };
    },
    async write(fd, bytes) {
      const data = Buffer.from(new Uint8Array(bytes));
      files.set(open.get(fd), data);
      return data.length;
    },
    async close(file) { assert.ok(open.delete(file.fd)); },
    async readText(name) { return files.get(name).toString(); },
    async copyFile(fd, dest) {
      const source = selected.get(open.get(fd));
      files.set(dest, Buffer.alloc(source.size));
      if (source.failed) { throw nativeError(13900025); }
    },
    async unlink(name) { if (!files.delete(name)) { throw nativeError(13900002); } },
    renameSync(from, to) {
      const bytes = files.get(from);
      assert.ok(bytes, from);
      files.delete(from);
      files.set(to, bytes);
    },
  };
  const network = {
    async metadata(url) {
      if (url.includes('getAllGameBasicInfo')) { return success({ game_info_list: [backgrounds(video(official))] }); }
      return success({ url: wallpaper, author: '画师', source_url: 'https://example.test/artwork' });
    },
    async download(_url, destination) {
      files.set(destination, Buffer.from('complete payload'));
      return { statusCode: 200 };
    },
  };
  const mocks = {
    '@kit.ArkTS': { util: { generateRandomUUID: () => `unique-${++serial}`,
      TextEncoder: { create: () => ({ encodeInto: value => new TextEncoder().encode(value) }) } } },
    '@kit.BasicServicesKit': {},
    '@kit.CoreFileKit': { fileIo: io, fileUri: { getUriFromPath: name => `file://app${name}` } },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: algorithm => {
      const hash = createHash(algorithm);
      return { updateSync: ({ data }) => hash.update(data), digestSync: () => ({ data: hash.digest() }) };
    } } },
    '@kit.RemoteCommunicationKit': { rcp: { createSession: () => {
      const id = ++serial;
      return {
        async downloadToFile(url, target) {
          assert.equal(target.kind, 'file');
          assert.ok(target.file.endsWith('.part'));
          downloads.push({ url, id, target: target.file });
          return network.download(url, target.file);
        },
        close() { assert.ok(!closed.includes(id)); closed.push(id); },
      };
    } } },
    '../common/AppContext': { AppContextProvider: { getCacheDir: () => '/cache', getFilesDir: () => '/files' } },
    '../common/Logger': { Logger: { warn() {} } },
    '../data/network/ApiClient': { ApiClient: { getInstance: () => ({ async get(url, headers) {
      requests.push({ url, headers });
      return network.metadata(url);
    } }) } },
    '../data/prefs/PreferencesStore': { PreferencesStore: { getString: (key, fallback) => prefs.get(key) ?? fallback,
      setString: (key, value) => prefs.set(key, value) } },
  };
  const modules = new Map();
  function load(name) {
    if (modules.has(name)) { return modules.get(name); }
    const source = fs.readFileSync(path.join(__dirname, `../entry/src/main/ets/service/${name}.ets`), 'utf8');
    const compilerOptions = { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 };
    const compiled = ts.transpileModule(source, { compilerOptions, reportDiagnostics: true });
    assert.equal(compiled.diagnostics.filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
    const module = { exports: {} };
    vm.runInNewContext(compiled.outputText, { module, exports: module.exports,
      AppStorage: { setOrCreate: (key, value) => changed.push({ key, value }) },
      require: id => id.startsWith('./') ? load(id.slice(2)) : (assert.ok(id in mocks, id), mocks[id]) });
    modules.set(name, module.exports);
    return module.exports;
  }
  return { files, directories, selected, open, prefs, changed, requests, downloads, closed, network,
    media: load('BackgroundMediaService').BackgroundMediaService,
    daily: load('HutaoDailyImageService').HutaoDailyImageService,
    images: load('CachedImageService').CachedImageService,
    cache: load('MediaCacheService').MediaCacheService };
}

test('launcher chooses the first playable Chinese Genshin video and applies the upstream exact mapping', () => {
  const { media } = harness();
  assert.deepEqual(Array.from(media.VIDEO_EXTENSIONS), ['.mp4', '.mkv', '.ts']);
  assert.equal(media.officialVideo({ game_info_list: [null, { game: { biz: 'hkrpg_cn' }, backgrounds: [video(official)] },
    backgrounds(null, video('http://example.test/insecure.mp4'), video('https://example.test/unsupported.webm'),
      video(webm), video(official))] }), mapped);
  assert.equal(media.officialVideo({ game_info_list: [backgrounds(video('https://example.test/current.MKV?a=1#t=0'))] }),
    'https://example.test/current.MKV?a=1#t=0');
  assert.equal(media.officialVideo({ game_info_list: [backgrounds(video(`${webm}?different=1`))] }), '');
  assert.equal(media.officialVideo({ game_info_list: {} }), '');
});

test('official resolution shares work, returns a sandbox URI and revalidates the cache file', async () => {
  const h = harness();
  h.prefs.set(h.media.TYPE_KEY, 'official');
  h.network.metadata = async () => success({ game_info_list: [backgrounds(video(webm))] });
  const arrived = deferred();
  const finish = deferred();
  const download = h.network.download;
  h.network.download = async (url, destination) => {
    arrived.resolve();
    await finish.promise;
    return download(url, destination);
  };
  const first = h.media.source();
  const other = h.media.source();
  await Promise.race([arrived.promise, first.then(() => assert.fail('expected a video download'))]);
  assert.equal(h.requests.length, 1);
  assert.equal(h.downloads.length, 1);
  assert.equal(h.downloads[0].url, mapped);
  assert.match(h.requests[0].url, /hyp-api\.mihoyo\.com\/.+game_id=1Z8W5NHUQb$/);
  assert.equal(Object.keys(h.requests[0].headers).length, 0);
  finish.resolve();
  const uri = await first;
  assert.match(uri, /^file:\/\/app\/cache\/wallpaper\/official_[a-f0-9]{64}\.mp4$/);
  assert.equal(await other, uri);
  assert.equal(await h.media.source(), uri);
  assert.equal(h.downloads.length, 1);
  h.files.delete(uri.replace('file://app', ''));
  assert.equal(await h.media.source(), uri);
  assert.equal(h.downloads.length, 2);
  assert.equal(h.closed.length, h.downloads.length);
});

test('a failed official download closes the request, cleans staging and streams the selected URL', async () => {
  const h = harness();
  h.prefs.set(h.media.TYPE_KEY, 'official');
  h.network.download = async (_url, destination) => {
    h.files.set(destination, Buffer.from('error body'));
    return { statusCode: 503 };
  };
  assert.equal(await h.media.source(), official);
  assert.equal(h.closed.length, 1);
  assert.equal(h.files.size, 0);
});

test('local imports preserve the video format, validate sandbox paths and roll back a failed batch', async () => {
  const h = harness();
  const one = 'file://docs/user/movie.MKV';
  const two = 'file://docs/user/movie.ts';
  const failed = 'file://docs/user/copy-error.mp4';
  h.selected.set(one, { name: 'movie.MKV', size: 11 });
  h.selected.set(two, { name: 'movie.ts', size: 22 });
  h.selected.set(failed, { name: 'copy-error.mp4', size: 33, failed: true });
  assert.equal(await h.media.importVideos([one, two, one]), 2);
  const saved = h.prefs.get(h.media.FILES_KEY);
  const [mkv, tsVideo] = saved.split('\n');
  assert.match(mkv, /^\/files\/background-video\/.+\.mkv$/);
  assert.match(tsVideo, /\.ts$/);
  assert.equal(h.open.size, 0);
  assert.equal(h.changed.length, 1);
  await assert.rejects(h.media.importVideos([one, failed]), /13900025/);
  assert.deepEqual([...h.files.keys()], [mkv, tsVideo]);
  assert.equal(h.prefs.get(h.media.FILES_KEY), saved);
  assert.equal(h.open.size, 0);
  assert.equal(h.changed.length, 1);
  assert.equal(h.selected.size, 3);
  h.files.delete(mkv);
  h.prefs.set(h.media.FILES_KEY, `${saved}\n/files/background-video/../other.mp4`);
  assert.equal(await h.media.source(), `file://app${tsVideo}`);
  assert.equal(await h.cache.clear(), true);
  assert.ok(h.files.has(tsVideo), 'cache clear preserves copies of imported user files');
});

test('daily image deduplicates settings and backdrop callers and retains attribution across instances', async () => {
  const h = harness();
  const sourceUrl = 'https://example.test/作品/%E8%83%A1%E6%A1%83?lang=zh-CN&from=wallpaper%20daily#作者';
  h.network.metadata = async () => success({ url: wallpaper, author: '画师', source_url: sourceUrl });
  const firstService = h.daily.getInstance();
  const [image, same] = await Promise.all([firstService.getToday(), firstService.getToday('hutao')]);
  assert.equal(h.requests.length, 1);
  assert.equal(h.downloads.length, 1);
  assert.equal(image.path, same.path);
  assert.equal(image.fromCache, false);
  assert.equal(image.author, '画师');
  assert.equal(image.sourceUrl, sourceUrl, 'the API source URL is preserved without normalization');
  assert.equal(h.closed.length, 1);
  assert.equal(h.open.size, 0);
  const restarted = await new h.daily().getToday();
  assert.equal(restarted.path, image.path);
  assert.equal(restarted.fromCache, true);
  assert.equal(restarted.author, '画师');
  assert.equal(restarted.sourceUrl, sourceUrl, 'UTF-8, percent escapes, query and fragment survive the cache round trip');
  assert.equal(h.requests.length, 1);
  h.files.delete(image.path);
  assert.equal((await firstService.getToday()).fromCache, false);
  assert.equal(h.downloads.length, 2);
});

test('daily wallpaper remains available when author or source URL is missing, null or empty', async () => {
  for (const attribution of [{}, { author: '画师' }, { source_url: 'https://example.test/source?q=1#art' },
    { author: null, source_url: null }, { author: '', source_url: '' }]) {
    const h = harness();
    h.network.metadata = async () => success({ url: wallpaper, ...attribution });
    const fresh = await h.daily.getInstance().getToday();
    assert.ok(fresh?.path, 'optional attribution cannot make a valid wallpaper unavailable');
    assert.equal(fresh.author, attribution.author ?? '');
    assert.equal(fresh.sourceUrl, attribution.source_url ?? '');
    const cached = await new h.daily().getToday();
    assert.equal(cached.path, fresh.path); assert.equal(cached.fromCache, true);
    assert.equal(cached.author, fresh.author); assert.equal(cached.sourceUrl, fresh.sourceUrl);
    assert.equal(h.requests.length, 1); assert.equal(h.downloads.length, 1);
  }
});

test('legacy wallpaper caches without readable attribution still return the cached image', async () => {
  const h = harness();
  const image = await h.daily.getInstance().getToday();
  const sidecar = `${image.path}.json`;
  h.files.delete(sidecar);
  const legacy = await new h.daily().getToday();
  assert.equal(legacy.path, image.path); assert.equal(legacy.fromCache, true);
  assert.equal(legacy.author, ''); assert.equal(legacy.sourceUrl, '');
  h.files.set(sidecar, Buffer.from('{broken metadata'));
  const recovered = await new h.daily().getToday();
  assert.equal(recovered.path, image.path); assert.equal(recovered.fromCache, true);
  assert.equal(recovered.author, ''); assert.equal(recovered.sourceUrl, '');
  assert.equal(h.requests.length, 1); assert.equal(h.downloads.length, 1);
});

test('distinct banner URLs use distinct files and an empty cache file is fetched again', async () => {
  const h = harness();
  const one = 'https://example.test/a?b=c';
  const two = 'https://example.test/a_b_c';
  const [first, again, other] = await Promise.all([one, one, two].map(url => h.images.fetchToCache(url)));
  assert.equal(first, again);
  assert.notEqual(first, other);
  assert.equal(h.downloads.length, 2);
  h.files.set(first, Buffer.alloc(0));
  assert.equal(await h.images.fetchToCache(one), first);
  assert.equal(h.downloads.length, 3);
  assert.equal(h.closed.length, 3);
});

test('clearing invalidates a late download and a later request can repopulate the cache', async () => {
  const h = harness();
  const arrived = deferred();
  const finish = deferred();
  const download = h.network.download;
  h.network.download = async (url, destination) => {
    arrived.resolve();
    await finish.promise;
    return download(url, destination);
  };
  const old = h.images.fetchToCache(wallpaper);
  await Promise.race([arrived.promise, old.then(() => assert.fail('expected an image download'))]);
  assert.equal(await h.cache.clear(), true);
  assert.deepEqual(h.changed, [{ key: 'mediaCacheVersion', value: 1 }]);
  finish.resolve();
  assert.equal(await old, '');
  assert.equal(h.files.size, 0);
  assert.equal(h.closed.length, 1);
  assert.ok(await h.images.fetchToCache(wallpaper));
  assert.equal(h.files.size, 1);
});
