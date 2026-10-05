// Production cloud-session coordination with deterministic synthetic vault/network boundaries. No live credentials or HTTP.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const test=require('node:test'),ts=require(process.env.TYPESCRIPT_PATH||'../ci/node_modules/typescript');
const root=path.resolve(__dirname,'../entry/src/main/ets');
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
const flush=async()=>{for(let i=0;i<60;i++)await Promise.resolve();};
const copy=value=>JSON.parse(JSON.stringify(value));
function session(user='a@example.invalid',expired=false){return {userName:user,accessToken:'fixture-access-'+user,refreshToken:'fixture-refresh-'+user,expiresAt:Date.now()+(expired?1000:3600000)};}
const accepted=name=>({AccessToken:'fixture-new-access-'+name,RefreshToken:'fixture-new-refresh-'+name,ExpiresIn:3600});
function harness(initial=session()){
 const state={disk:copy(initial),loads:0,saves:0,clears:0,active:0,maxActive:0,log:[],requests:[],loadGate:undefined,saveGate:undefined,clearGate:undefined,encryptGate:undefined,requestHook:undefined,failClear:false};
 const vault={
  async load(){state.loads++;const snapshot=copy(state.disk);if(state.loadGate){const gate=state.loadGate;state.loadGate=undefined;await gate.promise;}return snapshot;},
  async save(value){state.saves++;state.active++;state.maxActive=Math.max(state.maxActive,state.active);const snapshot=copy(value);state.log.push('save-start');try{if(state.saveGate){const gate=state.saveGate;state.saveGate=undefined;await gate.promise;}state.disk=snapshot;state.log.push('save-end');}finally{state.active--; }},
  async clear(){state.clears++;state.active++;state.maxActive=Math.max(state.maxActive,state.active);state.log.push('clear-start');try{if(state.clearGate){const gate=state.clearGate;state.clearGate=undefined;await gate.promise;}if(state.failClear)throw Error('fixture vault unavailable');state.disk={userName:'',accessToken:'',refreshToken:'',expiresAt:0};state.log.push('clear-end');}finally{state.active--;}}
 };
 const client={deviceId:()=> 'fixture-device',async encrypt(value){if(state.encryptGate){const gate=state.encryptGate;state.encryptGate=undefined;await gate.promise;}return 'encrypted-fixture';},
  async request(endpoint,body='',token=''){const request={endpoint,body,token};state.requests.push(request);if(state.requestHook)return state.requestHook(request);if(endpoint.includes('RefreshToken'))return accepted('rotated');if(endpoint.includes('Login'))return accepted('login');return {Distribution:[{Pull:80,Count:3}]};}
 };
 const modules=new Map();
 function load(name){if(modules.has(name))return modules.get(name);const output=ts.transpileModule(fs.readFileSync(path.join(root,name+'.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});assert.equal(output.diagnostics.length,0,name);const module={exports:{}};
  vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`,{Error,Date})(id=>{
   if(id.endsWith('/HutaoCloudClient'))return {HutaoCloudClient:client};if(id.endsWith('/HutaoCloudVault'))return {HutaoCloudVault:vault};
   if(id.endsWith('/GachaRepo'))return {GachaRepo:{}};if(id.endsWith('/WikiMetaService'))return {WikiMetaService:{}};
   if(id.endsWith('/Constants'))return {RegionUtil:{isValidUid:()=>true}};
   assert.ok(id.startsWith('.'),id);return load(path.posix.normalize(path.posix.join(path.posix.dirname(name),id)));
  },module,module.exports);modules.set(name,module.exports);return module.exports;
 }
 const service=load('service/HutaoCloudService').HutaoCloudService.getInstance();return {state,service};
}
function strictCloudTypes(){
 const virtualRoot='/cloud-session-types',files=new Map(),put=(name,text)=>files.set(virtualRoot+'/'+name+'.ts',text);
 for(const name of ['service/HutaoCloudService','model/HutaoCloud','model/HutaoCloudGacha','model/GachaItem','model/GachaArchive'])put(name,fs.readFileSync(path.join(root,name+'.ets'),'utf8'));
 put('data/network/HutaoCloudClient',`export class HutaoCloudClient{static deviceId():string{return '';}static async encrypt(value:string):Promise<string>{return '';}static async request(path:string,body:string='',token:string=''):Promise<Object>{return {};}}`);
 put('data/local/HutaoCloudVault',`import {HutaoCloudSession} from '../../model/HutaoCloud';export class HutaoCloudVault{static async load():Promise<HutaoCloudSession>{return new HutaoCloudSession();}static async save(value:HutaoCloudSession):Promise<void>{}static async clear():Promise<void>{}}`);
 put('data/repo/GachaRepo',`import {GachaArchive} from '../../model/GachaArchive';import {GachaItem} from '../../model/GachaItem';export class GachaRepo{static async getAllArchives():Promise<GachaArchive[]>{return [];}static async getItemsByArchive(id:number):Promise<GachaItem[]>{return [];}static async getOrCreateArchive(uid:string):Promise<GachaArchive>{return new GachaArchive();}static async insertItems(items:GachaItem[]):Promise<number>{return 0;}}`);
 put('common/Constants',`export class RegionUtil{static isValidUid(uid:string):boolean{return true;}static regionOfUid(uid:string):string{return '';}}`);
 put('service/WikiMetaService',`export class WikiAvatarMeta{id=0;name='';quality=0;}export class WikiWeaponMeta{id=0;name='';rankLevel=0;}export class WikiMetaService{static async getAvatars():Promise<WikiAvatarMeta[]>{return [];}static async getWeapons():Promise<WikiWeaponMeta[]>{return [];}}`);
 const options={strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,skipLibCheck:true},host=ts.createCompilerHost(options),base={fileExists:host.fileExists,readFile:host.readFile,getSourceFile:host.getSourceFile,directoryExists:host.directoryExists};
 host.fileExists=file=>files.has(file)||base.fileExists(file);host.readFile=file=>files.get(file)??base.readFile(file);host.getSourceFile=(file,version,...rest)=>files.has(file)?ts.createSourceFile(file,files.get(file),version,true):base.getSourceFile(file,version,...rest);host.directoryExists=directory=>[...files.keys()].some(file=>file.startsWith(directory+'/'))||base.directoryExists(directory);
 const diagnostics=ts.getPreEmitDiagnostics(ts.createProgram([...files.keys()],options,host));assert.equal(diagnostics.length,0,diagnostics.map(value=>ts.flattenDiagnosticMessageText(value.messageText,'\n')).join('\n'));
}
(async()=>{
 await test('coalesced initialization cannot restore a session after local forget',async()=>{
  const {state,service}=harness();const gate=deferred();state.loadGate=gate;const a=service.initialize(),b=service.initialize();await flush();assert.equal(state.loads,1);
  const forget=service.forgetLocal();assert.equal(service.isLoggedIn(),false);gate.resolve();await Promise.all([a,b,forget]);assert.equal(service.isLoggedIn(),false);assert.equal(state.disk.refreshToken,'');await service.initialize();assert.equal(state.loads,1);
 });
 await test('forget invalidates immediately and its queued clear runs after a delayed save',async()=>{
  const {state,service}=harness();await service.initialize();const gate=deferred();state.saveGate=gate;const login=service.authenticate('b@example.invalid','fixture-password','','login');const rejected=assert.rejects(login,/状态已变化/);await flush();assert.equal(state.active,1);
  const forget=service.forgetLocal();assert.equal(service.isLoggedIn(),false);gate.resolve();await Promise.all([rejected,forget]);assert.equal(service.getUserName(),'');assert.equal(state.disk.refreshToken,'');assert.equal(state.maxActive,1);assert.equal(state.log.at(-1),'clear-end');
 });
 await test('a delayed clear cannot erase a newer login persisted behind it',async()=>{
  const {state,service}=harness();await service.initialize();const gate=deferred();state.clearGate=gate;const forget=service.forgetLocal();await flush();const login=service.authenticate('b@example.invalid','fixture-password','','login');await flush();assert.equal(state.maxActive,1);gate.resolve();await Promise.all([forget,login]);assert.equal(service.getUserName(),'b@example.invalid');assert.equal(state.disk.userName,'b@example.invalid');assert.equal(service.isLoggedIn(),true);assert.equal(state.maxActive,1);
 });
 await test('an old login response cannot overwrite a newer login identity',async()=>{
  const {state,service}=harness();await service.initialize();const old=deferred();let logins=0;state.requestHook=request=>request.endpoint.includes('/Login')?(++logins===1?old.promise:accepted('new')):{};
  const first=service.authenticate('old@example.invalid','fixture-password','','login');const rejected=assert.rejects(first,/状态已变化/);await flush();await service.authenticate('new@example.invalid','fixture-password','','login');old.resolve(accepted('old'));await rejected;assert.equal(service.getUserName(),'new@example.invalid');assert.equal(state.disk.userName,'new@example.invalid');assert.equal(state.saves,1);
 });
 await test('stale in-progress save repairs the last committed identity if a newer login fails',async()=>{
  const initial=session(),{state,service}=harness(initial);await service.initialize();const save=deferred();state.saveGate=save;let logins=0;state.requestHook=request=>{if(request.endpoint.includes('/Login')){if(++logins===2)throw Error('fixture login rejected');return accepted('old');}return {};};
  const old=service.authenticate('old@example.invalid','fixture-password','','login');const rejected=assert.rejects(old,/状态已变化/);await flush();await assert.rejects(service.authenticate('new@example.invalid','fixture-password','','login'),/login rejected/);save.resolve();await rejected;assert.equal(service.getUserName(),initial.userName);assert.deepEqual(state.disk,initial);assert.equal(state.maxActive,1);
 });
 await test('natural token refresh is coalesced, preserves identity revision and permits statistics',async()=>{
  const {state,service}=harness(session('a@example.invalid',true));await service.initialize();const revision=service.getSessionRevision(),gate=deferred();state.requestHook=request=>request.endpoint.includes('/RefreshToken')?gate.promise:{Distribution:[{Pull:80,Count:3}]};
  const a=service.statistics('weaponDistribution'),b=service.statistics('weaponDistribution');await flush();assert.equal(state.requests.filter(row=>row.endpoint.includes('/RefreshToken')).length,1);gate.resolve(accepted('rotated'));await Promise.all([a,b]);assert.equal(service.getSessionRevision(),revision);assert.equal(service.getUserName(),'a@example.invalid');assert.equal(state.saves,1);assert.equal(state.requests.filter(row=>row.endpoint.includes('/Distribution/')).length,2);
 });
 await test('a refresh response after forget cannot save tokens or dispatch its waiting statistics',async()=>{
  const {state,service}=harness(session('a@example.invalid',true));await service.initialize();const gate=deferred();state.requestHook=request=>request.endpoint.includes('/RefreshToken')?gate.promise:{};const pending=service.statistics('weaponDistribution');const rejected=assert.rejects(pending,/状态已变化/);await flush();await service.forgetLocal();gate.resolve(accepted('old'));await rejected;assert.equal(state.saves,0);assert.equal(state.disk.refreshToken,'');assert.equal(state.requests.filter(row=>row.endpoint.includes('/Distribution/')).length,0);
 });
 await test('statistics checks ownership both after token acquisition and after an already dispatched response',async()=>{
  const {state,service}=harness();await service.initialize();const token=deferred();const original=service.accessToken;service.accessToken=()=>token.promise;const pending=service.statistics('weaponDistribution');const rejected=assert.rejects(pending,/状态已变化/);await service.forgetLocal();token.resolve('fixture-old-token');await rejected;assert.equal(state.requests.length,0);service.accessToken=original;
  await service.authenticate('b@example.invalid','fixture-password','','login');const gate=deferred();state.requestHook=()=>gate.promise;const response=service.statistics('weaponDistribution');const late=assert.rejects(response,/状态已变化/);await flush();const count=state.requests.length;await service.forgetLocal();gate.resolve({Distribution:[{Pull:80,Count:3}]});await late;assert.equal(state.requests.length,count,'already-dispatched HTTP is not claimed cancelled or retried');
 });
 await test('late logout and unregister completions cannot clear a newer logged-in identity',async()=>{
  for(const mode of ['logout','unregister']){
   const {state,service}=harness();await service.initialize();const gate=deferred();state.requestHook=request=>request.endpoint.includes('/Login')?accepted('new'):gate.promise;
   const pending=mode==='logout'?service.logout():service.unregister('a@example.invalid','fixture-password','fixture-code');const rejected=assert.rejects(pending,/状态已变化/);await flush();await service.authenticate('new@example.invalid','fixture-password','','login');gate.resolve({});await rejected;assert.equal(service.isLoggedIn(),true);assert.equal(service.getUserName(),'new@example.invalid');assert.equal(state.disk.userName,'new@example.invalid');assert.equal(state.clears,0);
  }
 });
 await test('clear failure remains a logged-out error and does not poison later queued login',async()=>{
  const {state,service}=harness();await service.initialize();state.failClear=true;await assert.rejects(service.forgetLocal(),/vault unavailable/);assert.equal(service.isLoggedIn(),false);await service.initialize();assert.equal(service.isLoggedIn(),false);state.failClear=false;await service.authenticate('new@example.invalid','fixture-password','','login');assert.equal(service.getUserName(),'new@example.invalid');assert.equal(state.disk.userName,'new@example.invalid');
 });
 await test('an explicit login supersedes an older pending initialization without adopting its old identity',async()=>{
  const {state,service}=harness();const gate=deferred();state.loadGate=gate;const initial=service.initialize();await flush();const login=service.authenticate('new@example.invalid','fixture-password','','login');gate.resolve();await Promise.all([initial,login]);assert.equal(service.getUserName(),'new@example.invalid');assert.equal(state.disk.userName,'new@example.invalid');assert.equal(service.isLoggedIn(),true);
 });
 await test('a late email-identity response cannot overwrite a newer login or clear its tokens',async()=>{
  const {state,service}=harness();await service.initialize();const gate=deferred();state.requestHook=request=>request.endpoint.includes('ResetUsername')?gate.promise:accepted('new');const email=service.resetEmail('fixture-old-code','old-target@example.invalid','fixture-new-code');const rejected=assert.rejects(email,/状态已变化/);await flush();await service.authenticate('new@example.invalid','fixture-password','','login');gate.resolve(accepted('email'));await rejected;assert.equal(service.getUserName(),'new@example.invalid');assert.equal(state.disk.userName,'new@example.invalid');
 });
 await test('cloud session and wire-model graph passes strict host types with explicit external boundaries',strictCloudTypes);
 await test('identity cancellation errors contain no captured token, password or account string',async()=>{
  const {state,service}=harness();await service.initialize();const gate=deferred();state.encryptGate=gate;const pending=service.authenticate('private-user@example.invalid','private-fixture-password','','login');const rejection=assert.rejects(pending,error=>{assert.equal(error.message,'云登录状态已变化，请重试');return true;});await flush();await service.forgetLocal();gate.resolve();await rejection;assert.equal(state.requests.length,0);
 });
})().catch(error=>{console.error(error);process.exitCode=1;});
