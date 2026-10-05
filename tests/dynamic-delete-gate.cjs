const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {spawnSync}=require('node:child_process');
const {compilers,inspectSource,checkProject}=require('../ci/check-dynamic-delete.cjs');
const parsers=compilers();
const valid=[
  'delete obj.key;', 'delete obj["key"];', "delete obj['de\\u006cete'];", 'delete obj[7];', 'delete obj[-1];',
  'delete obj[(-1)];', 'delete obj[("key")];', 'delete obj?.[7];',
  'const text="delete obj[key]"; const regex=/delete obj[key]/; // delete obj[key]\n',
  'obj.delete(key);', 'class Valid { value = Math.max(1,2); remove(){delete this.value;} }',
  'delete (()=>obj[key])();'
];
const invalid=[
  'delete obj[key];', 'delete obj[key.toUpperCase()];', 'delete obj[1+2];', 'delete obj[`key`];',
  'delete obj[`prefix${key}`];', 'delete obj[+1];', 'delete obj[-key];', 'delete obj[null];',
  'delete obj[true];', 'delete obj[1n];', 'delete obj["a"+"b"];', 'delete obj[(key)];',
  'delete (obj[key]);', 'delete obj?.[key];', 'delete (obj[key] as unknown);', 'delete (obj[key]!);',
  'class Invalid { value = (()=>{delete obj[key]; return 1;})(); }',
  'class Invalid { @Prop value = (()=>{delete obj[key]; return 1;})(); }',
  'const template=`${delete obj[key]}`;', 'function nested(){return ()=>delete obj[key]}',
  'const regex=/safe/; delete obj[key];'
];
for(const text of valid)assert.equal(inspectSource('Fixture.ts',text,parsers).violations.length,0,text);
for(const text of invalid)assert.equal(inspectSource('Fixture.ts',text,parsers).violations.length,1,text);
for(const text of ['delete obj[;', 'class Broken { value = delete obj[key;', '`unterminated']) {
  assert.throws(()=>inspectSource('Broken.ts',text,parsers),/invalid syntax/);
}
const struct='@Entry\n@Component\nstruct Fixture { @State value:number=1; build(){ Column(){ Text("safe").onClick(()=>{delete obj["key"];}) } } }';
const mutated=struct.replace('delete obj["key"]','delete obj[key]');
const hds=struct.replace('Column()','HdsTabs()');
if(parsers.ark) {
  for(const text of [struct,hds])assert.equal(inspectSource('Fixture.ets',text,parsers).violations.length,0);
  for(const text of [mutated,mutated.replace('Column()','HdsTabs()')])assert.equal(inspectSource('Fixture.ets',text,parsers).violations.length,1,'Nested ArkUI callback mutation must be detected');
  assert.throws(()=>inspectSource('Broken.ets',struct.replace('delete obj["key"]','delete obj['),parsers),/invalid syntax/);
} else {
  assert.throws(()=>inspectSource('Fixture.ets',struct,parsers),/Native SDK ArkTS parser is required/);
  assert.throws(()=>inspectSource('Plain.ets','export class Plain {}',parsers),/Native SDK ArkTS parser is required/);
  console.log('dynamic-delete-gate: SKIP native ArkTS/ArkUI/HdsTabs success fixtures without CLT; production .ets verification fails closed');
}
const lintConfig=parsers.host.parseConfigFileTextToJson('code-linter.json5',fs.readFileSync(path.resolve(__dirname,'../code-linter.json5'),'utf8'));
assert.equal(lintConfig.error,undefined);
assert.deepEqual(Object.entries(lintConfig.config.rules).filter(([,value])=>value==='off').map(([name])=>name),['@typescript-eslint/no-dynamic-delete'],'Only the approved broken root rule is replaced');
assert.equal(lintConfig.config.rules['@security/no-unsafe-hash'],'error','Native security coverage must remain enabled');
const workflow=fs.readFileSync(path.resolve(__dirname,'../.github/workflows/ci.yml'),'utf8');
assert.match(workflow,/Install pinned AST gate compiler/);
assert.match(workflow,/Verify native ArkTS AST gate fixtures/);
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'hutao-delete-gate-'));
const dir=path.join(temp,'entry/src/main/ets');fs.mkdirSync(dir,{recursive:true});
const source=path.join(dir,'Canary.ts');fs.writeFileSync(source,'export class Canary { value = Math.max(1,2); remove(){delete obj["key"];} }');
assert.equal(checkProject(temp).violations.length,0);
fs.writeFileSync(source,fs.readFileSync(source,'utf8').replace('obj["key"]','obj[key]'));
assert.equal(checkProject(temp).violations.length,1,'One-token mutation changes a pass to a failure');
const cli=path.resolve(__dirname,'../ci/check-dynamic-delete.cjs');
assert.equal(spawnSync(process.execPath,[cli,temp],{env:process.env}).status,1);
const runner=path.resolve(__dirname,'../ci/run-native-lint.cjs');
const evidence=path.join(temp,'evidence');
const result=spawnSync(process.execPath,[runner,evidence],{cwd:temp,env:{...process.env,DEVECO_CLI_CLT_PATH:process.env.DEVECO_CLI_CLT_PATH||path.join(temp,'missing-clt')},encoding:'utf8'});
assert.equal(result.status,1);assert.match(result.stderr,/Dynamic-delete AST gate/);
assert.ok(fs.existsSync(path.join(evidence,'dynamic-delete.json')),'Real runner must preserve AST rejection evidence');
assert.equal(fs.existsSync(path.join(evidence,'process.json')),false,'Native checker must not run before AST gate passes');
console.log(`dynamic-delete-gate: PASS (${valid.length} valid, ${invalid.length} invalid, malformed syntax, initializer mutation, runner canary; ${parsers.ark?'native ArkTS/ArkUI/HdsTabs fixtures verified':'native fixtures skipped; all .ets verification fails closed without SDK'})`);
