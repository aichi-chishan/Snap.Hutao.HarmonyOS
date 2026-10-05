// Production page methods, view-model, UIGF service and models; only platform/network/repository boundaries are doubles.
// No account, network, native ArkUI/SQLite or SDK execution. Offline access does not certify old UIGF transaction semantics.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const pageSource = fs.readFileSync(path.join(root, 'pages/GachaLogPage.ets'), 'utf8');
const A = '100000001', B = '700000002', C = '600000003';
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a;reject=b; });return { promise,resolve,reject }; };
const flush = async () => { for(let index=0;index<200;index++)await Promise.resolve(); };
const plain = value => JSON.parse(JSON.stringify(value));
function method(name) {
  const expression = new RegExp('(?:private )?(?:async )?' + name + '\\([^\\n]*\\)(?:: [^{\\n]+)? \\{');
  const found = expression.exec(pageSource); assert.ok(found, name);
  const first = pageSource.indexOf('{',found.index); let depth=0, quote='', comment='';
  for(let i=first;i<pageSource.length;i++) {
    const c=pageSource[i], next=pageSource[i+1];
    if(comment==='line'){if(c==='\n')comment='';continue;}
    if(comment==='block'){if(c==='*'&&next==='/'){comment='';i++;}continue;}
    if(quote){if(c==='\\')i++;else if(c===quote)quote='';continue;}
    if(c==='/'&&next==='/'){comment='line';i++;continue;}
    if(c==='/'&&next==='*'){comment='block';i++;continue;}
    if(c==='\''||c==='"'||c==='`'){quote=c;continue;}
    if(c==='{')depth++;
    if(c==='}'&&--depth===0)return pageSource.slice(found.index,i+1);
  }
  throw Error('Unbalanced method '+name);
}
function harness(initial=[{id:1,uid:A,isSelected:false},{id:2,uid:B,isSelected:true}]) {
  const state={archives:initial.map(row=>({...row})),rows:[],created:[],selected:[],deleted:[],refreshCalls:[],urlCalls:[],changes:[],cancelled:0,
    reads:0,opens:0,closes:0,writes:[],writeLengths:[],allocations:[],statCalls:0,statSize:undefined,afterSize:undefined,shortRead:false,shortWrite:false,pickerCalls:0,text:'',nextArchives:undefined,nextItems:undefined,nextSelect:undefined,nextRefresh:undefined,nextUrl:undefined,nextPicker:undefined,nextHistory:undefined};
  const modules=new Map();
  const repo={
    async getAllArchives(){state.reads++;if(state.nextArchives){const gate=state.nextArchives;state.nextArchives=undefined;return gate.promise;}return state.archives.map(row=>({...row}));},
    async selectArchive(id){state.selected.push(id);if(state.nextSelect){const gate=state.nextSelect;state.nextSelect=undefined;await gate.promise;}state.archives.forEach(row=>row.isSelected=row.id===id);},
    async getOrCreateArchive(uid){assert.match(uid,/^[1-9][0-9]{8,9}$/);state.created.push(uid);let row=state.archives.find(value=>value.uid===uid);if(!row){row={id:state.archives.length+1,uid,isSelected:false};state.archives.push(row);}return {...row};},
    async getItems(id,pool){if(state.nextItems){const gate=state.nextItems;state.nextItems=undefined;return gate.promise;}return state.rows.filter(row=>row.archiveId===id && row.gachaType===pool);},
    async getItemsByType(id,pool){return state.rows.filter(row=>row.archiveId===id && row.gachaType===pool);},
    async getItemsByArchive(id){return state.rows.filter(row=>row.archiveId===id);},
    async getAllGachaIds(id){return state.rows.filter(row=>row.archiveId===id).map(row=>row.gachaId);},
    async insertItems(items){state.rows.push(...items);return items.length;},
    async deleteArchive(id){state.deleted.push(id);state.archives=state.archives.filter(row=>row.id!==id);state.rows=state.rows.filter(row=>row.archiveId!==id);}
  };
  const network={
    cancelRefresh(){state.cancelled++;},
    async refreshByStoken(uid,progress,full){state.refreshCalls.push({uid,progress,full});if(state.nextRefresh){const gate=state.nextRefresh;state.nextRefresh=undefined;return gate.promise;}return {ok:true,uid,message:'refreshed',fetchedCount:0};},
    async importByUrl(url,uid,progress,full){state.urlCalls.push({url,uid,progress,full});if(state.nextUrl){const gate=state.nextUrl;state.nextUrl=undefined;return gate.promise;}return {ok:true,uid:C,message:'imported',fetchedCount:0};}
  };
  const globals={Error,Date,AppStorage:{setOrCreate:(key,value)=>state.changes.push([key,value])},Observed:value=>value};
  const metadata={ensureIconMaps:async()=>{},getGachaEvents:async()=>[]};
  function load(name){
    if(modules.has(name))return modules.get(name);
    const compiled=ts.transpileModule(fs.readFileSync(path.join(root,name+'.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true},reportDiagnostics:true});
    assert.equal(compiled.diagnostics.length,0,name);
    const module={exports:{}};
    vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`,globals,{filename:name+'.ets'})(id=>{
      if(id.endsWith('/GachaRepo'))return {GachaRepo:repo};
      if(id.endsWith('/GachaLogService'))return {GachaLogService:{getInstance:()=>network},RefreshResult:class{}};
      if(id.endsWith('/WikiMetaService'))return {WikiMetaService:metadata};
      if(id.endsWith('/Logger'))return {Logger:{info(){},warn(){}}};
      if(id.endsWith('/Constants'))return {AppConstants:{APP_VERSION:'offline-host'}};
      assert.ok(id.startsWith('.'),id);
      return load(path.posix.normalize(path.posix.join(path.posix.dirname(name),id)));
    },module,module.exports);
    modules.set(name,module.exports);return module.exports;
  }
  const {GachaLogViewModel:Model}=load('viewmodel/GachaLogViewModel');
  const {UigfService}=load('service/UigfService');
  const model=new Model();
  const names=['aboutToAppear','aboutToDisappear','onLoginStateChanged','onUidChanged','resetLocalView','reloadData','archiveOptions','currentArchiveIndex','chooseLocalArchive','refreshAccount','submitUrlImport','uigfImport','uigfExport','loadHistoryWishes'];
  const compiled=ts.transpileModule('export class Page {\n'+names.map(method).join('\n')+'\n}',{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
  assert.equal(compiled.diagnostics.length,0,'page methods');
  const pageModule={exports:{}};
  vm.runInNewContext(`(function(module,exports){${compiled.outputText}\n})`,{...globals,UigfService,WikiMetaService:metadata,
    Logger:{warn(){}},GACHA_TAG:'host',UIGF_MAX_BYTES:32*1024*1024,ArrayBuffer:class extends ArrayBuffer{constructor(size){state.allocations.push(size);super(size);}},GachaHistoryService:{getInstance:()=>({buildHistory:async()=>state.nextHistory ? state.nextHistory.promise : []})},
    picker:{DocumentSelectOptions:class{},DocumentSaveOptions:class{},DocumentViewPicker:class{
      async select(){state.pickerCalls++;return state.nextPicker ? state.nextPicker.promise : ['/fixture.json'];}
      async save(){state.pickerCalls++;return state.nextPicker ? state.nextPicker.promise : ['/export.json'];}
    }},
    fileIo:{OpenMode:{READ_ONLY:1,READ_WRITE:2,TRUNC:4},openSync(){state.opens++;return {fd:1};},statSync(){state.statCalls++;return {size:state.statCalls>1 && state.afterSize!==undefined ? state.afterSize : state.statSize ?? Buffer.byteLength(state.text)};},readSync(fd,buffer){new Uint8Array(buffer).set(Buffer.from(state.text));return state.shortRead ? buffer.byteLength-1 : buffer.byteLength;},closeSync(){state.closes++;},writeSync(fd,bytes){assert.ok(bytes instanceof Uint8Array);state.writeLengths.push(bytes.byteLength);state.writes.push(Buffer.from(bytes).toString('utf8'));return state.shortWrite ? bytes.byteLength-1 : bytes.byteLength;}},
    util:{TextDecoder:{create:()=>({decodeToString:bytes=>Buffer.from(bytes).toString('utf8')})},TextEncoder:{create:()=>({encodeInto:text=>new Uint8Array(Buffer.from(text,'utf8'))})}}
  })(pageModule,pageModule.exports);
  function page(){const target=new pageModule.exports.Page(),toasts=[];Object.assign(target,{pageActive:true,pageEpoch:1,historyGeneration:0,historyLoading:false,historyLoadedFor:-1,
    vm:model,isLoggedIn:false,currentUid:A,pivotIndex:0,initialized:false,urlInput:'',showUrlInput:false,
    historyWishes:[],poolCards:[],poolRows:[],charCounts:[],weaponCounts:[],historySource:{notifyDataReload(){}},
    toast:message=>toasts.push(message),loadPoolViewModes(){},syncs:0,syncAll(){this.syncs++;},syncProgress(){},preloadHistoryBanners(){}});return {target,toasts};}
  return {state,repo,model,Model,page};
}
const uigfFile=uid=>JSON.stringify({info:{version:'v4.2'},hk4e:[{uid,timezone:8,list:[{id:'184467440737095516151234',gacha_type:400,uigf_gacha_type:301,item_id:10000001,rank_type:5,time:'2026-10-05 10:00:00',name:'试验🔥',item_type:'角色',count:1}]}]});
function strictModelTypes() {
  // In-memory TypeScript host: validates the production VM/model graph, not HarmonyOS SDK declarations.
  const virtualRoot='/offline-gacha-types',files=new Map();
  const put=(name,text)=>files.set(virtualRoot+'/'+name+'.ts',text);
  for(const name of ['viewmodel/GachaLogViewModel','model/GachaArchive','model/GachaItem','model/GachaType','model/GachaStatistics','model/RefreshProgress'])put(name,fs.readFileSync(path.join(root,name+'.ets'),'utf8'));
  put('common/Logger',`export class Logger{static info(tag:string,message:string):void{} static warn(tag:string,message:string):void{}}`);
  put('service/UigfService',`export class UigfService{static timezoneOfUid(uid:string):number{return 8;}static normalizeTime(value:string,from:number,to:number):string{return value;}}`);
  put('service/WikiMetaService',`export class GachaEventMeta{type=0;from=0;to=0;upOrange:number[]=[];}export class WikiMetaService{static async getGachaEvents():Promise<GachaEventMeta[]>{return [];}}`);
  put('service/GachaLogService',`import {RefreshProgress} from '../model/RefreshProgress';export class RefreshResult{ok=false;uid='';message='';fetchedCount=0;}
    export class GachaLogService{static getInstance():GachaLogService{return new GachaLogService();}cancelRefresh():void{}
      async refreshByStoken(uid:string,progress:(value:RefreshProgress)=>void,full:boolean):Promise<RefreshResult>{return new RefreshResult();}
      async importByUrl(url:string,uid:string,progress:(value:RefreshProgress)=>void,full:boolean):Promise<RefreshResult>{return new RefreshResult();}}`);
  put('data/repo/GachaRepo',`import {GachaArchive} from '../../model/GachaArchive';import {GachaItem} from '../../model/GachaItem';export class GachaRepo{
    static async getAllArchives():Promise<GachaArchive[]>{return [];}static async selectArchive(id:number):Promise<void>{}
    static async getItems(id:number,pool:number,limit:number,offset:number):Promise<GachaItem[]>{return [];}
    static async getItemsByType(id:number,pool:number):Promise<GachaItem[]>{return [];}static async deleteArchive(id:number):Promise<void>{}}`);
  put('globals',`declare function Observed(target:Function):void;declare namespace AppStorage{function setOrCreate<T>(key:string,value:T):void;}`);
  const options={strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,experimentalDecorators:true,skipLibCheck:true};
  const host=ts.createCompilerHost(options),base={fileExists:host.fileExists,readFile:host.readFile,getSourceFile:host.getSourceFile,directoryExists:host.directoryExists};
  host.fileExists=file=>files.has(file)||base.fileExists(file);
  host.readFile=file=>files.get(file)??base.readFile(file);
  host.getSourceFile=(file,version,...rest)=>files.has(file)?ts.createSourceFile(file,files.get(file),version,true):base.getSourceFile(file,version,...rest);
  host.directoryExists=directory=>[...files.keys()].some(file=>file.startsWith(directory+'/'))||base.directoryExists(directory);
  const diagnostics=ts.getPreEmitDiagnostics(ts.createProgram([...files.keys()],options,host));
  assert.equal(diagnostics.length,0,diagnostics.map(value=>ts.flattenDiagnosticMessageText(value.messageText,'\n')).join('\n'));
}
(async()=>{
  await test('offline load honors persisted selection, reports its UID, and never creates an archive',async()=>{
    const {state,model}=harness();await model.load('');assert.equal(model.currentArchiveId,2);assert.equal(model.currentUid,B);assert.equal(model.stats.uid,B);assert.equal(model.gameAccountUid,'');assert.equal(model.loaded,true);assert.equal(state.created.length,0);
    await model.load(A);assert.equal(model.currentUid,B);assert.equal(model.gameAccountUid,A);
    await model.load('');assert.equal(model.currentUid,B);assert.equal(model.gameAccountUid,'');assert.equal(state.created.length,0);
  });
  await test('empty and invalid existing archives remain read-only even with a valid logged-in UID',async()=>{
    const {state,model}=harness([{id:1,uid:'',isSelected:true},{id:2,uid:'invalid',isSelected:false}]);
    for(const uid of ['',A,'bad']){await model.load(uid);assert.equal(model.currentArchiveId,0);assert.equal(model.currentUid,'');assert.equal(model.archives.length,0);assert.equal(model.items.length,0);assert.equal(model.stats.archiveId,0);}
    assert.equal(state.created.length,0);
  });
  await test('explicit archive selection persists locally across fresh models without changing the network UID',async()=>{
    const {state,model,Model}=harness();await model.load(A);await model.selectArchive(1);assert.equal(model.currentUid,A);assert.equal(model.gameAccountUid,A);assert.deepEqual(state.selected,[1]);
    await model.selectArchive(2);assert.equal(model.currentUid,B);assert.equal(model.gameAccountUid,A);
    const restarted=new Model();await restarted.load('');assert.equal(restarted.currentUid,B);assert.equal(state.created.length,0);
    await assert.rejects(model.selectArchive(999),/不存在/);
  });
  await test('automatic refresh uses only authenticated account UID, never selected offline archive',async()=>{
    const {state,model}=harness();await model.load('');assert.equal(await model.refresh(),false);assert.equal(state.refreshCalls.length,0);
    await model.load(A);assert.equal(model.currentUid,B);assert.equal(await model.refresh(),true);assert.equal(state.refreshCalls[0].uid,A);assert.equal(model.currentUid,B);assert.equal(state.created.length,0);
  });
  await test('manual URL import has independent auth/response UID and cannot become the automatic-refresh account',async()=>{
    const {state,model}=harness();await model.load('');state.archives.push({id:3,uid:C,isSelected:false});
    assert.equal(await model.importByUrl('https://fixture.invalid/?authkey=fixture'),true);assert.equal(state.urlCalls[0].uid,'');assert.equal(model.currentUid,C);assert.equal(model.gameAccountUid,'');assert.equal(await model.refresh(),false);
    await model.load(A);assert.equal(model.currentUid,C);assert.equal(await model.refresh(),true);assert.equal(state.refreshCalls[0].uid,A);
  });
  await test('late loads and stale item/stat reads cannot overwrite a newer archive context',async()=>{
    const {state,model}=harness();const old=deferred();state.nextArchives=old;const pending=model.load(A);await model.load('');old.resolve([{id:9,uid:C,isSelected:true}]);await pending;
    assert.equal(model.currentUid,B);assert.equal(model.gameAccountUid,'');
    const items=deferred();state.nextItems=items;const late=model.reloadItems();await model.selectArchive(1);items.resolve([{name:'stale'}]);await late;assert.equal(model.currentUid,A);assert.equal(model.items.length,0);
    const stats=deferred();const original=model.buildPoolStats;let first=true;model.buildPoolStats=async(...args)=>{if(first){first=false;return stats.promise;}return original.apply(model,args);};
    const oldStats=model.reloadStats();await model.selectArchive(2);stats.resolve({totalCount:999});await oldStats;assert.equal(model.stats.uid,B);assert.equal(model.stats.totalPulls,0);
  });
  await test('invalidation requests cancellation, blocks a replacement network job, and ignores old progress/result',async()=>{
    const {state,model}=harness();await model.load(A);const gate=deferred();state.nextRefresh=gate;const pending=model.refresh();
    const owned={reportText:'old live progress'};state.refreshCalls[0].progress(owned);await model.load('');const before=model.progress;owned.reportText='mutated after cancellation';assert.notEqual(model.progress.reportText,owned.reportText);assert.equal(state.cancelled,1);assert.equal(model.isRefreshing,true);assert.equal(await model.refresh(),false);
    state.refreshCalls[0].progress({reportText:'stale progress'});assert.equal(model.progress,before);
    gate.resolve({ok:true,uid:A,message:'late',fetchedCount:1});assert.equal(await pending,false);assert.equal(model.currentUid,B);assert.notEqual(model.message,'late');assert.equal(model.isRefreshing,false);assert.equal(state.changes.length,1,'a real committed change still notifies other views');
  });
  await test('deletion chooses another local archive and never recreates the logged-in or empty UID',async()=>{
    const {state,model}=harness();await model.load(A);await model.deleteCurrentArchive();assert.equal(model.currentUid,A);await model.deleteCurrentArchive();assert.equal(model.currentUid,'');assert.equal(model.currentArchiveId,0);assert.equal(model.gameAccountUid,A);await model.load(A);assert.equal(state.created.length,0);assert.deepEqual(state.deleted,[2,1]);
  });
  await test('page logout/empty-UID watchers still load offline data and unmount fences late UI callbacks',async()=>{
    const {state,model,page}=harness();const {target,toasts}=page();target.reloadData();await flush();assert.equal(model.currentUid,B);assert.equal(model.gameAccountUid,'');
    target.isLoggedIn=true;target.onLoginStateChanged();await flush();assert.equal(model.gameAccountUid,A);
    target.currentUid='';target.onUidChanged();await flush();assert.equal(model.gameAccountUid,'');assert.equal(model.currentUid,B);
    const gate=deferred();state.nextArchives=gate;target.reloadData();target.aboutToDisappear();const syncs=target.syncs;gate.resolve([{id:3,uid:C,isSelected:true}]);await flush();assert.equal(target.syncs,syncs);assert.equal(toasts.length,0);
  });
  await test('offline UIGF import/export use the production service and imported UID never gains login authority',async()=>{
    const {state,model,page}=harness([]);const {target}=page();state.text=uigfFile(C);target.reloadData();await flush();
    await target.uigfImport();assert.equal(model.currentUid,C);assert.equal(model.gameAccountUid,'');assert.deepEqual(state.created,[C]);assert.equal(state.rows[0].gachaId,'184467440737095516151234');assert.equal(model.isTransferring,false);
    await target.uigfExport();assert.equal(state.writes.length,1);const exported=JSON.parse(state.writes[0]);assert.equal(String(exported.hk4e[0].uid),C);assert.equal(exported.hk4e[0].list[0].id,'184467440737095516151234');assert.equal(state.opens,state.closes);assert.equal(state.writeLengths[0],Buffer.byteLength(state.writes[0]));assert.ok(state.writeLengths[0]>state.writes[0].length,'UTF-8 bytes, not string length, are checked');
    await target.refreshAccount();assert.equal(state.refreshCalls.length,0);
  });
  await test('file-picker cancellation/unmount and duplicate commands cannot start unintended reads or imports',async()=>{
    const {state,model,page}=harness();const {target,toasts}=page();const gate=deferred();state.nextPicker=gate;state.text=uigfFile(C);
    const pending=target.uigfImport();await target.uigfImport();assert.equal(state.pickerCalls,1);await assert.rejects(model.selectArchive(1),/等待/);
    target.aboutToDisappear();gate.resolve(['/fixture.json']);await pending;assert.equal(state.opens,0);assert.equal(state.created.length,0);assert.equal(toasts.length,0);assert.equal(model.isTransferring,false);
  });
  await test('an export picker completing after unmount never opens or writes the destination',async()=>{
    const {state,model,page}=harness();await model.load('');const {target}=page();const gate=deferred();state.nextPicker=gate;
    const pending=target.uigfExport();await flush();assert.equal(state.pickerCalls,1);target.aboutToDisappear();gate.resolve(['/export.json']);await pending;
    assert.equal(state.opens,0);assert.equal(state.writes.length,0);assert.equal(model.isTransferring,false);
  });
  await test('oversized, empty and malformed stat sizes fail before allocation and close the input',async()=>{
    for(const size of [0,-1,1.5,Infinity,32*1024*1024+1]){
      const {state,model,page}=harness([]);const {target,toasts}=page();state.text=uigfFile(C);state.statSize=size;
      await target.uigfImport();assert.equal(state.allocations.length,0);assert.equal(state.opens,1);assert.equal(state.closes,1);assert.equal(state.created.length,0);assert.equal(model.isTransferring,false);assert.match(toasts[0],/32 MiB/);
    }
  });
  await test('short or size-changing reads fail before any UIGF database writes',async()=>{
    for(const mode of ['short','changed']){
      const {state,model,page}=harness([]);const {target,toasts}=page();state.text=uigfFile(C);
      if(mode==='short')state.shortRead=true;else state.afterSize=Buffer.byteLength(state.text)+1;
      await target.uigfImport();assert.equal(state.created.length,0);assert.equal(state.opens,state.closes);assert.equal(model.isTransferring,false);assert.match(toasts[0],mode==='short'?/读取不完整/:/大小发生变化/);
    }
  });
  await test('a short UTF-8 export is reported as failure, never success, and closes the output',async()=>{
    const {state,model,page}=harness();await model.load('');const {target,toasts}=page();state.shortWrite=true;
    await target.uigfExport();assert.equal(state.writes.length,1);assert.equal(state.opens,state.closes);assert.equal(model.isTransferring,false);assert.match(toasts[0],/写入不完整/);assert.ok(toasts.every(value=>!value.includes('导出成功')));
  });
  await test('history completion is archive/epoch owned after local selection or disposal',async()=>{
    const {state,model,page}=harness();await model.load('');const {target}=page();const gate=deferred();state.nextHistory=gate;const pending=target.loadHistoryWishes();
    target.pageEpoch++;target.resetLocalView();await model.selectArchive(1);gate.resolve([{name:'old archive'}]);await pending;assert.equal(target.historyWishes.length,0);assert.equal(target.historyLoadedFor,-1);assert.equal(target.historyLoading,false);
  });
  await test('production view-model and model graph pass strict host types with explicit service/platform doubles',strictModelTypes);
  await test('page exposes local controls without a login branch and binds refresh to the separate account',()=>{
    assert.doesNotMatch(pageSource,/loginGuide\(/);
    const build=method('build');assert.match(build,/this\.localArchiveControls\(\)/);assert.doesNotMatch(build,/if \(!this\.isLoggedIn\)/);
    assert.match(build,/\.enabled\(this\.isLoggedIn && this\.vm\.gameAccountUid\.length > 0/);
    assert.match(pageSource,/Select\(this\.archiveOptions\(\)\)/);
    assert.match(method('uigfImport'),/this\.vm\.load\(this\.vm\.gameAccountUid, result\.uid\)/);
    assert.doesNotMatch(fs.readFileSync(path.join(root,'viewmodel/GachaLogViewModel.ets'),'utf8'),/getOrCreateArchive/);
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
