// Actual production page methods + rules/prediction service; only ArkUI, cloud transport and local VM loading are doubles.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const ts=require(process.env.TYPESCRIPT_PATH||'../ci/node_modules/typescript');const root=path.resolve(__dirname,'../entry/src/main/ets');
const source=fs.readFileSync(path.join(root,'pages/GachaLogPage.ets'),'utf8');
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
const flush=async()=>{for(let i=0;i<60;i++)await Promise.resolve();};
function block(start){let depth=0,quote='',comment='';const first=source.indexOf('{',start);for(let i=first;i<source.length;i++){const c=source[i],next=source[i+1];if(comment==='line'){if(c==='\n')comment='';continue;}if(comment==='block'){if(c==='*'&&next==='/'){comment='';i++;}continue;}if(quote){if(c==='\\')i++;else if(c===quote)quote='';continue;}if(c==='/'&&next==='/'){comment='line';i++;continue;}if(c==='/'&&next==='*'){comment='block';i++;continue;}if(c==='\''||c==='"'||c==='`'){quote=c;continue;}if(c==='{')depth++;if(c==='}'&&--depth===0)return source.slice(start,i+1);}throw Error('Unbalanced page block');}
function method(name){const expression=new RegExp('^  (?:private )?(?:static )?(?:async )?'+name+'\\([^]*?\\)(?:: [^{\\n]+)? \\{','m');const match=expression.exec(source);assert.ok(match,name);return block(match.index);}
const history=(type,pity,reset=5)=>Array.from({length:pity+1},(_,i)=>({archiveId:1,gachaType:type,gachaId:String(1000-i),rankType:i===pity?reset:3,count:1}));
function harness(){
 const state={calls:[],cloudLogged:true,revision:0,initGate:undefined,fetchGate:undefined,selectGate:undefined,response:{Distribution:[{Pull:3,Count:10},{Pull:4,Count:20},{Pull:80,Count:70}]}};
 const cloud={async initialize(){if(state.initGate)await state.initGate.promise;},isLoggedIn:()=>state.cloudLogged,getSessionRevision:()=>state.revision,async statistics(kind){state.calls.push(kind);if(state.fetchGate)return state.fetchGate.promise;return state.response;}};
 const modules=new Map();function load(name){if(modules.has(name))return modules.get(name);const output=ts.transpileModule(fs.readFileSync(path.join(root,name+'.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});assert.equal(output.diagnostics.length,0,name);const module={exports:{}};vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`,{Error,Date})(id=>{if(id.endsWith('/HutaoCloudService'))return {HutaoCloudService:{getInstance:()=>cloud}};return load(path.posix.normalize(path.posix.join(path.posix.dirname(name),id)));},module,module.exports);modules.set(name,module.exports);return module.exports;}
 const rules=load('model/GachaPoolRules').GachaPoolRules,types=load('model/GachaType').GachaType;
 const {GachaPrediction:Prediction,GachaPredictionService:Service}=load('service/GachaPredictionService');
 const names=['pityFromHistory','invalidatePrediction','selectPredictionPool','predictionTypes','predictionPoolOptions','currentPity','predictionUnavailableReason','predictionHistoryKey','predictionOwnerMatches','fetchPrediction','predictionIsCurrent','predictionStatusText','predictionPercent','predictionRetrievedText','syncPoolCards','cardKey','resetLocalView','aboutToDisappear','toggleBeyondMode'];
 const declarations=block(source.indexOf('class FiveStarPull'))+'\n'+block(source.indexOf('class PoolCardData'));
 const output=ts.transpileModule(declarations+'\nexport class GachaLogPage{\n'+names.map(method).join('\n')+'\n}',{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});assert.equal(output.diagnostics.length,0,'production page methods');
 const module={exports:{}};vm.runInNewContext(`(function(module,exports){${output.outputText}\n})`,{Error,Date,GachaType:types,GachaPoolRules:rules,GachaPrediction:Prediction,GachaPredictionService:Service,HutaoCloudService:{getInstance:()=>cloud},Logger:{info(){},warn(){}},GACHA_TAG:'host'})(module,module.exports);
 const Page=module.exports.GachaLogPage,target=new Page();
 const model={currentArchiveId:1,currentPoolType:302,gameAccountUid:'',isRefreshing:false,isTransferring:false,items:history(302,2),stats:{pools:[]},invalidateRequests(){},onProgressChanged(){},async selectPool(type){this.currentPoolType=type;if(state.selectGate)await state.selectGate.promise;this.items=history(type,2);}};
 Object.assign(target,{vm:model,pageActive:true,pageEpoch:1,isLoggedIn:false,beyondMode:false,prediction:new Prediction(),predictionLoading:false,predictionMessage:'idle',predictionRequest:0,predictionArchiveId:0,predictionSessionRevision:-1,poolSelectionRequest:0,poolSelectionLoading:false,historyGeneration:0,historyLoading:false,historyWishes:[],showImportPreview:false,showExportOptions:false,poolCards:[],poolRows:[],charCounts:[],weaponCounts:[],historySource:{notifyDataReload(){}},rebuildPoolRows(){},syncAll(){this.setPool(this.vm.currentPoolType,2);}});
 target.setPool=(type,pity,rows=history(type,pity))=>{model.currentPoolType=type;model.items=rows;target.poolCards=[{gachaType:type,sinceLastFive:pity,sinceLastFour:0,fivePityKnown:Page.pityFromHistory(rows,type,5)===pity,fourPityKnown:false,isCurrent:true}];};target.setPool(302,2);
 return {state,target,Page,model,Service,Prediction,rules};
}
(async()=>{
 await test('render helpers and pool selection never fetch; one explicit action produces bounded empirical probabilities',async()=>{
  const {state,target}=harness();target.currentPity();target.predictionUnavailableReason();target.predictionPoolOptions();target.predictionIsCurrent();target.predictionStatusText();assert.equal(state.calls.length,0);
  await target.selectPredictionPool(302);assert.equal(state.calls.length,0);await target.fetchPrediction();assert.deepEqual(state.calls,['weaponDistribution']);assert.equal(target.prediction.available,true);assert.equal(target.prediction.nextProbability,.1);assert.equal(target.prediction.predictedRemaining,78);assert.equal(target.prediction.sampleEvents,100);assert.equal(target.prediction.remainingEvents,100);assert.ok(target.predictionIsCurrent());assert.equal(target.isLoggedIn,false,'cloud auth is independent of game login');
 });
 await test('repeat clicks share the visible in-flight lock and unavailable/zero-tail data stays unavailable',async()=>{
  const {state,target}=harness();const gate=deferred();state.fetchGate=gate;const first=target.fetchPrediction();await flush();await target.fetchPrediction();assert.equal(state.calls.length,1);assert.equal(target.predictionLoading,true);gate.resolve({Distribution:[{Pull:1,Count:2}]});await first;assert.equal(target.predictionLoading,false);assert.equal(target.prediction.available,false);assert.match(target.predictionMessage,/没有可用样本/);
 });
 await test('missing/reset-free/unknown-quality/mixed or out-of-range history never falls back to role pity',async()=>{
  const {state,target,Page}=harness();
  for(const rows of [[],history(302,3).slice(0,3),history(302,80),history(302,2).map((r,i)=>i===0?{...r,rankType:0}:r),history(301,2),history(302,2).reverse(),history(302,2).map(r=>({...r,gachaId:'9'.repeat(129)}))]){target.setPool(302,2,rows);assert.equal(target.currentPity(),-1);await target.fetchPrediction();}
  target.poolCards=[{gachaType:301,sinceLastFive:20,fivePityKnown:true}];assert.equal(target.currentPity(),-1);await target.fetchPrediction();assert.equal(state.calls.length,0);
  assert.equal(Page.pityFromHistory(history(302,79),302,5),79);assert.equal(Page.pityFromHistory(history(301,89),301,5),89);assert.equal(Page.pityFromHistory(history(1000,89,4),1000,4),89);assert.equal(Page.pityFromHistory(history(1000,0),1000,5),-1);
 });
 await test('all finite bounds come from pool rules and only the selected verified pool gets countdown certainty',()=>{
  const {target,model}=harness();model.stats.pools=[{gachaType:302,typeName:'weapon',totalCount:3,fiveStarCount:1,fourStarCount:0,sinceLastFive:2,sinceLastFour:3,fiveDetails:[],averageOrangePull:3},{gachaType:301,typeName:'avatar',totalCount:5,fiveStarCount:1,fourStarCount:0,sinceLastFive:4,sinceLastFour:5,fiveDetails:[],averageOrangePull:5}];target.syncPoolCards();assert.equal(target.poolCards[0].fivePityKnown,true);assert.equal(target.poolCards[1].fivePityKnown,false);
  const key=target.poolCards[0].key;model.items[0].rankType=0;target.syncPoolCards();assert.equal(target.poolCards[0].fivePityKnown,false);assert.notEqual(target.poolCards[0].key,key,'confidence-only changes invalidate reused rows');
  assert.doesNotMatch(source,/ORANGE_GUARANTEE|PURPLE_GUARANTEE|predictFive|pullFiveRate|0\.006|74 抽软保底/);assert.match(source,/GachaPoolRules\.fiveStarThreshold\(card\.gachaType\)/);assert.match(source,/GachaPoolRules\.fourStarThreshold\(card\.gachaType\)/);assert.match(source,/选择该池后校验历史/);
 });
 await test('pool/archive/page/game-login/history changes cannot publish an old distribution or unlock a newer request',async()=>{
  for(const change of [(p,m)=>{m.currentPoolType=301;},(p,m)=>{m.currentArchiveId=2;},p=>{p.pageEpoch++;},p=>{p.isLoggedIn=true;},(p,m)=>{m.gameAccountUid='100000001';},(p,m)=>{m.items=m.items.map((r,i)=>({...r,gachaId:String(2000-i)}));},p=>p.aboutToDisappear()]){
   const {state,target,model}=harness();const gate=deferred();state.fetchGate=gate;const pending=target.fetchPrediction();await flush();change(target,model);gate.resolve(state.response);await pending;assert.equal(target.prediction.available,false);
  }
  const {state,target}=harness();const old=deferred();state.fetchGate=old;const first=target.fetchPrediction();await flush();target.invalidatePrediction();target.setPool(301,2);const current=deferred();state.fetchGate=current;const second=target.fetchPrediction();await flush();old.resolve({Distribution:[{Pull:80,Count:1}]});await first;assert.equal(target.predictionLoading,true);current.resolve({Distribution:[{Pull:90,Count:1}]});await second;assert.equal(target.prediction.poolType,301);assert.equal(target.predictionLoading,false);
 });
 await test('cloud session initialization/logout/relogin is guarded separately from natural token refresh',async()=>{
  const a=harness();a.state.cloudLogged=false;await a.target.fetchPrediction();assert.equal(a.state.calls.length,0);assert.match(a.target.predictionMessage,/胡桃云通行证/);
  const b=harness();const init=deferred();b.state.initGate=init;const before=b.target.fetchPrediction();b.target.pageEpoch++;init.resolve();await before;assert.equal(b.state.calls.length,0);
  for(const logout of [state=>{state.cloudLogged=false;state.revision++;},state=>{state.revision+=2;}]){const {state,target}=harness();const gate=deferred();state.fetchGate=gate;const pending=target.fetchPrediction();await flush();logout(state);gate.resolve(state.response);await pending;assert.equal(target.prediction.available,false);assert.match(target.predictionMessage,/云登录状态已变化/);}
  const c=harness();await c.target.fetchPrediction();assert.equal(c.target.predictionIsCurrent(),true);c.state.revision++;assert.equal(c.target.predictionIsCurrent(),false);assert.match(c.target.predictionStatusText(),/已变化/);
 });
 await test('retrieval time and actual sample denominators are labeled honestly and exceptional errors stay redacted',async()=>{
  const {state,target}=harness();const failed=deferred();state.fetchGate=failed;const pending=target.fetchPrediction();await flush();failed.reject(Error('fixture-secret-token'));await pending;assert.equal(target.prediction.available,false);assert.doesNotMatch(target.predictionMessage,/fixture-secret/);
  state.fetchGate=undefined;await target.fetchPrediction();assert.match(target.predictionRetrievedText(),/UTC；不是样本采集日期/);assert.ok(target.prediction.conditional.length<=80);assert.match(source,/云分布样本：/);assert.match(source,/垫数之后的条件样本/);assert.match(source,/不是理论概率、未来结果保证或指定 UP 概率/);
  assert.doesNotMatch(method('predictionPanel'),/fetchPrediction\(\)(?!\))/);assert.match(method('predictionPanel'),/\.onClick\(\(\) => this\.fetchPrediction\(\)\)/);
 });
 await test('pool switching is owner-fenced and a bounded primitive history key replaces any full-array request capture',async()=>{
  const {state,target,model}=harness();const gate=deferred();state.selectGate=gate;const pending=target.selectPredictionPool(301);assert.equal(target.poolSelectionLoading,true);await target.fetchPrediction();assert.equal(state.calls.length,0);target.aboutToDisappear();gate.resolve();await pending;assert.equal(target.prediction.available,false);
  assert.doesNotMatch(method('fetchPrediction'),/const items: GachaItem\[\]/);assert.match(method('fetchPrediction'),/const historyKey: string/);
 });
})().catch(error=>{console.error(error);process.exitCode=1;});
