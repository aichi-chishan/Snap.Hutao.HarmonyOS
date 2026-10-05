// Execute real non-rendering component methods; native I/O and decorators are deterministic doubles.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const original = fs.readFileSync('entry/src/main/ets/components/MetaIcon.ets', 'utf8');
let source = original.replace('@Component\n', '').replace('export struct MetaIcon', 'export class MetaIcon');
source = source.slice(0, source.indexOf('  build() {')) + '}';
const code = ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}}).outputText;
const deferred = () => { let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}; };
const raws=[],cdns=[],packs=[],dirs=[],writes=[];
let failMkdir=false;
const mocks={
 '@kit.CoreFileKit':{fileUri:{getUriFromPath:p=>'uri:'+p},fileIo:{OpenMode:{READ_WRITE:1,CREATE:2,TRUNC:4},accessSync:()=>false,mkdirSync:p=>{dirs.push(p);if(failMkdir){failMkdir=false;throw Error('missing parent')}},openSync:p=>({fd:p}),writeSync:(fd,b)=>writes.push({fd,b}),closeSync(){}}},
 ResourcePackService:{ResourcePackService:{ensure:()=>{const d=deferred();packs.push(d);return d.promise}}},
 StandardIconService:{StandardIconService:{ensure:()=>{const d=deferred();cdns.push(d);return d.promise}}},
 GameDataService:{GameDataService:{getInstance:()=>({readIcon:()=>''})}},
 AppContext:{AppContextProvider:{getCacheDir:()=>'/sandbox/cache',getResourceManager:()=>({getRawFileContent:()=>{const d=deferred();raws.push(d);return d.promise}})}},
 Logger:{Logger:{warn(){},error(){}}}
};
const m={exports:{}};
vm.runInNewContext(`(function(require,module,exports){${code}\n})`,{Prop:()=>{},State:()=>{},Watch:()=>()=>{}})(n=>mocks[n]||mocks[n.split('/').pop()],m,m.exports);
const C=m.exports.MetaIcon;
const flush=async()=>{for(let i=0;i<20;i++)await Promise.resolve()};
(async()=>{
 const x=new C();x.category='AvatarIcon';x.name='first';x.remoteFallback=true;x.aboutToAppear();
 assert.equal(raws.length,1);x.src='old';x.name='second';x.onMetaChanged();assert.equal(x.src,'');
 raws[0].reject(Error('missing'));await flush();assert.equal(cdns.length,0,'stale miss must not start CDN');
 x.aboutToDisappear();raws[1].reject(Error('missing'));await flush();assert.equal(cdns.length,0,'detached miss must not start CDN');assert.equal(x.src,'');
 x.name='third';x.aboutToAppear();raws[2].reject(Error('missing'));await flush();assert.equal(cdns.length,1);
 x.aboutToDisappear();cdns[0].resolve('');await flush();assert.equal(packs.length,0,'detached CDN must not start next fallback');
 x.name='fourth';x.aboutToAppear();raws[3].reject(Error('missing'));await flush();cdns[1].resolve('');await flush();assert.equal(packs.length,1);
 x.name='fifth';x.onMetaChanged();packs[0].resolve('/old.png');await flush();assert.equal(x.src,'','stale remote result must not overwrite new image');
 failMkdir=true;raws[4].resolve(new Uint8Array([1,2,3]));await flush();assert.equal(x.src,'uri:/sandbox/cache/rawicons/AvatarIcon/fifth.png');assert(dirs.every(p=>p.startsWith('/')),'mkdir fallback must retain absolute sandbox root');assert.equal(writes.length,1);
 x.name='sixth';x.onMetaChanged();raws[5].reject(Error('missing'));await flush();cdns[2].reject(Error('network'));await flush();
 assert.match(original,/@Prop @Watch\('onMetaChanged'\) remoteFallback/);
 assert(!original.includes('Logger.info(META_TAG'));
 assert(!original.match(/aboutToDisappear\(\): void \{[^}]*this\.src/s));
 console.log('PASS: MetaIcon replace/detach/stale fallback/rejection/file URI/absolute cache path');
})().catch(e=>{console.error(e);process.exitCode=1});
