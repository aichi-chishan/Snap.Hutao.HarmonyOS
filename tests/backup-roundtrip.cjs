// Execute production backup code with deterministic storage fault injection (no device/account data).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const base = path.resolve(__dirname, '../entry/src/main/ets');
const cache = new Map();
let db, prefs, vault, failTable, failVault, writes, prefsFail, sessionReloads, journal, commitError;
const clone = value => JSON.parse(JSON.stringify(value));
const columns = {
  user_accounts: ['id','mid','aid','is_oversea','display_nickname','avatar','created_at','is_selected','cookie_account_token','cookie_ltoken_ltuid','cookie_stoken_stuid'],
  user_game_roles: ['id','user_id','game_uid','region','nickname','level','is_default','is_chosen'],
  gacha_archives: ['id','uid','is_selected','timezone'], gacha_items:['id','archive_id','gacha_id','gacha_type','item_id','count','time','name','item_type','rank_type','schedule_id'],
  achievement_archives:['id','name','created_at','is_selected'], achievement_entries:['id','archive_id','ach_id','current','timestamp','status'],
  cultivate_projects:['id','name','created_at'], cultivate_entries:['id','project_id','avatar_id','name','icon','level','target_level','created_at'], cultivate_items:['id','entry_id','item_id','name','icon','count','finished'],
  cultivate_inventory:['project_id','item_id','count'],
  daily_notes:['id','user_id','uid','raw_json'], sign_in_info:['id','user_id'], act_calendar_entries:['id'], announcements:['id'],
  abyss_history:['schedule_id','raw_json'], role_combat_history:['schedule_id','raw_json'], hard_challenge_history:['schedule_id','raw_json'],
  challenge_records:['kind','uid','region','schedule_id','start_time','end_time','total_star','raw_json','record_time'],
  backpack_archives:['id','name','uid','is_selected','created_at','updated_at','source','document_json'],
  backpack_items:['archive_id','instance_id','item_id','kind','category','raw_json']
};
function rs(rows, names) { let index = -1; return { columnNames: names, goToNextRow:()=>++index < rows.length, goToFirstRow:()=>{index=0;return rows.length>0}, getValue:i=>rows[index][names[i]]??null, getLong:i=>Number(rows[index][names[i]]), getString:i=>String(rows[index][names[i]]), close(){} }; }
function query(data, sql) {
  if(sql.includes('SELECT marker FROM backup_recovery')) return rs(clone(data.backup_recovery),['marker']);
  if(sql.includes('MAX(value)')) return rs([{max_id:10}],['max_id']);
  const name = sql.match(/SELECT \* FROM (\w+)/)[1];
  return rs(sql.includes('LIMIT 0')?[]:clone(data[name]), columns[name]);
}
const store = { version:7, querySql:async sql=>query(db,sql), createTransaction: async()=> {
  const staged = clone(db);
  return { querySql:async sql=>query(staged,sql), delete:async pred=>{writes++;staged[pred.table]=[]}, insert:async(name,row)=>{writes++;if(name===failTable)throw Error('injected write failure'); staged[name].push(clone(row)); return row.id??0;}, commit:async()=>{db=staged;if(commitError)throw Error('commit status uncertain')}, rollback:async()=>{if(commitError)throw Error('transaction already closed')} };
}};
const mocks = {
  '@kit.ArkData': {relationalStore:{TransactionType:{IMMEDIATE:1},RdbPredicates:class {constructor(table){this.table=table}}}},
  RelationalStoreHelper:{getStore:()=>store},
  TokenVault:{loadCookie:async id=>vault[id]??'',saveCookie:async(id,cookie)=>{if(failVault)throw Error('injected vault failure');vault[id]=cookie},removeCookie:async id=>{delete vault[id]}},
  PreferencesStore:{KEY_CURRENT_USER_ID:'app.current_user_id',KEY_CURRENT_UID:'app.current_uid',exportPortable:()=>clone(prefs),getBackupJournal:()=>journal,saveBackupJournal:async text=>{journal=text},replacePortable:async value=>{prefs=clone(value);if(prefsFail){prefsFail=false;throw Error('injected preference failure')}},getRefreshIntervalMinutes:()=>30},
  DailyNoteService:{getInstance:()=>({isTimerRunning:()=>true,stopAutoRefresh(){},startAutoRefresh(){}})},
  UserService:{getInstance:()=>({reloadLocalSession:async()=>{sessionReloads++}})},
  Logger:{warn(){},info(){}}
};
function load(name) {
  const file=path.resolve(base,name.endsWith('.ets')?name:`${name}.ets`);
  if(cache.has(file))return cache.get(file);
  const output=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
  const module={exports:{}};
  const req=id=>{if(id==='@kit.ArkData')return mocks[id];const key=path.basename(id);if(mocks[key])return {[key]:mocks[key]};return load(path.relative(base,path.resolve(path.dirname(file),id)));};
  vm.runInNewContext(`(function(require,module,exports){${output}\n})`,{AppStorage:{setOrCreate(){}}})(req,module,module.exports);
  cache.set(file,module.exports);return module.exports;
}
const {BackupService}=load('service/BackupService');
const {BackupSnapshotValidator}=load('model/BackupSnapshot');
function reset(){
  db=Object.fromEntries(Object.keys(columns).map(name=>[name,[]]));
  db.backup_recovery=[];journal='';
  db.user_accounts=[{id:1,mid:'old-mid',aid:'old-aid',is_oversea:0,display_nickname:'fixture',avatar:'',created_at:1,is_selected:1,cookie_account_token:'',cookie_ltoken_ltuid:'',cookie_stoken_stuid:''}];
  db.user_game_roles=[{id:1,user_id:1,game_uid:'100000001',region:'cn_gf01',nickname:'fixture',level:1,is_default:1,is_chosen:1}];
  db.cultivate_projects=[{id:1,name:'fixture project',created_at:1}];
  db.challenge_records=[{kind:'abyss',uid:'100000001',region:'cn_gf01',schedule_id:1,start_time:1,end_time:2,total_star:36,raw_json:'{}',record_time:1}];
  prefs={'app.current_user_id':1,'app.current_uid':'100000001','theme.mode':'dark','dailynote.tracked_1':'["100000001"]'};
  vault={1:'fixture-old-cookie'};failTable='';failVault=false;writes=0;prefsFail=false;sessionReloads=0;commitError=false;
}
(async()=>{
 const service=BackupService.getInstance();reset();
 const text=await service.buildBackupJson(); const snapshot=JSON.parse(text);
 assert.equal(snapshot.version,2);assert.equal(snapshot.tables.length,Object.keys(columns).length);
 for(const key of ['app.device_id','app.device_fp','app.cookie','authkey','theme.password'])assert.equal(BackupSnapshotValidator.portableKey(key),false);
 for(const mutate of [s=>delete s.tables,s=>s.version=99,s=>s.schemaVersion=99,s=>s.tables.pop(),s=>s.credentials=[],s=>s.preferences['app.device_id']='forbidden',s=>s.tables[0].rows[0].unexpected='field',s=>s.tables.find(t=>t.name==='user_game_roles').rows[0].user_id=999]){
  reset();const bad=clone(snapshot);mutate(bad);const before=clone(db);const result=await service.restoreFromText(JSON.stringify(bad));assert.equal(result.ok,false);assert.equal(writes,0);assert.deepEqual(db,before);assert.equal(vault[1],'fixture-old-cookie');
 }
 reset();failVault=true;assert.equal((await service.restoreFromText(text)).ok,false);assert.equal(writes,0);assert.equal(vault[1],'fixture-old-cookie');
 reset();const old=clone(db);failTable='user_game_roles';assert.equal((await service.restoreFromText(text)).ok,false);assert.deepEqual(db,old);assert.deepEqual(vault,{1:'fixture-old-cookie'});
 reset();const oldPrefs=clone(prefs);prefsFail=true;assert.equal((await service.restoreFromText(text)).ok,false);assert.deepEqual(prefs,oldPrefs);assert.equal(db.user_accounts[0].id,1);assert.deepEqual(vault,{1:'fixture-old-cookie'});
 reset();assert.equal((await service.restoreFromText(text)).ok,true);assert.equal(db.user_accounts[0].id,11);assert.equal(db.user_game_roles[0].user_id,11);assert.equal(vault[11],'fixture-old-cookie');assert.equal(vault[1],undefined);assert.equal(prefs['app.current_user_id'],11);assert.equal(prefs['dailynote.tracked_11'],'["100000001"]');assert.equal(prefs['dailynote.tracked_1'],undefined);assert.equal(db.challenge_records[0].total_star,36);assert.equal(db.cultivate_projects[0].name,'fixture project');assert.equal(sessionReloads,1);
 reset();const legacy={app:'snaphutao-harmonyos-backup',version:1,users:[],gacha:[],achievements:[],prefs:{themeMode:'system',refreshInterval:30,autoRefresh:true,ambientStrength:0.25,dailyBgEnabled:true,bgImageType:'none',bgFolderPath:'',geetestUrl:'',currentUid:''}};
 assert.equal((await service.restoreFromText(JSON.stringify(legacy))).ok,true);assert.equal(db.user_accounts.length,0);assert.equal(db.cultivate_projects.length,1);assert.equal(db.challenge_records.length,1);assert.equal(prefs['app.current_uid'],'');
 reset();delete legacy.gacha;assert.equal((await service.restoreFromText(JSON.stringify(legacy))).ok,false);assert.equal(writes,0);
 reset();commitError=true;const uncertain=await service.restoreFromText(text);
 assert.equal(uncertain.ok,false);assert.equal(db.user_accounts[0].id,11);assert.equal(vault[11],'fixture-old-cookie');assert.equal(vault[1],'fixture-old-cookie');assert.notEqual(journal,'');
 assert.equal((await service.restoreFromText(text)).ok,false);commitError=false;await service.recoverInterruptedRestore();assert.equal(vault[11],'fixture-old-cookie');assert.equal(vault[1],undefined);assert.equal(journal,'');
 reset();const oldRecoveryPrefs=clone(prefs);const nextRecoveryPrefs={'app.current_user_id':11,'theme.mode':'light'};
 journal=JSON.stringify({marker:'fixture-commit',oldPreferences:oldRecoveryPrefs,nextPreferences:nextRecoveryPrefs,oldUsers:[1],newUsers:[11]});
 vault[11]='fixture-staged';prefs=clone(nextRecoveryPrefs);await service.recoverInterruptedRestore();
 assert.deepEqual(prefs,oldRecoveryPrefs);assert.equal(vault[11],undefined);assert.equal(vault[1],'fixture-old-cookie');assert.equal(journal,'');
 reset();journal=JSON.stringify({marker:'fixture-commit',oldPreferences:oldRecoveryPrefs,nextPreferences:nextRecoveryPrefs,oldUsers:[1],newUsers:[11]});
 db.backup_recovery=[{id:1,marker:'fixture-commit'}];vault[11]='fixture-staged';await service.recoverInterruptedRestore();
 assert.deepEqual(prefs,nextRecoveryPrefs);assert.equal(vault[1],undefined);assert.equal(vault[11],'fixture-staged');assert.equal(journal,'');
 console.log('backup-roundtrip: PASS (complete snapshot, legacy, schema/shape/ref rejection, credential staging, transactional and preference failure recovery, account remap)');
})().catch(error=>{console.error(error);process.exitCode=1});
