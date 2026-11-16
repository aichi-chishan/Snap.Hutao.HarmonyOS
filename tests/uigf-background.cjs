// Executes production worker, primitive codec, hydration, VM and SQLite transaction under SDK doubles.
// Native API/ArkTS compilation belongs to the coordinated native build; device scheduling is not simulated.
const assert=require('node:assert/strict'),test=require('node:test'),fs=require('node:fs'),path=require('node:path');
const {harness,A,B,C,big,row,section,file,plain,seedItems}=require('./helpers/uigf-harness.cjs');
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
      if(legacy){assert.equal(typeof root.info.uid,'string');assert.equal(root.info.region_time_zone,8);}
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
  await test('export refuses out-of-range Windows IDs in legacy and modern files',async()=>{
    const {service,load}=harness();const Export=load('service/UigfExportCodec').UigfExportCodec;
    const prepared=service.prepareImport(file([section(A,[row('184467440737095516151234')])])),records=prepared.select(),item=records.get(A)[0];assert.equal(item.gachaId,'184467440737095516151234');
    for(const version of ['v3.0','v4.2']){
      for(const id of ['184467440737095516151234','9223372036854775808','9223372036854775807']){
        item.gachaId=id;
        assert.throws(()=>Export.build(records,version,'test'),/祈愿 ID 超出/);
      }
      item.gachaId='9223372036854775806';
      const output=JSON.parse(Export.build(records,version,'test'));
      assert.equal((output.list??output.hk4e[0].list)[0].id,item.gachaId);
    }
    assert.throws(()=>Export.build(new Map([['4294967296',[]]]),'v4.2','test'),/UID 超出/);
    item.itemId=4294967296;assert.throws(()=>Export.build(records,'v4.2','test'),/物品 ID 超出/);
  });
  await test('export refuses unsupported optional fields and noncanonical timezone text',async()=>{
    const {service,load}=harness();const Export=load('service/UigfExportCodec').UigfExportCodec;
    const records=service.prepareImport(file()).select(),item=records.get(A)[0];
    item.gachaId='1';item.scheduleId=7;assert.throws(()=>Export.build(records,'v3.0','test'),/期次/);item.scheduleId=0;
    item.time='2026-10-05T10:00:00+08:00';assert.throws(()=>Export.build(records,'v2.4','test'),/本地时间/);item.time='2026-10-05 10:00:00';
    item.future_field=1;assert.throws(()=>Export.build(records,'v3.0','test'),/未支持字段/);delete item.future_field;
    assert.throws(()=>Export.build(records,'v8.0','test'),/不支持/);
  });
  await test('export reports the precise invalid stored fields and leaves the record intact',()=>{
    const {service,load}=harness();
    const Export=load('service/UigfExportCodec').UigfExportCodec;
    const records=service.prepareImport(file()).select(),item=records.get(A)[0];
    item.gachaId='1757085600000214319';item.itemId=0;item.count=0;item.rankType=2;item.scheduleId=-1;
    assert.throws(()=>Export.build(records,'v4.2','test'),
      /1757085600000214319.*item_id=0.*count=0.*rank_type=2.*schedule_id=-1/);
    assert.equal(records.get(A).length,1);
  });
  await test('legacy API rows with blank IDs export through SQLite using exact canonical and translated identities',async()=>{
    const {service,load,state,repo,snapshot}=harness();
    const Item=load('model/GachaItem').GachaItem;
    const archive=await repo.getOrCreateArchive(A);
    const rows=[
      Item.fromServer(row('1757085600000214319',{uid:A,item_id:'',name:'刻晴'})),
      Item.fromServer(row('1757085600000214320',{uid:A,item_id:'',name:'Keqing',item_type:'Character'})),
      Item.fromServer(row('1757085600000214321',{uid:A,item_id:'',name:'黎明神剑',item_type:'武器',rank_type:'3'})),
      Item.fromServer(row('1757085600000214322',{uid:A,item_id:10000011,name:'刻晴'})),
    ];
    for(const item of rows)item.archiveId=archive.id;
    await repo.insertItems(rows);
    const before=snapshot();
    assert.deepEqual(before.items.map(item=>item.item_id),[0,0,0,10000011]);
    state.avatarMetadata=[{id:10000042,canonicalName:'刻晴',name:'刻晴',quality:5}];
    state.weaponMetadata=[{id:11302,canonicalName:'黎明神剑',name:'黎明神剑',rankLevel:3}];
    state.names.set('avatar_meta.json:en',new Map([[10000042,'Keqing']]));
    const output=JSON.parse(await service.buildExportJson([A]));
    assert.deepEqual(output.hk4e[0].list.map(item=>[item.id,item.item_id,item.rank_type]),[
      ['1757085600000214319','10000042','5'],['1757085600000214320','10000042','5'],
      ['1757085600000214321','11302','3'],['1757085600000214322','10000011','5'],
    ]);
    assert.equal(output.hk4e[0].list[1].name,'Keqing');
    assert.ok(state.languageReads.includes('avatar_meta.json:en'));
    assert.ok(!state.languageReads.some(value=>value.endsWith(':de')));
    assert.deepEqual(snapshot(),before);
  });
  await test('export snapshot and preview share logical rows while original SQLite duplicates remain intact',async()=>{
    const {load,state,service,repo,snapshot,db}=harness();
    const Item=load('model/GachaItem').GachaItem;
    const first=await repo.getOrCreateArchive(A),second=await repo.getOrCreateArchive(B);
    const shared='1793884800001694719';
    const regular=Item.fromServer(row(shared,{uid:A}));
    const weapon=Item.fromServer(row('1793884800001694720',{uid:A,gacha_type:'302',item_id:'11501'}));
    const beyond=Item.fromServer({id:shared,uid:A,op_gacha_type:'20011',item_id:'250013',
      item_type:'装扮',item_name:'服饰',rank_type:'2',schedule_id:'7',time:'2026-10-05 10:00:00'},true);
    const other=Item.fromServer(row(shared,{uid:B}));
    for(const item of [regular,weapon,beyond])item.archiveId=first.id;
    other.archiveId=second.id;
    seedItems(db,[regular,regular,weapon,beyond,beyond,other]);
    const before=snapshot();
    const text=await service.buildExportJson([A,B]);
    const exported=JSON.parse(text);
    assert.deepEqual(exported.hk4e.map(entry=>entry.list.length),[2,1]);
    assert.deepEqual(exported.hk4e_ugc.map(entry=>entry.list.length),[1]);
    assert.equal(service.prepareImport(text).preview().totalCount,4);
    const log=state.logs.find(([tag,message])=>tag==='UigfService'&&message.startsWith('export snapshot'))?.[1];
    assert.equal(log,'export snapshot archives=2 rows=4 unique=4 standard=3/3 beyond=1/1 pools=100:0/0,200:0/0,301:2/2,302:1/1,500:0/0,1000:0/0,2000:1/1');
    assert.deepEqual(snapshot(),before);
  });
  await test('one archive projection gives the same logical statistics and history as separate SQLite queries',async()=>{
    const {load,state,repo,Model,snapshot,db}=harness();
    const Item=load('model/GachaItem').GachaItem;
    const Type=load('model/GachaType').GachaType;
    const Identity=load('service/GachaItemIdentityService').GachaItemIdentityService;
    const Statistics=load('service/GachaStatisticsService').GachaStatisticsService;
    const Collection=load('service/GachaCollectionService').GachaCollectionService;
    const archive=await repo.getOrCreateArchive(A);
    const cursor='1793884800001694720';
    const role=Item.fromServer(row(cursor,{uid:A,gacha_type:'301',item_id:'',name:'刻晴',
      time:'2026-10-05 10:00:00',count:'2'}));
    const role2=Item.fromServer(row('1793884800001694723',{uid:A,item_id:'',name:'刻晴',time:'2026-10-05 10:01:00'}));
    const weapon=Item.fromServer(row('1793884800001694721',{uid:A,gacha_type:'302',item_type:'武器',
      name:'风鹰剑',item_id:'11501'}));
    const beyond=(id,type,rank)=>Item.fromServer({id,uid:A,op_gacha_type:String(type),item_id:'250013',
      item_type:'装扮',item_name:'服饰',rank_type:String(rank),schedule_id:'7',time:'2026-10-05 10:00:00'},true);
    const stored=[role,role2,role2,weapon,beyond(cursor,20011,5),beyond('1793884800001694722',20022,4)];
    for(const item of stored)item.archiveId=archive.id;
    seedItems(db,stored);
    const before=snapshot();
    state.avatarMetadata=[{id:10000042,canonicalName:'刻晴',name:'刻晴',quality:5,icon:'avatar'}];
    state.weaponMetadata=[{id:11501,canonicalName:'风鹰剑',name:'风鹰剑',rankLevel:5,icon:'weapon'}];
    state.wishEvents=[301,400].map(type=>({type,from:Date.parse('2026-10-05T00:00:00Z'),
      to:Date.parse('2026-10-06T00:00:00Z'),upOrange:[10000042],upPurple:[]}));
    const expectedPools=[];
    for(const type of Type.QUERY_ORDER.concat(Type.BEYOND_ORDER)){
      const rows=await Identity.resolveMissing(await repo.getItemsByType(archive.id,type));
      expectedPools.push(Statistics.buildPool(rows,type,state.wishEvents,8));
    }
    const expectedCollection=Collection.count(await Identity.resolveMissing(await repo.getItemsByArchive(archive.id)),
      state.avatarMetadata,state.weaponMetadata,state.wishEvents,false);
    const expectedHistory=await Identity.resolveMissing(await repo.getItems(archive.id,301,100000,0));
    const expectedBeyond=await Identity.resolveMissing(await repo.getItems(archive.id,2000,100000,0));
    state.readIds=[];
    const model=new Model();
    await model.load('');
    assert.deepEqual(state.readIds,[archive.id]);
    assert.equal(state.wishEventReads,1);
    assert.equal(model.stats.totalPulls,3);
    assert.deepEqual(plain(model.stats.pools),plain(expectedPools));
    assert.deepEqual(plain(model.stats.avatars),plain(expectedCollection.avatars));
    assert.deepEqual(plain(model.stats.weapons),plain(expectedCollection.weapons));
    assert.deepEqual(plain(model.items),plain(expectedHistory));
    state.readIds=[];
    const stats=model.stats;
    await model.selectPool(2000);
    assert.deepEqual(state.readIds,[archive.id]);
    assert.equal(state.wishEventReads,1);
    assert.equal(model.stats,stats);
    assert.deepEqual(plain(model.items),plain(expectedBeyond));
    assert.deepEqual(snapshot(),before);
  });
  await test('same-rarity alias collisions remain invalid and the active metadata version invalidates recovery',async()=>{
    const {service,load,state,repo,snapshot}=harness();
    const Item=load('model/GachaItem').GachaItem;
    const archive=await repo.getOrCreateArchive(A);
    const old=Item.fromServer(row('71',{uid:A,item_id:'',name:'Nome',item_type:'Arma',rank_type:'4'}));
    old.archiveId=archive.id;
    await repo.insertItems([old]);
    state.weaponMetadata=[{id:11401,canonicalName:'甲',name:'甲',rankLevel:4},
      {id:11402,canonicalName:'乙',name:'乙',rankLevel:4},{id:11301,canonicalName:'丙',name:'丙',rankLevel:3}];
    state.names.set('weapon_meta.json:es',new Map([[11401,'Nome']]));
    state.names.set('weapon_meta.json:pt',new Map([[11402,'Nome']]));
    state.names.set('weapon_meta.json:it',new Map([[11301,'Nome']]));
    await assert.rejects(service.buildExportJson([A]),/记录 71.*item_id=0/);
    const Identity=load('service/GachaItemIdentityService').GachaItemIdentityService;
    const stillUnknown=await Identity.resolveMissing(await repo.getItemsByArchive(archive.id));
    assert.deepEqual(plain(stillUnknown.map(item=>[item.name,item.itemId])),[['Nome',0]]);
    state.metadataVersion='corrected';
    state.names.set('weapon_meta.json:pt',new Map());
    const output=JSON.parse(await service.buildExportJson([A]));
    assert.equal(output.hk4e[0].list[0].item_id,'11401');
    assert.equal(snapshot().items[0].item_id,0);
  });
  await test('new API refresh resolves missing identities before writing and rejects an unresolved replacement page',async()=>{
    const {load,state,snapshot}=harness();
    const wishes=load('service/GachaLogService').GachaLogService.getInstance();
    state.avatarMetadata=[{id:10000042,canonicalName:'刻晴',name:'刻晴',quality:5}];
    state.wishLanguage='ja-jp';
    state.names.set('avatar_meta.json:ja',new Map([[10000042,'刻晴（日本語）']]));
    state.wishReplies.push({success:true,data:{list:[row('81',{uid:A,item_id:'',name:'刻晴（日本語）',item_type:'キャラクター'})]}});
    const result=await wishes.importByUrl('fixture',A,()=>{},false,[301]);
    assert.equal(result.ok,true);
    assert.equal(result.fetchedCount,1);
    assert.equal(snapshot().items[0].item_id,10000042);
    const before=snapshot();
    state.wishReplies.push({success:true,data:{list:[row('81',{uid:A,item_id:'',name:'未收录的新物品',item_type:'キャラクター'})]}});
    const rejected=await wishes.importByUrl('fixture',A,()=>{},true,[301]);
    assert.equal(rejected.ok,false);
    assert.match(rejected.message,/记录 81.*item_id=0.*未保存本页/);
    assert.deepEqual(snapshot(),before);
  });
  await test('7.2 bundled metadata resolves new avatar and weapon pages without server item IDs',async()=>{
    const {load,state,snapshot}=harness();
    const metadata=path.join(__dirname,'../entry/src/main/resources/rawfile/metadata');
    const read=name=>JSON.parse(fs.readFileSync(path.join(metadata,name),'utf8'));
    state.avatarMetadata=read('avatar_meta.json');
    state.weaponMetadata=read('weapon_meta.json');
    const featured=read('GachaEvent.json').filter(event=>event.Version==='7.2');
    const newAvatars=[10000136,10000137].map(id=>state.avatarMetadata.find(item=>item.id===id));
    const newWeapon=state.weaponMetadata.find(item=>item.id===14525);
    assert.deepEqual(newAvatars.map(item=>item?.name),['米提亚','瓦列里']);
    assert.equal(newWeapon?.name,'秘星典谕');
    assert.ok(featured.some(event=>event.Type===301&&event.UpOrangeList.includes(newAvatars[0].id)));
    assert.ok(featured.some(event=>event.Type===302&&event.UpOrangeList.includes(newWeapon.id)));
    const time='2026-11-05 12:00:00';
    const regularRow=(id,type,item,kind,rank)=>row(id,{uid:A,gacha_type:String(type),item_id:'',
      item_type:kind,name:item.name,rank_type:String(rank),time});
    state.wishUser={isOversea:false,stoken:'fixture',stokenCookie:()=> 'fixture'};
    state.wishReplies.push(
      {success:true,data:{list:[
        regularRow('1793884800001600003',301,newAvatars[0],'角色',newAvatars[0].quality),
        regularRow('1793884800001600002',400,newAvatars[1],'角色',newAvatars[1].quality),
      ]}},
      {success:true,data:{list:[regularRow('1793884800001600001',302,newWeapon,'武器',newWeapon.rankLevel)]}},
    );
    const service=load('service/GachaLogService').GachaLogService.getInstance();
    const result=await service.refreshByStoken(A,()=>{},false,[301,302]);
    assert.equal(result.ok,true,result.message);
    assert.equal(result.fetchedCount,3);
    assert.equal(state.wishReplies.length,0);
    assert.deepEqual(snapshot().items.map(item=>[item.item_id,item.gacha_type,item.rank_type,item.name]),[
      [10000136,301,5,'米提亚'],[10000137,400,4,'瓦列里'],[14525,302,5,'秘星典谕'],
    ]);
  });
  await test('lazy refresh honors a sparse pool watermark and keeps exact long cursors across overlapping pages',async()=>{
    const {load,state,repo,snapshot}=harness();
    const Item=load('model/GachaItem').GachaItem;
    const archive=await repo.getOrCreateArchive(A);
    const newest=1793884800001694703n;
    const make=(offset,type=400)=>row(String(newest+BigInt(offset)),{uid:A,gacha_type:String(type)});
    const stored=[Item.fromServer(make(-30)),Item.fromServer(make(0,301)),Item.fromServer(make(900,302))];
    for(const item of stored)item.archiveId=archive.id;
    await repo.insertItems(stored);
    const first=Array.from({length:20},(_,index)=>make(30-index));
    const second=[first.at(-1),make(1),...Array.from({length:18},(_,index)=>make(-1-index))];
    state.wishReplies.push({success:true,data:{list:first}},{success:true,data:{list:second}});
    const service=load('service/GachaLogService').GachaLogService.getInstance();
    const result=await service.importByUrl('fixture',A,()=>{},false,[301]);
    assert.equal(result.ok,true,result.message);
    assert.equal(result.fetchedCount,21);
    assert.deepEqual(state.wishRequests.map(request=>request.slice(1)),[
      ['/gacha_info/api/getGachaLog','301','20','0'],
      ['/gacha_info/api/getGachaLog','301','20',first.at(-1).id],
    ]);
    assert.deepEqual(snapshot().items.map(item=>item.gacha_id).sort(),
      [...stored.map(item=>item.gachaId),...first.map(item=>item.id),make(1).id].sort());
  });
  await test('complete refresh replaces its returned window and retains older and other-pool records',async()=>{
    const {load,state,repo,snapshot}=harness();
    const Item=load('model/GachaItem').GachaItem;
    const archive=await repo.getOrCreateArchive(A);
    const stored=[Item.fromServer(row('90',{uid:A})),Item.fromServer(row('95',{uid:A})),
      Item.fromServer(row('99',{uid:A,gacha_type:'302'}))];
    for(const item of stored)item.archiveId=archive.id;
    await repo.insertItems(stored);
    const page=[row('96',{uid:A}),row('95',{uid:A}),row('94',{uid:A})];
    state.wishReplies.push({success:true,data:{list:page}});
    const result=await load('service/GachaLogService').GachaLogService.getInstance().importByUrl('fixture',A,()=>{},true,[301]);
    assert.equal(result.ok,true,result.message);
    assert.equal(result.fetchedCount,3);
    const rows=snapshot().items;
    assert.deepEqual(rows.map(item=>item.gacha_id).sort(),['90','94','95','96','99']);
    assert.equal(rows.find(item=>item.gacha_id==='95').item_id,10000001);
  });
  await test('Beyond refresh uses five-row CN requests and reads op_gacha_type, schedule and low ranks',async()=>{
    const {load,state,snapshot}=harness();
    const beyond=(id,type,rank)=>({uid:A,id,region:'cn_gf01',op_gacha_type:String(type),
      schedule_id:'10',item_id:'250013',item_name:'服饰',item_type:'装扮',rank_type:String(rank),
      time:'2026-11-05 12:00:00'});
    const eventTypes=[20011,20012,20021,20022];
    state.wishReplies.push({success:true,data:{list:[beyond('99',1000,1)]}},
      {success:true,data:{list:eventTypes.map((type,index)=>beyond(String(98-index),type,index%2+1))}});
    const result=await load('service/GachaLogService').GachaLogService.getInstance()
      .importByUrl('fixture',A,()=>{},false,[1000,2000]);
    assert.equal(result.ok,true,result.message);
    assert.equal(result.fetchedCount,5);
    assert.deepEqual(state.wishRequests,[
      ['public-operation-hk4e.mihoyo.com','/gacha_info/api/getBeyondGachaLog','1000','5','0'],
      ['public-operation-hk4e.mihoyo.com','/gacha_info/api/getBeyondGachaLog','2000','5','0'],
    ]);
    assert.deepEqual(snapshot().items.map(item=>[item.gacha_type,item.rank_type,item.schedule_id]),
      [[1000,1,10],[20011,1,10],[20012,2,10],[20021,1,10],[20022,2,10]]);
  });
  await test('malformed successful reply and a rounded numeric cursor fail before any archive write',async()=>{
    const {load,state,snapshot}=harness();
    const service=load('service/GachaLogService').GachaLogService.getInstance();
    for(const [data,message] of [[{},/缺少记录列表/],
      [{list:[row(1793884800001694719,{uid:A})]},/祈愿记录 ID 无效/]]){
      state.wishReplies.push({success:true,data});
      const result=await service.importByUrl('fixture',A,()=>{},false,[301]);
      assert.equal(result.ok,false);
      assert.match(result.message,message);
      assert.deepEqual(snapshot(),{archives:[],items:[]});
    }
  });
  await test('Windows-style v2.0 and v2.1 files survive taskpool preview and commit',async()=>{
    const {Model,state,service}=harness();
    const model=new Model();
    for(const [index,version] of ['v2.0','v2.1'].entries()){
      const uid=index===0?A:B;
      state.text=JSON.stringify({info:{uid,uigf_version:version,region_time_zone:8},list:[row(String(index+1))]});
      assert.equal(await model.prepareImportFile('/picked.json'),true);
      assert.equal(model.importPreview.version,version);
      assert.equal((await model.confirmImport()).inserted,1);
      await assert.rejects(service.buildExportJson([uid],version),/不支持的 UIGF 导出版本/);
    }
  });
  await test('low-rank Windows Beyond subpools roundtrip and remain visible under the 2000 query pool',async()=>{
    const {Model,state,service,snapshot,load}=harness();
    const poolTypes=[20011,20012,20021,20022];
    const rows=poolTypes.map((type,index)=>({id:String(index+1),op_gacha_type:String(type),
      item_id:'250013',rank_type:String(index%2+1),schedule_id:'10',time:'2026-10-05 10:00:00'}));
    state.text=file([section(A,[])],[section(A,rows)]);
    const model=new Model();
    assert.equal(await model.prepareImportFile('/picked.json'),true);
    assert.equal(model.importPreview.archives[0].beyondCount,4);
    assert.equal((await model.confirmImport()).inserted,4);
    const repo=load('data/repo/GachaRepo').GachaRepo,archiveId=snapshot().archives[0].id;
    assert.deepEqual(plain((await repo.getItemsByType(archiveId,2000)).map(item=>item.gachaType)),poolTypes);
    assert.equal(await repo.countByType(archiveId,2000),4);
    assert.deepEqual(plain(await repo.getAllGachaIds(archiveId,2000)),['1','2','3','4']);
    const output=JSON.parse(await service.buildExportJson([A]));
    assert.equal(String(output.hk4e[0].uid),A);
    assert.deepEqual(output.hk4e[0].list,[]);
    assert.deepEqual(output.hk4e_ugc[0].list.map(({op_gacha_type,rank_type})=>[Number(op_gacha_type),rank_type]),
      poolTypes.map((type,index)=>[type,String(index%2+1)]));
    assert.ok(output.hk4e_ugc[0].list.every(item=>item.count===undefined));
    assert.throws(()=>service.prepareImport(file([section(A,[row('1',{rank_type:2})])])),/星级/);
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
