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
 class Task{constructor(){this.enabled=false;this.queued=false;this.message='disabled';}}
 const kinds={DAILY_NOTE:'daily_note',SIGN_IN:'sign_in'};
 const user={sessionRevision:()=>state.revision,addSessionRevisionListener:f=>{state.listeners.add(f);return()=>state.listeners.delete(f)}};
 const service={EXPLANATION:'系统择机执行',getState:async kind=>{state.reads++;if(state.readGate)await state.readGate.promise;const result=new Task();result.kind=kind;return result;},captureBinding:()=>{if(state.captureFailure)throw Error();const binding=new Binding();binding.revision=state.revision;return binding;},setEnabled:async(kind,value,binding)=>{state.calls.push(['enable',kind,value,binding]);if(state.gate)await state.gate.promise;if(state.fail)throw Error('fixture');},retryBlocked:async kind=>{state.calls.push(['retry',kind]);if(state.gate)await state.gate.promise;}};
 const deps={BackgroundTask:{BackgroundTaskBinding:Binding,BackgroundTaskState:Task,BackgroundTaskKind:kinds},BackgroundTaskService:{BackgroundTaskService:service},UserService:{UserService:{getInstance:()=>user}},AutoSignInService:{AutoSignInService:{getInstance:()=>({retryCurrent:async()=>{state.calls.push(['sign']);if(state.gate)await state.gate.promise;return {message:'fixture retry result'};}})}}};
 const classes=load('viewmodel/BackgroundTaskSettingsViewModel',deps);deps.BackgroundTaskSettingsViewModel=classes;
 const Model=classes.BackgroundTaskSettingsViewModel;
 const Page=load('components/BackgroundTaskSettings',deps).BackgroundTaskSettings;
 const page=new Page();page.getUIContext=()=>({showAlertDialog:dialog=>state.dialogs.push(dialog)});
 return {state,kinds,model:new Model(),page,change:()=>{state.revision++;for(const f of [...state.listeners])f(state.revision);}};
}
function lifecycle(){
 const state={events:[],hook:undefined,restore:true,resetError:false,stop:true,restoreGate:undefined,recoveryError:false};
 const event=name=>{state.events.push(name)};
 const user={setSessionInvalidationHook:hook=>{event('hook');state.hook=hook},restoreSession:async()=>{event('restore');if(state.restoreGate)await state.restoreGate.promise;await state.hook('restore');return state.restore},getCurrentUser:()=>({id:1})};
 const bg={init:async()=>event('background-init'),reset:async()=>{event('reset');if(state.resetError)throw Error('reset failure')},stopAndInvalidate:async()=>{event('stop');return state.stop},reconcile:async()=>event('reconcile')};
 const deps={'@kit.AbilityKit':{UIAbility:class{},ConfigurationConstant:{ColorMode:{}}},'@kit.PerformanceAnalysisKit':{hilog:{info(){},warn(){},error(){}}},'@kit.ArkUI':{},RelationalStoreHelper:{RelationalStoreHelper:{init:async()=>event('database')}},PreferencesStore:{PreferencesStore:{init:async()=>event('preferences'),bumpLaunchTimes:()=>event('launch')}},BackupService:{BackupService:{getInstance:()=>({recoverInterruptedRestore:async()=>{event('recover');assert.ok(state.hook);if(state.recoveryError)throw Error('journal recovery incomplete')}})}},UserService:{UserService:{getInstance:()=>user}},BackgroundTaskService:{BackgroundTaskService:bg},NotificationHelper:{NotificationHelper:{init:async()=>event('notification-slot')}},DailyNoteService:{DailyNoteService:{getInstance:()=>({bootstrapAutoRefresh:async()=>event('foreground-daily'),clearCardSnapshot:async()=>event('clear-card')})}},AutoSignInService:{AutoSignInService:{getInstance:()=>({bootstrapAutoSignIn:async()=>event('startup-sign')})}},AppContext:{AppContextProvider:{init:()=>event('context')}},Motion:{Motion:{}},GameDataService:{GameDataService:{initializeSnapshot:async()=>event('metadata')}},RiskVerifyModal:{}};
 const Ability=load('entryability/EntryAbility',deps,{AppStorage:{setOrCreate(){}}}).default;
 const Backup=load('entrybackupability/EntryBackupAbility',{'@kit.CoreFileKit':{BackupExtensionAbility:class{}},'@kit.PerformanceAnalysisKit':deps['@kit.PerformanceAnalysisKit'],BackgroundTaskService:{BackgroundTaskService:bg},DailyNoteService:deps.DailyNoteService}).default;
 return {state,Ability,Backup};
}
(async()=>{
 await test('activation is read-only, repeat activation has one listener, detach drops stale loads',async()=>{
  const h=harness();h.state.readGate=deferred();h.model.activate();h.model.activate();assert.equal(h.state.listeners.size,1);h.model.invalidate();h.state.readGate.resolve();await flush();assert.equal(h.model.daily.kind,undefined);assert.equal(h.state.calls.length,0);assert.equal(h.state.listeners.size,0);h.model.activate();await flush();assert.equal(h.model.daily.kind,'daily_note');
 });
 await test('copied revision dispatch cannot publish after another listener detaches the controls',async()=>{
  const h=harness();h.state.listeners.add(()=>h.model.invalidate());h.model.activate();await flush();h.model.message='before';h.model.busy=false;const reads=h.state.reads;h.change();await flush();assert.equal(h.model.message,'before');assert.equal(h.model.busy,false);assert.equal(h.state.reads,reads);
 });
 await test('confirmation is explicit, UID-bound and single use; cancelling and duplicate clicks do not enable',async()=>{
  const h=harness();h.page.aboutToAppear();await flush();h.page.enable(h.kinds.DAILY_NOTE);h.page.enable(h.kinds.SIGN_IN);assert.equal(h.state.dialogs.length,1);assert.equal(h.state.calls.length,0);const dialog=h.state.dialogs[0];assert.match(dialog.message,/100000001/);assert.ok(!dialog.message.includes('private-fixture'));dialog.primaryButton.action();assert.equal(h.state.calls.length,0);h.page.enable(h.kinds.DAILY_NOTE);const next=h.state.dialogs[1];next.secondaryButton.action();next.secondaryButton.action();await flush();assert.equal(h.state.calls.length,1);assert.equal(h.state.calls[0][3].revision,1);assert.equal(h.state.calls[0][3].uid,'100000001');
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
 await test('coalesced startup installs one hook before recovery, preserves opt-in and reconciles only matching restore',async()=>{
  const h=lifecycle();h.state.restoreGate=deferred();const a=h.Ability.initializeRuntime({}),b=h.Ability.initializeRuntime({});await flush();assert.equal(h.state.events.filter(x=>x==='hook').length,1);assert.ok(h.state.events.indexOf('hook')<h.state.events.indexOf('recover'));assert.equal(h.state.events.includes('reset'),false);assert.equal(h.state.events.includes('reconcile'),false);h.state.restoreGate.resolve();await Promise.all([a,b]);assert.equal(h.state.events.filter(x=>x==='restore').length,1);assert.equal(h.state.events.filter(x=>x==='reconcile').length,1);await h.Ability.initializeRuntime({});assert.equal(h.state.events.filter(x=>x==='restore').length,1);
  const failed=lifecycle();failed.state.restore=false;await failed.Ability.initializeRuntime({});assert.equal(failed.state.events.includes('reconcile'),false);
 });
 await test('destructive invalidation resets; ordinary changes fence; failures propagate as false',async()=>{
  const h=lifecycle();await h.Ability.initializeRuntime({});for(const reason of ['logout','delete','localReplacement']){const count=h.state.events.length;assert.equal(await h.state.hook(reason),true);assert.deepEqual(h.state.events.slice(count),['reset','clear-card']);}for(const reason of ['restore','reload','switch','defaultUid','refreshRoles']){const count=h.state.events.length;assert.equal(await h.state.hook(reason),true);assert.deepEqual(h.state.events.slice(count),['stop','clear-card']);}h.state.stop=false;assert.equal(await h.state.hook('switch'),false);h.state.resetError=true;assert.equal(await h.state.hook('logout'),false);
 });
 await test('journal recovery failure prevents restore/reconcile/foreground work and initialization can retry',async()=>{
  const h=lifecycle();h.state.recoveryError=true;await assert.rejects(h.Ability.initializeRuntime({}));new h.Ability().onForeground();assert.equal(h.state.events.includes('restore'),false);assert.equal(h.state.events.includes('reconcile'),false);assert.equal(h.state.events.includes('foreground-daily'),false);h.state.recoveryError=false;await h.Ability.initializeRuntime({});assert.ok(h.state.events.includes('restore'));
 });
 await test('OS restore initializes then resets before completion and propagates a failed reset',async()=>{
  const h=lifecycle();await new h.Backup().onRestore({});assert.deepEqual(h.state.events,['background-init','reset','clear-card']);h.state.resetError=true;await assert.rejects(new h.Backup().onRestore({}));assert.ok(!h.state.events.includes('restore'));
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
