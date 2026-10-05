// Tests only the production filesystem adapter. Compatible with the serial cohort checkpoint.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const source = process.env.SNAPSHOT_IO_SOURCE || path.resolve(__dirname, '../entry/src/main/ets/data/remote/HarmonySnapshotIo.ets');
const compiled = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }, reportDiagnostics: true,
}); assert.equal(compiled.diagnostics.length, 0);
const sandboxes = [];
function fixture() {
  const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'hutao-quota-traversal-')); sandboxes.push(sandbox);
  const state = { scans: [], afterLstat: null, enumerate: null };
  const fileIo = {
    lstatSync(file) { const stat = fs.lstatSync(file); state.afterLstat?.(file, stat); return stat; },
    mkdirSync: file => fs.mkdirSync(file),
    listFileSync(file, options) {
      state.scans.push({ file, ...options });
      assert.equal(options.recursion, false, 'adapter must never request native recursive traversal');
      assert.ok(Number.isInteger(options.listNum) && options.listNum >= 1 && options.listNum <= 100001);
      return state.enumerate?.(file, options) ?? fs.readdirSync(file).slice(0, options.listNum);
    },
  };
  const module = { exports: {} };
  const kits = { '@kit.CoreFileKit': { fileIo }, '@kit.ArkTS': {}, '@kit.CryptoArchitectureKit': {} };
  vm.runInThisContext(`(function(require,module,exports){${compiled.outputText}\n})`, { filename: source })(name => {
    assert.ok(Object.hasOwn(kits, name), 'unmocked import: ' + name); return kits[name];
  }, module, module.exports);
  const io = new module.exports.HarmonySnapshotIo(sandbox);
  function write(relative, bytes) {
    const file = path.join(io.root, relative); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, bytes); return file;
  }
  return { io, sandbox, state, write };
}
let count = 0;
function test(name, run) { run(); console.log(`PASS ${++count}: ${name}`); }
try {
  test('validated retained files are counted through one-level enumeration', () => {
    const h = fixture(); h.write('staging/a/one.bin', Buffer.alloc(3)); h.write('snapshots/b/nested/two.bin', Buffer.alloc(7)); h.write('retained.bin', Buffer.alloc(11));
    assert.equal(h.io.usedBytes(), 21); assert.equal(new Set(h.state.scans.map(scan => scan.file)).size, 6);
    assert.ok(h.state.scans.every(scan => scan.recursion === false));
  });
  test('a symlink in the cohort-root ancestry is rejected before enumeration', () => {
    const h = fixture(), outside = path.join(h.sandbox, 'outside'); fs.mkdirSync(outside); fs.writeFileSync(path.join(outside, 'keep'), 'keep');
    fs.symlinkSync(outside, path.join(h.sandbox, 'gamedata'));
    assert.throws(() => h.io.usedBytes(), /不安全/); assert.equal(h.state.scans.length, 0);
    assert.equal(fs.readFileSync(path.join(outside, 'keep'), 'utf8'), 'keep');
  });
  test('a directory symlink is rejected before its target is scanned', () => {
    const h = fixture(), outside = path.join(h.sandbox, 'outside'); fs.mkdirSync(outside); fs.mkdirSync(h.io.root, { recursive: true });
    fs.writeFileSync(path.join(outside, 'keep'), 'keep'); fs.symlinkSync(outside, path.join(h.io.root, 'staging'));
    assert.throws(() => h.io.usedBytes(), /不安全/); assert.deepEqual(h.state.scans.map(scan => scan.file), [h.io.root]);
    assert.equal(fs.readFileSync(path.join(outside, 'keep'), 'utf8'), 'keep');
  });
  test('an ancestor-cycle symlink fails closed without recursive ELOOP scanning', () => {
    const h = fixture(); fs.mkdirSync(h.io.root, { recursive: true }); fs.symlinkSync(h.sandbox, path.join(h.io.root, 'staging'));
    assert.throws(() => h.io.usedBytes(), /不安全/); assert.equal(h.state.scans.length, 1);
  });
  test('a file symlink is rejected without following or changing its target', () => {
    const h = fixture(), outside = path.join(h.sandbox, 'outside.bin'); fs.writeFileSync(outside, 'untouched'); fs.mkdirSync(h.io.root, { recursive: true });
    fs.symlinkSync(outside, path.join(h.io.root, 'receipt.bin')); assert.throws(() => h.io.usedBytes(), /不安全/);
    assert.equal(fs.readFileSync(outside, 'utf8'), 'untouched'); assert.equal(h.state.scans.length, 1);
  });
  test('a queued directory replaced after lstat is rechecked before its scan', () => {
    const h = fixture(), branch = path.join(h.io.root, 'branch'), outside = path.join(h.sandbox, 'outside');
    fs.mkdirSync(branch, { recursive: true }); fs.mkdirSync(outside); fs.writeFileSync(path.join(outside, 'keep'), 'keep');
    let replaced = false;
    h.state.afterLstat = (file, stat) => {
      if (file === branch && stat.isDirectory() && !replaced) {
        replaced = true; fs.renameSync(branch, branch + '-retained'); fs.symlinkSync(outside, branch);
      }
    };
    assert.throws(() => h.io.usedBytes(), /不安全/); assert.equal(replaced, true);
    assert.deepEqual(h.state.scans.map(scan => scan.file), [h.io.root]); assert.equal(fs.readFileSync(path.join(outside, 'keep'), 'utf8'), 'keep');
  });
  test('all directories share one entry budget and oversized lists fail before entry access', () => {
    const h = fixture(); fs.mkdirSync(path.join(h.io.root, 'branch'), { recursive: true });
    h.state.enumerate = file => file === h.io.root ? ['branch'] : Array(100000).fill('never-lstat');
    assert.throws(() => h.io.usedBytes(), /数量超过/); assert.equal(h.state.scans.length, 2);
    assert.equal(h.state.scans[0].listNum, 100001); assert.equal(h.state.scans[1].listNum, 100000);
  });
  test('nonrecursive results cannot smuggle unvalidated descendant or parent paths', () => {
    for (const name of ['nested/unchecked', '../outside', '', '/']) {
      const h = fixture(); h.state.enumerate = () => [name]; assert.throws(() => h.io.usedBytes(), /不安全|超出/);
      assert.equal(h.state.scans.length, 1);
    }
  });
  test('deep directory trees use an iterative queue and bounded one-level scans', () => {
    const h = fixture(); const depth = 96; h.write(Array(depth).fill('d').join('/') + '/leaf.bin', Buffer.alloc(9));
    assert.equal(h.io.usedBytes(), 9); assert.equal(h.state.scans.length, depth + 1);
    assert.ok(h.state.scans.every(scan => scan.recursion === false && scan.listNum <= 100001));
  });
  console.log(`snapshot-quota-traversal: PASS ${count} production adapter cases (host filesystem boundaries)`);
} catch (error) { console.error(error); process.exitCode = 1; }
finally { for (const sandbox of sandboxes) fs.rmSync(sandbox, { recursive: true, force: true }); /* only roots created by this fixture */ }
