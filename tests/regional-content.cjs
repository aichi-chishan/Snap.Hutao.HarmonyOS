// Deterministic public/CN/HoYoLAB request contracts and account/UID/month race tests.
// No real accounts or network calls; production transport, services and viewmodels execute.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const test=require('node:test');
const ts=require(process.env.TYPESCRIPT_PATH||'../ci/node_modules/typescript');
const root=path.resolve(__dirname,'../entry/src/main/ets');
const deferred=()=>{let resolve;const promise=new Promise(done=>resolve=done);return{promise,resolve};};
const outcome=promise=>promise.then(value=>({value}),error=>({error}));
const tick=()=>new Promise(done=>setImmediate(done));
const plain=value=>JSON.parse(JSON.stringify(value));
function harness(){
 const state={sent:[],signatures:[],risk:[],refreshed:[],saved:[],closed:0,timestamp:100,signGate:null,tokenGate:null,
  response:async()=>({retcode:0,data:{}}),riskResult:async()=>'',codes:async()=>[],codeCalls:0};
 const prefs=new Map();
 const boundaries={
  '@kit.NetworkKit':{http:{RequestMethod:{GET:'GET',POST:'POST'},HttpDataType:{STRING:0},ResponseCode:{OK:200},createHttp:()=>({
   async request(url,options){state.sent.push({url,options:plain(options)});const result=await state.response(url,options);return{responseCode:200,result:JSON.stringify(result),header:{}};},destroy(){state.closed++;}})}},
  '@kit.BasicServicesKit':{deviceInfo:{marketName:'host fixture'}},
  Logger:{Logger:{info(){},warn(){},error(){}}},
  PreferencesStore:{PreferencesStore:{getDeviceId:()=> 'fixture-device',getDeviceFp:()=> 'fixture-fp',getString:(key,value)=>prefs.get(key)||value,setString:(key,value)=>prefs.set(key,value)}},
  DsSigner:{DsSigner:{sortQuery:query=>Object.keys(query).sort().map(key=>`${key}=${query[key]}`).join('&'),nowTimestamp:()=>++state.timestamp,randomNumber:()=>String(state.timestamp),
   async signGen2(salt,time,nonce,body,query){state.signatures.push({salt,time,nonce,body,query});if(state.signGate)await state.signGate;return`${time},${nonce},fixture-signature`;}}},
  RiskVerifier:{RiskVerifier:{async tryResolveRisk(response,cookie,path){state.risk.push({response,cookie,path});return state.riskResult();}}},
  UserRepo:{UserRepo:{async saveCookieFor(id,cookie){state.saved.push({id,cookie});}}},
  DeviceFpApi:{DeviceFpApi:{}},DailyNoteReminderService:{DailyNoteReminderService:{}},
  MiyoliveService:{MiyoliveService:{getInstance:()=>({async fetchRedeemCodes(){state.codeCalls++;return state.codes();}})}},
 };
 const cache=new Map();
 function load(relative){
  const file=path.resolve(root,relative.endsWith('.ets')?relative:relative+'.ets');if(cache.has(file))return cache.get(file);
  let source=fs.readFileSync(file,'utf8').replace(/^@Observed\s*$/gm,'');
  if(file.endsWith('/components/HomeTravelersDiaryCard.ets')){
   // Execute real lifecycle methods; leave native build()/UI rendering to the SDK/device checks.
   source=source.slice(0,source.indexOf('  build() {'))+'\n}';
   source=source.replace(/@\w+(?:\([^)]*\))?\s*/g,'').replace('export struct ','export class ')
    .replace(/^import \{ (PressCard|NavIcon) \}[^\n]*\n/gm,'');
  }
  const compiled=ts.transpileModule(source,{fileName:file.replace('.ets','.ts'),compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
  assert.equal(compiled.diagnostics.length,0,file);const module={exports:{}};cache.set(file,module.exports);
  const requireLocal=id=>{if(boundaries[id])return boundaries[id];const name=path.basename(id);if(boundaries[name])return boundaries[name];assert.ok(id.startsWith('.'),id);return load(path.resolve(path.dirname(file),id));};
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`,{AppStorage:{setOrCreate(){}}})(requireLocal,module,module.exports);return module.exports;
 }
 const User=load('model/User').User,Role=load('model/UserGameRole').UserGameRole;
 const Users=load('service/UserService').UserService,users=Users.getInstance(),client=load('data/network/ApiClient').ApiClient.getInstance();
 const ledger=load('service/LedgerService').LedgerService.getInstance();
 const AnnouncementService=load('service/AnnouncementService').AnnouncementService,announcements=AnnouncementService.getInstance();
 const Context=load('model/RegionalContent').AnnouncementContext;
 function select(uid='100000001',id=1){
  const user=new User();user.id=id;user.mid=`fixture-mid-${id}`;user.aid=`fixture-aid-${id}`;
  user.accountId=String(id);user.cookieToken=`fixture-cookie-${id}`;user.ltuid=String(id);user.ltoken=`fixture-ltoken-${id}`;user.stuid=String(id);user.stoken=`fixture-stoken-${id}`;
  const region=load('common/Constants').RegionUtil.regionOfUid(uid);user.isOversea=region.startsWith('os_');
  const role=Role.of(uid,region,'fixture',55);role.userId=id;user.roles=[role];users.currentUser=user;client.setCookie(user.fullCookie(),user.isOversea);return user;
 }
 users.completeTokenChainInner=async(user,force)=>{state.refreshed.push({user,force});if(state.tokenGate)await state.tokenGate;user.cookieToken='fixture-refreshed-cookie';};
 const LedgerVM=load('viewmodel/LedgerViewModel').LedgerViewModel,AnnVM=load('viewmodel/AnnouncementViewModel').AnnouncementViewModel;
 return{state,load,users,client,ledger,announcements,Context,LedgerVM,AnnVM,select};
}
function ledgerData(uid,region,month=10,amount=100){return{uid,region,nickname:'fixture',month,date:'2026-10-05',optional_month:[month,month,9,0,13],
 day_data:{current_primogems:1,current_mora:2,last_primogems:3,last_mora:4},
 month_data:{current_primogems:amount,current_mora:20,last_primogems:90,last_mora:30,group_by:[]}};}
const listData=(id=42,title='fixture')=>({list:[{type_id:1,list:[{ann_id:id,type:1,title,start_time:'2026-10-01 00:00:00'}]}],type_list:[{id:1,mi18n_name:'活动'}]});

test('six ledger regions use exact pinned endpoints, query names, DS salt and explicit owner cookies',async()=>{
 for(const[uid,region]of Object.entries({'100000001':'cn_gf01','500000001':'cn_qd01','600000001':'os_usa','700000001':'os_euro','800000001':'os_asia','900000001':'os_cht'})){
  const h=harness(),user=h.select(uid);h.state.response=async()=>({retcode:0,data:ledgerData(uid,region)});
  const result=await h.ledger.fetchMonth(10,uid);assert.equal(result.uid,Number(uid));assert.deepEqual(plain(result.optionalMonth),[10,9]);
  const request=h.state.sent[0],url=new URL(request.url),os=region.startsWith('os_');
  assert.equal(url.origin,os?'https://sg-hk4e-api.hoyolab.com':'https://hk4e-api.mihoyo.com');
  assert.equal(url.pathname,os?'/event/ysledgeros/month_info':'/event/ys_ledger/monthInfo');
  assert.equal(url.searchParams.get(os?'uid':'bind_uid'),uid);assert.equal(url.searchParams.get(os?'region':'bind_region'),region);
  assert.equal(url.searchParams.get('month'),'10');assert.equal(url.searchParams.get(os?'bind_uid':'uid'),null);
  assert.equal(h.state.signatures[0].query,url.search.slice(1));assert.equal(h.state.signatures[0].body,'');
  assert.equal(h.state.signatures[0].salt,os?'h4c1d6ywfq5bsbnbhm1bzq7bxzzv6srt':'xV8v4Qu54lUKrEYFZkJhB8cuOh9Asafs');
  assert.equal(request.options.header.Cookie,user.gameRecordCookie());assert.equal(request.options.header['x-rpc-client_type'],'5');
  assert.equal(request.options.header.Referer,os?undefined:'https://webstatic.mihoyo.com/');
  assert.equal(request.options.header['x-rpc-device_fp'],os?undefined:'fixture-fp');
  if(os)assert.equal(url.searchParams.get('lang'),'zh-cn');
 }
});

test('ledger rejects wrong account region, unbound UID, malformed month and mismatched bound role before signing/network',async()=>{
 const h=harness(),user=h.select('800000001');
 for(const month of [-1,13,1.5,NaN])await assert.rejects(h.ledger.fetchMonth(month,'800000001'));
 await assert.rejects(h.ledger.fetchMonth(0,'100000001'),/不匹配/);
 await assert.rejects(h.ledger.fetchMonth(0,'800000002'),/绑定/);
 user.roles[0].region='os_euro';await assert.rejects(h.ledger.fetchMonth(0,'800000001'),/绑定/);
 assert.equal(h.state.sent.length,0);assert.equal(h.state.signatures.length,0);assert.equal(h.state.refreshed.length,0);
});

test('OS authentication retry stays overseas, re-signs, refreshes explicit cookie and never falls back to CN risk flow',async()=>{
 const h=harness();h.select('800000001');let calls=0;
 h.state.response=async()=>++calls===1?{retcode:-100,message:'expired'}:{retcode:0,data:ledgerData('800000001','os_asia')};
 await h.ledger.fetchMonth(10,'800000001');assert.equal(h.state.sent.length,2);assert.equal(h.state.refreshed.length,1);
 assert.notEqual(h.state.sent[0].options.header.DS,h.state.sent[1].options.header.DS);assert.ok(h.state.sent[1].options.header.Cookie.includes('fixture-refreshed-cookie'));
 assert.ok(h.state.sent.every(request=>new URL(request.url).origin==='https://sg-hk4e-api.hoyolab.com'));
 h.state.response=async()=>({retcode:1034,message:'risk'});await assert.rejects(h.ledger.fetchMonth(10,'800000001'),/HoYoLAB/);assert.equal(h.state.risk.length,0);
});

test('CN risk and auth retries are bounded and obtain new DS signatures; cancelling verification preserves ownership',async()=>{
 const h=harness();h.select();let calls=0;
 h.state.response=async()=>({retcode:++calls===1?1034:0,data:ledgerData('100000001','cn_gf01')});h.state.riskResult=async()=> 'fixture-challenge';
 await h.ledger.fetchMonth(10,'100000001');assert.equal(h.state.risk.length,1);assert.notEqual(h.state.sent[0].options.header.DS,h.state.sent[1].options.header.DS);
 assert.equal(h.state.sent[1].options.header['x-rpc-challenge'],'fixture-challenge');
 h.state.response=async()=>({retcode:1034,message:'risk'});h.state.riskResult=async()=>'';
 await assert.rejects(h.ledger.fetchMonth(10,'100000001'),/取消/);
 const before=h.state.sent.length;h.state.response=async()=>({retcode:-100,message:'expired'});
 await assert.rejects(h.ledger.fetchMonth(10,'100000001'));assert.equal(h.state.sent.length-before,2);
});

test('account switch during signing, HTTP, refresh or risk waits prevents old retry/result publication',async()=>{
 for(const phase of ['sign','http','refresh','risk']){
  const h=harness(),gate=deferred();h.select();let waiting=false;
  if(phase==='sign')h.state.signGate=gate.promise;
  h.state.response=async()=>{if(phase==='http'){waiting=true;await gate.promise;}return{retcode:phase==='refresh'?-100:phase==='risk'?1034:0,data:ledgerData('100000001','cn_gf01')};};
  if(phase==='refresh')h.state.tokenGate=gate.promise;
  if(phase==='risk')h.state.riskResult=async()=>{waiting=true;await gate.promise;return'old-challenge';};
  const running=outcome(h.ledger.fetchMonth(10,'100000001'));
  while(!(phase==='sign'?h.state.signatures.length:phase==='refresh'?h.state.refreshed.length:waiting))await tick();
  const newUser=h.select('800000001',2);gate.resolve();assert.match((await running).error.message,/已改变/);
  assert.equal(h.client.getCurrentCookie(),newUser.fullCookie());assert.equal(h.state.sent.length,phase==='sign'?0:1);
 }
});

test('ledger response cannot cross UID, region or requested month',async()=>{
 const h=harness();h.select();
 for(const bad of [ledgerData('100000002','cn_gf01'),ledgerData('100000001','os_asia'),ledgerData('100000001','cn_gf01',9)]){
  h.state.response=async()=>({retcode:0,data:bad});await assert.rejects(h.ledger.fetchMonth(10,'100000001'),/不匹配/);
 }
 for(const bad of [{...ledgerData('100000001','cn_gf01'),uid:['100000001']},{...ledgerData('100000001','cn_gf01'),month:[10]},
  {...ledgerData('100000001','cn_gf01'),month_data:null},{...ledgerData('100000001','cn_gf01'),month_data:{current_primogems:0,current_mora:0}}]){
  h.state.response=async()=>({retcode:0,data:bad});await assert.rejects(h.ledger.fetchMonth(10,'100000001'));
 }
});

test('account switch at the request-Promise handoff cannot start old risk UI or publish a response',async()=>{
 for(const retcode of [0,1034,-100]){
  const h=harness();h.select();h.state.response=async()=>({retcode,data:ledgerData('100000001','cn_gf01')});
  const request=h.ledger.request.bind(h.ledger);
  h.ledger.request=async(...args)=>{const response=await request(...args);h.select('800000001',2);return response;};
  await assert.rejects(h.ledger.fetchMonth(10,'100000001'),/已改变/);
  assert.equal(h.state.risk.length,0);assert.equal(h.state.refreshed.length,0);assert.equal(h.state.sent.length,1);
 }
});

test('ledger viewmodel keeps only latest month, clears account changes, labels same-month refresh failures and ignores dispose',async()=>{
 const h=harness();h.select();const view=new h.LedgerVM(),gate=deferred();
 h.state.response=async url=>{const month=Number(new URL(url).searchParams.get('month'));if(month===9)await gate.promise;return{retcode:0,data:ledgerData('100000001','cn_gf01',month||10,month*100)};};
 view.month=9;const old=view.load('100000001',1,()=>true);await tick();view.month=10;await view.load('100000001',1,()=>true);gate.resolve();await old;
 assert.equal(view.ledger.month,10);assert.equal(view.ledger.monthData.currentPrimogems,1000);
 h.state.response=async()=>({retcode:-2,message:'offline'});await view.load('100000001',1,()=>true);assert.equal(view.stale,true);assert.equal(view.ledger.month,10);
 h.select('800000001',2);view.clear();await view.load('800000001',2,()=>true);assert.equal(view.ledger,undefined);assert.equal(view.stale,false);
 const late=deferred();h.state.response=async()=>{await late.promise;return{retcode:0,data:ledgerData('800000001','os_asia')};};
 const pending=view.load('800000001',2,()=>true);await tick();view.dispose();late.resolve();await pending;assert.equal(view.ledger,undefined);assert.equal(view.loading,false);
});

test('both token completion wrappers cannot republish cookies after switch, logout, or account-ID reuse',async()=>{
 for(const wrapper of ['completeTokenChainPublic','refreshCookieTokenForced'])for(const target of ['switch','logout','reuse']){
  const h=harness(),user=h.select(),gate=deferred();h.state.tokenGate=gate.promise;
  const running=h.users[wrapper](user);while(!h.state.refreshed.length)await tick();
  if(target==='logout'){h.users.currentUser=undefined;h.client.setCookie('');}
  else h.select('800000001',target==='reuse'?1:2);
  const expected=h.client.getCurrentCookie();gate.resolve();await running;assert.equal(h.client.getCurrentCookie(),expected,wrapper+' '+target);
 }
 const h=harness(),user=h.select();await h.users.completeTokenChainPublic(user);assert.ok(h.client.getCurrentCookie().includes('fixture-refreshed-cookie'));
});

test('home diary lifecycle immediately clears prior account figures and ignores switched/detached results',async()=>{
 const h=harness(),gate=deferred();h.select();
 const Card=h.load('components/HomeTravelersDiaryCard').HomeTravelersDiaryCard,card=new Card();
 card.currentUid='100000001';card.currentUserId=1;
 h.state.response=async url=>{const u=new URL(url),uid=u.searchParams.get('uid')||u.searchParams.get('bind_uid');if(uid==='100000001')await gate.promise;
  return{retcode:0,data:ledgerData(uid,uid==='100000001'?'cn_gf01':'os_asia',10,uid==='100000001'?111:222)};};
 card.aboutToAppear();await tick();h.select('800000001',2);card.currentUid='800000001';card.currentUserId=2;card.onOwnerChanged();
 assert.equal(card.vm.ledger,undefined);while(!card.loaded)await tick();assert.equal(card.vm.ledger.monthData.currentPrimogems,222);
 gate.resolve();await tick();await tick();assert.equal(card.vm.ledger.uid,800000001);
 const late=deferred();h.state.response=async()=>{await late.promise;return{retcode:0,data:ledgerData('800000001','os_asia',10,333)};};
 card.onOwnerChanged();await tick();card.aboutToDisappear();late.resolve();await tick();await tick();assert.equal(card.vm.ledger,undefined);assert.equal(card.loaded,false);
});

test('announcements route all six regions and 15 supported language codes without credentials or DS',async()=>{
 const h=harness();h.select('800000001');h.state.response=async()=>({retcode:0,data:listData()});
 for(const region of h.Context.REGIONS){
  const groups=await h.announcements.fetchGroups(region,55,'en-us');const request=h.state.sent.at(-1),url=new URL(request.url),os=region.startsWith('os_');
  assert.equal(url.origin,os?'https://sg-hk4e-api.hoyoverse.com':'https://hk4e-ann-api.mihoyo.com');
  assert.equal(url.pathname,`/common/${os?'hk4e_global':'hk4e_cn'}/announcement/api/getAnnList`);
  for(const key of ['game_biz','bundle_id'])assert.equal(url.searchParams.get(key),os?'hk4e_global':'hk4e_cn');
  assert.equal(url.searchParams.get('region'),region);assert.equal(url.searchParams.get('lang'),'en-us');assert.equal(url.searchParams.get('level'),'55');assert.equal(url.searchParams.get('uid'),'100000000');
  assert.ok(request.options.header.Cookie===undefined||request.options.header.Cookie==='');assert.equal(request.options.header.DS,undefined);
  assert.equal(groups[0].items[0].sourceRegion,region);assert.equal(groups[0].items[0].sourceLanguage,'en-us');
 }
 assert.equal(h.Context.LANGUAGES.length,15);for(const language of h.Context.LANGUAGES)assert.equal(h.Context.create('os_asia',language).language,language);
 for(const invalid of ['', '9abc', '80000000X', '012345678', '2800000001', '12345678901'])assert.equal(h.Context.forUid(invalid).region,'cn_gf01');
 assert.equal(h.Context.forUid('1800000001').region,'os_asia');
 for(const bad of ['','os_bad','https://evil'])await assert.rejects(h.announcements.fetchGroups(bad,55,'en-us'));
 await assert.rejects(h.announcements.fetchGroups('os_asia',55,'en-us&uid=private'));
});

test('announcement body selects exact ann_id and caches by region/language/level, never first element',async()=>{
 const h=harness();h.state.response=async url=>{const u=new URL(url);return{retcode:0,data:{list:[{ann_id:1,content:'wrong-first'},{ann_id:42,content:`${u.searchParams.get('region')}|${u.searchParams.get('lang')}|${u.searchParams.get('level')}`} ]}};};
 assert.equal(await h.announcements.fetchContent(42,'os_asia',55,'en-us'),'os_asia|en-us|55');
 const before=h.state.sent.length;assert.equal(await h.announcements.fetchContent(42,'os_asia',55,'en-us'),'os_asia|en-us|55');assert.equal(h.state.sent.length,before);
 assert.equal(await h.announcements.fetchContent(42,'cn_gf01',55,'en-us'),'cn_gf01|en-us|55');
 assert.equal(await h.announcements.fetchContent(42,'os_asia',55,'zh-cn'),'os_asia|zh-cn|55');
 assert.equal(await h.announcements.fetchContent(42,'os_asia',60,'en-us'),'os_asia|en-us|60');
 await assert.rejects(h.announcements.fetchContent(99,'os_asia',55,'en-us'),/所选公告/);
 assert.ok(h.state.sent.every(request=>!new URL(request.url).searchParams.has('ann_id')));
});

test('announcement cache copies caller data, coalesces requests and failed refresh does not poison successful results',async()=>{
 const h=harness(),gate=deferred();h.state.response=async()=>{await gate.promise;return{retcode:0,data:listData()};};
 const one=h.announcements.fetchGroups('os_asia',55,'en-us'),two=h.announcements.fetchGroups('os_asia',55,'en-us');assert.equal(h.state.sent.length,1);
 gate.resolve();const a=await one,b=await two;a[0].items[0].title='mutated';assert.equal(b[0].items[0].title,'fixture');
 h.state.response=async()=>({retcode:-2,message:'offline'});await assert.rejects(h.announcements.fetchGroups('os_asia',55,'en-us',true));
 const saved=await h.announcements.fetchGroups('os_asia',55,'en-us');assert.equal(saved[0].items[0].title,'fixture');
});

test('announcement viewmodel fences region/language/account reload races and drops late CN redeem codes',async()=>{
 const h=harness(),old=deferred(),codes=deferred(),view=new h.AnnVM();h.state.codes=async()=>codes.promise;
 h.state.response=async url=>{const u=new URL(url),region=u.searchParams.get('region');if(region==='cn_gf01')await old.promise;return{retcode:0,data:listData(42,region+'|'+u.searchParams.get('lang'))};};
 const pending=view.load(h.Context.create('cn_gf01','zh-cn'));await tick();await view.load(h.Context.create('os_asia','en-us'));
 old.resolve();codes.resolve([{code:'cn-only',title:'fixture'}]);await pending;await tick();assert.equal(view.filtered[0].title,'os_asia|en-us');assert.equal(view.redeemCodes.length,0);
 const later=deferred();h.state.response=async()=>{await later.promise;return{retcode:0,data:listData(50,'late')};};
 const loading=view.load(h.Context.create('os_euro','de-de'));await tick();view.dispose();later.resolve();await loading;assert.equal(view.filtered.length,0);assert.equal(view.loading,false);
});

test('detail navigation carries item-owned context and never invents announcement article URLs',()=>{
 const h=harness(),service=h.load('service/AnnouncementService').AnnouncementService;
 assert.equal(service.officialUrl('https://www.hoyolab.com/article/123'),'https://www.hoyolab.com/article/123');
 for(const url of ['javascript:alert(1)','https://www.hoyolab.com.evil/article/1','https://www.hoyolab.com@evil/article/1','http://www.miyoushe.com/ys/article/1'])assert.equal(service.officialUrl(url),'');
 const detail=fs.readFileSync(path.join(root,'pages/AnnouncementDetailPage.ets'),'utf8');
 assert.equal(detail.includes('article/${this.annId}'),false);assert.ok(detail.includes('this.context.region, this.context.level, this.context.language'));
 assert.ok(detail.includes('generation !== this.generation'));assert.ok(detail.includes('.javaScriptAccess(false)'));
 const page=fs.readFileSync(path.join(root,'pages/AnnouncementPage.ets'),'utf8');for(const field of ['region: item.sourceRegion','language: item.sourceLanguage','level: item.sourceLevel'])assert.ok(page.includes(field));
});
