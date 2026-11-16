// Visible values from the 2026-11-16 device tree/Windows reference, in the upstream C# wire shape.
// These are reviewable reconstruction fixtures, not captured authenticated API responses.
// Production models, VMs and repositories execute against real SQLite; OS/network boundaries are doubles.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const {DatabaseSync}=require('node:sqlite');const ts=require(process.env.TYPESCRIPT_PATH||'../ci/node_modules/typescript');
const root=path.resolve(__dirname,'../entry/src/main/ets'),metadata=path.resolve(root,'../resources/rawfile/metadata');
const uid='100000001',region='cn_gf01';
const plain=value=>JSON.parse(JSON.stringify(value)),turn=()=>new Promise(resolve=>setImmediate(resolve));
const deferred=()=>{let resolve;const promise=new Promise(done=>{resolve=done;});return {promise,resolve};};
const read=name=>JSON.parse(fs.readFileSync(path.join(metadata,name),'utf8'));
function method(source,name){
  const match=new RegExp('^  (?:private )?(?:static )?(?:async )?'+name+'\\(','m').exec(source);assert.ok(match,name);
  const end=source.indexOf('\n  }',match.index);assert.ok(end>match.index,name);return source.slice(match.index,end+4);
}
function harness(){
  const db=new DatabaseSync(':memory:');db.exec('CREATE TABLE challenge_records(kind TEXT,uid TEXT,region TEXT,schedule_id INTEGER,start_time INTEGER,end_time INTEGER,raw_json TEXT,record_time INTEGER,UNIQUE(kind,uid,region,schedule_id))');
  const state={selectedUid:uid,revision:0,openSets:0,closedSets:0,hardFetches:0,theaterFetches:0,metadataReady:true,dialogs:[]};
  class Predicates{constructor(table){this.table=table;this.where=[];this.values=[];this.order='';}equalTo(column,value){this.where.push(column+'=?');this.values.push(value);return this;}orderByDesc(column){this.order=' ORDER BY '+column+' DESC';return this;}}
  class Result{constructor(rows){this.rows=rows;this.index=-1;this.columns=Object.keys(rows[0]??{});state.openSets++;}goToFirstRow(){this.index=0;return this.rows.length>0;}goToNextRow(){return ++this.index<this.rows.length;}getColumnIndex(name){return this.columns.indexOf(name);}getLong(index){return Number(this.rows[this.index][this.columns[index]]??0);}getString(index){return String(this.rows[this.index][this.columns[index]]??'');}close(){state.closedSets++;}}
  const where=pred=>pred.where.length?' WHERE '+pred.where.join(' AND '):'';
  const helper={query:async pred=>new Result(db.prepare('SELECT * FROM '+pred.table+where(pred)+pred.order).all(...pred.values)),
    update:async(table,values,pred)=>db.prepare('UPDATE '+table+' SET '+Object.keys(values).map(key=>key+'=?')+where(pred)).run(...Object.values(values),...pred.values).changes,
    getStore:()=>({insert:async(table,values)=>Number(db.prepare('INSERT OR REPLACE INTO '+table+'('+Object.keys(values)+') VALUES('+Object.keys(values).map(()=>'?')+')').run(...Object.values(values)).lastInsertRowid)})};
  const actorMap=new Map(read('avatar_meta.json').map(actor=>[actor.id,actor]));
  const theaterMetadata=read('RoleCombatSchedule.json').map(row=>({id:row.Id,begin:Date.parse(row.Begin),end:Date.parse(row.End),elements:row.Elements,initialAvatars:row.InitialAvatars,specialAvatars:row.SpecialAvatars}));
  const wiki={getRoleCombatSchedules:async()=>{if(state.scheduleGate)await state.scheduleGate.promise;return theaterMetadata;},
    ensureIconMaps:async()=>{if(state.iconGate)await state.iconGate.promise;state.metadataReady=true;},
    iconOfAvatar:id=>state.metadataReady?actorMap.get(id)?.icon??'':'',sideIconOfAvatar:id=>state.metadataReady?actorMap.get(id)?.sideIcon??'':'',
    iconOfAvatarName:()=>'',nameOfAvatarId:id=>actorMap.get(id)?.name??'',cleanText:text=>text.replace(/<[^>]*>/g,'')};
  const modules=new Map();
  const mocks={
    '@kit.ArkData':{relationalStore:{RdbPredicates:Predicates,ConflictResolution:{ON_CONFLICT_REPLACE:0}}},
    'data/db/RelationalStoreHelper':{RelationalStoreHelper:helper},'common/Logger':{Logger:{info(){},warn(){}}},
    'common/HoyolabEndpoints':{},'data/network/ApiClient':{},'data/network/HoyolabClient':{},'data/network/DsSigner':{},
    'data/network/RiskVerifier':{RiskControlError:class extends Error{}},'common/RiskUiHelper':{RiskUiHelper:{consumePendingChallenge:()=>''}},
    'service/UserService':{},'service/GameDataService':{GameDataService:{readMetadataFile:async name=>fs.readFileSync(path.join(metadata,name),'utf8')}},
    'service/WikiMetaService':{WikiMetaService:wiki},
    'service/ChallengeSession':{ChallengeSession:{capture(id){if(id!==state.selectedUid)return undefined;const revision=state.revision;return {uid:id,region,isCurrent:()=>state.selectedUid===id&&state.revision===revision};}}},
    'service/RoleCombatService':{RoleCombatService:{getInstance:()=>({fetch:async()=>{state.theaterFetches++;return state.theaterReply;}})}},
  };
  function load(name){
    if(mocks[name])return mocks[name];if(modules.has(name))return modules.get(name);
    const source=fs.readFileSync(path.join(root,name+'.ets'),'utf8');const output=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true},reportDiagnostics:true});assert.equal(output.diagnostics.length,0,name);
    const module={exports:{}};modules.set(name,module.exports);vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`,{Error,Date,Observed:type=>type})(id=>mocks[id]??load(path.posix.normalize(path.posix.join(path.posix.dirname(name),id))),module,module.exports);return module.exports;
  }
  const Hard=load('model/HardChallenge'),Role=load('model/RoleCombat'),Period=load('model/ChallengePeriod').ChallengePeriod;
  const hardService=load('service/HardChallengeService').HardChallengeService.getInstance();
  hardService.fetch=async()=>{state.hardFetches++;if(state.fetchGate)await state.fetchGate.promise;return state.hardReply;};hardService.fetchPopularity=async()=>[];
  const hardRepo=load('data/repo/HardChallengeRepo').HardChallengeRepo,roleRepo=load('data/repo/RoleCombatRepo').RoleCombatRepo;
  const hardVm=new (load('viewmodel/HardChallengeViewModel').HardChallengeViewModel)(),roleVm=new (load('viewmodel/RoleCombatViewModel').RoleCombatViewModel)();
  function page(name,methods,viewModel){
    const source=fs.readFileSync(path.join(root,'pages/'+name+'.ets'),'utf8');const output=ts.transpileModule('class '+name+' {\n'+methods.map(item=>method(source,item)).join('\n')+'\n}\nexports.Page='+name+';',{
      compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});assert.equal(output.diagnostics.length,0,name);
    const module={exports:{}};vm.runInNewContext(output.outputText,{module,exports:module.exports,Error,Date,WikiMetaService:wiki,
      RoleCombatAvatarStat:Role.RoleCombatAvatarStat,DateUtil:{pad2:value=>String(value).padStart(2,'0')},Logger:{warn(){}},UiSurface:{dialogMaterial:()=>undefined},$r:id=>id});
    const instance=new module.exports.Page();Object.assign(instance,{vm:viewModel,attached:true,iconRevision:0,iconSequence:0,challengeColumns:1,moonGridW:0,isWide:false});
    instance.getUIContext=()=>({getPromptAction:()=>({showDialog:async options=>{state.dialogs.push(options);return {index:0};}})});return instance;
  }
  const hardPage=page('HardChallengePage',['loadIcons','onChallengeAreaChange','showMonsterDetails','damageIcon','formatSeconds'],hardVm);
  const rolePage=page('RoleCombatPage',['loadIcons','syncScheduleMeta','summaryLabel','summaryValue','statLabel','statValue','statIcon','statIconOf','iconNameOf','medalIcon','formatMinutes','moonCols'],roleVm);
  const snapshot=()=>plain(db.prepare('SELECT * FROM challenge_records ORDER BY kind,schedule_id').all());
  return {db,state,Hard,Role,Period,hardRepo,roleRepo,hardVm,roleVm,hardPage,rolePage,load,snapshot,actorMap,theaterMetadata};
}
function hardPeriod(number,end='2026-12-15T03:59:59+08:00'){
  return {schedule:{schedule_id:5269000+number,start_time:String(Date.parse(number===13?'2026-11-11T10:00:00+08:00':'2026-09-30T10:00:00+08:00')/1000),end_time:String(Date.parse(end)/1000),name:number===13?'鲸波之役':'烁煌之役'},
    single:{has_data:true,best:{difficulty:number===13?3:4,second:58},challenge:[8,21,29].map((second,index)=>({second,
      monster:{name:['浪涛锚定者·常形','铁甲熔火帝皇·常形','蕴光月守宫·常形'][index],level:90,icon:'UI_MonsterIcon_Fixture',desc:['<color=#fff>机制说明</color>','第二行']},
      teams:[{avatar_id:10000042,name:'刻晴',rarity:5,rank:0,level:90}],best_avatar:[{avatar_id:10000042,type:1,dps:[589950,51103,150722][index]},
        {avatar_id:10000042,type:2,dps:[1092133,569220,630768][index]}]}))}};
}
function theaterPeriod(id=31){
  const round=(round_id,is_get_medal,is_tarot=false,tarot_serial_no=0)=>({round_id,is_get_medal,is_tarot,tarot_serial_no,avatars:[],choice_cards:[]});
  return {has_data:true,has_detail_data:true,schedule:{schedule_id:id,start_time:Date.parse('2026-11-01T04:00:00+08:00')/1000,end_time:Date.parse('2026-12-01T03:59:59+08:00')/1000},
    stat:{difficulty_id:5,max_round_id:10,tarot_finished_cnt:2,medal_num:7,coin_num:1335,avatar_bonus_num:1,rent_cnt:3},
    detail:{rounds_data:[...Array.from({length:9},(_,index)=>round(index+1,![1,5,8].includes(index))),round(10,true,true,1),round(10,true,true,2),round(10,true)],
      backup_avatars:[{avatar_id:10000042,avatar_type:1,rarity:5,element:'Electro',level:90},
        {avatar_id:10000002,avatar_type:2,rarity:5,element:'Cryo',level:90},{avatar_id:10000003,avatar_type:3,rarity:4,element:'Anemo',level:90}],
      fight_statisic:{is_show_battle_stats:true,total_use_time:901,max_defeat_avatar:{avatar_id:10000042,value:'7'},max_damage_avatar:{avatar_id:10000042,value:'829770'},
        max_take_damage_avatar:{avatar_id:10000042,value:'30701'},total_coin_consumed:{value:'999999'},shortest_avatar_list:[{avatar_id:10000042,value:'1'}]}}};
}
(async()=>{
  await test('stored API windows for period 13/12 display the actual published metadata range without rewriting SQLite',async()=>{
    const h=harness();const apiPeriods=[hardPeriod(13),hardPeriod(12,'2026-11-03T03:59:59+08:00')];
    for(const period of apiPeriods){const schedule=period.schedule;const raw=h.Hard.HardChallengeRoot.fromJson({is_unlock:true,data:[period]}).itemRawJson[0];
      await h.hardRepo.saveHistory(uid,region,schedule.schedule_id,Number(schedule.start_time)*1000,Number(schedule.end_time)*1000,raw);}
    const before=h.snapshot();await h.hardVm.initialize(uid);
    assert.equal(h.hardVm.scheduleId,5269013);assert.equal(h.hardVm.history[0].summary,'困难');assert.equal(h.hardVm.history[1].summary,'险恶');
    assert.equal(h.Period.detailedRange(h.hardVm.history[0].startTime,h.hardVm.history[0].endTime),'2026.11.11 10:00 – 2026.12.23 09:59');
    assert.equal(h.Period.detailedRange(h.hardVm.history[1].startTime,h.hardVm.history[1].endTime),'2026.09.30 10:00 – 2026.11.11 09:59');
    assert.equal(h.Period.dateTime(before[1].end_time),'2026.12.15 03:59');assert.equal(h.Period.dateTime(before[0].end_time),'2026.11.03 03:59');
    assert.deepEqual(h.snapshot(),before);assert.equal(h.state.hardFetches,0);
    await h.hardVm.loadFromHistory(uid,5269010);assert.equal(h.hardVm.single.hasData,false);assert.equal(h.hardVm.history.find(period=>period.scheduleId===5269010).summary,'');
    assert.deepEqual(h.snapshot(),before);assert.equal(h.state.openSets,h.state.closedSets);h.db.close();
  });
  await test('refresh and selecting another saved period use metadata only for the display rail, with exact raw server fields retained',async()=>{
    const h=harness();const period=hardPeriod(13);h.state.hardReply=h.Hard.HardChallengeRoot.fromJson({is_unlock:true,data:[period]});
    await h.hardVm.load(uid);assert.equal(h.state.hardFetches,1);assert.equal(h.Period.dateTime(h.hardVm.history[0].endTime),'2026.12.23 09:59');
    const saved=await h.hardRepo.getRawJson(uid,region,5269013);assert.equal(JSON.parse(saved).data[0].schedule.end_time,period.schedule.end_time);
    const unknown=hardPeriod(-5268901,'2027-02-03T04:05:06+08:00');unknown.schedule.schedule_id=99;
    await h.hardRepo.saveHistory(uid,region,99,100000,200000,h.Hard.HardChallengeRoot.fromJson({is_unlock:true,data:[unknown]}).itemRawJson[0]);
    await h.hardVm.initialize(uid);const fallback=h.hardVm.history.find(item=>item.scheduleId===99);assert.equal(fallback.startTime,100000);assert.equal(fallback.endTime,200000);
    await h.hardVm.loadFromHistory(uid,5269013);assert.equal(h.hardVm.single.challenges[0].second,8);h.db.close();
  });
  await test('three reconstructed boss records retain times, zero constellations, levels and strongest-hit/total-damage identities',async()=>{
    const h=harness(),data=h.Hard.HardChallengeRoot.fromJson({is_unlock:true,data:[hardPeriod(13)]}).data;
    assert.deepEqual(Array.from(data.single.challenges,challenge=>[challenge.monster.level,challenge.second,challenge.teams[0].avatars[0].rank]),[[90,8,0],[90,21,0],[90,29,0]]);
    assert.deepEqual(Array.from(data.single.challenges,challenge=>Array.from(challenge.bestAvatars,best=>[best.type,best.value])),
      [[['oneAttack',589950],['allAttack',1092133]],[['oneAttack',51103],['allAttack',569220]],[['oneAttack',150722],['allAttack',630768]]]);
    assert.equal(h.hardPage.damageIcon(data.single.challenges[0].bestAvatars[0]),h.actorMap.get(10000042).sideIcon);
    h.hardPage.showMonsterDetails(data.single.challenges[0]);assert.equal(h.state.dialogs[0].message,'机制说明\n第二行');
    assert.equal(h.hardPage.constructor.formatSeconds(276),'276 秒');assert.equal(h.hardPage.constructor.formatSeconds(0),'--');
    for(const [width,columns]of [[320,1],[529,1],[530,2],[799,2],[800,3],[1200,3],[360,1]]){h.hardPage.onChallengeAreaChange(width);assert.equal(h.hardPage.challengeColumns,columns);}
    h.db.close();
  });
  await test('theater observed statistics map avatar bonus to off-stage support and rent to assistance, retaining tarot completion and source fields',async()=>{
    const h=harness(),raw=theaterPeriod();await h.roleRepo.saveHistory(uid,region,31,raw.schedule.start_time*1000,raw.schedule.end_time*1000,JSON.stringify(raw));
    const before=h.snapshot();await h.roleVm.initialize(uid);
    const values=Array.from({length:9},(_,slot)=>[h.rolePage.statLabel(slot),h.rolePage.statValue(slot)]);
    assert.deepEqual(values,[['最多击破','7'],['最强一击','829770'],['最多承伤','30701'],['消耗「幻剧之花」','1335'],['挑战星章','7'],
      ['演出总时长','00:15:01'],['最佳记录','第 10 幕 圣牌 2'],['场外声援','1'],['助演次数','3']]);
    assert.equal(h.rolePage.statIcon(0),h.actorMap.get(10000042).sideIcon);assert.equal(h.rolePage.statIcon(3),'');
    assert.equal(h.roleVm.current().detail.roundsData.length,12);assert.equal(h.roleVm.current().detail.roundsData.filter(round=>round.isTarot).length,2);
    assert.deepEqual(Array.from(h.roleVm.current().detail.backupAvatars,actor=>actor.avatarType),[3,2,1]);assert.deepEqual(h.snapshot(),before);
    await h.rolePage.syncScheduleMeta();await turn();assert.equal(h.rolePage.scheduleMeta.id,31);
    assert.deepEqual(plain(h.rolePage.scheduleMeta.elements),[2,4,8]);assert.equal(h.rolePage.scheduleMeta.initialAvatars.length,6);assert.equal(h.rolePage.scheduleMeta.specialAvatars.length,4);
    const next=h.Role.RoleCombatRoot.dataItemFromJson(theaterPeriod(30));next.stat.maxRoundId=8;next.stat.tarotFinishedCount=0;next.stat.avatarBonusNumber=4;next.stat.rentCount=9;
    h.roleVm.dataItems=[next];assert.equal(h.rolePage.statValue(6),'第 8 幕');assert.equal(h.rolePage.statValue(7),'4');assert.equal(h.rolePage.statValue(8),'9');h.db.close();
  });
  await test('earned/unearned standard stars and tarot use all four bundled resources and remote icon URLs remain intact',()=>{
    const h=harness();for(const [tarot,done,name]of [[false,true,'towerStar1'],[false,false,'towerStar2'],[true,true,'tarot4'],[true,false,'tarot5']]){
      const round=new h.Role.RoleCombatRoundData();round.isTarot=tarot;round.isGetMedal=done;assert.equal(h.rolePage.constructor.medalIcon(round),name);
    }
    for(const file of ['UI_Icon_Tower_Star1.png','UI_Icon_Tower_Star2.png','UI_Icon_RoleCombat_Reward_Tarot_04.png','UI_Icon_RoleCombat_Reward_Tarot_05.png'])
      assert.ok(fs.existsSync(path.resolve(root,'../resources/base/media',file)),file);
    assert.equal(h.rolePage.constructor.iconNameOf('https://example.invalid/actor.png'),'https://example.invalid/actor.png');
    assert.equal(h.rolePage.constructor.iconNameOf('UI_AvatarIcon_Test.png'),'UI_AvatarIcon_Test');h.db.close();
  });
  await test('metadata completion updates icons only on its current page and period metadata cannot return into another selection',async()=>{
    const h=harness();for(const page of [h.hardPage,h.rolePage]){
      const gate=deferred();h.state.iconGate=gate;page.loadIcons();page.attached=false;page.iconSequence++;gate.resolve();await turn();assert.equal(page.iconRevision,0);page.attached=true;
      h.state.iconGate=undefined;page.loadIcons();await turn();assert.equal(page.iconRevision,1);
    }
    h.roleVm.dataItems=[h.Role.RoleCombatRoot.dataItemFromJson(theaterPeriod(31))];const gate=deferred();h.state.scheduleGate=gate;h.rolePage.syncScheduleMeta();
    h.roleVm.dataItems=[h.Role.RoleCombatRoot.dataItemFromJson(theaterPeriod(30))];h.state.scheduleGate=undefined;h.rolePage.syncScheduleMeta();await turn();gate.resolve();await turn();assert.equal(h.rolePage.scheduleMeta.id,30);h.db.close();
  });
  await test('native pages keep mechanisms behind the boss header, use constant statistic slots and preserve stage, element and avatar controls',()=>{
    const hard=fs.readFileSync(path.join(root,'pages/HardChallengePage.ets'),'utf8'),role=fs.readFileSync(path.join(root,'pages/RoleCombatPage.ets'),'utf8');
    assert.match(hard,/onClick\(\(\) => this\.showMonsterDetails\(challenge\)\)/);assert.match(hard,/columns: this\.challengeColumns/);
    assert.match(hard,/if \(avatar\.rank >= 0\)/);assert.match(hard,/damageIcon\(best\)/);assert.doesNotMatch(hard,/Text\(WikiMetaService\.cleanText\(challenge\.monster\.desc\)\)/);
    assert.match(role,/statValueCell\(slot: number\)/);assert.doesNotMatch(role,/statValueCell\(label: string/);
    assert.match(role,/AssetIcon\(\{ name: RoleCombatPage\.medalIcon\(round\)/);assert.match(role,/this\.combatAvatar\(avatar\)/);
    assert.match(role,/avatar\.avatarType === 2 \|\| avatar\.avatarType === 3/);assert.match(role,/this\.scheduleMeta\.elements/);
    assert.match(role,/rc_roundcard_\$\{this\.vm\.recordVersion\}/);assert.match(role,/this\.backupSection\(cur\)/);
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
