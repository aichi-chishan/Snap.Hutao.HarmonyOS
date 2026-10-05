// Production service/worker/preparation/repository/VM; native APIs are narrow host doubles.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const test=require('node:test'),ts=require(process.env.TYPESCRIPT_PATH||'../ci/node_modules/typescript');
const root=path.resolve(__dirname,'../entry/src/main/ets');
const {harness,A,B,C,big,row,section,file,plain}=require('./helpers/uigf-harness.cjs');
function strictGraphTypes(){
  const virtualRoot='/uigf-selection-types',files=new Map(),put=(name,text)=>files.set(virtualRoot+'/'+name+'.ts',text);
  for(const name of ['service/UigfService','service/UigfCodec','service/UigfExportCodec','model/UigfBounds','model/UigfError','data/repo/GachaRepo','model/GachaItem','model/GachaType','model/GachaArchive','model/UigfImportPreparation'])put(name,fs.readFileSync(path.join(root,name+'.ets'),'utf8'));
  put('common/Logger',`export class Logger{static info(tag:string,message:string):void{} static warn(tag:string,message:string):void{}}`);
  put('common/Constants',`export class AppConstants{static APP_VERSION:string='host';}`);
  put('data/db/RelationalStoreHelper',`import {relationalStore as r} from '@kit.ArkData';export class RelationalStoreHelper{
    static getStore():r.RdbStore{throw Error();}static async query(pred:r.RdbPredicates):Promise<r.ResultSet>{throw Error();}
    static async insert(table:string,value:r.ValuesBucket):Promise<number>{return 0;}static async batchInsert(table:string,rows:r.ValuesBucket[]):Promise<number>{return 0;}
    static async update(table:string,value:r.ValuesBucket,pred:r.RdbPredicates):Promise<number>{return 0;}static async delete(table:string,pred:r.RdbPredicates):Promise<number>{return 0;}}`);
  put('globals',`declare module '@kit.ArkData'{export namespace relationalStore{
    type ValuesBucket=Record<string,string|number|boolean|Uint8Array|null>;
    class RdbPredicates{constructor(table:string);equalTo(key:string,value:string|number):RdbPredicates;in(key:string,values:Array<string|number>):RdbPredicates;orderByAsc(key:string):RdbPredicates;orderByDesc(key:string):RdbPredicates;limitAs(value:number):RdbPredicates;offsetAs(value:number):RdbPredicates;}
    interface ResultSet{goToFirstRow():boolean;goToNextRow():boolean;getColumnIndex(key:string):number;getLong(index:number):number;getString(index:number):string;close():void;}
    interface RdbStore{beginTransaction():void;commit():void;rollBack():void;querySync(pred:RdbPredicates):ResultSet;insertSync(table:string,value:ValuesBucket):number;batchInsertSync(table:string,rows:ValuesBucket[]):number;deleteSync(pred:RdbPredicates):number;}
  }}`);
  const options={strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,skipLibCheck:true};
  const host=ts.createCompilerHost(options),base={fileExists:host.fileExists,readFile:host.readFile,getSourceFile:host.getSourceFile,directoryExists:host.directoryExists};
  host.fileExists=file=>files.has(file)||base.fileExists(file);host.readFile=file=>files.get(file)??base.readFile(file);
  host.getSourceFile=(file,version,...rest)=>files.has(file)?ts.createSourceFile(file,files.get(file),version,true):base.getSourceFile(file,version,...rest);
  host.directoryExists=directory=>[...files.keys()].some(file=>file.startsWith(directory+'/'))||base.directoryExists(directory);
  const diagnostics=ts.getPreEmitDiagnostics(ts.createProgram([...files.keys()],options,host));
  assert.equal(diagnostics.length,0,diagnostics.map(value=>ts.flattenDiagnosticMessageText(value.messageText,'\n')).join('\n'));
}
(async()=>{
  await test('all seven input versions retain preview, exact string cursor and normalized data with one parse',async()=>{
    const {state,service}=harness();
    for(const version of ['v2.2','v2.3','v2.4','v3.0','v4.0','v4.1','v4.2']){
      const text=version.startsWith('v4.')?JSON.stringify({info:{version},hk4e:[section(A,[row(version.slice(1).replace('.',''))])]}):JSON.stringify({info:{uid:A,uigf_version:version,region_time_zone:8},list:[row(version.slice(1).replace('.',''))]});
      const before=state.parseCalls,prepared=service.prepareImport(text);assert.equal(prepared.preview().version,version);assert.equal(prepared.preview().totalCount,1);assert.equal(state.parseCalls,before+1);
      assert.equal((await service.importPrepared(prepared,[A])).ok,true);assert.equal(state.parseCalls,before+1,'confirmation does not parse');prepared.dispose();
    }
  });
  await test('preview merges repeated UID sections/partitions and counts exact duplicate records once without writes',()=>{
    const {state,service}=harness();const ugc={id:big,op_gacha_type:1000,item_id:10001,rank_type:5,schedule_id:20,count:3,item_name:'beyond',time:'2026-10-05 10:00:00'};
    const prepared=service.prepareImport(file([section(A,[row(),row()]),section(A,[row('2')]),section(B,[])],[section(A,[ugc])]));
    const preview=prepared.preview();assert.equal(preview.archiveCount,2);assert.equal(preview.totalCount,3);assert.equal(preview.archives[0].standardCount,2);assert.equal(preview.archives[0].beyondCount,1);assert.equal(state.begins,0);
    preview.uids.push(C);preview.archives[0].uid=C;assert.deepEqual(plain(prepared.preview().uids),[A,B]);assert.throws(()=>prepared.select([C]),/所选 UID/);
  });
  await test('explicit UID selection commits only selected archives in one transaction and repeat imports are idempotent',async()=>{
    const {state,service,snapshot}=harness();const prepared=service.prepareImport(file([section(A,[row()]),section(B,[row('2')])]));
    const original=JSON.stringify([...prepared.select()]);const result=await service.importPrepared(prepared,[B,B]);assert.equal(result.ok,true);assert.equal(result.archiveCount,1);assert.equal(result.inserted,1);assert.equal(result.uid,B);
    assert.deepEqual(snapshot().archives.map(row=>row.uid),[B]);assert.equal(state.begins,1);assert.equal(state.commits,1);assert.equal(state.rollbacks,0);assert.equal(JSON.stringify([...prepared.select()]),original,'repository never assigns archiveId into preparation');
    assert.equal((await service.importPrepared(prepared,[B])).inserted,0);assert.equal(state.resultSets,state.closedSets);
  });
  await test('empty/unknown selections and invalidated preparation fail without database writes',async()=>{
    const {state,service}=harness();const prepared=service.prepareImport(file());
    for(const selection of [[],[B]]){const result=await service.importPrepared(prepared,selection);assert.equal(result.ok,false);assert.equal(result.inserted,0);assert.equal(result.archiveCount,0);}
    prepared.dispose();const result=await service.importPrepared(prepared,[A]);assert.equal(result.ok,false);assert.match(result.message,/失效/);assert.equal(state.begins,0);
  });
  await test('malformed and conflicting unselected UID records fail full-file validation before any write',async()=>{
    const {state,service}=harness();const bad=[
      file([section(A,[row()]),section(B,[row('2',{time:'2026-02-30 00:00:00'})])]),
      file([section(A,[row()]),section(B,[row('2'),row('2',{name:'conflict'})])]),
      file([section(A,[row()]),section(B,[row('2',{uid:C})])]),
      file([section(A,[row()]),section(B,[row('2',{uigf_gacha_type:302})])])
    ];
    for(const text of bad){const result=await service.importFromText(text,[A]);assert.equal(result.ok,false);assert.equal(result.inserted,0);}
    assert.equal(state.begins,0);
  });
  await test('second-archive errors, short writes and archive creation failures roll back all selected changes',async()=>{
    for(const mode of ['error','short','archive']){
      const {state,service,snapshot}=harness();await service.importFromText(file([section(A,[row('99')])]));const before=plain(snapshot());
      const prepared=service.prepareImport(file([section(A,[row('1')]),section(B,[row('2')])]));
      if(mode==='error')state.failBatch=state.batches+2;else if(mode==='short')state.shortBatch=state.batches+2;else state.failArchive=Number(B);
      const result=await service.importPrepared(prepared);assert.equal(result.ok,false);assert.equal(result.inserted,0);assert.equal(result.archiveCount,0);assert.deepEqual(plain(snapshot()),before);assert.equal(state.rollbacks,1);assert.equal(state.resultSets,state.closedSets);
      state.failBatch=0;state.shortBatch=0;state.failArchive=0;const parses=state.parseCalls;assert.equal((await service.importPrepared(prepared)).inserted,2);assert.equal(state.parseCalls,parses,'retry uses retained validated data');
    }
  });
  await test('500-row batches remain in one transaction and a later short batch rolls everything back',async()=>{
    const {state,service,snapshot}=harness();const prepared=service.prepareImport(file([section(A,Array.from({length:1001},(_,i)=>row(String(i+1))))]));state.shortBatch=3;
    assert.equal((await service.importPrepared(prepared)).ok,false);assert.equal(state.begins,1);assert.equal(state.commits,0);assert.equal(state.rollbacks,1);assert.equal(snapshot().archives.length,0);assert.equal(snapshot().items.length,0);
  });
  await test('selected v4.2 export reads only selected archives and preserves Beyond quantity/domain and server time',async()=>{
    const {state,service,snapshot}=harness();const ugc={id:big,op_gacha_type:2000,item_id:10001,rank_type:5,schedule_id:123,count:3,item_name:'beyond',time:'2026-10-05 10:00:00'};
    await service.importFromText(file([section(A,[row('1')]),section(B,[row()])],[section(B,[ugc])]));
    state.readIds=[];const output=await service.buildExportJson([B]);const root=JSON.parse(output),archive=snapshot().archives.find(row=>row.uid===B);
    assert.equal(root.info.version,'v4.2');assert.deepEqual(root.hk4e.map(row=>String(row.uid)),[B]);assert.deepEqual(root.hk4e_ugc.map(row=>String(row.uid)),[B]);assert.deepEqual(state.readIds,[archive.id]);
    assert.equal(root.hk4e[0].list[0].id,big);assert.equal(root.hk4e[0].list[0].gacha_type,'400');assert.equal(root.hk4e[0].list[0].uigf_gacha_type,'301');assert.equal(root.hk4e[0].list[0].time,'2026-10-05 03:00:00');
    assert.equal(root.hk4e_ugc[0].list[0].count,'3');assert.equal(root.hk4e_ugc[0].list[0].schedule_id,'123');assert.equal((await service.importFromText(output)).inserted,0);
  });
  await test('selected export refuses empty/unknown UID selection and retains intentionally empty archives',async()=>{
    const {state,service}=harness();await service.importFromText(file([section(A,[]),section(B,[row()])]));state.readIds=[];
    await assert.rejects(service.buildExportJson([]),/至少选择/);await assert.rejects(service.buildExportJson([C]),/所选 UID/);assert.equal(state.readIds.length,0);
    const output=JSON.parse(await service.buildExportJson([A]));assert.equal(String(output.hk4e[0].uid),A);assert.equal(output.hk4e[0].list.length,0);
  });
  await test('preparation limits are explicit, reject empty files and release all retained rows on dispose',()=>{
    const {service,Preparation}=harness();assert.throws(()=>service.prepareImport(''),/为空/);assert.throws(()=>service.prepareImport(' '.repeat(Preparation.MAX_TEXT_CODE_UNITS+1)),/限制/);
    const text=file(Array.from({length:1025},(_,i)=>section(String(100000000+i),[])));assert.throws(()=>service.prepareImport(text),/1024/);
    const prepared=service.prepareImport(file());prepared.dispose();assert.equal(prepared.archives.size,0);assert.throws(()=>prepared.preview(),/失效/);assert.throws(()=>service.prepareImport(file([])),/没有可导入/);
  });
  await test('account/page/new-file cancellation clears retained confirmation and never promotes imported UID to login authority',async()=>{
    const {state,Model}=harness();const model=new Model();await model.load(A);await model.prepareImport(file([section(B,[row()]) ]));assert.equal(state.begins,0);const prepared=model.preparedImport;
    model.clearImport();assert.equal(prepared.archives.size,0);await assert.rejects(model.confirmImport(),/预览/);assert.equal(state.begins,0);
    await model.prepareImport(file([section(B,[row()]) ]));await model.load('');await assert.rejects(model.confirmImport(),/预览/);
    await model.prepareImport(file([section(B,[row()]) ]));model.invalidateRequests();await assert.rejects(model.confirmImport(),/预览/);
    await model.prepareImport(file([section(B,[row()]) ]));await model.prepareImport(file([section(C,[row('2')]) ]));const count=state.parseCalls;const result=await model.confirmImport();assert.equal(result.ok,true);assert.equal(state.parseCalls,count);assert.equal(model.currentUid,C);assert.equal(model.gameAccountUid,'');assert.equal(model.importPreview.archiveCount,0);
  });
  await test('owner fence runs before transaction and a committed stale result cannot clear a newer preview',async()=>{
    const {state,service,Model}=harness();const prepared=service.prepareImport(file());assert.equal((await service.importPrepared(prepared,[A],()=>{throw Error('owner changed');})).ok,false);assert.equal(state.begins,0);
    const model=new Model();await model.prepareImport(file());const pending=model.confirmImport();model.invalidateRequests();await model.prepareImport(file([section(B,[row('2')]) ]));assert.equal((await pending).ok,true);assert.deepEqual(plain(model.importUids),[B]);assert.equal(model.importPreview.archiveCount,1);assert.equal(state.changes.length,1);
  });
  await test('post-commit view reload failure keeps the successful import result truthful',async()=>{
    const {Model,snapshot}=harness();const model=new Model();await model.prepareImport(file());model.load=async()=>{throw Error('view failed');};const result=await model.confirmImport();assert.equal(result.ok,true);assert.equal(result.inserted,1);assert.match(result.message,/重新打开页面/);assert.equal(snapshot().items.length,1);
  });
  await test('malformed scalar containers never masquerade as valid UID, version, dates or numbers',()=>{
    const {service,state}=harness();
    for(const extra of [{id:[big]},{gacha_type:[400]},{item_id:true},{count:true},{time:['2026-10-05 10:00:00']},{name:{value:'fixture'}},{item_type:['角色']}])assert.throws(()=>service.prepareImport(file([section(A,[row('1',extra)])])));
    assert.throws(()=>service.prepareImport(file([section([A],[row()])])));
    assert.throws(()=>service.prepareImport(JSON.stringify({info:{version:['v4.2']},hk4e:[section(A,[row()])]})));
    assert.equal(state.begins,0);
  });
  await test('service/model/repository graph passes strict host types with explicit RDB declarations',strictGraphTypes);
  await test('new UID controls expose readable names, visible counts and minimum44vp target constraints',()=>{
    const page=fs.readFileSync(path.join(root,'pages/GachaLogPage.ets'),'utf8');const panels=page.slice(page.indexOf('  importPreviewPanel()'),page.indexOf('  urlInputPanel()'));
    assert.match(panels,/accessibilityText\(`导入 UID \$\{archive\.uid\}，\$\{archive\.totalCount\} 条记录`\)/);
    assert.match(panels,/accessibilityText\(`导出 UID \$\{archive\.uid\}`\)/);
    assert.equal((panels.match(/\.width\(44\)\.height\(44\)/g)||[]).length,2);
    assert.doesNotMatch(panels,/\.height\(32\)/);assert.match(panels,/Flex\(\{ wrap: FlexWrap\.Wrap \}\)/);
    assert.match(panels,/\$\{archive\.totalCount\} 条（颂愿 \$\{archive\.beyondCount\}）/);
  });
  await test('confirmation source has no reparse and repository transaction contains no await',()=>{
    const service=fs.readFileSync(path.join(root,'service/UigfService.ets'),'utf8');const method=service.slice(service.indexOf('  async importPrepared('),service.indexOf('  /** Backwards-compatible'));
    assert.doesNotMatch(method,/JSON\.parse|prepareImport\(/);
    const repo=fs.readFileSync(path.join(root,'data/repo/GachaRepo.ets'),'utf8');const transaction=repo.slice(repo.indexOf('  static async importArchives('),repo.indexOf('  private static importKey('));assert.doesNotMatch(transaction,/\bawait\b/);
    const page=fs.readFileSync(path.join(root,'pages/GachaLogPage.ets'),'utf8');assert.match(page,/this\.importPreviewPanel\(\)/);assert.match(page,/this\.exportOptionsPanel\(\)/);assert.match(page,/buildExportJson\(this\.vm\.exportUids\.slice\(\), this\.vm\.exportVersion\)/);
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
