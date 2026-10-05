// Executes production worker, primitive codec, hydration, VM and SQLite transaction under SDK doubles.
// Native API/ArkTS compilation belongs to the coordinated native build; device scheduling is not simulated.
const assert=require('node:assert/strict'),test=require('node:test'),fs=require('node:fs'),path=require('node:path');
const {harness,A,B,C,big,row,section,file,plain}=require('./helpers/uigf-harness.cjs');
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
const flush=async()=>{for(let i=0;i<30;i++)await Promise.resolve();};
(async()=>{
  await test('file URI alone reaches worker; stat/read/fatal decode/parse happen once with no writes before confirmation',async()=>{
    const {state,Model,snapshot}=harness();state.text=file([section(A,[row()]),section(B,[row('2')])]);const model=new Model();
    assert.equal(await model.prepareImportFile('/picked.json'),true);assert.equal(state.workerStarts,1);assert.equal(state.workerParseCalls,1);assert.equal(state.parseCalls,1);
    assert.equal(state.lastTask.args[0],'/picked.json');assert.equal(state.lastTask.args[1],true);assert.equal(state.opens,1);assert.equal(state.closes,1);assert.equal(state.begins,0);
    assert.equal(Object.values(model.preparedImport).includes(state.text),false);model.importUids=[B];
    assert.equal((await model.confirmImport()).ok,true);assert.equal(state.parseCalls,1);assert.equal(state.begins,1);assert.deepEqual(snapshot().archives.map(x=>x.uid),[B]);
  });
  await test('cancel rejects waiting owner but holds global admission until native task settles',async()=>{
    const {state,Model}=harness();const gate=deferred();state.workerGate=gate;const first=new Model(),second=new Model();
    const pending=first.prepareImport(file());first.clearImport();assert.equal(await pending,false);assert.equal(state.workerCancels,1);
    await assert.rejects(second.prepareImport(file()),/仍在处理/);assert.equal(state.workerStarts,1);assert.equal(state.parseCalls,0);
    state.workerGate=undefined;gate.resolve();await flush();assert.equal(await second.prepareImport(file([section(B,[row('2')])])),true);assert.deepEqual(plain(second.importUids),[B]);assert.equal(first.importPreview.archiveCount,0);assert.equal(state.begins,0);
  });
  await test('account change and page invalidation fence late results and cannot arm an import',async()=>{
    for(const change of ['account','detach']){
      const {state,Model}=harness();const model=new Model();await model.load(A);const gate=deferred();state.workerGate=gate;const pending=model.prepareImport(file());
      if(change==='account')await model.load(B);else model.invalidateRequests();assert.equal(await pending,false);gate.resolve();await flush();assert.equal(model.importPreview.archiveCount,0);await assert.rejects(model.confirmImport(),/预览/);assert.equal(state.begins,0);
    }
  });
  await test('cancel during sliced hydration clears partial preparation and never parses on confirmation',async()=>{
    const {state,Model}=harness();const model=new Model();const pending=model.prepareImport(file([section(A,Array.from({length:900},(_,i)=>row(String(i+1))))]));
    setTimeout(()=>model.clearImport(),0);assert.equal(await pending,false);await new Promise(resolve=>setTimeout(resolve,5));
    assert.equal(model.preparedImport,undefined);assert.equal(model.importPreview.archiveCount,0);assert.equal(state.workerParseCalls,1);assert.equal(state.begins,0);
    assert.equal(await model.prepareImport(file()),true);assert.equal((await model.confirmImport()).ok,true);assert.equal(state.parseCalls,2);
  });
  await test('worker startup/rejection never falls back to foreground parsing and releases admission',async()=>{
    const {state,Model}=harness();const model=new Model();state.workerFailure=true;
    await assert.rejects(model.prepareImport(file()),/后台任务失败/);assert.equal(state.parseCalls,0);assert.equal(state.begins,0);state.workerFailure=false;
    assert.equal(await model.prepareImport(file()),true);assert.equal(state.workerParseCalls,1);
  });
  await test('deadline ends waiting without prematurely admitting a second native task',async()=>{
    const {state,Model,load}=harness();const Bounds=load('model/UigfBounds').UigfBounds;const previous=Bounds.WAIT_MS;Bounds.WAIT_MS=5;
    const gate=deferred();state.workerGate=gate;const model=new Model();await assert.rejects(model.prepareImport(file()),/超时/);
    await assert.rejects(model.prepareImport(file()),/仍在处理/);assert.equal(state.workerStarts,1);assert.equal(state.begins,0);
    gate.resolve();await flush();state.workerGate=undefined;Bounds.WAIT_MS=previous;assert.equal(await model.prepareImport(file()),true);
  });
  await test('invalid UTF8 and provider errors close files and return bounded localized messages without raw paths',async()=>{
    const {state,Model}=harness();state.bytes=Buffer.from([0x7b,0xc3,0x28,0x7d]);const model=new Model();
    await assert.rejects(model.prepareImportFile('/private/invalid.json'),/有效的 UTF-8/);assert.equal(state.opens,state.closes);assert.equal(state.parseCalls,0);
    state.bytes=undefined;state.text=file();state.statCalls=0;state.closeError=true;state.closeMessage='文档权限失败 /private/provider/token';
    await assert.rejects(model.prepareImportFile('/private/invalid.json'),/无法读取或后台解析失败/);assert.equal(state.opens,state.closes);assert.equal(state.parseCalls,0);
  });
  await test('preflight rejects depth, malformed JSON, unknown versions and size before any database access',async()=>{
    const {Model,state,load}=harness();const Bounds=load('model/UigfBounds').UigfBounds;assert.equal(Bounds.MAX_DEPTH,32);assert.equal(Bounds.MAX_ROWS,262144);assert.equal(Bounds.MAX_WIRE_UNITS,48*1024*1024);
    const model=new Model();for(const text of ['['.repeat(33)+']'.repeat(33),'{',file().replace('v4.2','v99.0'),' '.repeat(Bounds.MAX_TEXT_UNITS+1)])await assert.rejects(model.prepareImport(text));
    assert.equal(state.begins,0);const quoted=row('7',{name:'\\\"[[]]{}'});assert.equal(await model.prepareImport(file([section(A,[quoted])])),true);
  });
  await test('row limits count raw duplicates; oversized fields and UID-count limits fail before writes',async()=>{
    const {service,state,load}=harness();const Bounds=load('model/UigfBounds').UigfBounds,limit=Bounds.MAX_ROWS;Bounds.MAX_ROWS=2;
    assert.throws(()=>service.prepareImport(file([section(A,[row(),row(),row()])])),/原始记录/);Bounds.MAX_ROWS=limit;
    assert.throws(()=>service.prepareImport(file([section(A,[row('1',{name:'x'.repeat(4097)})])])),/4096/);
    assert.throws(()=>service.prepareImport(file(Array.from({length:1025},(_,i)=>section(String(100000000+i),[])))),/1024/);assert.equal(state.begins,0);
  });
  await test('primitive envelope rejects malformed headers, unknown versions, invalid numbers and duplicate UIDs/rows',async()=>{
    const {service,load}=harness();const Transfer=load('service/UigfImportTransfer').UigfImportTransfer;
    const wire=Transfer.encode(service.prepareImport(file()),()=>{});assert.ok(wire.every(x=>typeof x==='string'));
    const invalid=[[],['uigf-error-2',42],['uigf-error-2','x'.repeat(513)],[...wire,'extra'],['wrong',...wire.slice(1)],wire.map((x,i)=>i===1?'v9.0':x),wire.map((x,i)=>i===2?'01':x),wire.map((x,i)=>i===7?'0':x),wire.map((x,i)=>i===9?'2026-02-30 10:00:00':x)];
    for(const value of invalid)await assert.rejects(Transfer.adopt(value,()=>{}));
    const duplicateUid=[...wire];duplicateUid[2]='2';duplicateUid.push(...wire.slice(3));await assert.rejects(Transfer.adopt(duplicateUid,()=>{}),/后台结果/);
    const duplicateRow=[...wire];duplicateRow[4]='2';duplicateRow.push(...wire.slice(5));await assert.rejects(Transfer.adopt(duplicateRow,()=>{}),/重复记录/);
    const restored=await Transfer.adopt(wire,()=>{});assert.equal(restored.preview().totalCount,1);assert.equal(restored.select().get(A)[0].rankStars(),'★★★★★');
  });
  await test('wire budget and owner checks apply again during hydration without a second JSON parse',async()=>{
    const {service,load,state}=harness(),Transfer=load('service/UigfImportTransfer').UigfImportTransfer,Bounds=load('model/UigfBounds').UigfBounds;
    const prepared=service.prepareImport(file()),wire=Transfer.encode(prepared,()=>{}),before=state.parseCalls,limit=Bounds.MAX_WIRE_UNITS;Bounds.MAX_WIRE_UNITS=70;
    assert.throws(()=>Transfer.encode(prepared,()=>{}),/传输/);await assert.rejects(Transfer.adopt(wire,()=>{}),/传输/);Bounds.MAX_WIRE_UNITS=limit;
    await assert.rejects(Transfer.adopt(wire,()=>{throw Error('owner expired');}),/owner expired/);assert.equal(state.parseCalls,before);
  });
  await test('all seven exporters roundtrip normalized records and use schema string item IDs',async()=>{
    const {service,snapshot}=harness();await service.importFromText(file([section(A,[row('123',{name:'试作武器',item_type:'武器'})])]));
    const expected=plain(snapshot());for(const version of ['v2.2','v2.3','v2.4','v3.0','v4.0','v4.1','v4.2']){
      const output=await service.buildExportJson([A],version),root=JSON.parse(output),legacy=!version.startsWith('v4.');assert.equal(legacy?root.info.uigf_version:root.info.version,version);
      const records=legacy?root.list:root.hk4e[0].list;assert.equal(typeof records[0].item_id,'string');assert.equal(records[0].gacha_type,'400');assert.equal(records[0].uigf_gacha_type,'301');
      if(legacy){assert.equal(typeof root.info.uid,'string');assert.equal('region_time_zone' in root.info,['v2.4','v3.0'].includes(version));}
      else assert.equal('hk4e_ugc' in root,version==='v4.2');
      assert.equal((await service.importFromText(output)).inserted,0);assert.deepEqual(plain(snapshot()),expected);
    }
  });
  await test('legacy exports refuse multiUID, Beyond, pre-v3 Chronicled and unverified v2.2 language',async()=>{
    const {service}=harness();await service.importFromText(file([section(A,[row('1',{gacha_type:500,uigf_gacha_type:500})]),section(B,[row('2')])]));
    for(const version of ['v2.2','v2.3','v2.4','v3.0'])await assert.rejects(service.buildExportJson([A,B],version),/单个 UID/);
    for(const version of ['v2.2','v2.3','v2.4'])await assert.rejects(service.buildExportJson([A],version),/集录祈愿/);
    await assert.rejects(service.buildExportJson([B],'v2.2'),/语言/);assert.equal(JSON.parse(await service.buildExportJson([A],'v3.0')).list[0].gacha_type,'500');
    await service.importFromText(file([],[section(C,[{id:'3',op_gacha_type:'1000',item_id:10001,item_type:'装扮',item_name:'试验',rank_type:'5',time:'2026-10-05 10:00:00',schedule_id:7}])]));
    for(const version of ['v2.2','v2.3','v2.4','v3.0','v4.0','v4.1'])await assert.rejects(service.buildExportJson([C],version),/不支持颂愿/);
  });
  await test('export refuses unsupported optional fields, noncanonical timezone text and overlong v4 cursors',async()=>{
    const {service,load}=harness();const Export=load('service/UigfExportCodec').UigfExportCodec;
    const prepared=service.prepareImport(file([section(A,[row('184467440737095516151234')])])),records=prepared.select(),item=records.get(A)[0];assert.equal(item.gachaId,'184467440737095516151234');
    assert.throws(()=>Export.build(records,'v4.2','test'),/19 位/);assert.equal(JSON.parse(Export.build(records,'v3.0','test')).list[0].id,item.gachaId);
    item.gachaId='1';item.scheduleId=7;assert.throws(()=>Export.build(records,'v3.0','test'),/期次/);item.scheduleId=0;
    item.time='2026-10-05T10:00:00+08:00';assert.throws(()=>Export.build(records,'v2.4','test'),/本地时间/);item.time='2026-10-05 10:00:00';
    item.future_field=1;assert.throws(()=>Export.build(records,'v3.0','test'),/未支持字段/);delete item.future_field;
    assert.throws(()=>Export.build(records,'v8.0','test'),/不支持/);
  });
  await test('worker preparation preserves real SQLite all-selected rollback and retry uses retained records',async()=>{
    const {state,Model,snapshot}=harness(),model=new Model();await model.prepareImport(file([section(A,[row('1')]),section(B,[row('2')])]));state.failBatch=2;
    assert.equal((await model.confirmImport()).ok,false);assert.equal(snapshot().archives.length,0);assert.equal(state.rollbacks,1);assert.equal(state.parseCalls,1);
    state.failBatch=0;assert.equal((await model.confirmImport()).ok,true);assert.equal(snapshot().items.length,2);assert.equal(state.parseCalls,1);assert.equal(state.commits,1);
  });
  await test('production code uses real @Concurrent Task/execute/cancel and worker has no database import',()=>{
    const root=path.resolve(__dirname,'../entry/src/main/ets'),worker=fs.readFileSync(path.join(root,'data/taskpool/UigfImportWorker.ets'),'utf8'),job=fs.readFileSync(path.join(root,'service/UigfImportJob.ets'),'utf8'),page=fs.readFileSync(path.join(root,'pages/GachaLogPage.ets'),'utf8');
    assert.match(worker,/@Concurrent\s+export function/);assert.match(worker,/fatal: true/);assert.doesNotMatch(worker,/GachaRepo|RelationalStore|AppStorage/);assert.match(job,/new taskpool\.Task\(prepareUigfImport, source, isFile, deadline\)/);assert.match(job,/taskpool\.execute\(this\.task\)/);assert.match(job,/taskpool\.cancel\(this\.task\)/);
    const method=page.slice(page.indexOf('  async uigfImport()'),page.indexOf('  async uigfExport()'));assert.doesNotMatch(method,/JSON\.parse|readSync|TextDecoder|ArrayBuffer/);assert.match(method,/await this\.vm\.prepareImportFile/);
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
