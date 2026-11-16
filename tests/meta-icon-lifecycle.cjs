// Execute the real component, including build() and its Image.onError closure.
// Native I/O, decorators, and ArkUI node creation are deterministic doubles; this is not device rendering QA.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const original = fs.readFileSync('entry/src/main/ets/components/MetaIcon.ets', 'utf8');
let source = original.replace('@Component\n', '').replace('export struct MetaIcon', 'export class MetaIcon');
const compiled = ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true},reportDiagnostics:true});
assert.equal(compiled.diagnostics.filter(d=>d.category===ts.DiagnosticCategory.Error).length,0,'production build fixture must parse');
const code = compiled.outputText;
const deferred = () => { let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}; };
const raws=[],cdns=[],packs=[],dirs=[],writes=[],accesses=[];
let failMkdir=false;let shortWrite=false;let stagingId=0;let remoteIcon='';let onMkdir=()=>{};const disk=new Set();
let bundleUpdateTime=100;let bundleReads=0;
const mocks={
 '@kit.AbilityKit':{bundleManager:{BundleFlag:{GET_BUNDLE_INFO_DEFAULT:0},async getBundleInfoForSelf(){bundleReads++;return {versionCode:7,updateTime:bundleUpdateTime}}}},
 '@kit.CoreFileKit':{fileUri:{getUriFromPath:p=>'uri:'+p},fileIo:{
  OpenMode:{WRITE_ONLY:1,CREATE:2,NOFOLLOW:4},
  async access(p){accesses.push(p);return disk.has(p)},
  async mkdir(p,recursive){assert.equal(recursive,true);dirs.push(p);onMkdir();if(failMkdir){failMkdir=false;throw Error('existing directory')}},
  async stat(p){return {isDirectory:()=>dirs.includes(p)}},
  async open(p){return {fd:p}},
  async write(fd,b){writes.push({fd,b});disk.add(fd);return shortWrite ? 1 : b.byteLength},
  async close(){},
  async mkdtemp(p){return p.replace('XXXXXX',String(++stagingId))},
  async rename(from,to){assert(disk.has(from));disk.delete(from);disk.add(to)},
  async rmdir(p){for(const f of disk)if(f.startsWith(p+'/'))disk.delete(f)}
 }},
 ResourcePackService:{ResourcePackService:{ensure:()=>{const d=deferred();packs.push(d);return d.promise}}},
 StandardIconService:{StandardIconService:{ensure:()=>{const d=deferred();cdns.push(d);return d.promise}}},
 GameDataService:{GameDataService:{getInstance:()=>({readIcon:()=>remoteIcon})}},
 AppContext:{AppContextProvider:{getCacheDir:()=>'/sandbox/cache',getResourceManager:()=>({getRawFileContent:()=>{const d=deferred();raws.push(d);return d.promise}})}},
 Logger:{Logger:{warn(){},error(){}}}
};
const rendered=[];
let nodeKey;
const makeNode=(kind,source)=>{
 const node={kind,source,key:nodeKey};
 const chain={};
 for(const method of ['width','height','objectFit','borderRadius','autoResize','draggable','onError','backgroundColor']){
  chain[method]=value=>{node[method]=value;return chain};
 }
 rendered.push(node);
 return chain;
};
function loadComponent(){
 const m={exports:{}};
 vm.runInNewContext(`(function(require,module,exports){${code}\n})`,{
  Prop:()=>{},State:()=>{},Watch:()=>()=>{},
  Image:src=>makeNode('Image',src),Column:()=>makeNode('Column'),$r:name=>name,
  ImageFit:{Cover:'Cover',Contain:'Contain'},
  ForEach:(frames,render,key)=>{for(const frame of frames){nodeKey=key(frame);render(frame)}nodeKey=undefined}
 })(n=>mocks[n]||mocks[n.split('/').pop()],m,m.exports);
 return m.exports.MetaIcon;
}
const C=loadComponent();
const flush=()=>new Promise(resolve=>setImmediate(resolve));
const render=x=>{rendered.length=0;x.build();assert.equal(rendered.length,1);return rendered[0]};
const expectImage=x=>{const node=render(x);assert.equal(node.kind,'Image');assert.equal(typeof node.onError,'function');assert.equal(node.autoResize,true);return node};
// 缺图占位必须是中性主题色：曾用 app.color.page_background，深色主题下即纯黑（真机显示为黑块）。
const expectMissing=x=>{assert.equal(x.src,'');const node=render(x);assert.equal(node.kind,'Column');assert.equal(node.backgroundColor,'app.color.icon_placeholder');assert.equal(node.width,x.iconSize);assert.equal(node.height,x.iconSize)};
(async()=>{
 const x=new C();x.category='AvatarIcon';x.name='first';x.remoteFallback=true;x.aboutToAppear();
 await flush();assert.equal(raws.length,1);x.src='old';x.name='second';x.onMetaChanged();assert.equal(x.src,'');
 raws[0].reject(Error('missing'));await flush();assert.equal(cdns.length,0,'stale miss must not start CDN');
 x.aboutToDisappear();raws[1].reject(Error('missing'));await flush();assert.equal(cdns.length,0,'detached miss must not start CDN');assert.equal(x.src,'');
 x.name='third';x.aboutToAppear();await flush();raws[2].reject(Error('missing'));await flush();assert.equal(cdns.length,1);
 x.aboutToDisappear();cdns[0].resolve('');await flush();assert.equal(packs.length,0,'detached CDN must not start next fallback');
 x.name='fourth';x.aboutToAppear();await flush();raws[3].reject(Error('missing'));await flush();cdns[1].resolve('');await flush();assert.equal(packs.length,1);
 x.name='fifth';x.onMetaChanged();packs[0].resolve('/old.png');await flush();assert.equal(x.src,'','stale remote result must not overwrite new image');
 failMkdir=true;raws[4].resolve(new Uint8Array([9,1,2,3,9]).subarray(1,4));await flush();assert.equal(x.src,'uri:/sandbox/cache/rawicons/7-100/AvatarIcon/fifth.png');assert(dirs.every(p=>p.startsWith('/')),'mkdir fallback must retain absolute sandbox root');assert.equal(writes.length,1);assert.deepEqual([...new Uint8Array(writes[0].b)],[1,2,3]);
 x.name='sixth';x.onMetaChanged();await flush();raws[5].reject(Error('missing'));await flush();cdns[2].reject(Error('network'));await flush();
 const y=new C();y.category='AvatarIcon';y.name='detached-success';y.aboutToAppear();await flush();const raw=raws.at(-1);y.aboutToDisappear();raw.resolve(new Uint8Array([4]));await flush();assert.equal(writes.length,1,'detached raw success must not write');
 const z=new C();z.category='../escape';z.name='item';const count=raws.length;z.aboutToAppear();assert.equal(raws.length,count);assert.equal(z.src,'');z.category='AvatarIcon';z.name='../escape';z.onMetaChanged();assert.equal(raws.length,count);z.name='https://example.com/icon.png';z.onMetaChanged();assert.equal(z.src,z.name);
 const a=new C();a.category='AvatarIcon';a.name='race';
 const b=new C();b.category=a.category;b.name=a.name;
 const beforeRace=raws.length, writesBeforeRace=writes.length, accessBeforeRace=accesses.length;
 a.aboutToAppear();b.aboutToAppear();await flush();
 assert.equal(raws.length,beforeRace+1,'concurrent components share a rawfile read');
 assert.equal(accesses.length,accessBeforeRace+1,'concurrent components share the disk existence check');
 a.aboutToDisappear();raws.at(-1).resolve(new Uint8Array([1]));await flush();
 const racePath='/sandbox/cache/rawicons/7-100/AvatarIcon/race.png';
 assert.equal(a.src,'');assert.equal(b.src,`uri:${racePath}`);
 assert.equal(writes.length,writesBeforeRace+1,'one remaining subscriber publishes once');
 const c=new C();c.category=b.category;c.name=b.name;
 const before=raws.length;c.aboutToAppear();await flush();assert.equal(c.src,`uri:${racePath}`);assert.equal(raws.length,before);
 disk.delete(racePath);c.onMetaChanged();await flush();assert.equal(raws.length,before+1,'evicted cache must reread');
 raws.at(-1).reject(Error('temporary'));await flush();c.onMetaChanged();await flush();
 assert.equal(raws.length,before+2,'transient failure must not be permanently memoized');
 raws.at(-1).resolve(new Uint8Array([2]));await flush();

 remoteIcon='file://verified/new.png';c.onMetaChanged();
 assert.equal(c.src,remoteIcon,'verified cohort takes precedence over a warm rawfile path');remoteIcon='';
 assert.equal(bundleReads,1,'bundle revision is read once per process');
 bundleUpdateTime=200;
 const Upgraded=loadComponent();const upgraded=new Upgraded();upgraded.category=b.category;upgraded.name=b.name;
 upgraded.aboutToAppear();await flush();assert.equal(raws.length,before+3,'reinstallation at the same version code reads new bundle assets');
 raws.at(-1).resolve(new Uint8Array([3]));await flush();
 assert.equal(upgraded.src,'uri:/sandbox/cache/rawicons/7-200/AvatarIcon/race.png');
 assert.ok(disk.has(racePath),'an upgrade leaves earlier cache paths for OS eviction');

 const preserved='/sandbox/cache/rawicons/7-100/AvatarIcon/existing.png';disk.add(preserved);shortWrite=true;await assert.rejects(C.writeCache(preserved,new Uint8Array([1,2,3]),()=>true),/Incomplete/);assert(disk.has(preserved));assert(![...disk].some(p=>p.includes('.stage-')),'owned temporary files cleaned');shortWrite=false;
 // Execute the actual build closure, not a test-only copy of the ownership guard.
 const image=new C();image.name='file://user/portrait.png';disk.add(image.name);image.aboutToAppear();
 const first=expectImage(image);assert.equal(first.width,32);assert.equal(first.height,32);assert.equal(first.objectFit,'Contain');
 image.name='https://example.com/new.png';image.onMetaChanged();const second=expectImage(image);
 assert.notEqual(first.key,second.key,'source replacement must own another native Image node');
 first.onError();assert.equal(image.src,second.source,'late old-source decode error must not clear replacement');
 second.onError();expectMissing(image);second.onError();expectMissing(image);
 image.onMetaChanged();const retry=expectImage(image);assert.notEqual(retry.key,second.key,'same-URI retry must not reuse the failed Image node');
 second.onError();assert.equal(image.src,retry.source,'late callback from same-URI prior attempt must be ignored');
 // Layout changes must keep source resolution but replace frame identity before receiving old errors.
 const beforeResize=raws.length+cdns.length+packs.length;
 const tokenBeforeResize=image.resolveToken;
 image.iconSize=64;image.onRenderChanged();const resized=expectImage(image);
 assert.equal(image.resolveToken,tokenBeforeResize,'layout change must not restart pending I/O');
 assert.equal(resized.width,64);assert.equal(resized.height,64);assert.notEqual(resized.key,retry.key);
 retry.onError();assert.equal(image.src,resized.source,'old-size callback must not clear new-size frame within the same resolution');
 image.iconSize=32;image.onRenderChanged();const shrunk=expectImage(image);assert.notEqual(shrunk.key,retry.key,'A/B/A size changes must never reuse an old frame key');
 resized.onError();retry.onError();assert.equal(image.src,shrunk.source);
 image.circular=true;image.onRenderChanged();const circle=expectImage(image);
 assert.equal(circle.objectFit,'Cover');assert.equal(circle.borderRadius,16);shrunk.onError();assert.equal(image.src,circle.source);
 assert.equal(raws.length+cdns.length+packs.length,beforeResize,'size and crop changes must not read or fetch images again');
 image.aboutToDisappear();circle.onError();assert.equal(image.src,circle.source,'detached callbacks must not mutate state');
 image.iconSize=48;image.onRenderChanged();assert.equal(image.frames[0].id,Number(circle.key),'detached layout watches must not publish');
 image.aboutToAppear();const remounted=expectImage(image);assert.equal(remounted.width,48);assert.notEqual(remounted.key,circle.key);
 circle.onError();assert.equal(image.src,remounted.source,'previous mount cannot clear an identical URI after reattachment');
 image.remoteFallback=true;image.onMetaChanged();const toggled=expectImage(image);remounted.onError();assert.equal(image.src,toggled.source);
 image.name='awaiting_raw';image.onMetaChanged();toggled.onError();expectMissing(image);
 await flush();
 const pending=raws.at(-1);image.iconSize=80;image.onRenderChanged();assert.equal(raws.at(-1),pending,'resize during resolution must preserve the pending operation');
 pending.resolve(new Uint8Array([1,2,3]));await flush();const local=expectImage(image);assert.equal(local.width,80);
 const filesBeforeDecodeError=[...disk].sort();const rawBeforeRetry=raws.length;
 local.onError();expectMissing(image);assert.deepEqual([...disk].sort(),filesBeforeDecodeError,'decode failures must not delete user or cache files');
 image.onMetaChanged();await flush();const cachedRetry=expectImage(image);assert.notEqual(cachedRetry.key,local.key);assert.equal(raws.length,rawBeforeRetry,'decode failure must not evict or rewrite the shared cache');
 local.onError();assert.equal(image.src,cachedRetry.source);
 image.name='';image.onMetaChanged();cachedRetry.onError();expectMissing(image);
 // Both direct URI families and updated metadata sources reach the existing missing placeholder.
 for(const name of ['file://user/portrait.png','https://example.com/corrupt.png','http://example.com/corrupt.png']){
  image.name=name;image.onMetaChanged();expectImage(image).onError();expectMissing(image);
 }
 assert(disk.has('file://user/portrait.png'));
 remoteIcon='file://downloaded/update.png';image.name='updated_metadata';image.onMetaChanged();assert.equal(expectImage(image).source,remoteIcon);expectImage(image).onError();expectMissing(image);remoteIcon='';
 for(const usePack of [false,true]){
  image.name=usePack?'corrupt_pack':'corrupt_cdn';image.onMetaChanged();await flush();raws.at(-1).reject(Error('missing'));await flush();
  cdns.at(-1).resolve(usePack?'':'/remote/corrupt.png');await flush();
  if(usePack){packs.at(-1).resolve('/pack/corrupt.png');await flush()}
  expectImage(image).onError();expectMissing(image);
 }
 // Cancel exactly at the asynchronous directory-creation boundary, before cache publication.
 const cancelled=new C();cancelled.name='cancel_during_directory';cancelled.aboutToAppear();await flush();const writesBeforeCancel=writes.length;
 onMkdir=()=>cancelled.aboutToDisappear();raws.at(-1).resolve(new Uint8Array([7,8]));await flush();onMkdir=()=>{};
 assert.equal(writes.length,writesBeforeCancel,'detach during directory creation must stop cache writes');assert.equal(cancelled.src,'');
 assert.match(original,/@Prop @Watch\('onMetaChanged'\) remoteFallback/);
 assert.match(original,/@Prop @Watch\('onRenderChanged'\) iconSize/);
 assert.match(original,/@Prop @Watch\('onRenderChanged'\) circular/);
 assert(!original.includes('.sourceSize('),'native autoResize must handle density/aspect instead of forcing a square decode');
 assert(!original.includes('Logger.info(META_TAG'));
 assert.doesNotMatch(original,/fileIo\.\w+Sync\(/);
 assert(!original.match(/aboutToDisappear\(\): void \{[^}]*this\.src/s));
 console.log('PASS: MetaIcon async shared read/write, package revision, retries, lifecycle ownership and native autoResize');
})().catch(e=>{console.error(e);process.exitCode=1});
