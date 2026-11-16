// Execute the production codec, catalog, repository, service and viewmodel on real SQLite.
// Native UI/file-picker behavior still needs the official compiler and a device.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { DatabaseSync } = require('node:sqlite');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const rawRoot = path.resolve(root, '../resources/rawfile');
const db = new DatabaseSync(':memory:');
db.exec('PRAGMA foreign_keys=ON');
let failTable = '', writes = 0, opened = 0, closed = 0;
let frozenTime;
let displayLocale = 'zh-Hans';
const localizedNames = new Map();
let loadedAvatars = [];
const TestClock = class extends Date { static now() { return frozenTime ?? Date.now(); } };
class Pred {
  constructor(table) { this.table=table; this.fields=[]; this.values=[]; this.order=''; }
  equalTo(key,value) { this.fields.push(`${key}=?`); this.values.push(value); return this; }
  and() { return this; }
  orderByAsc(key) { this.order=` ORDER BY ${key} ASC`; return this; }
  orderByDesc(key) { this.order=` ORDER BY ${key} DESC`; return this; }
  where() { return this.fields.length ? ` WHERE ${this.fields.join(' AND ')}` : ''; }
}
function resultSet(sql, values=[]) {
  const statement=db.prepare(sql), names=statement.columns().map(column=>column.name), rows=statement.all(...values);
  let index=-1, isClosed=false; opened++;
  return {columnNames:names,getColumnIndex:name=>names.indexOf(name),goToNextRow:()=>++index<rows.length,
    goToFirstRow:()=>{index=0;return rows.length>0;},getLong:column=>Number(rows[index][names[column]]),
    getString:column=>String(rows[index][names[column]]),getValue:column=>rows[index][names[column]],
    close(){assert.equal(isClosed,false);isClosed=true;closed++;}};
}
const store={
  get version(){return db.prepare('PRAGMA user_version').get().user_version;},
  set version(value){db.exec(`PRAGMA user_version=${value}`);},
  async executeSql(sql){db.exec(sql);},
  beginTransaction(){db.exec('BEGIN');},commit(){db.exec('COMMIT');},rollBack(){db.exec('ROLLBACK');},
  querySync(pred){return resultSet(`SELECT * FROM ${pred.table}${pred.where()}${pred.order}`,pred.values);},
  async query(pred){return this.querySync(pred);},async querySql(sql){return resultSet(sql);},
  deleteSync(pred){writes++;return Number(db.prepare(`DELETE FROM ${pred.table}${pred.where()}`).run(...pred.values).changes);},
  updateSync(row,pred){writes++;return Number(db.prepare(`UPDATE ${pred.table} SET ${Object.keys(row).map(key=>`${key}=?`).join(',')}${pred.where()}`).run(...Object.values(row),...pred.values).changes);},
  insertSync(table,row){writes++;if(table===failTable)throw Error('injected storage failure');const keys=Object.keys(row);
    return Number(db.prepare(`INSERT INTO ${table} (${keys}) VALUES (${keys.map(()=>'?')})`).run(...Object.values(row)).lastInsertRowid);},
  batchInsertSync(table,rows){rows.forEach(row=>this.insertSync(table,row));return rows.length;},
  async insert(table,row){return this.insertSync(table,row);}
};
const mocks={
  '@kit.ArkData':{relationalStore:{getRdbStore:async()=>store,SecurityLevel:{S1:1},RdbPredicates:Pred}},
  '@kit.ArkTS':{util:{TextDecoder:{create:()=>({decodeToString:bytes=>new TextDecoder().decode(bytes)})}}},
  Logger:{info(){},warn(){},debug(){}},
  AppContextProvider:{getResourceManager:()=>({getRawFileContent:async name=>new Uint8Array(fs.readFileSync(path.join(rawRoot,name)))})},
  WikiMetaService:{getWeapons:async()=>[{id:11501,name:'测试单手剑',icon:'UI_EquipIcon_Test',rankLevel:5,weaponType:1}],
    getAvatars:async()=>{
      const names=displayLocale==='en-US' ? localizedNames.get('avatar_meta.json') : undefined;
      loadedAvatars=[{id:10000046,name:names?.get(10000046)??'胡桃',sideIcon:'UI_AvatarIcon_Side_Hutao',icon:'UI_AvatarIcon_Hutao'},
        {id:10000002,name:'神里绫华',sideIcon:'',icon:'UI_AvatarIcon_Ayaka'}];
      return loadedAvatars;
    }, avatarOf:id=>loadedAvatars.find(avatar=>avatar.id===id)},
  GameDataService:{readMetadataFile:async name=>fs.readFileSync(path.join(rawRoot,'metadata',name),'utf8')},
  LocalizedGameDataService:{current:()=>displayLocale,names:async(table,locale=displayLocale)=>
    locale==='en-US' ? localizedNames.get(table)??new Map() : new Map()},
};
mocks['./WikiMetaService']={WikiMetaService:mocks.WikiMetaService,MetaMaterial:class {}};
const scorePrefs = new Map();
mocks.PreferencesStore = { getString: (key, fallback) => scorePrefs.get(key) ?? fallback, setString: (key, value) => scorePrefs.set(key, value) };
const cache=new Map();
function load(relative) {
  const file=path.resolve(root,relative.endsWith('.ets')?relative:relative+'.ets');
  if(cache.has(file))return cache.get(file);
  const compiled=ts.transpileModule(fs.readFileSync(file,'utf8').replace(/^@Observed\s*$/gm,''),
    {fileName:file.replace(/\.ets$/,'.ts'),compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
  assert.equal(compiled.diagnostics.length,0,file);
  const module={exports:{}};cache.set(file,module.exports);
  const requireLocal=id=>{if(mocks[id])return mocks[id];const name=path.basename(id);if(name==='AppContext')return {AppContextProvider:mocks.AppContextProvider};if(mocks[name])return {[name]:mocks[name]};
    assert.ok(id.startsWith('.'),'unexpected native dependency: '+id);return load(path.resolve(path.dirname(file),id));};
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`,{Date:TestClock})(requireLocal,module,module.exports);
  return module.exports;
}
const {UIIFCodec:Codec,BackpackJson}=load('model/UIIFCodec');
const {BackpackCategory:Category,BackpackFilter,BackpackFilterChoice,BackpackFilterKind:FilterKind,
  BackpackItem,BackpackManualInput,BackpackSortRule}=load('model/BackpackData');
const {BackpackCatalog:Catalog}=load('model/BackpackCatalog');
const {BackpackRepo:Repo}=load('data/repo/BackpackRepo');
const {BackpackService:Service}=load('service/BackpackService');
const {BackpackViewModel:ViewModel}=load('viewmodel/BackpackViewModel');
const helper=load('data/db/RelationalStoreHelper').RelationalStoreHelper;
const clone=value=>JSON.parse(JSON.stringify(value));
const uiif=(items,info='{"uiif_version":"v1.0"}')=>`{"info":${info},"list":[${items.join(',')}]}`;
const weapon='{"itemId":11501,"equip":{"weapon":{"level":90,"promoteLevel":6,"affixMap":{"111501":4}}}}';
const relic='{"itemId":75544,"equip":{"reliquary":{"level":21,"mainPropId":15001,"appendPropIdList":[501201,501201,501203]}}}';
const material='{"itemId":104003,"material":{"count":0}}';
const furniture='{"itemId":361101,"furniture":{"count":2}}';
let first=0,second=0;

test('Windows v1.0 fields and repeated equipment remain independent; nullable branches and omitted export metadata work',()=>{
  const result=Codec.parse(uiif([weapon,weapon,relic,material,furniture]));
  assert.equal(result.items.length,5);assert.equal(result.weaponCount,2);assert.equal(result.reliquaryCount,1);
  assert.equal(result.items[0].instanceId,'local:1');assert.equal(result.items[1].instanceId,'local:2');
  assert.equal(result.items[0].isLocked,undefined);assert.equal(result.items[2].level,21);
  assert.deepEqual(clone(result.items[2].appendPropIds),[501201,501201,501203]);
  assert.equal(result.items[3].count,0);
  const nullable=Codec.parse(uiif(['{"itemId":"11501","material":null,"furniture":null,"equip":{"weapon":{"level":"90","promoteLevel":"6","affixMap":null},"reliquary":null}}'],
    '{"uiif_version":"v1.0","export_timestamp":"-9223372036854775808","export_app":null,"export_app_version":null}'));
  assert.equal(nullable.items[0].level,90);assert.equal(nullable.items[0].affixMap.size,0);
});

test('raw JSON round trips unknown fields and uint64 IDs without float rounding',()=>{
  const raw='{"itemId":11501,"guid":18446744073709551615,"equip":{"weapon":{"level":90,"promoteLevel":6},"isLocked":true},"unknown":{"exact":18446744073709551614,"escaped":"braces }[ and \\\" quote"}}';
  const original=`{"info":{"uiif_version":"v1.0","export_timestamp":9223372036854775807,"extra":18446744073709551613},"list":[${raw}],"future":18446744073709551612}`;
  const parsed=Codec.parse(original), output=Codec.export(parsed.documentJson,parsed.items);
  assert.equal(parsed.items[0].guid,'18446744073709551615');assert.equal(parsed.items[0].instanceId,'guid:18446744073709551615');
  assert.equal(parsed.items[0].isLocked,true);
  for(const exact of ['18446744073709551615','18446744073709551614','18446744073709551613','18446744073709551612','9223372036854775807'])assert.ok(output.includes(exact));
  assert.equal(Codec.parse(output).items[0].rawJson,raw);
  const safe=Codec.parse(uiif(['{"itemId":1,"material":{"count":1},"__proto__":{"polluted":true}}']));
  assert.ok(Codec.export(safe.documentJson,safe.items).includes('"__proto__"'));assert.equal({}.polluted,undefined);
});

test('ambiguous, corrupt, duplicate and unsafe payloads fail before writes',()=>{
  const invalid=['null','[]','{}',uiif(['{"itemId":1,"material":{"count":-1}}']),uiif(['{"itemId":1,"material":{"count":1.5}}']),
    uiif(['{"itemId":1,"material":{"count":4294967296}}']),uiif(['{"itemId":0,"material":{"count":1}}']),
    uiif(['{"itemId":1,"material":{"count":1},"furniture":{"count":1}}']),uiif(['{"itemId":1,"equip":{}}']),
    uiif(['{"itemId":1,"equip":{"weapon":{"level":1,"promoteLevel":0},"reliquary":{"level":1,"mainPropId":1,"appendPropIdList":[]}}}']),
    uiif(['{"itemId":1,"itemId":2,"material":{"count":1}}']),uiif(['{"itemId":1,"material":{"count":1},"future":{"a":1,"a":2}}']),
    uiif([material,material]),uiif([furniture,furniture]),uiif([weapon.replace('11501','9007199254740993')]),
    uiif([weapon.replace('"itemId":11501','"itemId":11501,"guid":18446744073709551616')]),
    uiif([weapon.replace('"itemId":11501','"itemId":11501,"guid":123'),weapon.replace('"itemId":11501','"itemId":11501,"guid":"123"')]),
    uiif([weapon.replace('"itemId":11501','"itemId":11501,"isLocked":"true"')]),
    uiif([relic.replace('"mainPropId":15001,','')]),uiif([relic.replace(',"appendPropIdList":[501201,501201,501203]','')]),
    uiif([material],'{"uiif_version":"v2.0"}'),uiif([],'{"uiif_version":"v1.0","export_timestamp":9223372036854775808}')];
  const before=writes;for(const value of invalid)assert.throws(()=>Codec.parse(value),undefined,value);assert.equal(writes,before);
  assert.throws(()=>Codec.parse(' '.repeat(Codec.MAX_FILE_BYTES+1)));
  assert.throws(()=>Codec.parse('汉'.repeat(Math.floor(Codec.MAX_FILE_BYTES/3)+1)),/16 MiB/);
  assert.throws(()=>Codec.parse(uiif(['{"itemId":1,"material":{"count":1},"deep":'+'['.repeat(66)+'0'+']'.repeat(66)+'}'])),/64/);
  assert.throws(()=>Codec.parse(uiif(new Array(Codec.MAX_ITEMS+1).fill(weapon))),/50000/);
});

test('all nine categories follow pinned Windows rules, including overlapping type precedence and unknown fallback',()=>{
  assert.equal(Catalog.category(201,undefined),Category.PreciousItem);
  assert.equal(Catalog.category(220007,21),Category.PreciousItem);
  assert.equal(Catalog.category(108001,undefined),Category.Food);
  assert.equal(Catalog.category(101001,14),Category.Material);
  assert.equal(Catalog.category(101001,undefined),Category.Unknown);
  assert.equal(Catalog.category(220000,undefined),Category.Gadget);
  for(const type of [14,11,20,6,7,13,72,73])assert.equal(Catalog.category(999999,type),Category.UpgradeItem);
  for(const type of [2,49,64,41,46])assert.equal(Catalog.category(999999,type),Category.Quest);
  assert.equal(Catalog.category(999999,36),Category.PreciousItem);
  assert.equal(Catalog.category(999999,33),Category.Gadget);
  assert.equal(Catalog.category(999999,37),Category.Food);
  assert.equal(Catalog.category(999999,999),Category.Material);
  assert.equal(Catalog.category(999999,undefined),Category.Unknown);
  const references=JSON.parse(fs.readFileSync(path.join(rawRoot,'backpack/reference.json'),'utf8'));
  const counts={};for(const row of references)counts[row.kind]=(counts[row.kind]||0)+row.ids.length;
  assert.deepEqual(counts,{material:7210,reliquary:4320,furniture:2319});
});

test('search, stable sorting and known-lock filtering never assign missing lock data',()=>{
  const records=Codec.parse(uiif([weapon,weapon.replace('"itemId":11501','"itemId":11501,"isLocked":true'),material,relic])).items;
  records[0].name='天空之刃';records[1].name='天空之刃';const filter=new BackpackFilter();
  filter.keyword='天空';assert.equal(Catalog.filter(records,filter).length,2);
  filter.lockedOnly=true;assert.equal(Catalog.filter(records,filter)[0].instanceId,'local:2');
  filter.keyword='';filter.lockedOnly=false;filter.category=Category.Reliquary;assert.equal(Catalog.filter(records,filter).length,1);
  filter.category=-1;filter.sort='level';assert.deepEqual(Catalog.filter(records,filter).map(record=>record.instanceId).join(','),'local:1,local:2,local:4,local:3');
  assert.match(Catalog.detail(records[3]),/^\+20/);assert.match(Catalog.detail(records[0]),/5 阶/);
});
test('offline status filters distinguish explicit false, true and unknown, keeping optional raw extensions intact',()=>{
  const equipped='{"itemId":75544,"equippedAvatarId":10000002,"isMarked":true,"equip":{"reliquary":{"level":21,"mainPropId":15001,"appendPropIdList":[501201],"purchasedAppendPropIdList":[501201]}}}';
  const unequipped='{"itemId":75544,"isMarked":false,"equip":{"equippedAvatarId":0,"reliquary":{"level":20,"mainPropId":15001,"appendPropIdList":[501201],"purchasedAppendPropIdList":[]}}}';
  const older='{"itemId":75544,"equippedAvatarId":"unknown","equip":{"reliquary":{"level":19,"mainPropId":15001,"appendPropIdList":[501201],"purchasedAppendPropIdList":{"future":true}}}}';
  const imported=Codec.parse(uiif([equipped,unequipped,older]));
  const filter=new BackpackFilter(); filter.category=Category.Reliquary;
  const choices=code=>[FilterKind.Mark,FilterKind.Equipped,FilterKind.Purchased].map(kind=>new BackpackFilterChoice(kind,code,''));
  filter.choices=choices(1);
  assert.deepEqual(clone(Catalog.filter(imported.items,filter).map(item=>item.level)),[21]);
  filter.choices=choices(0);
  assert.deepEqual(clone(Catalog.filter(imported.items,filter).map(item=>item.level)),[20]);
  filter.choices=choices(2);
  assert.deepEqual(clone(Catalog.filter(imported.items,filter).map(item=>item.level)),[19]);
  assert.ok(Codec.export(imported.documentJson,imported.items).includes(older));
  filter.choices=[new BackpackFilterChoice(FilterKind.Mark,0,''),new BackpackFilterChoice(FilterKind.Mark,1,'')];
  assert.deepEqual(clone(Catalog.filter(imported.items,filter).map(item=>item.level)),[21,20]);
  filter.choices.push(new BackpackFilterChoice(FilterKind.Purchased,0,''));
  assert.deepEqual(clone(Catalog.filter(imported.items,filter).map(item=>item.level)),[20]);
});

test('multicolumn sorting uses rule order and keeps unknown status last in either direction',()=>{
  const rows=Codec.parse(uiif([weapon,weapon,weapon])).items;
  rows[0].level=20; rows[0].isLocked=true;
  rows[1].level=40; rows[1].isLocked=true;
  rows[2].level=90;
  const filter=new BackpackFilter(); filter.category=Category.Weapon;
  filter.sortRules=[new BackpackSortRule('lock',false),new BackpackSortRule('level',true)];
  assert.deepEqual(clone(Catalog.filter(rows,filter).map(item=>item.level)),[40,20,90]);
  filter.sortRules=[new BackpackSortRule('level',true),new BackpackSortRule('lock',true)];
  assert.deepEqual(clone(Catalog.filter(rows,filter).map(item=>item.level)),[90,40,20]);
});

test('database migration and local archive creation enforce explicit UID/name; selected archive is persisted',async()=>{
  await helper.init({});assert.equal(store.version,9);
  await assert.rejects(Repo.createArchive('empty',''));await assert.rejects(Repo.createArchive('','100000001'));
  first=await Repo.createArchive('主号十月','100000001');second=await Repo.createArchive('另一档','700000002');
  let archives=await Repo.getArchives();assert.equal(archives.filter(archive=>archive.isSelected).length,1);assert.equal(archives[1].isSelected,true);
  await Repo.selectArchive(first);archives=await Repo.getArchives();assert.equal(archives[0].isSelected,true);
  const before=clone(archives);await assert.rejects(Repo.selectArchive(99999));assert.deepEqual(clone(await Repo.getArchives()),before);
});

test('import validates before delete and atomically replaces selected UID only',async()=>{
  const firstImport=await Service.prepareImport(uiif([weapon,weapon,relic,material,furniture]));
  await Service.importSnapshot(first,firstImport);await Service.importSnapshot(second,await Service.prepareImport(uiif([material.replace(':0',':99')])));
  assert.equal((await Repo.getItems(first)).length,5);assert.equal((await Repo.getItems(second))[0].count,99);
  const before=await Service.exportArchive(first), beforeWrites=writes;
  const wrong=await Service.prepareImport(uiif([material],'{"uiif_version":"v1.0","uid":"700000002"}'));
  await assert.rejects(Service.importSnapshot(first,wrong),/UID/);assert.equal(writes,beforeWrites);assert.equal(await Service.exportArchive(first),before);
  failTable='backpack_items';await assert.rejects(Service.importSnapshot(first,await Service.prepareImport(uiif([material]))),/storage failure/);failTable='';
  assert.equal(await Service.exportArchive(first),before);assert.equal((await Repo.getItems(second))[0].count,99);
  const loaded=await Service.getItems(first);assert.equal(loaded[0].name,'测试单手剑');assert.equal(loaded.find(item=>item.kind==='material').name,'大英雄的经验');
  assert.ok(loaded.find(item=>item.kind==='furniture').name.length>0);
});

test('manual creation keeps independent equipment IDs and preserves derived category',async()=>{
  const input=new BackpackManualInput();input.kind='weapon';input.itemId='11501';input.level='1';input.promoteLevel='0';
  await Service.addManual(first,input);await Service.addManual(first,input);
  const rows=await Repo.getItems(first);assert.equal(rows.filter(item=>item.itemId===11501).length,4);
  assert.equal(new Set(rows.map(item=>item.instanceId)).size,rows.length);
  const materialInput=new BackpackManualInput();materialInput.itemId='104002';materialInput.count='10';
  await Service.addManual(first,materialInput);assert.equal((await Repo.getItems(first)).find(item=>item.itemId===104002).category,Category.UpgradeItem);
  await assert.rejects(Service.addManual(first,materialInput),/重复/);
});

test('prepared import refuses archive-ID reuse or intervening snapshot replacement before any write',async()=>{
  const view=new ViewModel();await view.load(first);
  const prepared=await view.prepare(uiif([material]));
  const before=await Service.exportArchive(first), beforeWrites=writes;
  const owner=await Repo.getArchive(first);
  db.prepare('UPDATE backpack_archives SET uid=? WHERE id=?').run('800000003',first);
  await assert.rejects(Service.importSnapshot(first,prepared),/目标档案已更改/);assert.equal(writes,beforeWrites);
  db.prepare('UPDATE backpack_archives SET uid=?,updated_at=? WHERE id=?').run(owner.uid,owner.updatedAt+1,first);
  await assert.rejects(Service.importSnapshot(first,prepared),/目标档案已更改/);assert.equal(writes,beforeWrites);
  db.prepare('UPDATE backpack_archives SET updated_at=? WHERE id=?').run(owner.updatedAt,first);
  assert.equal(await Service.exportArchive(first),before);
});

test('material snapshot merge/replace is project-scoped, equipment/furniture excluded, zero known and failures roll back',async()=>{
  db.exec("INSERT INTO cultivate_projects(id,name,created_at) VALUES(1,'养成一',1),(2,'养成二',1)");
  db.exec('INSERT INTO cultivate_inventory(project_id,item_id,count) VALUES(1,99,10),(1,104003,500),(2,99,20)');
  assert.equal(await Service.syncMaterials(first,1,false),2);
  const rows=()=>clone(db.prepare('SELECT * FROM cultivate_inventory ORDER BY project_id,item_id').all());
  assert.deepEqual(rows(),[{project_id:1,item_id:99,count:10},{project_id:1,item_id:104002,count:10},{project_id:1,item_id:104003,count:0},{project_id:2,item_id:99,count:20}]);
  const before=rows();failTable='cultivate_inventory';await assert.rejects(Service.syncMaterials(second,1,true),/storage failure/);failTable='';assert.deepEqual(rows(),before);
  await assert.rejects(Service.syncMaterials(first,999,false),/项目/);assert.deepEqual(rows(),before);
  await Service.syncMaterials(second,1,true);assert.deepEqual(rows(),[{project_id:1,item_id:104003,count:99},{project_id:2,item_id:99,count:20}]);
});

test('count editing preserves unknown exact numbers, classification persists, and deleting one instance keeps its twin',async()=>{
  const raw='{"itemId":104003,"material":{"count":1,"future":18446744073709551615},"extension":"retain"}';
  const changed=Codec.changeCount(Codec.parse(uiif([raw])).items[0],'0');
  assert.ok(changed.rawJson.includes('18446744073709551615'));assert.ok(changed.rawJson.includes('"extension":"retain"'));assert.equal(changed.count,0);
  const rows=await Repo.getItems(first), materialItem=rows.find(item=>item.itemId===104002), firstWeapon=rows.find(item=>item.kind==='weapon');
  const before=await Service.exportArchive(first);
  await assert.rejects(Service.updateCount(first,materialItem.instanceId,'-1'));assert.equal(await Service.exportArchive(first),before);
  await assert.rejects(Service.updateCount(first,firstWeapon.instanceId,'10'));assert.equal(await Service.exportArchive(first),before);
  failTable='backpack_items';await assert.rejects(Service.updateCount(first,materialItem.instanceId,'20'),/storage failure/);failTable='';assert.equal(await Service.exportArchive(first),before);
  await Service.updateCount(first,materialItem.instanceId,'20');assert.equal((await Repo.getItems(first)).find(item=>item.instanceId===materialItem.instanceId).count,20);
  await Service.categorize(first,materialItem.instanceId,Category.PreciousItem);assert.equal((await Service.getItems(first)).find(item=>item.instanceId===materialItem.instanceId).category,Category.PreciousItem);
  await assert.rejects(Service.categorize(first,materialItem.instanceId,Category.Weapon));
  const count=rows.filter(item=>item.itemId===11501).length;
  await Service.removeItem(first,firstWeapon.instanceId);assert.equal((await Repo.getItems(first)).filter(item=>item.itemId===11501).length,count-1);
  await assert.rejects(Service.removeItem(first,firstWeapon.instanceId),/已被删除/);
});

test('reload without a login retains archive, details and filters; deleted archive cannot receive an import',async()=>{
  const view=new ViewModel();await view.load();assert.equal(view.currentId,first);assert.ok(view.items.length>0);
  view.filter.keyword='11501';view.applyFilter();assert.equal(view.items.length,3);
  const raw=await Service.exportArchive(second);await Repo.deleteArchive(second);
  await assert.rejects(Service.importSnapshot(second,Codec.parse(raw)),/删除/);assert.ok((await Repo.getItems(first)).length>0);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM backpack_items WHERE archive_id=?').get(second).n,0);
  assert.equal(opened,closed,'all native result sets must close');
});

test('detached and superseded viewmodel reads never overwrite newer selection',async()=>{
  const original=Service.getItems;let release;
  Service.getItems=()=>new Promise(resolve=>{release=resolve;});
  const view=new ViewModel();const pending=view.load(first);while(!release)await new Promise(resolve=>setImmediate(resolve));
  view.invalidate();release([new BackpackItem()]);await pending;assert.equal(view.items.length,0);assert.equal(view.currentId,0);
  Service.getItems=original;
  const page=fs.readFileSync(path.join(root,'pages/BackpackPage.ets'),'utf8');
  for(const marker of ['LazyForEach(this.source','Number(area.width) >= 840','archive.id, prepared','size > UIIFService.MAX_FILE_BYTES','read !== size','written !== bytes.length','this.vm.invalidate()'])assert.ok(page.includes(marker),marker);
  assert.match(page,/\.bindSheet\([\s\S]*systemMaterial: UiSurface\.dialogMaterial\(this\.surfaceMode, this\.surfaceLevel\)/);
  assert.equal(/isLoggedIn|UserService|Yae|http\.request/.test(page),false);
});

test('pinned item metadata supplies weapon type, artifact set and slot, and recipe output quality',async()=>{
  const archive=await Service.createArchive('过滤元数据','100000001');
  await Service.importSnapshot(archive,await Service.prepareImport(uiif([weapon,relic,'{"itemId":108011,"material":{"count":2}}'])));
  const rows=await Service.getItems(archive);
  const loadedWeapon=rows.find(item=>item.kind==='weapon'); assert.equal(loadedWeapon.weaponType,1);
  const loadedRelic=rows.find(item=>item.kind==='reliquary'); assert.ok(loadedRelic.setId>0); assert.ok(loadedRelic.equipType>0);
  assert.ok(loadedRelic.setName.length>0);
  const food=rows.find(item=>item.category===Category.Food); assert.equal(food.foodType,1); assert.equal(food.foodQuality,0);
  const filter=new BackpackFilter(); filter.category=Category.Food;
  filter.choices=[new BackpackFilterChoice(FilterKind.FoodType,1,''),new BackpackFilterChoice(FilterKind.FoodQuality,0,'')];
  assert.deepEqual(clone(Catalog.filter(rows,filter).map(item=>item.itemId)),[108011]);
  await Repo.deleteArchive(archive);
});

test('same-millisecond archive writes invalidate prepared imports and deleting the selection persists a fallback',async()=>{
  frozenTime=1800000000000;
  const archive=await Service.createArchive('固定时钟','100000001');
  try {
    const initial=await Repo.getArchive(archive);
    const model=new ViewModel(); await model.load(archive);
    const prepared=await model.prepare(uiif([weapon]));
    const manual=new BackpackManualInput(); manual.itemId='104003'; manual.count='10';
    await Service.addManual(archive,manual);
    assert.equal((await Repo.getArchive(archive)).updatedAt,initial.updatedAt+1);
    await assert.rejects(model.importSnapshot(archive,prepared),/目标档案已更改/);
    const snapshot=await Service.exportArchive(archive);
    assert.equal(Codec.parse(snapshot).items[0].count,10);
  } finally { frozenTime=undefined; await Repo.deleteArchive(archive); }
  assert.equal((await Repo.getArchives()).find(row=>row.isSelected).id,first);
});

test('stale item detail cannot edit, categorize or remove a replacement with the same local instance ID',async()=>{
  const archive=await Service.createArchive('物品详情归属','100000001');
  try {
    await Service.importSnapshot(archive,await Service.prepareImport(uiif(['{"itemId":104003,"material":{"count":5}}'])));
    const view=new ViewModel(); await view.load(archive);
    const stale=view.allItems[0];
    await Service.importSnapshot(archive,await Service.prepareImport(uiif(['{"itemId":104002,"material":{"count":8}}'])));
    const replaced=(await Repo.getItems(archive))[0];
    assert.equal(replaced.instanceId,stale.instanceId);
    assert.notEqual(replaced.rawJson,stale.rawJson);
    const before=await Service.exportArchive(archive);
    const beforeWrites=writes;
    await assert.rejects(view.updateCount(stale,'99'),/已被删除或替换/);
    await assert.rejects(view.categorize(stale,Category.PreciousItem),/已被删除或替换/);
    await assert.rejects(view.removeItem(stale),/已被删除或替换/);
    assert.equal(await Service.exportArchive(archive),before);
    assert.equal(writes,beforeWrites);
    await view.load(first);
    await assert.rejects(view.updateCount(replaced,'12'),/档案已改变/);
    await view.load(archive);
    await view.updateCount(view.allItems[0],'12');
    assert.equal((await Repo.getItems(archive))[0].count,12);
  } finally { await Repo.deleteArchive(archive); }
});

test('locale reload overlays item and set names and keeps prepared archive and score edits valid',async()=>{
  const archive=await Service.createArchive('显示语言','100000001');
  try {
    const equippedRelic=relic.replace('"equip":','"equippedAvatarId":10000046,"equip":');
    const text=uiif([equippedRelic,'{"itemId":104003,"material":{"count":2}}',furniture]);
    await Service.importSnapshot(archive,await Service.prepareImport(text));
    const model=new ViewModel(); await model.load(archive);
    const baseline=model.allItems.find(item=>item.kind==='reliquary');
    assert.equal(model.equippedAvatarLabel(baseline.equippedAvatarId),'已装备 · 胡桃');
    const initial=await Service.exportArchive(archive);
    const scoreEdit=model.beginScoreEdit();
    const prepared=await model.prepare(uiif([weapon]));
    localizedNames.set('material_meta.json',new Map([[104003,"Hero's Wit"]]));
    localizedNames.set('Reliquary.json',new Map([[75544,'Test Circlet']]));
    localizedNames.set('ReliquarySet.json',new Map([[baseline.setId,'Test Set']]));
    localizedNames.set('Furniture.json',new Map([[361101,'Test Furniture']]));
    localizedNames.set('avatar_meta.json',new Map([[10000046,'Hu Tao']]));
    displayLocale='en-US';
    assert.equal(await model.refreshDisplay(),true);
    assert.equal(model.currentId,archive);
    const translated=model.allItems.find(item=>item.kind==='reliquary');
    assert.equal(translated.name,'Test Circlet'); assert.equal(translated.setName,'Test Set');
    assert.equal(translated.instanceId,baseline.instanceId); assert.equal(translated.setId,baseline.setId);
    assert.equal(translated.equipType,baseline.equipType); assert.equal(translated.icon,baseline.icon);
    assert.equal(model.equippedAvatarLabel(translated.equippedAvatarId),'已装备 · Hu Tao');
    assert.equal(model.equippedAvatarIcon(translated.equippedAvatarId),'UI_AvatarIcon_Side_Hutao');
    assert.equal(translated.rawJson,baseline.rawJson);
    assert.equal(model.allItems.find(item=>item.kind==='furniture').name,'Test Furniture');
    assert.equal(model.allItems.find(item=>item.itemId===104003).name,"Hero's Wit");
    assert.equal((await Service.cultivationMaterialMetadata()).get(104003).n,"Hero's Wit");
    assert.equal(await Service.exportArchive(archive),initial);
    model.saveScore(scoreEdit,scoreEdit.profile);
    await model.importSnapshot(archive,prepared);
    assert.equal(model.allItems[0].itemId,11501);
  } finally {
    displayLocale='zh-Hans'; localizedNames.clear(); scorePrefs.clear(); await Repo.deleteArchive(archive);
  }
});

test('equipment details display actual FightProperty names, avatar portraits and unknown IDs without changing UIIF',async()=>{
  const archive=await Service.createArchive('装备展示','100000001');
  try {
    const equipped='{"itemId":75544,"guid":18446744073709551615,"equippedAvatarId":10000046,"equip":{"reliquary":{"level":21,"mainPropId":15001,"appendPropIdList":[501201],"purchasedAppendPropIdList":[20,22,3,2,5,8,501201,501201]}},"extension":{"future":true}}';
    const unknown=weapon.replace('"equip":','"equippedAvatarId":19999999,"equip":');
    const missingSide=weapon.replace('"equip":','"equippedAvatarId":10000002,"equip":');
    await Service.importSnapshot(archive,await Service.prepareImport(uiif([equipped,unknown,missingSide])));
    const baseline=await Service.exportArchive(archive);
    const model=new ViewModel(); await model.load(archive);
    const item=model.allItems.find(entry=>entry.kind==='reliquary');
    assert.deepEqual(Array.from(model.purchasedStatNames(item.purchasedAppendPropIds)),
      ['暴击率','暴击伤害','生命值','攻击力','防御力','未知属性 #501201']);
    assert.equal(model.equippedAvatarLabel(item.equippedAvatarId),'已装备 · 胡桃');
    assert.equal(model.equippedAvatarIcon(item.equippedAvatarId),'UI_AvatarIcon_Side_Hutao');
    assert.ok(fs.existsSync(path.join(rawRoot,'icons','AvatarIcon','UI_AvatarIcon_Side_Hutao.png')));
    assert.equal(model.equippedAvatarIcon(10000002),'UI_AvatarIcon_Ayaka');
    assert.equal(model.equippedAvatarLabel(19999999),'已装备 · 角色 ID 19999999');
    assert.equal(model.equippedAvatarIcon(19999999),'');
    assert.equal(model.equippedAvatarLabel(undefined),'装备状态未知');
    assert.equal(model.equippedAvatarLabel(0),'未装备');
    assert.equal(item.rawJson,equipped);
    assert.equal(await Service.exportArchive(archive),baseline);
  } finally { await Repo.deleteArchive(archive); }
});
