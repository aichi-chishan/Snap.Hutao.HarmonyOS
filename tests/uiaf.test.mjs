// Run with Node.js 24+: node --test tests/uiaf.test.mjs
// Executes the production ArkTS model/service/repository after stripping types.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';

const root = new URL('../entry/src/main/ets/', import.meta.url);
const moduleUrl = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
async function etsUrl(path, imports = {}) {
  let code = await readFile(new URL(path, root), 'utf8');
  code = code.replace(/from\s+'([^']+)'/g, (match, name) => {
    assert.ok(imports[name], `Unmocked platform import: ${name}`);
    return `from '${imports[name]}'`;
  });
  return moduleUrl(stripTypeScriptTypes(code, { mode: 'transform' }));
}
const modelUrl = await etsUrl('model/AchievementData.ets');
const { AchievementRecord, UiafCodec, UiafImportStrategy } = await import(modelUrl);

const db = new DatabaseSync(':memory:');
db.exec(`CREATE TABLE achievement_entries (archive_id INTEGER, ach_id INTEGER, current INTEGER, status INTEGER, timestamp INTEGER)`);
let batchCalls = 0;
let failAtBatch = 0;
let transactionCount = 0;
class Predicates {
  constructor(table) { this.table = table; this.fields = []; this.values = []; }
  equalTo(field, value) { this.fields.push(`${field} = ?`); this.values.push(value); return this; }
  and() { return this; }
  where() { return this.fields.length ? ` WHERE ${this.fields.join(' AND ')}` : ''; }
}
function insert(values) {
  const keys = Object.keys(values);
  return db.prepare(`INSERT INTO achievement_entries (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`).run(...Object.values(values));
}
const store = {
  beginTransaction() { transactionCount++; batchCalls = 0; db.exec('BEGIN'); },
  commit() { db.exec('COMMIT'); },
  rollBack() { db.exec('ROLLBACK'); },
  deleteSync(pred) { return Number(db.prepare(`DELETE FROM ${pred.table}${pred.where()}`).run(...pred.values).changes); },
  batchInsertSync(table, values) {
    batchCalls++;
    if (batchCalls === failAtBatch) throw new Error('injected disk failure');
    values.forEach(insert);
    return values.length;
  },
  insertSync(table, values) { return Number(insert(values).lastInsertRowid); },
  updateSync(values, pred) {
    return Number(db.prepare(`UPDATE ${pred.table} SET ${Object.keys(values).map(key => `${key}=?`).join(',')}${pred.where()}`)
      .run(...Object.values(values), ...pred.values).changes);
  },
};
const helper = {
  getStore: () => store,
  async query(pred) {
    const rows = db.prepare(`SELECT * FROM ${pred.table}${pred.where()}`).all(...pred.values);
    let index = -1;
    return { goToNextRow: () => ++index < rows.length, getColumnIndex: name => name,
      getLong: name => rows[index][name], close() {} };
  },
};
globalThis.__uiafTest = { helper, Predicates };
const loggerUrl = moduleUrl('export const Logger = {info(){},warn(){}};');
const repoUrl = await etsUrl('data/repo/AchievementRepo.ets', {
  '@kit.ArkData': moduleUrl('export const relationalStore = {RdbPredicates:globalThis.__uiafTest.Predicates};'),
  '../db/RelationalStoreHelper': moduleUrl('export const RelationalStoreHelper=globalThis.__uiafTest.helper;'),
  '../../model/AchievementData': modelUrl,
  '../../common/Logger': loggerUrl,
});
const { AchievementRepo } = await import(repoUrl);
const serviceUrl = await etsUrl('service/AchievementService.ets', {
  '@kit.ArkTS': moduleUrl('export const util={};'),
  '../common/AppContext': moduleUrl('export const AppContextProvider={};'),
  '../data/repo/AchievementRepo': repoUrl,
  './WikiMetaService': moduleUrl('export const WikiMetaService={cleanText:text=>text};'),
  '../model/AchievementData': modelUrl,
  '../common/Logger': loggerUrl,
  './GameDataService': moduleUrl(`export const GameDataDomain={}; export const GameDataService={
    getInstance:()=>({remoteVersion:()=>'',readText:async()=>'{}'}),
    readMetadataFile: async name => JSON.stringify(name==='AchievementGoal.json'?[{Id:1,Name:'test',Order:1}]:
      [1,2,3].map(id=>({Id:id,Goal:1,Title:'test',Description:'',Order:id,Reward:5}))) };`),
  '../common/Constants': moduleUrl('export const AppConstants={APP_VERSION:"test"};'),
});
const { AchievementService } = await import(serviceUrl);
const item = (id, status = 1, current = 30, timestamp = 0) => ({ id, status, current, timestamp });
const json = list => JSON.stringify({ info: { export_app: 'fixture', uiaf_version: 'v1.1' }, list });
const parse = list => UiafCodec.parse(json(list), 7);
const records = list => new Map(parse(list).map(record => [record.achId, record]));
function clearDb() { db.exec('DELETE FROM achievement_entries'); failAtBatch = 0; }

await test('completion depends on status, including completed records with unknown progress', () => {
  const values = parse([item(1, 1, 30), item(2, 2, 0), item(3, 3, 0), item(4, 0, 90)]);
  assert.deepEqual(values.map(AchievementRecord.isDone), [false, true, true, false]);
  assert.equal(AchievementRecord.isDone(undefined), false);
});
await test('UIAF exact round trip retains all statuses, unknown IDs, progress, and second timestamps', () => {
  const values = [item(4000000000, 1, 4294967295, 253402271999), item(1, 0, 0, -62135596800),
    item(2, 2, 30, 1700000000), item(3, 3, 0, 0)];
  const exported = JSON.parse(UiafCodec.export(parse(values), '1.2.3', 1800000000));
  assert.equal(exported.info.uiaf_version, 'v1.1');
  assert.deepEqual(exported.list, values.toSorted((a,b) => a.id-b.id));
  assert.deepEqual(UiafCodec.parse(JSON.stringify(exported), 7), parse(values).sort((a,b) => a.achId-b.achId));
});
await test('reject malformed roots, missing fields, unsupported versions, duplicate IDs and invalid numbers', () => {
  const invalid = ['{', 'null', '[]', '{}', json({}), json([null]), json([[]]),
    JSON.stringify({info:{export_app:'fixture',uiaf_version:'v1.0'},list:[]}),
    JSON.stringify({info:{uiaf_version:'v1.1'},list:[]}), json([item(1), item(1)]),
    ...[{id:0},{id:'1'},{current:-1},{current:0.5},{status:-1},{status:4},{timestamp:1700000000000}]
      .map(patch => json([{...item(1),...patch}])),
    ...['id','current','status','timestamp'].map(field => {const value=item(1);delete value[field];return json([value]);})];
  invalid.forEach(text => assert.throws(() => UiafCodec.parse(text,7), undefined, text));
  assert.deepEqual(parse([]), []);
});
await test('Lazy, Aggressive and Overwrite preserve the upstream conflict semantics', () => {
  const existing = records([item(1,3,99,100), item(2,1,4,0)]);
  const incoming = parse([item(1,1,3,0), item(3,2,0,200)]);
  const lazy = UiafCodec.merge(existing, incoming);
  assert.deepEqual(lazy.map(r => [r.achId,r.status,r.current,r.timestamp]), [[1,3,99,100],[2,1,4,0],[3,2,0,200]]);
  const aggressive = UiafCodec.merge(existing, incoming, UiafImportStrategy.Aggressive);
  assert.deepEqual(aggressive.map(r => [r.achId,r.status,r.current]), [[1,1,3],[2,1,4],[3,2,0]]);
  const overwrite = UiafCodec.merge(existing, incoming, UiafImportStrategy.Overwrite);
  assert.deepEqual(overwrite.map(r => r.achId), [1,3]);
  assert.deepEqual(UiafCodec.merge(existing, [], UiafImportStrategy.Overwrite), []);
  assert.equal(existing.get(1).current, 99);
});
await test('service import/export and repository retain unfinished progress, stats count only completed', async () => {
  clearDb();
  const values = [item(1,1,30),item(2,2,0,100),item(3,3,100,200)];
  const result = await AchievementService.importUiaf(7,json(values));
  assert.equal(result.ok,true); assert.equal(result.mergedDone,2); assert.equal(result.mergedTotal,3);
  assert.deepEqual(JSON.parse(await AchievementService.exportUiaf(7)).list,values);
  const stats = await AchievementService.getOverallStats(7);
  assert.equal(stats.done,2); assert.equal(stats.total,3); assert.equal(stats.primogemsEarned,10);
  assert.equal((await AchievementService.getCategoryStats(7))[0].stats.done,2);
});
await test('invalid import never starts a database write and leaves the archive intact', async () => {
  clearDb(); await AchievementRepo.replaceRecords(7,parse([item(1,3,40,100)]));
  const before=transactionCount;
  const result=await AchievementService.importUiaf(7,json([item(2),{...item(3),status:8}]));
  assert.equal(result.ok,false); assert.equal(transactionCount,before);
  assert.equal((await AchievementRepo.getRecords(7)).get(1).current,40);
});
await test('failed second insertion chunk rolls back deletion and all earlier chunks', async () => {
  clearDb(); await AchievementRepo.replaceRecords(7,parse([item(999,3,40,100)]));
  failAtBatch=2;
  await assert.rejects(AchievementRepo.replaceRecords(7,parse(Array.from({length:501},(_,i)=>item(i+1)))),/disk failure/);
  failAtBatch=0;
  const saved=await AchievementRepo.getRecords(7);
  assert.equal(saved.size,1); assert.equal(saved.get(999).current,40);
});
await test('manual checking and unchecking preserves known progress', async () => {
  clearDb(); await AchievementRepo.replaceRecords(7,parse([item(1,1,30,0)]));
  assert.equal(await AchievementService.toggle(7,1),true);
  let saved=(await AchievementRepo.getRecords(7)).get(1);
  assert.equal(saved.current,30); assert.equal(saved.status,3);
  await AchievementRepo.setRecord(7,1,false,0);
  saved=(await AchievementRepo.getRecords(7)).get(1);
  assert.equal(saved.current,30); assert.equal(saved.status,0); assert.equal(saved.timestamp,0);
});
