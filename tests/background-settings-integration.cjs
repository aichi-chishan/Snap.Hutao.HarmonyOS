// Execute production Settings VM/component callbacks and ability lifecycle against counted native doubles.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = name => fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
const deferred = () => { let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject}; };
const flush = async()=>{for(let i=0;i<30;i++)await Promise.resolve();};
function load(name, deps, extra={}) {
 let source=read(name);
 if(name==='components/BackgroundTaskSettings')source=source.slice(0,source.indexOf('  @Builder'))+'}';
 source=source.replace('export struct BackgroundTaskSettings','export class BackgroundTaskSettings');
 const code=ts.transpileModule(source,{reportDiagnostics:true,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}});
 assert.equal(code.diagnostics.length,0,name);
 const m={exports:{}};
 vm.runInNewContext(`(function(require,module,exports){${code.outputText}\n})`,{Observed:x=>x,Component:x=>x,Prop:()=>{},State:()=>{},Watch:()=>()=>{},StorageProp:()=>()=>{},...extra})(id=>{
  const key=id.startsWith('@')?id:path.basename(id);assert.ok(deps[key],`unexpected dependency ${id}`);return deps[key];
 },m,m.exports);return m.exports;
}
function harness(){
 const state={revision:1,listeners:new Set(),calls:[],reads:0,gate:undefined,fail:false,dialogs:[],notifications:0};
 class Binding{constructor(){this.revision=1;this.userId=7;this.uid='100000001';this.region='cn_gf01';this.identity='private-fixture-identity';}}
 class Task{constructor(){this.enabled=false;this.queued=false;this.message='disabled';this.userId=0;}allAccounts(){return this.userId===0;}}
 const kinds={DAILY_NOTE:'daily_note',SIGN_IN:'sign_in'};
 const user={sessionRevision:()=>state.revision,addSessionRevisionListener:f=>{state.listeners.add(f);return()=>state.listeners.delete(f)}};
 const service={EXPLANATION:'系统择机执行',getState:async kind=>{state.reads++;if(state.readGate)await state.readGate.promise;const result=new Task();result.kind=kind;return result;},captureBinding:allAccounts=>{if(state.captureFailure)throw Error();const binding=new Binding();binding.revision=state.revision;if(allAccounts){binding.userId=0;binding.uid='';binding.region='';binding.identity='';}return binding;},setEnabled:async(kind,value,binding)=>{state.calls.push(['enable',kind,value,binding]);if(state.gate)await state.gate.promise;if(state.fail)throw Error('fixture');},retryBlocked:async kind=>{state.calls.push(['retry',kind]);if(state.gate)await state.gate.promise;}};
 const deps={BackgroundTask:{BackgroundTaskBinding:Binding,BackgroundTaskState:Task,BackgroundTaskKind:kinds},BackgroundTaskService:{BackgroundTaskService:service},UserService:{UserService:{getInstance:()=>user}},AutoSignInService:{AutoSignInService:{getInstance:()=>({retryCurrent:async()=>{state.calls.push(['sign']);if(state.gate)await state.gate.promise;return {message:'fixture retry result'};}})}} ,UiSurface:{CardSurfaceModifier:class {},UiSurface:{dialogMaterial:()=>undefined}}};
 const classes=load('viewmodel/BackgroundTaskSettingsViewModel',deps);deps.BackgroundTaskSettingsViewModel=classes;
 const Model=classes.BackgroundTaskSettingsViewModel;
 const Page=load('components/BackgroundTaskSettings',deps).BackgroundTaskSettings;
 const page=new Page();page.getUIContext=()=>({showAlertDialog:dialog=>state.dialogs.push(dialog)});
 return {state,kinds,model:new Model(),page,change:()=>{state.revision++;for(const f of [...state.listeners])f(state.revision);}};
}
function lifecycle(){
 const state={events:[],hook:undefined,restore:true,resetError:false,stop:true,restoreGate:undefined,recoveryError:false};
 const event=name=>{state.events.push(name)};
 const user={setSessionInvalidationHook:hook=>{event('hook');state.hook=hook},addSessionRevisionListener:listener=>{state.listener=listener;},isSessionTransitionPending:()=>state.transition,restoreSession:async()=>{event('restore');if(state.restoreGate)await state.restoreGate.promise;await state.hook('restore');return state.restore},getCurrentUser:()=>({id:1}),refreshSession:async()=>{event('credentials');if(state.refreshGate)await state.refreshGate.promise;}};
 const bg={init:async()=>event('background-init'),reset:async()=>{event('reset');if(state.resetError)throw Error('reset failure')},stopAndInvalidate:async()=>{event('stop');return state.stop},reconcile:async()=>event('reconcile')};
 const signIn={bootstrapAutoSignIn:async()=>event('startup-sign'),setForeground:active=>event(active?'resume-sign-schedule':'pause-sign-schedule')};
 const deps={'@kit.AbilityKit':{UIAbility:class{},ConfigurationConstant:{ColorMode:{}}},'@kit.PerformanceAnalysisKit':{hilog:{info(){},warn(){},error(){}}},'@kit.ArkUI':{},RelationalStoreHelper:{RelationalStoreHelper:{init:async()=>event('database')}},PreferencesStore:{PreferencesStore:{init:async()=>event('preferences'),bumpLaunchTimes:()=>event('launch')}},BackupService:{BackupService:{getInstance:()=>({recoverInterruptedRestore:async()=>{event('recover');assert.ok(state.hook);if(state.recoveryError)throw Error('journal recovery incomplete')}})}},UserService:{UserService:{getInstance:()=>user}},BackgroundTaskService:{BackgroundTaskService:bg},NotificationHelper:{NotificationHelper:{init:async()=>event('notification-slot')}},DailyNoteService:{DailyNoteService:{getInstance:()=>({setForeground:active=>event(active?'resume-note-schedule':'pause-note-schedule'),bootstrapAutoRefresh:async()=>event('foreground-daily'),clearCardSnapshot:async()=>event('clear-card')})}},AutoSignInService:{AutoSignInService:{getInstance:()=>signIn}},AppContext:{AppContextProvider:{init:()=>event('context')}},Motion:{Motion:{}},GameDataService:{GameDataService:{initializeSnapshot:async()=>event('metadata')}},RiskVerifyModal:{},UiSurface:{UiSurface:{publish:()=>event('material')}}};
 deps.AppLocaleService={AppLocaleService:{initialize:()=>event('locale'),onConfigurationUpdate(){}}};
 deps.Logger={Logger:{flush:async()=>{}}};
 deps.RiskVerifyService={RiskVerifyService:{getInstance:()=>({cancel(){}})}};
 const storage=new Map();
 const Ability=load('entryability/EntryAbility',deps,{AppStorage:{get:key=>storage.get(key),setOrCreate:(key,value)=>storage.set(key,value)}}).default;
 const Backup=load('entrybackupability/EntryBackupAbility',{'@kit.CoreFileKit':{BackupExtensionAbility:class{}},'@kit.PerformanceAnalysisKit':deps['@kit.PerformanceAnalysisKit'],BackgroundTaskService:{BackgroundTaskService:bg},DailyNoteService:deps.DailyNoteService}).default;
 return {state,Ability,Backup};
}
(async()=>{
 await test('foreground note refresh is opt-in and stores the five upstream intervals',async()=>{
  const saved=new Map();
  const preferences={getSync:(key,fallback)=>saved.get(key)??fallback,putSync:(key,value)=>saved.set(key,value),
    flush:async()=>{}};
  const {PreferencesStore:prefs}=load('data/prefs/PreferencesStore',{
    '@kit.ArkData':{preferences:{getPreferences:async()=>preferences}},
    Logger:{Logger:{info(){},warn(){}}},BackupSnapshot:{},
  });
  await prefs.init({});
  assert.equal(prefs.getAutoRefreshEnabled(),false);
  assert.equal(prefs.getRefreshIntervalMinutes(),30);
  assert.deepEqual(Array.from(prefs.DAILY_NOTE_REFRESH_INTERVALS),[4,8,30,40,60]);
  for(const minutes of prefs.DAILY_NOTE_REFRESH_INTERVALS){
   prefs.setRefreshIntervalMinutes(minutes);
   assert.equal(prefs.getRefreshIntervalMinutes(),minutes);
  }
  saved.set(prefs.KEY_REFRESH_INTERVAL,15);
  assert.equal(prefs.getRefreshIntervalMinutes(),15);
  prefs.setRefreshIntervalMinutes(13);
  assert.equal(prefs.getRefreshIntervalMinutes(),15);
  prefs.setAutoRefreshEnabled(true);
  assert.equal(prefs.getAutoRefreshEnabled(),true);
 });
 await test('activation is read-only, repeat activation has one listener, detach drops stale loads',async()=>{
  const h=harness();h.state.readGate=deferred();h.model.activate();h.model.activate();assert.equal(h.state.listeners.size,1);h.model.invalidate();h.state.readGate.resolve();await flush();assert.equal(h.model.daily.kind,undefined);assert.equal(h.state.calls.length,0);assert.equal(h.state.listeners.size,0);h.model.activate();await flush();assert.equal(h.model.daily.kind,'daily_note');
 });
 await test('copied revision dispatch cannot publish after another listener detaches the controls',async()=>{
  const h=harness();h.state.listeners.add(()=>h.model.invalidate());h.model.activate();await flush();h.model.message='before';h.model.busy=false;const reads=h.state.reads;h.change();await flush();assert.equal(h.model.message,'before');assert.equal(h.model.busy,false);assert.equal(h.state.reads,reads);
 });
 await test('global scope confirmation is explicit and single use',async()=>{
  const h=harness();h.page.aboutToAppear();await flush();
  h.page.enable(h.kinds.DAILY_NOTE);h.page.enable(h.kinds.SIGN_IN);
  assert.equal(h.state.dialogs.length,1);assert.equal(h.state.calls.length,0);
  const dialog=h.state.dialogs[0];
  assert.match(dialog.message,/所有已追踪的国服角色/);
  assert.match(dialog.message,/Webhook/);
  assert.doesNotMatch(dialog.message,/100000001|private-fixture/);
  dialog.primaryButton.action();assert.equal(h.state.calls.length,0);
  h.page.enable(h.kinds.DAILY_NOTE);
  const next=h.state.dialogs[1];next.secondaryButton.action();next.secondaryButton.action();await flush();
  assert.equal(h.state.calls.length,1);
  assert.equal(h.state.calls[0][3].revision,1);
  assert.equal(h.state.calls[0][3].userId,0);
 });
 await test('switch away-and-back, page hide, detach or old dialog callback cannot enable a new owner',async()=>{
  for(const cancel of ['switch','hide','detach']){const h=harness();h.page.aboutToAppear();h.page.enable(h.kinds.SIGN_IN);if(cancel==='switch'){h.change();h.change();}else if(cancel==='hide'){h.page.active=false;h.page.visibilityChanged();h.page.active=true;h.page.visibilityChanged();}else{h.page.aboutToDisappear();h.page.aboutToAppear();}h.state.dialogs[0].secondaryButton.action();await flush();assert.equal(h.state.calls.length,0,cancel);}
 });
 await test('disabled controls serialize mutation, explicit retry calls correct service, and failures recover',async()=>{
  const h=harness();h.model.activate();await flush();h.state.gate=deferred();const retry=h.model.retry(h.kinds.DAILY_NOTE);await h.model.retry(h.kinds.SIGN_IN);await h.model.disable(h.kinds.SIGN_IN);assert.equal(h.state.calls.length,1);h.state.gate.resolve();await retry;h.state.gate=undefined;await h.model.disable(h.kinds.DAILY_NOTE);assert.deepEqual(h.state.calls[1].slice(0,3),['enable','daily_note',false]);h.state.fail=true;const review=h.model.prepareEnable(h.kinds.DAILY_NOTE);await h.model.confirmEnable(review);assert.equal(h.model.busy,false);assert.match(h.model.message,/未完成/);await h.model.retryCurrentSignIn();assert.equal(h.state.calls.at(-1)[0],'sign');assert.equal(h.model.message,'fixture retry result');
 });
 await test('stale foreground sign-in outcome never appears for replacement owner or detached page',async()=>{
  for(const mode of ['switch','detach']){const h=harness();h.model.activate();h.state.gate=deferred();const pending=h.model.retryCurrentSignIn();if(mode==='switch')h.change();else h.model.invalidate();h.state.gate.resolve();await pending;assert.notEqual(h.model.message,'fixture retry result');}
 });
 await test('local startup is coalesced and deferred maintenance never blocks its completion',async()=>{
  const h=lifecycle();h.state.restoreGate=deferred();h.state.refreshGate=deferred();
  const a=h.Ability.initializeRuntime({}),b=h.Ability.initializeRuntime({});
  await flush();
  assert.equal(h.state.events.filter(x=>x==='hook').length,1);
  assert.ok(h.state.events.indexOf('hook')<h.state.events.indexOf('recover'));
  assert.equal(h.state.events.includes('reset'),false);
  assert.equal(h.state.events.includes('reconcile'),false);
  h.state.restoreGate.resolve();await Promise.all([a,b]);
  assert.equal(h.state.events.filter(x=>x==='restore').length,1);
  assert.equal(h.state.events.includes('credentials'),false);
  assert.equal(h.state.events.includes('notification-slot'),false);
  assert.equal(h.state.events.includes('startup-sign'),false);
  h.Ability.startDeferredServices();h.Ability.startDeferredServices();await flush();
  assert.equal(h.state.events.filter(x=>x==='credentials').length,1);
  assert.equal(h.state.events.filter(x=>x==='reconcile').length,1);
  assert.equal(h.state.events.filter(x=>x==='startup-sign').length,1);
  await h.Ability.initializeRuntime({});
  assert.equal(h.state.events.filter(x=>x==='restore').length,1);
  h.state.refreshGate.resolve();await flush();
 });
 await test('logout and replacement reset; account removal and selection changes fence and requeue on commit',async()=>{
  const h=lifecycle();await h.Ability.initializeRuntime({});
  for(const reason of ['logout','localReplacement']){const count=h.state.events.length;assert.equal(await h.state.hook(reason),true);assert.deepEqual(h.state.events.slice(count),['reset','clear-card']);}
  for(const reason of ['delete','restore','reload','switch','defaultUid','refreshRoles']){const count=h.state.events.length;assert.equal(await h.state.hook(reason),true);assert.deepEqual(h.state.events.slice(count),['stop','clear-card']);}
  const count=h.state.events.length;
  h.state.transition=true;h.state.listener();assert.equal(h.state.events.length,count);
  h.state.transition=false;h.state.listener();assert.deepEqual(h.state.events.slice(count),['reconcile']);
  h.state.stop=false;assert.equal(await h.state.hook('switch'),false);h.state.resetError=true;assert.equal(await h.state.hook('logout'),false);
 });
 await test('journal recovery failure prevents restore/reconcile/foreground work and initialization can retry',async()=>{
  const h=lifecycle();
  h.state.recoveryError=true;
  await assert.rejects(h.Ability.initializeRuntime({}));
  new h.Ability().onForeground();
  assert.equal(h.state.events.includes('restore'),false);
  assert.equal(h.state.events.includes('reconcile'),false);
  assert.equal(h.state.events.includes('foreground-daily'),false);
  assert.equal(h.state.events.includes('launch'),false,'failed startup does not increment the launch count');
  h.state.recoveryError=false;
  await h.Ability.initializeRuntime({});
  await h.Ability.initializeRuntime({});
  assert.ok(h.state.events.includes('restore'));
  assert.equal(h.state.events.filter(event=>event==='launch').length,1,'successful retry counts the process once');
 });
 await test('foreground daily sign-in scheduling follows the initialized ability lifecycle',async()=>{
  const h=lifecycle();
  const ability=new h.Ability();
  ability.onForeground();
  assert.ok(!h.state.events.includes('resume-sign-schedule'));
  await h.Ability.initializeRuntime({});
  const beforePage = h.state.events.length;
  ability.onForeground();
  assert.equal(h.state.events.length, beforePage, 'foreground before Index finishes loading must not start network work');
  h.Ability.startDeferredServices();await flush();
  assert.ok(h.state.events.indexOf('startup-sign')<h.state.events.indexOf('resume-sign-schedule'));
  ability.onBackground();
  assert.deepEqual(h.state.events.slice(-2),['pause-sign-schedule','pause-note-schedule']);
  ability.onForeground();
  assert.equal(h.state.events.filter(event=>event==='resume-sign-schedule').length,2);
  ability.onDestroy();
  assert.deepEqual(h.state.events.slice(-2),['pause-sign-schedule','pause-note-schedule']);
 });
 await test('OS restore initializes then resets before completion and propagates a failed reset',async()=>{
  const h=lifecycle();await new h.Backup().onRestore({});assert.deepEqual(h.state.events,['background-init','reset','clear-card']);h.state.resetError=true;await assert.rejects(new h.Backup().onRestore({}));assert.ok(!h.state.events.includes('restore'));
 });
 await test('background folder persists a read-only grant before saving it and retains session-only access on failure',async()=>{
  const source=read('pages/SettingPage');
  const start=source.indexOf('  async pickBgFolder(');
  const end=source.indexOf('\n  }',start)+'\n  }'.length;
  const code=ts.transpileModule(`class FolderPicker {bgFolderPicking=false;${source.slice(start,end)}}\nmodule.exports=FolderPicker;`,{
   compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}
  });
  const uri='file://docs/storage/Users/currentUser/Pictures';
  const gate=deferred(),calls=[],stored=[],published=[],messages=[];
  let selection=[uri],supported=true,persistence=gate.promise;
  const module={exports:{}};
  vm.runInNewContext(code.outputText,{module,$r:key=>key,canIUse:capability=>{
   assert.equal(capability,'SystemCapability.FileManagement.AppFileService.FolderAuthorization');return supported;
  },picker:{DocumentSelectOptions:class{},DocumentSelectMode:{FOLDER:1},DocumentViewPicker:class{
   async select(options){assert.equal(options.selectMode,1);calls.push('select');return selection;}
  }},fileShare:{OperationMode:{READ_MODE:1},async persistPermission(policies){
   assert.deepEqual(JSON.parse(JSON.stringify(policies)),[{uri,operationMode:1}]);calls.push('persist');await persistence;
  }},PreferencesStore:{setBackgroundFolderPath:path=>stored.push(path)},
  AppStorage:{setOrCreate:(key,path)=>published.push([key,path])},Logger:{warn(){}},TAG:'fixture'});
  const target=new module.exports();target.toast=message=>messages.push(message);
  const pending=target.pickBgFolder();await flush();await target.pickBgFolder();
  assert.deepEqual(calls,['select','persist']);assert.deepEqual(stored,[]);assert.deepEqual(published,[]);
  gate.resolve();await pending;
  assert.deepEqual(stored,[uri]);assert.deepEqual(published,[['bgFolderPath',uri]]);
  assert.equal(messages.at(-1),'app.string.ui_bg_folder_saved');assert.equal(target.bgFolderPicking,false);
  persistence=Promise.reject(new Error('persistent access unavailable'));
  await target.pickBgFolder();assert.deepEqual(stored,[uri]);assert.equal(published.length,2);
  assert.equal(messages.at(-1),'app.string.ui_bg_folder_temporary');
  supported=false;await target.pickBgFolder();assert.deepEqual(stored,[uri]);assert.equal(published.length,3);
  selection=[];await target.pickBgFolder();assert.equal(published.length,3);
 });
 await test('production route/resources/backup/privacy contracts are exact and Settings retains help/cancel update',()=>{
  const pages=JSON.parse(fs.readFileSync(path.join(root,'../resources/base/profile/main_pages.json'),'utf8')).src;assert.equal(pages.filter(x=>x==='pages/UpdatePage').length,1);assert.match(read('pages/UpdatePage'),/export struct UpdatePage[\s\S]*@Prop embedMode/);
  const settings=read('pages/SettingPage');assert.match(settings,/router\.pushUrl\(\{ url: 'pages\/UpdatePage'/);assert.match(settings,/pages\/HelpPage/);assert.match(settings,/cancelGameData/);assert.ok(!/checkAppUpdate|confirmOpenUrl|ApiClient|releases\/latest/.test(settings));assert.match(settings,/onPageHide\(\): void \{ this.backgroundControlsActive = false/);
  const ui=read('components/BackgroundTaskSettings');assert.match(ui,/Number\(area.width\) >= 840/);assert.equal((ui.match(/Button\(/g)||[]).length,(ui.match(/\.height\(44\)/g)||[]).length);assert.ok(!/requestPermission|requestEnableNotification|RiskVerifier/.test(ui+read('viewmodel/BackgroundTaskSettingsViewModel')));
  for(const mode of ['base','dark']){const colors=new Set(JSON.parse(fs.readFileSync(path.join(root,`../resources/${mode}/element/color.json`),'utf8')).color.map(x=>x.name));for(const match of ui.matchAll(/\$r\('app\.color\.([^']+)'\)/g))assert.ok(colors.has(match[1]),`${mode} ${match[1]}`);}
  const backup=JSON.parse(fs.readFileSync(path.join(root,'../resources/base/profile/backup_config.json'),'utf8'));assert.equal(backup.allowToBackupRestore,true);assert.deepEqual(backup.excludes,['/data/storage/el2/database/entry/rdb/hutao_background/']);assert.match(read('data/repo/BackgroundTaskRepo'),/customDir:\s*'hutao_background'/);
 });
 console.log('background-settings-integration: PASS (production VM, consent ownership, lifecycle, OS backup, route and resources)');
})().catch(error=>{console.error(error);process.exitCode=1});
