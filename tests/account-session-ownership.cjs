// Deterministic production UserService/UserViewModel tests. No live credentials, OS services, or HTTP.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const deferred = () => { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return { promise, resolve, reject }; };
const flush = async () => { for (let i=0;i<100;i++) await Promise.resolve(); };
const accepted = data => ({ success:true, retcode:0, data, message:'' });
function harness() {
  const state = { prefsId:0, prefsUid:'', cookie:'', cookieRegion:false, rows:new Map(), requests:[], logs:[], app:new Map(), gates:new Map(), calls:[], activeWrites:0, maxWrites:0, fail:undefined, network:undefined, nextId:10 };
  const cache = new Map();
  const gate = async (kind,id) => { const key=kind+':'+id; const pending=state.gates.get(key); if(pending){state.gates.delete(key);await pending.promise;} };
  const read = id => { const user=state.rows.get(id); return user ? copy(user) : undefined; };
  const write = async (kind,id,operation) => {
    state.activeWrites++; state.maxWrites=Math.max(state.maxWrites,state.activeWrites);state.calls.push(kind+':'+id);
    try { await gate(kind,id); if(state.fail===kind){state.fail=undefined;throw Error('fixture '+kind+' failed');}operation(); } finally {state.activeWrites--;}
  };
  const repo = {
    async getUserById(id) { const snapshot=read(id); await gate('read',id);return snapshot; },
    async getCurrentUser(){const id=state.prefsId,snapshot=read(id); await gate('restore',id);return snapshot;},
    async getAllUsers(){const users=[...state.rows.keys()].map(read);await gate('all',0);return users;},
    async getRolesByUserId(id){const roles=read(id)?.roles||[];await gate('roles',id);return roles;},
    async insertUser(user){const id=state.nextId++;await write('insert',id,()=>{user.id=id;state.rows.set(id,copy(user));});return id;},
    async updateUser(user){const snapshot=copy(user);await write('update',user.id,()=>{const old=state.rows.get(user.id);if(old){snapshot.roles=old.roles;snapshot.applyCookie(old.fullCookie());state.rows.set(user.id,snapshot);}});},
    async upsertRoles(id,roles){const snapshot=roles.map(copyRole);await write('upsert',id,()=>{const user=state.rows.get(id);if(user)user.roles=snapshot;});},
    async saveCookieFor(id,cookie){await write('cookie',id,()=>{const user=state.rows.get(id);if(user)user.applyCookie(cookie);});},
    async loadCookieFor(id){await gate('vaultRead',id);return state.rows.get(id)?.fullCookie()||'';},
    async selectUser(id){await write('select',id,()=>{for(const user of state.rows.values())user.isSelected=user.id===id;state.prefsId=id;});},
    async deleteUser(id){await write('delete',id,()=>{state.rows.delete(id);if(state.prefsId===id){state.prefsId=0;state.prefsUid='';}});},
    async setDefaultUid(){throw Error('UserService must not use the global-UID-writing repository helper');},
  };
  const client = {
    setCookie(cookie,region=false){state.cookie=cookie;state.cookieRegion=region;},
    async get(url,headers){state.requests.push({url,headers});if(state.network)return state.network(url,headers);if(url.includes('getCookieAccountInfo'))return accepted({uid:'11',cookie_token:'fixture-rotated'});if(url.includes('getLToken'))return accepted({ltoken:'fixture-ltoken-rotated'});if(url.includes('getUserFullInfo'))return accepted({user_info:{nickname:'fixture-name',avatar_url:'https://example.invalid/avatar'}});return accepted({list:[]});},
    async postJson(url,body,headers){return client.get(url,headers);},
  };
  const prefs = {getCurrentUserId:()=>state.prefsId,setCurrentUserId:id=>{state.prefsId=id;},getCurrentUid:()=>state.prefsUid,setCurrentUid:uid=>{state.prefsUid=uid;},getDeviceFp:()=> 'fixture-fp',getDeviceFpTime:()=>Date.now(),getDeviceId:()=> 'fixture-device',setDeviceFp(){} };
  function load(name){
    if(cache.has(name))return cache.get(name);
    const source=fs.readFileSync(path.join(root,name+'.ets'),'utf8');
    const output=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true},reportDiagnostics:true});assert.equal(output.diagnostics.length,0,name);
    const module={exports:{}};
    const req=id=>{
      if(id.endsWith('/UserRepo'))return {UserRepo:repo};
      if(id.endsWith('/ApiClient'))return {ApiClient:{getInstance:()=>client}};
      if(id.endsWith('/PreferencesStore'))return {PreferencesStore:prefs};
      if(id.endsWith('/DailyNoteReminderService'))return {DailyNoteReminderService:{cancelUser:async id=>{await gate('reminder',id);}}};
      if(id.endsWith('/Logger'))return {Logger:{warn:(tag,message)=>state.logs.push(message),info:(tag,message)=>state.logs.push(message)}};
      if(id.endsWith('/DeviceFpApi'))return {DeviceFpApi:{fetchFingerprint:async()=> 'fixture-fp'}};
      if(id.endsWith('/DsSigner'))return {DsSigner:{nowTimestamp:()=>1,randomLowerAlphaNumeric:()=> 'fixture',signGen2:async()=> 'fixture-ds'}};
      if(id.endsWith('/HoyolabClient'))return {HoyolabClient:{passportHeaders:()=>({}),merge:(a,b)=>({...a,...b}),getBaseHeaders:()=>({}),getActionTicket:async()=>accepted({ticket:'fixture-ticket'}),getUserGameRoles:async()=>client.get('fixture-roles',{})}};
      assert.ok(id.startsWith('.'),id);return load(path.posix.normalize(path.posix.join(path.posix.dirname(name),id)));
    };
    vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`,{Error,Date,Observed:value=>value,AppStorage:{setOrCreate:(key,value)=>state.app.set(key,value)}})(req,module,module.exports);
    cache.set(name,module.exports);return module.exports;
  }
  const {User}=load('model/User'),{UserGameRole}=load('model/UserGameRole');
  function copyRole(role){return Object.assign(new UserGameRole(),role);}
  function copy(user){const result=user.clone();result.roles=user.roles.map(copyRole);return result;}
  function user(id,uid='10000000'+id){const value=new User();value.id=id;value.aid='1'+id;value.applyCookie(`account_id=1${id}; cookie_token=fixture-cookie-${id}; ltuid=1${id}; ltoken=fixture-ltoken-${id}; stuid=1${id}; stoken=fixture-stoken-${id}; mid=fixture-mid-${id}`);value.displayName='fixture-'+id;value.avatar='fixture-avatar';value.roles=[UserGameRole.of(uid,'cn_gf01','fixture-role',60)];value.roles[0].isDefault=true;state.rows.set(id,copy(value));return value;}
  const service=load('service/UserService').UserService.getInstance();
  const seed=async(id=1)=>{if(!state.rows.has(id))user(id);state.prefsId=id;await service.reloadLocalSession();return service.getCurrentUser();};
  return {state,service,repo,client,user,seed,load,copy,gate:(kind,id)=>{const value=deferred();state.gates.set(kind+':'+id,value);return value;}};
}
function strictAccountTypes() {
  const virtualRoot='/account-session-types', files=new Map(), put=(name,text)=>files.set(virtualRoot+'/'+name+'.ts',text);
  for(const name of ['service/UserService','viewmodel/UserViewModel','model/User','model/UserGameRole','model/ApiResponse','common/Constants'])put(name,fs.readFileSync(path.join(root,name+'.ets'),'utf8'));
  put('globals',`declare function Observed<T extends Function>(value:T):T; declare class AppStorage { static setOrCreate<T>(key:string,value:T):void; }`);
  put('service/DailyNoteReminderService',`export class DailyNoteReminderService {static async cancelUser(id:number):Promise<void>{}}`);
  put('data/repo/UserRepo',`import {User} from '../../model/User';import {UserGameRole} from '../../model/UserGameRole';export class UserRepo {static async getCurrentUser():Promise<User|undefined>{return undefined;}static async getUserById(id:number):Promise<User|undefined>{return undefined;}static async getAllUsers():Promise<User[]>{return [];}static async getRolesByUserId(id:number):Promise<UserGameRole[]>{return [];}static async selectUser(id:number):Promise<void>{}static async insertUser(user:User):Promise<number>{return 0;}static async updateUser(user:User):Promise<void>{}static async deleteUser(id:number):Promise<void>{}static async upsertRoles(id:number,roles:UserGameRole[]):Promise<void>{}static async saveCookieFor(id:number,cookie:string):Promise<void>{}static async loadCookieFor(id:number):Promise<string>{return '';}}`);
  put('data/network/ApiClient',`import {ApiResponse} from '../../model/ApiResponse';export class ApiClient {static getInstance():ApiClient{return new ApiClient();}setCookie(cookie:string,oversea:boolean=false):void{}async get(url:string,headers:Record<string,string>):Promise<ApiResponse>{return new ApiResponse();}async postJson(url:string,body:string,headers:Record<string,string>):Promise<ApiResponse>{return new ApiResponse();}}`);
  put('data/network/HoyolabClient',`import {ApiResponse} from '../../model/ApiResponse';export class HoyolabClient {static passportHeaders():Record<string,string>{return {};}static merge(a:Record<string,string>,b:Record<string,string>):Record<string,string>{return {};}static getBaseHeaders(region:string):Record<string,string>{return {};}static async getActionTicket(cookie:string,token:string,uid:string):Promise<ApiResponse>{return new ApiResponse();}static async getUserGameRoles(ticket:string):Promise<ApiResponse>{return new ApiResponse();}}`);
  put('data/prefs/PreferencesStore',`export class PreferencesStore {static setCurrentUserId(id:number):void{}static setCurrentUid(uid:string):void{}static getDeviceFp():string{return '';}static getDeviceFpTime():number{return 0;}static getDeviceId():string{return '';}static setDeviceFp(fp:string):void{}}`);
  put('data/network/DsSigner',`export class DsSigner {static nowTimestamp():number{return 0;}static randomLowerAlphaNumeric():string{return '';}static async signGen2(salt:string,time:number,random:string,body:string,query:string):Promise<string>{return '';}}`);
  put('data/network/DeviceFpApi',`export class DeviceFpApi {static async fetchFingerprint(id:string,existing:string):Promise<string>{return '';}}`);
  put('common/Logger',`export class Logger {static info(tag:string,message:string):void{}static warn(tag:string,message:string):void{}}`);
  const options={strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,experimentalDecorators:true,skipLibCheck:true},host=ts.createCompilerHost(options),base={fileExists:host.fileExists,readFile:host.readFile,getSourceFile:host.getSourceFile,directoryExists:host.directoryExists};
  host.fileExists=file=>files.has(file)||base.fileExists(file);host.readFile=file=>files.get(file)??base.readFile(file);host.getSourceFile=(file,version,...rest)=>files.has(file)?ts.createSourceFile(file,files.get(file),version,true):base.getSourceFile(file,version,...rest);host.directoryExists=directory=>[...files.keys()].some(file=>file.startsWith(directory+'/'))||base.directoryExists(directory);
  const diagnostics=ts.getPreEmitDiagnostics(ts.createProgram([...files.keys()],options,host));assert.equal(diagnostics.length,0,diagnostics.map(value=>ts.flattenDiagnosticMessageText(value.messageText,'\n')).join('\n'));
}
const selected = (h,id,uid) => {assert.equal(h.service.getCurrentUser()?.id,id||undefined);assert.equal(h.state.prefsId,id);assert.equal(h.state.app.get('currentUserId'),id);if(uid!==undefined){assert.equal(h.state.prefsUid,uid);assert.equal(h.state.app.get('currentUid'),uid);}assert.equal(h.state.cookie,id?h.service.getCurrentUser().fullCookie():'');};
(async()=>{
 await test('out-of-order switches publish only latest intent and revision changes before awaits',async()=>{
  const h=harness();await h.seed();h.user(2);h.user(3);const oldRevision=h.service.sessionRevision(),gate=h.gate('read',2);const first=h.service.switchUser(2);const rejected=assert.rejects(first,/状态已变化/);assert.ok(h.service.sessionRevision()>oldRevision);assert.equal(h.service.getCurrentUser(),undefined);await flush();await h.service.switchUser(3);gate.resolve();await rejected;selected(h,3,'100000003');
 });
 await test('stale in-flight select repairs the prior session when a newer switch fails',async()=>{
  const h=harness();await h.seed();h.user(2);const gate=h.gate('select',2),first=h.service.switchUser(2),rejected=assert.rejects(first,/状态已变化/);await flush();const failed=h.service.switchUser(99),failedResult=assert.rejects(failed,/不存在/);gate.resolve();await Promise.all([rejected,failedResult]);selected(h,1,'100000001');assert.equal(h.state.maxWrites,1);assert.equal(h.state.rows.get(1).isSelected,true);assert.equal(h.state.rows.get(2).isSelected,false);
 });
 await test('logout and delete during restore cannot resurrect saved identity or cookie',async()=>{
  for(const mode of ['logout','delete']){const h=harness();h.user(1);h.state.prefsId=1;const gate=h.gate('restore',1),restore=h.service.restoreSession();await flush();if(mode==='logout')await h.service.logout();else await h.service.deleteUser(1);gate.resolve();await restore;selected(h,0,'');assert.equal(h.state.rows.has(1),mode==='logout');}
 });
 await test('two logins finishing out of order cannot select or persist the older identity',async()=>{
  const h=harness();await h.seed();const gate=deferred();let count=0;h.state.network=async url=>{if(url==='fixture-roles'){if(++count===1)return gate.promise;return accepted({list:[]});}return accepted({});};
  const first=h.service.loginWithCookie('stuid=77; stoken=fixture-old; mid=fixture-old-mid','old','avatar'),rejected=assert.rejects(first,/状态已变化/);await flush();const latest=await h.service.loginWithCookie('stuid=88; stoken=fixture-new; mid=fixture-new-mid','new','avatar');gate.resolve(accepted({list:[]}));await rejected;selected(h,latest.id,'');assert.equal([...h.state.rows.values()].some(user=>user.mid==='fixture-old-mid'),false);
 });
 await test('same-ID login replacement fences token callback without mutating original object',async()=>{
  const h=harness(),original=await h.seed(),originalCookie=original.fullCookie(),gate=deferred();h.state.network=async url=>url.includes('getCookieAccountInfo')?gate.promise:accepted({list:[]});const first=h.service.refreshCookieTokenForced(original),rejected=assert.rejects(first,/状态已变化/);await flush();const replacement=await h.service.loginWithCookie(original.fullCookie(),'replacement','avatar');assert.equal(replacement.id,original.id);assert.notEqual(replacement,original);gate.resolve(accepted({uid:'11',cookie_token:'fixture-late'}));await rejected;assert.equal(original.fullCookie(),originalCookie);selected(h,1,'');assert.ok(!h.state.cookie.includes('fixture-late'));
 });
 await test('token completion after switch-away-and-back rejects even if same User object is restored',async()=>{
  for(const method of ['refreshCookieTokenForced','completeTokenChainPublic']){const h=harness(),original=await h.seed();h.user(2);if(method==='completeTokenChainPublic')original.cookieToken='';const before=original.fullCookie(),gate=deferred();h.state.network=async url=>url.includes('getCookieAccountInfo')?gate.promise:accepted({ltoken:'fixture-new-ltoken'});const pending=h.service[method](original),rejected=assert.rejects(pending,/状态已变化/);await flush();await h.service.switchUser(2);await h.service.switchUser(1);h.service.currentUser=original;gate.resolve(accepted({uid:'11',cookie_token:'fixture-late'}));await rejected;assert.equal(original.fullCookie(),before);assert.ok(!h.state.cookie.includes('fixture-late'));}
 });
 await test('in-flight token vault save rolls back before a new switch reads the same account',async()=>{
  const h=harness(),original=await h.seed(),before=original.fullCookie(),gate=h.gate('cookie',1);const pending=h.service.refreshCookieTokenForced(original),rejected=assert.rejects(pending,/状态已变化/);await flush();const latest=h.service.switchUser(1);gate.resolve();await Promise.all([rejected,latest]);selected(h,1,'100000001');assert.equal(h.state.cookie,before);assert.equal(h.state.maxWrites,1);
 });
 await test('a delayed role refresh cannot overwrite account or default UID after selection changes',async()=>{
  const h=harness();await h.seed();h.user(2);const gate=deferred();h.state.network=()=>gate.promise;const pending=h.service.refreshRolesOfCurrent(),rejected=assert.rejects(pending,/状态已变化/);await flush();await h.service.switchUser(2);gate.resolve(accepted({list:[{game_uid:'100000009',region:'cn_gf01',nickname:'late',level:1}]}));await rejected;selected(h,2,'100000002');assert.equal(h.state.rows.get(1).roles[0].gameUid,'100000001');
 });
 await test('default UID for another account never contaminates current session or preferences',async()=>{
  const h=harness();await h.seed();const other=h.user(2);other.roles.push(Object.assign(other.roles[0].constructor.of('100000009','cn_gf01','other',60),{isDefault:false}));h.state.rows.set(2,h.copy(other));const before=h.service.sessionRevision();await h.service.setDefaultUid(2,'100000009');assert.ok(h.service.sessionRevision()>before);selected(h,1,'100000001');assert.equal(h.state.rows.get(2).roles.find(role=>role.isDefault).gameUid,'100000009');await assert.rejects(h.service.setDefaultUid(1,'100000099'),/未绑定/);selected(h,1,'100000001');
 });
 await test('stale default-UID upsert rolls back before a same-account switch reads roles',async()=>{
  const h=harness();await h.seed();const row=h.state.rows.get(1);row.roles.push(row.roles[0].constructor.of('100000009','cn_gf01','other',60));const gate=h.gate('upsert',1),pending=h.service.setDefaultUid(1,'100000009'),rejected=assert.rejects(pending,/状态已变化/);await flush();const switchBack=h.service.switchUser(1);gate.resolve();await Promise.all([rejected,switchBack]);selected(h,1,'100000001');
 });
 await test('failed background fence preserves session and aborts logout, deletion and backup writes',async()=>{
  const h=harness(),owner=await h.seed();const calls=h.state.calls.length;const reasons=[];h.service.setSessionInvalidationHook(async reason=>{reasons.push(reason);return false;});for(const action of [()=>h.service.logout(),()=>h.service.deleteUser(1),()=>h.service.beginLocalSessionReplacement()]){const revision=h.service.sessionRevision();await assert.rejects(action(),/后台任务/);assert.ok(h.service.sessionRevision()>revision);assert.equal(h.service.getCurrentUser(),owner);selected(h,1,'100000001');}assert.equal(h.state.calls.length,calls);assert.deepEqual(reasons,['logout','delete','localReplacement']);
 });
 await test('backup barrier drains stale vault writes, blocks new work, and reloads same-ID replacement locally',async()=>{
  const h=harness(),owner=await h.seed(),gate=h.gate('cookie',1);const pending=h.service.refreshCookieTokenForced(owner),rejected=assert.rejects(pending,/状态已变化/);await flush();const barrier=h.service.beginLocalSessionReplacement();let completed=false;barrier.then(()=>{completed=true;});await flush();assert.equal(completed,false);gate.resolve();const revision=await barrier;await rejected;await assert.rejects(h.service.switchUser(1),/还原正在进行/);await assert.rejects(h.service.completeTokenChainPublic(owner),/正在切换/);const newUser=h.user(1,'100000009');newUser.mid='fixture-restored';h.state.rows.set(1,h.copy(newUser));h.state.prefsId=1;const requests=h.state.requests.length;await h.service.reloadLocalSession();selected(h,1,'100000009');assert.notEqual(h.service.getCurrentUser(),owner);assert.equal(h.state.requests.length,requests);h.service.cancelLocalSessionReplacement(revision);selected(h,1,'100000009');
 });
 await test('backup rollback cancellation and repeated logout/delete remain bounded and recoverable',async()=>{
  const h=harness(),owner=await h.seed(),revision=await h.service.beginLocalSessionReplacement();h.service.cancelLocalSessionReplacement(revision);assert.equal(h.service.getCurrentUser(),owner);await h.service.logout();await h.service.logout();await h.service.deleteUser(1);await h.service.deleteUser(1);selected(h,0,'');await h.service.loginWithCookie('stuid=99; stoken=fixture-stoken','new','avatar');assert.ok(h.service.getCurrentUser());
 });
 await test('failed partial login persistence rolls back credentials and preserves last committed owner',async()=>{
  const h=harness(),owner=await h.seed(),before=owner.fullCookie();h.state.fail='update';await assert.rejects(h.service.loginWithCookie(before.replace('fixture-cookie-1','fixture-replacement'),'new','avatar'),/fixture update failed/);assert.equal(h.service.getCurrentUser(),owner);selected(h,1,'100000001');assert.equal(h.state.rows.get(1).fullCookie(),before);await h.service.switchUser(1);selected(h,1,'100000001');
 });
 await test('a failed restore never clears a newer committed session',async()=>{
  const h=harness();h.user(1);h.user(2);h.state.prefsId=1;const gate=h.gate('restore',1),restore=h.service.restoreSession();await flush();await h.service.switchUser(2);gate.reject(Error('private fixture account failure'));await restore;selected(h,2,'100000002');assert.ok(h.state.logs.every(line=>!line.includes('private fixture')));
 });
 await test('revision listeners are bounded, removable, isolated and carry only a number',async()=>{
  const h=harness();await h.seed();const seen=[];const unsubscribe=h.service.addSessionRevisionListener(value=>seen.push(value));h.service.addSessionRevisionListener(()=>{throw Error('fixture listener');});await h.service.logout();assert.ok(seen.length>=2);assert.ok(seen.every(value=>typeof value==='number'));unsubscribe();const count=seen.length;await h.service.logout();assert.equal(seen.length,count);for(let i=0;i<15;i++)h.service.addSessionRevisionListener(()=>{});assert.throws(()=>h.service.addSessionRevisionListener(()=>{}),/限制/);
 });
 await test('account ViewModel late load cannot restore a stale selection or write default UID',async()=>{
  const h=harness();await h.seed();h.user(2);const Model=h.load('viewmodel/UserViewModel').UserViewModel,model=new Model();await model.load();const gate=h.gate('all',0),pending=model.load();await flush();await model.switchUser(2);gate.resolve();await pending;assert.equal(model.currentUser.id,2);assert.equal(model.currentUid,'100000002');selected(h,2,'100000002');const raw=fs.readFileSync(path.join(root,'viewmodel/UserViewModel.ets'),'utf8');assert.ok(!raw.includes('UserRepo.setDefaultUid'));assert.ok(!raw.includes('AppStorage'));
 });
 await test('natural current-session token refresh and retry preserve owner object and revision',async()=>{
  const h=harness(),owner=await h.seed(),revision=h.service.sessionRevision(),UserService=h.load('service/UserService').UserService;
  let observed='';const result=await UserService.retryWithRefreshedCookie(owner,async()=>{observed=owner.gameRecordCookie();return accepted({fixture:true});});
  assert.equal(result.success,true);assert.equal(h.service.getCurrentUser(),owner);assert.equal(h.service.sessionRevision(),revision);assert.ok(observed.includes('fixture-rotated'));assert.ok(observed.includes('fixture-ltoken-rotated'));selected(h,1,'100000001');assert.equal(h.state.rows.get(1).cookieToken,owner.cookieToken);
 });
 await test('successful token completion updates a matching caller copy and selected owner without replacement',async()=>{
  const h=harness(),owner=await h.seed(),revision=h.service.sessionRevision(),copy=owner.clone();copy.cookieToken='';h.state.rows.get(1).cookieToken='';owner.cookieToken='';
  await h.service.completeTokenChainPublic(copy);assert.equal(h.service.getCurrentUser(),owner);assert.equal(h.service.sessionRevision(),revision);assert.equal(copy.cookieToken,'fixture-rotated');assert.equal(owner.cookieToken,'fixture-rotated');selected(h,1,'100000001');
 });
 await test('a retried request finishing after logout cannot return stale authenticated data',async()=>{
  const h=harness(),owner=await h.seed(),gate=deferred(),UserService=h.load('service/UserService').UserService;let sent=false;
  const pending=UserService.retryWithRefreshedCookie(owner,async()=>{sent=true;return gate.promise;}),rejected=assert.rejects(pending,/状态已变化/);await flush();assert.equal(sent,true);await h.service.logout();gate.resolve(accepted({fixture:true}));await rejected;selected(h,0,'');
 });
 await test('an already-dispatched role upsert rolls back when logout invalidates refresh',async()=>{
  const h=harness();await h.seed();h.state.network=async()=>accepted({list:[{game_uid:'100000009',region:'cn_gf01',nickname:'new',level:60}]});const gate=h.gate('upsert',1),pending=h.service.refreshRolesOfCurrent(),rejected=assert.rejects(pending,/状态已变化/);await flush();const logout=h.service.logout();gate.resolve();await Promise.all([rejected,logout]);selected(h,0,'');assert.equal(h.state.rows.get(1).roles[0].gameUid,'100000001');
 });
 await test('local reload cannot restore an old object after a newer login or logout',async()=>{
  for(const action of ['login','logout']){const h=harness();await h.seed();const gate=h.gate('restore',1),pending=h.service.reloadLocalSession(),rejected=assert.rejects(pending,/状态已变化/);await flush();if(action==='logout')await h.service.logout();else await h.service.loginWithCookie('stuid=22; stoken=fixture-new','new','avatar');const expected=h.service.getCurrentUser();gate.resolve();await rejected;assert.equal(h.service.getCurrentUser(),expected);selected(h,expected?.id||0,expected?'':'');}
 });
 await test('current-account default UID updates all stores while out-of-order intent cannot win',async()=>{
  const h=harness();await h.seed();const row=h.state.rows.get(1);row.roles.push(row.roles[0].constructor.of('100000009','cn_gf01','other',60));const revision=h.service.sessionRevision();await h.service.setDefaultUid(1,'100000009');selected(h,1,'100000009');assert.ok(h.service.sessionRevision()>revision);assert.equal(h.state.rows.get(1).roles.find(role=>role.isDefault).gameUid,'100000009');
  const gate=h.gate('read',1),old=h.service.setDefaultUid(1,'100000001'),rejected=assert.rejects(old,/状态已变化/);await flush();await h.service.setDefaultUid(1,'100000009');gate.resolve();await rejected;selected(h,1,'100000009');
 });
 await test('superseded partial login removes its inserted identity when later login validation fails',async()=>{
  const h=harness(),owner=await h.seed(),gate=h.gate('cookie',10);const old=h.service.loginWithCookie('stuid=77; stoken=fixture-old','old','avatar'),rejected=assert.rejects(old,/状态已变化/);await flush();await assert.rejects(h.service.loginWithCookie('invalid','bad','avatar'),/有效 token/);gate.resolve();await rejected;assert.equal(h.service.getCurrentUser(),owner);selected(h,1,'100000001');assert.equal(h.state.rows.has(10),false);assert.equal(h.state.maxWrites,1);
 });
 await test('logout while a switch select is already dispatched repairs durable selection to empty',async()=>{
  const h=harness();await h.seed();h.user(2);const gate=h.gate('select',2),old=h.service.switchUser(2),rejected=assert.rejects(old,/状态已变化/);await flush();const logout=h.service.logout();gate.resolve();await Promise.all([rejected,logout]);selected(h,0,'');assert.ok([...h.state.rows.values()].every(user=>!user.isSelected));
 });
 await test('late profile and public-role callbacks cannot mutate a switched-away User or resurrect its rows',async()=>{
  for(const method of ['fetchUserFullInfo','fetchAndStoreRoles']){const h=harness(),owner=await h.seed(),oldName=owner.displayName,gate=deferred();h.state.network=()=>gate.promise;const work=h.service[method](owner),rejected=assert.rejects(work,/状态已变化/);await flush();await h.service.deleteUser(1);gate.resolve(accepted({user_info:{nickname:'late'},list:[{game_uid:'100000009',region:'cn_gf01'}]}));await rejected;assert.equal(owner.displayName,oldName);assert.equal(owner.roles[0].gameUid,'100000001');assert.equal(h.state.rows.has(1),false);selected(h,0,'');}
 });
 await test('a delayed invalidation hook cannot allow an older switch after a newer logout',async()=>{
  const h=harness();await h.seed();h.user(2);const gate=deferred();h.service.setSessionInvalidationHook(reason=>reason==='switch'?gate.promise:Promise.resolve(true));const old=h.service.switchUser(2),rejected=assert.rejects(old,/状态已变化/);await flush();await h.service.logout();gate.resolve(true);await rejected;selected(h,0,'');
 });
 await test('token refresh fills missing account alias durably without changing session ownership',async()=>{
  const h=harness(),owner=await h.seed();owner.aid='';h.state.rows.get(1).aid='';const revision=h.service.sessionRevision();await h.service.refreshCookieTokenForced(owner);assert.equal(owner.aid,'11');assert.equal(h.state.rows.get(1).aid,'11');await h.service.refreshCookieTokenForced(owner);assert.equal(h.service.sessionRevision(),revision);assert.equal(h.service.getCurrentUser(),owner);selected(h,1,'100000001');
 });
 await test('failed post-commit local reload cannot expose the pre-restore identity',async()=>{
  const h=harness(),owner=await h.seed(),revision=await h.service.beginLocalSessionReplacement();h.user(1,'100000009');const gate=h.gate('restore',1),reload=h.service.reloadLocalSession(),rejected=assert.rejects(reload,/fixture reload failure/);await flush();gate.reject(Error('fixture reload failure'));await rejected;selected(h,0,'');assert.notEqual(h.service.getCurrentUser(),owner);h.service.cancelLocalSessionReplacement(revision);selected(h,0,'');
 });
 await test('delete write failure leaves the attempted selected identity logged out and remains retryable',async()=>{
  const h=harness();await h.seed();h.state.fail='delete';await assert.rejects(h.service.deleteUser(1),/fixture delete failed/);selected(h,0,'');await h.service.deleteUser(1);assert.equal(h.state.rows.has(1),false);selected(h,0,'');
 });
 await test('restore exposes explicit success only for a committed matching account and pending state is observable',async()=>{
  const empty=harness();assert.equal(await empty.service.restoreSession(),false);const h=harness();h.user(1);h.state.prefsId=1;assert.equal(await h.service.restoreSession(),true);assert.equal(h.service.isSessionTransitionPending(),false);const gate=h.gate('restore',1),restore=h.service.restoreSession();assert.equal(h.service.isSessionTransitionPending(),true);await flush();await h.service.logout();gate.resolve();assert.equal(await restore,false);assert.equal(h.service.isSessionTransitionPending(),false);selected(h,0,'');
 });
 await test('account service/model/viewmodel graph passes strict host types at explicit platform boundaries',strictAccountTypes);
 await test('modified UserService logs never interpolate account, UID, profile or raw errors',()=>{
  const source=fs.readFileSync(path.join(root,'service/UserService.ets'),'utf8');const logs=source.split('\n').filter(line=>line.includes('Logger.'));for(const line of logs)assert.doesNotMatch(line,/\$\{(?:user|uid|saved|existingId|stuid|nickname|avatar|account|\(e|.*\.message)/);
 });
})().catch(error=>{console.error(error);process.exitCode=1;});
