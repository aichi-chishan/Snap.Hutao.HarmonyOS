// Production policy, transport and VM; HTTP/ability boundaries are counted doubles, never live downloads.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const os = require('node:os');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = name => fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
const deferred = () => { let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject}; };
const flush = async()=>{for(let i=0;i<30;i++)await Promise.resolve();};
function harness(){
 const state={requests:[],queue:[],links:[],linkGate:undefined,client:{name:'com.example.snaphutaoharmonyos',versionName:'1.21.0',versionCode:1002100},api:24,reads:0};
 const kits={
  '@kit.NetworkKit':{http:{RequestMethod:{GET:'GET'},HttpDataType:{STRING:'STRING'},createHttp:()=>{
   const handle={destroyed:0,destroy(){this.destroyed++;},async request(url,options){state.requests.push({url,options,handle});const next=state.queue.shift();if(next instanceof Error)throw next;if(next?.promise)return next.promise;return next||{responseCode:200,result:'[]'};}};return handle;
  }}},
  '@kit.AbilityKit':{bundleManager:{BundleFlag:{GET_BUNDLE_INFO_DEFAULT:0},getBundleInfoForSelfSync:()=>{state.reads++;return state.client;}}},
  '@kit.BasicServicesKit':{deviceInfo:{get sdkApiVersion(){return state.api;}}}
 };
 const cache=new Map();
 function load(name){
  if(kits[name])return kits[name];if(cache.has(name))return cache.get(name);if(name.startsWith('components/'))return {};
  let source=read(name);if(name==='pages/UpdatePage')source=source.slice(0,source.indexOf('  @Builder'))+'}';source=source.replace('export struct UpdatePage','export class UpdatePage');
  const out=ts.transpileModule(source,{reportDiagnostics:true,compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,experimentalDecorators:true}});assert.equal(out.diagnostics.length,0,name);
  const module={exports:{}};vm.runInNewContext(`(function(require,module,exports){${out.outputText}\n})`,{Observed:v=>v,Entry:v=>v,Component:v=>v,Prop:()=>{},State:()=>{},StorageProp:()=>()=>{}})(id=>load(id.startsWith('@')?id:path.posix.normalize(path.posix.join(path.posix.dirname(name),id))),module,module.exports);cache.set(name,module.exports);return module.exports;
 }
 const policy=load('model/AppUpdate');const service=load('service/AppUpdateService');
 return {...policy,...service,state,load,VM:load('viewmodel/UpdateViewModel').UpdateViewModel,context:{openLink:async url=>{state.links.push(url);if(state.linkGate)await state.linkGate.promise;}},page:()=>new (load('pages/UpdatePage').UpdatePage)()};
}
const row=(tag,extra={})=>({tag_name:tag,html_url:`https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/releases/tag/${encodeURIComponent(tag)}`,name:tag,body:'Release notes',draft:false,prerelease:false,assets:[],...extra});
const manifest=(tag,extra={})=>'<!-- hutao-harmony-update:v1\n'+JSON.stringify({schema:1,bundleName:'com.example.snaphutaoharmonyos',tagName:tag,versionName:tag,versionCode:1002200,minimumApi:24,channel:'stable',...extra})+'\n-->';
const response=rows=>({responseCode:200,result:JSON.stringify(rows)});
const compare=(h,rows,channel=h.UpdateChannel.Stable)=>h.AppUpdatePolicy.evaluate(h.AppUpdatePolicy.parsePage(JSON.stringify(rows)),h.AppUpdateService.readClient(),channel);
function strictTypes() {
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hutao-update-types-'));
 const names=['model/AppUpdate','service/AppUpdateService','viewmodel/UpdateViewModel'];
 for(const name of names){const filename=path.join(dir,name+'.ts');fs.mkdirSync(path.dirname(filename),{recursive:true});fs.writeFileSync(filename,read(name));}
 fs.writeFileSync(path.join(dir,'globals.d.ts'),`declare function Observed<T extends new (...args:never[])=>object>(value:T):T;
 declare module '@kit.AbilityKit' {export namespace common {interface UIAbilityContext {openLink(url:string):Promise<void>}};export namespace bundleManager {interface BundleInfo {name:string;versionName:string;versionCode:number};enum BundleFlag {GET_BUNDLE_INFO_DEFAULT};function getBundleInfoForSelfSync(flag:BundleFlag):BundleInfo}}
 declare module '@kit.BasicServicesKit' {export const deviceInfo:{sdkApiVersion:number};}
 declare module '@kit.NetworkKit' {export namespace http {interface HttpResponse {responseCode:number;result:string|Object|ArrayBuffer};interface HttpRequest {destroy():void;request(url:string,options:{method:RequestMethod;header:Record<string,string>;connectTimeout:number;readTimeout:number;expectDataType:HttpDataType;maxLimit:number;maxRedirects:number;usingCache:boolean}):Promise<HttpResponse>};enum RequestMethod {GET};enum HttpDataType {STRING};function createHttp():HttpRequest;}}`);
 const program=ts.createProgram([...names.map(name=>path.join(dir,name+'.ts')),path.join(dir,'globals.d.ts')],{strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,experimentalDecorators:true,skipLibCheck:true});
 const errors=ts.getPreEmitDiagnostics(program).filter(d=>d.category===ts.DiagnosticCategory.Error);
 assert.equal(errors.length,0,ts.formatDiagnosticsWithColorAndContext(errors,{getCurrentDirectory:()=>dir,getCanonicalFileName:x=>x,getNewLine:()=> '\n'}));
}
(async()=>{
 await test('model/service/viewmodel pass strict host type checking',strictTypes);
 await test('numeric version components, fourth component, leading v, padding and arbitrary precision',()=>{
  const {AppUpdatePolicy:P}=harness();
  for(const [a,b,n]of [['1.10','1.9',1],['v1.21.0','1.21',0],['1.21.0.1','1.21.0',1],['1.20.99','1.21.0',-1],['100000000000000000001','100000000000000000000',1],['V2.0+build.2','2.0+build.1',0]])assert.equal(P.compare(a,b),n,`${a}/${b}`);
  for(const invalid of ['', 'latest','1.02.0','1.0.0.0.0',' 1.0','1.0 ','1.0-01','1.0+','1.0-','1.0/evil','1.0\n'])assert.equal(P.compare(invalid,'1.0'),undefined,invalid);
 });
 await test('SemVer prerelease precedence follows numeric and lexical identifiers',()=>{
  const {AppUpdatePolicy:P}=harness();const ordered=['1.0.0-alpha','1.0.0-alpha.1','1.0.0-alpha.beta','1.0.0-beta','1.0.0-beta.2','1.0.0-beta.11','1.0.0-rc.1','1.0.0'];
  for(let i=1;i<ordered.length;i++)assert.equal(P.compare(ordered[i-1],ordered[i]),-1);
 });
 await test('equal/older/newer and old-branch releases compare by version, not creation order',()=>{
  const h=harness();assert.equal(compare(h,[row('v1.21.0')]).status,'equal');assert.equal(compare(h,[row('v1.20.4')]).status,'local-newer');assert.equal(compare(h,[row('v1.22.0')]).status,'newer');
  const result=compare(h,[row('v1.20.9',{published_at:'2099-01-01'}),row('v1.22.0',{published_at:'2026-01-01'})]);assert.equal(result.release.tag,'v1.22.0');
 });
 await test('stable excludes prereleases from GitHub flags or tags; preview includes stable upgrades',()=>{
  const h=harness();const releases=[row('v1.22.0-beta.1'),row('v1.23.0',{prerelease:true}),row('v1.21.0')];
  assert.equal(compare(h,releases).status,'equal');assert.equal(compare(h,releases,h.UpdateChannel.Preview).release.tag,'v1.23.0');
  assert.equal(compare(h,[row('v1.22.0-beta')]).status,'no-channel-release');
  h.state.client.versionName='1.22.0-rc.1';assert.equal(compare(h,[row('v1.22.0')]).status,'newer');
 });
 await test('empty, draft, unknown and incomplete listings never falsely say current/newer',()=>{
  const h=harness();assert.equal(compare(h,[]).status,'no-release');assert.equal(compare(h,[row('v99.0',{draft:true})]).status,'no-release');
  assert.equal(compare(h,[row('nightly')]).status,'unknown');assert.equal(compare(h,[row('nightly'),row('v1.21.0')]).status,'unknown');
  h.state.client.versionName='development';assert.equal(compare(h,[row('v1.22.0')]).status,'unknown');
  const catalog=h.AppUpdatePolicy.parsePage(JSON.stringify([row('v1.20.0')]));catalog.complete=false;assert.equal(h.AppUpdatePolicy.evaluate(catalog,h.AppUpdateService.readClient(),h.UpdateChannel.Stable).status,'unknown');
 });
 await test('request and release URLs are pinned to exact project with no credentials, redirect URLs or arbitrary query',()=>{
  const {AppUpdatePolicy:P}=harness();assert(P.allowsRequest(P.requestUrl(1)));assert.equal(P.requestUrl(0),'');assert.equal(P.requestUrl(4),'');
  for(const bad of [P.requestUrl(1)+'&token=x',P.requestUrl(1).replace('api.github.com','api.github.com.evil'),P.requestUrl(1).replace('/aichi-chishan/','/attacker/'),'https://user:pass@api.github.com/repos/aichi-chishan/Snap.Hutao.HarmonyOS/releases'])assert.equal(P.allowsRequest(bad),false);
  for(const bad of ['http://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/releases/tag/v1','https://github.com.evil/aichi-chishan/Snap.Hutao.HarmonyOS/releases/tag/v1',P.releaseUrl('v1')+'?next=evil','https://github.com/attacker/repo/releases/tag/v1','javascript:alert(1)'])assert.equal(P.allowsDetails(bad,'v1'),false);
  assert.equal(P.parsePage(JSON.stringify([row('v9',{html_url:'https://evil.test/v9'})])).invalid,1);
 });
 await test('metadata binds schema/tag/version/bundle/channel and requires integer code/minimum API',()=>{
  const h=harness();const good=compare(h,[row('v1.22.0',{body:manifest('v1.22.0')})]);assert.equal(good.release.manifestState,'project-metadata');assert.equal(good.apiState,'api-requirement-met');assert.equal(good.installable,false);
  for(const change of [{schema:2},{bundleName:'other.app'},{tagName:'v1.23.0'},{versionName:'9.0.0'},{channel:'preview'},{versionCode:1.1},{versionCode:0},{minimumApi:'24'},{minimumApi:-1}]){
   const result=compare(h,[row('v1.22.0',{body:manifest('v1.22.0',change)})]);assert.equal(result.release.manifestState,'invalid');assert.equal(result.apiState,'unknown');assert.equal(result.installable,false);
  }
  const duplicate=compare(h,[row('v1.22.0',{body:manifest('v1.22.0')+manifest('v1.22.0')})]);assert.equal(duplicate.release.manifestState,'invalid');
 });
 await test('minimum API gate, missing metadata, bundle mismatch, and claimed signatures never grant installability',()=>{
  const h=harness();const rows=[row('v1.22.0',{body:manifest('v1.22.0',{minimumApi:26,signed:true,signatureVerified:true})})];
  const result=compare(h,rows);assert.equal(result.status,'newer');assert.equal(result.apiState,'requires-newer-api');assert.equal(result.installable,false);
  assert.equal(compare(h,[row('v1.22.0')]).apiState,'unknown');h.state.client.name='other.app';assert.equal(compare(h,rows).apiState,'unknown');
 });
 await test('source-bound versionCode handles rebuilds but conflicts never become safe updates',()=>{
  const h=harness();assert.equal(compare(h,[row('v1.21.0',{body:manifest('v1.21.0',{versionCode:1002101})})]).status,'newer');
  const conflict=compare(h,[row('v1.22.0',{body:manifest('v1.22.0',{versionCode:1002000})})]);assert.equal(conflict.status,'unknown');assert(conflict.metadataConflict);
 });
 await test('only recognizable same-release Harmony assets are counted, with no implied signature trust',()=>{
  const h=harness();const asset=name=>({name,size:100,browser_download_url:`https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/releases/download/v1.22.0/${name}`});
  const result=compare(h,[row('v1.22.0',{assets:[asset('entry.hap'),asset('bundle.app'),asset('install.exe'),asset('source.zip'),{...asset('malicious.hap'),browser_download_url:'https://evil.test/evil.hap'}]})]);assert.equal(result.release.harmonyAssetCount,2);assert.equal(result.installable,false);assert.equal(compare(h,[row('v1.22.0')]).release.harmonyAssetCount,0);
 });
 await test('public metadata transport has bounded GET requests with no auth/cookies and no redirects',async()=>{
  const h=harness();h.state.queue.push(response([row('v1.22.0')]));const result=await new h.AppUpdateRequest().run(h.AppUpdateService.readClient(),h.UpdateChannel.Stable);assert.equal(result.status,'newer');assert.equal(h.state.requests.length,1);
  const {options,handle,url}=h.state.requests[0];assert(h.AppUpdatePolicy.allowsRequest(url));assert.equal(options.method,'GET');assert.equal(options.maxRedirects,0);assert.equal(options.usingCache,false);assert.equal(options.maxLimit,2097152);assert.equal(handle.destroyed,1);assert(!Object.keys(options.header).some(k=>/cookie|authorization/i.test(k)));
 });
 await test('404 unavailable differs from empty release, while rate/network/invalid responses stay explicit',async()=>{
  for(const [reply,status] of [[{responseCode:404,result:'{}'},'unavailable'],[{responseCode:403,result:'{}'},'rate-limited'],[{responseCode:429,result:'{}'},'rate-limited'],[{responseCode:302,result:''},'invalid-response'],[{responseCode:200,result:'{}'},'invalid-response'],[{responseCode:200,result:'not json'},'invalid-response'],[new Error('secret detail'), 'network-error'],[response([]),'no-release']]){
   const h=harness();h.state.queue.push(reply);const result=await new h.AppUpdateRequest().run(h.AppUpdateService.readClient(),h.UpdateChannel.Stable);assert.equal(result.status,status);assert.equal(h.state.requests[0].handle.destroyed,1);
  }
 });
 await test('pagination is bounded to generated same-project URLs and reports incompleteness',async()=>{
  const h=harness();for(let i=0;i<3;i++)h.state.queue.push(response(Array.from({length:100},()=>row('v1.21.0'))));
  const result=await new h.AppUpdateRequest().run(h.AppUpdateService.readClient(),h.UpdateChannel.Stable);assert.equal(result.status,'unknown');assert.equal(result.complete,false);assert.equal(h.state.requests.length,3);assert(h.state.requests.every(r=>h.AppUpdatePolicy.allowsRequest(r.url)&&r.handle.destroyed===1));
 });
 await test('request cancel destroys once and prevents late results or follow-on pagination',async()=>{
  const h=harness(),gate=deferred(),request=new h.AppUpdateRequest();h.state.queue.push(gate);const pending=request.run(h.AppUpdateService.readClient(),h.UpdateChannel.Stable);request.cancel();request.cancel();gate.resolve(response(Array.from({length:100},()=>row('v9.0'))));assert.equal((await pending).status,'cancelled');assert.equal(h.state.requests.length,1);assert.equal(h.state.requests[0].handle.destroyed,1);assert.equal((await request.run(h.AppUpdateService.readClient(),h.UpdateChannel.Stable)).status,'cancelled');
 });
 await test('view lifecycle, repeated check, channel changes, late success and old finally preserve newer ownership',async()=>{
  const h=harness(),model=new h.VM();await model.check();assert.equal(h.state.requests.length,0);model.activate();assert.equal(h.state.requests.length,0);
  const old=deferred(),fresh=deferred();h.state.queue.push(old,fresh);const first=model.check();const repeated=model.check();await repeated;assert.equal(h.state.requests.length,1);
  model.setChannel(h.UpdateChannel.Preview);const second=model.check();assert.equal(h.state.requests.length,2);old.resolve(response([row('v99.0')]));await first;assert.equal(model.busy,true);assert.equal(model.result.status,'checking');fresh.resolve(response([row('v1.22.0-beta')]));await second;assert.equal(model.result.release.tag,'v1.22.0-beta');assert.equal(model.busy,false);
  const late=deferred();h.state.queue.push(late);const pending=model.check();model.invalidate();model.activate();late.reject(new Error('old'));await pending;assert.equal(model.result.status,'cancelled');assert.equal(model.busy,false);assert.equal(model.openFailed,false);
 });
 await test('link opening is explicit, verified, duplicate-suppressed and stale errors cannot reach a new page context',async()=>{
  const h=harness(),model=new h.VM();model.activate();h.state.queue.push(response([row('v1.22.0')]));await model.check();assert.equal(h.state.links.length,0);
  h.state.linkGate=deferred();const first=model.open(h.context);await model.open(h.context);assert.equal(h.state.links.length,1);model.invalidate();model.activate();assert.equal(model.opening,true);await model.open(h.context);assert.equal(h.state.links.length,1);h.state.linkGate.reject(new Error('old'));await first;assert.equal(model.openFailed,false);assert.equal(model.opening,false);
  await assert.rejects(h.AppUpdateService.openDetails(h.context,'https://evil.test','v1.22.0'));assert.equal(h.state.links.length,1);
 });
 await test('returning with changed app/API context clears prior comparison',async()=>{
  const h=harness(),model=new h.VM();model.activate();h.state.queue.push(response([row('v1.22.0')]));await model.check();assert.equal(model.result.status,'newer');model.invalidate();h.state.api=26;model.activate();assert.equal(model.result.status,'idle');assert.equal(model.client.api,26);
 });
 await test('native page uses lifecycle invalidation, component-width breakpoint and only manual metadata actions',async()=>{
  const h=harness(),page=h.page();page.aboutToAppear();page.onPageShow();assert.equal(h.state.reads,1);assert.equal(h.state.requests.length,0);
  const gate=deferred();h.state.queue.push(gate);const pending=page.vm.check();page.onPageHide();page.aboutToDisappear();gate.resolve(response([row('v99.0')]));await pending;assert.equal(page.vm.result.status,'cancelled');assert.equal(h.state.requests[0].handle.destroyed,1);
  const source=read('pages/UpdatePage');assert.match(source,/Number\(area.width\) >= 840/);assert(!/installBundle|startAbility|request\.agent|browser_download_url/.test(source));assert.match(source,/hoverEffect/);
 });
 console.log('PASS: native app update policy, transport, lifecycle and trust boundaries');
})().catch(error=>{console.error(error);process.exitCode=1;});
