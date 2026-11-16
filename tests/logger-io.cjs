// Production Logger with the file, HiLog and timer boundaries replaced by deterministic doubles.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/common/Logger.ets'), 'utf8');
const compiled = ts.transpileModule(source, { reportDiagnostics: true,
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
assert.equal(compiled.diagnostics.length, 0);
const FILE = '/sandbox/files/app.log';
const LIMIT = 256 * 1024;
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };

function storage(initial = Buffer.alloc(0)) {
  const state = { bytes: initial, fd: 0, opens: 0, locks: 0, stats: 0, reads: 0, writes: 0,
    truncates: 0, closes: 0, failWrites: 0, shortWrite: false, writeGate: undefined, active: undefined };
  let tail = Promise.resolve();
  const fileIo = {
    OpenMode: { READ_WRITE: 1, CREATE: 2, APPEND: 4, NOFOLLOW: 8 },
    async open(filename, mode) {
      assert.equal(filename, FILE);
      assert.equal(mode, 15);
      state.opens++;
      const file = { fd: ++state.fd, async lock(exclusive) {
        assert.equal(exclusive, true);
        state.locks++;
        const previous = tail;
        const lock = deferred();
        tail = lock.promise;
        await previous;
        assert.equal(state.active, undefined);
        state.active = file.fd;
        file.release = lock.resolve;
      } };
      return file;
    },
    async stat(fd) { assert.equal(fd, state.active); state.stats++; return { size: state.bytes.length }; },
    async read(fd, buffer, { offset }) {
      assert.equal(fd, state.active);
      state.reads++;
      return state.bytes.copy(Buffer.from(buffer), 0, offset, offset + buffer.byteLength);
    },
    async truncate(fd, length) {
      assert.equal(fd, state.active);
      state.truncates++;
      state.bytes = state.bytes.subarray(0, length);
    },
    async write(fd, buffer) {
      assert.equal(fd, state.active);
      state.writes++;
      if (state.writeGate !== undefined) {
        const gate = state.writeGate;
        state.writeGate = undefined;
        await gate.promise;
      }
      if (state.failWrites > 0) { state.failWrites--; throw Error('write unavailable'); }
      const bytes = Buffer.from(buffer);
      const length = state.shortWrite ? bytes.indexOf(Buffer.from('🌙')) + 2 : bytes.length;
      state.bytes = Buffer.concat([state.bytes, bytes.subarray(0, length)]);
      return length;
    },
    async close(file) {
      state.closes++;
      assert.equal(file.fd, state.active);
      state.active = undefined;
      file.release();
    },
  };
  return { state, fileIo };
}

function logger({ fileIo }) {
  const messages = [];
  const timers = new Map();
  let nextTimer = 0;
  const hilog = Object.fromEntries(['info', 'debug', 'warn', 'error'].map(level =>
    [level, (...args) => messages.push([level, ...args])]));
  const bindings = {
    '@kit.PerformanceAnalysisKit': { hilog }, '@kit.CoreFileKit': { fileIo },
    '@kit.ArkTS': { util: { TextEncoder: { create: () => ({ encodeInto: text => new TextEncoder().encode(text) }) } } },
    './AppContext': { AppContextProvider: { getFilesDir: () => '/sandbox/files' } },
  };
  const mod = { exports: {} };
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`, {
    setTimeout(callback) { const id = ++nextTimer; timers.set(id, callback); return id; },
    clearTimeout(id) { timers.delete(id); },
  })(name => { assert.ok(bindings[name], name); return bindings[name]; }, mod, mod.exports);
  return { log: mod.exports.Logger, messages, timers };
}

test('HiLog is immediate and a burst queues one async file batch', async () => {
  const backend = storage();
  const { log, messages, timers } = logger(backend);
  for (let index = 0; index < 30; index++) log.info('batch', `line-${index}`);
  assert.equal(messages.length, 30);
  assert.equal(backend.state.opens, 0);
  assert.equal(timers.size, 1);
  timers.values().next().value();
  await log.flush();
  assert.equal(timers.size, 0);
  const { opens, writes, closes, reads, truncates, locks } = backend.state;
  assert.deepEqual({ opens, writes, closes, reads, truncates, locks }, { opens: 1, writes: 1, closes: 1, reads: 0, truncates: 0, locks: 1 });
  assert.deepEqual(backend.state.bytes.toString().trimEnd().split('\n').map(line => line.split('] ')[1]),
    Array.from({ length: 30 }, (_, index) => `line-${index}`));
  await log.flush();
  assert.equal(backend.state.opens, 1);
});

test('explicit flush waits for in-flight writes and drains messages arriving while they run', async () => {
  const backend = storage();
  const { log, timers } = logger(backend);
  const gate = deferred();
  backend.state.writeGate = gate;
  log.info('sequence', 'first');
  const first = log.flush();
  await tick();
  assert.equal(backend.state.writes, 1);
  log.warn('sequence', 'second');
  const second = log.flush();
  assert.equal(first, second);
  assert.equal(backend.state.opens, 1);
  gate.resolve();
  await second;
  assert.equal(timers.size, 0);
  assert.match(backend.state.bytes.toString(), /first\n.*second\n$/s);
  assert.equal(backend.state.closes, 2);
});

test('retains complete UTF-8 lines at a fixed byte limit, including a pre-existing oversized log', async () => {
  const history = Array.from({ length: 20000 }, (_, index) => `previous-${index} 原始记录 🍀\n`).join('');
  const backend = storage(Buffer.from(history));
  const { log } = logger(backend);
  log.warn('cap', '最新日志 🌙');
  await log.flush();
  assert.ok(backend.state.bytes.length <= LIMIT);
  assert.equal(backend.state.reads, 1);
  assert.equal(backend.state.truncates, 1);
  const text = new TextDecoder('utf-8', { fatal: true }).decode(backend.state.bytes);
  assert.match(text, /^previous-\d+ 原始记录 🍀\n/);
  assert.ok(text.includes('previous-19999'));
  assert.ok(text.endsWith('最新日志 🌙\n'));
});

test('file failure settles flush and subsequent batches can write without recursive logging', async () => {
  const backend = storage();
  const { log, messages } = logger(backend);
  backend.state.failWrites = 1;
  log.error('failure', 'retained in HiLog');
  await log.flush();
  assert.equal(messages.length, 1);
  assert.equal(backend.state.bytes.length, 0);
  assert.equal(backend.state.closes, 1);
  log.info('failure', 'next batch succeeds');
  await log.flush();
  assert.equal(messages.length, 2);
  assert.match(backend.state.bytes.toString(), /next batch succeeds\n$/);
});

test('a short write retains only complete lines and does not leave invalid UTF-8', async () => {
  const backend = storage(Buffer.from('previous\n'));
  backend.state.shortWrite = true;
  const { log } = logger(backend);
  log.info('short', 'complete line');
  log.info('short', 'cut emoji 🌙 here');
  await log.flush();
  const text = new TextDecoder('utf-8', { fatal: true }).decode(backend.state.bytes);
  assert.match(text, /^previous\n.*complete line\n$/s);
  assert.equal(backend.state.truncates, 1);
});

test('separate runtimes keep the same file bounded when their batches overlap', async () => {
  const backend = storage(Buffer.from('prior entry 🍀\n'.repeat(20000)));
  const first = logger(backend).log;
  const second = logger(backend).log;
  const gate = deferred();
  backend.state.writeGate = gate;
  first.info('process-a', 'A');
  second.info('process-b', 'B');
  const left = first.flush(), right = second.flush();
  await tick();
  assert.equal(backend.state.opens, 2);
  assert.equal(backend.state.locks, 2);
  assert.equal(backend.state.stats, 1);
  gate.resolve();
  await Promise.all([left, right]);
  assert.ok(backend.state.bytes.length <= LIMIT);
  assert.match(backend.state.bytes.toString(), /\[process-a\] A\n.*\[process-b\] B\n$/s);
  assert.equal(backend.state.active, undefined);
});
