const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};
const flush = () => new Promise(resolve => setImmediate(resolve));

function loadWallpaper({ image = {}, listFile = async () => [], getToday = async () => undefined,
  fileShare = { OperationMode: { READ_MODE: 1 }, checkPersistentPermission: async () => [false] } } = {}) {
  const filename = path.join(__dirname, '../entry/src/main/ets/components/WallpaperLayer.ets');
  let source = fs.readFileSync(filename, 'utf8').replace('@Component\n', '')
    .replace('export struct WallpaperLayer', 'export class WallpaperLayer');
  source = source.slice(0, source.indexOf('  build() {')) + '}';
  const compiled = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true,
  } });
  const module = { exports: {} };
  const timerIds = new Set();
  const display = new Map();
  let nextTimer = 1;
  const fileUri = {
    FileUri: class { constructor(uri) { this.path = decodeURI(uri.replace('file://media', '')); } },
    getUriFromPath: file => `file://test.bundle${encodeURI(file).replaceAll('#', '%23')}`,
  };
  const sandbox = {
    AppStorage: { setOrCreate: (key, value) => display.set(key, value) },
    State() {}, Prop() {}, StorageProp: () => () => {}, Watch: () => () => {},
    Curve: { EaseInOut: 0 },
    canIUse: () => true,
    setInterval(callback, delay) { assert.equal(delay, 300000); const id = nextTimer++; timerIds.add(id); return id; },
    clearInterval(id) { timerIds.delete(id); },
  };
  vm.runInNewContext(`(function(require, module, exports) { ${compiled.outputText}\n})`, sandbox)(id => {
    if (id === '@kit.ImageKit') return { image };
    if (id === '@kit.CoreFileKit') return { fileIo: { listFile }, fileShare, fileUri };
    if (id.endsWith('/Logger')) return { Logger: { info() {}, warn() {} } };
    if (id.endsWith('/HutaoDailyImageService')) return { HutaoDailyImageService: { getInstance: () => ({ getToday }) } };
    if (id.endsWith('/BackgroundVideoLayer') || id.endsWith('/AppContext')) return {};
    throw new Error(`Unexpected dependency ${id}`);
  }, module, module.exports);
  const { WallpaperLayer } = module.exports;
  const layer = new WallpaperLayer();
  layer.getUIContext = () => ({ animateTo(options, update) { update(); } });
  return { WallpaperLayer, layer, timerIds, fileUri, display };
}

for (const failure of ['decode', 'info', 'pixels', 'none', 'release']) {
  test(`luminance releases owned image resources after ${failure}`, async () => {
    const released = [];
    const pixelMap = {
      async getImageInfo() { if (failure === 'info') throw Error('info'); return { size: { width: 1, height: 1 } }; },
      async readPixelsToBuffer(buffer) { if (failure === 'pixels') throw Error('pixels'); new Uint8Array(buffer).set([255, 255, 255, 255]); },
      async release() { await flush(); released.push('pixel'); if (failure === 'release') throw Error('release'); },
    };
    const image = { PixelMapFormat: { RGBA_8888: 3 }, createImageSource: () => ({
      async createPixelMap() { if (failure === 'decode') throw Error('decode'); return pixelMap; },
      async release() { await flush(); released.push('source'); },
    }) };
    const { WallpaperLayer } = loadWallpaper({ image });
    const luminance = await WallpaperLayer.luminance('/images/photo.png');
    const expected = ['none', 'release'].includes(failure) ? 1 : .5;
    assert.ok(Math.abs(luminance - expected) < 1e-12);
    assert.deepEqual(released, failure === 'decode' ? ['source'] : ['pixel', 'source']);
  });
}

test('old directory scans cannot replace a new source or revive an unmounted layer', async () => {
  const first = deferred(), second = deferred();
  const { WallpaperLayer, layer } = loadWallpaper({ listFile: folder => folder === '/first' ? first.promise : second.promise });
  WallpaperLayer.luminance = async () => .5;
  layer.bgType = 'local'; layer.folderPath = '/first';
  const oldLoad = layer.loadImage();
  layer.folderPath = '/second'; const newLoad = layer.loadImage();
  second.resolve(['/photo #2.png']); await newLoad; await flush();
  assert.equal(layer.imgSrc, 'file://test.bundle/second/photo%20%232.png');
  first.resolve(['/old.png']); await oldLoad; await flush();
  assert.equal(layer.imgSrc, 'file://test.bundle/second/photo%20%232.png');

  const late = deferred();
  const detached = loadWallpaper({ listFile: () => late.promise });
  detached.WallpaperLayer.luminance = async () => .5;
  detached.layer.bgType = 'local'; detached.layer.folderPath = '/late';
  const pending = detached.layer.loadImage(); detached.layer.aboutToDisappear();
  late.resolve(['/late.png']); await pending; await flush();
  assert.equal(detached.layer.hasImage, false);
});

test('local rotation consumes a cycle without repeats and keeps one five-minute timer', async () => {
  const { WallpaperLayer, layer, timerIds } = loadWallpaper({ listFile: async () => ['/a.png', '/b.jpg', '/c.webp', '/notes.txt'] });
  WallpaperLayer.luminance = async () => .5;
  layer.bgType = 'local'; layer.folderPath = '/images'; layer.aboutToAppear(); await flush();
  const seen = new Set([layer.imgSrc]);
  for (let i = 0; i < 2; i++) { await layer.pickLocalRandom(); await flush(); seen.add(layer.imgSrc); }
  assert.equal(seen.size, 3);
  const previous = layer.imgSrc;
  await layer.pickLocalRandom(); await flush(); assert.notEqual(layer.imgSrc, previous);
  layer.onBgChanged(); await flush(); assert.equal(timerIds.size, 1);
  layer.aboutToDisappear(); assert.equal(timerIds.size, 0);
});

test('late remote results cannot replace a local wallpaper or a disabled background', async () => {
  const daily = deferred();
  const { WallpaperLayer, layer } = loadWallpaper({ getToday: () => daily.promise, listFile: async () => ['/new.png'] });
  WallpaperLayer.luminance = async () => .5;
  layer.bgType = 'hutao'; const pending = layer.loadImage();
  layer.bgType = 'local'; layer.folderPath = '/local'; await layer.loadImage(); await flush();
  daily.resolve({ path: '/cache/old.jpg', author: '', fromCache: true }); await pending;
  assert.equal(layer.imgSrc, 'file://test.bundle/local/new.png');
  layer.bgType = 'none'; await layer.loadImage(); assert.equal(layer.hasImage, false);
});

test('settings receives only the currently displayed wallpaper credit and web source', async () => {
  const old = deferred();
  const current = { path: '/cache/today.jpg', author: 'miHoYo', sourceUrl: 'https://example.com/original', fromCache: true };
  const h = loadWallpaper({ getToday: source => source === 'bing' ? old.promise : Promise.resolve(current) });
  h.WallpaperLayer.luminance = async () => .5;
  h.layer.bgType = 'bing'; const pending = h.layer.loadImage();
  h.layer.bgType = 'hutao'; await h.layer.loadImage();
  old.resolve({ ...current, author: 'previous' }); await pending;
  assert.equal(h.display.get('bgCopyright'), 'miHoYo');
  assert.equal(h.display.get('bgSourceUrl'), current.sourceUrl);
  current.sourceUrl = 'file:///private'; await h.layer.loadImage();
  assert.equal(h.display.get('bgSourceUrl'), '');
  h.layer.bgType = 'none'; await h.layer.loadImage();
  assert.equal(h.display.get('bgCopyright'), '');
  assert.equal(h.display.get('dailyWallpaperState'), '');
});

test('persisted Picker URI is activated before scanning; temporary authorization still works', async () => {
  const uri = 'file://media/storage/space%20name';
  for (const mode of ['persistent', 'temporary', 'activation-failed']) {
    const calls = [];
    const fileShare = {
      OperationMode: { READ_MODE: 1 },
      async checkPersistentPermission(policies) { assert.equal(policies[0].uri, uri); calls.push('check'); return [mode !== 'temporary']; },
      async activatePermission(policies) { assert.equal(policies[0].operationMode, 1); calls.push('activate'); if (mode === 'activation-failed') throw Error('denied'); },
    };
    const { WallpaperLayer } = loadWallpaper({ fileShare, listFile: async folder => {
      assert.equal(folder, '/storage/space name'); calls.push('scan'); return ['/image.png'];
    } });
    const paths = await WallpaperLayer.scanImages(uri);
    assert.deepEqual(calls, mode === 'temporary' ? ['check', 'scan'] : ['check', 'activate', 'scan']);
    assert.equal(paths[0], '/storage/space name/image.png');
  }
});
