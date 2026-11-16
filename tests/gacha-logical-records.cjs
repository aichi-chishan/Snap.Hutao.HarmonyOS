// Production repository, models, statistics, homepage and UIGF on real in-memory SQLite.
// Historical rows are seeded directly; SDK/network doubles exercise request boundaries only.
const assert=require('node:assert/strict'),test=require('node:test');
const {harness,A,B,big,row,section,file,plain,seedItems}=require('./helpers/uigf-harness.cjs');
function regular(h,archive,id,extra={}){
  const Item=h.load('model/GachaItem').GachaItem;
  const item=Item.fromServer(row(String(id),{uid:archive.uid,...extra}));item.archiveId=archive.id;return item;
}
function beyond(h,archive,id,type=1000,extra={}){
  const Item=h.load('model/GachaItem').GachaItem;
  const item=Item.fromServer({id:String(id),uid:archive.uid,op_gacha_type:String(type),item_id:'250013',
    item_type:'装扮',item_name:'服饰',rank_type:'4',schedule_id:'7',count:'1',time:'2026-10-05 10:00:00',...extra},true);
  item.archiveId=archive.id;return item;
}
const total=entries=>entries.reduce((sum,entry)=>sum+entry.count,0);
const success=list=>({success:true,data:{list}});
const failed=retcode=>({success:false,retcode,userFriendlyMessage:()=>`request failed ${retcode}`});
(async()=>{
  await test('device ratio 2559 physical / 1616 logical agrees across homepage, overview, history, collection, paging and UIGF',async()=>{
    const h=harness(),{repo,db,state,service,Model,snapshot,load}=h;
    const archive=await repo.getOrCreateArchive(A),otherArchive=await repo.getOrCreateArchive(B);
    const base=1793884800001694000n,records=[],events=[];
    for(let index=0;index<215;index++)records.push(regular(h,archive,base+BigInt(index),
      {gacha_type:'200',item_id:'10000042',name:'刻晴'}));
    for(let index=0;index<1094;index++){
      const item=regular(h,archive,base+215n+BigInt(index),{gacha_type:index%2?'400':'301',item_id:'10000042',name:'刻晴'});
      records.push(item);events.push(item);
    }
    for(let index=0;index<292;index++)records.push(regular(h,archive,base+1309n+BigInt(index),
      {gacha_type:'302',item_id:'11501',name:'风鹰剑',item_type:'武器'}));
    for(let index=0;index<15;index++)records.push(beyond(h,archive,base+BigInt(index)));
    seedItems(db,records.concat(events.slice(0,943)));
    state.avatarMetadata=[{id:10000042,name:'刻晴',canonicalName:'刻晴',quality:5,icon:'avatar'}];
    state.weaponMetadata=[{id:11501,name:'风鹰剑',canonicalName:'风鹰剑',rankLevel:5,icon:'weapon'}];
    state.wishEvents=[301,400].map(type=>({type,name:String(type),version:'fixture',banner:'',
      from:Date.parse('2026-10-05T00:00:00Z'),to:Date.parse('2026-10-06T00:00:00Z'),upOrange:[10000042],upPurple:[]}));
    const original=snapshot();assert.equal(original.items.length,2559);
    assert.equal(await repo.countAll(archive.id),1616);
    for(const [type,count]of [[200,215],[301,1094],[302,292],[1000,15]]){
      assert.equal(await repo.countByType(archive.id,type),count);
      assert.equal((await repo.getItemsByType(archive.id,type)).length,count);
      const ids=await repo.getAllGachaIds(archive.id,type);assert.equal(ids.length,count);assert.equal(new Set(ids).size,count);
    }
    const model=new Model();await model.load('');
    assert.equal(model.currentUid,A);assert.equal(model.gameAccountUid,'');assert.equal(model.stats.totalPulls,1601);
    assert.equal(model.stats.pools.find(pool=>pool.gachaType===301).totalCount,1094);
    assert.equal(model.stats.pools.find(pool=>pool.gachaType===1000).totalCount,15);
    assert.equal(model.items.length,1094);assert.equal(total(model.stats.avatars)+total(model.stats.weapons),1601);
    const Home=load('viewmodel/HomeViewModel').HomeViewModel,home=new Home();await home.reloadGacha(A);
    assert.equal(home.gachaTotal,1601);assert.equal(home.gachaPools.find(pool=>pool.gachaType===301).totalCount,1094);
    const homePages=await load('service/GachaHomeStatService').GachaHomeStatService.loadArchivePages();
    assert.equal(homePages.find(page=>page.uid===A).totalCount(),1601);assert.equal(homePages.find(page=>page.uid===B).totalCount(),0);
    const history=await load('service/GachaHistoryService').GachaHistoryService.getInstance().buildHistory(archive.id);
    assert.deepEqual(plain(history.map(period=>[period.type,period.totalCount,period.orangeUps[0].count])),[[301,547,547],[400,547,547]]);
    const newest=String(base+1308n),page=await repo.getItems(archive.id,301,7,3);
    assert.equal(page.length,7);assert.equal(page[0].gachaId,String(BigInt(newest)-3n));assert.equal(new Set(page.map(item=>item.gachaId)).size,7);
    const text=await service.buildExportJson([A]),output=JSON.parse(text),prepared=service.prepareImport(text);
    assert.equal(output.hk4e[0].list.length,1601);assert.equal(output.hk4e_ugc[0].list.length,15);
    assert.equal(output.hk4e[0].list.filter(item=>item.gacha_type==='400').length,547);
    assert.deepEqual(plain(prepared.preview().archives.map(entry=>[entry.totalCount,entry.standardCount,entry.beyondCount])),[[1616,1601,15]]);
    const imported=await service.importPrepared(prepared,[A],undefined,true);assert.equal(imported.ok,true,imported.message);
    assert.equal(imported.inserted,0);assert.equal(imported.skipped,1616);assert.deepEqual(snapshot(),original);
    await model.selectArchive(otherArchive.id);assert.equal(model.currentUid,B);assert.equal(model.stats.totalPulls,0);assert.equal(model.items.length,0);
    await model.selectArchive(archive.id);assert.equal(model.currentUid,A);assert.equal(model.items.length,1094);
    assert.equal(state.resultSets,state.closedSets);db.close();
  });
  await test('historical missing fields enrich only owned copies, known item aliases merge and exact decimal IDs keep namespace and UID scope',async()=>{
    const h=harness(),{repo,db,service,load,snapshot}=h;
    const a=await repo.getOrCreateArchive(A),b=await repo.getOrCreateArchive(B);
    const missing=regular(h,a,'000'+big,{item_id:'',name:'',item_type:'',rank_type:0,count:0,time:''});
    const known=regular(h,a,big,{item_id:'10000042',name:'刻晴'});
    const alias=regular(h,a,big,{item_id:'10000042',name:'Keqing',item_type:'Character'});
    const ugc=beyond(h,a,big,20011),other=regular(h,b,big,{item_id:'11501',name:'风鹰剑',item_type:'武器'});
    seedItems(db,[missing,known,alias,ugc,other]);const before=snapshot();
    const items=await repo.getItemsByArchive(a.id);assert.equal(items.length,2);
    const projected=items.find(item=>item.gachaType===400);
    assert.equal(projected.gachaId,big);assert.equal(projected.itemId,10000042);assert.equal(projected.rankType,5);assert.equal(projected.count,1);
    assert.equal(projected.name,'刻晴');assert.equal(projected.gachaType,400);
    assert.equal(await repo.countAll(a.id),2);assert.equal(await repo.countAll(b.id),1);
    const output=await service.buildExportJson([A,B]);assert.equal(service.prepareImport(output).preview().totalCount,3);
    assert.deepEqual(snapshot(),before);
    const aliasFile=file([section(A,[row('000'+big,{item_id:'10000042',name:'刻晴'}),row(big,{item_id:'10000042',name:'Keqing',item_type:'Character'})])]);
    const prepared=service.prepareImport(aliasFile);assert.equal(prepared.preview().totalCount,1);assert.equal(prepared.select().get(A)[0].gachaId,big);
    const wire=load('service/UigfImportTransfer').UigfImportTransfer.encode(prepared,()=>{});
    assert.equal((await load('service/UigfImportTransfer').UigfImportTransfer.adopt(wire,()=>{})).preview().totalCount,1);
    db.close();
  });
  await test('same-namespace content conflicts diagnose fields and retain all raw rows, including exact original pool identities',async()=>{
    const variants=[['item_id','10000002','物品 ID'],['gacha_type','301','原始卡池'],['time','2026-10-05 10:00:01','时间'],
      ['count','2','数量'],['rank_type','4','星级']];
    for(const [field,value,label]of variants){
      const h=harness(),a=await h.repo.getOrCreateArchive(A),safe=await h.repo.getOrCreateArchive(B);
      seedItems(h.db,[regular(h,a,big),regular(h,a,'0'+big,{[field]:value})]);const before=h.snapshot();
      for(const read of [()=>h.repo.getItemsByArchive(a.id),()=>h.repo.getItemsByType(a.id,200),()=>h.repo.getItems(a.id,301,1,0),
        ()=>h.repo.countAll(a.id),()=>h.repo.countByType(a.id,301),()=>h.repo.getAllGachaIds(a.id,301),()=>h.service.buildExportJson([A])]){
        await assert.rejects(read,error=>error.message.includes(big)&&error.message.includes(label)&&error.message.includes('数据库行 1/2'));
      }
      assert.deepEqual(h.snapshot(),before);assert.equal(JSON.parse(await h.service.buildExportJson([safe.uid])).hk4e[0].list.length,0);h.db.close();
    }
    for(const changed of [{op_gacha_type:'20012'},{op_gacha_type:'2000'},{schedule_id:'8'}]){
      const h=harness(),a=await h.repo.getOrCreateArchive(A);seedItems(h.db,[beyond(h,a,big,20011),beyond(h,a,big,20011,changed)]);
      await assert.rejects(h.repo.getItemsByArchive(a.id),/冲突.*颂愿 ID/);h.db.close();
    }
  });
  await test('import and incremental writes reject conflicting known identities and roll back every selected UID or earlier batch',async()=>{
    const h=harness(),a=await h.repo.getOrCreateArchive(A);await h.repo.insertItems([regular(h,a,'10')]);const before=h.snapshot();
    const prepared=h.service.prepareImport(file([section(B,[row('1')]),section(A,[row('10',{item_id:'10000002'})])]));
    const result=await h.service.importPrepared(prepared,[B,A],undefined,true);
    assert.equal(result.ok,false);assert.match(result.message,/UID 100000001.*普通 ID 10.*物品 ID/);assert.deepEqual(h.snapshot(),before);
    const many=Array.from({length:501},(_,index)=>regular(h,a,String(index+20)));
    many.push(regular(h,a,'10',{item_id:'10000002'}));
    await assert.rejects(h.repo.insertItems(many),/冲突/);assert.deepEqual(h.snapshot(),before);
    assert.equal(await h.repo.insertItems([regular(h,a,'00010'),regular(h,a,'11'),regular(h,a,'00011')]),1);
    assert.equal(await h.repo.countAll(a.id),2);h.db.close();
  });
  await test('100000 history cap applies after global cursor ordering and projection, leaving complete statistics and stable pool selection',async()=>{
    const {repo,db,Model,state}=harness(),archive=await repo.getOrCreateArchive(A);
    db.exec(`WITH RECURSIVE sequence(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM sequence WHERE i<100005)
      INSERT INTO gacha_items(archive_id,gacha_type,item_id,count,time,name,item_type,rank_type,gacha_id,schedule_id)
      SELECT ${archive.id},CASE WHEN i%2=0 THEN 301 ELSE 400 END,11301,1,
        CASE WHEN i=0 THEN '2026-10-06 10:00:00' ELSE '2026-10-05 10:00:00' END,'fixture','武器',3,
        printf('%lld',9007199254740993+i),0 FROM sequence;
      INSERT INTO gacha_items(archive_id,gacha_type,item_id,count,time,name,item_type,rank_type,gacha_id,schedule_id)
        SELECT archive_id,gacha_type,item_id,count,time,name,item_type,rank_type,'00'||gacha_id,schedule_id FROM gacha_items;`);
    assert.equal(db.prepare('SELECT count(*) AS n FROM gacha_items').get().n,200012);
    const newest=String(9007199254740993n+100005n),oldestVisible=String(9007199254740993n+6n);
    assert.equal(await repo.countAll(archive.id),100006);
    const page=await repo.getItems(archive.id,301,100000,0);
    assert.equal(page.length,100000);assert.equal(new Set(page.map(item=>item.gachaId)).size,100000);
    assert.equal(page[0].gachaId,newest);assert.equal(page.at(-1).gachaId,oldestVisible);
    const tail=await repo.getItems(archive.id,301,10,99999);assert.equal(tail.length,7);assert.equal(tail[0].gachaId,oldestVisible);
    assert.equal((await repo.getItems(archive.id,301,10,100006)).length,0);assert.equal((await repo.getItems(archive.id,301,0,0)).length,0);
    await assert.rejects(repo.getItems(archive.id,301,-1,0),/分页/);await assert.rejects(repo.getItems(archive.id,301,10,0.5),/分页/);
    state.readIds=[];const model=new Model();await model.load('');
    assert.deepEqual(state.readIds,[archive.id]);assert.equal(model.stats.totalPulls,100006);assert.equal(model.items.length,100000);
    assert.equal(model.items[0].gachaId,newest);assert.equal(model.items.at(-1).gachaId,oldestVisible);
    await model.selectPool(200);assert.equal(model.items.length,0);await model.selectPool(301);assert.equal(model.items.length,100000);
    assert.equal(model.items[0].gachaId,newest);assert.equal(model.stats.totalPulls,100006);assert.equal(state.resultSets,state.closedSets);db.close();
  });
  await test('watermark includes stored 400 rows and canonical IDs, repeat refreshes are idempotent and overlap conflicts are visible',async()=>{
    const h=harness(),a=await h.repo.getOrCreateArchive(A),base=9007199254740993n;
    seedItems(h.db,[regular(h,a,base),regular(h,a,'00'+base)]);const original=h.snapshot().items;
    const wishes=h.load('service/GachaLogService').GachaLogService.getInstance();
    const response=[row(String(base+1n),{uid:A}),row('000'+base,{uid:A})];h.state.wishReplies.push(success(response));
    let progress;let result=await wishes.importByUrl('fixture',A,value=>{progress=value;},false,[301]);
    assert.equal(result.ok,true,result.message);assert.equal(result.fetchedCount,1);assert.equal(progress.pools[0].duplicates,1);
    assert.deepEqual(h.snapshot().items.slice(0,2),original);assert.equal(await h.repo.countByType(a.id,301),2);
    h.state.wishReplies.push(success(response));result=await wishes.importByUrl('fixture',A,()=>{},false,[301]);assert.equal(result.ok,true);assert.equal(result.fetchedCount,0);
    const before=h.snapshot();h.state.wishReplies.push(success([row(String(base+1n),{uid:A,item_id:'10000002'})]));
    result=await wishes.importByUrl('fixture',A,value=>{progress=value;},false,[301]);
    assert.equal(result.ok,false);assert.equal(result.fetchedCount,0);assert.match(result.message,/冲突.*物品 ID/);assert.equal(progress.running,false);assert.equal(progress.pools[0].failed,true);
    assert.deepEqual(h.snapshot(),before);h.db.close();
  });
  await test('explicit full refresh validates before deletion, rolls back disk failures, then replaces only its confirmed window',async()=>{
    const h=harness(),a=await h.repo.getOrCreateArchive(A);
    seedItems(h.db,[regular(h,a,'1'),regular(h,a,'005'),regular(h,a,'5'),regular(h,a,'7'),regular(h,a,'9',{gacha_type:'302'})]);
    const before=h.snapshot();await assert.rejects(h.repo.replaceFetchedWindow([regular(h,a,'5',{item_id:'10000002'})],301),/冲突/);
    assert.deepEqual(h.snapshot(),before);
    h.state.failBatch=h.state.batches+1;await assert.rejects(h.repo.replaceFetchedWindow([regular(h,a,'5'),regular(h,a,'6')],301),/failure/);
    assert.deepEqual(h.snapshot(),before);h.state.failBatch=0;
    assert.equal(await h.repo.replaceFetchedWindow([regular(h,a,'0005'),regular(h,a,'6')],301),2);
    assert.deepEqual(h.snapshot().items.map(item=>item.gacha_id).sort(),['1','5','6','9']);assert.equal(await h.repo.countAll(a.id),4);h.db.close();
  });
  await test('a page makes at most three network attempts and permanent auth or risk errors never retry',async()=>{
    for(const responses of [[failed(-2),failed(-1),failed(-2),success([])],
      [failed(-2),failed(-1),success([row('1',{uid:A})])],[failed(-101),success([])],[failed(1034),success([])]]){
      const h=harness();h.state.wishReplies.push(...responses);const code=responses[0].retcode;
      const result=await h.load('service/GachaLogService').GachaLogService.getInstance().importByUrl('fixture',A,()=>{},false,[301]);
      assert.equal(h.state.wishRequests.length,code===-101||code===1034?1:3);
      assert.equal(result.ok,responses[2]?.success===true);assert.equal(h.snapshot().items.length,result.ok?1:0);h.db.close();
    }
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
