// Production offline rules/VM and page lifecycle; doubles are only metadata, navigation and ArkUI.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const os = require('node:os');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const pageSource = fs.readFileSync(path.join(root, 'pages/WishHistoryPage.ets'), 'utf8');
const DAY = 86400000;
const NOW = Date.parse('2026-08-20T12:00:00+08:00');
const plain = value => JSON.parse(JSON.stringify(value));
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a;reject=b; });return { promise,resolve,reject }; };
const flush = async () => { for(let i=0;i<50;i++)await Promise.resolve(); };
function harness() {
  const modules=new Map();
  const state={events:[],avatars:[],weapons:[],reads:[],routes:[],timers:new Map(),cleared:[],nextTimer:0};
  const metadata={
    GachaEventMeta:class {},WikiAvatarMeta:class {},WikiWeaponMeta:class {},
    WikiMetaService:{getGachaEvents:async()=>{state.reads.push('events');return state.events;},
      getAvatars:async()=>{state.reads.push('avatars');return state.avatars;},
      getWeapons:async()=>{state.reads.push('weapons');return state.weapons;}}
  };
  const globals={Observed:v=>v,Entry:v=>v,Component:v=>v,Prop:()=>{},State:()=>{},StorageProp:()=>()=>{},
    setInterval:callback=>{const id=++state.nextTimer;state.timers.set(id,callback);return id;},
    clearInterval:id=>{state.cleared.push(id);state.timers.delete(id);}};
  function load(name) {
    if(modules.has(name))return modules.get(name);
    if(name==='service/WikiMetaService')return metadata;
    if(name==='@kit.ArkUI')return {router:{pushUrl:async args=>{state.routes.push(args);}}};
    if(name==='components/SimpleDataSource')return {SimpleDataSource:class {constructor(items){this.items=items;this.reloads=0;}notifyDataReload(items){this.items=items;this.reloads++;}}};
    if(name.startsWith('components/'))return {};
    let text=fs.readFileSync(path.join(root,name+'.ets'),'utf8');
    if(name==='pages/WishHistoryPage')text=text.slice(0,text.indexOf('  @Builder'))+'}';
    text=text.replace('export struct WishHistoryPage','export class WishHistoryPage');
    const result=ts.transpileModule(text,{reportDiagnostics:true,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}});
    assert.equal(result.diagnostics.length,0,name);
    const m={exports:{}};vm.runInNewContext(`(function(require,module,exports){${result.outputText}\n})`,globals)(id=>load(id.startsWith('@')?id:path.posix.normalize(path.posix.join(path.posix.dirname(name),id))),m,m.exports);
    modules.set(name,m.exports);return m.exports;
  }
  const model=load('model/WishHistory');
  const service=load('service/WishHistoryService').WishHistoryService;
  const Model=load('viewmodel/WishHistoryViewModel').WishHistoryViewModel;
  return {state,model,service,Model,page:()=>new (load('pages/WishHistoryPage').WishHistoryPage)()};
}
function event(extra={}) { return {name:'测试祈愿',version:'6.0',order:1,type:301,from:NOW-20*DAY,to:NOW-10*DAY,upOrange:[10000022],upPurple:[],...extra}; }
function meta(id,name='已知物品') { return {id,name,icon:`icon_${id}`}; }
function strictTypes() {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hutao-wish-history-'));
  const names=['model/WishHistory','service/WishHistoryService','viewmodel/WishHistoryViewModel'];
  for(const name of names){const file=path.join(dir,name+'.ts');fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,fs.readFileSync(path.join(root,name+'.ets'),'utf8'));}
  fs.writeFileSync(path.join(dir,'service/WikiMetaService.ts'),`export class GachaEventMeta {name='';version='';order=0;type=0;from=0;to=0;upOrange:number[]=[];upPurple:number[]=[];}\nexport class WikiAvatarMeta {id=0;name='';icon='';}\nexport class WikiWeaponMeta {id=0;name='';icon='';}\nexport class WikiMetaService {static async getGachaEvents():Promise<GachaEventMeta[]>{return [];}static async getAvatars():Promise<WikiAvatarMeta[]>{return [];}static async getWeapons():Promise<WikiWeaponMeta[]>{return [];}}`);
  fs.writeFileSync(path.join(dir,'globals.d.ts'),'declare function Observed<T extends new (...args: never[]) => object>(value:T):T;');
  const program=ts.createProgram([...names.map(name=>path.join(dir,name+'.ts')),path.join(dir,'globals.d.ts')],{strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,experimentalDecorators:true,skipLibCheck:true});
  const errors=ts.getPreEmitDiagnostics(program).filter(d=>d.category===ts.DiagnosticCategory.Error);
  assert.equal(errors.length,0,ts.formatDiagnosticsWithColorAndContext(errors,{getCurrentDirectory:()=>dir,getCanonicalFileName:x=>x,getNewLine:()=> '\n'}));
}
(async()=>{
  await test('pinned Windows exclusions and all four rarity/kind groups',()=>{
    const {service:S}=harness();
    const excludedA=[10000003,10000016,10000041,10000042,10000035,10000069,10000079,10000109,10000006,10000021,10000015,10000062];
    const excludedW=[11501,11502,12501,12502,13502,13505,14501,14502,15501,15502,15515,15518];
    const r=S.build([event({upOrange:[...excludedA,...excludedW,10000022,11509],upPurple:[...excludedA,10000014,11401]})],[],[],NOW);
    assert.deepEqual(plain(r.items.map(x=>[x.id,x.category])),[[11401,3],[11509,2],[10000014,1],[10000022,0]]);
    assert.equal(r.unknownItemCount,4);
    assert.equal(S.build([event({upOrange:[],upPurple:[11501]})],[],[],NOW).items.length,1,'weapon exclusion applies to orange list only, matching Windows');
  });
  await test('future, invalid, reversed and unsupported IDs do not fabricate histories',()=>{
    const {service:S}=harness();
    const invalid=[event({from:0}),event({from:NaN}),event({to:Infinity}),event({to:NOW-30*DAY}),event({from:NOW,to:NOW}),event({to:8640000000000001})];
    const r=S.build([...invalid,event({from:NOW+1,to:NOW+DAY}),event({upOrange:[0,NaN,Infinity,5,999999,10000022.5,10000022,19999999,99999]})],[],[],NOW);
    assert.equal(r.ignoredInvalidEvents,6);assert.equal(r.ignoredFutureEvents,1);assert.equal(r.ignoredItemIds,6);
    assert.equal(r.items.length,3);assert.equal(r.items.find(x=>x.id===19999999).name,'#19999999');assert.equal(r.items.find(x=>x.id===99999).name,'#99999');
    for(const now of [0,NaN,Infinity,-1])assert.throws(()=>S.build([],[],[],now),/当前时间/);
  });
  await test('date boundaries use event END and explicitly distinguish ended from current',()=>{
    const {service:S}=harness();const from=NOW,to=NOW+3*DAY;
    assert.equal(S.build([event({from,to})],[],[],from-1).items.length,0);
    const item=S.build([event({from,to})],[],[],from).items[0];assert.equal(item.lastTime,to);
    assert.equal(S.ongoing(item,from),true);assert.equal(S.countdown(item,from),'正在 UP · 剩余 3 天');
    assert.equal(S.countdown(item,to-1),'正在 UP · 剩余不足 1 天');assert.equal(S.ongoing(item,to),false);
    assert.equal(S.countdown(item,to),'上次 UP 结束不足 1 天');assert.equal(S.countdown(item,to+DAY),'距上次 UP 结束 1 天');
    assert.equal(S.dateText(Date.parse('2026-08-19T16:00:00Z')),'2026-08-20');assert.equal(S.dateText(NaN),'--');
  });
  await test('overlapping active pools count down to an active end without predicting a rerun',()=>{
    const {service:S}=harness();
    const r=S.build([event({from:NOW-20*DAY,to:NOW+5*DAY}),event({from:NOW-10*DAY,to:NOW-DAY})],[],[],NOW);
    const item=r.items[0];assert.equal(item.lastTime,NOW-DAY);assert.equal(S.ongoing(item,NOW),true);
    assert.equal(S.countdown(item,NOW),'正在 UP · 剩余 5 天');assert.equal(S.dateText(8640000000000000),'--');
  });
  await test('dual simultaneous pools count once but preserve every distinct pool detail',()=>{
    const {service:S}=harness();const a=event({name:'一池',type:301,upPurple:[10000014,10000014]});const b=event({name:'二池',type:400,upPurple:[10000014]});
    const older=event({from:NOW-50*DAY,to:NOW-40*DAY,upPurple:[10000014]});
    const r=S.build([older,b,a,a],[],[],NOW);const item=r.items.find(x=>x.id===10000014);
    assert.equal(item.histories.length,2);assert.equal(item.histories[0].pools.length,2);
    assert.deepEqual(plain(item.histories[0].pools.map(x=>x.type)),[301,400]);assert.equal(item.lastTime,a.to);
    const different=S.build([a,event({...a,to:a.to+1})],[],[],NOW);assert.equal(different.items.find(x=>x.id===10000014).histories.length,2);
  });
  await test('oldest-last-UP ordering and ties are stable and input arrays are untouched',()=>{
    const {service:S}=harness();const source=[event({upOrange:[10000046,10000022]}),event({from:NOW-50*DAY,to:NOW-40*DAY,upOrange:[10000029]})];
    const before=JSON.stringify(source);const one=S.build(source,[],[],NOW);const two=S.build(source.slice().reverse(),[],[],NOW);
    assert.deepEqual(plain(one.items.map(x=>x.id)),[10000029,10000022,10000046]);assert.deepEqual(plain(one),plain(two));assert.equal(JSON.stringify(source),before);
  });
  await test('names/icons, unknown IDs, category/search and pool labels remain explicit',()=>{
    const {service:S}=harness();const r=S.build([event({upOrange:[10000022,10000029,11509],upPurple:[11401]})],[meta(10000022,'Venti'),meta(10000029,'')],[meta(11509,'雾切之回光')],NOW);
    assert.equal(r.items.find(x=>x.id===10000022).icon,'icon_10000022');assert.equal(r.items.find(x=>x.id===10000029).name,'#10000029');
    assert.equal(S.filter(r.items,0,' vEnTi ')[0].id,10000022);assert.equal(S.filter(r.items,0,'#10000029')[0].id,10000029);
    assert.equal(S.filter(r.items,2,'雾切')[0].id,11509);assert.equal(S.filter(r.items,0,'雾切').length,0);
    assert.equal(S.poolTypeText(500),'集录祈愿');assert.equal(S.poolTypeText(999),'祈愿类型 999');assert.match(S.periodText({version:'',order:3}),/版本未知.*第 3 期/);
  });
  await test('real bundled metadata uses the production read path and independent occurrence oracle',async()=>{
    const {state,service:S}=harness();const directory=path.resolve('entry/src/main/resources/rawfile/metadata');
    const raw=JSON.parse(fs.readFileSync(path.join(directory,'GachaEvent.json'),'utf8'));
    state.events=raw.map(x=>event({name:x.Name,version:x.Version,order:x.Order,type:x.Type,from:Date.parse(x.From),to:Date.parse(x.To),upOrange:x.UpOrangeList,upPurple:x.UpPurpleList}));
    state.avatars=JSON.parse(fs.readFileSync(path.join(directory,'avatar_meta.json'),'utf8'));state.weapons=JSON.parse(fs.readFileSync(path.join(directory,'weapon_meta.json'),'utf8'));
    const result=await S.load(NOW);assert.deepEqual(state.reads,['events','avatars','weapons']);assert.equal(result.sourceEventCount,292);
    assert(result.items.length>180);assert(result.items.some(x=>x.name==='温迪'));assert(result.items.some(x=>S.ongoing(x,NOW)));
    for(const item of result.items){
      const expected=new Set(state.events.filter(e=>e.from<=NOW && (e.upOrange.includes(item.id)||e.upPurple.includes(item.id))).map(e=>`${e.from}_${e.to}`));
      assert.equal(item.histories.length,expected.size,`independent dedup: ${item.id}`);
      assert.equal(item.lastTime,item.histories[0].to);assert(item.histories.every(x=>x.from<=NOW));
    }
    assert(result.items.some(x=>x.histories.some(h=>h.pools.length===2)),'dual pools represented');
    const globalPoolCount=result.items.reduce((n,x)=>n+x.histories.reduce((m,h)=>m+h.pools.length,0),0);assert(globalPoolCount>result.items.reduce((n,x)=>n+x.histories.length,0));
  });
  await test('view-model ignores late older loads and keeps a newer request loading',async()=>{
    const {service:S,Model,model}=harness();const pending=[];S.load=()=>{const gate=deferred();pending.push(gate);return gate.promise;};
    const target=new Model();assert.equal(await target.load(),false);target.activate();const a=target.load(),b=target.load();
    const old=new model.WishHistorySnapshot();old.metadataAvailable=true;old.asOf=1;pending[0].resolve(old);assert.equal(await a,false);assert.equal(target.loading,true);
    const fresh=new model.WishHistorySnapshot();fresh.metadataAvailable=true;fresh.asOf=2;pending[1].resolve(fresh);assert.equal(await b,true);assert.equal(target.snapshot.asOf,2);assert.equal(target.loading,false);
    const c=target.load(),d=target.load();pending[3].resolve(fresh);await d;pending[2].reject(Error('late failure'));assert.equal(await c,false);assert.equal(target.message,'');assert.equal(target.snapshot.asOf,2);
  });
  await test('detach/remount fences result and finalizer, filter changes apply to the arriving snapshot',async()=>{
    const {service:S,Model}=harness();const first=deferred(),second=deferred();let calls=0;S.load=()=>++calls===1?first.promise:second.promise;
    const target=new Model();target.activate();const a=target.load();target.invalidate();target.activate();const b=target.load();
    first.resolve(S.build([event()],[],[],NOW));assert.equal(await a,false);assert.equal(target.loading,true);
    target.setFilter(1,'#10000014');second.resolve(S.build([event({upPurple:[10000014]})],[],[],NOW));assert.equal(await b,true);
    assert.equal(target.items.length,1);assert.equal(target.items[0].id,10000014);target.select(10000014);assert.equal(target.selected().id,10000014);target.setFilter(0,'');assert.equal(target.selected(),undefined);
    target.invalidate();assert.equal(await target.load(),false);
  });
  await test('empty metadata, rejected reads and retry have distinct honest states',async()=>{
    const {service:S,Model}=harness();const target=new Model();target.activate();await target.load(NOW);assert.equal(target.loaded,true);assert.equal(target.snapshot.metadataAvailable,false);assert.match(target.message,/为空或无法读取/);
    S.load=async()=>{throw Error('private IO detail');};await target.load(NOW);assert.match(target.message,/无法读取本地/);assert(!target.message.includes('private'));assert.equal(target.items.length,0);assert.equal(target.loading,false);
    S.load=async()=>S.build([event({from:NOW+1,to:NOW+DAY})],[],[],NOW);await target.load(NOW);assert.equal(target.message,'');assert.equal(target.snapshot.ignoredFutureEvents,1);assert.equal(target.items.length,0);
  });
  await test('page timers, repeated attachment and stale detached callbacks are owned',async()=>{
    const {service:S,state,page}=harness();const pending=[];S.load=()=>{const gate=deferred();pending.push(gate);return gate.promise;};const target=page();
    target.aboutToAppear();target.onPageShow();assert.equal(pending.length,1);assert.equal(state.timers.size,1);state.timers.values().next().value();assert.equal(pending.length,1,'timer does not interrupt loading');
    target.onPageHide();assert.equal(state.timers.size,0);target.onPageShow();assert.equal(pending.length,2);const before=target.source.reloads;
    pending[0].resolve(S.build([event()],[],[],NOW));await flush();assert.equal(target.source.reloads,before);assert.equal(target.vm.loading,true);
    pending[1].resolve(S.build([event()],[],[],NOW));await flush();assert.equal(target.source.reloads,before+1);state.timers.values().next().value();assert.equal(pending.length,3);
    target.aboutToDisappear();pending[2].reject(Error('late'));await flush();assert.equal(target.source.reloads,before+1);assert.equal(state.timers.size,0);
  });
  await test('page Wiki navigation carries only verified known item identity',async()=>{
    const {service:S,state,page}=harness();const target=page();S.load=async()=>S.build([event({upOrange:[10000022,10000029,11509]})],[meta(10000022)],[meta(11509)],NOW);
    target.aboutToAppear();await flush();target.select(target.vm.items.find(x=>x.id===10000022));await target.openWiki();assert.deepEqual(plain(state.routes[0]),{url:'pages/WikiAvatarPage',params:{itemId:10000022}});
    target.select(target.vm.items.find(x=>x.id===10000029));await target.openWiki();assert.equal(state.routes.length,1);
    target.filter(2,'');target.select(target.vm.items[0]);await target.openWiki();assert.equal(state.routes[1].url,'pages/WikiWeaponPage');assert.equal(state.routes[1].params.itemId,11509);
    target.aboutToDisappear();await target.openWiki();assert.equal(state.routes.length,2);
  });
  await test('pure production model/service/VM pass strict TypeScript with typed metadata boundary',strictTypes);
  await test('page structure keeps API24-native lazy responsive/offline controls',()=>{
    assert.match(pageSource,/Number\(area\.width\) >= 840/);assert.equal((pageSource.match(/LazyForEach\(/g)||[]).length,2);
    assert.doesNotMatch(pageSource,/isLoggedIn|currentUid|GachaRepo|HutaoCloud|\.fontColor\(Color\.|#[0-9a-fA-F]{6}/);
    assert.match(pageSource,/remoteFallback: false/);assert.match(pageSource,/\.height\(44\)/);assert.match(pageSource,/\.hoverEffect\(HoverEffect.Highlight\)/);
    assert.match(pageSource,/不预测未来复刻/);assert.match(pageSource,/item\.known/);
    for(const name of ['WishHistoryService','WishHistoryViewModel'])assert.doesNotMatch(fs.readFileSync(path.join(root,name.includes('ViewModel')?'viewmodel':'service',name+'.ets'),'utf8'),/UserService|GachaRepo|HutaoCloud|http\.create/);
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
