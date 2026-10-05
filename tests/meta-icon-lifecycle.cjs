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
let failMkdir=false;let shortWrite=false;let stagingId=0;const disk=new Set();
const mocks={
 '@kit.CoreFileKit':{fileUri:{getUriFromPath:p=>'uri:'+p},fileIo:{OpenMode:{READ_WRITE:1,CREATE:2,TRUNC:4},accessSync:p=>disk.has(p),mkdirSync:p=>{dirs.push(p);if(failMkdir){failMkdir=false;throw Error('missing parent')}},openSync:p=>({fd:p}),writeSync:(fd,b)=>{writes.push({fd,b});disk.add(fd);return shortWrite ? 1 : b.byteLength},closeSync(){},mkdtempSync:p=>p.replace('XXXXXX',String(++stagingId)),renameSync:(from,to)=>{assert(disk.has(from));disk.delete(from);disk.add(to)},rmdirSync:p=>{for(const f of disk)if(f.startsWith(p+'/'))disk.delete(f)}}},
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
 failMkdir=true;raws[4].resolve(new Uint8Array([9,1,2,3,9]).subarray(1,4));await flush();assert.equal(x.src,'uri:/sandbox/cache/rawicons/AvatarIcon/fifth.png');assert(dirs.every(p=>p.startsWith('/')),'mkdir fallback must retain absolute sandbox root');assert.equal(writes.length,1);assert.deepEqual([...new Uint8Array(writes[0].b)],[1,2,3]);
 x.name='sixth';x.onMetaChanged();raws[5].reject(Error('missing'));await flush();cdns[2].reject(Error('network'));await flush();
 const y=new C();y.category='AvatarIcon';y.name='detached-success';y.aboutToAppear();const raw=raws.at(-1);y.aboutToDisappear();raw.resolve(new Uint8Array([4]));await flush();assert.equal(writes.length,1,'detached raw success must not write');
 const z=new C();z.category='../escape';z.name='item';const count=raws.length;z.aboutToAppear();assert.equal(raws.length,count);assert.equal(z.src,'');z.category='AvatarIcon';z.name='../escape';z.onMetaChanged();assert.equal(raws.length,count);z.name='https://example.com/icon.png';z.onMetaChanged();assert.equal(z.src,z.name);
 const a=new C();a.category='AvatarIcon';a.name='race';a.aboutToAppear();const one=raws.at(-1);const b=new C();b.category=a.category;b.name=a.name;b.aboutToAppear();const two=raws.at(-1);one.resolve(new Uint8Array([1]));await flush();two.reject(Error('temporary'));await flush();const c=new C();c.category=a.category;c.name=a.name;const before=raws.length;c.aboutToAppear();assert.equal(c.src,'uri:/sandbox/cache/rawicons/AvatarIcon/race.png');assert.equal(raws.length,before);
 disk.delete('/sandbox/cache/rawicons/AvatarIcon/race.png');c.onMetaChanged();assert.equal(raws.length,before+1,'evicted cache must reread');raws.at(-1).reject(Error('temporary'));await flush();c.onMetaChanged();assert.equal(raws.length,before+2,'transient failure must not be permanently memoized');raws.at(-1).resolve(new Uint8Array([2]));await flush();
 const preserved='/sandbox/cache/rawicons/AvatarIcon/existing.png';disk.add(preserved);shortWrite=true;assert.throws(()=>C.writeCache(preserved,new Uint8Array([1,2,3])),/Incomplete/);assert(disk.has(preserved));assert(![...disk].some(p=>p.includes('.stage-')),'owned temporary files cleaned');shortWrite=false;
 assert.match(original,/@Prop @Watch\('onMetaChanged'\) remoteFallback/);
 assert(!original.includes('Logger.info(META_TAG'));
 assert(!original.match(/aboutToDisappear\(\): void \{[^}]*this\.src/s));
 console.log('PASS: MetaIcon replace/detach/stale fallback/rejection/file URI/absolute cache path');
})().catch(e=>{console.error(e);process.exitCode=1});
