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
  db.exec(`CREATE TABLE cultivate_projects(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT,created_at INTEGER);
    CREATE TABLE cultivate_entries(id INTEGER PRIMARY KEY AUTOINCREMENT,project_id INTEGER,avatar_id INTEGER,name TEXT,icon TEXT,level INTEGER,target_level INTEGER,created_at INTEGER,input_json TEXT NOT NULL DEFAULT '');
    CREATE TABLE cultivate_items(id INTEGER PRIMARY KEY AUTOINCREMENT,entry_id INTEGER,item_id INTEGER,name TEXT,icon TEXT,count INTEGER,finished INTEGER);
    INSERT INTO cultivate_projects VALUES(1,'One',1); INSERT INTO cultivate_projects VALUES(2,'Two',2);`);
  const state = { uid:'100000001', user:1, begins:0, commits:0, rollbacks:0, inserts:0, failAfter:0, shortTable:'', shortDelete:false, open:0, closed:0, fetchList:async()=>[], gate:undefined };
  class Pred {
    constructor(table){this.table=table;this.terms=[];this.values=[];this.order='';}
    equalTo(key,value){this.terms.push(`${key}=?`);this.values.push(value);return this;}
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
    batchInsertSync(table,rows){for(const row of rows)this.insertSync(table,row);return rows.length;},
  };
  const avatarMeta=JSON.parse(fs.readFileSync(path.resolve(root,'../resources/rawfile/metadata/avatar_meta.json'),'utf8'));
  const weaponMeta=JSON.parse(fs.readFileSync(path.resolve(root,'../resources/rawfile/metadata/weapon_meta.json'),'utf8'));
  const wiki={getAvatars:async()=>avatarMeta,getWeapons:async()=>weaponMeta,getMaterials:async()=>new Map(),iconOfAvatar:()=>''};
  const mocks={
    '@kit.ArkData':{relationalStore:{RdbPredicates:Pred}},
    RelationalStoreHelper:{getStore:()=>store,query:async pred=>query(pred)},
    Logger:{info(){},warn(){}},ApiClient:{},ApiResponse:class{},HoyolabClient:{},DsSigner:{},RiskVerifier:{},RiskControlError:class extends Error{},
    Constants:{RegionUtil:{regionOfUid:()=> 'cn_gf01'},AppConstants:{}},
    UserService:{getInstance:()=>({getCurrentUser:()=>({id:state.user})})},
    CharacterService:{getInstance:()=>({fetchList:(...args)=>state.fetchList(...args)})},
    WikiMetaService:wiki,
  };
  const cache=new Map();
  function load(relative){
    const file=path.resolve(root,relative.endsWith('.ets')?relative:relative+'.ets');if(cache.has(file))return cache.get(file).exports;
    const result=ts.transpileModule(fs.readFileSync(file,'utf8'),{fileName:file.replace('.ets','.ts'),compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true},reportDiagnostics:true});
    assert.equal(result.diagnostics.length,0,file);const module={exports:{}};cache.set(file,module);
    function requireLocal(name){if(mocks[name])return mocks[name];const key=path.basename(name);if(key==='Constants')return mocks.Constants;if(mocks[key])return {[key]:mocks[key]};return load(path.resolve(path.dirname(file),name));}
    vm.runInNewContext('(function(require,module,exports){'+result.outputText+'\n})',{Observed:target=>target,AppStorage:{get:()=>state.uid},Date,Map,Set,Error,Number,Array,JSON})(requireLocal,module,module.exports);
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
  return {db,state,Draft,repo,service,Editor,calculator,rows,snapshot,close,load};
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
test('UI routes prepare editable drafts before save and do not hide local plans behind login',()=>{
  const read=name=>fs.readFileSync(path.join(root,'pages',name+'.ets'),'utf8');
  const character=read('CharacterPage');assert.match(character,/规划所选/);assert.match(character,/全部规划/);assert.match(character,/规划当前装备武器/);assert.match(character,/draftVm.characters/);assert.doesNotMatch(character,/vm.addAvatarToPlan/);
  const cultivation=read('CultivationPage');assert.match(cultivation,/this.draftVm.edit\(entry\)/);assert.match(cultivation,/Number\(area.width\)|newValue.width/);assert.match(cultivation,/>= 840/);assert.doesNotMatch(cultivation.slice(cultivation.indexOf('  build()')),/this.loginGuide\(/);
  for(const page of ['WikiAvatarPage','WikiWeaponPage']){assert.match(read(page),/CultivationDraftEditor/);assert.doesNotMatch(read(page),/await CultivationRepo.createProject/);}
  const editor=fs.readFileSync(path.join(root,'components/CultivationDraftEditor.ets'),'utf8');assert.match(editor,/重新同步当前进度（保留目标）/);assert.match(editor,/\.height\(44\)/);assert.match(editor,/text: this.fieldText/);
});
