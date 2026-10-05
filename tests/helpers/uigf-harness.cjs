// Production service/preparation/repository/VM with in-memory SQLite and narrow native SDK doubles.
// Checks transaction behavior and retained preparation, not device performance or native ArkTS compilation.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {DatabaseSync}=require('node:sqlite');const test=require('node:test');
const ts=require(process.env.TYPESCRIPT_PATH||'../../ci/node_modules/typescript');
const root=path.resolve(__dirname,'../../entry/src/main/ets');
const A='100000001',B='700000002',C='600000003',big='1844674407370955161';
const plain=value=>JSON.parse(JSON.stringify(value));
const row=(id=big,extra={})=>({id,gacha_type:'400',uigf_gacha_type:'301',item_id:10000001,count:'1',rank_type:'5',time:'2026-10-05 10:00:00',name:'fixture',item_type:'角色',...extra});
const section=(uid,list,timezone=8)=>({uid,list,timezone});
const file=(sections=[section(A,[row()])],ugc)=>JSON.stringify({info:{version:'v4.2'},hk4e:sections,...(ugc?{hk4e_ugc:ugc}:{})});
class Predicates{
  constructor(table){this.table=table;this.conditions=[];this.values=[];this.order='';this.limit='';this.offset='';}
  equalTo(key,value){this.conditions.push(`${key}=?`);this.values.push(value);return this;}
  in(key,values){this.conditions.push(`${key} IN (${values.map(()=>'?')})`);this.values.push(...values);return this;}
  orderByAsc(key){this.order=` ORDER BY ${key} ASC`;return this;}
  orderByDesc(key){this.order=` ORDER BY ${key} DESC`;return this;}
  limitAs(value){this.limit=` LIMIT ${value}`;return this;}
  offsetAs(value){this.offset=` OFFSET ${value}`;return this;}
  where(){return this.conditions.length?' WHERE '+this.conditions.join(' AND '):'';}
}
class ResultSet{
  constructor(rows,state){this.rows=rows;this.state=state;this.index=-1;this.columns=Object.keys(rows[0]??{});state.resultSets++;}
  goToFirstRow(){this.index=0;return this.rows.length>0;}
  goToNextRow(){return ++this.index<this.rows.length;}
  getColumnIndex(key){return this.columns.indexOf(key);}
  getLong(index){return Number(this.rows[this.index][this.columns[index]]??0);}
  getString(index){return String(this.rows[this.index][this.columns[index]]??'');}
  close(){this.state.closedSets++;}
}
function harness(){
  const db=new DatabaseSync(':memory:');db.exec(`CREATE TABLE gacha_archives(id INTEGER PRIMARY KEY AUTOINCREMENT,uid TEXT UNIQUE,is_selected INTEGER DEFAULT 0);
    CREATE TABLE gacha_items(id INTEGER PRIMARY KEY AUTOINCREMENT,archive_id INTEGER,gacha_type INTEGER,item_id INTEGER,count INTEGER,time TEXT,name TEXT,item_type TEXT,rank_type INTEGER,gacha_id TEXT,schedule_id INTEGER);`);
  const state={parseCalls:0,begins:0,commits:0,rollbacks:0,batches:0,failBatch:0,shortBatch:0,failArchive:0,resultSets:0,closedSets:0,readIds:[],changes:[]};
  const store={
    beginTransaction(){state.begins++;db.exec('BEGIN');},commit(){state.commits++;db.exec('COMMIT');},rollBack(){state.rollbacks++;db.exec('ROLLBACK');},
    querySync(pred){if(pred.table==='gacha_items'&&pred.conditions.includes('archive_id=?'))state.readIds.push(pred.values[0]);return new ResultSet(db.prepare(`SELECT * FROM ${pred.table}${pred.where()}${pred.order}${pred.limit}${pred.offset}`).all(...pred.values),state);},
    insertSync(table,values){if(table==='gacha_archives'&&state.failArchive===Number(values.uid))throw Error('archive insert failed');return Number(db.prepare(`INSERT INTO ${table} (${Object.keys(values)}) VALUES (${Object.keys(values).map(()=>'?')})`).run(...Object.values(values)).lastInsertRowid);},
    batchInsertSync(table,rows){state.batches++;if(state.batches===state.failBatch)throw Error('injected second archive disk failure');for(const values of rows)this.insertSync(table,values);return state.batches===state.shortBatch?rows.length-1:rows.length;},
    updateSync(values,pred){return db.prepare(`UPDATE ${pred.table} SET ${Object.keys(values).map(key=>`${key}=?`)}${pred.where()}`).run(...Object.values(values),...pred.values).changes;},
    deleteSync(pred){return db.prepare(`DELETE FROM ${pred.table}${pred.where()}`).run(...pred.values).changes;}
  };
  const helper={getStore:()=>store,query:async pred=>store.querySync(pred),insert:async(table,values)=>store.insertSync(table,values),batchInsert:async(table,rows)=>store.batchInsertSync(table,rows),update:async(table,values,pred)=>store.updateSync(values,pred),delete:async(table,pred)=>store.deleteSync(pred)};
  const sdk=require('./uigf-sdk-double.cjs')(state);
  const modules=new Map();
  function load(name){
    if(modules.has(name))return modules.get(name);
    const output=ts.transpileModule(fs.readFileSync(path.join(root,name+'.ets'),'utf8').replace(/^@Concurrent\s*$/gm,''),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true},reportDiagnostics:true});assert.equal(output.diagnostics.length,0,name);
    const module={exports:{}};modules.set(name,module.exports);
    vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`,{...sdk.globals,Error,Date,Observed:value=>value,JSON:{parse:(...args)=>{state.parseCalls++;if(state.inWorker)state.workerParseCalls=(state.workerParseCalls??0)+1;return JSON.parse(...args);},stringify:JSON.stringify},AppStorage:{setOrCreate:(key,value)=>state.changes.push([key,value])}})(id=>{
      if(id==='@kit.ArkTS')return sdk.arkTS;
      if(id==='@kit.CoreFileKit')return sdk.files;
      if(id==='@kit.ArkData')return {relationalStore:{RdbPredicates:Predicates}};
      if(id.endsWith('/RelationalStoreHelper'))return {RelationalStoreHelper:helper};
      if(id.endsWith('/Logger'))return {Logger:{info(){},warn(){}}};
      if(id.endsWith('/Constants'))return {AppConstants:{APP_VERSION:'selective-host'}};
      if(id.endsWith('/WikiMetaService'))return {WikiMetaService:{getGachaEvents:async()=>[]}};
      if(id.endsWith('/GachaLogService'))return {GachaLogService:{getInstance:()=>({cancelRefresh(){}})}};
      assert.ok(id.startsWith('.'),id);return load(path.posix.normalize(path.posix.join(path.posix.dirname(name),id)));
    },module,module.exports);return module.exports;
  }
  const service=load('service/UigfService').UigfService.getInstance();
  const Model=load('viewmodel/GachaLogViewModel').GachaLogViewModel;
  const Preparation=load('model/UigfImportPreparation').UigfImportPreparation;
  const repo=load('data/repo/GachaRepo').GachaRepo;
  const snapshot=()=>({archives:db.prepare('SELECT * FROM gacha_archives ORDER BY id').all(),items:db.prepare('SELECT * FROM gacha_items ORDER BY id').all()});
  return {db,state,service,repo,Model,Preparation,snapshot,load};
}
module.exports={harness,A,B,C,big,row,section,file,plain};
