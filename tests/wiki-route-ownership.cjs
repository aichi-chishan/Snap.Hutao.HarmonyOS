// Execute the production Wiki route/lifecycle/load methods with metadata and ArkUI boundaries doubled.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const test=require('node:test');
const ts=require(process.env.TYPESCRIPT_PATH||'../ci/node_modules/typescript');
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return{promise,resolve,reject};};
const flush=async()=>{for(let i=0;i<50;i++)await Promise.resolve();};
function harness(kind) {
  const source=fs.readFileSync(`entry/src/main/ets/pages/Wiki${kind}Page.ets`,'utf8');
  const imports=Array.from(source.matchAll(/^import[\s\S]*?;\n/gm),m=>m[0]).join('');
  const first=source.indexOf(`export struct Wiki${kind}Page`),last=source.indexOf('  @Builder',first);
  const body=source.slice(first,last).replace(`export struct Wiki${kind}Page`,`export class Wiki${kind}Page`)+'}';
  const ids=kind==='Avatar'?[10000022,10000046]:[11509,13509];
  const items=ids.map(id=>({id,name:`item_${id}`,rankLevel:5,nameCardPic:`card_${id}`,growCurves:[]}));
  const state={params:{itemId:ids[1]},paramsReads:0,paramsError:false,items,itemsReads:0,materialsReads:0,itemsGates:[],materialGates:[],cancelled:0,selected:[],nameGates:[],attacks:[]};
  const metadata={getAvatars:async()=>readItems(),getWeapons:async()=>readItems(),getMaterials:async()=>{state.materialsReads++;return state.materialGates.length?state.materialGates.shift().promise:new Map();},
    getNameCardByPic:async()=>{const gate=deferred();state.nameGates.push(gate);return gate.promise;}};
  const readItems=()=>{state.itemsReads++;return state.itemsGates.length?state.itemsGates.shift().promise:state.items;};
  const mocks={
    '../model/CharacterData':{CharacterDetail:class {}},
    '@kit.ArkUI':{router:{getParams:()=>{state.paramsReads++;if(state.paramsError)throw Error('route unavailable');return state.params;}}},
    '../viewmodel/CultivationDraftViewModel':{CultivationDraftViewModel:class {cancel(){state.cancelled++;}}},
    '../service/WikiMetaService':{WikiMetaService:metadata},
    '../data/prefs/PreferencesStore':{PreferencesStore:{getBool:(_key,fallback)=>fallback}},
    '../components/SimpleDataSource':{SimpleDataSource:class {constructor(items){this.items=items;this.reloads=0;}notifyDataReload(items){this.items=items;this.reloads++;}}},
    '../service/BaseValueService':{BaseValueService:{weaponMaxLevel:()=>90,weaponAttack:async()=>{const gate=deferred();state.attacks.push(gate);return gate.promise;}}},
  };
  const output=ts.transpileModule(imports+body,{reportDiagnostics:true,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}});assert.equal(output.diagnostics.length,0);
  const m={exports:{}};vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`,{State:()=>{},Prop:()=>{},StorageProp:()=>()=>{}})(id=>{assert(mocks[id],`Unexpected dependency ${id}`);return mocks[id];},m,m.exports);
  const page=new m.exports[`Wiki${kind}Page`]();
  // Derived base-value/art work is independent from loading/selecting the routed metadata item.
  page[`on${kind}Selected`]=()=>state.selected.push(page.selectedId);
  return{page,state,ids,source};
}
(async()=>{
  for(const kind of ['Avatar','Weapon']) {
    await test(`${kind}: known route selects the exact item on narrow and wide pages`,async()=>{
      for(const wide of [false,true]){const {page,state,ids}=harness(kind);page.isWide=wide;page.aboutToAppear();await flush();assert.equal(page.selectedId,ids[1]);assert.equal(page.current.id,ids[1]);assert.equal(page.loading,false);assert.equal(page.routeMessage,'');assert.deepEqual(state.selected,[ids[1]]);assert.equal(state.paramsReads,1);assert.equal(page.listSource.items.length,2);}
    });
    await test(`${kind}: missing route preserves normal defaults; invalid/unknown never shows unrelated detail`,async()=>{
      const {page,state,ids}=harness(kind);page.isWide=true;state.params={};page.aboutToAppear();await flush();assert.equal(page.selectedId,ids[0]);
      for(const value of [ids[1]+1000,0,-1,NaN,1.5,String(ids[1]),null]){state.params={itemId:value};page.aboutToAppear();await flush();assert.equal(page.selectedId,0,String(value));assert.equal(page.current,undefined);assert.match(page.routeMessage,/本地暂无/);assert.equal(page.listSource.items.length,2);}
      state.paramsError=true;page.aboutToAppear();await flush();assert.equal(page.current,undefined);assert.equal(page.selectedId,0);
    });
    await test(`${kind}: embedded pages never read global route params`,async()=>{
      for(const wide of [false,true]){const {page,state,ids}=harness(kind);page.embedMode=true;page.isWide=wide;state.paramsError=true;page.aboutToAppear();await flush();assert.equal(state.paramsReads,0);assert.equal(page.selectedId,wide?ids[0]:0);assert.equal(page.routeMessage,'');}
    });
    await test(`${kind}: stale metadata load cannot override a newer routed selection`,async()=>{
      const {page,state,ids}=harness(kind);const old=deferred();state.params={itemId:ids[0]};state.itemsGates.push(old);page.aboutToAppear();
      state.params={itemId:ids[1]};page.aboutToAppear();await flush();assert.equal(page.selectedId,ids[1]);assert.equal(state.materialsReads,1);const reloads=page.listSource.reloads;
      old.resolve([state.items[0]]);await flush();assert.equal(page.selectedId,ids[1]);assert.equal(page.current.id,ids[1]);assert.equal(page.listSource.reloads,reloads);assert.equal(state.materialsReads,1);
    });
    await test(`${kind}: detached metadata/material completions never publish, reject, or finish a newer load`,async()=>{
      for(const stage of ['items','materials'])for(const rejects of [false,true]){
        const {page,state,ids}=harness(kind);const old=deferred(),newer=deferred();
        if(stage==='items')state.itemsGates.push(old);else state.materialGates.push(old);
        page.aboutToAppear();await flush();page.aboutToDisappear();assert.equal(state.cancelled,1);const reloads=page.listSource.reloads;
        state.params={itemId:ids[0]};state.itemsGates.push(newer);page.aboutToAppear();
        if(rejects)old.reject(Error('stale read'));else old.resolve(stage==='items'?state.items:new Map());await flush();
        assert.equal(page.loading,true);assert.equal(page.listSource.reloads,reloads);assert.equal(page.current,undefined);
        newer.resolve(state.items);await flush();assert.equal(page.selectedId,ids[0]);assert.equal(page.loading,false);assert.equal(page.routeMessage,'');
      }
    });
    await test(`${kind}: active read failure settles honestly, selection clears unknown-route notice`,async()=>{
      const {page,state}=harness(kind);const gate=deferred();state.itemsGates.push(gate);page.aboutToAppear();gate.reject(Error('internal detail'));await flush();assert.equal(page.loading,false);assert.equal(page.current,undefined);assert.match(page.routeMessage,/无法读取本地/);assert(!page.routeMessage.includes('internal'));
      state.params={itemId:0};page.aboutToAppear();await flush();page.select(state.items[1]);assert.equal(page.routeMessage,'');assert.equal(page.current,state.items[1]);page.aboutToDisappear();page.select(state.items[0]);assert.equal(page.current,state.items[1]);
    });
    await test(`${kind}: late secondary detail reads are fenced after detach`,async()=>{
      const {page,state}=harness(kind);page.aboutToAppear();await flush();
      if(kind==='Avatar'){
        const pending=page.loadNameCardInfo();page.aboutToDisappear();state.nameGates[0].resolve({name:'stale name',description:'stale detail'});await pending;assert.equal(page.ncName,'');assert.equal(page.ncDesc,'');
      }else{
        const pending=page.calcAttack();page.aboutToDisappear();state.attacks[0].resolve(999);await pending;assert.notEqual(page.curAttack,999);
      }
    });
    await test(`${kind}: cultivation editor and only explicit route consumers remain wired`,()=>{
      const {source}=harness(kind);assert.match(source,/CultivationDraftEditor/);assert.match(source,/this\.draftVm\.cancel\(\)/);assert.match(source,/WishHistoryWikiParams/);assert.match(source,/if \(this\.embedMode\) \{ return; \}/);assert.match(source,/if \(!this\.ownsLoad\(sequence\)\) \{ return; \}/);
    });
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
