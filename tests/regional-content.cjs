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
  response:async()=>({retcode:0,data:{}}),riskResult:async()=>'',codes:async()=>[],codeCalls:0,deviceFp:'fixture-fp'};
 const prefs=new Map(),accountRows=new Map();
 const boundaries={
  '@kit.NetworkKit':{http:{RequestMethod:{GET:'GET',POST:'POST'},HttpDataType:{STRING:0},ResponseCode:{OK:200},createHttp:()=>({
   async request(url,options){state.sent.push({url,options:plain(options)});const result=await state.response(url,options);return{responseCode:200,result:JSON.stringify(result),header:{}};},destroy(){state.closed++;}})}},
  '@kit.BasicServicesKit':{deviceInfo:{marketName:'host fixture'}},
  Logger:{Logger:{info(){},warn(){},error(){}}},
  PreferencesStore:{PreferencesStore:{getDeviceId:()=> 'fixture-device',getDeviceFp:()=> state.deviceFp,
   getString:(key,value)=>prefs.get(key)||value,setString:(key,value)=>prefs.set(key,value),
   getCookieExchangeTime:id=>prefs.get(`cookie-time:${id}`)??0,setCookieExchangeTime:(id,value)=>prefs.set(`cookie-time:${id}`,value)}},
  DsSigner:{DsSigner:{sortQuery:query=>Object.keys(query).sort().map(key=>`${key}=${query[key]}`).join('&'),nowTimestamp:()=>++state.timestamp,randomNumber:()=>String(state.timestamp),
   async signGen1(salt,time,nonce){state.signatures.push({salt,time,nonce});return`${time},${nonce},fixture-signature`;},
   async signGen2(salt,time,nonce,body,query){state.signatures.push({salt,time,nonce,body,query});if(state.signGate)await state.signGate;return`${time},${nonce},fixture-signature`;}}},
  RiskVerifier:{RiskVerifier:{async tryResolveRisk(response,cookie,path){state.risk.push({response,cookie,path});return state.riskResult();}}},
  UserRepo:{UserRepo:{async getUserById(id){return accountRows.get(id)?.clone();},async loadCookieFor(id){return accountRows.get(id)?.fullCookie()||'';},async saveCookieFor(id,cookie){state.saved.push({id,cookie});const row=accountRows.get(id);if(row)row.applyCookie(cookie);}}},
  DeviceFpApi:{DeviceFpApi:{}},DailyNoteReminderService:{DailyNoteReminderService:{}},
  PassportClient:{PassportClient:{}},
  MiyoliveService:{MiyoliveService:{getInstance:()=>({async fetchRedeemCodes(){state.codeCalls++;return state.codes();}})}},
 };
 const cache=new Map();
  // path.resolve yields '\' separators on Windows; the structural check below is written in
  // '/'-space, so compare a normalized copy instead of weakening the assertion.
  const posix=value=>String(value).replaceAll('\\','/');
 function load(relative){
  const file=path.resolve(root,relative.endsWith('.ets')?relative:relative+'.ets');if(cache.has(file))return cache.get(file);
  let source=fs.readFileSync(file,'utf8').replace(/^@Observed\s*$/gm,'');
  if(posix(file).endsWith('/components/HomeTravelersDiaryCard.ets')){
   // Execute real lifecycle/page methods; native builders and rendering stay in the SDK/device pass.
   const builder=source.indexOf('  @Builder');
   const renderStart=builder>=0?builder:source.indexOf('  build() {');
   source=source.slice(0,renderStart)+'\n}';
   source=source.replace(/@\w+(?:\([^)]*\))?\s*/g,'').replace('export struct ','export class ')
    .replace(/^import \{ (PressCard|NavIcon) \}[^\n]*\n/gm,'');
  }
  if (posix(file).endsWith('/components/HomeGachaBannerCard.ets')) {
    const build = source.indexOf('  build() {');
    const iconMethods = source.indexOf('  /** UP 图标显示单元', build);
    source = (source.slice(0, build) + source.slice(iconMethods))
      .replace(/@\w+(?:\([^)]*\))?\s*/g, '').replace('export struct ', 'export class ');
  }
  if (posix(file).endsWith('/components/HomeActBannerCard.ets')) {
    source = (source.slice(0, source.indexOf('  build() {')) + '\n}')
      .replace(/@\w+(?:\([^)]*\))?\s*/g, '').replace('export struct ', 'export class ');
  }
  const compiled=ts.transpileModule(source,{fileName:file.replace('.ets','.ts'),compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
  assert.equal(compiled.diagnostics.length,0,file);const module={exports:{}};cache.set(file,module.exports);
  const requireLocal=id=>{if(boundaries[id])return boundaries[id];const name=path.basename(id);if(boundaries[name])return boundaries[name];assert.ok(id.startsWith('.'),id);return load(path.resolve(path.dirname(file),id));};
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`,{AppStorage:{setOrCreate(){}},
    $r: name => name })(requireLocal,module,module.exports);return module.exports;
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
  const role=Role.of(uid,region,'fixture',55);role.userId=id;user.roles=[role];accountRows.set(id,user.clone());users.currentUser=user;users.advanceRevision();client.setCookie(user.fullCookie(),user.isOversea);return user;
 }
 users.completeTokenChainInner=async(user,force)=>{state.refreshed.push({user,force});if(state.tokenGate)await state.tokenGate;user.cookieToken='fixture-refreshed-cookie';return true;};
 const LedgerVM=load('viewmodel/LedgerViewModel').LedgerViewModel,AnnVM=load('viewmodel/AnnouncementViewModel').AnnouncementViewModel;
 return{state,load,users,client,ledger,announcements,Context,LedgerVM,AnnVM,select};
}
function ledgerData(uid,region,month=10,amount=100){return{uid,region,nickname:'fixture',month,date:'2026-10-05',optional_month:[month,month,9,0,13],
 day_data:{current_primogems:1,current_mora:2,last_primogems:3,last_mora:4},
 month_data:{current_primogems:amount,current_mora:20,last_primogems:90,last_mora:30,group_by:[]}};}
const listData=(id=42,title='fixture')=>({list:[{type_id:1,list:[{ann_id:id,type:1,title,start_time:'2026-10-01 00:00:00'}]}],type_list:[{id:1,mi18n_name:'活动'}]});

test('both CN ledger regions use the pinned query, DS salt and explicit owner cookie',async()=>{
 for(const[uid,region]of Object.entries({'100000001':'cn_gf01','500000001':'cn_qd01'})){
  const h=harness(),user=h.select(uid);h.state.response=async()=>({retcode:0,data:ledgerData(uid,region)});
  const result=await h.ledger.fetchMonth(10,uid);assert.equal(result.uid,Number(uid));assert.deepEqual(plain(result.optionalMonth),[10,9]);
  const request=h.state.sent[0],url=new URL(request.url);
  assert.equal(url.origin,'https://hk4e-api.mihoyo.com');
  assert.equal(url.pathname,'/event/ys_ledger/monthInfo');
  assert.equal(url.searchParams.get('bind_uid'),uid);assert.equal(url.searchParams.get('bind_region'),region);
  assert.equal(url.searchParams.get('month'),'10');assert.equal(url.searchParams.get('uid'),null);
  assert.equal(h.state.signatures[0].query,url.search.slice(1));assert.equal(h.state.signatures[0].body,'');
  assert.equal(h.state.signatures[0].salt,'xV8v4Qu54lUKrEYFZkJhB8cuOh9Asafs');
  assert.equal(request.options.header.Cookie,user.gameRecordCookie());assert.equal(request.options.header['x-rpc-client_type'],'5');
  assert.equal(request.options.header.Referer,'https://webstatic.mihoyo.com/');
  assert.equal(request.options.header['x-rpc-device_fp'],'fixture-fp');
 }
});

test('ledger rejects wrong account region, unbound UID, malformed month and mismatched bound role before signing/network',async()=>{
 const h=harness();h.select('800000001');
 await assert.rejects(h.ledger.fetchMonth(0,'100000001'),/不匹配/);
 const user=h.select();
 for(const month of [-1,13,1.5,NaN])await assert.rejects(h.ledger.fetchMonth(month,'100000001'),/月份无效/);
 await assert.rejects(h.ledger.fetchMonth(0,'100000002'),/绑定/);
 user.roles[0].region='cn_qd01';await assert.rejects(h.ledger.fetchMonth(0,'100000001'),/绑定/);
 assert.equal(h.state.sent.length,0);assert.equal(h.state.signatures.length,0);assert.equal(h.state.refreshed.length,0);
});

test('stored overseas ledger roles fail before signing, token refresh or network',async()=>{
 const h=harness();
 for(const uid of ['600000001','700000001','800000001','900000001','1800000001']){
  const user=h.select(uid);user.cookieToken='';
  await assert.rejects(h.ledger.fetchMonth(10,uid),/仅支持国服/);
 }
 assert.equal(h.state.sent.length,0);assert.equal(h.state.signatures.length,0);
 assert.equal(h.state.refreshed.length,0);assert.equal(h.state.risk.length,0);
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
  const newUser=h.select('800000001',2);gate.resolve();assert.match((await running).error.message,/已改变|已变化/);
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
  await assert.rejects(h.ledger.fetchMonth(10,'100000001'),/已改变|已变化/);
  assert.equal(h.state.risk.length,0);assert.equal(h.state.refreshed.length,0);assert.equal(h.state.sent.length,1);
 }
});

test('ledger viewmodel keeps only latest month, clears account changes, labels same-month refresh failures and ignores dispose',async()=>{
 const h=harness();h.select();const view=new h.LedgerVM(),gate=deferred();
 h.state.response=async url=>{const month=Number(new URL(url).searchParams.get('month'));if(month===9)await gate.promise;return{retcode:0,data:ledgerData('100000001','cn_gf01',month||10,month*100)};};
 view.month=9;const old=view.load('100000001',1,()=>true);await tick();view.month=10;await view.load('100000001',1,()=>true);gate.resolve();await old;
 assert.equal(view.ledger.month,10);assert.equal(view.ledger.monthData.currentPrimogems,1000);
 h.state.response=async()=>({retcode:-2,message:'offline'});await view.load('100000001',1,()=>true);assert.equal(view.stale,true);assert.equal(view.ledger.month,10);
 view.month=9;await view.load('100000001',1,()=>true);
 assert.equal(view.ledger,undefined);assert.equal(view.stale,false);assert.deepEqual(plain(view.availableMonths),[10,9]);
 h.select('100000002',2);view.clear();await view.load('100000002',2,()=>true);
 assert.equal(view.ledger,undefined);assert.deepEqual(plain(view.availableMonths),[]);
 const late=deferred();h.state.response=async()=>{await late.promise;return{retcode:0,data:ledgerData('100000002','cn_gf01')};};
 const pending=view.load('100000002',2,()=>true);await tick();view.dispose();late.resolve();await pending;
 assert.equal(view.ledger,undefined);view.activate();assert.equal(view.loading,false);
});

test('latest ledger refresh keeps asking the API for the current month at rollover',async()=>{
 const h=harness();h.select();
 const view=new h.LedgerVM();
 let month=12;
 h.state.response=async()=>({retcode:0,data:ledgerData('100000001','cn_gf01',month)});
 await view.load('100000001',1,()=>true);assert.equal(view.ledger.month,12);
 month=1;
 await view.load('100000001',1,()=>true);assert.equal(view.ledger.month,1);
 assert.ok(h.state.sent.every(request=>new URL(request.url).searchParams.get('month')==='0'));
});

test('both token completion wrappers cannot republish cookies after switch, logout, or account-ID reuse',async()=>{
 for(const wrapper of ['completeTokenChainPublic','refreshCookieTokenForced'])for(const target of ['switch','logout','reuse']){
  const h=harness(),user=h.select(),gate=deferred();h.state.tokenGate=gate.promise;
  const running=outcome(h.users[wrapper](user));while(!h.state.refreshed.length)await tick();
  if(target==='logout'){h.users.currentUser=undefined;h.users.advanceRevision();h.client.setCookie('');}
  else h.select('800000001',target==='reuse'?1:2);
  const expected=h.client.getCurrentCookie();gate.resolve();const result=await running;assert.match(result.error.message,/状态已变化/);assert.equal(h.client.getCurrentCookie(),expected,wrapper+' '+target);
 }
 const h=harness(),user=h.select();await h.users.completeTokenChainPublic(user);assert.ok(h.client.getCurrentCookie().includes('fixture-refreshed-cookie'));
});

test('home diary lifecycle immediately clears prior account figures and ignores switched/detached results',async()=>{
 const h=harness(),gate=deferred();h.select();
 const Card=h.load('components/HomeTravelersDiaryCard').HomeTravelersDiaryCard,card=new Card();
 card.currentUid='100000001';card.currentUserId=1;
 h.state.response=async url=>{const uid=new URL(url).searchParams.get('bind_uid');if(uid==='100000001')await gate.promise;
  return{retcode:0,data:ledgerData(uid,'cn_gf01',10,uid==='100000001'?111:222)};};
 card.aboutToAppear();await tick();card.selectPage(1);
 h.select('100000002',2);card.currentUid='100000002';card.currentUserId=2;card.onOwnerChanged();
 assert.equal(card.pageIndex,0);assert.equal(card.amount(false,true),'—');
 assert.equal(card.vm.ledger,undefined);while(!card.loaded)await tick();assert.equal(card.vm.ledger.monthData.currentPrimogems,222);
 gate.resolve();await tick();await tick();assert.equal(card.vm.ledger.uid,100000002);
 const late=deferred();h.state.response=async()=>{await late.promise;return{retcode:0,data:ledgerData('100000002','cn_gf01',10,333)};};
 card.onOwnerChanged();await tick();card.selectPage(1);card.aboutToDisappear();late.resolve();await tick();await tick();
 assert.equal(card.vm.ledger,undefined);assert.equal(card.loaded,false);assert.equal(card.amount(false,true),'—');
 h.state.response=async()=>({retcode:0,data:ledgerData('100000002','cn_gf01',10,444)});
 card.aboutToAppear();await tick();assert.equal(card.pageIndex,0);assert.equal(card.loaded,true);
 assert.equal(card.amount(false,true),'444');
});

test('home diary changes pages without requerying and preserves independent source amounts, percentages and order',async()=>{
 const h=harness();h.select();
 const Card=h.load('components/HomeTravelersDiaryCard').HomeTravelersDiaryCard,card=new Card();
 card.currentUid='100000001';card.currentUserId=1;
 const sources=[
  {action_id:7,action:'任务',num:25,percent:60},
  {action_id:2,action:'活动',num:150,percent:15},
  {action_id:9,action:'其他',num:75,percent:25},
 ];
 const data=ledgerData('100000001','cn_gf01',10,123456);
 data.day_data.current_primogems=0;data.day_data.current_mora=0;
 data.month_data.current_mora=98765;data.month_data.group_by=sources;
 h.state.response=async()=>({retcode:0,data});
 card.aboutToAppear();await tick();assert.equal(card.loaded,true);
 assert.equal(card.amount(true,true),'0');assert.equal(card.amount(true,false),'0');
 assert.equal(card.amount(false,true),'123,456');assert.equal(card.amount(false,false),'98,765');
 const ledger=card.vm.ledger;
 for(const page of [1,0,1,0,1,0]){card.selectPage(page);assert.equal(card.pageIndex,page);}
 await tick();
 assert.equal(card.vm.ledger,ledger);assert.equal(card.vm.month,0);
 assert.equal(h.state.sent.length,1);assert.equal(new URL(h.state.sent[0].url).searchParams.get('month'),'0');
 assert.deepEqual(plain(ledger.monthData.groupBy.map(source=>[source.actionId,source.action,source.num,source.percent])),
  sources.map(source=>[source.action_id,source.action,source.num,source.percent]));
});

test('home diary missing daily figures use dashes while an empty source page keeps the month summary available',async()=>{
 const h=harness();h.select();
 const Card=h.load('components/HomeTravelersDiaryCard').HomeTravelersDiaryCard,card=new Card();
 card.currentUid='100000001';card.currentUserId=1;
 const data=ledgerData('100000001','cn_gf01',10,1600);delete data.day_data;
 data.month_data.current_mora=25000;
 h.state.response=async()=>({retcode:0,data});
 card.aboutToAppear();await tick();assert.equal(card.loaded,true);
 assert.equal(card.amount(true,true),'—');assert.equal(card.amount(true,false),'—');
 assert.equal(card.amount(false,true),'1,600');assert.equal(card.amount(false,false),'25,000');
 card.selectPage(1);assert.equal(card.pageIndex,1);assert.equal(card.vm.ledger.monthData.groupBy.length,0);
 assert.equal(card.loaded,true);assert.equal(card.vm.message,'');
 card.selectPage(0);assert.equal(card.pageIndex,0);assert.equal(card.amount(false,true),'1,600');
 assert.equal(card.amount(true,true),'—');await tick();
 assert.equal(h.state.sent.length,1);assert.equal(new URL(h.state.sent[0].url).searchParams.get('month'),'0');
 card.aboutToDisappear();data.month_data.current_primogems=0;data.month_data.current_mora=0;
 card.aboutToAppear();await tick();assert.equal(card.loaded,true);assert.equal(card.pageIndex,0);
 assert.equal(card.amount(false,true),'0');assert.equal(card.amount(false,false),'0');
 assert.equal(card.amount(true,true),'—');card.selectPage(1);
 assert.equal(card.vm.ledger.monthData.groupBy.length,0);card.selectPage(0);
 assert.equal(card.amount(false,true),'0');await tick();assert.equal(h.state.sent.length,2);
});

test('activity calendar signs a CN POST, replays one verified challenge and parses activities and pools',async()=>{
 const h=harness(),user=h.select('500000001');
 const calendar=h.load('service/CalendarService').CalendarService.getInstance();
 const now=Date.parse('2026-11-11T00:00:00Z'),start=now/1000-1800,end=now/1000+1800;
 h.state.riskResult=async()=> 'calendar-challenge';
 h.state.response=async()=>h.state.sent.length===1?{retcode:1034,message:'risk'}:{retcode:0,data:{
  act_list:[{id:1,type:'ActTypeTower',name:'挑战',start_timestamp:start,end_timestamp:end,countdown_seconds:1800,tower_detail:{is_unlock:true,max_star:36,total_star:36}}],
  fixed_act_list:[{id:2,type:'ActTypeSignIn',name:'签到',start_timestamp:start-100,end_timestamp:end,is_finished:true}],
  weapon_card_pool_list:[{pool_id:3,pool_name:'武器祈愿',start_timestamp:start+3600,end_timestamp:end+7200,weapon:[{icon:'https://example.test/weapon.png'}]}]
 }};
 const entries=await calendar.fetchCalendar('500000001');
 assert.deepEqual(plain(entries.map(entry=>entry.name)),['签到','挑战','武器祈愿']);
 assert.equal(entries[0].typeName,'签到');assert.equal(entries[0].statusText(now),'已完成');
 assert.equal(entries[1].statusText(now),'进行中');assert.match(entries[1].progressLine(),/36\/36/);
 assert.equal(entries[2].weaponIcons.length,1);assert.match(entries[2].statusText(now),/后开始/);
 for (const request of h.state.sent) {
  assert.equal(request.url,'https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/act_calendar');
  assert.equal(request.options.method,'POST');assert.equal(request.options.header.Cookie,user.gameRecordCookie());
 }
 assert.deepEqual(JSON.parse(h.state.signatures[1].body),{role_id:'500000001',server:'cn_qd01'});
 assert.notEqual(h.state.sent[0].options.header.DS,h.state.sent[1].options.header.DS);
 assert.equal(h.state.risk[0].path,'https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/hard_challenge');
 assert.equal(h.state.sent[1].options.header['x-rpc-challenge'],'calendar-challenge');
});

test('activity calendar refuses stored overseas roles and drops a request invalidated during signing',async()=>{
 const h=harness(),calendar=h.load('service/CalendarService').CalendarService.getInstance();
 h.select('800000001');
 await assert.rejects(calendar.fetchCalendar('800000001'),/仅支持国服/);
 assert.equal(h.state.sent.length,0);assert.equal(h.state.signatures.length,0);
 const gate=deferred();h.state.signGate=gate.promise;h.select();
 const pending=outcome(calendar.fetchCalendar('100000001'));
 while(!h.state.signatures.length)await tick();
 h.select('500000001',2);gate.resolve();
 assert.match((await pending).error.message,/已改变/);
 assert.equal(h.state.sent.length,0);assert.equal(h.state.risk.length,0);
});

test('home calendar keeps the complete Windows source order and mixed pools render both icon families', async () => {
  const h = harness();
  h.select();
  const { CalendarEntryOrder, CalendarService } = h.load('service/CalendarService');
  const calendar = CalendarService.getInstance();
  const now = Date.parse('2026-11-12T00:00:00Z') / 1000;
  const activity = (id, name, start, end) => ({ id, name, start_timestamp: start, end_timestamp: end });
  const pool = (id, name, start, avatars = [], weapon = []) =>
    ({ pool_id: id, pool_name: name, start_timestamp: start, end_timestamp: now + 10000, avatars, weapon });
  const avatarIcon = 'https://example.test/UI_AvatarIcon_Mitya.png?v=2';
  const weaponIcon = 'https://example.test/UI_EquipIcon_Sword_Regalis.png';
  h.state.response = async () => ({ retcode: 0, data: {
    fixed_act_list: [activity(1, '固定挑战', now - 500, now + 500), activity(2, '固定签到', now - 600, now + 500)],
    act_list: [activity(3, '已排期活动', now + 100, now + 200), activity(4, '待公布活动', 0, 0)],
    avatar_card_pool_list: [pool(31, '角色活动祈愿', now - 100), pool(32, '角色活动祈愿 - 2', now - 100)],
    weapon_card_pool_list: [pool(33, '武器祈愿', now - 200)],
    mixed_card_pool_list: [pool(34, '混池', now - 300, [{ icon: avatarIcon }], [{ icon: weaponIcon }])],
    selected_act_list: [activity(9, '精选入口', 0, 0)],
    selected_avatar_card_pool_list: [pool(39, '精选池', now)],
  } });
  const home = await calendar.fetchCalendar('100000001', undefined, CalendarEntryOrder.Home);
  assert.deepEqual(plain(home.map(entry => entry.name)),
    ['固定挑战', '固定签到', '已排期活动', '待公布活动', '角色活动祈愿', '角色活动祈愿 - 2', '武器祈愿', '混池']);
  assert.equal(home[3].endTime, 0);
  assert.match(home[2].statusText(now * 1000), /后开始/);
  const timeline = await calendar.fetchCalendar('100000001');
  assert.deepEqual(plain(timeline.map(entry => entry.name)),
    ['待公布活动', '固定签到', '固定挑战', '混池', '武器祈愿', '角色活动祈愿', '角色活动祈愿 - 2', '已排期活动']);
  assert.equal(h.state.sent.length, 2, 'each order uses exactly one calendar request');

  const { HomeGachaBannerCard } = h.load('components/HomeGachaBannerCard');
  const banner = new HomeGachaBannerCard();
  banner.pool = home[7];
  assert.deepEqual(plain(banner.upCells().map(cell => [cell.name, cell.url])),
    [['UI_AvatarIcon_Mitya', avatarIcon], ['UI_EquipIcon_Sword_Regalis', weaponIcon]]);
  const bannerSource = fs.readFileSync(path.join(root, 'components/HomeGachaBannerCard.ets'), 'utf8');
  assert.match(bannerSource, /\(cell: UpIconCell, index: number\): string => `\$\{cell\.url\}_\$\{index\}`/);
  const { HomeActBannerCard } = h.load('components/HomeActBannerCard');
  const announcement = new HomeActBannerCard();
  announcement.entry = home[3];
  assert.equal(announcement.hasDates(), false);
  assert.equal(announcement.remainText(), 'app.string.ui_calendar_time_pending');
});

test('CN action ticket keeps the default scope and includes an available fingerprint',async()=>{
 const h=harness(),client=h.load('data/network/HoyolabClient').HoyolabClient;
 const cookie='stuid=42; stoken=fixture',token='fixture+/?';
 await client.getActionTicket(cookie,token,'42');
 await client.getActionTicket(cookie,token,'42','fixture_explicit_scope');
 h.state.deviceFp='';
 await client.getActionTicket(cookie,token,'42','fixture_explicit_scope');
 const requests=h.state.sent.map(request=>({url:new URL(request.url),headers:request.options.header}));
 assert.deepEqual(requests.map(request=>request.url.searchParams.get('action_type')),
  ['game_role','fixture_explicit_scope','fixture_explicit_scope']);
 assert.deepEqual(requests.map(request=>request.headers['x-rpc-device_fp']),['fixture-fp','fixture-fp',undefined]);
 for(const request of requests){
  assert.equal(request.url.origin,'https://api-takumi.mihoyo.com');
  assert.equal(request.url.pathname,'/auth/api/getActionTicketBySToken');
  assert.equal(request.url.searchParams.get('stoken'),token);
  assert.equal(request.url.searchParams.get('uid'),'42');
  assert.equal(request.headers.Cookie,cookie);
  assert.ok(request.headers.DS);
 }
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

test('official announcement groups preserve empty wrappers and their source indices', async () => {
  const h = harness();
  h.state.response = async () => ({ retcode: 0, data: {
    list: [
      { type_id: 2, list: [] },
      { type_id: 1, list: [{ ann_id: 40, title: '活动条目' }] },
      { type_id: 5, list: [] },
    ],
    type_list: [
      { id: 2, mi18n_name: '游戏公告' },
      { id: 1, mi18n_name: '活动公告' },
      { id: 5, mi18n_name: '千星奇域' },
    ],
  } });
  const groups = await h.announcements.fetchGroups('cn_gf01', 55, 'zh-cn');
  assert.deepEqual(plain(groups.map(group => [group.typeId, group.label, group.items.length])),
    [[2, '游戏公告', 0], [1, '活动公告', 1], [5, '千星奇域', 0]]);
  const all = await h.announcements.fetchList('cn_gf01', 55, 'zh-cn');
  assert.deepEqual(plain(all.map(item => [item.id, item.sourceRegion, item.sourceLanguage, item.sourceLevel])),
    [[40, 'cn_gf01', 'zh-cn', 55]]);
  assert.equal(h.state.sent.length, 1, 'flattened consumers reuse the grouped cache');
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

test('typed announcement promises preserve list/body coalescing, rejection cleanup and replacement ownership', async () => {
 for (const kind of ['lists', 'bodies']) {
  const h = harness(), gate = deferred();
  const context = h.Context.create('os_asia', 'en-us', 55), key = context.key();
  const fetch = () => kind === 'lists' ? h.announcements.fetchGroups('os_asia', 55, 'en-us', true)
    : h.announcements.fetchContent(42, 'os_asia', 55, 'en-us');
  h.state.response = async () => { await gate.promise; throw new Error('fixture announced rejection'); };
  const first = outcome(fetch()), second = outcome(fetch());
  assert.equal(h.state.sent.length, 1, kind + ' shares one request');
  assert.equal(h.announcements[kind].size, 1);
  gate.resolve();
  for (const result of await Promise.all([first, second])) assert.match(result.error.message, /网络异常|fixture announced rejection/);
  assert.equal(h.announcements[kind].has(key), false, kind + ' failed request is removed');
  const nextGate = deferred();
  h.state.response = async () => { await nextGate.promise; return { retcode: 0, data: kind === 'lists' ? listData() : { list: [{ ann_id: 42, content: 'fixture body' }] } }; };
  const retry = fetch();
  assert.equal(h.state.sent.length, 2, kind + ' next call starts a fresh request');
  const replacement = Promise.resolve(kind === 'lists' ? [] : new Map());
  h.announcements[kind].set(key, replacement);
  nextGate.resolve(); await retry;
  assert.equal(h.announcements[kind].get(key), replacement, kind + ' older completion does not remove newer owner');
 }
});
