// Production help/search/outcomes/policy/VM and page lifecycle. Platform boundaries are counted doubles.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = name => fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
const plain = value => JSON.parse(JSON.stringify(value));
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return {promise,resolve,reject}; };
const flush = async () => { for(let i=0;i<30;i++)await Promise.resolve(); };
const IDs = ['accounts','import','data','backups','daily-note','devices','privacy'];
const LOCALES = ['zh-Hans','zh-Hant','en','de','es','fr','id','it','ja','ko','pt','ru','th','tr','vi'];
const sourceRoot = path.resolve(__dirname, '../tools/help-locales');
const catalogNames = fs.readdirSync(path.join(root, 'data/help')).filter(n => n.endsWith('.ets')).map(n => 'data/help/' + n.slice(0,-4));
function harness() {
  const cache = new Map();
  const state = { preference:'system', language:'zh-CN', ready:true, appReads:0, deviceReads:0, themeReads:0,
    preferenceReads:0, preferenceWrites:0, clipboardReads:0, copies:[], routes:[], links:[],
    theme:'system', appVersion:'1.21.0', api:24, deviceType:'phone', appStorage:new Map(), copyGate:undefined };
  const prefs = { isReady:()=>state.ready, getString:()=>{state.preferenceReads++;return state.preference;},
    setString:(_key,value)=>{state.preferenceWrites++;state.preference=value;},
    getThemeMode:()=>{state.themeReads++;return state.theme;} };
  const device = { get sdkApiVersion(){state.deviceReads++;return state.api;}, get deviceType(){state.deviceReads++;return state.deviceType;},
    get osFullName(){throw Error('Forbidden full system identifier');},get serial(){throw Error('Forbidden serial');} };
  const kits={
    '@kit.LocalizationKit':{i18n:{System:{getSystemLanguage:()=>state.language}}},
    '@kit.AbilityKit':{bundleManager:{BundleFlag:{GET_BUNDLE_INFO_DEFAULT:0},getBundleInfoForSelfSync:()=>{state.appReads++;return {versionName:state.appVersion};}}},
    '@kit.BasicServicesKit':{deviceInfo:device,pasteboard:{MIMETYPE_TEXT_PLAIN:'text/plain',createData:(_type,text)=>text,
      getSystemPasteboard:()=>({setData:async text=>{state.copies.push(text);if(state.copyGate)await state.copyGate.promise;},getData:()=>{state.clipboardReads++;throw Error('Forbidden clipboard read');}})}},
    '@kit.ArkUI':{router:{pushUrl:async args=>{state.routes.push(args);}}}
  };
  const globals={Observed:v=>v,Entry:v=>v,Component:v=>v,Prop:()=>{},State:()=>{},StorageProp:()=>()=>{},Watch:()=>()=>{},
    AppStorage:{get:key=>state.appStorage.get(key),setOrCreate:(key,value)=>state.appStorage.set(key,value)}};
  function load(name){
    if(cache.has(name))return cache.get(name);
    if(kits[name])return kits[name];
    if(name==='data/prefs/PreferencesStore')return {PreferencesStore:prefs};
    if(name==='common/AppContext')return {AppContextProvider:{getAppContext:()=>({openLink:async url=>state.links.push(url)})}};
    if(name.startsWith('components/'))return {};
    let source=read(name);
    if(name==='pages/HelpPage')source=source.slice(0,source.indexOf('  @Builder'))+'}';
    source=source.replace('export struct HelpPage','export class HelpPage');
    const result=ts.transpileModule(source,{reportDiagnostics:true,compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}});
    assert.equal(result.diagnostics.length,0,name);
    const module={exports:{}};
    vm.runInNewContext(`(function(require,module,exports){${result.outputText}\n})`,globals)(
      id=>load(id.startsWith('@')?id:path.posix.normalize(path.posix.join(path.posix.dirname(name),id))),module,module.exports);
    cache.set(name,module.exports);return module.exports;
  }
  return {state,load,Search:load('service/DocumentationSearchService').DocumentationSearchService,
    Policy:load('model/LocalePolicy').LocalePolicy,Out:load('model/CommonOutcome'),Text:load('model/CommonOutcomeText').CommonOutcomeText,
    Diagnostic:load('model/DiagnosticPolicy'),Support:load('service/SupportService').SupportService,
    Locale:load('service/AppLocaleService').AppLocaleService,Model:load('viewmodel/HelpViewModel').HelpViewModel,
    page:()=>new (load('pages/HelpPage').HelpPage)()};
}
function strictTypes() {
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hutao-offline-help-'));
 const names=['model/LocalePolicy','model/HelpDocument','model/CommonOutcome','model/CommonOutcomeText','model/HelpText',
  'model/DiagnosticPolicy',...catalogNames,'service/DocumentationSearchService','viewmodel/HelpViewModel','service/AppLocaleService'];
 for(const name of names){const file=path.join(dir,name+'.ts');fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,read(name));}
 const write=(name,text)=>{const file=path.join(dir,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,text);};
 write('service/SupportService.ts',`import {CommonOutcomeId} from '../model/CommonOutcome';import {DiagnosticPreview} from '../model/DiagnosticPolicy';export class SupportService {static async previewDiagnostics(feature:string,outcome:CommonOutcomeId,include:boolean):Promise<DiagnosticPreview>{return new DiagnosticPreview();}static async copyDiagnosticPreview(preview:DiagnosticPreview):Promise<void>{}}`);
 write('data/prefs/PreferencesStore.ts',`export class PreferencesStore {static getString(key:string,value:string):string{return value;}static isReady():boolean{return true;}static setString(key:string,value:string):void{}}`);
 write('globals.d.ts',`declare function Observed<T extends new (...args:never[])=>object>(value:T):T;declare const AppStorage:{get<T>(key:string):T|undefined;setOrCreate<T>(key:string,value:T):void};declare module '@kit.LocalizationKit' {export const i18n:{System:{getSystemLanguage():string}};}`);
 const program=ts.createProgram([...names.map(n=>path.join(dir,n+'.ts')),path.join(dir,'globals.d.ts')],{strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,experimentalDecorators:true,skipLibCheck:true});
 const errors=ts.getPreEmitDiagnostics(program).filter(d=>d.category===ts.DiagnosticCategory.Error);
 assert.equal(errors.length,0,ts.formatDiagnosticsWithColorAndContext(errors,{getCurrentDirectory:()=>dir,getCanonicalFileName:x=>x,getNewLine:()=> '\n'}));
}
(async()=>{
 await test('105 actionable articles in all fifteen shipped locales preserve identities/routes',()=>{
  const {Search,Policy}=harness();
  assert.deepEqual(plain(Policy.locales()),LOCALES);
  let articleCount=0;
  for(const locale of Policy.locales()){
   articleCount+=7;
   const docs=Search.documents(locale);assert.deepEqual(plain(docs.map(d=>d.id)),IDs);assert.equal(new Set(docs.map(d=>d.id)).size,7);
   for(const doc of docs){assert(doc.title.length>3);assert(doc.summary.length>15);assert.equal(doc.steps.length,4);assert(doc.steps.every(s=>s.length>20));assert.deepEqual(plain([doc.keywords,doc.route]),plain([Search.document(doc.id,'en').keywords,Search.document(doc.id,'en').route]));}
  }
  assert.equal(articleCount,105);
  assert.match(Search.document('backups','en').summary,/credentials/);assert.match(Search.document('privacy','en').summary,/never.*UIDs.*logs/);
  assert.notEqual(Search.document('accounts','zh-Hans').title,Search.document('accounts','zh-Hant').title);
  assert.notEqual(Search.document('accounts','zh-Hant').title,Search.document('accounts','en').title);
 });
 await test('locale canonicalization honors explicit script and unsupported language fallback',()=>{
  const {Policy,Locale,state}=harness();
  for(const [input,expected] of [['zh','zh-Hans'],['zh_CN','zh-Hans'],['zh-SG','zh-Hans'],['zh-TW','zh-Hant'],['zh-HK','zh-Hant'],['zh-MO','zh-Hant'],['zh-Hans-TW','zh-Hans'],['zh-Hant-CN','zh-Hant'],['en-GB','en'],['es-MX','es'],['fr_CA','fr'],['pt-BR','pt'],['de-Latn-DE','de'],['id-ID','id'],['it-IT','it'],['ja-Jpan-JP','ja'],['ko-Kore-KR','ko'],['ru-Cyrl-RU','ru'],['th-TH','th'],['tr-TR','tr'],['vi-VN','vi'],['zh-u-rg-twzzzz','zh-Hans'],['zh-Latn-CN','en'],['ar-SA','en'],['de-','en'],['en--US','en'],['constructor','en'],['','en']])assert.equal(Policy.resourceLocale(input),expected,input);
  assert.equal(Policy.supported('fr-FR'),true);assert.equal(Policy.supported('ar-SA'),false);assert.equal(Policy.supported('zh-Latn'),false);assert.equal(Policy.supported('EN_us'),true);
  const locales=Policy.locales();locales.push('evil');assert.equal(Policy.locales().length,15);
  assert.equal(Locale.current(),'zh-Hans');state.language='ar-SA';assert.equal(Locale.current(),'en');assert.equal(Locale.usingFallback(),true);
  assert.equal(Locale.select('zh-Hant'),true);assert.equal(Locale.current(),'zh-Hant');assert.equal(Locale.usingFallback(),false);assert.equal(state.preferenceWrites,1);
  assert.equal(Locale.select('en-US'),false);assert.equal(Locale.select('invalid'),false);assert.equal(state.preferenceWrites,1);
  assert.equal(Locale.select('system'),true);assert.equal(state.appStorage.get('helpLocaleVersion'),2);
  state.ready=false;assert.equal(Locale.select('en'),false);assert.equal(state.preferenceWrites,2);
 });
 await test('offline search ANDs bounded terms, folds diacritics/letters and searches all canonical languages',()=>{
  const {Search}=harness();
  for(const locale of LOCALES){
   assert.deepEqual(plain(Search.search('UIGF archive',locale).map(d=>d.id)),['import']);
   assert(Search.search('備份',locale).some(d=>d.id==='backups'));
   assert(Search.search('contraSENA',locale).some(d=>d.id==='accounts'));
   assert(Search.search('sifre',locale).some(d=>d.id==='accounts'));
   assert(Search.search('dien thoai',locale).some(d=>d.id==='accounts'));
   assert.equal(Search.search('notarealword',locale).length,0);assert.equal(Search.search(' \n \t ',locale).length,7);
  }
  assert.equal(Search.normalize('Électricité Straße cœur Æ Łódź ı Đ'), 'electricite strasse coeur ae lodz i d');
  assert.equal(Search.search(' '.repeat(120)+'impossible').length,7,'query truncated before work');
  assert.deepEqual(plain(Search.search('UIGF '.repeat(12)+'impossible').map(d=>d.id)),plain(Search.search('UIGF').map(d=>d.id)),'at most twelve terms');
  for(let i=0;i<2000;i++)Search.search('backup','unknown-'+i);
  assert.equal(Search.indexes.size,15);assert.equal(Search.common.size,7);
 });
 await test('search/catalog results and array mutations cannot poison future documents or routes',()=>{
  const {Search}=harness();const first=Search.documents('en'),expected=Search.document('accounts','en').title;
  first[0].title='poison';first[0].steps.push('secret');first[0].route='pages/LoginPage?token=secret';first.pop();
  const doc=Search.document('accounts','en');assert.equal(doc.title,expected);assert.equal(doc.steps.length,4);assert.equal(Search.documents('en').length,7);assert.equal(Search.routeFor('accounts'),'pages/UserPage');assert.equal(Search.routeFor('unknown'),'');
  const translated=Search.search('account','zh-Hant');translated[0].steps[0]='mutated';assert.notEqual(Search.search('account','zh-Hant')[0].steps[0],'mutated');
 });
 await test('typed outcomes cover every locale without raw-error or parameter leakage',()=>{
  const {Out,Text}=harness();
  for(const id of Object.values(Out.CommonOutcomeId))for(const locale of LOCALES){
   const text=Text.text(new Out.CommonOutcome(id,7),locale);assert.equal(text.length>0,id!=='');assert(!text.includes('{count}'));
  }
  assert.match(Text.text(new Out.CommonOutcome(Out.CommonOutcomeId.ImportComplete,7),'en'),/7 records/);
  const bad=new Out.CommonOutcome('cookie=secret',-1);bad.count='token=secret';assert(!Text.text(bad,'fr').includes('secret'));assert.match(Text.text(bad,'en'),/did not complete/);
  const poisoned=new Out.CommonOutcome(Out.CommonOutcomeId.ImportComplete,Infinity);assert.match(Text.text(poisoned,'en'),/0 records/);
 });
 await test('diagnostics reconstruct allowlisted fields and strip poisoned values and extra properties',()=>{
  const {Diagnostic:D,Out}=harness();const p=new D.DiagnosticPreview();p.feature='uid=123456789';p.outcome='cookie=secret';p.generatedAt=NaN;p.cookie='SECRET';p.uid='123456789';
  p.environment=new D.DiagnosticEnvironment();Object.assign(p.environment,{appVersion:'1.2.3\ncookie=secret',api:123456789,deviceType:'serial=secret',theme:'token=secret',rawLogs:'SECRET',uid:'123456789'});
  const text=D.DiagnosticPolicy.serialize(p);assert(!text.includes('SECRET'));assert(!text.includes('secret'));assert(!text.includes('123456789'));assert.match(text,/Feature: privacy/);assert.match(text,/Outcome: failed/);assert.match(text,/API: unknown/);
  p.feature='import';p.outcome=Out.CommonOutcomeId.InvalidFile;p.generatedAt=Date.parse('2026-10-05T12:00:00Z');Object.assign(p.environment,{appVersion:'1.21.0',api:24,deviceType:'2in1',theme:'dark'});
  const safe=D.DiagnosticPolicy.sanitize(p);assert.deepEqual(Object.keys(safe.environment).sort(),['api','appVersion','deviceType','theme']);assert.match(D.DiagnosticPolicy.serialize(safe),/2026-10-05T12:00:00.000Z/);
  safe.environment.theme='mutated';assert.equal(p.environment.theme,'dark');
 });
 await test('opening/searching/selecting help performs no diagnostics, account, clipboard or external IO',()=>{
  const {Model,state}=harness();const target=new Model();target.activate('en');target.setQuery('account');target.select('accounts');target.setLocale('zh-Hant');target.setEnvironment(true);target.setIssue('permissionRequired');target.invalidate();
  assert.equal(state.appReads,0);assert.equal(state.deviceReads,0);assert.equal(state.themeReads,0);assert.equal(state.copies.length,0);assert.equal(state.clipboardReads,0);assert.equal(state.links.length,0);assert.equal(state.routes.length,0);assert.equal(state.preferenceReads,0);
 });
 await test('explicit preview reads optional environment only once requested; copy is separate and re-sanitized',async()=>{
  const {Model,state}=harness();const target=new Model();target.activate('en');target.select('privacy');
  await target.generatePreview();assert(target.previewText().length>0);assert.equal(state.appReads,0);assert.equal(state.deviceReads,0);assert.equal(state.themeReads,0);assert.equal(state.copies.length,0);
  target.setEnvironment(true);assert.equal(target.preview,undefined);await target.generatePreview();assert.equal(state.appReads,1);assert.equal(state.deviceReads,2);assert.equal(state.themeReads,1);assert.match(target.previewText(),/API: 24/);
  target.preview.environment.appVersion='cookie=secret';await target.copyPreview();assert.equal(state.copies.length,1);assert(!state.copies[0].includes('secret'));assert.match(target.message(),/Copied/);assert.equal(state.clipboardReads,0);assert.equal(state.links.length,0);
 });
 await test('locale switches preserve query and selected article; mutation resets an obsolete preview',async()=>{
  const {Model}=harness();const target=new Model();target.activate('en');target.setQuery('UIGF');target.select('import');await target.generatePreview();target.setLocale('zh-Hant');assert.equal(target.query,'UIGF');assert.equal(target.selectedId,'import');assert.match(target.selected().title,/匯入/);assert.match(target.message(),/準備完成/);
  target.setIssue('loginExpired');assert.equal(target.preview,undefined);await target.generatePreview();target.setQuery('diagnostics');assert.equal(target.selectedId,'');assert.equal(target.preview,undefined);
 });
 await test('late preview, cancellation, detach/remount and stale failures cannot publish',async()=>{
  const {Model,Support,Diagnostic:D}=harness();const gates=[];Support.previewDiagnostics=()=>{const gate=deferred();gates.push(gate);return gate.promise;};
  const target=new Model();assert.equal(await target.generatePreview(),false);target.activate('en');target.select('data');const a=target.generatePreview();assert.equal(await target.generatePreview(),false);target.clearPreview();const b=target.generatePreview();gates[0].resolve(new D.DiagnosticPreview());assert.equal(await a,false);assert.equal(target.busy,true);
  target.invalidate();target.activate('en');const c=target.generatePreview();gates[1].reject(Error('secret late error'));assert.equal(await b,false);assert.equal(target.busy,true);gates[2].resolve(new D.DiagnosticPreview());assert.equal(await c,true);assert(target.preview);assert.equal(target.busy,false);
  const d=target.generatePreview();target.setEnvironment(true);gates[3].resolve(new D.DiagnosticPreview());assert.equal(await d,false);assert.equal(target.preview,undefined);assert.equal(target.busy,false);
 });
 await test('clipboard duplicate clicks are blocked and detached completion never reports success',async()=>{
  const {Model,state}=harness();const target=new Model();target.activate('en');target.select('privacy');await target.generatePreview();state.copyGate=deferred();const pending=target.copyPreview();assert.equal(await target.copyPreview(),false);assert.equal(state.copies.length,1);
  target.invalidate();target.activate('zh-Hans');assert.equal(target.busy,true);assert.equal(await target.generatePreview(),false);state.copyGate.resolve();assert.equal(await pending,false);assert.equal(target.busy,false);assert.equal(target.message(),'');assert.equal(target.preview,undefined);
  await target.generatePreview();state.copyGate=deferred();const next=target.copyPreview();target.invalidate();state.copyGate.reject(Error('secret'));assert.equal(await next,false);target.activate('en');assert.equal(target.busy,false);assert.equal(target.message(),'');
 });
 await test('page attachment is idempotent, route actions are explicit, and callbacks are fenced',async()=>{
  const {page,state,Support,Diagnostic:D}=harness();const target=page();target.aboutToAppear();target.onPageShow();assert.equal(state.appReads,0);assert.equal(state.deviceReads,0);assert.equal(state.themeReads,0);assert.equal(state.copies.length,0);
  target.select('accounts');assert.equal(state.routes.length,0);target.openRelated();await flush();assert.equal(state.routes[0].url,'pages/UserPage');target.selected.route='pages/evil';target.openRelated();await flush();assert.equal(state.routes[1].url,'pages/UserPage');
  const gate=deferred();Support.previewDiagnostics=()=>gate.promise;const pending=target.generate();target.onPageHide();target.onPageShow();gate.resolve(new D.DiagnosticPreview());await pending;assert.equal(target.previewText,'');target.aboutToDisappear();target.openRelated();assert.equal(state.routes.length,2);
 });
 await test('page locale failure and diagnostic failure remain typed, actionable and credential-free',async()=>{
  const {page,state,Support,Model}=harness();const target=page();target.aboutToAppear();state.ready=false;target.chooseLocale(3);assert.match(target.vm.message(),/未应用/);
  const model=new Model();model.activate('en');model.select('privacy');Support.previewDiagnostics=async()=>{throw Error('cookie=SECRET UID=123456789');};await model.generatePreview();assert.match(model.message(),/did not complete/);assert(!model.message().includes('SECRET'));assert.equal(model.preview,undefined);
 });
 await test('all source keysets and generated native articles/labels/outcomes match exactly without hidden English fallback',()=>{
  const {Search,Policy,Text,Out,load}=harness();const Help=load('model/HelpText').HelpText;
  const en=JSON.parse(fs.readFileSync(path.join(sourceRoot,'en.json'),'utf8'));
  assert.equal(Help.rows.length,25);assert.equal(Text.rows.length,18);
  assert.equal(new Set(Help.rows.map(row=>row.key)).size,25);assert.equal(new Set(Text.rows.map(row=>row.id)).size,18);
  for(const row of [...Help.rows,...Text.rows])assert.equal(row.values.length,15);
  for(const locale of LOCALES){
    const source=JSON.parse(fs.readFileSync(path.join(sourceRoot,locale+'.json'),'utf8'));
    assert.deepEqual(plain(Search.documents(locale)),source.articles,locale);
    assert.deepEqual(Object.keys(source.labels).sort(),Object.keys(en.labels).sort());
    assert.deepEqual(Object.keys(source.outcomes).sort(),Object.keys(Out.CommonOutcomeId).sort());
    for(const [key,text] of Object.entries(source.labels)){assert(text.trim());assert.equal(Help.text(key,locale),text);}
    for(const [key,text] of Object.entries(source.outcomes))assert.equal(Text.text(new Out.CommonOutcome(Out.CommonOutcomeId[key],9),locale),text.replace('{count}','9'));
    assert(source.articles[6].steps[0].includes(Help.text('generate',locale)),locale+' diagnostic button wording');
    for(const doc of source.articles){assert(Search.search(doc.title,locale).some(found=>found.id===doc.id),locale+' '+doc.id+' native title searchable');}
    if(locale!=='en'){assert.notEqual(source.articles[0].title,en.articles[0].title);assert.notEqual(Help.text('scope',locale),en.labels.scope);assert.notEqual(source.outcomes.PermissionRequired,en.outcomes.PermissionRequired);}
    assert(Policy.nativeName(locale).trim().length>0);
  }
  assert.equal(Help.text('noSuchLabel','en'),'');
  assert.equal(Help.text('fallback','ar-SA'),en.labels.fallback);
  execFileSync(process.execPath,[path.resolve(__dirname,'../tools/render-help-locales.cjs'),'--check'],{encoding:'utf8'});
 });
 await test('fifteen locale choices persist exactly; unsupported system tags visibly fall back to English',()=>{
  const {Locale,Policy,state,page}=harness();const target=page();target.aboutToAppear();
  assert.deepEqual(plain(target.localeKeys),['system',...LOCALES]);assert.equal(target.locales().length,16);
  for(const [index,locale] of LOCALES.entries()){
    target.chooseLocale(index+1);assert.equal(Locale.preference(),locale);assert.equal(Locale.current(),locale);assert.equal(target.vm.locale,locale);
    assert.equal(target.locales()[index+1].value,Policy.nativeName(locale));assert.equal(target.localeIndex,index+1);assert.equal(target.fallback,false);
  }
  assert.equal(state.preferenceWrites,15);assert.equal(state.appStorage.get('helpLocaleVersion'),15);
  for(const bad of ['en-US','FR',' pt ','constructor','__proto__','zh-Latn','', 'de-'+ 'a'.repeat(100)]){assert.equal(Locale.select(bad),false);assert.equal(Policy.preference(bad),'system');}
  assert.equal(state.preferenceWrites,15);
  target.chooseLocale(0);state.language='ar-SA';target.localeChanged();assert.equal(target.vm.locale,'en');assert.equal(target.fallback,true);assert.match(target.label('fallback'),/English/);
  state.language='fr-CA';target.localeChanged();assert.equal(target.vm.locale,'fr');assert.equal(target.fallback,false);
  assert.equal(state.deviceReads,0);assert.equal(state.appReads,0);assert.equal(state.themeReads,0);assert.equal(state.clipboardReads,0);assert.equal(state.copies.length,0);assert.equal(state.links.length,0);assert.equal(state.routes.length,0);
  target.aboutToDisappear();
 });
 await test('region variants cannot expand cache bounds; every locale returns detached articles and search results',()=>{
  const {Search,Policy}=harness();
  const terms=[['de','Wiederherstellung','backups'],['es','verificacion','accounts'],['fr','donnees','data'],['id','cadangan','backups'],['it','ripristino','backups'],['ja','診断','privacy'],['ko','클립보드','privacy'],['pt','recuperacao','backups'],['ru','напоминания','daily-note'],['th','คลิปบอร์ด','privacy'],['tr','sifre','accounts'],['vi','chan doan','privacy']];
  for(const [locale,query,id] of terms)assert(Search.search(query,locale).some(doc=>doc.id===id),locale+' '+query);
  for(const locale of LOCALES){
    for(let i=0;i<100;i++)Search.search('UIGF',locale+'-x-'+i);
    const direct=Search.documents(locale),fresh=Search.document('privacy',locale);direct[6].title='poison';direct[6].steps[0]='poison';direct.length=0;
    const found=Search.search('privacy',locale);found[0].steps.push('poison');
    assert.equal(Search.documents(locale).length,7);assert.equal(Search.document('privacy',locale).title,fresh.title);assert.equal(Search.document('privacy',locale).steps.length,4);
    assert.equal(Search.routeFor('privacy'),'');
  }
  for(let i=0;i<2000;i++)Search.documents('unknown-'+i);
  assert.equal(Search.indexes.size,15);assert.equal(Search.common.size,7);
  assert.deepEqual([...Search.indexes.keys()].sort(),[...LOCALES].sort());
  assert.equal(Policy.supported('en-'+ 'a'.repeat(100)),false);
 });
 await test('queries, article identities and privacy boundaries survive switching through all fifteen locales',async()=>{
  const {Model,state}=harness();const target=new Model();target.activate('en');target.setQuery('UIGF');target.select('import');
  for(const locale of LOCALES){
    target.setLocale(locale);assert.equal(target.query,'UIGF');assert.equal(target.selectedId,'import');assert.equal(target.selected().id,'import');assert.equal(target.documents.length,1);
    await target.generatePreview();assert(target.previewText().length>0);assert.equal(state.deviceReads,0);assert.equal(state.appReads,0);assert.equal(state.themeReads,0);assert.equal(state.copies.length,0);
    target.clearPreview();assert.equal(target.preview,undefined);
  }
  target.invalidate();assert.equal(target.preview,undefined);assert.equal(state.clipboardReads,0);assert.equal(state.links.length,0);
 });
 await test('pure source passes strict TypeScript with typed platform boundaries',strictTypes);
 await test('source boundaries preserve API24 native help without speculative features or automatic IO',()=>{
  const source=read('pages/HelpPage');assert.match(source,/Number\(area.width\) >= 840/);assert.match(source,/\.height\(44\)/);assert.match(source,/HoverEffect.Highlight/);
  assert.doesNotMatch(source,/PageBackdrop|WallpaperLayer|SupportService\.copyDiagnostics|openIssues|setInterval|http|#[0-9a-fA-F]{6}/);
  for(const name of ['service/DocumentationSearchService',...catalogNames,'model/DiagnosticPolicy'])assert.doesNotMatch(read(name),/from ['"].*(?:UserService|TokenVault|GachaRepo|network|pasteboard|deviceInfo)/);
  const support=read('service/SupportService');assert.doesNotMatch(support,/osFullName|versionCode|\bserial\b|TokenVault|UserService|getCurrentUid|getAllSync|getData\(/);
  assert.doesNotMatch(read('service/AppLocaleService'),/setSystemLanguage|setAppPreferredLanguage/);
  const catalog=catalogNames.map(read).join('\n');assert.doesNotMatch(catalog,/Ctrl\+Alt|ArkWeb|global shortcut|C#|DLL|pipelines/);
 });
})().catch(error=>{console.error(error);process.exitCode=1;});
