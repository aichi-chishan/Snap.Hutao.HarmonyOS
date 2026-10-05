// Execute production DB migrations, snapshot validation, UIIF codec and backup service
// against real SQLite. Only vault/preferences/session/native SDK boundaries are doubled.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { DatabaseSync } = require('node:sqlite');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const clone = value => JSON.parse(JSON.stringify(value));
const uid = '100000001';
const weapon = '{"itemId":11501,"guid":18446744073709551615,"equip":{"weapon":{"level":90,"promoteLevel":6,"affixMap":{"111501":4}},"isLocked":true},"extension":18446744073709551614}';
const material = '{"itemId":104003,"material":{"count":12},"unknown":{"exact":18446744073709551613}}';
const document = '{"info":{"uiif_version":"v1.0","uid":"100000001","export_app":"fixture"},"list":[],"extension":18446744073709551612}';
const legacy = { app:'snaphutao-harmonyos-backup', version:1, users:[], gacha:[], achievements:[], prefs:{
  themeMode:'system', refreshInterval:30, autoRefresh:true, ambientStrength:0.25, dailyBgEnabled:true,
  bgImageType:'none', bgFolderPath:'', geetestUrl:'', currentUid:''
}};
class Predicates { constructor(table) { this.table = table; } }

function harness() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys=ON');
  const state = { writes:0, begins:0, commits:0, rollbacks:0, resultSets:0, closedSets:0,
    failSql:'', failInsert:'', failDelete:'', failVersion:false, failCommit:false,
    failPrefs:false, failVault:false, journal:'', prefs:{'theme.mode':'dark'}, vault:{}, reloads:0 };
  function resultSet(sql) {
    const stmt = db.prepare(sql), rows = stmt.all(), names = stmt.columns().map(column => column.name);
    let index = -1, closed = false;
    state.resultSets++;
    return { columnNames:names, goToNextRow:()=>++index < rows.length,
      goToFirstRow:()=>{ index=0; return rows.length>0; },
      getValue:i=>rows[index][names[i]], getLong:i=>Number(rows[index][names[i]]),
      getString:i=>String(rows[index][names[i]]),
      close(){ assert.equal(closed,false); closed=true; state.closedSets++; } };
  }
  const store = {
    get version() { return db.prepare('PRAGMA user_version').get().user_version; },
    set version(value) { db.exec('PRAGMA user_version='+Number(value)); if(state.failVersion&&value===7)throw Error('injected version failure'); },
    async executeSql(sql) { if(state.failSql&&sql.includes(state.failSql))throw Error('injected CREATE failure'); db.exec(sql); },
    beginTransaction() { state.begins++; db.exec('BEGIN'); },
    commit() { if(state.failCommit)throw Error('injected commit failure'); db.exec('COMMIT'); state.commits++; },
    rollBack() { db.exec('ROLLBACK'); state.rollbacks++; },
    async querySql(sql) { return resultSet(sql); },
    async createTransaction() {
      store.beginTransaction();
      return { querySql:async sql=>resultSet(sql),
        delete:async pred=>{ state.writes++; if(pred.table===state.failDelete)throw Error('injected delete failure'); return db.prepare('DELETE FROM '+pred.table).run().changes; },
        insert:async(table,row)=>{ state.writes++; if(table===state.failInsert)throw Error('injected insert failure');
          const names=Object.keys(row); return Number(db.prepare(`INSERT INTO ${table} (${names}) VALUES (${names.map(()=>'?')})`).run(...Object.values(row)).lastInsertRowid); },
        commit:async()=>store.commit(), rollback:async()=>store.rollBack() };
    }
  };
  const mocks = {
    '@kit.ArkData':{ relationalStore:{ getRdbStore:async()=>store, SecurityLevel:{S1:1}, TransactionType:{IMMEDIATE:1}, RdbPredicates:Predicates } },
    Logger:{ info(){}, warn(){} },
    TokenVault:{ loadCookie:async id=>state.vault[id]??'', saveCookie:async(id,cookie)=>{ if(state.failVault)throw Error('injected vault failure'); state.vault[id]=cookie; }, removeCookie:async id=>{ delete state.vault[id]; } },
    PreferencesStore:{ KEY_CURRENT_USER_ID:'app.current_user_id', KEY_CURRENT_UID:'app.current_uid', exportPortable:()=>clone(state.prefs),
      getBackupJournal:()=>state.journal, saveBackupJournal:async text=>{ state.journal=text; },
      replacePortable:async value=>{ state.prefs=clone(value); if(state.failPrefs){ state.failPrefs=false; throw Error('injected preferences failure'); } }, getRefreshIntervalMinutes:()=>30 },
    DailyNoteService:{ getInstance:()=>({ isTimerRunning:()=>true, stopAutoRefresh(){}, startAutoRefresh(){} }) },
    UserService:{ getInstance:()=>({ reloadLocalSession:async()=>{state.reloads++;} }) }
  };
  const cache = new Map();
  function load(relative) {
    const filename = path.resolve(root, relative.endsWith('.ets')?relative:relative+'.ets');
    if(cache.has(filename))return cache.get(filename);
    const compiled=ts.transpileModule(fs.readFileSync(filename,'utf8'), {fileName:filename.replace(/\.ets$/,'.ts'),
      compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}, reportDiagnostics:true });
    assert.equal(compiled.diagnostics.length,0,filename);
    const module={exports:{}}; cache.set(filename,module.exports);
    const requireLocal=id=>{ if(mocks[id])return mocks[id]; const key=path.basename(id); if(mocks[key])return {[key]:mocks[key]};
      assert.ok(id.startsWith('.'),'unexpected dependency '+id); return load(path.resolve(path.dirname(filename),id)); };
    vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`,{AppStorage:{setOrCreate(){}}})(requireLocal,module,module.exports);
    return module.exports;
  }
  const helper=load('data/db/RelationalStoreHelper').RelationalStoreHelper;
  const service=load('service/BackupService').BackupService.getInstance();
  const validator=load('model/BackupSnapshot').BackupSnapshotValidator;
  const converter=load('model/LegacyBackup').LegacyBackup;
  async function init() { await helper.init({}); state.writes=0; }
  function seed() {
    db.exec(`INSERT INTO user_accounts(id,mid,is_selected,created_at) VALUES(1,'fixture',1,1);
      INSERT INTO user_game_roles(id,user_id,game_uid,region,is_default) VALUES(1,1,'${uid}','cn_gf01',1);
      INSERT INTO cultivate_projects(id,name,created_at) VALUES(1,'keep cultivation',1);
      INSERT INTO challenge_records(kind,uid,region,schedule_id,raw_json,record_time) VALUES('abyss','${uid}','cn_gf01',7,'keep history',1);`);
    const archive=db.prepare('INSERT INTO backpack_archives(id,name,uid,is_selected,created_at,updated_at,source,document_json) VALUES(?,?,?,?,?,?,?,?)');
    archive.run(1,'keep backpack',uid,1,1,2,'fixture',document);
    archive.run(2,'another UID','700000002',0,1,2,'manual','{"info":{"uiif_version":"v1.0"},"list":[]}');
    const item=db.prepare('INSERT INTO backpack_items(archive_id,instance_id,item_id,kind,category,raw_json) VALUES(?,?,?,?,?,?)');
    item.run(1,'guid:18446744073709551615',11501,'weapon',0,weapon);
    item.run(1,'local:2',104003,'material',4,material);
    item.run(2,'local:1',361101,'furniture',8,'{"itemId":361101,"furniture":{"count":2}}');
    state.vault={1:'fixture-cookie'};
    state.prefs={'app.current_user_id':1,'app.current_uid':uid,'theme.mode':'dark'};
  }
  const rows=name=>clone(db.prepare('SELECT * FROM '+name).all());
  const backpack=()=>({archives:rows('backpack_archives'),items:rows('backpack_items')});
  const all=()=>Object.fromEntries(validator.TABLES.concat('backup_recovery').map(name=>[name,rows(name)]));
  const close=()=>{ assert.equal(state.resultSets,state.closedSets,'every result set must close'); db.close(); };
  return {db,state,store,helper,service,validator,converter,init,seed,rows,backpack,all,close};
}
const table=(snapshot,name)=>snapshot.tables.find(value=>value.name===name);

function strictModelTypes() {
  const virtualRoot='/backup-model-types', files=new Map();
  for(const name of ['BackupSnapshot','LegacyBackup','BackpackData','UIIFCodec']) {
    files.set(`${virtualRoot}/${name}.ts`,fs.readFileSync(path.join(root,'model',name+'.ets'),'utf8'));
  }
  const options={strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,skipLibCheck:true};
  const host=ts.createCompilerHost(options), original={fileExists:host.fileExists,readFile:host.readFile,getSourceFile:host.getSourceFile,directoryExists:host.directoryExists};
  host.fileExists=file=>files.has(file)||original.fileExists(file);
  host.readFile=file=>files.get(file)??original.readFile(file);
  host.getSourceFile=(file,version,...rest)=>files.has(file)?ts.createSourceFile(file,files.get(file),version,true):original.getSourceFile(file,version,...rest);
  host.directoryExists=directory=>[...files.keys()].some(file=>file.startsWith(directory+'/'))||original.directoryExists(directory);
  const diagnostics=ts.getPreEmitDiagnostics(ts.createProgram([...files.keys()],options,host));
  assert.equal(diagnostics.length,0,diagnostics.map(value=>ts.flattenDiagnosticMessageText(value.messageText,'\n')).join('\n'));
}

(async()=>{
  await test('fresh production migration creates v7 tables and a real foreign key without orphans',async()=>{
    const h=harness(); await h.init(); assert.equal(h.store.version,7);
    assert.equal(h.db.prepare('PRAGMA foreign_key_list(backpack_items)').all()[0].table,'backpack_archives');
    assert.throws(()=>h.db.exec(`INSERT INTO backpack_items VALUES(99,'local:1',1,'material',9,'{}')`),/FOREIGN KEY/);
    assert.equal(h.rows('backpack_items').length,0); h.close();
  });
  await test('v7 CREATE, version-stamp and commit failures roll back DDL and retry from v6',async()=>{
    for(const mode of ['create','version','commit']) {
      const h=harness(); await h.init(); h.seed();
      h.db.exec('DROP TABLE backpack_items; DROP TABLE backpack_archives; PRAGMA user_version=6');
      h.helper.rdbStore=undefined;
      if(mode==='create')h.state.failSql='CREATE TABLE IF NOT EXISTS backpack_items';
      if(mode==='version')h.state.failVersion=true;
      if(mode==='commit')h.state.failCommit=true;
      await assert.rejects(h.helper.init({}),/数据库升级 v6 失败/);
      assert.equal(h.store.version,6,mode); assert.equal(h.helper.isReady(),false);
      assert.equal(h.db.prepare("SELECT count(*) AS n FROM sqlite_master WHERE name IN ('backpack_archives','backpack_items')").get().n,0);
      assert.equal(h.rows('challenge_records')[0].raw_json,'keep history');
      h.state.failSql=''; h.state.failVersion=false; h.state.failCommit=false;
      await h.init(); assert.equal(h.store.version,7); assert.equal(h.helper.isReady(),true); h.close();
    }
  });
  await test('v7 production capture/restore is lossless with reversed table order and foreign keys enabled',async()=>{
    const h=harness(); await h.init(); h.seed(); const before=h.backpack();
    const snapshot=JSON.parse(await h.service.buildBackupJson()); assert.equal(snapshot.schemaVersion,7); assert.equal(snapshot.tables.length,20);
    snapshot.tables.reverse(); h.db.exec("UPDATE backpack_archives SET name='replace me'; DELETE FROM backpack_items WHERE archive_id=1");
    const result=await h.service.restoreFromText(JSON.stringify(snapshot)); assert.equal(result.ok,true,result.message);
    assert.deepEqual(h.backpack(),before); assert.equal(h.rows('challenge_records')[0].raw_json,'keep history');
    const exported=JSON.parse(await h.service.buildBackupJson());
    assert.equal(table(exported,'backpack_archives').rows[0].document_json,document);
    assert.equal(table(exported,'backpack_items').rows.find(row=>row.kind==='weapon').raw_json,weapon);
    assert.equal(h.db.prepare('PRAGMA foreign_key_check').all().length,0); assert.equal(h.state.journal,''); h.close();
  });
  await test('all schema1–6 snapshots preserve v7 backpack state and legacy conversion never stamps v7',async()=>{
    for(let schemaVersion=1;schemaVersion<=6;schemaVersion++) {
      const h=harness(); await h.init(); h.seed(); const before=h.backpack();
      const old=JSON.parse(await h.service.buildBackupJson()); old.schemaVersion=schemaVersion;
      old.tables=old.tables.filter(value=>!value.name.startsWith('backpack_'));
      const result=await h.service.restoreFromText(JSON.stringify(old)); assert.equal(result.ok,true,result.message);
      assert.deepEqual(h.backpack(),before); assert.equal(h.rows('challenge_records')[0].raw_json,'keep history'); h.close();
    }
    const h=harness(); await h.init(); h.seed(); const before=h.backpack();
    const converted=h.converter.convert(legacy,7); assert.equal(converted.schemaVersion,6);
    assert.equal(converted.tables.some(value=>value.name.startsWith('backpack_')),false);
    const result=await h.service.restoreFromText(JSON.stringify(legacy)); assert.equal(result.ok,true,result.message);
    assert.deepEqual(h.backpack(),before); assert.equal(h.rows('challenge_records')[0].raw_json,'keep history');
    assert.equal(h.rows('cultivate_projects')[0].name,'keep cultivation'); h.close();
  });
  await test('schema7 requires both tables and malformed rows fail before any SQL mutation or credential staging',async()=>{
    const h=harness(); await h.init(); h.seed(); const baseline=JSON.parse(await h.service.buildBackupJson());
    const mutations=[
      s=>s.tables.splice(s.tables.findIndex(t=>t.name==='backpack_items'),1),
      s=>s.tables.splice(s.tables.findIndex(t=>t.name==='backpack_archives'),1),
      s=>s.schemaVersion=6,
      s=>table(s,'backpack_archives').rows[0].id='1',
      s=>table(s,'backpack_archives').rows[0].uid=100000001,
      s=>table(s,'backpack_archives').rows[0].uid='000000001',
      s=>table(s,'backpack_archives').rows[0].name=' ',
      s=>table(s,'backpack_archives').rows[0].name='x'.repeat(81),
      s=>table(s,'backpack_archives').rows[0].source='x'.repeat(201),
      s=>table(s,'backpack_archives').rows[0].created_at=-1,
      s=>table(s,'backpack_archives').rows[0].updated_at=1.1,
      s=>table(s,'backpack_archives').rows[1].is_selected=1,
      s=>table(s,'backpack_archives').rows.push(clone(table(s,'backpack_archives').rows[0])),
      s=>table(s,'backpack_archives').rows[0].document_json='[]',
      s=>table(s,'backpack_archives').rows[0].document_json='{"info":{"uiif_version":"v9"},"list":[]}',
      s=>table(s,'backpack_archives').rows[0].document_json='{"info":{"uiif_version":"v1.0","uid":"100000002"},"list":[]}',
      s=>table(s,'backpack_archives').rows[0].document_json='{"info":{"uiif_version":"v1.0"},"list":['+material+']}',
      s=>table(s,'backpack_items').rows[0].archive_id=999,
      s=>table(s,'backpack_items').rows[0].archive_id='1',
      s=>table(s,'backpack_items').rows[0].instance_id='',
      s=>table(s,'backpack_items').rows[0].instance_id='x'.repeat(161),
      s=>table(s,'backpack_items').rows[0].instance_id='guid:rounded',
      s=>table(s,'backpack_items').rows[0].item_id=4294967296,
      s=>table(s,'backpack_items').rows[0].item_id=11502,
      s=>table(s,'backpack_items').rows[0].kind='equip',
      s=>table(s,'backpack_items').rows[0].kind='material',
      s=>table(s,'backpack_items').rows[0].category=1,
      s=>table(s,'backpack_items').rows[1].category=8,
      s=>table(s,'backpack_items').rows[1].category='4',
      s=>table(s,'backpack_items').rows[1].category=10,
      s=>table(s,'backpack_items').rows[0].raw_json='{',
      s=>table(s,'backpack_items').rows[0].raw_json='null',
      s=>table(s,'backpack_items').rows[0].raw_json='{"itemId":11501,"equip":{"weapon":{"level":90}}}',
      s=>table(s,'backpack_items').rows[1].raw_json='{"itemId":104003,"itemId":104003,"material":{"count":12}}',
      s=>table(s,'backpack_items').rows.push(clone(table(s,'backpack_items').rows[1])),
      s=>{const row=clone(table(s,'backpack_items').rows[1]);row.instance_id='another-stack';table(s,'backpack_items').rows.push(row);}
    ];
    const before=h.all(), vault=clone(h.state.vault);
    for(let i=0;i<mutations.length;i++) {
      const invalid=clone(baseline); mutations[i](invalid); h.state.writes=0;
      const result=await h.service.restoreFromText(JSON.stringify(invalid)); assert.equal(result.ok,false,`case ${i}`);
      assert.equal(h.state.writes,0,`case ${i}`); assert.deepEqual(h.all(),before,`case ${i}`);
      assert.deepEqual(h.state.vault,vault); assert.equal(h.state.journal,'');
    }
    h.close();
  });
  await test('backpack insert/delete failures, preference failures and commit failures restore the full SQLite state',async()=>{
    for(const mode of ['insert','delete','preferences','commit','vault']) {
      const h=harness(); await h.init(); h.seed(); const text=await h.service.buildBackupJson();
      const before=h.all(), prefs=clone(h.state.prefs), vault=clone(h.state.vault);
      if(mode==='insert')h.state.failInsert='backpack_items';
      if(mode==='delete')h.state.failDelete='backpack_archives';
      if(mode==='preferences')h.state.failPrefs=true;
      if(mode==='commit')h.state.failCommit=true;
      if(mode==='vault')h.state.failVault=true;
      const result=await h.service.restoreFromText(text); assert.equal(result.ok,false,mode);
      assert.deepEqual(h.all(),before,mode); assert.deepEqual(h.state.prefs,prefs,mode); assert.deepEqual(h.state.vault,vault,mode);
      assert.equal(h.state.journal,''); assert.equal(h.db.prepare('PRAGMA foreign_key_check').all().length,0); h.close();
    }
  });
  await test('capture refuses corrupt persisted UIIF data and cannot emit orphan snapshot rows',async()=>{
    const h=harness(); await h.init(); h.seed(); h.db.exec("UPDATE backpack_items SET raw_json='{}' WHERE kind='weapon'");
    await assert.rejects(h.service.buildBackupJson(),/itemId/);
    h.db.exec('PRAGMA foreign_keys=OFF'); h.db.prepare('UPDATE backpack_items SET raw_json=?,archive_id=999 WHERE kind=?').run(weapon,'weapon');
    await assert.rejects(h.service.buildBackupJson(),/存档归属/); h.close();
  });
  await test('production backup/UIIF/legacy pure model graph passes strict host types',strictModelTypes);
  console.log('backup-sqlite: PASS (production v7 migration/SQLite rollback, lossless UIIF roundtrip, schema1–6 + legacy preservation, validation and no orphan snapshots)');
})().catch(error=>{console.error(error);process.exitCode=1;});
