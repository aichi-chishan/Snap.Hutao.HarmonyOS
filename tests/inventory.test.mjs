// Run with Node.js 24+: node tests/inventory.test.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
const root = new URL('../entry/src/main/ets/', import.meta.url);
const url = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
async function ets(path, imports={}) {
  const source=(await readFile(new URL(path,root),'utf8')).replace(/from\s+'([^']+)'/g,(match,name)=>{
    assert.ok(imports[name],`Unmocked dependency: ${name}`); return `from '${imports[name]}'`;
  });
  return url(stripTypeScriptTypes(source,{mode:'transform'}));
}
const db = new DatabaseSync(':memory:');
db.exec('CREATE TABLE cultivate_inventory (project_id INTEGER, item_id INTEGER, count INTEGER, PRIMARY KEY(project_id,item_id))');
let failInsert=false;
let writes=0;
class Pred {
  constructor(table){this.table=table;this.fields=[];this.values=[];}
  equalTo(key,value){this.fields.push(`${key}=?`);this.values.push(value);return this;}
  and(){return this;}
  where(){return ` WHERE ${this.fields.join(' AND ')}`;}
}
const store={
  beginTransaction(){writes++;db.exec('BEGIN');}, commit(){db.exec('COMMIT');}, rollBack(){db.exec('ROLLBACK');},
  deleteSync(pred){return db.prepare(`DELETE FROM ${pred.table}${pred.where()}`).run(...pred.values).changes;},
  insertSync(table, values){return db.prepare(`INSERT INTO ${table} (${Object.keys(values).join(',')}) VALUES (${Object.keys(values).map(()=>'?')})`).run(...Object.values(values)).lastInsertRowid;},
  updateSync(values,pred){return Number(db.prepare(`UPDATE ${pred.table} SET ${Object.keys(values).map(k=>`${k}=?`).join(',')}${pred.where()}`).run(...Object.values(values),...pred.values).changes);},
  batchInsertSync(table,values){if(failInsert)throw new Error('simulated storage failure');values.forEach(value=>this.insertSync(table,value));return values.length;},
};
const helper={getStore:()=>store,async query(pred){
  const rows=db.prepare(`SELECT * FROM ${pred.table}${pred.where()}`).all(...pred.values);let i=-1;
  return {goToNextRow:()=>++i<rows.length,getColumnIndex:name=>name,getLong:name=>rows[i][name],close(){}};
}};
globalThis.__inventoryTest={helper,Pred};
const repoUrl=await ets('data/repo/InventoryRepo.ets',{
  '@kit.ArkData':url('export const relationalStore={RdbPredicates:globalThis.__inventoryTest.Pred};'),
  '../db/RelationalStoreHelper':url('export const RelationalStoreHelper=globalThis.__inventoryTest.helper;'),
});
const modelUrl=await ets('model/Calculate.ets');
const {InventoryRepo}=await import(repoUrl);
const {CalBatchResult}=await import(modelUrl);
const {InventoryService}=await import(await ets('service/InventoryService.ets',{
  '../data/repo/InventoryRepo':repoUrl,'../model/Calculate':modelUrl,
}));
const lightweight=materials=>JSON.stringify({materials});
const uiif=list=>JSON.stringify({info:{uiif_version:'v1.0'},list});
const batch=(items,has=true)=>CalBatchResult.fromJson({has_user_info:has,overall_consume:items});
await test('material JSON and UIIF preserve explicit zero and ignore non-material equipment',()=>{
  assert.deepEqual([...InventoryService.parseInventory(lightweight([{itemId:1,count:20},{itemId:2,count:0}]))],[[1,20],[2,0]]);
  assert.deepEqual([...InventoryService.parseInventory(uiif([{itemId:1,material:{count:25}},{itemId:100,equip:{weapon:{}}}]))],[[1,25]]);
});
await test('malformed, duplicate and fractional inventory files are rejected before writes',()=>{
  const invalid=['null','[]','{}',lightweight([{itemId:1,count:-1}]),lightweight([{itemId:1,count:'10'}]),
    lightweight([{itemId:1,count:1},{itemId:1,count:2}]),lightweight([{itemId:1,count:1.2}]),uiif([{itemId:1,material:{}}]),
    JSON.stringify({info:{uiif_version:'v2.0'},list:[]})];
  invalid.forEach(text=>assert.throws(()=>InventoryService.parseInventory(text)));
});
await test('project inventories stay isolated and import merges by default',async()=>{
  await InventoryRepo.setCount(1,10,100);await InventoryRepo.setCount(2,10,200);
  await InventoryService.importInventory(1,lightweight([{itemId:20,count:0}]));
  assert.deepEqual([...await InventoryRepo.getInventory(1)],[[10,100],[20,0]]);
  assert.deepEqual([...await InventoryRepo.getInventory(2)],[[10,200]]);
});
await test('valid calculator surplus uses signed lack_num and keeps absent materials',async()=>{
  const result=batch([{id:'10',num:'50',lack_num:'-20'},{id:30,num:10,lack_num:10}]);
  assert.equal(result.overallConsume[0].hasInventoryData,true);
  assert.equal(await InventoryService.syncFromCalculator(1,result),2);
  const saved=await InventoryRepo.getInventory(1);
  assert.equal(saved.get(10),70);assert.equal(saved.get(20),0);assert.equal(saved.get(30),0);
});
await test('missing or invalid calculator fields and unauthenticated results never erase inventory',async()=>{
  const before=[...await InventoryRepo.getInventory(1)];const beforeWrites=writes;
  const invalid=[batch([{id:10,num:50}]),batch([{id:10,num:50,lack_num:null}]),
    batch([{id:10,num:50,lack_num:''}]),batch([{id:10,num:50,lack_num:false}]),
    batch([{id:10,num:50,lack_num:51}]),batch([{id:10,num:50,lack_num:0}],false),batch([])];
  for(const result of invalid)await assert.rejects(InventoryService.syncFromCalculator(1,result));
  assert.equal(writes,beforeWrites);assert.deepEqual([...await InventoryRepo.getInventory(1)],before);
});
await test('replacement validates before deletion and database failures roll back',async()=>{
  const before=[...await InventoryRepo.getInventory(1)];
  await assert.rejects(InventoryRepo.replaceInventory(1,new Map([[100,-1]])));
  assert.deepEqual([...await InventoryRepo.getInventory(1)],before);
  failInsert=true;
  await assert.rejects(InventoryRepo.replaceInventory(1,new Map([[100,10]])),/storage failure/);
  failInsert=false;
  assert.deepEqual([...await InventoryRepo.getInventory(1)],before);
  await InventoryRepo.clear(1);
  assert.equal((await InventoryRepo.getInventory(1)).size,0);
  assert.equal((await InventoryRepo.getInventory(2)).get(10),200);
});
