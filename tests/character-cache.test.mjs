// Run with Node.js 24+: node tests/character-cache.test.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
const root=new URL('../entry/src/main/ets/',import.meta.url);
const url=code=>`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
async function ets(path,imports={}){
  const source=(await readFile(new URL(path,root),'utf8')).replace(/from\s+'([^']+)'/g,(match,name)=>{
    assert.ok(imports[name],`Unmocked dependency ${name}`);return `from '${imports[name]}'`;
  });
  return url(stripTypeScriptTypes(source,{mode:'transform'}));
}
const prefs=new Map();
globalThis.__characterCacheTest={prefs};
const modelUrl=await ets('model/CharacterData.ets');
const {CharacterListItem,CharacterDetail}=await import(modelUrl);
const {CharacterService}=await import(await ets('service/CharacterService.ets',{
  '../data/network/ApiClient':url('export const ApiClient={};'),
  '../model/ApiResponse':url('export class ApiResponse {}'),
  '../data/network/HoyolabClient':url('export const HoyolabClient={};'),
  '../data/network/DsSigner':url('export const DsSigner={};'),
  '../data/network/RiskVerifier':url('export const RiskVerifier={};export class RiskControlError extends Error {}'),
  '../model/CharacterData':modelUrl,
  './WikiMetaService':url("export const WikiMetaService={iconOfAvatar:id=>`UI_AvatarIcon_${id}`,cleanText:text=>text};"),
  './UserService':url('export const UserService={};'),
  '../common/Constants':url("export const RegionUtil={regionOfUid:uid=>'cn_gf01'};export const AppConstants={};"),
  '../common/HoyolabEndpoints':url("export const HoyolabEndpoints={gameRecordUrl:path=>path,gameRecordSalt:()=>''};"),
  '../common/Logger':url('export const Logger={info(){},warn(){}};'),
  '../data/prefs/PreferencesStore':url('export const PreferencesStore={getString:(key,def)=>globalThis.__characterCacheTest.prefs.get(key)??def,setString:(key,value)=>globalThis.__characterCacheTest.prefs.set(key,value)};'),
}));
const service=CharacterService.getInstance();
let response;
service.postJson=async()=>{if(response instanceof Error)throw response;return response;};
const ok=list=>({success:true,retcode:0,data:{list}});
const detail=(id,level=80)=>({base:{id,level,name:`character ${id}`},weapon:{id:10,level:90}});
await test('successful list snapshots persist per UID and recreate model instances',async()=>{
  response=ok([{id:1,name:'first',level:80}]);await service.fetchList('100000001');
  response=ok([{id:2,name:'second',level:90}]);await service.fetchList('100000002');
  const first=service.getCachedList('100000001');
  assert.equal(first[0].id,1);assert.ok(first[0] instanceof CharacterListItem);
  assert.equal(service.getCachedList('100000002')[0].id,2);
  assert.deepEqual(service.getCachedList(''),[]);
});
await test('successful detail batches merge per ID and keep other UIDs isolated',async()=>{
  response=ok([detail(1)]);await service.fetchDetail('100000001',[1]);
  response=ok([detail(2)]);await service.fetchDetail('100000001',[2]);
  response=ok([detail(1,90)]);await service.fetchDetail('100000001',[1]);
  response=ok([detail(3)]);await service.fetchDetail('100000002',[3]);
  const saved=service.getCachedDetails('100000001');
  assert.deepEqual(saved.map(item=>[item.id,item.level]),[[1,90],[2,80]]);
  assert.ok(saved[0] instanceof CharacterDetail);
  assert.deepEqual(service.getCachedDetails('100000002').map(item=>item.id),[3]);
});
await test('remote errors and malformed successful responses preserve prior snapshots',async()=>{
  const before=prefs.get('character.list.100000001');
  response=new Error('offline');await assert.rejects(service.fetchList('100000001'),/offline/);
  response={success:true,retcode:0,data:{}};await assert.rejects(service.fetchList('100000001'),/响应不完整/);
  response=ok([{id:0}]);await assert.rejects(service.fetchList('100000001'),/无效条目/);
  assert.equal(prefs.get('character.list.100000001'),before);
  assert.equal(service.getCachedDetails('100000001').length,2);
});
await test('corrupt cache is safe and successful later fetch repairs it',async()=>{
  prefs.set('character.list.100000003','{invalid');assert.deepEqual(service.getCachedList('100000003'),[]);
  prefs.set('character.details.100000003','[null]');assert.deepEqual(service.getCachedDetails('100000003'),[]);
  prefs.set('character.details.100000003',JSON.stringify([{base:{id:2},relics:[null]}]));
  assert.deepEqual(service.getCachedDetails('100000003'),[]);
  response=ok([detail(3)]);await service.fetchDetail('100000003',[3]);
  assert.deepEqual(service.getCachedDetails('100000003').map(item=>item.id),[3]);
});
await test('promotion is unknown without an explicit API field, never inferred from level',async()=>{
  response=ok([detail(1),{...detail(2),base:{id:2,level:80,promote_level:6}},
    {...detail(3),base:{id:3,level:20,avatar_promote_level:'1'}}]);
  const values=await service.fetchDetail('100000004',[1,2,3]);
  assert.deepEqual(values.map(value=>value.promoteLevel),[-1,6,1]);
});
