// Execute the production daily-note repository guard after its final asynchronous read.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const file = path.resolve(__dirname, '../entry/src/main/ets/data/repo/DailyNoteRepo.ets');
let queries = 0, writes = 0, active = true, finishQuery, finishWrite, blockWrite = false, rollbacks = 0;
let existing = false, updated;
class Predicates { equalTo() {} }
const helper = { getStore: () => ({ createTransaction: async () => {
  let staged = 0;
  return { query: async () => {
      queries++;
      await new Promise(resolve => { finishQuery = resolve; });
      return { goToFirstRow: () => existing, close() {} };
    },
    insert: async () => { staged++; if (blockWrite) await new Promise(resolve => { finishWrite = resolve; }); },
    update: async values => { staged++; updated = values; },
    commit: async () => { writes += staged; }, rollback: async () => { rollbacks++; staged = 0; } };
} }) };
const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
}).outputText;
const moduleResult = { exports: {} };
vm.runInNewContext(`(function(require,module,exports){${output}\n})`)((name) => {
  if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: Predicates, TransactionType: { IMMEDIATE: 1 } } };
  if (name.endsWith('/RelationalStoreHelper')) return { RelationalStoreHelper: helper };
  if (name.endsWith('/Logger')) return { Logger: { info() {} } };
  return {};
}, moduleResult, moduleResult.exports);
const Repo = moduleResult.exports.DailyNoteRepo;
(async () => {
  const saving = Repo.upsert(1, '100000001', {}, async () => active);
  while (!finishQuery) await new Promise(resolve => setImmediate(resolve));
  active = false; finishQuery(); await saving;
  assert.equal(writes, 0, 'cancelled after repo reads but before final write must not persist');
  active = true; finishQuery = undefined;
  const current = Repo.upsert(1, '100000001', {}, async () => active);
  while (!finishQuery) await new Promise(resolve => setImmediate(resolve)); finishQuery(); await current;
  assert.equal(writes, 1); assert.equal(queries, 2); assert.equal(rollbacks, 1);
  blockWrite = true; finishQuery = undefined;
  const transactional = Repo.upsert(1, '100000001', {}, async () => active);
  while (!finishQuery) await new Promise(resolve => setImmediate(resolve)); finishQuery();
  while (!finishWrite) await new Promise(resolve => setImmediate(resolve)); active = false; finishWrite(); await transactional;
  assert.equal(writes, 1, 'cancel after dispatched write rolls back before publication'); assert.equal(rollbacks, 2);
  active = true; existing = true; finishQuery = undefined;
  const refreshing = Repo.upsert(1, '100000001', { currentResin: 175 }, async () => active);
  while (!finishQuery) await new Promise(resolve => setImmediate(resolve)); finishQuery(); await refreshing;
  assert.equal(updated.current_resin, 175);
  assert.equal(Object.keys(updated).some(key => key.includes('threshold') || key === 'notify_flags'), false,
    'cache refresh cannot overwrite a threshold or notification toggle saved concurrently');
  console.log('background-daily-persistence: PASS (cancellation boundaries and threshold preservation)');
})().catch(error => { console.error(error); process.exitCode = 1; });
