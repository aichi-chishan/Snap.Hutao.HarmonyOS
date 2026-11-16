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
const DEFAULT_UIDS=['100000001','100000002','100000003','100000004'];
const state={prefs,reads:[],writes:[],requests:[],risks:[],revision:0,reply:null,sign:null,risk:null,user:null};
globalThis.__characterCacheTest=state;
const modelUrl=await ets('model/CharacterData.ets');
const constantsUrl=await ets('common/Constants.ets');
const rolesUrl=await ets('model/UserGameRole.ets');
const userUrl=await ets('model/User.ets',{'./UserGameRole':rolesUrl});
const responseUrl=await ets('model/ApiResponse.ets',{'../common/Constants':constantsUrl});
const {CharacterListItem,CharacterDetail}=await import(modelUrl);
const {User}=await import(userUrl);
const {UserGameRole}=await import(rolesUrl);
const {ApiResponse}=await import(responseUrl);
const {CharacterService}=await import(await ets('service/CharacterService.ets',{
  '../data/network/ApiClient':url(`const state=globalThis.__characterCacheTest;
    export const ApiClient={getInstance:()=>({async postJson(path,body,headers) {
      const request={path,body:JSON.parse(body),headers:{...headers}};
      state.requests.push(request); return state.reply(request);
    }})};`),
  '../model/ApiResponse':responseUrl,
  '../data/network/HoyolabClient':url('export const HoyolabClient={getBaseHeaders:()=>({}),merge:(a,b)=>({...a,...b})};'),
  '../data/network/DsSigner':url(`const state=globalThis.__characterCacheTest;
    export const DsSigner={nowTimestamp:()=>1,randomNumber:()=> '123456',signGen2:async()=>state.sign()};`),
  '../data/network/RiskVerifier':url(`const state=globalThis.__characterCacheTest;
    export const RiskVerifier={async tryResolveRisk(response,cookie,path) {
      state.risks.push({path}); return state.risk();
    }};`),
  '../model/CharacterData':modelUrl,
  '../model/User':userUrl,
  '../model/UserGameRole':rolesUrl,
  '../model/PromoteState':await ets('model/PromoteState.ets'),
  './WikiMetaService':url("export const WikiMetaService={iconOfAvatar:id=>`UI_AvatarIcon_${id}`,cleanText:text=>text};"),
  './UserService':url(`const state=globalThis.__characterCacheTest;
    export const UserService={getInstance:()=>({getCurrentUser:()=>state.user,sessionRevision:()=>state.revision,
      ensureDeviceFingerprintPublic:async()=>{}, completeTokenChainPublic:async()=>{ throw Error('unexpected fixture credential refresh'); }})};`),
  '../common/Constants':constantsUrl,
  '../common/HoyolabEndpoints':url("export const HoyolabEndpoints={gameRecordUrl:path=>path,gameRecordSalt:()=>''};"),
  '../common/Logger':url('export const Logger={info(){},warn(){}};'),
  '../data/prefs/PreferencesStore':url(`const state=globalThis.__characterCacheTest;
    export const PreferencesStore={getString:(key,def)=>{state.reads.push(key);return state.prefs.get(key)??def;},
      setString:(key,value)=>{state.writes.push(key);state.prefs.set(key,value);}};`),
}));
const service=CharacterService.getInstance();
let response;
const ok=list=>ApiResponse.fromJson(JSON.stringify({retcode:0,data:{list}}));
const detail=(id,level=80)=>({base:{id,level,name:`character ${id}`},weapon:{id:10,level:90}});
const deferred=()=>{let resolve;const promise=new Promise(done=>{resolve=done;});return{promise,resolve};};
const flush=async()=>{for(let i=0;i<30;i++)await Promise.resolve();};
const uid=DEFAULT_UIDS[0];
const detailKey=`character.details.${uid}`;
const allIds=Array.from({length:45},(_,index)=>10000001+index);

function account(id, uids=DEFAULT_UIDS){
  const user=new User();
  user.id=id;
  user.applyCookie(`stuid=${id}; stoken=fixture-stoken-${id}; account_id=${id}; cookie_token=fixture-cookie-${id}; ltuid=${id}; ltoken=fixture-ltoken-${id}`);
  user.roles=uids.map(value=>UserGameRole.of(value,'cn_gf01','fixture role',60));
  return user;
}

function resetTransport(){
  state.revision++;
  state.user=account(1);
  state.reads=[];
  state.writes=[];
  state.requests=[];
  state.risks=[];
  state.reply=async()=>{if(response instanceof Error)throw response;return response;};
  state.sign=async()=> 'fixture-ds';
  state.risk=async()=> 'fixture-challenge';
}
resetTransport();
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
  const priorDetails=prefs.get(detailKey);
  response=new Error('offline');await assert.rejects(service.fetchList('100000001'),/offline/);
  response=ApiResponse.fromJson('{"retcode":0,"data":{}}');await assert.rejects(service.fetchList('100000001'),/响应不完整/);
  response=ok([{id:0}]);await assert.rejects(service.fetchList('100000001'),/无效条目/);
  response=ok([detail(2,90)]);await assert.rejects(service.fetchDetail(uid,[1]),/无效条目/);
  assert.equal(prefs.get('character.list.100000001'),before);
  assert.equal(prefs.get(detailKey),priorDetails);
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

await test('45 selected-first details send 3 HTTP batches and reduce persisted reads and writes from 3 to 1',async()=>{
  const ordered=[allIds[44],...allIds.slice(0,44)];
  const rawOld={...detail(10000199),future_detail:{known_only_to_next_version:true}};
  const serve=async({body})=>ok(body.character_ids.map(id=>({...detail(id,90),future_rolls:[7,8]})));
  const measured=new CharacterService();
  const decoded=new WeakSet();
  let parsedCachedEntries=0;
  const readCached=measured.readCached.bind(measured);
  const parseDetail=measured.parseDetail.bind(measured);
  measured.readCached=(key,isDetail)=>{
    const values=readCached(key,isDetail);
    if(isDetail)for(const value of values)decoded.add(value);
    return values;
  };
  measured.parseDetail=value=>{
    if(decoded.has(value))parsedCachedEntries++;
    return parseDetail(value);
  };
  const countCache=()=>[state.reads.filter(key=>key===detailKey).length,
    state.writes.filter(key=>key===detailKey).length,parsedCachedEntries];
  resetTransport();
  prefs.set(detailKey,JSON.stringify([rawOld]));
  state.reply=serve;
  for(let i=0;i<ordered.length;i+=20)await measured.fetchDetail(uid,ordered.slice(i,i+20));
  assert.equal(state.requests.length,3);
  assert.deepEqual(countCache(),[3,3,63]);

  resetTransport();
  parsedCachedEntries=0;
  prefs.set(detailKey,JSON.stringify([rawOld]));
  state.reply=serve;
  const publications=[];
  await measured.fetchDetailBatches(uid,ordered,batch=>{
    publications.push(batch.map(item=>item.id));
    assert.equal(state.writes.filter(key=>key===detailKey).length,0);
  },()=>true);
  assert.deepEqual(state.requests.map(request=>request.body.character_ids.length),[20,20,5]);
  assert.deepEqual(publications.flat(),ordered);
  assert.equal(state.requests[0].body.character_ids[0],ordered[0]);
  assert.ok(state.requests.every(request=>request.body.role_id===uid));
  assert.deepEqual(countCache(),[1,1,1]);
  const saved=JSON.parse(prefs.get(detailKey));
  assert.equal(saved.length,46);
  assert.deepEqual(saved[0],rawOld);
  assert.deepEqual(saved.at(-1).future_rolls,[7,8]);
});

await test('a later failed batch keeps its published prefix and writes that prefix exactly once',async()=>{
  resetTransport();
  prefs.set(detailKey,JSON.stringify([detail(allIds[20],60)]));
  state.reply=async({body})=>state.requests.length===2
    ? ApiResponse.fail(-42,'fixture batch failed') : ok(body.character_ids.map(id=>detail(id,90)));
  const publications=[];
  await assert.rejects(service.fetchDetailBatches(uid,allIds,batch=>publications.push(batch),()=>true),/fixture batch failed/);
  assert.equal(state.requests.length,2);
  assert.deepEqual(publications.map(batch=>batch.length),[20]);
  assert.deepEqual([state.reads.length,state.writes.length],[1,1]);
  const values=service.getCachedDetails(uid);
  assert.equal(values.length,21);
  assert.equal(values.find(item=>item.id===allIds[20]).level,60);
  assert.equal(values.find(item=>item.id===allIds[0]).level,90);
});

await test('a newer standalone response keeps its raw entry when an older bulk request commits',async()=>{
  resetTransport();
  prefs.set(detailKey,'[]');
  const gate=deferred();
  const first=allIds[0];
  const last=allIds[20];
  state.reply=async({body})=>{
    if(body.character_ids[0]===last)return gate.promise;
    if(body.character_ids.length===1)return ok([{...detail(first,90),future_standalone:[3,4]}]);
    return ok(body.character_ids.map(id=>detail(id,70)));
  };
  const publications=[];
  const bulk=service.fetchDetailBatches(uid,allIds.slice(0,21),batch=>publications.push(batch),()=>true);
  await flush();
  assert.equal(publications.length,1);
  assert.equal(publications[0][0].level,70);
  const [fresh]=await service.fetchDetail(uid,[first]);
  assert.equal(fresh.level,90);
  gate.resolve(ok([detail(last,80)]));
  await bulk;
  assert.deepEqual([state.requests.length,state.reads.length,state.writes.length],[3,2,2]);
  const saved=JSON.parse(prefs.get(detailKey));
  assert.equal(saved.length,21);
  assert.equal(saved.find(item=>item.base.id===first).base.level,90);
  assert.deepEqual(saved.find(item=>item.base.id===first).future_standalone,[3,4]);
  assert.equal(saved.find(item=>item.base.id===last).base.level,80);
});

await test('canceling or replacing the session during later HTTP discards the pending cache and publication',async()=>{
  for(const stop of ['caller','account']){
    resetTransport();
    const original=JSON.stringify([detail(10000199)]);
    prefs.set(detailKey,original);
    let active=true;
    const gate=deferred();
    state.reply=async({body})=>state.requests.length===2 ? gate.promise : ok(body.character_ids.map(id=>detail(id)));
    const publications=[];
    const pending=service.fetchDetailBatches(uid,allIds,batch=>publications.push(batch),()=>active);
    const rejected=assert.rejects(pending,/已切换/);
    await flush();
    assert.equal(state.requests.length,2);
    if(stop==='caller')active=false;
    else {state.user=account(2);state.revision++;}
    gate.resolve(ok(state.requests[1].body.character_ids.map(id=>detail(id))));
    await rejected;
    assert.equal(publications.length,1);
    assert.equal(state.requests.length,2);
    assert.equal(state.writes.length,0);
    assert.equal(prefs.get(detailKey),original);
  }
});

await test('invalidated signing and unbound UIDs never dispatch character requests',async()=>{
  resetTransport();
  await assert.rejects(service.fetchList('100000009'),/未绑定/);
  await assert.rejects(service.fetchDetail('100000009',[allIds[0]]),/未绑定/);
  const sign=deferred();
  state.sign=()=>sign.promise;
  const pending=service.fetchList(uid);
  const rejected=assert.rejects(pending,/已切换/);
  await flush();
  state.revision++;
  sign.resolve('fixture-ds');
  await rejected;
  assert.equal(state.requests.length,0);
  assert.equal(state.writes.length,0);
});

await test('stale 1034 never opens verification and a valid owner replays once with the challenge',async()=>{
  resetTransport();
  const responseGate=deferred();
  state.reply=()=>responseGate.promise;
  const pending=service.fetchDetail(uid,[allIds[0]]);
  const rejected=assert.rejects(pending,/已切换/);
  await flush();
  state.user=account(2);
  state.revision++;
  responseGate.resolve(ApiResponse.fail(1034,'fixture risk'));
  await rejected;
  assert.equal(state.risks.length,0);
  assert.equal(state.writes.length,0);

  resetTransport();
  state.reply=async()=>state.requests.length===1
    ? ApiResponse.fail(1034,'fixture risk') : ok([detail(allIds[0])]);
  assert.equal((await service.fetchDetail(uid,[allIds[0]])).length,1);
  assert.equal(state.risks.length,1);
  assert.equal(state.requests.length,2);
  assert.equal(state.requests[1].headers['x-rpc-challenge'],'fixture-challenge');
});

await test('ownership changes during rate-limit backoff prevent the next attempt',async t=>{
  resetTransport();
  t.mock.timers.enable({apis:['setTimeout']});
  state.reply=async()=>ApiResponse.fail(-502,'fixture limit');
  const pending=service.fetchDetail(uid,[allIds[0]]);
  const rejected=assert.rejects(pending,/已切换/);
  await flush();
  assert.equal(state.requests.length,1);
  state.revision++;
  t.mock.timers.tick(2000);
  await rejected;
  assert.equal(state.requests.length,1);
  assert.equal(state.writes.length,0);
});
