// Node.js 24+: node tests/data-port.test.mjs
// Runs production ETS logic; only platform/database/network boundaries are mocked.
// Offline expected totals follow Windows Service/Cultivation/Offline/Lookups.cs and XP tables.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
const root=new URL('../entry/src/main/ets/',import.meta.url);
const url=code=>`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
async function ets(path,imports={}){
  const source=(await readFile(new URL(path,root),'utf8')).replace(/from\s+'([^']+)'/g,(match,name)=>{
    assert.ok(imports[name],`Unmocked dependency: ${name}`);return `from '${imports[name]}'`;
  });
  return url(stripTypeScriptTypes(source,{mode:'transform'}));
}
const logger=url('export const Logger={info(){},warn(){}};');
const archives=[];const gachaRows=[];let gachaWrites=0;
const gachaRepo={
  async getAllArchives(){return archives;},
  async getOrCreateArchive(uid){gachaWrites++;let archive=archives.find(a=>a.uid===uid);if(!archive){archive={id:archives.length+1,uid};archives.push(archive);}return archive;},
  async getItemsByArchive(id){return gachaRows.filter(row=>row.archiveId===id);},
  async insertItems(items){gachaWrites++;gachaRows.push(...items);return items.length;},
};
globalThis.__dataPort={gachaRepo};
const {UigfService}=await import(await ets('service/UigfService.ets',{
  '../data/repo/GachaRepo':url('export const GachaRepo=globalThis.__dataPort.gachaRepo;'),
  '../model/GachaItem':await ets('model/GachaItem.ets'),
  '../model/GachaType':await ets('model/GachaType.ets'),
  '../common/Logger':logger,
  '../common/Constants':url('export const AppConstants={APP_VERSION:"test"};'),
}));
const uigf=UigfService.getInstance();
const wish=(id,extra={})=>({id,gacha_type:'400',uigf_gacha_type:'301',item_id:10000001,count:'1',rank_type:'5',time:'2026-01-02 10:00:00',name:'test',item_type:'角色',...extra});
const file=sections=>JSON.stringify({info:{version:'v4.2'},hk4e:sections});
await test('UIGF normalizes China, Europe, America and explicit ISO offsets without local timezone dependence',()=>{
  assert.equal(UigfService.normalizeTime('2026-01-02 10:00:00',8,8),'2026-01-02 10:00:00');
  assert.equal(UigfService.normalizeTime('2026-01-02 10:00:00',8,1),'2026-01-02 03:00:00');
  assert.equal(UigfService.normalizeTime('2026-01-02 01:00:00',8,-5),'2026-01-01 12:00:00');
  assert.equal(UigfService.normalizeTime('2026-01-02T02:00:00Z',-5,8),'2026-01-02 10:00:00');
  assert.equal(UigfService.normalizeTime('2026-01-02T10:00:00+08:00',0,1),'2026-01-02 03:00:00');
  assert.equal(UigfService.normalizeTime('2026-01-02T00:00:00-0500',8,8),'2026-01-02 13:00:00');
  assert.throws(()=>UigfService.normalizeTime('2025-02-29 10:00:00',8,8));
});
await test('UIGF multiple UIDs retain huge string IDs and 400 while exporting normalized type 301',async()=>{
  const big='184467440737095516151234';
  const result=await uigf.importFromText(file([
    {uid:100000001,timezone:8,list:[wish(big),wish(big)]},
    {uid:700000001,timezone:8,list:[wish(big)]},
  ]));
  assert.equal(result.ok,true);assert.equal(result.archiveCount,2);assert.equal(result.inserted,2);
  assert.equal(gachaRows[0].gachaId,big);assert.equal(gachaRows[0].gachaType,400);
  assert.equal(gachaRows[1].time,'2026-01-02 03:00:00');
  const exported=JSON.parse(await uigf.buildExportJson());
  assert.equal(exported.hk4e[0].list[0].id,big);
  assert.equal(exported.hk4e[0].list[0].gacha_type,'400');
  assert.equal(exported.hk4e[0].list[0].uigf_gacha_type,'301');
  assert.equal(exported.hk4e[1].timezone,1);
  assert.equal((await uigf.importFromText(JSON.stringify(exported))).inserted,0);
});
await test('UIGF malformed data is fully validated before any archive creation or item write',async()=>{
  const before=gachaWrites;
  const bad=['null','[]','{}','{',JSON.stringify({info:{version:'v9.0'},hk4e:[]}),
    file([{uid:100000003,timezone:8,list:[wish('12'),wish('13',{time:'2026-02-30 01:00:00'})]}]),
    file([{uid:100000003,timezone:8,list:[wish(9007199254740992)]}]),
    file([{uid:100000003,timezone:8,list:[wish('13',{rank_type:'6'})]}]),
    file([{uid:100000003,timezone:8,list:[wish('13',{count:'0'})]}]),
    file([{uid:'',timezone:8,list:[]}]),file([{uid:100000003,timezone:8,list:{}}])];
  for(const text of bad)assert.equal((await uigf.importFromText(text)).ok,false,text);
  assert.equal(gachaWrites,before);
});
await test('UIGF v4.2 permits UGC-only archives and keeps standard/UGC equal IDs separate',async()=>{
  const text=JSON.stringify({info:{version:'v4.2'},hk4e_ugc:[{uid:100000001,timezone:8,list:[{
    id:gachaRows[0].gachaId,op_gacha_type:'1000',item_id:10001,item_type:'outfit',item_name:'test UGC',
    rank_type:'5',time:'2026-01-02 10:00:00',schedule_id:101,
  }]}]});
  const result=await uigf.importFromText(text);assert.equal(result.ok,true);assert.equal(result.inserted,1);
  const exported=JSON.parse(await uigf.buildExportJson());
  assert.equal(exported.hk4e_ugc[0].list[0].schedule_id,101);
  assert.equal(exported.hk4e_ugc[0].list[0].op_gacha_type,'1000');
  assert.equal((await uigf.importFromText(text)).inserted,0);
});
const calculateUrl=await ets('model/Calculate.ets');
const {CalItem}=await import(calculateUrl);
const avatars=[{id:1,name:'test avatar',vision:'火',cultivationItems:[0,200001,200002,200013,200023,200030]}];
const weapons=[{id:11,name:'1 star',rankLevel:1,cultivationItems:[210003,220002,230002]},
  {id:12,name:'2 star',rankLevel:2,cultivationItems:[210003,220002,230002]}];
globalThis.__dataPort.avatars=avatars;globalThis.__dataPort.weapons=weapons;
const {OfflineCultivationService:offline}=await import(await ets('service/OfflineCultivationService.ets',{
  './CalculateService':url('export class CalAvatarDelta{};export class CalWeaponDelta{};'),
  '../model/Calculate':calculateUrl,
  './WikiMetaService':url('export class WikiAvatarMeta{};export class WikiWeaponMeta{};export class MetaMaterial{};export const WikiMetaService={getAvatars:async()=>globalThis.__dataPort.avatars,getWeapons:async()=>globalThis.__dataPort.weapons,getMaterials:async()=>new Map()};'),
  './CultivationTables':await ets('service/CultivationTables.ets'),
}));
const delta=(current,target,skills=[])=>({avatarId:1,levelCurrent:current,levelTarget:target,avatarPromoteLevel:current>=90?6:0,skills});
const counts=items=>new Map(items.map(item=>[item.id,item.num]));
await test('offline 1 to 90 and three talents 1 to 10 match Windows material tables',async()=>{
  const result=await offline.batchCompute([delta(1,90,[1,2,3].map(id=>({id,levelCurrent:1,levelTarget:10})))]);
  const value=counts(result.overallConsume);
  // Windows book-rounded XP cost: ceil(8,362,650 / 20,000)=419 books; talents cost 1,652,500 each.
  assert.equal(value.get(104003),419);assert.equal(value.get(202),7053500);
  assert.equal(value.get(200001),46);assert.equal(value.get(200002),168);
  assert.deepEqual([200011,200012,200013].map(id=>value.get(id)),[36,96,129]);
  assert.deepEqual([200021,200022,200023].map(id=>value.get(id)),[9,63,114]);
  assert.equal(value.get(200030),18);assert.equal(value.get(104319),3);
  assert.deepEqual([104111,104112,104113,104114].map(id=>value.get(id)),[1,9,9,6]);
  assert.equal(result.hasUserInfo,false);
});
await test('offline 90 to 95 to 100 consumes 1 then 2 Masterless Stella Fortuna',()=>{
  assert.deepEqual([...counts(offline.avatarItems(delta(90,95),avatars[0]))],[[104300,1]]);
  assert.deepEqual([...counts(offline.avatarItems(delta(95,100),avatars[0]))],[[104300,2]]);
  assert.deepEqual([...counts(offline.avatarItems(delta(90,100),avatars[0]))],[[104300,3]]);
  assert.deepEqual(offline.avatarItems(delta(100,100),avatars[0]),[]);
});
await test('offline 1 and 2 star weapons cap at level 70 and cannot overrun XP tables',async()=>{
  for(const weapon of weapons){
    const at70=counts(await offline.weaponCompute(weapon.id,1,70,0));
    const capped=counts(await offline.weaponCompute(weapon.id,1,90,0));
    assert.deepEqual(capped,at70);assert.ok(at70.get(104013)>0);
    assert.throws(()=>offline.weaponItems({levelCurrent:1,levelTarget:90,weaponPromoteLevel:0},weapon));
  }
  assert.deepEqual(offline.requiredAscensions(20,20,0),[0]);
  assert.deepEqual(offline.requiredAscensions(20,20,1),[]);
});
const db=new DatabaseSync(':memory:');
db.exec('CREATE TABLE cultivate_entries (id INTEGER PRIMARY KEY AUTOINCREMENT,project_id INTEGER,avatar_id INTEGER,name TEXT,icon TEXT,level INTEGER,target_level INTEGER,created_at INTEGER); CREATE TABLE cultivate_items (entry_id INTEGER,item_id INTEGER,name TEXT,icon TEXT,count INTEGER,finished INTEGER)');
let failure='';
const store={
  beginTransaction(){db.exec('BEGIN');},commit(){db.exec('COMMIT');},rollBack(){db.exec('ROLLBACK');},
  insertSync(table,values){return Number(db.prepare(`INSERT INTO ${table} (${Object.keys(values).join(',')}) VALUES (${Object.keys(values).map(()=>'?')})`).run(...Object.values(values)).lastInsertRowid);},
  batchInsertSync(table,rows){if(failure==='throw')throw new Error('disk failure');if(failure==='short')return -1;rows.forEach(row=>this.insertSync(table,row));return rows.length;},
};
globalThis.__dataPort.store=store;
const {CultivationRepo}=await import(await ets('data/repo/CultivationRepo.ets',{
  '@kit.ArkData':url('export const relationalStore={};'),
  '../db/RelationalStoreHelper':url('export const RelationalStoreHelper={getStore:()=>globalThis.__dataPort.store};'),
  '../../model/Calculate':calculateUrl,'../../common/Logger':logger,
}));
const material=(id,num)=>Object.assign(new CalItem(),{id,num,name:`material ${id}`});
await test('cultivation saving merges into new objects and leaves input unchanged across repeated saves',async()=>{
  const input=[material(1,10),material(1,20),material(2,5)];const before=JSON.stringify(input);
  await CultivationRepo.addEntry(1,1,'test','',1,90,input);
  await CultivationRepo.addEntry(1,1,'test','',1,90,input);
  assert.equal(JSON.stringify(input),before);
  assert.deepEqual(db.prepare('SELECT count FROM cultivate_items WHERE item_id=1').all().map(row=>row.count),[30,30]);
});
await test('cultivation write exceptions roll back entry and materials without mutating input',async()=>{
  const input=[material(3,15),material(3,25)];const before=JSON.stringify(input);
  const saved=db.prepare('SELECT COUNT(*) AS count FROM cultivate_entries').get().count;
  failure='throw';await assert.rejects(CultivationRepo.addEntry(1,1,'test','',1,90,input),/disk failure/);failure='';
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM cultivate_entries').get().count,saved);
  assert.equal(JSON.stringify(input),before);
  await assert.rejects(CultivationRepo.addEntry(1,1,'test','',1,1,[]));
});
await test('cultivation short insertion result also rolls back the new entry',async()=>{
  const saved=db.prepare('SELECT COUNT(*) AS count FROM cultivate_entries').get().count;
  failure='short';try{await assert.rejects(CultivationRepo.addEntry(1,1,'test','',1,90,[material(9,1)]));}finally{failure='';}
  assert.equal(db.prepare('SELECT COUNT(*) AS count FROM cultivate_entries').get().count,saved);
});
const characterUrl=await ets('model/CharacterData.ets');
const {Reliquary,RelicProperty}=await import(characterUrl);
const {ReliquaryScore}=await import(await ets('common/ReliquaryScore.ets',{'../model/CharacterData':characterUrl}));
await test('Kokomi alone disables crit scoring; Ayaka retains both crit contributions',()=>{
  const relic=new Reliquary();
  relic.subProperties=[Object.assign(new RelicProperty(),{propertyType:'FIGHT_PROP_CRITICAL',value:'10.5%'}),
    Object.assign(new RelicProperty(),{propertyType:'FIGHT_PROP_CRITICAL_HURT',value:'21.0%'})];
  assert.equal(ReliquaryScore.isCritEffective(10000054),false);
  assert.equal(ReliquaryScore.isCritEffective(10000002),true);
  assert.equal(ReliquaryScore.doubleCritScore(relic,ReliquaryScore.isCritEffective(10000054)),0);
  assert.equal(ReliquaryScore.doubleCritScore(relic,ReliquaryScore.isCritEffective(10000002)),42);
  assert.equal(ReliquaryScore.calculate(relic.subProperties,[],'NONE',ReliquaryScore.isCritEffective(10000002)),42);
});
