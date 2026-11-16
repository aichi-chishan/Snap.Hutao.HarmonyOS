const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(yes => { resolve = yes; }); return { promise, resolve }; };

function fixture(fetchSource = async () => 'file://test/video.mp4') {
  let text = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/BackgroundVideoLayer.ets'), 'utf8')
    .replace('@Component\n', '').replace('export struct BackgroundVideoLayer', 'export class BackgroundVideoLayer');
  const render = text.slice(text.indexOf('  build() {'));
  text = text.slice(0, text.indexOf('  build() {')) + '}';
  const compiled = ts.transpileModule(text, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true,
  } });
  const storage = new Map();
  const module = { exports: {} };
  const env = {
    State() {}, StorageProp: () => () => {}, Watch: () => () => {},
    AppStorage: { setOrCreate: (key, value) => storage.set(key, value) },
    VideoController: class {
      calls = [];
      start() { this.calls.push('start'); }
      pause() { this.calls.push('pause'); }
      stop() { this.calls.push('stop'); }
    },
  };
  vm.runInNewContext(`(function(require, module, exports) { ${compiled.outputText}\n})`, env)(id => {
    if (id.endsWith('/BackgroundMediaService')) return { BackgroundMediaService: { source: fetchSource } };
    if (id.endsWith('/PreferencesStore')) return { PreferencesStore: { getBool: () => true, getString: () => 'local' } };
    throw new Error(`Unexpected dependency ${id}`);
  }, module, module.exports);
  return { layer: new module.exports.BackgroundVideoLayer(), storage, render };
}

test('playback waits for preparation, visibility and foreground together', async () => {
  const { layer, render } = fixture();
  assert.match(render, /\.autoPlay\(false\)/, 'native autoPlay must not bypass playback conditions');
  layer.foreground = false; layer.aboutToAppear(); await flush();
  const source = layer.sources[0];
  layer.onVisibilityChanged(source, 1); assert.equal(source.controller.calls.length, 0);
  layer.onPrepared(source); assert.deepEqual(source.controller.calls, ['pause']);
  layer.foreground = true; layer.syncPlayback(); assert.equal(source.controller.calls.at(-1), 'start');
  layer.onVisibilityChanged(source, 0); assert.equal(source.controller.calls.at(-1), 'pause');
  layer.onStarted(source); assert.equal(source.controller.calls.at(-1), 'pause');
  layer.onVisibilityChanged(source, 1); assert.equal(source.controller.calls.at(-1), 'start');
  layer.aboutToDisappear(); assert.equal(source.controller.calls.at(-1), 'stop');
  const count = source.controller.calls.length;
  layer.onPrepared(source); layer.onVisibilityChanged(source, 1); layer.syncPlayback();
  assert.equal(source.controller.calls.length, count, 'detached callbacks cannot restart playback');
});

test('replacement creates a separate controller even for the same URL', async () => {
  const { layer, storage } = fixture(); layer.aboutToAppear(); await flush();
  const first = layer.sources[0]; layer.onVisibilityChanged(first, 1); layer.onPrepared(first);
  await layer.loadSource(); const second = layer.sources[0];
  assert.notEqual(second.id, first.id); assert.notEqual(second.controller, first.controller);
  assert.equal(first.controller.calls.at(-1), 'stop');
  const status = storage.get('backgroundMediaStatus');
  layer.onPlaybackError(first); layer.onPrepared(first); layer.onVisibilityChanged(first, 1);
  assert.equal(layer.sources[0], second); assert.equal(storage.get('backgroundMediaStatus'), status);
  layer.onStarted(first); assert.equal(first.controller.calls.at(-1), 'pause');
  assert.equal(second.controller.calls.length, 0);
  layer.onPlaybackError(second); assert.equal(layer.sources.length, 0);
  layer.onPrepared(second); assert.equal(second.controller.calls.length, 0);
});

test('late source requests cannot overwrite a replacement or recreate a detached Video', async () => {
  const requests = [];
  const { layer } = fixture(() => { const wait = deferred(); requests.push(wait); return wait.promise; });
  layer.aboutToAppear(); const next = layer.loadSource();
  requests[1].resolve('file://new.mp4'); await next;
  requests[0].resolve('file://old.mp4'); await flush();
  assert.equal(layer.sources[0].path, 'file://new.mp4');
  const late = layer.loadSource(); layer.aboutToDisappear();
  requests[2].resolve('file://detached.mp4'); await late;
  assert.equal(layer.sources.length, 0);
  await layer.loadSource(); assert.equal(requests.length, 3, 'watchers after teardown do not fetch');
});
