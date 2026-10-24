const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { verifyLint } = require('../ci/check-lint-report.cjs');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hutao-lint-gate-'));
const root = path.join(temp, 'project'); fs.mkdirSync(root);
fs.mkdirSync(path.join(root, 'entry/src/main/ets'), {recursive:true});
const source = path.join(root, 'entry/src/main/ets/Probe.ets'); fs.writeFileSync(source, 'export const probe: number = 1;');
const reportPath = path.join(temp, 'report.json');
const scanPath = path.join(temp, 'scan.log');
const markerPath = path.join(temp, 'run.json');
const gate = path.resolve(__dirname, '../ci/check-lint-report.cjs');
const marker = () => ({ version: 1, startedAtMs: Date.now() - 1000, minimumSourceFiles: 1, projectRoot: root });
const message = severity => ({ line: 1, severity, message: 'Fixture diagnostic', rule: '@security/no-unsafe-hash' });
const report = severity => [{ filePath: source, messages: [message(severity)] }];
// The scan log embeds the project path via JSON.stringify, so on Windows the recorded form has
// escaped separators ('\\\\'). The fixture must rewrite the escaped form too, otherwise the
// "foreign project" case silently keeps the original root and the gate (correctly) does not throw.
const escaped = value => JSON.stringify(String(value)).slice(1, -1);
const scan = () => `[INFO] options ${JSON.stringify({projectPath: root})}\n[INFO] File count: 1\n[INFO] Checking completed.\n`;
function reset() {
  fs.writeFileSync(reportPath, JSON.stringify(report('warn')));
  fs.writeFileSync(scanPath, scan());
  fs.writeFileSync(markerPath, JSON.stringify(marker()));
}
function rejects(change, pattern) {
  reset(); change(); assert.throws(() => verifyLint(reportPath, scanPath, markerPath), pattern);
}
reset(); assert.deepEqual(verifyLint(reportPath, scanPath, markerPath), { scanned: 1, error: 0, warn: 1, suggestion: 0, errors: [] });
reset(); fs.writeFileSync(reportPath, JSON.stringify(report('suggestion'))); assert.equal(verifyLint(reportPath, scanPath, markerPath).suggestion, 1);
reset(); fs.writeFileSync(reportPath, JSON.stringify(report('error')));
assert.equal(verifyLint(reportPath, scanPath, markerPath).error, 1);
assert.equal(spawnSync(process.execPath, [gate, reportPath, scanPath, markerPath]).status, 1, 'Canary fails regardless of native exit 0');
rejects(() => fs.unlinkSync(reportPath), /ENOENT/);
rejects(() => fs.unlinkSync(scanPath), /ENOENT/);
rejects(() => fs.unlinkSync(markerPath), /ENOENT/);
rejects(() => fs.writeFileSync(reportPath, ''), /empty/);
rejects(() => fs.writeFileSync(scanPath, ''), /empty/);
rejects(() => fs.writeFileSync(reportPath, '[]'), /empty report/);
rejects(() => fs.writeFileSync(reportPath, '{}'), /report array/);
rejects(() => fs.writeFileSync(reportPath, '{'), /JSON/);
rejects(() => fs.writeFileSync(reportPath, JSON.stringify([{filePath: source, messages: []}])), /Empty findings/);
rejects(() => fs.writeFileSync(reportPath, JSON.stringify([null])), /Malformed/);
rejects(() => fs.writeFileSync(reportPath, JSON.stringify(report('fatal'))), /unknown severity/);
rejects(() => fs.writeFileSync(reportPath, JSON.stringify([{filePath: source, messages: [{severity: 'warn'}]}])), /Malformed/);
rejects(() => fs.writeFileSync(reportPath, JSON.stringify([{filePath: '/foreign/Probe.ets', messages: [message('warn')]}])), /different project/);
rejects(() => fs.writeFileSync(scanPath, scan().replace('File count: 1', 'File count: 0')), /Incomplete/);
rejects(() => fs.writeFileSync(scanPath, scan() + 'File count: 1\n'), /Incomplete/);
rejects(() => fs.writeFileSync(scanPath, scan().replace('Checking completed.', 'Checking started.')), /did not complete/);
// Rewrite the JSON-escaped form actually present in the log (raw separators differ on Windows).
const foreign = () => scan().replaceAll(escaped(root), escaped(path.join(temp, 'other')));
rejects(() => fs.writeFileSync(scanPath, foreign()), /does not belong/);
rejects(() => fs.writeFileSync(scanPath, scan() + '[ERROR] Error running file check: getDeclaringMethod\n'), /coverage is incomplete/);
rejects(() => fs.writeFileSync(scanPath, scan() + '[ERROR] Invalid rule name: unavailable-rule\n'), /configuration errors/);
rejects(() => fs.writeFileSync(scanPath, scan() + 'Error running file check for Probe.ets\n'), /coverage is incomplete/);
for (const filename of [reportPath, scanPath]) rejects(() => fs.utimesSync(filename, new Date(0), new Date(0)), /Stale/);
rejects(() => fs.writeFileSync(markerPath, '{}'), /Malformed/);
rejects(() => fs.writeFileSync(markerPath, JSON.stringify({...marker(), startedAtMs:Date.now()+60000})), /Malformed/);
// A symlink escaping the project must be refused. Creating a file symlink needs elevation on
// Windows, so when the host forbids it we state the skip instead of silently passing the case.
const external=path.join(temp,'external.ets');fs.writeFileSync(external,'external');
const linked=path.join(root,'linked.ets');
let canLink=true;
try { fs.symlinkSync(external,linked,'file'); }
catch (error) {
  if (error.code==='EPERM'||error.code==='EACCES') { canLink=false; console.log('SKIP external symlink case: host forbids file symlinks ('+error.code+')'); }
  else throw error;
}
if (canLink) rejects(() => fs.writeFileSync(reportPath,JSON.stringify([{filePath:linked,messages:[message('warn')]}])),/different project/);
rejects(() => fs.writeFileSync(markerPath, JSON.stringify({...marker(), minimumSourceFiles: 2})), /Incomplete/);

// The installer runner and HAP checker are POSIX-only (bash / python3). On a host without
// them the cases cannot execute; report that explicitly instead of failing or pretending.
// The Windows Store 'python3' alias stub exits 0 while executing nothing, so probe for
// real output instead of trusting the exit status alone.
const hasBash = spawnSync('bash', ['-c', 'exit 0']).status === 0;
const python3Probe = spawnSync('python3', ['-c', 'print(42)'], { encoding: 'utf8' });
const hasPython3 = python3Probe.status === 0 && String(python3Probe.stdout).trim() === '42';
const installer = path.resolve(__dirname, '../ci/install-clt.sh');
const fakeBin = path.join(temp, 'bin'); fs.mkdirSync(fakeBin);
const calls = path.join(temp, 'curl-calls');
fs.writeFileSync(path.join(fakeBin, 'curl'), `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> "$CURL_CALLS"\nwhile [[ $# -gt 0 ]]; do if [[ "$1" == --output ]]; then printf fake > "$2"; shift; fi; shift; done\n`);
fs.chmodSync(path.join(fakeBin, 'curl'), 0o755);
const approved = 'https://github.com/aichi-chishan/snap-hutao-data/releases/download/clt-26.0.0.851/clt-part-00';
if (!hasBash || !hasPython3) {
  console.log('SKIP installer URL/size cases: no bash or no working python3 on this host (CI runs them on Linux)');
} else {
  let index = 0;
  for (const url of ['', 'https://example.invalid/clt-part-00', approved + '?other=1', approved.replace('851','852'), approved.replace('part-00','part-01')]) {
    const run = spawnSync('bash', [installer, path.join(temp, `install-${index++}`)], { env: {...process.env, DEVECO_CLT_URL: url, PATH: fakeBin + path.delimiter + process.env.PATH, CURL_CALLS: calls} });
    assert.notEqual(run.status, 0); assert.equal(fs.existsSync(calls), false, 'Unknown URL must fail before any network request');
  }
  const destination = path.join(temp, 'install-approved');
  const attempted = spawnSync('bash', [installer, destination], { env: {...process.env, DEVECO_CLT_URL: approved, PATH: fakeBin + path.delimiter + process.env.PATH, CURL_CALLS: calls}, encoding:'utf8' });
  assert.notEqual(attempted.status, 0); assert.match(attempted.stderr, /Unexpected size/, 'Fake bytes fail before extraction or execution');
  const requests = fs.readFileSync(calls, 'utf8').trim().split('\n');
  assert.equal(requests.length, 2); assert.ok(requests[0].endsWith(approved)); assert.ok(requests[1].endsWith(approved.replace('part-00','part-01')));
  assert.equal(fs.existsSync(path.join(destination, 'clt')), false);
}
const verifySource = fs.readFileSync(path.resolve(__dirname, '../ci/verify-clt.py'), 'utf8');
for (const pin of ['c57ebdd4850bbd1eb4744da661e58c0e3fed5c492fdd2aa35c4d91edd22166d7','830ae286a66d89a43f7a88504ffab4c13317b72e29efb15bbc722b4ce16f2837','ab604bd92721d5cbcafd154e6461d46b9f1b105e7b89eab04a9d046681198082','1992294400','355768909']) assert.ok(verifySource.includes(pin));
const workflow = fs.readFileSync(path.resolve(__dirname, '../.github/workflows/ci.yml'),'utf8');
assert.doesNotMatch(workflow, /devecocli (check lint|build)|if-no-files-found: warn/);
assert.match(workflow, /hvigorw clean --no-daemon/); assert.match(workflow, /ci\/check-hap.py/);

const hapChecker = path.resolve(__dirname, '../ci/check-hap.py');
const hapPath = path.join(temp, 'fixture.hap');
const manifest = {app:{minAPIVersion:260000026,targetAPIVersion:260000026,apiReleaseType:'Release'},module:{deviceTypes:['phone','tablet','2in1']}};
function makeHap(value) {
  const generated=spawnSync('python3',['-c',"import json,sys,zipfile; z=zipfile.ZipFile(sys.argv[1],'w'); z.writestr('module.json',sys.argv[2]); z.close()",hapPath,JSON.stringify(value)]);
  assert.equal(generated.status,0);
}
if (!hasPython3) {
  console.log('SKIP HAP checker cases: no python3 on this host (CI runs them on Linux)');
} else {
  const checkHap=()=>spawnSync('python3',[hapChecker,hapPath]);
  assert.notEqual(checkHap().status,0,'Missing HAP fails');
  fs.writeFileSync(hapPath,'');assert.notEqual(checkHap().status,0,'Empty HAP fails');
  fs.writeFileSync(hapPath,'not a zip');assert.notEqual(checkHap().status,0,'Corrupt HAP fails');
  makeHap(manifest);assert.equal(checkHap().status,0);
  makeHap({...manifest,app:{...manifest.app,minAPIVersion:60101024}});assert.notEqual(checkHap().status,0,'Lowered minimum API fails');
  makeHap({...manifest,module:{deviceTypes:['phone']}});assert.notEqual(checkHap().status,0,'Dropped devices fail');
}

const fakeClt=path.join(temp,'clt');fs.mkdirSync(path.join(fakeClt,'bin'),{recursive:true});
fs.mkdirSync(path.join(fakeClt,'codelinter/linter/result'),{recursive:true});
const fakeLinter=path.join(fakeClt,'bin/codelinter');
fs.writeFileSync(fakeLinter,String.raw`#!/usr/bin/env node
const fs=require('node:fs'),path=require('node:path');
const root=process.cwd();const report=process.argv[process.argv.indexOf('-o')+1];
fs.writeFileSync(report,JSON.stringify([{filePath:path.join(root,'entry/src/main/ets/Probe.ets'),messages:[{severity:'warn',line:1,rule:'fixture',message:'Warning remains nonfatal'}]}]));
fs.writeFileSync(path.join(process.env.FIXTURE_CLT,'codelinter/linter/result/arkPerfCheck.log'),'[INFO] '+JSON.stringify({projectPath:root})+'\nFile count: 1\nChecking completed.\n'+(process.env.FIXTURE_CRASH?'[ERROR] Error running file check: getDeclaringMethod\n':''));
`);fs.chmodSync(fakeLinter,0o755);
const runner=path.resolve(__dirname,'../ci/run-native-lint.cjs');
const realSdk=process.env.DEVECO_CLI_CLT_PATH && path.join(process.env.DEVECO_CLI_CLT_PATH,'sdk');
if(realSdk && fs.existsSync(realSdk)) fs.symlinkSync(realSdk,path.join(fakeClt,'sdk'));
if(realSdk && fs.existsSync(realSdk)) for(const crash of [false,true]) {
  const evidence=path.join(temp,crash?'runner-failure':'runner-success');
  const result=spawnSync(process.execPath,[runner,evidence],{cwd:root,env:{...process.env,DEVECO_CLI_CLT_PATH:fakeClt,FIXTURE_CLT:fakeClt,FIXTURE_CRASH:crash?'1':''},encoding:'utf8'});
  assert.equal(result.status,crash?1:0,result.stderr);
  assert.ok(fs.existsSync(path.join(evidence,'run.json')));
  assert.ok(fs.existsSync(path.join(evidence,'lint-scan.log')));
  if(crash)assert.match(result.stderr,/coverage is incomplete/);
  const repeated=spawnSync(process.execPath,[runner,evidence],{cwd:root,env:{...process.env,DEVECO_CLI_CLT_PATH:fakeClt,FIXTURE_CLT:fakeClt}});
  assert.notEqual(repeated.status,0,'Existing evidence directory cannot be reused');
}
if(realSdk && fs.existsSync(realSdk)) {
  const scan=path.join(fakeClt,'codelinter/linter/result/arkPerfCheck.log');
  const lock=scan+'.hutao-lock';
  fs.mkdirSync(lock);const before=fs.readFileSync(scan);
  const blocked=spawnSync(process.execPath,[runner,path.join(temp,'runner-held-lock')],{cwd:root,env:{...process.env,DEVECO_CLI_CLT_PATH:fakeClt,FIXTURE_CLT:fakeClt},encoding:'utf8'});
  assert.equal(blocked.status,1);assert.ok(fs.existsSync(lock));assert.deepEqual(fs.readFileSync(scan),before);fs.rmdirSync(lock);
  const hook=path.join(temp,'deny-cross-device-rename.cjs');
  fs.writeFileSync(hook,"require('node:fs').renameSync=()=>{const e=new Error('cross-device fixture');e.code='EXDEV';throw e};");
  const evidence=path.join(temp,'runner-cross-device');
  const cross=spawnSync(process.execPath,[runner,evidence],{cwd:root,env:{...process.env,DEVECO_CLI_CLT_PATH:fakeClt,FIXTURE_CLT:fakeClt,NODE_OPTIONS:'--require='+hook},encoding:'utf8'});
  assert.equal(cross.status,0,cross.stderr);assert.deepEqual(fs.readFileSync(path.join(evidence,'previous-scan.log')),before);assert.equal(fs.existsSync(lock),false);
}
if(!realSdk || !fs.existsSync(realSdk)) {
  const result=spawnSync(process.execPath,[runner,path.join(temp,'missing-parser-evidence')],{cwd:root,env:{...process.env,DEVECO_CLI_CLT_PATH:fakeClt},encoding:'utf8'});
  assert.equal(result.status,1);assert.match(result.stderr,/Native SDK ArkTS parser is required/);
  console.log('lint-report-gate: SKIP native-parser-dependent runner success fixtures without CLT; missing-parser rejection verified');
}
console.log('lint-report-gate: PASS (fresh project-bound evidence, scanner crashes, malformed/empty/stale reports, canary errors, warning policy, exact release pins)');
