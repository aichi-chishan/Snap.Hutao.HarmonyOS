// Execute the production Wiki route/lifecycle/load methods with metadata and ArkUI boundaries doubled.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const test=require('node:test');
const ts=require(process.env.TYPESCRIPT_PATH||'../ci/node_modules/typescript');
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return{promise,resolve,reject};};
const flush=async()=>{for(let i=0;i<50;i++)await Promise.resolve();};
const pureModules=new Map();
function loadPure(file) {
  file=path.resolve(file);if(pureModules.has(file))return pureModules.get(file);
  const source=fs.readFileSync(file,'utf8');
  const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
  const mod={exports:{}};vm.runInThisContext(`(function(require,module,exports){${code}\n})`,{filename:file})(id=>{
    assert.ok(id.startsWith('.'),`unexpected native dependency in filter/guide model: ${id}`);
    return loadPure(path.resolve(path.dirname(file),id)+'.ets');
  },mod,mod.exports);pureModules.set(file,mod.exports);return mod.exports;
}
function harness(kind) {
  const source=fs.readFileSync(`entry/src/main/ets/pages/Wiki${kind}Page.ets`,'utf8').replaceAll('\r\n','\n');
  const imports=Array.from(source.matchAll(/^import[\s\S]*?;\n/gm),m=>m[0]).join('');
  const first=source.indexOf(`export struct Wiki${kind}Page`),last=source.indexOf('  @Builder',first);
  const extra=kind==='Monster'?source.slice(source.indexOf('  filtered()'),source.indexOf('  build()')):
    kind==='Avatar'?source.slice(source.indexOf('  avatarMaxLevel()'),source.indexOf('  static qualityColor')):'';
  const body=source.slice(first,last).replace(`export struct Wiki${kind}Page`,`export class Wiki${kind}Page`)+extra+'}';
  const ids=kind==='Avatar'?[10000022,10000046]:kind==='Weapon'?[11509,13509]:[10701,10702];
  const items=ids.map((id,index)=>({id,describeId:id,name:`item_${id}`,canonicalName:`item_${id}`,title:'',rankLevel:5-index,quality:5-index,
    nameCardPic:`card_${id}`,growCurves:[],promoteId:1,vision:index===0?'火':'水',weapon:1,begin:'2020-01-01',sort:10-index,
    weaponType:1,body:index+1,association:index+1,secondaryProperty:index===0?20:22}));
  const state={params:{itemId:ids[1]},paramsReads:0,paramsError:false,items,itemsReads:0,materialsReads:0,itemsGates:[],materialGates:[],cancelled:0,selected:[],nameGates:[],attacks:[],skills:[],skillGates:[],scrolls:[],locale:'zh-Hans'};
  const metadata={getAvatars:async()=>readItems(),getWeapons:async()=>readItems(),getMonsters:async()=>readItems(),getMaterials:async()=>{state.materialsReads++;return state.materialGates.length?state.materialGates.shift().promise:new Map();},
    getMonsterDrops:async()=>metadata.getMaterials(),
    getNameCardByPic:async()=>{const gate=deferred();state.nameGates.push(gate);return gate.promise;},
    qualityName:quality=>({4:'四星',5:'五星'}[quality]||''),elementName:value=>value,weaponTypeName:()=> '单手剑',
    BODY_TYPES:['少年','少女'],associationName:value=>['','蒙德','璃月'][value]};
  const readItems=()=>{state.itemsReads++;return state.itemsGates.length?state.itemsGates.shift().promise:state.items;};
  const mocks={
    '../model/CharacterData':{CharacterDetail:class {}},
    '@kit.ArkUI':{router:{getParams:()=>{state.paramsReads++;if(state.paramsError)throw Error('route unavailable');return state.params;},back:()=>{}}},
    '../viewmodel/CultivationDraftViewModel':{CultivationDraftViewModel:class {cancel(){state.cancelled++;}}},
    '../service/WikiMetaService':{WikiMetaService:metadata},
    '../service/AppLocaleService':{AppLocaleService:{current:()=>state.locale}},
    '../service/WikiAvatarFilter':loadPure('entry/src/main/ets/service/WikiAvatarFilter.ets'),
    '../service/WikiAvatarGuide':loadPure('entry/src/main/ets/service/WikiAvatarGuide.ets'),
    '../service/AvatarSkillParameterService':{AvatarSkillParameterService:{
      forAvatar:async()=>state.skillGates.length?state.skillGates.shift().promise:state.skills,
      rows:(skill,level)=>skill.levels.includes(level)?[{label:'Damage',value:String(level),isSpecial:false}]:[],
    }},
    '../common/UiSurface':{UiSurface:{dialogMaterial:()=>undefined},CardSurfaceModifier:class {},ControlMaterialModifier:class {}},
    '../data/prefs/PreferencesStore':{PreferencesStore:{getBool:(_key,fallback)=>fallback}},
    '../components/SimpleDataSource':{SimpleDataSource:class {constructor(items){this.items=items;this.reloads=0;}getItems(){return this.items;}notifyDataReload(items){this.items=items;this.reloads++;}}},
    '../service/BaseValueService':{BaseValueService:{avatarMaxLevel:()=>100,weaponMaxLevel:()=>90,weaponBaseValues:async()=>{const gate=deferred();state.attacks.push(gate);return gate.promise;},
      fightPropName:prop=>({20:'暴击率',22:'暴击伤害'}[prop]||'')}},
  };
  const output=ts.transpileModule(imports+body,{reportDiagnostics:true,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}});assert.equal(output.diagnostics.length,0);
  const m={exports:{}};vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`,{State:()=>{},Prop:()=>{},StorageProp:()=>()=>{},Watch:()=>()=>{},Scroller:class{scrollTo(options){state.scrolls.push(options);}}})(id=>{assert(mocks[id],`Unexpected dependency ${id}`);return mocks[id];},m,m.exports);
  const page=new m.exports[`Wiki${kind}Page`]();
  // Derived base-value/art work is independent from loading/selecting the routed metadata item.
  page[`on${kind}Selected`]=()=>state.selected.push(page.selectedId);
  if(kind==='Avatar'){page.calcAvatarBase=()=>{};}
  return{page,state,ids,source};
}
(async()=>{
  for(const kind of ['Avatar','Weapon']) {
    await test(`${kind}: known route selects the exact item on narrow and wide pages`,async()=>{
      for(const wide of [false,true]){const {page,state,ids}=harness(kind);page.isWide=wide;page.aboutToAppear();await flush();assert.equal(page.selectedId,ids[1]);assert.equal(page.current.id,ids[1]);assert.equal(page.loading,false);assert.equal(page.routeMessage,'');assert.deepEqual(state.selected,[ids[1]]);assert.equal(state.paramsReads,1);assert.equal(page.listSource.items.length,2);}
    });
    await test(`${kind}: missing route preserves normal defaults; invalid/unknown never shows unrelated detail`,async()=>{
      const {page,state,ids}=harness(kind);page.isWide=true;state.params={};page.aboutToAppear();await flush();assert.equal(page.selectedId,ids[0]);
      for(const value of [ids[1]+1000,0,-1,NaN,1.5,String(ids[1]),null]){state.params={itemId:value};page.aboutToAppear();await flush();assert.equal(page.selectedId,0,String(value));assert.equal(page.current,undefined);assert.match(page.routeMessage,/本地暂无/);assert.equal(page.listSource.items.length,2);}
      state.paramsError=true;page.aboutToAppear();await flush();assert.equal(page.current,undefined);assert.equal(page.selectedId,0);
    });
    await test(`${kind}: embedded pages never read global route params`,async()=>{
      for(const wide of [false,true]){const {page,state,ids}=harness(kind);page.embedMode=true;page.isWide=wide;state.paramsError=true;page.aboutToAppear();await flush();assert.equal(state.paramsReads,0);assert.equal(page.selectedId,wide?ids[0]:0);assert.equal(page.routeMessage,'');}
    });
    await test(`${kind}: stale metadata load cannot override a newer routed selection`,async()=>{
      const {page,state,ids}=harness(kind);const old=deferred();state.params={itemId:ids[0]};state.itemsGates.push(old);page.aboutToAppear();
      state.params={itemId:ids[1]};page.aboutToAppear();await flush();assert.equal(page.selectedId,ids[1]);assert.equal(state.materialsReads,1);const reloads=page.listSource.reloads;
      old.resolve([state.items[0]]);await flush();assert.equal(page.selectedId,ids[1]);assert.equal(page.current.id,ids[1]);assert.equal(page.listSource.reloads,reloads);assert.equal(state.materialsReads,1);
    });
    await test(`${kind}: detached metadata/material completions never publish, reject, or finish a newer load`,async()=>{
      for(const stage of ['items','materials'])for(const rejects of [false,true]){
        const {page,state,ids}=harness(kind);const old=deferred(),newer=deferred();
        if(stage==='items')state.itemsGates.push(old);else state.materialGates.push(old);
        page.aboutToAppear();await flush();page.aboutToDisappear();assert.equal(state.cancelled,1);const reloads=page.listSource.reloads;
        state.params={itemId:ids[0]};state.itemsGates.push(newer);page.aboutToAppear();
        if(rejects)old.reject(Error('stale read'));else old.resolve(stage==='items'?state.items:new Map());await flush();
        assert.equal(page.loading,true);assert.equal(page.listSource.reloads,reloads);assert.equal(page.current,undefined);
        newer.resolve(state.items);await flush();assert.equal(page.selectedId,ids[0]);assert.equal(page.loading,false);assert.equal(page.routeMessage,'');
      }
    });
    await test(`${kind}: active read failure settles honestly, selection clears unknown-route notice`,async()=>{
      const {page,state}=harness(kind);const gate=deferred();state.itemsGates.push(gate);page.aboutToAppear();gate.reject(Error('internal detail'));await flush();assert.equal(page.loading,false);assert.equal(page.current,undefined);assert.match(page.routeMessage,/无法读取本地/);assert(!page.routeMessage.includes('internal'));
      state.params={itemId:0};page.aboutToAppear();await flush();page.select(state.items[1]);assert.equal(page.routeMessage,'');assert.equal(page.current,state.items[1]);page.aboutToDisappear();page.select(state.items[0]);assert.equal(page.current,state.items[1]);
    });
    await test(`${kind}: late secondary detail reads are fenced after detach`,async()=>{
      const {page,state}=harness(kind);page.aboutToAppear();await flush();
      if(kind==='Avatar'){
        const pending=page.loadNameCardInfo();page.aboutToDisappear();state.nameGates[0].resolve({name:'stale name',description:'stale detail'});await pending;assert.equal(page.ncName,'');assert.equal(page.ncDesc,'');
      }else{
        const pending=page.calcWeaponBase();page.aboutToDisappear();state.attacks[0].resolve({attack:999,secondary:'stale'});await pending;
        assert.notEqual(page.curAttack,999);assert.notEqual(page.curSecondary,'stale');
      }
    });
    await test(`${kind}: cultivation editor and only explicit route consumers remain wired`,()=>{
      const {source}=harness(kind);assert.match(source,/CultivationDraftEditor/);assert.match(source,/this\.draftVm\.cancel\(\)/);assert.match(source,/WishHistoryWikiParams/);assert.match(source,/if \(this\.embedMode\) \{ return; \}/);assert.match(source,/if \(!this\.ownsLoad\(sequence\)\) \{ return; \}/);
    });
    await test(`${kind}: multiselect keeps group intersections and a narrow back retains its selection`,async()=>{
      const {page,state,ids}=harness(kind);state.params={};page.aboutToAppear();await flush();
      if(kind==='Avatar') {
        for(const label of ['四星','五星','单手剑']){page.editFilterText(label);page.commitFilterText();}
      } else {page.qualities=['四星','五星'];page.weaponTypes=['单手剑'];page.applyFilter();}
      assert.equal(page.listSource.items.length,2);
      if(kind==='Avatar'){page.editFilterText('璃月');page.commitFilterText();}else{page.properties=['暴击伤害'];}
      page.applyFilter();assert.deepEqual(Array.from(page.listSource.items,item=>item.id),[ids[1]]);
      assert.equal(page.selectedId,ids[1]);assert.equal(page.showDetail,false);
      if(kind==='Avatar'){assert.deepEqual(Array.from(page.splashSource.items,item=>item.id),[ids[1]]);assert.equal(page.curIdx,0);}
      page.select(state.items[1]);assert.equal(page.showDetail,true);assert.equal(page.onBackPress(),true);
      assert.equal(page.showDetail,false);assert.equal(page.selectedId,ids[1]);
      page.keyword='DOES NOT EXIST';if(kind==='Avatar'){page.commitFilterText();}else{page.applyFilter();}
      assert.equal(page.current,undefined);assert.equal(page.visibleCount,0);
    });
  }
  for(const kind of ['Avatar','Weapon','Monster']) {
    await test(`${kind}: changing identity resets detail scroll but locale reload retains its position`, async()=>{
      const {page,state}=harness(kind);page.aboutToAppear();await flush();
      page.select(state.items[0]);state.scrolls=[];
      page.select(state.items[1]);assert.equal(state.scrolls.length,1);
      assert.equal(state.scrolls[0].yOffset,0);assert.equal(state.scrolls[0].animation,false);
      page.select(state.items[1]);assert.equal(state.scrolls.length,1);
      page.localeVersion=1;page.onLocaleChanged();await flush();assert.equal(state.scrolls.length,1);
    });
    await test(`${kind}: locale reload keeps the selected identity and Chinese search, ignoring older translations`, async()=>{
      const {page,state,ids}=harness(kind);
      page.aboutToAppear();await flush();
      page.keyword=state.items[0].canonicalName;
      if(kind==='Avatar'){page.commitFilterText();}else{page.applyFilter();}
      page.select(state.items[0]);page.curLevel=80;
      const old=deferred();state.itemsGates.push(old);page.localeVersion=1;page.onLocaleChanged();
      const first=state.items.map(item=>({...item,name:`English ${item.id}`}));
      state.locale='ja';state.items=state.items.map(item=>({...item,name:`日本語 ${item.id}`}));
      page.localeVersion=2;page.onLocaleChanged();await flush();
      assert.equal(page.selectedId,ids[0]);assert.equal(page.current.name,`日本語 ${ids[0]}`);
      if(kind==='Avatar'){assert.equal(page.keyword,'');assert.equal(page.filterTokens[0].value,String(ids[0]));assert.equal(page.filterTokens[0].label,`日本語 ${ids[0]}`);}
      else{assert.equal(page.keyword,`item_${ids[0]}`);}
      assert.equal(page.curLevel,80);assert.equal(page.showDetail,true);
      assert.equal(page.listSource.items.length,1);assert.equal(page.appliedLocaleVersion,2);
      old.resolve(first);await flush();assert.equal(page.current.name,`日本語 ${ids[0]}`);
    });
  }
  await test('Avatar: skill selection uses stable IDs, available levels and source defaults', async()=>{
    const {page,state}=harness('Avatar');page.aboutToAppear();await flush();
    state.skills=[
      {id:101,name:'Normal',levels:[1,5,10],defaultLevel:10},
      {id:102,name:'Passive',levels:[1],defaultLevel:1},
      {id:103,name:'Description',levels:[],defaultLevel:0},
    ];
    await page.loadSkills();assert.equal(page.selectedSkillId,101);assert.equal(page.selectedSkillLevel,10);
    assert.deepEqual(Array.from(page.skillLevelOptions(),option=>option.value),['Lv. 1','Lv. 5','Lv. 10']);
    page.selectSkillLevel(1);assert.equal(page.selectedSkillLevel,5);assert.equal(page.skillParameterRows()[0].value,'5');
    state.skills=state.skills.map(skill=>({...skill,name:'Translated '+skill.name}));
    await page.loadSkills(true);assert.equal(page.selectedSkillId,101);assert.equal(page.selectedSkillLevel,5);
    assert.equal(page.selectedSkill().name,'Translated Normal');
    page.selectSkill(102);assert.equal(page.selectedSkillLevel,1);assert.equal(page.skillLevelOptions().length,1);
    page.selectSkill(103);assert.equal(page.selectedSkillLevel,0);assert.equal(page.skillParameterRows().length,0);
    page.selectSkillLevel(100);assert.equal(page.selectedSkillLevel,0);
  });
  await test('Avatar: type to suggest, commit five chips, remove one and clear the roster filter', async()=>{
    const {page,state}=harness('Avatar');state.params={};page.isWide=true;page.aboutToAppear();await flush();
    page.editFilterText('五星');assert.equal(page.visibleCount,2);assert.equal(page.filterTokens.length,0);
    assert.equal(page.showFilters,true);assert.ok(page.suggestionSource.items.some(item=>item.label==='五星'));
    page.commitFilterText();assert.equal(page.filterTokens.length,1);assert.equal(page.visibleCount,1);
    page.editFilterText('火 单手剑 蒙德');page.commitFilterText();assert.equal(page.filterTokens.length,4);
    page.editFilterText('五星');page.commitFilterText();assert.equal(page.filterTokens.length,4);
    page.editFilterText('少男');page.addFilter(page.suggestionSource.items.find(item=>item.label==='少男'));
    assert.equal(page.filterTokens.length,5);assert.equal(page.showFilters,false);
    page.addFilter(page.filterCatalog.find(item=>item.label==='璃月'));assert.equal(page.filterTokens.length,5);
    page.removeFilter(page.filterTokens[0]);page.showSuggestions();assert.equal(page.filterTokens.length,4);
    assert.ok(page.suggestionSource.items.some(item=>item.label==='五星'));assert.equal(page.onBackPress(),true);
    page.clearFilters();assert.equal(page.filterTokens.length,0);assert.equal(page.visibleCount,2);
    state.items[0].name='Hu Tao';await page.load(true);page.editFilterText('Hu T');
    assert.equal(page.filterTokens.length,0);assert.equal(page.suggestionSource.items.length,1);
    page.addFilter(page.suggestionSource.items[0]);assert.equal(page.filterTokens[0].label,'Hu Tao');
    assert.equal(page.visibleCount,1);
  });
  await test('Avatar: a new selection starts at its actual maximum level with promotion off', async()=>{
    const {page}=harness('Avatar');page.aboutToAppear();await flush();
    page.loadNameCardInfo=()=>{};page.loadSkills=()=>{};
    page.curLevel=1;page.curPromoted=true;
    Object.getPrototypeOf(page).onAvatarSelected.call(page);
    assert.equal(page.curLevel,100);assert.equal(page.curPromoted,false);
    page.avatarMaxLevel=()=>70;
    Object.getPrototypeOf(page).onAvatarSelected.call(page);
    assert.equal(page.curLevel,70);
  });
  await test('Avatar: guide actions open the selected character’s public guide and explain a missing entry', async()=>{
    const {page,state}=harness('Avatar');const seed=state.items[0];
    state.items=[{...seed,id:10000136,name:'米提亚',canonicalName:'米提亚'},
      {...seed,id:10000002,name:'神里绫华',canonicalName:'神里绫华'}];
    const links=[],notices=[];
    page.getUIContext=()=>({getHostContext:()=>({openLink:async url=>links.push(url)}),
      getPromptAction:()=>({showToast:options=>notices.push(options.message)})});
    state.params={itemId:10000136};page.aboutToAppear();await flush();
    await page.openStrategy('mys');assert.match(links[0],/\/channel\/map\/39\/535\?/);
    await page.openStrategy('bili');assert.equal(decodeURIComponent(new URL(links[1]).pathname),'/ys/米提亚/攻略');
    await page.openStrategy('hoyolab');assert.equal(links.length,2);assert.equal(notices.length,1);
    page.select(state.items[1]);await page.openStrategy('hoyolab');
    assert.equal(links[2],'https://www.hoyolab.com/guidelist?game_id=2&guide_id=188');
    page.aboutToDisappear();await page.openStrategy('mys');assert.equal(links.length,3);
  });
  await test('Avatar: Wiki excludes virtual travelers and sorts a copy by release date then source sort', async()=>{
    const {page,state}=harness('Avatar');const seed=state.items[0];
    const boy={...seed,id:10000005,name:'Traveler',begin:'',sort:1};
    const girl={...boy,id:10000007};
    const older={...seed,id:10000140,name:'Vodyanitsa',begin:'2026-09-22',sort:122};
    const mitya={...seed,id:10000136,name:'Mitya',begin:'2026-11-03',sort:124};
    const valeriy={...seed,id:10000137,name:'Valeriy',begin:'2026-11-03',sort:123};
    state.items=[boy,girl,older,valeriy,mitya];state.params={};page.isWide=true;
    page.aboutToAppear();await flush();
    assert.deepEqual(Array.from(page.avatars,row=>row.id),[10000136,10000137,10000140]);
    assert.equal(page.selectedId,10000136);
    assert.deepEqual(state.items.map(row=>row.id),[10000005,10000007,10000140,10000137,10000136]);
    assert.equal(page.splashSource.items.length,3);
    state.params={itemId:10000007};page.aboutToAppear();await flush();
    assert.equal(page.current,undefined);assert.match(page.routeMessage,/本地暂无/);
  });
  await test('Avatar: seven or eight skill tabs fit a tablet while narrow strips retain touch width and scrolling', ()=>{
    const {page}=harness('Avatar');
    for(const count of [7,8]){
      page.skillItems=Array.from({length:count},(_,index)=>({id:index+1}));page.skillStripWidth=650;
      const width=page.skillTabWidth();assert.ok(width>=64);assert.ok(count*width+(count-1)*4<=650);
    }
    page.skillStripWidth=320;assert.equal(page.skillTabWidth(),64);
    assert.ok(page.skillItems.length*page.skillTabWidth()+(page.skillItems.length-1)*4>320);
  });
  await test('Avatar: late skill reads cannot overwrite another character or a detached page', async()=>{
    const {page,state}=harness('Avatar');page.aboutToAppear();await flush();
    const old=deferred();state.skillGates.push(old);const oldRead=page.loadSkills();
    page.current=state.items[0];page.selectedId=state.items[0].id;
    state.skills=[{id:201,name:'New character',levels:[1,10],defaultLevel:10}];
    await page.loadSkills();old.resolve([{id:101,name:'Old character',levels:[1],defaultLevel:1}]);await oldRead;
    assert.equal(page.selectedSkillId,201);assert.equal(page.selectedSkillLevel,10);
    const detached=deferred();state.skillGates.push(detached);const pending=page.loadSkills();
    page.aboutToDisappear();detached.resolve(state.skills);await pending;
    assert.equal(page.skillItems.length,0);assert.equal(page.selectedSkillId,0);
  });
  for(const kind of ['Weapon','Monster']) {
    await test(`${kind}: source sort is explicit and never mutates cached metadata`,async()=>{
      const {page,state}=harness(kind);state.params={};page.isWide=true;
      state.items=[{...state.items[0],id:3,describeId:3,sort:10},{...state.items[0],id:1,describeId:1,sort:30},
        {...state.items[0],id:2,describeId:2,sort:20}];
      page.aboutToAppear();await flush();
      assert.deepEqual(Array.from(page.listSource.items,item=>item.id),[1,2,3]);assert.equal(page.selectedId,1);
      assert.deepEqual(state.items.map(item=>item.id),[3,1,2]);
    });
    await test(`${kind}: selection starts at its source maximum and locale refresh retains the chosen level`,async()=>{
      const {page,state}=harness(kind);page.aboutToAppear();await flush();page.select(state.items[0]);
      page[kind==='Weapon'?'calcWeaponBase':'calcMonsterBase']=()=>{};
      page.curLevel=1;page.curPromoted=true;
      Object.getPrototypeOf(page)[`on${kind}Selected`].call(page);
      assert.equal(page.curLevel,kind==='Weapon'?90:110);
      if(kind==='Weapon')assert.equal(page.curPromoted,false);
      page.curLevel=50;page.localeVersion=1;page.onLocaleChanged();await flush();assert.equal(page.curLevel,50);
      if(kind==='Weapon'){
        page.maxLevel=()=>70;Object.getPrototypeOf(page).onWeaponSelected.call(page);assert.equal(page.curLevel,70);
      }
    });
    await test(`${kind}: five local name tokens use OR, preserve filters, reject a sixth, and clear both draft and chips`,async()=>{
      const {page,state,ids}=harness(kind);state.params={};page.aboutToAppear();await flush();
      for(const id of ids){page.setKeyword(`ITEM_${id}`);page.commitKeyword();}
      assert.equal(page.nameTokens.length,2);assert.equal(page.listSource.items.length,2);
      page.setKeyword('not present');page.commitKeyword();assert.equal(page.listSource.items.length,2);
      page.setKeyword('fourth');page.commitKeyword();page.setKeyword('fifth');page.commitKeyword();
      page.setKeyword('sixth');page.commitKeyword();assert.equal(page.nameTokens.length,5);assert.equal(page.keyword,'');
      page.clearFilters();assert.equal(page.nameTokens.length,0);assert.equal(page.keyword,'');assert.equal(page.listSource.items.length,2);
      page.setKeyword(`item_${ids[0]}`);page.commitKeyword();page.setKeyword(`item_${ids[0]}`);page.commitKeyword();
      assert.equal(page.nameTokens.length,1);
      if(kind==='Weapon'){
        page.setKeyword(`item_${ids[1]}`);page.commitKeyword();
        page.updateFilterGroup(0,['四星','五星']);assert.equal(page.listSource.items.length,2);
        page.updateFilterGroup(1,['单手剑']);page.updateFilterGroup(2,['暴击伤害']);assert.equal(page.properties.length,0);
        page.updateFilterGroup(0,['四星']);
        page.updateFilterGroup(2,['暴击伤害']);assert.deepEqual(Array.from(page.listSource.items,item=>item.id),[ids[1]]);
        page.updateFilterGroup(2,['暴击伤害','暴击率']);assert.equal(page.properties.length,1);
        page.clearFilters();assert.equal(page.filterCount(),0);
      }
    });
  }
  await test('Monster: resistance display keeps fractional precision and follows the Windows two-column reading order',()=>{
    const {page,state}=harness('Monster');page.current={...state.items[0],subHurts:[.1,.125,.1,.1,.7,.2,.4,-.1]};
    assert.equal(page.resistanceText(1),'12.5%');assert.equal(page.resistanceText(7),'-10.0%');
    const order=Array.from(page.constructor.RESIST_ORDER);
    assert.deepEqual(order.map(index=>page.resistanceText(index)),['10.0%','12.5%','10.0%','10.0%','40.0%','70.0%','20.0%','-10.0%']);
  });
  await test('Weapon: secondary stat shows its actual property name and value separately',()=>{
    const {page,state}=harness('Weapon');page.current={...state.items[0],secondaryProperty:22};page.curSecondary='暴击伤害 88.2%';
    assert.equal(page.secondaryLabel(),'暴击伤害');assert.equal(page.secondaryValue(),'88.2%');
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
