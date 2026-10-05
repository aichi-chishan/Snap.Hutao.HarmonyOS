const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
let openDb = 0, openPrefs = 0, finishDb, finishPrefs;
const store = {}, prefs = {};
const platform = {
  relationalStore: { SecurityLevel: { S1: 1 }, getRdbStore: async () => {
    openDb++; await new Promise((resolve, reject) => { finishDb = { resolve, reject }; }); return store;
  } },
  preferences: { getPreferences: async () => {
    openPrefs++; await new Promise((resolve, reject) => { finishPrefs = { resolve, reject }; }); return prefs;
  } },
};
function load(name) {
  const text = ts.transpileModule(fs.readFileSync(path.join(root, name + '.ets'), 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(`(function(require,module,exports){${text}\n})`)((name) => {
    if (name === '@kit.ArkData') return platform;
    if (name.endsWith('/Logger')) return { Logger: { info() {}, warn() {} } };
    return {};
  }, module, module.exports);
  return module.exports;
}
const { PreferencesStore: Prefs } = load('data/prefs/PreferencesStore');
const { RelationalStoreHelper: DB } = load('data/db/RelationalStoreHelper');
(async () => {
  let finishMigration;
  DB.createTables = async () => new Promise((resolve, reject) => { finishMigration = { resolve, reject }; });
  const a = DB.init({}), b = DB.init({}); const dbResults = Promise.allSettled([a, b]);
  assert.equal(openDb, 1); assert.equal(DB.isReady(), false);
  finishDb.resolve(); while (!finishMigration) await new Promise(resolve => setImmediate(resolve));
  assert.equal(DB.isReady(), false, 'store is not published before migrations complete');
  finishMigration.reject(new Error('fixture migration failure'));
  assert.ok((await dbResults).every(result => result.status === 'rejected')); assert.equal(DB.isReady(), false);
  finishMigration = undefined;
  const retry = DB.init({}); assert.equal(openDb, 2); finishDb.resolve();
  while (!finishMigration) await new Promise(resolve => setImmediate(resolve)); finishMigration.resolve(); await retry;
  assert.equal(DB.isReady(), true); assert.equal(DB.getStore(), store);
  await DB.init({}); assert.equal(openDb, 2, 'already initialized runtime is reused');

  const x = Prefs.init({}), y = Prefs.init({}); const prefResults = Promise.allSettled([x, y]);
  assert.equal(openPrefs, 1); assert.equal(Prefs.isReady(), false);
  finishPrefs.reject(new Error('fixture unavailable preferences'));
  assert.ok((await prefResults).every(result => result.status === 'rejected')); assert.equal(Prefs.isReady(), false);
  const retryPrefs = Prefs.init({}); assert.equal(openPrefs, 2); finishPrefs.resolve(); await retryPrefs;
  assert.equal(Prefs.isReady(), true); await Prefs.init({}); assert.equal(openPrefs, 2);
  console.log('runtime-init: PASS (coalesced database/preferences opens, no partial publication, failed-init retry)');
})().catch(error => { console.error(error); process.exitCode = 1; });
