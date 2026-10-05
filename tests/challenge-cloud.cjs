// Synthetic first-party game reads and cloud HTTP boundaries; no real account or upload calls.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const test=require('node:test'),ts=require(process.env.TYPESCRIPT_PATH||'../ci/node_modules/typescript');
const root=path.resolve(__dirname,'../entry/src/main/ets'),copy=x=>JSON.parse(JSON.stringify(x));
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
const flush=async()=>{for(let i=0;i<100;i++)await Promise.resolve();};
const ids=[10000005,10000006,10000015,10000021,10000022,10000023,10000024,10000025,10000026];
const uid='100000001',region='cn_gf01';
function fixtures(){return {
 index:{role:{nickname:'Fixture player',level:60,region:'天空岛'}},
 'character/list':{list:ids.map(id=>({id})),total:ids.length},
 'character/detail':{list:ids.map((id,index)=>({base:{id,actived_constellation_num:index%7},weapon:{id:11501},relics:[{set:{id:15001+1000000}},{set:{id:15001+1000000}}]}))},
 spiralAbyss:{is_unlock:true,schedule_id:123,total_battle_times:20,total_win_times:12,damage_rank:[{avatar_id:ids[0],value:345678}],take_damage_rank:[],floors:[{index:9,star:3,levels:[{index:1,star:3,battles:[{index:1,avatars:ids.slice(0,4).map(id=>({id}))},{index:2,avatars:ids.slice(4,8).map(id=>({id}))}]}]}]},
 role_combat:{is_unlock:true,data:[{has_data:true,has_detail_data:true,schedule:{schedule_id:456},detail:{backup_avatars:ids.slice(0,8).map(avatar_id=>({avatar_id}))}}]}
};}
function harness(){
 const state={game:[],cloud:[],fixtures:fixtures(),revision:1,cloudRevision:1,passport:'',selectedUid:uid,stores:new Map(),now:1800000000000,failFlush:false,riskCalls:0,hashGate:undefined};
 const modules=new Map();
 const user={id:1,isOversea:false,cookieToken:'fixture-game-secret',ltoken:'fixture-ltoken',roles:[{gameUid:uid,region}],hasCookie:()=>true,gameRecordCookie:()=> 'cookie_token=fixture-game-secret; ltoken=fixture-ltoken'};state.user=user;
 const users={getCurrentUser:()=>state.user,sessionRevision:()=>state.revision,async completeTokenChainPublic(){},};
 const cloud={getSessionRevision:()=>state.cloudRevision,async initialize(){},isLoggedIn:()=>state.passport.length>0,getUserName:()=>state.passport};
 const sdk={
  cryptoFramework:{createMd:algorithm=>{let data;return {async update(blob){data=Buffer.from(blob.data);if(state.hashGate)await state.hashGate.promise;},async digest(){return {data:new Uint8Array(crypto.createHash(algorithm.toLowerCase()).update(data).digest())};}};}},
  util:{TextEncoder:class{encodeInto(text){return new Uint8Array(Buffer.from(text));}},generateRandomUUID:()=> 'fixture-device'},
  http:{RequestMethod:{POST:'POST',GET:'GET'},HttpDataType:{STRING:'STRING'},createHttp:()=>({async request(url,options){const call={url,options};state.cloud.push(call);if(state.cloudHook)return state.cloudHook(call);return {responseCode:200,result:JSON.stringify({retcode:0,message:'fixture server accepted anonymous'})};},destroy(){state.destroyed=(state.destroyed??0)+1;}})},
  preferences:{async getPreferences(context,name){if(!state.stores.has(name))state.stores.set(name,new Map());const values=state.stores.get(name);return {getSync:(key,def)=>values.get(key)??def,putSync:(key,value)=>values.set(key,value),async flush(){if(state.failFlush)throw Error('fixture durable failure');}};}}
 };
 const gameRead=async(url,body,headers)=>{
  const endpoint=new URL(url).pathname.split('/api/')[1];const call={endpoint,url,body:body?JSON.parse(body):undefined,headers};state.game.push(call);
  if(state.gameHook){const override=await state.gameHook(call);if(override!==undefined)return override;}
  const data=copy(state.fixtures[endpoint]);return {success:true,data,isRiskControl:()=>false,userFriendlyMessage:()=> 'fixture game error'};
 };
 const api={get:(url,headers)=>gameRead(url,'',headers),postJson:(url,body,headers)=>gameRead(url,body,headers)};
 const nativeDate=Date;class Clock extends nativeDate{static now(){return state.now;}}
 function load(name){if(modules.has(name))return modules.get(name);const source=fs.readFileSync(path.join(root,name+'.ets'),'utf8').replace(/^@Observed\s*$/mg,'');const out=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});assert.equal(out.diagnostics.length,0,name);const mod={exports:{}};modules.set(name,mod.exports);
  vm.runInNewContext(`(function(require,module,exports){${out.outputText}\n})`,{Error,Date:Clock,AppStorage:{get:()=>state.selectedUid},TextEncoder})(id=>{
   if(id==='@kit.CryptoArchitectureKit')return {cryptoFramework:sdk.cryptoFramework};
   if(id==='@kit.ArkTS')return {util:sdk.util};if(id==='@kit.NetworkKit')return {http:sdk.http};if(id==='@kit.ArkData')return {preferences:sdk.preferences};
   if(id.endsWith('/AppContext'))return {AppContextProvider:{getAppContext:()=>({})}};
   if(id.endsWith('/UserService'))return {UserService:{getInstance:()=>users,isCookieAuthError:resp=>resp.retcode===-100,async retryWithRefreshedCookie(user,operation){return operation();}}};
   if(id.endsWith('/HutaoCloudService'))return {HutaoCloudService:{getInstance:()=>cloud}};
   if(id.endsWith('/ApiClient'))return {ApiClient:{getInstance:()=>api}};
   if(id.endsWith('/HoyolabClient'))return {HoyolabClient:{getBaseHeaders:()=>({'x-rpc-app_version':'fixture'}),merge:(a,b)=>({...a,...b})}};
   if(id.endsWith('/DsSigner'))return {DsSigner:{sortQuery:query=>Object.keys(query).sort().map(k=>`${k}=${query[k]}`).join('&'),nowTimestamp:()=>state.now/1000,randomNumber:()=> '123456',signGen2:async()=> 'fixture-ds'}};
   if(id.endsWith('/RiskVerifier'))return {RiskVerifier:{async tryResolveRisk(){state.riskCalls++;return state.riskResult??'fixture-replay';}}};
   if(id.endsWith('/PreferencesStore'))return {PreferencesStore:{getString:()=> 'fixture-device',setString(){}}};
   if(id.endsWith('/Constants'))return {RegionUtil:{isValidUid:uid=>/^\d{9}$/.test(uid),regionOfUid:()=>region,isOverseaRegion:r=>r.startsWith('os_')},AppConstants:{DS_SALT_X4:'fixture',DS_SALT_OS_X4:'fixture'}};
   assert.ok(id.startsWith('.'),id);return load(path.posix.normalize(path.posix.join(path.posix.dirname(name),id)));
  },mod,mod.exports);return mod.exports;
 }
 const Model=load('viewmodel/ChallengeCloudViewModel').ChallengeCloudViewModel;
 const Service=load('service/ChallengeCloudService').ChallengeCloudService;
 const Store=load('data/local/ChallengeCloudReceiptStore').ChallengeCloudReceiptStore;
 return {state,model:new Model(),Model,service:new Service(),Service,Store,load};
}
function strictTypes(){
 const vr='/challenge-cloud-types',files=new Map(),put=(name,text)=>files.set(vr+'/'+name+'.ts',text);
 const production=['model/ChallengeCloud','model/User','model/UserGameRole','model/ApiResponse','model/HutaoCloud','common/HoyolabEndpoints','service/ChallengeCloudService','viewmodel/ChallengeCloudViewModel','data/network/ChallengeGameRecordClient','data/network/HutaoCloudClient','data/local/ChallengeCloudReceiptStore'];
 for(const name of production)put(name,fs.readFileSync(path.join(root,name+'.ets'),'utf8').replace(/^@Observed\s*$/mg,''));
 put('sdk',`declare const AppStorage:{get<T>(key:string):T|undefined};
 declare module '@kit.ArkData' {export namespace preferences {interface Preferences{getSync(k:string,d:string):Object;putSync(k:string,v:string):void;flush():Promise<void>;}function getPreferences(c:Object,n:string):Promise<Preferences>;}}
 declare module '@kit.CryptoArchitectureKit'{export namespace cryptoFramework {interface DataBlob{data:Uint8Array;}interface Md{update(b:DataBlob):Promise<void>;digest():Promise<DataBlob>;}function createMd(s:string):Md;interface Cipher{init(m:Object,k:Object,n:null):Promise<void>;doFinal(b:DataBlob):Promise<DataBlob>;}interface KeyPair{pubKey:Object;}interface AsyKeyGenerator{convertKey(b:DataBlob,n:null):Promise<KeyPair>;}function createAsyKeyGenerator(s:string):AsyKeyGenerator;function createCipher(s:string):Cipher;const CryptoMode:{ENCRYPT_MODE:number};}}
 declare module '@kit.ArkTS'{export namespace util{class TextEncoder{encodeInto(s:string):Uint8Array;}function generateRandomUUID(b:boolean):string;class Base64Helper{decodeSync(s:string):Uint8Array;encodeToStringSync(b:Uint8Array):string;}}}
 declare module '@kit.NetworkKit'{export namespace http{interface HttpResponse{responseCode:number;result:string;}interface HttpRequest{request(url:string,options:Object):Promise<HttpResponse>;destroy():void;}function createHttp():HttpRequest;const RequestMethod:{POST:string;GET:string};const HttpDataType:{STRING:string};}}
 `);
 put('common/AppContext',`export class AppContextProvider{static getAppContext():Object{return {};}}`);
 put('common/Constants',`export class RegionUtil{static isValidUid(s:string):boolean{return true;}static regionOfUid(s:string):string{return '';}static isOverseaRegion(s:string):boolean{return false;}}export class AppConstants{static DS_SALT_X4='';static DS_SALT_OS_X4='';static SIGN_ACT_ID='';static DS_SALT_OS_LK2='';static DS_SALT_LK2='';}export class RetCodes{static OK=0;static NOT_LOGGED_IN=-100;static ALREADY_SIGNED=-5003;static NOT_STARTED=-5001;static DAILY_LIMIT=-1008;static ACCOUNT_RISK=1034;static NOTE_BANNED=10102;static SUCCESS=0;static RISK_CONTROL=1034;static COOKIE_EXPIRED=10001;static LOGIN_EXPIRED=-100;static INVALID_PARAMS=-2;static NOT_LOGIN=-100;static RATE_LIMIT=-502;}`);
 put('common/Logger',`export class Logger{static warn(a:string,b:string):void{}}`);
 put('service/UserService',`import {User} from '../model/User';import {ApiResponse} from '../model/ApiResponse';export class UserService{static getInstance():UserService{return new UserService();}getCurrentUser():User|undefined{return undefined;}sessionRevision():number{return 0;}async completeTokenChainPublic(u:User):Promise<void>{}static isCookieAuthError(r:ApiResponse):boolean{return false;}static async retryWithRefreshedCookie(u:User,op:()=>Promise<ApiResponse>):Promise<ApiResponse>{return op();}}`);
 put('service/HutaoCloudService',`export class HutaoCloudService{static getInstance():HutaoCloudService{return new HutaoCloudService();}getSessionRevision():number{return 0;}async initialize():Promise<void>{}isLoggedIn():boolean{return false;}getUserName():string{return '';}}`);
 put('data/network/ApiClient',`import {ApiResponse} from '../../model/ApiResponse';export class ApiClient{static getInstance():ApiClient{return new ApiClient();}async get(u:string,h:Record<string,string>):Promise<ApiResponse>{return new ApiResponse();}async postJson(u:string,b:string,h:Record<string,string>):Promise<ApiResponse>{return new ApiResponse();}}`);
 put('data/network/HoyolabClient',`export class HoyolabClient{static getBaseHeaders(r:string):Record<string,string>{return {};}static merge(a:Record<string,string>,b:Record<string,string>):Record<string,string>{return a;}}`);
 put('data/network/DsSigner',`export class DsSigner{static sortQuery(q:Record<string,string>):string{return '';}static nowTimestamp():number{return 0;}static randomNumber():string{return '';}static async signGen2(s:string,t:number,r:string,b:string,q:string):Promise<string>{return '';}}`);
 put('data/network/RiskVerifier',`import {ApiResponse} from '../../model/ApiResponse';export class RiskVerifier{static async tryResolveRisk(r:ApiResponse,c:string,u:string):Promise<string>{return '';}}`);
 put('data/prefs/PreferencesStore',`export class PreferencesStore{static getString(k:string,d:string):string{return d;}static setString(k:string,v:string):void{}}`);
 const options={strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,skipLibCheck:true},host=ts.createCompilerHost(options),base={fileExists:host.fileExists,readFile:host.readFile,getSourceFile:host.getSourceFile,directoryExists:host.directoryExists};
 host.fileExists=file=>files.has(file)||base.fileExists(file);host.readFile=file=>files.get(file)??base.readFile(file);host.getSourceFile=(file,version,...rest)=>files.has(file)?ts.createSourceFile(file,files.get(file),version,true):base.getSourceFile(file,version,...rest);host.directoryExists=directory=>[...files.keys()].some(file=>file.startsWith(directory+'/'))||base.directoryExists(directory);
 const diagnostics=ts.getPreEmitDiagnostics(ts.createProgram([...files.keys()],options,host));assert.equal(diagnostics.length,0,diagnostics.map(value=>`${value.file?.fileName}:${value.file?value.file.getLineAndCharacterOfPosition(value.start).line+1:''} ${ts.flattenDiagnosticMessageText(value.messageText,'\n')}`).join('\n'));
}

(async()=>{
 await test('production challenge graph passes strict host types with explicit SDK/account boundaries',strictTypes);
 await test('production DTO/client/VM prepare is read-only, anonymous confirm uses exact wire and bounded receipt digest',async()=>{
  const h=harness();await h.model.prepare('abyss',uid,123);assert.ok(h.model.preview,h.model.message);const preview=copy(h.model.preview);
  assert.deepEqual(h.state.game.map(x=>x.endpoint),['index','character/list','character/detail','spiralAbyss']);assert.equal(h.state.cloud.length,0);
  for(const call of h.state.game){assert.equal(call.headers.Cookie,'cookie_token=fixture-game-secret; ltoken=fixture-ltoken');assert.equal(new URL(call.url).host,'api-takumi-record.mihoyo.com');}
  const payload=JSON.parse(preview.body);assert.deepEqual(Object.keys(payload),['Uid','Identity','ReservedUserName','SpiralAbyss','Avatars']);assert.equal(payload.ReservedUserName,null);
  assert.deepEqual(payload.Avatars[0],{AvatarId:ids[0],WeaponId:11501,ReliquarySetIds:[1015001,1015001],ActivedConstellationNumber:0});
  assert.deepEqual(Object.keys(payload.SpiralAbyss),['ScheduleId','TotalBattleTimes','TotalWinTimes','Damage','TakeDamage','Floors']);assert.equal(payload.SpiralAbyss.TakeDamage,null);
  assert.equal(preview.digest,crypto.createHash('sha256').update(preview.body).digest('hex'));
  // Exposed preview mutation cannot alter the private pending request.
  h.model.preview.body='{"Cookie":"injected"}';await h.model.confirm();assert.equal(h.state.cloud.length,1);
  const request=h.state.cloud[0];assert.equal(request.url,'https://homa.snaphutaorp.org/Record/Upload');assert.equal(request.options.extraData,preview.body);assert.equal(request.options.method,'POST');assert.equal(request.options.maxRedirects,0);
  assert.equal(request.options.header.Cookie,undefined);assert.equal(request.options.header.Authorization,undefined);assert.ok(!JSON.stringify(request).includes('fixture-game-secret'));
  assert.equal(h.model.message,'fixture server accepted anonymous');const receipts=await h.Store.list();assert.equal(receipts.length,1);assert.equal(receipts[0].digest,preview.digest);assert.equal(receipts[0].uid,uid);assert.equal(receipts[0].uploadedAt,h.state.now);
  assert.ok(!JSON.stringify(receipts).includes('passport'));assert.ok(!JSON.stringify(receipts).includes('fixture-game-secret'));
  await h.model.prepare('abyss',uid,123);assert.equal(h.model.preview.duplicate,true);await h.model.confirm();assert.equal(h.state.cloud.length,1);
 });
 await test('Passport association is an explicit abyss DTO field, never a token or theater requirement',async()=>{
  const h=harness();h.state.passport='fixture@example.invalid';const preview=await h.service.prepare('abyss',uid,123);assert.equal(preview.passport,h.state.passport);assert.equal(JSON.parse(preview.body).ReservedUserName,h.state.passport);await h.service.confirm(preview.id);assert.equal(h.state.cloud[0].options.header.Authorization,undefined);
  const theater=await h.service.prepare('roleCombat',uid,456);assert.deepEqual(JSON.parse(theater.body),{Version:1,Uid:uid,Identity:'Snap Hutao',BackupAvatars:ids.slice(0,8),ScheduleId:456});assert.equal(theater.passport,'');await h.service.confirm(theater.id);assert.equal(h.state.cloud[1].url,'https://homa.snaphutaorp.org/RoleCombat/Upload');assert.equal(h.state.cloud[1].options.header.Authorization,undefined);
 });
 await test('missing/partial/fabricated data, wrong UID/period, and unsupported challenge reject before cloud send',async()=>{
  const changes=[f=>f.index.role.uid='100000002',f=>f['character/list'].total=999,f=>f['character/detail'].list.pop(),f=>delete f['character/detail'].list[0].relics,
   f=>delete f['character/detail'].list[0].relics[0].set.id,f=>delete f['character/detail'].list[0].base.actived_constellation_num,f=>f['character/detail'].list[0].weapon.id=0,
   f=>f.spiralAbyss.damage_rank=[],f=>f.spiralAbyss.total_win_times=0,f=>f.spiralAbyss.floors[0].levels[0].battles.pop(),f=>f.spiralAbyss.floors[0].levels[0].battles[1].avatars[0].id=ids[0],
   f=>f.spiralAbyss.schedule_id=999,f=>f.spiralAbyss.uid='100000002'];
  for(const change of changes){const h=harness();change(h.state.fixtures);await h.model.prepare('abyss',uid,123);assert.equal(h.model.preview,undefined);assert.ok(h.model.message);assert.equal(h.state.cloud.length,0);assert.equal((await h.Store.list()).length,0);}
  for(const mutate of [f=>f.role_combat.data[0].has_data=false,f=>f.role_combat.data[0].detail.backup_avatars.pop(),f=>f.role_combat.data[0].schedule.schedule_id=777]){const h=harness();mutate(h.state.fixtures);await h.model.prepare('roleCombat',uid,456);assert.equal(h.model.preview,undefined);assert.equal(h.state.cloud.length,0);}
  const h=harness();await assert.rejects(h.service.prepare('hardChallenge',uid,1),/不支持/);assert.equal(h.state.game.length,0);
 });
 await test('cancel during each read suppresses late previews; cancel after preview prevents send',async()=>{
  for(const endpoint of ['index','character/list','character/detail','spiralAbyss']){const h=harness(),gate=deferred();h.state.gameHook=call=>call.endpoint===endpoint?gate.promise:undefined;const pending=h.model.prepare('abyss',uid,123);await flush();assert.ok(h.state.game.some(x=>x.endpoint===endpoint));h.model.cancel();gate.resolve();await pending;assert.equal(h.model.preview,undefined);assert.equal(h.model.message,'');assert.equal(h.state.cloud.length,0);}
  const h=harness();await h.model.prepare('roleCombat',uid,456);h.model.cancel();await h.model.confirm();assert.equal(h.state.cloud.length,0);
 });
 await test('game ownership fences switches, UID changes, unowned roles and switch-away/back revisions',async()=>{
  for(const change of [s=>s.user={...s.user},s=>s.selectedUid='100000002',s=>s.revision+=2,s=>s.user.roles=[]]){const h=harness(),gate=deferred();h.state.gameHook=()=>gate.promise;const pending=h.model.prepare('abyss',uid,123);await flush();change(h.state);gate.resolve();await pending;assert.equal(h.model.preview,undefined);assert.match(h.model.message,/账号|UID/);assert.equal(h.state.cloud.length,0);assert.equal(h.state.game.length,1);}
  const h=harness();const preview=await h.service.prepare('abyss',uid,123);h.state.revision++;await assert.rejects(h.service.confirm(preview.id),/账号/);assert.equal(h.state.cloud.length,0);
 });
 await test('Passport change invalidates collection/preview even if no Bearer is sent',async()=>{
  const h=harness();const preview=await h.service.prepare('abyss',uid,123);h.state.cloudRevision++;await assert.rejects(h.service.confirm(preview.id),/通行证/);assert.equal(h.state.cloud.length,0);
 });
 await test('duplicate taps and distinct VM attempts share UID in-flight latch; no automatic resend',async()=>{
  const h=harness(),gate=deferred();await h.model.prepare('roleCombat',uid,456);const other=new h.Service();const otherPreview=await other.prepare('roleCombat',uid,456);h.state.cloudHook=()=>gate.promise;
  const pending=h.model.confirm();await flush();await h.model.confirm();await assert.rejects(other.confirm(otherPreview.id),/正在提交/);assert.equal(h.state.cloud.length,1);gate.resolve({responseCode:200,result:'{"retcode":0,"message":"ok"}'});await pending;await h.model.confirm();assert.equal(h.state.cloud.length,1);await assert.rejects(other.confirm(otherPreview.id),/成功收据/);assert.equal(h.state.cloud.length,1);
 });
 await test('HTTP/server refusal, malformed envelope and transport uncertainty never create success receipts',async()=>{
  for(const response of [{responseCode:429,result:'{}'},{responseCode:200,result:'{"retcode":-110,"message":"fixture server refusal"}'},{responseCode:200,result:'{"retcode":"0"}'},{responseCode:200,result:'null'},{responseCode:200,result:'false'},{responseCode:200,result:'{"message":"success"}'},{responseCode:200,result:'not json'}]){const h=harness();h.state.cloudHook=()=>response;await h.model.prepare('roleCombat',uid,456);await h.model.confirm();assert.ok(h.model.message.includes('未自动重试'));assert.equal((await h.Store.list()).length,0);assert.equal(h.state.cloud.length,1);assert.equal(h.state.destroyed,1);}
  const h=harness();h.state.cloudHook=()=>{throw Error('fixture timeout');};await h.model.prepare('abyss',uid,123);await h.model.confirm();assert.match(h.model.message,/可能已收到/);assert.equal((await h.Store.list()).length,0);
 });
 await test('late successful acknowledgement stays bound to original owner without overwriting new VM',async()=>{
  const h=harness(),gate=deferred();h.state.cloudHook=()=>gate.promise;await h.model.prepare('roleCombat',uid,456);const pending=h.model.confirm();await flush();h.model.cancel();h.state.revision++;h.state.selectedUid='100000002';gate.resolve({responseCode:200,result:'{"retcode":0,"message":"old successful submission"}'});await pending;assert.equal(h.model.message,'');const receipt=(await h.Store.list())[0];assert.equal(receipt.uid,uid);assert.equal(receipt.userId,1);
 });
 await test('expiry, durable receipt failure, bounded receipts and nonportable semantics are explicit',async()=>{
  const h=harness();const p=await h.service.prepare('roleCombat',uid,456);h.state.now=p.expiresAt+1;await assert.rejects(h.service.confirm(p.id),/过期/);assert.equal(h.state.cloud.length,0);
  const h2=harness();await h2.model.prepare('roleCombat',uid,456);h2.state.failFlush=true;await h2.model.confirm();assert.match(h2.model.message,/收据保存失败/);assert.equal(h2.state.cloud.length,1);
  const h3=harness(),Receipt=h3.load('model/ChallengeCloud').ChallengeCloudReceipt;for(let i=0;i<105;i++){const r=new Receipt();Object.assign(r,{userId:1,uid,region,kind:'abyss',scheduleId:i+1,digest:crypto.createHash('sha256').update(String(i)).digest('hex'),uploadedAt:h3.state.now+i});await h3.Store.save(r);}const receipts=await h3.Store.list();assert.equal(receipts.length,100);assert.equal(receipts[0].scheduleId,105);assert.equal(receipts.at(-1).scheduleId,6);
  const backup=fs.readFileSync(path.join(root,'model/BackupSnapshot.ets'),'utf8');assert.ok(!backup.includes('challenge_cloud_receipts'));assert.match(fs.readFileSync(path.join(root,'components/ChallengeCloudUploadCard.ets'),'utf8'),/不随数据备份迁移/);
 });
 await test('risk replay keeps original account and cancellation prevents replay; game Cookie never reaches cloud',async()=>{
  const h=harness();let count=0;h.state.gameHook=()=>++count===1?{success:false,retcode:1034,isRiskControl:()=>true}:undefined;await h.model.prepare('roleCombat',uid,456);assert.ok(h.model.preview,h.model.message);assert.equal(h.state.riskCalls,1);assert.equal(h.state.game[1].headers['x-rpc-challenge'],'fixture-replay');assert.equal(h.state.cloud.length,0);
  const h2=harness();h2.state.riskResult='';h2.state.gameHook=()=>({success:false,retcode:1034,isRiskControl:()=>true});await h2.model.prepare('roleCombat',uid,456);assert.match(h2.model.message,/验证已取消/);assert.equal(h2.state.game.length,1);
 });
 await test('reordering semantic sets and backend floor order preserves content digest',async()=>{
  const h=harness(),first=await h.service.prepare('abyss',uid,123);h.state.fixtures['character/list'].list.reverse();h.state.fixtures['character/detail'].list.reverse();h.state.fixtures.spiralAbyss.floors[0].levels[0].battles.reverse();for(const battle of h.state.fixtures.spiralAbyss.floors[0].levels[0].battles)battle.avatars.reverse();const second=await h.service.prepare('abyss',uid,123);assert.equal(first.digest,second.digest);
 });
})().catch(error=>{console.error(error);process.exitCode=1;});
