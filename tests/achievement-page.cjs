// Production AchievementPage handlers and UIAF models; only native UI/files and service I/O are doubles.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const ts=require(process.env.TYPESCRIPT_PATH||'../ci/node_modules/typescript');
const root=path.resolve(__dirname,'../entry/src/main/ets');
const source=fs.readFileSync(path.join(root,'pages/AchievementPage.ets'),'utf8').replace(/\r\n/g,'\n');
const plain=value=>JSON.parse(JSON.stringify(value));
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
const turn=()=>new Promise(resolve=>setImmediate(resolve));
function harness(){
  const state={archives:[{id:11,name:'主档案',isSelected:true},{id:22,name:'备用',isSelected:false}],records:new Map(),groups:[],
    calls:[],toasts:[],dialogs:[],opens:[],closes:0,writes:[],allocations:[],selects:[],saves:[],timers:new Map(),timerId:0,
    input:'',clipboard:'',choice:1,readCount:0};
  const modules=new Map();
  const modelResult=ts.transpileModule(fs.readFileSync(path.join(root,'model/AchievementData.ets'),'utf8'),{
    compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
  assert.equal(modelResult.diagnostics.length,0);const modelModule={exports:{}};
  vm.runInNewContext(modelResult.outputText,{module:modelModule,exports:modelModule.exports});const model=modelModule.exports;
  const service={
    async getArchives(){const snapshot=state.archives.map(archive=>({...archive}));if(state.archiveGate)await state.archiveGate.promise;return snapshot;},
    async getRecords(id){state.calls.push(['read',id]);const snapshot=new Map(state.records.get(id)??[]);if(state.recordGate){const gate=state.recordGate;state.recordGate=undefined;await gate.promise;}return snapshot;},
    async getCategoryStats(id,records){return state.groups.map(category=>{const stats=new model.AchievementStats();for(const entry of category.entries){stats.total++;stats.primogemsTotal+=entry.reward;if(model.AchievementRecord.isDone(records.get(entry.id))){stats.done++;stats.primogemsEarned+=entry.reward;}}return {category,stats};});},
    async selectArchive(id){state.calls.push(['select',id]);if(state.selectionGate)await state.selectionGate.promise;state.archives=state.archives.map(archive=>({...archive,isSelected:archive.id===id}));},
    async createArchive(name){state.calls.push(['create',name]);if(state.archives.some(archive=>archive.name===name))throw Error('已存在同名档案');const id=Math.max(0,...state.archives.map(archive=>archive.id))+1;state.archives.push({id,name,isSelected:false});await service.selectArchive(id);},
    async deleteArchive(id){state.calls.push(['delete',id]);state.archives=state.archives.filter(archive=>archive.id!==id);state.records.delete(id);if(state.archives.length)state.archives[0].isSelected=true;},
    async setCompleted(id,achId,done){state.calls.push(['complete',id,achId,done]);if(state.completionGate)await state.completionGate.promise;const records=new Map(state.records.get(id)??[]);const record=new model.AchievementRecord();Object.assign(record,{archiveId:id,achId,status:done?3:1,timestamp:done?1700000100:0});records.set(achId,record);state.records.set(id,records);},
    async importUiaf(id,text,strategy){state.calls.push(['import',id,strategy,state.closes]);try{const incoming=model.UiafCodec.parse(text,id);const records=model.UiafCodec.merge(state.records.get(id)??new Map(),incoming,strategy);state.records.set(id,new Map(records.map(record=>[record.achId,record])));return {ok:true,message:'导入完成'};}catch(error){return {ok:false,message:error.message};}},
    async exportUiaf(id){state.calls.push(['export',id]);return state.exportText??model.UiafCodec.export([...(state.records.get(id)??new Map()).values()],'page-host',1700000000);},
  };
  const picker={DocumentSelectOptions:class{},DocumentSaveOptions:class{},DocumentViewPicker:class{
    async select(options){state.selects.push(options);return state.selectGate?state.selectGate.promise:['/picked.json'];}
    async save(options){state.saves.push(options);return state.saveGate?state.saveGate.promise:['/export.json'];}
  }};
  const fileIo={OpenMode:{READ_ONLY:1,READ_WRITE:2,TRUNC:4},openSync(uri,mode){state.opens.push([uri,mode]);return {fd:1};},
    statSync(){state.readCount++;return {size:state.readCount>1&&state.afterSize!==undefined?state.afterSize:state.statSize??Buffer.byteLength(state.input)};},
    readSync(fd,buffer){new Uint8Array(buffer).set(state.bytes??Buffer.from(state.input));return state.shortRead?buffer.byteLength-1:buffer.byteLength;},
    writeSync(fd,buffer){assert.ok(buffer instanceof ArrayBuffer);const bytes=Buffer.from(buffer);state.writes.push(bytes.toString('utf8'));return state.shortWrite?bytes.byteLength-1:bytes.byteLength;},closeSync(){state.closes++;}};
  const util={TextDecoder:{create:(encoding,options)=>({decodeToString:bytes=>new TextDecoder(encoding,options).decode(bytes)})},
    TextEncoder:{create:()=>({encodeInto:text=>new Uint8Array(Buffer.from(text,'utf8'))})}};
  let logic=source.slice(0,source.indexOf('  build() {'))+'\n}';
  logic=logic.replace(/^@Entry\n@Component\n/m,'').replace('export struct AchievementPage','export class AchievementPage');
  const compiled=ts.transpileModule(logic,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true},reportDiagnostics:true});
  assert.equal(compiled.diagnostics.length,0);const module={exports:{}};
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`,{
    State(){},Prop(){},StorageProp:()=>()=>{},Watch:()=>()=>{},$r:id=>id,Error,Date,
    setTimeout(fn){const id=++state.timerId;state.timers.set(id,fn);return id;},clearTimeout(id){state.timers.delete(id);},
    ArrayBuffer:class extends ArrayBuffer{constructor(size){state.allocations.push(size);super(size);}},
  })(id=>{
    if(id.endsWith('/AchievementData'))return model;
    if(id.endsWith('/AchievementService'))return {AchievementService:service};
    if(id.endsWith('/SimpleDataSource'))return {SimpleDataSource:class{constructor(rows){this.rows=rows;}notifyDataReload(rows){this.rows=rows;}}};
    if(id.endsWith('/UiSurface'))return {UiSurface:{dialogMaterial:()=>undefined}};
    if(id==='@kit.CoreFileKit')return {fileIo,picker};
    if(id==='@kit.ArkTS')return {util};
    if(id==='@kit.BasicServicesKit')return {pasteboard:{getSystemPasteboard:()=>({getData:async()=>{if(state.clipboardGate)await state.clipboardGate.promise;return {getPrimaryText:()=>state.clipboard};}})}};
    throw Error('Unexpected runtime dependency '+id);
  },module,module.exports);
  const page=new module.exports.AchievementPage();page.attached=true;
  page.getUIContext=()=>({getPromptAction:()=>({showToast:options=>state.toasts.push(options.message),showDialog:async options=>{state.dialogs.push(options);return state.dialogGate?state.dialogGate.promise:{index:state.choice};}})});
  const entry=(id,name,desc,ver,order,daily=false)=>Object.assign(new model.AchievementEntry(),{id,name,canonicalName:name,desc,ver,order,reward:5,isDailyQuest:daily});
  state.groups=[Object.assign(new model.AchievementCategory(),{id:1,name:'第一类',entries:[entry(101,'动物园大亨','捕捉30只动物','1.0',1),entry(102,'动物园大亨','捕捉300只动物','1.0',2)]}),
    Object.assign(new model.AchievementCategory(),{id:2,name:'第二类',entries:[entry(201,'「你好，朋友！」','完成每日委托','2.0',3,true),entry(202,'Adventure','Visit Mondstadt','3.3',4)]}),
    Object.assign(new model.AchievementCategory(),{id:3,name:'第三类',entries:[entry(301,'终点','完成挑战','7.2',5)]})];
  const record=(archiveId,achId,status,timestamp=1700000000,current=0)=>Object.assign(new model.AchievementRecord(),{archiveId,achId,status,timestamp,current});
  state.records.set(11,new Map([[101,record(11,101,3,1700000000)],[102,record(11,102,1,0,31)],[301,record(11,301,2,1700000002)]]));
  return {page,state,model,service,record,flushSearch(){for(const callback of state.timers.values())callback();state.timers.clear();}};
}
const uiaf=rows=>JSON.stringify({info:{uiaf_version:'v1.1'},list:rows});
(async()=>{
  await test('default unfinished sorting applies to categories and rows while completion stays global and each stage stays independent',async()=>{
    const h=harness(),{page,state}=h;await page.reload();
    assert.equal(page.uncompletedFirst,true);assert.deepEqual(Array.from(page.categoryRows,group=>group.category.id),[2,1,3]);
    assert.deepEqual(Array.from(page.entrySource.rows,row=>row.entry.id),[102,201,202,301,101]);assert.equal(page.stats.done,2);assert.equal(page.stats.total,5);
    assert.equal(page.constructor.completionText(page.stats),'2/5 - 40.00%');
    const stage=page.entrySource.rows.find(row=>row.entry.id===102);assert.equal(stage.progress,31);
    await page.setCompletion(stage,true);assert.deepEqual(state.calls.filter(call=>call[0]==='complete'),[['complete',11,102,true]]);
    assert.equal(page.stats.done,3);assert.equal(state.records.get(11).get(101).timestamp,1700000000);
    page.toggleSort();assert.deepEqual(Array.from(page.categoryRows,group=>group.category.id),[1,2,3]);
    assert.deepEqual(Array.from(page.entrySource.rows,row=>row.entry.id),[101,102,201,202,301]);
  });
  await test('search supports names, punctuation, description, version and exact ID and limits categories to matching goals',async()=>{
    const h=harness(),{page}=h;await page.reload();
    for(const [query,ids,categories]of [['动物园',[102,101],[1]],['捕捉300',[102],[1]],['你好朋友',[201],[2]],['adventure',[202],[2]],
      ['1.0',[102,101],[1]],['101',[101],[1]],['10',[],[]],['unknown',[],[]]]){
      page.search(query);h.flushSearch();assert.deepEqual(Array.from(page.entrySource.rows,row=>row.entry.id),ids,query);
      assert.deepEqual(Array.from(page.categoryRows,group=>group.category.id),categories,query);assert.equal(page.stats.total,5);
    }
    page.chooseCategory(1);assert.equal(page.keyword,'');assert.equal(page.visibleCount,2);
    page.search('no match');page.search('7.2');assert.equal(h.state.timers.size,1);h.flushSearch();assert.equal(page.categoryFilter,-1);assert.equal(page.visibleCount,1);
    page.statusFilter=2;page.search('');h.flushSearch();assert.deepEqual(Array.from(page.categoryRows,group=>group.category.id),[2,1]);
    page.dailyQuestOnly=true;page.rebuildEntries();assert.deepEqual(Array.from(page.entrySource.rows,row=>row.entry.id),[201]);
  });
  await test('component widths switch list split and category grid density in both directions and opening a grid category reveals its list',async()=>{
    const {page}=harness();await page.reload();
    for(const [width,wide,columns]of [[320,false,1],[600,false,2],[839.9,false,3],[840,true,3],[1200,true,5],[360,false,1]]){
      page.onContentAreaChange(width);assert.equal(page.isWide,wide);assert.equal(page.categoryColumns,columns);assert.equal(page.contentWidth,width);
    }
    page.gridMode=true;page.openCategory(2);assert.equal(page.gridMode,false);assert.equal(page.categoryFilter,2);assert.equal(page.visibleCount,2);
    page.onContentAreaChange(NaN);assert.equal(page.contentWidth,360);
  });
  await test('create and select use existing archive actions, reject duplicates and stale row controls cannot write into another archive',async()=>{
    const {page,state}=harness();await page.reload();const stale=page.entrySource.rows[0];
    await page.switchArchive(22);await page.setCompletion(stale,true);assert.equal(state.calls.filter(call=>call[0]==='complete').length,0);
    page.newName=' 新存档 ';await page.createArchive();assert.equal(page.currentName(),'新存档');assert.equal(page.showCreate,false);assert.equal(page.newName,'');
    const id=page.currentArchiveId;page.newName='新存档';await page.createArchive();assert.equal(page.currentArchiveId,id);assert.match(state.toasts.at(-1),/同名/);
    const before=state.calls.length;await page.switchArchive(999);assert.equal(state.calls.length,before);
    state.archives=[];await page.reload();assert.equal(page.currentArchiveId,-1);assert.equal(page.entrySource.rows.length,0);assert.equal(page.categoryRows.length,0);
    assert.equal(page.pageActions().find(action=>action.value==='创建新档案').enabled,true);
    assert.equal(page.pageActions().find(action=>action.value==='从文件导入 UIAF').enabled,false);
  });
  await test('delete confirmation names and removes only its captured archive, and cancellation or leaving cannot delete',async()=>{
    for(const decision of ['delete','cancel','leave']){
      const {page,state}=harness();await page.reload();const gate=deferred();state.dialogGate=gate;
      const pending=page.deleteCurrentArchive();await turn();assert.match(state.dialogs[0].message,/主档案/);
      if(decision==='leave')page.aboutToDisappear();gate.resolve({index:decision==='cancel'?0:1});await pending;
      assert.deepEqual(state.calls.filter(call=>call[0]==='delete'),decision==='delete'?[['delete',11]]:[]);
      if(decision==='delete')assert.equal(page.currentArchiveId,22);assert.equal(page.busy,false);
    }
  });
  await test('file and clipboard imports keep all three UIAF strategies and close the input before overwrite confirmation',async()=>{
    for(const strategy of [0,1,2]){
      const {page,state}=harness();await page.reload();page.importStrategy=strategy;
      state.input=uiaf([{id:101,current:7,status:1,timestamp:0},{id:999,current:4,status:2,timestamp:1700000001}]);
      await page.importUiaf();assert.equal(state.closes,1);assert.equal(state.records.get(11).get(101).status,strategy===0?3:1);
      assert.equal(state.records.get(11).has(301),strategy!==2);assert.equal(state.records.get(11).get(999).current,4);
      assert.deepEqual(state.calls.find(call=>call[0]==='import'),['import',11,strategy,1]);
      assert.equal(state.dialogs.length,strategy===2?1:0);assert.equal(page.busy,false);
      state.clipboard=uiaf([{id:102,current:300,status:3,timestamp:1700000002}]);page.importStrategy=1;await page.importUiafFromClipboard();
      assert.equal(state.records.get(11).get(102).status,3);assert.equal(page.stats.done,3-strategy);
    }
    const {page,state}=harness();await page.reload();page.importStrategy=2;state.choice=0;state.input=uiaf([]);
    await page.importUiaf();assert.equal(state.calls.filter(call=>call[0]==='import').length,0);assert.equal(state.records.get(11).size,3);
  });
  await test('bounded file reads reject size, partial data, changing size and malformed UTF8 before import',async()=>{
    for(const fault of ['empty','huge','fraction','short','changed','utf8']){
      const {page,state}=harness();await page.reload();state.input=uiaf([]);
      if(fault==='empty')state.statSize=0;if(fault==='huge')state.statSize=32*1024*1024+1;if(fault==='fraction')state.statSize=1.5;
      if(fault==='short')state.shortRead=true;if(fault==='changed')state.afterSize=1;if(fault==='utf8'){state.bytes=Buffer.from([0xff]);state.input='x';}
      await page.importUiaf();assert.equal(state.calls.filter(call=>call[0]==='import').length,0);assert.equal(state.closes,1);assert.equal(page.busy,false);
      if(['empty','huge','fraction'].includes(fault))assert.equal(state.allocations.length,0);assert.match(state.toasts.at(-1),/导入失败/);
    }
  });
  await test('file pickers, clipboard and overwrite confirmations cannot complete against a departed page',async()=>{
    for(const operation of ['file','clipboard','overwrite']){
      const {page,state}=harness();await page.reload();const gate=deferred();state.input=uiaf([]);state.clipboard=state.input;
      if(operation==='file')state.selectGate=gate;if(operation==='clipboard')state.clipboardGate=gate;
      if(operation==='overwrite'){page.importStrategy=2;state.dialogGate=gate;}
      const pending=operation==='clipboard'?page.importUiafFromClipboard():page.importUiaf();await turn();page.aboutToDisappear();
      gate.resolve(operation==='file'?['/picked.json']:{index:1});await pending;
      assert.equal(state.calls.filter(call=>call[0]==='import').length,0);assert.equal(page.busy,false);
      if(operation==='file')assert.equal(state.opens.length,0);
    }
  });
  await test('export owns one archive, checks UTF8 writes and picker cancellation, and holds the busy guard',async()=>{
    for(const outcome of ['write','cancel','short','leave']){
      const {page,state}=harness();await page.reload();state.exportText='{"name":"胡桃🔥"}';const gate=deferred();state.saveGate=gate;
      const pending=page.exportUiaf();await turn();await page.exportUiaf();await page.switchArchive(22);
      assert.deepEqual(state.calls.filter(call=>call[0]==='export'),[['export',11]]);assert.equal(state.saves.length,1);
      assert.equal(state.saves[0].newFileNames[0],'主档案.json');assert.equal(page.currentArchiveId,11);
      if(outcome==='leave')page.aboutToDisappear();if(outcome==='short')state.shortWrite=true;
      gate.resolve(outcome==='cancel'?[]:['/export.json']);await pending;
      assert.equal(state.opens.length,outcome==='write'||outcome==='short'?1:0);assert.equal(state.closes,state.opens.length);
      assert.equal(page.busy,false);if(outcome==='write'){assert.equal(state.writes[0],state.exportText);assert.match(state.toasts.at(-1),/导出成功/);}
      if(outcome==='short'){assert.match(state.toasts.at(-1),/写入不完整/);assert.ok(state.toasts.every(message=>!message.includes('导出成功')));}
    }
  });
  await test('late archive reload and completion cannot replace a newer page attachment or mutate stale view state',async()=>{
    const {page,state}=harness();await page.reload();const gate=deferred();state.archiveGate=gate;
    const old=page.reload();state.archiveGate=undefined;state.archives=[{id:22,name:'备用',isSelected:true}];await page.reload();
    gate.resolve();await old;assert.equal(page.currentArchiveId,22);
    const other=harness();await other.page.reload();const completion=deferred();other.state.completionGate=completion;
    const saving=other.page.setCompletion(other.page.entrySource.rows[0],true);await turn();other.page.aboutToDisappear();
    const before=other.page.stats.done;completion.resolve();await saving;assert.equal(other.page.stats.done,before);
  });
  await test('native layout binds both views, all archive actions, split viewport and themed category/reward icons',()=>{
    assert.match(source,/PageToolbar\(\{ embedMode: this\.embedMode/);assert.match(source,/else if \(this\.gridMode\) \{\s*this\.categoryGrid\(\)/);
    assert.match(source,/if \(this\.isWide\) \{ this\.categoryPanel\(\) \}\s*this\.entryList\(\)/);
    assert.match(source,/\.onAreaChange\([\s\S]*?this\.onContentAreaChange\(Number\(area\.width\)\)/);
    assert.match(source,/\.onClick\(\(\) => this\.openCategory\(entry\.category\.id\)\)/);
    assert.match(source,/Checkbox\([\s\S]*?\.onChange\(\(done: boolean\) => this\.setCompletion\(row, done\)\)/);
    assert.match(source,/MetaIcon\(\{ category: 'AchievementIcon'/);assert.match(source,/MetaIcon\(\{ category: 'ItemIcon', name: 'UI_ItemIcon_201'/);
    assert.doesNotMatch(source,/#[0-9A-Fa-f]{6,8}\b/);assert.doesNotMatch(source,/this\.statsCard\(\)|PageHeader\(/);
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
