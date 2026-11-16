// Execute the weapon page's real artwork resolver and native Image error callbacks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/pages/WikiWeaponPage.ets','utf8').replaceAll('\r\n','\n');
const prefix = source.slice(0,source.indexOf('\n@Entry\n')).replace('@Component\n','')
  .replace('struct WikiWeaponArt','export class WikiWeaponArt')
  // Strip only the ArkUI container block grammar; resolver and Image callbacks stay unchanged.
  .replace('Stack() {','Stack(); {').replace("}.width('100%').height('100%')",'}');
const output = ts.transpileModule(prefix,{reportDiagnostics:true,
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}});
assert.equal(output.diagnostics.length,0);
const deferred=()=>{let resolve;const promise=new Promise(done=>resolve=done);return{promise,resolve};};
const flush=async()=>{for(let i=0;i<8;i++)await Promise.resolve();};
function harness(){
  const requests=[],rendered=[],fallbacks=[];
  const chain={width(){return this},height(){return this},objectFit(){return this},onError(callback){rendered.at(-1).onError=callback;return this}};
  const mocks={
    '@kit.CoreFileKit':{fileUri:{getUriFromPath:path=>'file://'+path}},
    '../data/remote/StandardIconService':{StandardIconService:{ensure(category,name){const gate=deferred();requests.push({category,name,...gate});return gate.promise;}}},
    '../components/MetaIcon':{MetaIcon:options=>fallbacks.push(options)},
  };
  const module={exports:{}};
  vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`,{
    State:()=>{},Prop:()=>{},Watch:()=>()=>{},
    Stack:()=>chain,Image:source=>{rendered.push({source});return chain},ImageFit:{Contain:'Contain'},
    ForEach:(frames,render,key)=>{for(const frame of frames){assert.equal(typeof key(frame),'string');render(frame)}},
  })(name=>{assert(mocks[name],name);return mocks[name]},module,module.exports);
  return{art:new module.exports.WikiWeaponArt(),requests,rendered,fallbacks};
}
(async()=>{
  await test('weapon art uses the actual Windows CDN category and cannot publish an older weapon or a detached result',async()=>{
    const{art,requests,rendered,fallbacks}=harness();
    art.icon='UI_EquipIcon_Bow_Alkonost';art.aboutToAppear();art.build();
    assert.equal(fallbacks[0].name,art.icon);assert.equal(requests[0].category,'GachaEquipIcon');
    assert.equal(requests[0].name,'UI_Gacha_EquipIcon_Bow_Alkonost');
    art.icon='UI_EquipIcon_Sword_Dvalin';const next=art.resolve();
    requests[0].resolve('/cache/bow.png');await flush();assert.equal(art.sources.length,0);
    requests[1].resolve('/cache/sword.png');await next;art.build();assert.equal(rendered[0].source,'file:///cache/sword.png');
    const pending=art.resolve();art.aboutToDisappear();requests[2].resolve('/cache/detached.png');await pending;
    assert.equal(art.sources.length,0);
  });
  await test('missing or undecodable large art keeps the packaged icon; an old error cannot clear a new render of the same file',async()=>{
    const{art,requests,rendered,fallbacks}=harness();art.icon='UI_EquipIcon_Bow_Alkonost';art.aboutToAppear();
    requests[0].resolve('/cache/bow.png');await flush();art.build();const oldError=rendered[0].onError;
    const retry=art.resolve();requests[1].resolve('/cache/bow.png');await retry;art.build();oldError();
    assert.equal(art.sources.length,1);rendered[1].onError();assert.equal(art.sources.length,0);
    art.build();assert.equal(fallbacks.at(-1).category,'EquipIcon');
    const missing=art.resolve();requests[2].resolve('');await missing;assert.equal(art.sources.length,0);
    art.icon='../untrusted';await art.resolve();assert.equal(requests.length,3);
  });
})().catch(error=>{console.error(error);process.exitCode=1;});
