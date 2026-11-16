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
  const expression = new RegExp('^  (?:private )?(?:static )?(?:async )?' + name + '\\([^\\n]*\\)(?:: [^{\\n]+)? \\{', 'm');
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
  const state={parseCalls:0,importCalls:0,archives:initial.map(row=>({...row})),rows:[],created:[],selected:[],deleted:[],refreshCalls:[],urlCalls:[],changes:[],cancelled:0,
    reads:0,detailReads:[],opens:0,closes:0,writes:[],writeLengths:[],allocations:[],statCalls:0,closeError:false,statSize:undefined,afterSize:undefined,shortRead:false,shortWrite:false,pickerCalls:0,text:'',nextArchives:undefined,nextArchiveItems:undefined,nextItems:undefined,nextSelect:undefined,nextRefresh:undefined,nextUrl:undefined,nextPicker:undefined,nextHistory:undefined};
  const sdk=require('./helpers/uigf-sdk-double.cjs')(state);
  const modules=new Map();
  const repo={
    async getAllArchives(){state.reads++;if(state.nextArchives){const gate=state.nextArchives;state.nextArchives=undefined;return gate.promise;}return state.archives.map(row=>({...row}));},
    async selectArchive(id){state.selected.push(id);if(state.nextSelect){const gate=state.nextSelect;state.nextSelect=undefined;await gate.promise;}state.archives.forEach(row=>row.isSelected=row.id===id);},
    async getOrCreateArchive(uid){assert.match(uid,/^[1-9][0-9]{8,9}$/);state.created.push(uid);let row=state.archives.find(value=>value.uid===uid);if(!row){row={id:state.archives.length+1,uid,isSelected:false};state.archives.push(row);}return {...row};},
    async getItems(id,pool){state.detailReads.push(['history',id,pool]);if(state.nextItems){const gate=state.nextItems;state.nextItems=undefined;return gate.promise;}return state.rows.filter(row=>row.archiveId===id && row.gachaType===pool);},
    async getItemsByType(id,pool){state.detailReads.push(['pool',id,pool]);return state.rows.filter(row=>row.archiveId===id && row.gachaType===pool);},
    async getItemsByArchive(id){state.detailReads.push(['archive',id]);if(state.nextArchiveItems){const gate=state.nextArchiveItems;state.nextArchiveItems=undefined;return gate.promise;}return state.rows.filter(row=>row.archiveId===id);},
    async getAllGachaIds(id){return state.rows.filter(row=>row.archiveId===id).map(row=>row.gachaId);},
    async insertItems(items){state.rows.push(...items);return items.length;},
    async importArchives(pending){state.importCalls++;let inserted=0;for(const [uid,items] of pending){const archive=await this.getOrCreateArchive(uid);const key=item=>`${[1000,2000].includes(item.gachaType)?'b':'s'}:${item.gachaId}`;const known=new Set((await this.getItemsByArchive(archive.id)).map(key));for(const item of items){const value=key(item);if(known.has(value))continue;known.add(value);state.rows.push(Object.assign(Object.create(Object.getPrototypeOf(item)),item,{archiveId:archive.id}));inserted++;}}return inserted;},
    async deleteArchive(id){state.deleted.push(id);state.archives=state.archives.filter(row=>row.id!==id);state.rows=state.rows.filter(row=>row.archiveId!==id);}
  };
  const network={
    cancelRefresh(){state.cancelled++;},
    async refreshByStoken(uid,progress,full,onlyTypes){state.refreshCalls.push({uid,progress,full,onlyTypes});if(state.nextRefresh){const gate=state.nextRefresh;state.nextRefresh=undefined;return gate.promise;}return {ok:true,uid,message:'refreshed',fetchedCount:0};},
    async importByUrl(url,uid,progress,full,onlyTypes){state.urlCalls.push({url,uid,progress,full,onlyTypes});if(state.nextUrl){const gate=state.nextUrl;state.nextUrl=undefined;return gate.promise;}return {ok:true,uid:C,message:'imported',fetchedCount:0};}
  };
  const globals={...sdk.globals,Error,Date,$r:resource=>resource,JSON:{parse:(...args)=>{state.parseCalls++;return JSON.parse(...args);},stringify:JSON.stringify},AppStorage:{setOrCreate:(key,value)=>state.changes.push([key,value])},Observed:value=>value};
  const metadata={ensureIconMaps:async()=>{},ensureBeyondItemMaps:async()=>{},getGachaEvents:async()=>[],getAvatars:async()=>[],getWeapons:async()=>[]};
  const preferences={KEY_GACHA_UNOBTAINED:'gacha.unobtained_visible',KEY_GACHA_EMPTY_HISTORY:'gacha.empty_history_visible',getBool:(_key,fallback)=>fallback};
  function load(name){
    if(modules.has(name))return modules.get(name);
    const compiled=ts.transpileModule(fs.readFileSync(path.join(root,name+'.ets'),'utf8').replace(/^@Concurrent\s*$/gm,''),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true},reportDiagnostics:true});
    assert.equal(compiled.diagnostics.length,0,name);
    const module={exports:{}};
    vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`,globals,{filename:name+'.ets'})(id=>{
      if(id==='@kit.ArkTS')return sdk.arkTS;
      if(id==='@kit.CoreFileKit')return sdk.files;
      if(id.endsWith('/GachaRepo'))return {GachaRepo:repo};
      if(id.endsWith('/GachaLogService'))return {GachaLogService:{getInstance:()=>network},RefreshResult:class{}};
      if(id.endsWith('/WikiMetaService'))return {WikiMetaService:metadata};
      if(id.endsWith('/GameDataService'))return {GameDataService:{getInstance:()=>({remoteVersion:()=>''})}};
      if(id.endsWith('/LocalizedGameDataService'))return {LocalizedGameDataService:{names:async()=>new Map()}};
      if(id.endsWith('/PreferencesStore'))return {PreferencesStore:preferences};
      if(id.endsWith('/Logger'))return {Logger:{info(){},warn(){}}};
      if(id.endsWith('/Constants'))return {AppConstants:{APP_VERSION:'offline-host'}};
      assert.ok(id.startsWith('.'),id);
      return load(path.posix.normalize(path.posix.join(path.posix.dirname(name),id)));
    },module,module.exports);
    modules.set(name,module.exports);return module.exports;
  }
  const {GachaLogViewModel:Model}=load('viewmodel/GachaLogViewModel');
  const {UigfService}=load('service/UigfService');
  const {GachaType}=load('model/GachaType');
  const {GachaPoolRules}=load('model/GachaPoolRules');
  const {FiveStarDetail}=load('model/GachaStatistics');
  const {GachaStatisticsService}=load('service/GachaStatisticsService');
  const model=new Model();
  const names=['aboutToAppear','aboutToDisappear','onLoginStateChanged','onUidChanged','resetLocalView','invalidatePoolSelection','reloadData','archiveOptions','currentArchiveIndex','chooseLocalArchive','removeLocalArchive','refreshAccount','retryPool','submitUrlImport','uigfImport','uigfExport','confirmUigfImport','prepareUigfExport','changeUigfSelection','loadHistoryWishes'];
  names.push('onLocaleChanged','loadDisplayMetadata','itemType','cleanName','displayItemName','itemIcon','displayItemType');
  names.push('syncPoolCards','cardKey','averageText','countText','pullColor','poolHasUp');
  names.push('showsCombined','visibleSummaryItems','summaryPullCount','summaryThreshold','summaryItemKey','showsRatio','setRatio','archiveActions',
    'onPoolAreaChange','widePoolCardWidth');
  const dataClasses=['GachaItemIcon','PoolCardData'].map(name=>{
    const start=pageSource.indexOf(`class ${name}`);
    return pageSource.slice(start,pageSource.indexOf('\n}',start)+2);
  });
  const breakpoints=pageSource.match(/^const (?:POOL_SINGLE_COLUMN_VP|POOL_MIN_CARD_WIDTH|POOL_CARD_GAP|POOL_VIEW_INSET): number = \d+;$/gm);
  const compiled=ts.transpileModule(`${breakpoints.join('\n')}\n${dataClasses.join('\n')}\nclass GachaLogPage {\n${names.map(method).join('\n')}\n}\nexport { GachaLogPage as Page };`,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
  assert.equal(compiled.diagnostics.length,0,'page methods');
  const pageModule={exports:{}};
  vm.runInNewContext(`(function(module,exports){${compiled.outputText}\n})`,{...globals,UigfService,GachaType,GachaPoolRules,FiveStarDetail,WikiMetaService:metadata,PreferencesStore:preferences,UiSurface:{dialogMaterial:()=>undefined},
    Logger:{warn(){},info(){}},GACHA_TAG:'host',UIGF_MAX_BYTES:32*1024*1024,ArrayBuffer:class extends ArrayBuffer{constructor(size){state.allocations.push(size);super(size);}},GachaHistoryService:{getInstance:()=>({buildHistory:async()=>state.nextHistory ? state.nextHistory.promise : []})},
    picker:{DocumentSelectOptions:class{},DocumentSaveOptions:class{},DocumentViewPicker:class{
      async select(){state.pickerCalls++;return state.nextPicker ? state.nextPicker.promise : ['/fixture.json'];}
      async save(){state.pickerCalls++;return state.nextPicker ? state.nextPicker.promise : ['/export.json'];}
    }},
    fileIo:{OpenMode:{READ_ONLY:1,READ_WRITE:2,TRUNC:4},openSync(){state.opens++;return {fd:1};},statSync(){state.statCalls++;return {size:state.statCalls>1 && state.afterSize!==undefined ? state.afterSize : state.statSize ?? Buffer.byteLength(state.text)};},readSync(fd,buffer){new Uint8Array(buffer).set(Buffer.from(state.text));return state.shortRead ? buffer.byteLength-1 : buffer.byteLength;},closeSync(){state.closes++;if(state.closeError)throw Error('close failed');},writeSync(fd,bytes){assert.ok(bytes instanceof ArrayBuffer);state.writeLengths.push(bytes.byteLength);state.writes.push(Buffer.from(bytes).toString('utf8'));return state.shortWrite ? bytes.byteLength-1 : bytes.byteLength;}},
    util:{TextDecoder:{create:()=>({decodeToString:bytes=>Buffer.from(bytes).toString('utf8')})},TextEncoder:{create:()=>({encodeInto:text=>new Uint8Array(Buffer.from(text,'utf8'))})}}
  })(pageModule,pageModule.exports);
  function page(){const target=new pageModule.exports.Page(),toasts=[];Object.assign(target,{pageActive:true,pageEpoch:1,historyGeneration:0,historyLoading:false,historyLoadedFor:-1,
    vm:model,isLoggedIn:false,currentUid:A,pivotIndex:0,initialized:false,showImportPreview:false,showExportOptions:false,urlInput:'',showUrlInput:false,
    historyWishes:[],poolCards:[],charCounts:[],weaponCounts:[],historySource:{notifyDataReload(){}},
    metadataSequence:0,localeVersion:0,appliedLocaleVersion:0,bannerPreloads:0,beyondMode:false,areaWidth:0,areaHeight:0,showCombinedAvatarPulls:false,ratioPools:[],
    toast:message=>toasts.push(message),loadPoolViewModes(){},syncs:0,syncAll(){this.syncs++;},syncProgress(){},
    preloadHistoryBanners(){this.bannerPreloads++;}});return {target,toasts};}
  return {state,repo,metadata,model,Model,page,GachaPoolRules,GachaStatisticsService};
}
function pulls(ranks,pool){
  return ranks.map((rankType,index)=>({archiveId:2,gachaType:pool,gachaId:String(index+1),
    itemId:index===2?10000023:10000022,name:`Pull ${index+1}`,itemType:'',time:'2026-10-05 10:00:00',rankType}));
}
const uigfFile=uid=>JSON.stringify({info:{version:'v4.2'},hk4e:[{uid,timezone:8,list:[{id:'1844674407370955161',gacha_type:400,uigf_gacha_type:301,item_id:10000001,rank_type:5,time:'2026-10-05 10:00:00',name:'试验🔥',item_type:'角色',count:1}]}]});
function strictModelTypes() {
  // In-memory TypeScript host: validates the production VM/model graph, not HarmonyOS SDK declarations.
  const virtualRoot='/offline-gacha-types',files=new Map();
  const put=(name,text)=>files.set(virtualRoot+'/'+name+'.ts',text);
  for(const name of ['viewmodel/GachaLogViewModel','service/GachaCollectionService','service/GachaStatisticsService','model/GachaArchive','model/GachaItem','model/GachaType','model/GachaPoolRules','model/GachaStatistics','model/RefreshProgress','model/UigfImportPreparation','model/UigfError'])put(name,fs.readFileSync(path.join(root,name+'.ets'),'utf8'));
  put('service/GachaItemIdentityService',`import {GachaItem} from '../model/GachaItem';export class GachaItemIdentityService{
    static async resolveMissing(items:GachaItem[]):Promise<GachaItem[]>{return items;}}`);
  put('common/Logger',`export class Logger{static info(tag:string,message:string):void{} static warn(tag:string,message:string):void{}}`);
  put('service/UigfService',`import {UigfImportPreparation} from '../model/UigfImportPreparation';export class UigfImportResult{ok=false;uid='';message='';inserted=0;archiveCount=0;}
    export class UigfService{static getInstance():UigfService{return new UigfService();}static timezoneOfUid(uid:string):number{return 8;}static normalizeTime(value:string,from:number,to:number):string{return value;}
      prepareImport(text:string):UigfImportPreparation{return new UigfImportPreparation('v4.2',new Map());}async importPrepared(prepared:UigfImportPreparation,selected?:string[],checkCurrent?:()=>void,fillGaps?:boolean):Promise<UigfImportResult>{return new UigfImportResult();}}`);
  put('service/UigfImportJob',`import {UigfImportPreparation} from '../model/UigfImportPreparation';export class UigfImportJob{cancel():void{}async prepare(source:string,isFile:boolean,checkCurrent:()=>void):Promise<UigfImportPreparation>{throw Error();}}`);
  put('service/WikiMetaService',`export class GachaEventMeta{type=0;from=0;to=0;upOrange:number[]=[];upPurple:number[]=[];}
    export class WikiAvatarMeta{id=0;name='';canonicalName='';icon='';quality=0;}export class WikiWeaponMeta{id=0;name='';canonicalName='';icon='';rankLevel=0;}
    export class WikiMetaService{static async getGachaEvents():Promise<GachaEventMeta[]>{return [];}static async getAvatars():Promise<WikiAvatarMeta[]>{return [];}static async getWeapons():Promise<WikiWeaponMeta[]>{return [];}}`);
  put('data/prefs/PreferencesStore',`export class PreferencesStore{static KEY_GACHA_UNOBTAINED='gacha.unobtained_visible';static getBool(key:string,fallback:boolean):boolean{return fallback;}}`);
  put('service/GachaLogService',`import {RefreshProgress} from '../model/RefreshProgress';export class RefreshResult{ok=false;uid='';message='';fetchedCount=0;}
    export class GachaLogService{static getInstance():GachaLogService{return new GachaLogService();}cancelRefresh():void{}
      async refreshByStoken(uid:string,progress:(value:RefreshProgress)=>void,full:boolean,onlyTypes?:number[]):Promise<RefreshResult>{return new RefreshResult();}
      async importByUrl(url:string,uid:string,progress:(value:RefreshProgress)=>void,full:boolean,onlyTypes?:number[]):Promise<RefreshResult>{return new RefreshResult();}}`);
  put('data/repo/GachaRepo',`import {GachaArchive} from '../../model/GachaArchive';import {GachaItem} from '../../model/GachaItem';export class GachaRepo{
    static async getAllArchives():Promise<GachaArchive[]>{return [];}static async selectArchive(id:number):Promise<void>{}
    static async getItems(id:number,pool:number,limit:number,offset:number):Promise<GachaItem[]>{return [];}
    static async getItemsByType(id:number,pool:number):Promise<GachaItem[]>{return [];}static async getItemsByArchive(id:number):Promise<GachaItem[]>{return [];}static async deleteArchive(id:number):Promise<void>{}}`);
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
  await test('page refresh and link import select their current mode while a failed-pool retry stays single-pool',async()=>{
    const {state,model,page}=harness();
    await model.load(A);
    const {target}=page();
    target.isLoggedIn=true;
    for(const beyond of [false,true]){
      target.beyondMode=beyond;
      await target.refreshAccount();
      target.urlInput='https://fixture.invalid/?authkey=fixture';
      await target.submitUrlImport();
    }
    await target.retryPool(2000);
    assert.deepEqual(plain(state.refreshCalls.map(call=>call.onlyTypes)),[[100,200,301,302,500],[1000,2000],[2000]]);
    assert.deepEqual(plain(state.urlCalls.map(call=>call.onlyTypes)),[[100,200,301,302,500],[1000,2000]]);
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
    const stats=deferred();state.nextArchiveItems=stats;
    const oldStats=model.reloadStats();await model.selectArchive(2);
    stats.resolve(pulls([3,4,5],301).map(item=>({...item,archiveId:1})));
    await oldStats;assert.equal(model.stats.uid,B);assert.equal(model.stats.totalPulls,0);assert.equal(model.items.length,0);
  });
  await test('refresh reloads one fresh archive snapshot and a late pool read cannot overwrite it',async()=>{
    const {state,model}=harness();
    state.rows=pulls([3],301).map(item=>({...item,archiveId:1}));
    await model.load(A,A);
    assert.deepEqual(state.detailReads,[['archive',1]]);
    const previousStats=model.stats;
    state.detailReads=[];
    const poolRead=deferred();state.nextItems=poolRead;
    const oldSelection=model.selectPool(302);
    assert.equal(model.stats,previousStats);
    const refresh=deferred();state.nextRefresh=refresh;
    const pending=model.refresh();
    state.rows.push({...pulls([5],302)[0],archiveId:1,gachaId:'2',name:'新入库的武器'});
    refresh.resolve({ok:true,uid:A,message:'refreshed',fetchedCount:1});
    assert.equal(await pending,true);
    assert.deepEqual(state.detailReads,[['history',1,302],['archive',1]]);
    assert.equal(model.stats.totalPulls,2);
    assert.deepEqual(plain(model.items.map(item=>item.name)),['新入库的武器']);
    poolRead.resolve([{...state.rows[1],name:'延迟的旧查询'}]);
    await oldSelection;
    assert.deepEqual(plain(model.items.map(item=>item.name)),['新入库的武器']);
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
  await test('the page deletes only the archive named by its confirmation',async()=>{
    const {state,model,page}=harness();await model.load(A);const {target}=page();
    const gate=deferred();let choice=gate.promise;let lastTitle='';
    target.getUIContext=()=>({getPromptAction:()=>({showDialog:options=>{lastTitle=options.title;return choice;}})});
    const pending=target.removeLocalArchive();assert.match(lastTitle,new RegExp(B));
    await target.chooseLocalArchive(1);gate.resolve({index:1});await pending;
    assert.deepEqual(state.deleted,[]);
    choice=Promise.resolve({index:0});await target.removeLocalArchive();assert.deepEqual(state.deleted,[]);
    choice=Promise.resolve({index:1});await target.removeLocalArchive();
    assert.deepEqual(state.deleted,[1]);assert.equal(model.currentUid,B);
  });
  await test('page logout/empty-UID watchers still load offline data and unmount fences late UI callbacks',async()=>{
    const {state,model,page}=harness();const {target,toasts}=page();target.reloadData();await flush();assert.equal(model.currentUid,B);assert.equal(model.gameAccountUid,'');
    target.isLoggedIn=true;target.onLoginStateChanged();await flush();assert.equal(model.gameAccountUid,A);
    target.currentUid='';target.onUidChanged();await flush();assert.equal(model.gameAccountUid,'');assert.equal(model.currentUid,B);
    const gate=deferred();state.nextArchives=gate;target.reloadData();target.aboutToDisappear();const syncs=target.syncs;gate.resolve([{id:3,uid:C,isSelected:true}]);await flush();assert.equal(target.syncs,syncs);assert.equal(toasts.length,0);
  });
  await test('offline UIGF import/export use the production service and imported UID never gains login authority',async()=>{
    const {state,model,page}=harness([]);const {target}=page();state.text=uigfFile(C);target.reloadData();await flush();
    await target.uigfImport();assert.equal(state.created.length,0);assert.equal(state.parseCalls,1);assert.equal(target.showImportPreview,true);await target.confirmUigfImport();assert.equal(state.parseCalls,1,'confirmation does not parse the original file again');assert.equal(model.currentUid,C);assert.equal(model.gameAccountUid,'');assert.deepEqual(state.created,[C]);assert.equal(state.rows[0].gachaId,'1844674407370955161');assert.equal(model.isTransferring,false);
    target.prepareUigfExport();await target.uigfExport();assert.equal(state.writes.length,1);const exported=JSON.parse(state.writes[0]);assert.equal(String(exported.hk4e[0].uid),C);assert.equal(exported.hk4e[0].list[0].id,'1844674407370955161');assert.equal(state.opens,state.closes);assert.equal(state.writeLengths[0],Buffer.byteLength(state.writes[0]));assert.ok(state.writeLengths[0]>state.writes[0].length,'UTF-8 bytes, not string length, are checked');
    await target.refreshAccount();assert.equal(state.refreshCalls.length,0);
  });
  await test('file-picker cancellation/unmount and duplicate commands cannot start unintended reads or imports',async()=>{
    const {state,model,page}=harness();const {target,toasts}=page();const gate=deferred();state.nextPicker=gate;state.text=uigfFile(C);
    const pending=target.uigfImport();await target.uigfImport();assert.equal(state.pickerCalls,1);await assert.rejects(model.selectArchive(1),/等待/);
    target.aboutToDisappear();gate.resolve(['/fixture.json']);await pending;assert.equal(state.opens,0);assert.equal(state.created.length,0);assert.equal(toasts.length,0);assert.equal(model.isTransferring,false);
  });
  await test('an export picker completing after unmount never opens or writes the destination',async()=>{
    const {state,model,page}=harness();await model.load('');const {target}=page();const gate=deferred();state.nextPicker=gate;
    target.prepareUigfExport();const pending=target.uigfExport();await flush();assert.equal(state.pickerCalls,1);target.aboutToDisappear();gate.resolve(['/export.json']);await pending;
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
    target.prepareUigfExport();await target.uigfExport();assert.equal(state.writes.length,1);assert.equal(state.opens,state.closes);assert.equal(model.isTransferring,false);assert.match(toasts[0],/写入不完整/);assert.ok(toasts.every(value=>!value.includes('导出成功')));
  });
  await test('history completion is archive/epoch owned after local selection or disposal',async()=>{
    const {state,model,page}=harness();await model.load('');const {target}=page();const gate=deferred();state.nextHistory=gate;const pending=target.loadHistoryWishes();
    target.pageEpoch++;target.resetLocalView();await model.selectArchive(1);gate.resolve([{name:'old archive'}]);await pending;assert.equal(target.historyWishes.length,0);assert.equal(target.historyLoadedFor,-1);assert.equal(target.historyLoading,false);
  });
  await test('the locale watcher refreshes the selected archive and period without fetching banners or wishes',async()=>{
    const {state,metadata,model,page}=harness();await model.load(A);const {target}=page();target.pivotIndex=1;
    const older=deferred(),newer=deferred();const reads=[older,newer];metadata.ensureIconMaps=()=>reads.shift().promise;
    state.nextHistory=deferred();state.nextHistory.resolve([{name:'Localized period'}]);
    target.localeVersion=1;target.onLocaleChanged();target.localeVersion=2;target.onLocaleChanged();
    newer.resolve();await flush();older.resolve();await flush();
    assert.equal(target.appliedLocaleVersion,2);assert.equal(target.syncs,1);
    assert.equal(model.currentArchiveId,2);assert.equal(model.gameAccountUid,A);
    assert.equal(target.pivotIndex,1);assert.equal(target.historyWishes[0].name,'Localized period');
    assert.equal(target.bannerPreloads,0);assert.deepEqual(state.refreshCalls,[]);assert.deepEqual(state.urlCalls,[]);
  });
  await test('old prayer rows keep their original fields while translated display resolves IDs and name aliases',async()=>{
    const {state,metadata,model,page}=harness();const {target}=page();
    Object.assign(metadata,{
      displayNameOfItem:(id,name,type)=>id===11509?'Mistplitter Reforged':type==='武器'&&name==='雾切之回光'?'Mistplitter Reforged':name,
      iconOfAvatar:()=>'',iconOfWeapon:id=>id===11509?'sword':'',iconOfBeyondId:id=>id===900001?'beyond':'',
      iconOfAvatarName:()=>'',iconOfWeaponName:name=>name==='雾切之回光'?'sword':'',iconOfBeyondName:()=>'',
    });
    const record={archiveId:2,gachaType:302,itemId:11509,gachaId:'1',name:'★ 雾切之回光 ',itemType:'Weapon',time:'2026-10-05 10:00:00',rankType:5};
    state.rows.push(record);await model.load('');
    assert.equal(model.stats.pools.find(pool=>pool.gachaType===302).fiveDetails[0].itemId,11509);
    assert.equal(target.displayItemName(record.itemId,record.name,''),'Mistplitter Reforged');
    assert.equal(target.displayItemName(0,record.name,'Weapon'),'Mistplitter Reforged');
    assert.deepEqual(plain(target.itemIcon(record.itemId,'outdated','Character')),{category:'EquipIcon',name:'sword'});
    assert.deepEqual(plain(target.itemIcon(900001,'outdated','')),{category:'BeyondItemIcon',name:'beyond'});
    assert.equal(target.displayItemType({...record,itemId:0,itemType:''}),'武器');
    assert.equal(record.name,'★ 雾切之回光 ');assert.equal(record.itemType,'Weapon');
  });
  await test('completed gold, purple and featured spans retain full precision and render two decimal places',async()=>{
    const {state,metadata,model,page}=harness();const {target}=page();
    state.rows=pulls([3,4,5,3,4,3,5,3,3,3,5,3],301);
    metadata.getGachaEvents=async()=>[{type:301,from:Date.parse('2026-10-05T00:00:00Z'),to:Date.parse('2026-10-06T00:00:00Z'),upOrange:[10000022]}];
    await model.load('');target.syncPoolCards();
    const pool=model.stats.pools.find(value=>value.gachaType===301), card=target.poolCards[0];
    assert.equal(pool.averageOrangePull,11/3);assert.equal(pool.averagePurplePull,2.5);assert.equal(pool.averageUpOrangePull,5.5);
    assert.deepEqual(plain(pool.summaryItems.map(item=>[item.gachaId,item.lastPull])),[['11',4],['7',4],['3',3]]);
    assert.deepEqual(plain(pool.fiveDetails.map(item=>item.totalCyclePull)),[4,7,0]);
    assert.equal(card.avgOrange,11/3);assert.equal(card.avgUpOrange,5.5);
    assert.equal(target.constructor.averageText(card.avgOrange),'3.67');
    metadata.getGachaEvents=async()=>[];await model.reloadStats();target.syncPoolCards();
    assert.equal(target.poolCards[0].avgUpOrange,0);
    assert.equal(target.constructor.averageText(target.poolCards[0].avgUpOrange),'0.00');
  });
  await test('permanent Beyond summary tracks four and three stars separately from lower ranks',async()=>{
    const {state,model,page,GachaPoolRules:rules}=harness();const {target}=page();
    state.rows=pulls([1,3,2,4,2,3,3,4,2],1000);
    await model.load('');model.currentPoolType=2000;model.items=[];target.beyondMode=true;target.syncPoolCards();
    const pool=model.stats.pools.find(value=>value.gachaType===1000), card=target.poolCards[0];
    assert.equal(rules.fiveStarThreshold(1000),0);assert.equal(rules.fourStarThreshold(1000),90);assert.equal(rules.threeStarThreshold(1000),10);
    assert.deepEqual([pool.fiveStarCount,pool.fourStarCount,pool.threeStarCount,pool.otherStarCount],[0,2,3,4]);
    assert.deepEqual(plain(card.summaryItems.map(item=>[item.gachaId,item.rankType,item.lastPull])),[['8',4,4],['7',3,1],['6',3,4],['4',4,4],['2',3,2]]);
    assert.equal(card.avgPurple,4);assert.equal(card.threeCount,3);assert.equal(card.otherCount,4);
    assert.equal(card.isCurrent,false);
    assert.equal(card.sinceLastFour,1);assert.equal(card.sinceLastThree,2);
    assert.equal(target.constructor.countText(card.threeCount,card.totalCount),'3 [33.33%]');
    assert.equal(target.constructor.pullColor(3),'app.color.three_star');assert.equal(target.constructor.pullColor(4),'app.color.four_star');
  });
  await test('Beyond event variants retain five and four star summary items in reverse pull order',()=>{
    const {GachaStatisticsService:stats,GachaPoolRules:rules,page}=harness();const {target}=page();
    const rows=pulls([3,4,5,1,4,3],20011);rows[4].gachaType=20022;
    const pool=stats.buildPool(rows,2000,[],8);
    assert.deepEqual(plain(pool.summaryItems.map(item=>[item.gachaId,item.rankType,item.lastPull])),[['5',4,3],['3',5,3],['2',4,2]]);
    assert.deepEqual([pool.averageOrangePull,pool.averagePurplePull,pool.averageUpOrangePull],[3,2.5,0]);
    assert.equal(pool.threeStarCount,2);assert.equal(pool.otherStarCount,1);
    assert.equal(rules.fiveStarThreshold(20011),90);assert.equal(rules.fourStarThreshold(20022),10);assert.equal(rules.threeStarThreshold(2000),0);
    assert.equal(target.constructor.poolHasUp(2000),true);
  });
  await test('local pity counts include recorded pulls even with no same-rarity drop or past the finite threshold',async()=>{
    const {state,model,page,GachaStatisticsService:stats}=harness();const {target}=page();
    state.rows=pulls([2,2,2],1000);target.beyondMode=true;
    await model.load('');target.syncPoolCards();
    assert.equal(target.poolCards[0].sinceLastFour,3);assert.equal(target.poolCards[0].sinceLastThree,3);
    const trailing=stats.buildPool(pulls([3,...new Array(12).fill(2)],1000),1000,[],8);
    assert.equal(trailing.sinceLastThree,12);
    const empty=stats.buildPool([],301,[],8);
    assert.deepEqual([empty.sinceLastFive,empty.sinceLastFour,empty.sinceLastThree],[0,0,0]);
    const standard=stats.buildPool(pulls([3,4,3],301),301,[],8);
    assert.deepEqual([standard.sinceLastFive,standard.sinceLastFour],[3,1]);
    for(const field of ['Five','Four','Three']){
      assert.ok(pageSource.includes(`this.guaranteeBar($r('app.string.ui_gacha_card_to_${field.toLowerCase()}'), card.sinceLast${field},`));
    }
    assert.doesNotMatch(pageSource,/PityKnown|垫数未知/);
  });
  await test('combined avatar view uses full UP cycles, keeps the newest unresolved loss, and leaves other pools alone',async()=>{
    const {state,metadata,model,page}=harness();const {target}=page();
    state.rows=pulls([3,4,5,3,4,3,5,3,3,3,5,3,5,4,5],301);
    state.rows[12].itemId=10000023;state.rows[14].itemId=10000023;
    metadata.getGachaEvents=async()=>[{type:301,from:Date.parse('2026-10-05T00:00:00Z'),to:Date.parse('2026-10-06T00:00:00Z'),upOrange:[10000022]}];
    await model.load('');target.syncPoolCards();const card=target.poolCards[0];
    const rows=()=>plain(target.visibleSummaryItems(card).map(pull=>[pull.gachaId,target.summaryPullCount(301,pull),target.summaryThreshold(301,pull)]));
    assert.deepEqual(rows(),[['15',2,90],['13',2,90],['11',4,90],['7',4,90],['3',3,90]]);
    const before=target.summaryItemKey(301,card.summaryItems[2]);
    target.showCombinedAvatarPulls=true;
    assert.deepEqual(rows(),[['15',2,90],['11',4,180],['7',7,180]]);
    assert.notEqual(target.summaryItemKey(301,card.summaryItems[2]),before);
    const weapon={...card,gachaType:302};
    assert.equal(target.visibleSummaryItems(weapon),card.summaryItems);
    assert.equal(target.summaryPullCount(302,card.summaryItems[3]),4);
    assert.equal(target.summaryThreshold(302,card.summaryItems[3]),80);
    target.showCombinedAvatarPulls=false;
    assert.equal(target.visibleSummaryItems(card).length,5);
    assert.match(pageSource,/if \(card\.gachaType === GachaType\.AVATAR_EVENT\) \{\s*Toggle\(\{ type: ToggleType\.Button/);
  });
  await test('overview follows the Windows card order independently of query order and the selected archive',async()=>{
    const {state,model,page}=harness();
    const queryOrder=[100,200,301,302,500,1000,2000];
    state.rows=queryOrder.flatMap((type,index)=>pulls(new Array(index+1).fill(3),type));
    await model.load('');
    const archiveId=model.currentArchiveId;
    const {target}=page();
    target.syncPoolCards();
    assert.deepEqual(plain(target.poolCards.map(card=>card.gachaType)),[301,302,200,500,100]);
    target.beyondMode=true;
    target.syncPoolCards();
    assert.deepEqual(plain(target.poolCards.map(card=>card.gachaType)),[1000,2000]);
    assert.deepEqual(plain(model.stats.pools.map(pool=>pool.gachaType)),queryOrder);
    assert.equal(model.currentArchiveId,archiveId);
  });
  await test('wide overview keeps every card in one row with the Windows minimum width and spacing',()=>{
    const {page}=harness();const {target}=page();
    target.poolCards=[301,302,200,500].map(gachaType=>({gachaType}));
    target.onPoolAreaChange(839.9,650);
    assert.equal(target.isWide,false);
    for(const [width,cardWidth] of [[840,302],[900,302],[1200,302],[1288,302],[1368,322]]){
      target.onPoolAreaChange(width,650);
      assert.equal(target.isWide,true);
      assert.equal(target.widePoolCardWidth(),cardWidth);
    }
    target.poolCards=target.poolCards.slice(0,3);
    target.onPoolAreaChange(970,480);
    assert.equal(target.widePoolCardWidth(),302);
    target.onPoolAreaChange(1000,480);
    assert.equal(target.widePoolCardWidth(),312);
    assert.equal(target.areaHeight,480);
    const overview=method('poolCardsArea');
    assert.match(overview,/else if \(this\.isWide\) \{\s*Scroll\(\) \{\s*Row\(\{ space: POOL_CARD_GAP \}\) \{\s*ForEach\(this\.poolCards/);
    assert.match(overview,/\.scrollable\(ScrollDirection\.Horizontal\)/);
    assert.match(overview,/else \{\s*Column\(\{ space: 10 \}\) \{\s*ForEach\(this\.poolCards/);
    assert.doesNotMatch(pageSource,/POOL_FOUR_COLUMN_VP|MAX_POOL_COLUMNS|poolRows\(|poolColumnsFor\(|gapSlots\(/);
  });
  await test('overview counters and statistics use content-sized rows inside the page scroll',()=>{
    const card=pageSource.slice(pageSource.indexOf('  poolCard(card: PoolCardData)'),pageSource.indexOf('  poolCardsArea()'));
    assert.doesNotMatch(card,/\b(?:Grid|GridItem)\(/);
    assert.match(card,/Row\(\{ space: 5 \}\) \{\s*if \(card\.gachaType !== GachaType\.UGC_STANDARD\) \{\s*this\.guaranteeBar/);
    assert.match(card,/if \(!this\.showsRatio\(card\.gachaType\)\) \{\s*Row\(\{ space: 4 \}\)/);
    assert.match(card,/\.layoutWeight\(1\)\s*\.height\(64\)/);
    assert.match(card,/if \(this\.isWide\) \{\s*Scroll\(\) \{\s*Column\(\) \{ this\.summaryArea\(card\) \}[\s\S]*?\.scrollable\(ScrollDirection\.Vertical\)[\s\S]*?\.layoutWeight\(1\)[\s\S]*?else \{\s*this\.summaryArea\(card\)/);
    assert.match(card,/\.height\(this\.isWide \? LayoutPolicy\.matchParent : LayoutPolicy\.wrapContent\)/);
  });
  await test('the fifth pivot mounts the offline featured history in its own viewport',()=>{
    assert.match(pageSource,/if \(!this\.beyondMode && this\.pivotIndex === 4[^\{]*\{\s*Column\(\) \{\s*WishHistoryPage\(\{ embedMode: true, showHeader: false \}\)\s*\}\.width\('100%'\)\.layoutWeight\(1\)\s*\} else \{\s*Scroll\(\)/);
    assert.match(pageSource,/this\.pivotIndex === 4 && !this\.vm\.isPreparingImport && !this\.vm\.isRefreshing/);
    assert.match(pageSource,/this\.pivotIndex === 5\) \{\s*this\.distributionPanel\(\)/);
    assert.doesNotMatch(pageSource,/countdownSection/);
    const routes=JSON.parse(fs.readFileSync(path.join(root,'../resources/base/profile/main_pages.json'),'utf8'));
    assert.ok(routes.src.includes('pages/WishHistoryPage'));
  });
  await test('production view-model and model graph pass strict host types with explicit service/platform doubles',strictModelTypes);
  await test('page UID checkboxes require confirmation and selected v4.2 export includes only checked archives',async()=>{
    const {state,model,page}=harness([]);const {target}=page();const source=JSON.parse(uigfFile(A));source.hk4e.push(JSON.parse(uigfFile(B)).hk4e[0]);state.text=JSON.stringify(source);
    await target.uigfImport();assert.equal(state.created.length,0);assert.equal(state.opens,state.closes,'preview does not retain an open input handle');target.changeUigfSelection(A,false,true);
    await target.confirmUigfImport();assert.deepEqual(state.archives.map(row=>row.uid),[B]);assert.equal(state.parseCalls,1);assert.equal(model.gameAccountUid,'');
    state.text=uigfFile(A);state.statCalls=0;await target.uigfImport();await target.confirmUigfImport();target.prepareUigfExport();target.changeUigfSelection(A,false,false);await target.uigfExport();
    assert.deepEqual(JSON.parse(state.writes[0]).hk4e.map(row=>String(row.uid)),[B]);assert.equal(state.parseCalls,2);
  });
  await test('cancel, a changed account and a canceled replacement picker cannot leave an old preview armed',async()=>{
    const {state,model,page}=harness([]);const {target}=page();state.text=uigfFile(C);await target.uigfImport();model.clearImport();target.showImportPreview=false;await target.confirmUigfImport();assert.equal(state.created.length,0);
    state.statCalls=0;await target.uigfImport();target.isLoggedIn=true;target.currentUid=A;target.onLoginStateChanged();await flush();assert.equal(target.showImportPreview,false);await target.confirmUigfImport();assert.equal(state.created.length,0);
    state.statCalls=0;await target.uigfImport();const gate=deferred();state.nextPicker=gate;const pending=target.uigfImport();gate.resolve([]);await pending;assert.equal(model.importPreview.archiveCount,0);assert.equal(target.showImportPreview,false);await target.confirmUigfImport();assert.equal(state.created.length,0);
  });
  await test('an input close failure clears its prepared confirmation instead of leaving a failed import armed',async()=>{
    const {state,model,page}=harness([]);const {target,toasts}=page();state.text=uigfFile(C);state.closeError=true;await target.uigfImport();
    assert.equal(state.created.length,0);assert.equal(model.importPreview.archiveCount,0);assert.equal(target.showImportPreview,false);assert.equal(model.isTransferring,false);assert.match(toasts[0],/无法读取或后台解析失败/);
  });
  await test('page exposes local controls without a login branch and binds refresh to the separate account',()=>{
    assert.doesNotMatch(pageSource,/loginGuide\(/);
    const build=method('build');assert.match(build,/PageToolbar\(\{ leading: \(\): void => this\.toolbarLeading\(\), trailing:/);
    assert.match(build,/PageToolbar\(\{ leading: \(\): void => this\.compactToolbar\(\)/);
    assert.doesNotMatch(build,/if \(!this\.isLoggedIn\)|localArchiveControls/);
    assert.match(method('toolbarActions'),/\.enabled\(this\.isLoggedIn && this\.vm\.gameAccountUid\.length > 0/);
    const picker=method('archivePicker');
    assert.match(picker,/Select\(this\.archiveOptions\(\)\)/);
    assert.match(picker,/\.font\(\{ size: 13 \}\)\.borderRadius\(6\)/);
    assert.match(picker,/\.value\(this\.vm\.currentUid\)/);
    assert.match(picker,/\.accessibilityDescription\(this\.vm\.currentUid\)/);
    assert.match(method('uigfImport'),/await this\.vm\.prepareImportFile\(uris\[0\]\)/);assert.match(fs.readFileSync(path.join(root,'viewmodel/GachaLogViewModel.ets'),'utf8'),/this\.load\(this\.gameAccountUid, result\.uid\)/);
    assert.doesNotMatch(fs.readFileSync(path.join(root,'viewmodel/GachaLogViewModel.ets'),'utf8'),/getOrCreateArchive/);
  });
  await test('toolbar menu keeps offline import and export enabled and ratio tabs are per-pool',async()=>{
    const {model,page}=harness();
    await model.load('');
    const {target}=page();
    assert.equal(target.isLoggedIn,false);
    const menu=target.archiveActions();
    assert.equal(menu.find(action=>action.value==='导入 UIGF').enabled,true);
    assert.equal(menu.find(action=>action.value==='导出 UIGF').enabled,true);
    target.setRatio(301,true);
    assert.equal(target.showsRatio(301),true);
    assert.equal(target.showsRatio(302),false);
    target.setRatio(302,true);
    target.setRatio(301,false);
    assert.deepEqual(plain(target.ratioPools),[302]);
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
