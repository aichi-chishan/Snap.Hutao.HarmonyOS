// Production input codec, calculator, repository and editor VM. SQLite is real; network/OS are fixtures.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const { DatabaseSync } = require('node:sqlite');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const plain = value => JSON.parse(JSON.stringify(value));
const defer = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
function harness() {
  const db = new DatabaseSync(':memory:');
  db.exec(`CREATE TABLE cultivate_projects(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT,created_at INTEGER,server_timezone_offset INTEGER NOT NULL DEFAULT 8);
    CREATE TABLE cultivate_entries(id INTEGER PRIMARY KEY AUTOINCREMENT,project_id INTEGER,avatar_id INTEGER,name TEXT,icon TEXT,level INTEGER,target_level INTEGER,created_at INTEGER,input_json TEXT NOT NULL DEFAULT '');
    CREATE TABLE cultivate_items(id INTEGER PRIMARY KEY AUTOINCREMENT,entry_id INTEGER,item_id INTEGER,name TEXT,icon TEXT,count INTEGER,finished INTEGER);
    CREATE TABLE cultivate_inventory(project_id INTEGER,item_id INTEGER,count INTEGER,PRIMARY KEY(project_id,item_id));
    INSERT INTO cultivate_projects(id,name,created_at) VALUES(1,'One',1),(2,'Two',2);`);
  const state = { uid:'100000001', user:1, begins:0, commits:0, rollbacks:0, inserts:0, failAfter:0, shortTable:'', shortDelete:false, open:0, closed:0, fetchList:async()=>[], fetchDetail:async()=>[], gate:undefined };
  const settings = new Map(), storage = new Map();
  class Pred {
    constructor(table){this.table=table;this.terms=[];this.values=[];this.order='';}
    equalTo(key,value){this.terms.push(`${key}=?`);this.values.push(value);return this;}
    and(){return this;}
    orderByAsc(key){this.order=` ORDER BY ${key} ASC`;return this;}
    orderByDesc(key){this.order=` ORDER BY ${key} DESC`;return this;}
    where(){return this.terms.length?' WHERE '+this.terms.join(' AND '):'';}
  }
  function query(pred) {
    const rows=db.prepare(`SELECT * FROM ${pred.table}${pred.where()}${pred.order}`).all(...pred.values);let index=-1;state.open++;
    return {goToFirstRow(){index=0;return rows.length>0;},goToNextRow:()=>++index<rows.length,
      getColumnIndex:name=>name,getLong:name=>Number(rows[index][name]),getString:name=>String(rows[index][name]),close(){state.closed++;}};
  }
  const store = {
    beginTransaction(){db.exec('BEGIN');state.begins++;},commit(){db.exec('COMMIT');state.commits++;},rollBack(){db.exec('ROLLBACK');state.rollbacks++;},querySync:query,
    insertSync(table,row){state.inserts++;if(table===state.shortTable)return -1;if(state.failAfter&&state.inserts===state.failAfter)throw Error('injected disk failure');const names=Object.keys(row);return Number(db.prepare(`INSERT INTO ${table}(${names}) VALUES(${names.map(()=>'?')})`).run(...Object.values(row)).lastInsertRowid);},
    updateSync(row,pred){const names=Object.keys(row);return Number(db.prepare(`UPDATE ${pred.table} SET ${names.map(name=>name+'=?')}${pred.where()}`).run(...Object.values(row),...pred.values).changes);},
    deleteSync(pred){if(state.shortDelete)return -1;return Number(db.prepare(`DELETE FROM ${pred.table}${pred.where()}`).run(...pred.values).changes);},
    executeSync(sql,args){return Number(db.prepare(sql).run(...args).changes);},
    batchInsertSync(table,rows){for(const row of rows)this.insertSync(table,row);return rows.length;},
  };
  const avatarMeta=JSON.parse(fs.readFileSync(path.resolve(root,'../resources/rawfile/metadata/avatar_meta.json'),'utf8'));
  const weaponMeta=JSON.parse(fs.readFileSync(path.resolve(root,'../resources/rawfile/metadata/weapon_meta.json'),'utf8'));
  const wiki={getAvatars:async()=>avatarMeta,getWeapons:async()=>weaponMeta,getMaterials:async()=>new Map(),getGachaEvents:async()=>[],iconOfAvatar:()=>''};
  const mocks={
    '@kit.ArkData':{relationalStore:{RdbPredicates:Pred}},
    RelationalStoreHelper:{getStore:()=>store,query:async pred=>query(pred)},
    Logger:{info(){},warn(){}},ApiClient:{},ApiResponse:class{},HoyolabClient:{},DsSigner:{},RiskVerifier:{},RiskControlError:class extends Error{},
    Constants:{RegionUtil:{regionOfUid:()=> 'cn_gf01'},AppConstants:{}},
    UserService:{getInstance:()=>({getCurrentUser:()=>({id:state.user})})},
    CharacterService:{getInstance:()=>({fetchList:(...args)=>state.fetchList(...args),fetchDetail:(...args)=>state.fetchDetail(...args)})},
    BackpackService:{cultivationMaterialMetadata:async()=>new Map()},
    PreferencesStore:{getNumber:(key,fallback)=>settings.get(key)??fallback,setNumber:(key,value)=>settings.set(key,value),
      getString:(key,fallback)=>settings.get(key)??fallback,setString:(key,value)=>settings.set(key,value)},
    WikiMetaService:wiki,
  };
  const cache=new Map();
  function load(relative){
    const file=path.resolve(root,relative.endsWith('.ets')?relative:relative+'.ets');if(cache.has(file))return cache.get(file).exports;
    const result=ts.transpileModule(fs.readFileSync(file,'utf8'),{fileName:file.replace('.ets','.ts'),compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true},reportDiagnostics:true});
    assert.equal(result.diagnostics.length,0,file);const module={exports:{}};cache.set(file,module);
    function requireLocal(name){if(mocks[name])return mocks[name];const key=path.basename(name);if(key==='Constants')return mocks.Constants;if(mocks[key])return {[key]:mocks[key]};return load(path.resolve(path.dirname(file),name));}
    vm.runInNewContext('(function(require,module,exports){'+result.outputText+'\n})',{Observed:target=>target,
      AppStorage:{get:key=>key==='currentUid'?state.uid:storage.get(key),setOrCreate:(key,value)=>storage.set(key,value)},
      Date,Map,Set,Error,Number,Array,JSON})(requireLocal,module,module.exports);
    return module.exports;
  }
  const {CultivationDraft:Draft}=load('model/CultivationDraft');
  const {CultivationRepo:repo}=load('data/repo/CultivationRepo');
  const {CultivationService:service}=load('service/CultivationService');
  const {CultivationDraftViewModel:Editor}=load('viewmodel/CultivationDraftViewModel');
  const {CalculateService:Calculator}=load('service/CalculateService');
  const calculator=Calculator.getInstance();
  const rows=table=>plain(db.prepare('SELECT * FROM '+table+' ORDER BY id').all());
  const snapshot=()=>JSON.stringify(['cultivate_projects','cultivate_entries','cultivate_items'].map(rows));
  const close=()=>{assert.equal(state.open,state.closed);db.close();};
  return {db,state,Draft,repo,service,Editor,calculator,rows,snapshot,close,load,settings,storage,wiki};
}

test('versioned input roundtrip preserves independent targets, current progress and source ownership',async()=>{
  const h=harness();const d=await h.service.offlineAvatar(10000002);d.sourceUid=h.state.uid;d.sourceAt=123;d.entryId=41;d.expectedInput='old';
  d.skills[0].target=6;d.skills[1].target=8;d.skills[2].target=9;
  const encoded=h.Draft.encode(d),restored=h.Draft.decode(encoded);
  assert.deepEqual(plain(restored.skills).map(s=>s.target),[6,8,9]);assert.equal(restored.sourceUid,h.state.uid);assert.equal(restored.entryId,0);assert.equal(restored.expectedInput,'');
  assert.throws(()=>h.Draft.decode(''),/旧计划/);assert.throws(()=>h.Draft.decode('{}'),/不完整/);
  const malformed=plain(restored);malformed.skills[1].id=malformed.skills[0].id;assert.throws(()=>h.Draft.decode(JSON.stringify(malformed)),/重复/);
  malformed.skills=[];assert.throws(()=>h.Draft.decode(JSON.stringify(malformed)),/三项/);h.close();
});
test('current-progress resync preserves even overtaken targets and rejects missing talent/UID/weapon data',async()=>{
  const h=harness();const saved=await h.service.offlineAvatar(10000002);saved.sourceUid=h.state.uid;saved.target=70;saved.targetPromote=5;saved.skills[0].target=6;
  const current=h.Draft.copy(saved);current.current=80;current.promote=6;current.skills[0].current=8;current.target=100;current.targetPromote=6;current.skills[0].target=10;
  const merged=h.service.mergeCurrent(saved,current);assert.equal(merged.current,80);assert.equal(merged.target,70);assert.equal(merged.skills[0].current,8);assert.equal(merged.skills[0].target,6);assert.equal(saved.current,1);
  const calculated=await h.service.calculate([merged]);assert.ok(calculated[0].items.every(i=>Number.isFinite(i.num)&&i.num>0));
  current.skills.pop();assert.throws(()=>h.service.mergeCurrent(saved,current));current.skills=h.Draft.copy(saved).skills;current.sourceUid='200000002';assert.throws(()=>h.service.mergeCurrent(saved,current),/UID/);h.close();
});
test('project-wide GameRecord sync matches exact skill IDs, retains targets and skips other UID plans',async()=>{
  const h=harness();
  const active=await h.service.offlineAvatar(10000002), foreign=await h.service.offlineAvatar(10000003);
  active.sourceUid=h.state.uid; active.skills[0].target=6; foreign.sourceUid='100000002';
  await h.service.save(1,await h.service.calculate([active,foreign]),false);
  const {SkillLevelService}=h.load('service/SkillLevelService');
  const skills=SkillLevelService.referenceSkills(active.itemId).map(skill=>({skillId:skill.skillId,level:4}));
  h.state.fetchDetail=async(uid,ids)=>{
    assert.equal(uid,h.state.uid); assert.deepEqual(plain(ids),[active.itemId]);
    return [{id:active.itemId,level:40,promoteLevel:2,skillDepotId:0,activedConstellationNum:0,constellations:[],skills:skills.reverse()}];
  };
  const snapshot=h.snapshot();
  const prepared=await h.service.prepareProjectProgress(h.state.uid,await h.repo.getEntries(1));
  assert.equal(prepared.entries.length,1); assert.equal(prepared.skipped,1); assert.equal(h.snapshot(),snapshot);
  await h.service.save(1,prepared.entries,true);
  const synced=h.Draft.decode(h.rows('cultivate_entries')[0].input_json);
  assert.equal(synced.current,40); assert.equal(synced.target,90); assert.equal(synced.skills[0].current,4);
  assert.equal(synced.skills[0].target,6); assert.equal(h.Draft.decode(h.rows('cultivate_entries')[1].input_json).current,1);
  h.close();
});
test('project time zone persists, stale inventory actions reject and deletion is scoped to one project',async()=>{
  const h=harness();
  const {CultivationViewModel}=h.load('viewmodel/CultivationViewModel');
  const model=new CultivationViewModel(); await model.loadPlan();
  assert.equal(model.currentProjectId,1); assert.equal(model.currentProjectOffset(),8);
  assert.equal(await model.createProject('Europe',1),true);
  const europe=model.currentProjectId;
  assert.equal((await h.repo.getProjects()).find(project=>project.id===europe).serverTimeZoneOffset,1);
  assert.equal(h.settings.get('cultivation.current_project_id'),europe);
  assert.ok(h.storage.get('calendarSettingsVersion')>0);
  await assert.rejects(h.repo.createProject(' Europe '),/同名/);
  await model.setInventoryCount(europe,104003,20);
  await model.selectProject(2);
  assert.match(await model.clearInventory(europe),/已切换/);
  assert.match(await model.importInventoryText(europe,'{"materials":[{"itemId":104003,"count":1}]}'),/已切换/);
  await model.setInventoryCount(2,104003,9);
  assert.equal(model.inventoryRows.find(row=>row.itemId===104003).current,9);
  await model.selectProject(europe);
  assert.equal(model.inventoryRows.find(row=>row.itemId===104003).current,20);
  assert.match(await model.deleteCurrentProject(europe),/已删除/);
  assert.deepEqual(plain(h.db.prepare('SELECT project_id,count FROM cultivate_inventory').all()),[{project_id:2,count:9}]);
  h.close();
});
test('calculator inventory sends catalog deltas with explicit UID and region; normal calculation keeps the old body',async()=>{
  const h=harness();
  const {CalculateService,CalculateInventoryCatalog}=h.load('service/CalculateService');
  const catalog=new CalculateInventoryCatalog(); catalog.avatarIds=[10000002,999]; catalog.weaponIds=[11501];
  const deltas=await h.service.inventoryCalculatorInputs(catalog);
  assert.equal(deltas.length,1); assert.equal(deltas[0].avatarId,10000002);
  assert.equal(deltas[0].skills.length,3); assert.equal(deltas[0].weapon.id,11501);
  const request=JSON.parse(CalculateService.buildBody(deltas,h.state.uid));
  assert.equal(request.uid,h.state.uid); assert.equal(request.region,'cn_gf01'); assert.equal(request.items[0].weapon.level_target,90);
  assert.deepEqual(JSON.parse(CalculateService.buildBody(deltas,'')),{items:request.items});
  h.close();
});
test('summary deficits and resin use one synthesis result, including the latest talent series',async()=>{
  const h=harness();
  const {ResinStatisticsService,ResinCategoryKind}=h.load('service/ResinStatisticsService');
  const items=[
    {itemId:112003,count:1,finished:false,name:'middle'},
    {itemId:112004,count:2,finished:false,name:'upper'},
    {itemId:104371,count:3,finished:false,name:'latest'},
  ];
  const stats=await ResinStatisticsService.compute([{items}],ResinStatisticsService.distributionOf(9),new Map([[112002,21]]));
  assert.equal(stats.materialShortfalls.get(112003),0);
  assert.equal(stats.materialShortfalls.get(112004),0);
  assert.equal(stats.materialShortfalls.get(104371),3);
  assert.equal(ResinStatisticsService.dayPairOf(104371),3);
  assert.equal(stats.rows.find(row=>row.kind===ResinCategoryKind.TALENT).runs,1);
  h.close();
});
test('resin uses surplus EXP books and signed same-family yields before rounding runs',async()=>{
  const h=harness();
  const {ResinStatisticsService,ResinCategoryKind}=h.load('service/ResinStatisticsService');
  const items=[{itemId:104003,count:1,finished:false,name:'experience'},
    {itemId:104303,count:2,finished:false,name:'talent'}, {itemId:114001,count:1,finished:false,name:'weapon'}];
  const inventory=new Map([[104002,4],[104301,8],[104304,1000]]);
  const stats=await ResinStatisticsService.compute([{items}],ResinStatisticsService.distributionOf(9),inventory);
  assert.ok(!stats.rows.some(row=>row.kind===ResinCategoryKind.REVELATION));
  assert.equal(stats.rows.find(row=>row.kind===ResinCategoryKind.TALENT).runs,1);
  assert.equal(stats.materialShortfalls.get(104303),2); // still needs two whole books
  assert.equal(stats.totalResin,40); assert.equal(stats.totalFragile,1);
  h.close();
});
test('drafts entered from the wiki use the current project and publish successful saves',async()=>{
  const h=harness(); const editor=new h.Editor(); h.settings.set('cultivation.current_project_id',2);
  await editor.offline('avatar',10000002);
  assert.equal(editor.projectId,2);
  await editor.calculate(); assert.equal(await editor.save(),true);
  assert.equal(h.storage.get('cultivationDataVersion'),1);
  assert.equal(h.rows('cultivate_entries')[0].project_id,2);
  h.close();
});
function equippedCharacter(h,id,weaponId,level=40,promoteLevel=2,weaponLevel=20) {
  const {SkillLevelService}=h.load('service/SkillLevelService');
  const weapon={id:weaponId,level:weaponLevel,promoteLevel:1,equipmentState:'equipped'};
  const character={id,name:`role-${id}`,level,weapon};
  const skillLevels={A:2,E:4,Q:6};
  const skills=SkillLevelService.referenceSkills(id).map(skill=>({skillId:skill.skillId,level:skillLevels[skill.kind]})).reverse();
  const detail={...character,element:'Cryo',promoteLevel,skillDepotId:0,activedConstellationNum:0,constellations:[],skills};
  return {character,detail};
}
test('planning a role and its current weapon opens two editable drafts in one confirmed save',async()=>{
  const h=harness();
  const fixture=equippedCharacter(h,10000002,11501);
  h.state.fetchDetail=async(uid,ids)=>{assert.equal(uid,h.state.uid);assert.deepEqual(plain(ids),[10000002]);return [fixture.detail];};
  const editor=new h.Editor(); await editor.characterAndWeapon(h.state.uid,fixture.character);
  assert.equal(editor.batchTargets,undefined);
  assert.deepEqual(plain(editor.drafts).map(draft=>[draft.kind,draft.itemId,draft.avatarId]),[['avatar',10000002,10000002],['weapon',11501,10000002]]);
  assert.deepEqual(plain(editor.drafts[0].skills).map(skill=>skill.current),[2,4,6]);
  editor.change(0,'target','80'); editor.change(1,'target','70');
  await editor.calculate(); assert.equal(editor.preview.length,2); assert.equal(h.state.begins,0);
  assert.equal(await editor.save(),true); assert.equal(h.state.commits,1);
  assert.deepEqual(h.rows('cultivate_entries').map(row=>row.target_level),[80,70]);
  assert.ok(h.rows('cultivate_entries').every(row=>h.Draft.decode(row.input_json).sourceUid===h.state.uid));
  h.close();
});
test('shared batch targets use exact A/E/Q IDs and current progress and keep independent weapon copies',async()=>{
  const h=harness();
  const {CultivationBatchField:Field,CultivationSaveMode:Mode}=h.load('model/CultivationDraft');
  const a=equippedCharacter(h,10000002,11101,90,6);
  const b=equippedCharacter(h,10000003,11101);
  const missing=equippedCharacter(h,10000006,11101); missing.detail.weapon={...missing.detail.weapon,equipmentState:'unknown'};
  h.state.fetchDetail=async()=>[a.detail,b.detail,missing.detail];
  const editor=new h.Editor(); await editor.batchCharacters(h.state.uid,[a.character,b.character,missing.character]);
  assert.equal(editor.batchSkipped,1); assert.equal(editor.drafts.length,4); assert.match(editor.message,/已跳过 1/);
  assert.deepEqual(plain(editor.batchTargets.levels),[90,10,10,10,90]);
  editor.changeBatchTarget(Field.AvatarLevel,'80'); editor.changeBatchTarget(Field.SkillA,'6');
  editor.changeBatchTarget(Field.SkillE,'7'); editor.changeBatchTarget(Field.SkillQ,'8');
  await editor.calculate(); assert.equal(editor.preview.length,4); assert.equal(h.state.begins,0);
  const prepared=plain(editor.preview).map(entry=>entry.draft);
  assert.deepEqual(prepared.filter(draft=>draft.kind==='avatar').map(draft=>[draft.current,draft.target,draft.skills.map(skill=>skill.target)]),
    [[90,80,[6,7,8]],[40,80,[6,7,8]]]);
  assert.deepEqual(prepared.filter(draft=>draft.kind==='weapon').map(draft=>draft.target),[70,70]);
  assert.ok(prepared[0].skills.every(skill=>skill.id===skill.groupId&&skill.groupId>0));
  editor.changeBatchTarget(Field.SkillE,''); assert.equal(await editor.save(),false);
  await editor.calculate(); assert.equal(editor.preview.length,0);
  editor.changeBatchTarget(Field.SkillE,'7'); await editor.calculate();
  editor.saveMode=Mode.CreateNew;
  assert.equal(await editor.save(),true); assert.equal(h.state.commits,1);
  const weapons=h.rows('cultivate_entries').filter(row=>row.avatar_id===11101).map(row=>h.Draft.decode(row.input_json));
  assert.deepEqual(weapons.map(draft=>draft.avatarId),[10000002,10000003]);
  const reopened=new h.Editor(); await reopened.batchCharacters(h.state.uid,[a.character,b.character]);
  assert.deepEqual(plain(reopened.batchTargets.levels),[80,6,7,8,90]);
  h.close();
});
test('account switch stops remaining detail requests and discards a late batch',async()=>{
  const h=harness(); const gate=defer(); let requests=0;
  h.state.fetchDetail=async()=>{requests++;return gate.promise;};
  const editor=new h.Editor(); const oldUid=h.state.uid;
  const pending=editor.batchCharacters(oldUid,Array.from({length:21},(_,index)=>({id:10000002+index,name:`role-${index}`})));
  assert.equal(requests,1); h.state.uid='200000002'; gate.resolve([]); await pending;
  assert.equal(requests,1); assert.equal(editor.drafts.length,0); assert.equal(await editor.save(),false); assert.equal(h.state.begins,0);
  h.close();
});
test('display language reload keeps current project, persisted targets and selected candidates',async()=>{
  const h=harness();
  const {CultivationViewModel}=h.load('viewmodel/CultivationViewModel');
  const model=new CultivationViewModel();
  await h.service.save(1,await h.service.calculate([await h.service.offlineAvatar(10000002)]),false);
  await model.load(''); await model.loadPlan();
  model.toggle(model.targets.findIndex(target=>target.avatarId===10000002));
  const baseline=h.snapshot(), avatars=await h.wiki.getAvatars();
  h.wiki.getAvatars=async()=>avatars.map(avatar=>avatar.id===10000002?{...avatar,name:'Kamisato Ayaka'}:avatar);
  h.wiki.getMaterials=async()=>new Map([[104003,{n:"Hero's Wit",i:'UI_ItemIcon_104003',r:4}]]);
  h.storage.set('helpLocaleVersion',2);
  await model.refreshDisplay();
  const target=model.targets.find(item=>item.avatarId===10000002);
  assert.equal(target.name,'Kamisato Ayaka'); assert.equal(target.selected,true);
  assert.equal(model.entryName(model.planEntries[0]),'Kamisato Ayaka');
  assert.equal(model.materialName(model.planEntries[0].items.find(item=>item.itemId===104003)),"Hero's Wit");
  assert.equal(model.materialLabelVersion,2);
  assert.equal(model.currentProjectId,1); assert.equal(h.snapshot(),baseline);
  h.close();
});
test('explicit target ascension controls cap-level materials; low-star weapons stay capped',async()=>{
  const h=harness();const weapon=await h.service.offlineWeapon(11101);assert.equal(weapon.maxLevel,70);assert.equal(weapon.target,70);
  const d=await h.service.offlineAvatar(10000002);d.current=20;d.target=20;d.promote=0;d.targetPromote=0;for(const skill of d.skills){skill.target=1;}
  assert.equal((await h.service.calculate([d]))[0].items.length,0);d.targetPromote=1;assert.ok((await h.service.calculate([d]))[0].items.length>0);
  d.promote=-1;await assert.rejects(h.service.calculate([d]),/突破阶段/);weapon.target=90;await assert.rejects(h.service.calculate([weapon]),/1–70/);h.close();
});
test('SQLite batch insert persists each input/result atomically and repeated save skips duplicates',async()=>{
  const h=harness();const drafts=[await h.service.offlineAvatar(10000002),await h.service.offlineAvatar(10000003)];const prepared=await h.service.calculate(drafts);
  const report=await h.service.save(1,prepared,false);assert.equal(report.added,2);assert.equal(h.rows('cultivate_entries').length,2);
  const read=await h.repo.getEntries(1);assert.equal(read.length,2);for(const entry of read){assert.equal(h.Draft.decode(entry.inputJson).itemId,entry.avatarId);assert.ok(entry.items.length>0);}
  const before=h.snapshot();const again=await h.service.save(1,prepared,false);assert.equal(again.added,0);assert.equal(again.skipped,2);assert.equal(h.snapshot(),before);
  await h.service.save(2,[prepared[0]],false);assert.equal(h.rows('cultivate_entries').length,3);h.close();
});
test('SQLite edit preserves stable ID and only unchanged-count completion; stale editor never overwrites',async()=>{
  const h=harness();const d=await h.service.offlineAvatar(10000002);const p=await h.service.calculate([d]);await h.service.save(1,p,false);
  const before=h.rows('cultivate_entries')[0];h.db.exec('UPDATE cultivate_items SET finished=1');const oldItems=h.rows('cultivate_items');
  const edit=h.Draft.decode(before.input_json);edit.entryId=before.id;edit.expectedInput=before.input_json;edit.skills[0].target=9;
  const changed=await h.service.calculate([edit]);const result=await h.service.save(1,changed,true);assert.equal(result.updated,1);assert.equal(h.rows('cultivate_entries')[0].id,before.id);
  for(const row of h.rows('cultivate_items')){const old=oldItems.find(i=>i.item_id===row.item_id);assert.equal(row.finished,old&&old.count===row.count?1:0);}
  const snapshot=h.snapshot();await assert.rejects(h.service.save(1,changed,true),/已变更/);assert.equal(h.snapshot(),snapshot);h.close();
});
test('mid-batch SQLite failure rolls back edits, materials and newly created project',async()=>{
  const h=harness();const d=await h.service.offlineAvatar(10000002);const p=await h.service.calculate([d]);const before=h.snapshot();
  h.state.failAfter=4;await assert.rejects(h.service.save(0,p,false),/disk failure/);assert.equal(h.snapshot(),before);assert.equal(h.state.rollbacks,1);
  h.state.failAfter=0;await h.service.save(1,p,false);const stable=h.snapshot();h.state.failAfter=h.state.inserts+2;
  d.target=80;d.targetPromote=6;await assert.rejects(h.service.save(1,await h.service.calculate([d]),true));assert.equal(h.snapshot(),stable);h.close();
});
test('legacy edit never invents missing progress or skill targets; cancel/preview perform zero writes',async()=>{
  const h=harness();h.db.exec("INSERT INTO cultivate_entries(project_id,avatar_id,name,icon,level,target_level,created_at) VALUES(1,10000002,'legacy','',20,90,1)");
  const e=new h.Editor();await e.edit((await h.repo.getEntries(1))[0]);assert.equal(e.drafts[0].promote,-1);assert.ok(e.drafts[0].skills.every(s=>s.current===0&&s.target===0));
  const before=h.snapshot();await e.calculate();assert.equal(e.preview.length,0);assert.match(e.message,/突破/);e.cancel();assert.equal(h.snapshot(),before);assert.equal(h.state.begins,0);h.close();
});
test('editor enforces preview, no repeat save, editable independent talents, and no write on back/cancel',async()=>{
  const h=harness();const e=new h.Editor();await e.begin([await h.service.offlineAvatar(10000002)],1);assert.equal(await e.save(),false);
  e.change(0,'target','8',1);assert.equal(e.drafts[0].skills[1].target,8);assert.equal(e.drafts[0].skills[0].target,10);
  await e.calculate();assert.equal(h.state.begins,0);assert.equal(await e.save(),true);const count=h.state.begins;assert.equal(await e.save(),false);assert.equal(h.state.begins,count);
  e.cancel();assert.equal(e.drafts.length,0);assert.equal(e.preview.length,0);h.close();
});
test('cancel and account switch discard late preparation and preview results',async()=>{
  const h=harness();const d=await h.service.offlineAvatar(10000002);const gate=defer();h.service.offlineAvatar=async()=>gate.promise;
  const e=new h.Editor();const work=e.offline('avatar',d.itemId);e.cancel();gate.resolve(d);await work;assert.equal(e.drafts.length,0);assert.equal(h.state.begins,0);
  await e.begin([d],1);const computeGate=defer();h.service.calculate=async()=>computeGate.promise;const computing=e.calculate();h.state.uid='200000002';computeGate.resolve([{draft:d,items:[]}]);await computing;
  assert.equal(e.preview.length,0);assert.equal(await e.save(),false);assert.equal(h.state.begins,0);h.close();
});
test('partial resync leaves all original drafts and saved plans untouched',async()=>{
  const h=harness();const a=await h.service.offlineAvatar(10000002),b=await h.service.offlineAvatar(10000003);a.sourceUid=h.state.uid;b.sourceUid=h.state.uid;
  const e=new h.Editor();await e.begin([a,b],1);const before=JSON.stringify(e.drafts);h.state.fetchList=async()=>[{id:a.avatarId}];h.service.fromCharacters=async()=>[a];
  await e.sync(h.state.uid);assert.equal(JSON.stringify(e.drafts),before);assert.match(e.message,/同步未应用/);assert.equal(h.state.begins,0);h.close();
});
test('snapshot bounds and nonzero group IDs reject invalid inputs before database writes',async()=>{
  const h=harness();const d=await h.service.offlineAvatar(10000002);d.name='x'.repeat(65536);
  assert.throws(()=>h.Draft.encode(d),/过大/);assert.throws(()=>h.Draft.decode('x'.repeat(65537)),/过大/);
  d.name='Ayaka';d.skills[0].groupId=0;assert.throws(()=>h.Draft.encode(d),/映射/);assert.equal(h.state.begins,0);h.close();
});
test('manual progress edits clear synced provenance while target-only edits retain it',async()=>{
  const h=harness();const d=await h.service.offlineAvatar(10000002);d.sourceUid=h.state.uid;d.sourceAt=12345;
  const e=new h.Editor();await e.begin([d],1);e.change(0,'target','80');assert.equal(e.drafts[0].sourceAt,12345);
  e.change(0,'current','5',0);assert.equal(e.drafts[0].sourceAt,0);assert.equal(e.drafts[0].skills[0].current,5);
  const weapon=await h.service.offlineWeapon(11101);assert.equal(weapon.targetPromote,4);
  weapon.current=70;weapon.promote=5;await assert.rejects(h.service.calculate([weapon]),/突破阶段/);h.close();
});
test('corrupt or future saved inputs cannot be silently reconstructed as a legacy plan',async()=>{
  const h=harness();h.db.exec(`INSERT INTO cultivate_entries(project_id,avatar_id,name,icon,level,target_level,created_at,input_json) VALUES(1,10000002,'future','',20,90,1,'{"version":99}')`);
  const e=new h.Editor();const before=h.snapshot();await e.edit((await h.repo.getEntries(1))[0]);assert.equal(e.drafts.length,0);
  assert.match(e.message,/版本|不完整/);assert.equal(h.snapshot(),before);assert.equal(h.state.begins,0);h.close();
});
test('merged material overflow rolls back before a partial result can commit',async()=>{
  const h=harness();const draft=await h.service.offlineAvatar(10000002);const before=h.snapshot();
  const material={id:202,name:'Mora',icon:'',num:Number.MAX_SAFE_INTEGER};
  await assert.rejects(h.service.save(1,[{draft,items:[material,{...material,num:1}]}],false),/安全范围/);
  assert.equal(h.snapshot(),before);h.close();
});
test('native short insert and delete returns are failures, never successful partial persistence',async()=>{
  for(const table of ['cultivate_projects','cultivate_entries','cultivate_items']){
    const h=harness();const prepared=await h.service.calculate([await h.service.offlineAvatar(10000002)]);const before=h.snapshot();
    h.state.shortTable=table;await assert.rejects(h.service.save(0,prepared,false),/写入未完成/);assert.equal(h.snapshot(),before);assert.equal(h.state.rollbacks,1);h.close();
  }
  const h=harness();const prepared=await h.service.calculate([await h.service.offlineAvatar(10000002)]);await h.service.save(1,prepared,false);
  const before=h.snapshot();h.state.shortDelete=true;await assert.rejects(h.service.save(1,prepared,true),/旧材料更新未完成/);assert.equal(h.snapshot(),before);h.close();
});

test('saved-plan filters match applicable Windows groups with same-kind OR and cross-kind AND', async () => {
  const h = harness();
  const { CultivationFilterKind: Kind, CultivationFilterToken: Token } = h.load('model/CultivationFilterToken');
  const { CultivationViewModel } = h.load('viewmodel/CultivationViewModel');
  const avatars = await h.wiki.getAvatars();
  const weapons = await h.wiki.getWeapons();
  const ids = [10000002, 10000089, 10000046, 10000048, 10000062, 11501, 11401, 13501];
  const insert = h.db.prepare(`INSERT INTO cultivate_entries
    (project_id,avatar_id,name,icon,level,target_level,created_at) VALUES (1,?,?,'',1,90,1)`);
  for (const id of ids) {
    const metadata = [...avatars, ...weapons].find(item => item.id === id);
    assert.ok(metadata, 'the filter fixture must use real bundled metadata for ' + id);
    insert.run(id, metadata.name);
  }
  const model = new CultivationViewModel();
  await model.loadPlan();
  assert.equal(model.planEntries.length, ids.length);
  const snapshot = h.snapshot();
  const filter = conditions => Array.from(model.filteredEntries(
    conditions.map(([kind, value]) => new Token(kind, value))), entry => entry.avatarId).sort((a, b) => a - b);
  const equalIds = (conditions, expected) => assert.deepEqual(filter(conditions), expected.slice().sort((a, b) => a - b));

  equalIds([], ids);
  equalIds([[Kind.Element, '火']], [10000046, 10000048]);
  equalIds([[Kind.Element, '冰'], [Kind.Element, '火']], [10000002, 10000046, 10000048, 10000062]);
  equalIds([[Kind.Element, '冰'], [Kind.Weapon, '1']], [10000002, 11501, 11401]);
  equalIds([[Kind.Element, '火'], [Kind.Weapon, '13'], [Kind.Weapon, '10'], [Kind.Quality, '5']],
    [10000046, 13501]);
  equalIds([[Kind.Target, '1'], [Kind.Element, '火'], [Kind.Quality, '5']], [10000046]);
  equalIds([[Kind.Target, '2'], [Kind.Element, '火']], [11501, 11401, 13501]);
  equalIds([[Kind.Target, '1'], [Kind.Target, '2']], ids);
  equalIds([[Kind.Name, '神里'], [Kind.Name, '胡桃']], [10000002, 10000046]);
  equalIds([[Kind.Name, '神里'], [Kind.Name, '胡桃'], [Kind.Element, '火']], [10000046]);
  equalIds([[Kind.Quality, '5']], [10000002, 10000089, 10000046, 11501, 13501]);
  equalIds([[Kind.Quality, '105']], [10000062]);
  equalIds([[Kind.Quality, '5'], [Kind.Quality, '105']],
    [10000002, 10000089, 10000046, 10000062, 11501, 13501]);

  equalIds([[Kind.Element, '未知元素']], []);
  equalIds([[Kind.Element, '未知元素'], [Kind.Weapon, '1']], [10000002, 10000089, 11501, 11401]);
  assert.equal(h.snapshot(), snapshot, 'filtering never changes the plan or its stored selection');
  assert.equal(model.currentProjectId, 1);
  h.close();
});

test('cultivation page counts the search draft toward five tokens and supports remove, commit and clear', () => {
  const h = harness();
  const { CultivationFilterKind: Kind, CultivationFilterToken: Token } = h.load('model/CultivationFilterToken');
  const source = fs.readFileSync(path.join(root, 'pages/CultivationPage.ets'), 'utf8').replaceAll('\r\n', '\n');
  const from = source.indexOf('  private filteredPlanEntries()');
  const to = source.indexOf('  @Builder\n  planTokenMenu(', from);
  assert.ok(from >= 0 && to > from);
  const code = ts.transpileModule('class FilterPage {\n' + source.slice(from, to) +
    '\n}\nmodule.exports = FilterPage;', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    reportDiagnostics: true,
  });
  assert.equal(code.diagnostics.length, 0);
  const module = { exports: {} };
  vm.runInNewContext(code.outputText, { module, CultivationFilterKind: Kind, CultivationFilterToken: Token });
  const page = new module.exports();
  const selectedTarget = { selected: true };
  const plan = { id: 1 };
  page.vm = { currentProjectId: 1, planEntries: [plan], targets: [selectedTarget],
    filteredEntries: tokens => tokens.length === 0 ? [plan] : tokens };
  page.planSearch = '';
  page.planTokens = [];
  assert.equal(page.filteredPlanEntries()[0], plan);

  const choices = [[Kind.Element, '火'], [Kind.Element, '冰'], [Kind.Weapon, '1'], [Kind.Quality, '5']];
  for (const [kind, value] of choices) page.setPlanToken(new Token(kind, value), true);
  assert.equal(page.planTokens.length, 4);
  page.planSearch = '  胡桃  ';
  assert.equal(page.effectivePlanTokens().length, 5, 'an unsubmitted search is the fifth condition');
  assert.equal(page.filteredPlanEntries()[4].value, '胡桃');
  page.setPlanToken(new Token(Kind.Target, '1'), true);
  assert.equal(page.planTokens.length, 4, 'a menu callback cannot add a sixth effective condition');
  page.commitPlanSearch(page.planSearch);
  assert.equal(page.planSearch, '');
  assert.equal(page.planTokens.length, 5);
  page.setPlanToken(new Token(Kind.Target, '1'), true);
  assert.equal(page.planTokens.length, 5);
  page.setPlanToken(new Token(Kind.Element, '火'), false);
  assert.equal(page.planTokens.length, 4);
  page.setPlanToken(new Token(Kind.Target, '1'), true);
  assert.equal(page.planTokens.length, 5, 'removing a chip frees a slot');

  page.clearPlanFilters();
  assert.equal(page.planSearch, '');
  assert.equal(page.planTokens.length, 0);
  page.planSearch = 'Ayaka';
  page.commitPlanSearch(page.planSearch);
  page.planSearch = ' ayaka ';
  page.commitPlanSearch(page.planSearch);
  assert.equal(page.planTokens.length, 1, 'repeated names share one condition');
  assert.equal(page.planSearch, '');
  page.planSearch = 'Hu Tao';
  page.setPlanToken(new Token(Kind.Quality, '5'), true);
  assert.equal(page.planSearch, 'Hu Tao', 'choosing another group preserves the search draft');
  assert.equal(page.effectivePlanTokens().length, 3);
  page.clearPlanFilters();
  assert.equal(page.filteredPlanEntries()[0], plan);
  assert.equal(page.vm.currentProjectId, 1);
  assert.equal(page.vm.targets[0], selectedTarget);
  assert.equal(selectedTarget.selected, true, 'filter controls preserve the selected cultivation targets');
  assert.match(source, /\.onSubmit\(\(value: string\): void => this\.commitPlanSearch\(value\)\)/);
  assert.match(source, /\.onChange\(\(selected: boolean\): void => this\.setPlanToken\(new CultivationFilterToken\(kind, value\), selected\)\)/);
  h.close();
});

test('cultivation and wiki routes keep local plans accessible and prepare editable drafts before save',()=>{
  const read=name=>fs.readFileSync(path.join(root,'pages',name+'.ets'),'utf8');
  // character-page-actions.cjs executes the current, selected, all and weapon-only menu and button actions.
  const cultivation=read('CultivationPage');assert.match(cultivation,/this.draftVm.edit\(entry\)/);assert.match(cultivation,/Number\(area.width\)|newValue.width/);assert.match(cultivation,/>= 840/);assert.doesNotMatch(cultivation.slice(cultivation.indexOf('  build()')),/this.loginGuide\(/);
  for(const page of ['WikiAvatarPage','WikiWeaponPage']){assert.match(read(page),/CultivationDraftEditor/);assert.doesNotMatch(read(page),/await CultivationRepo.createProject/);}
  const editor=fs.readFileSync(path.join(root,'components/CultivationDraftEditor.ets'),'utf8');assert.match(editor,/重新同步当前进度（保留目标）/);assert.match(editor,/\.height\(44\)/);assert.match(editor,/text: this.fieldText/);
});
