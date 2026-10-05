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
rejects(() => fs.writeFileSync(scanPath, scan().replace(root, path.join(temp, 'other'))), /does not belong/);
rejects(() => fs.writeFileSync(scanPath, scan() + '[ERROR] Error running file check: getDeclaringMethod\n'), /coverage is incomplete/);
rejects(() => fs.writeFileSync(scanPath, scan() + '[ERROR] Invalid rule name: unavailable-rule\n'), /configuration errors/);
rejects(() => fs.writeFileSync(scanPath, scan() + 'Error running file check for Probe.ets\n'), /coverage is incomplete/);
for (const filename of [reportPath, scanPath]) rejects(() => fs.utimesSync(filename, new Date(0), new Date(0)), /Stale/);
rejects(() => fs.writeFileSync(markerPath, '{}'), /Malformed/);
rejects(() => fs.writeFileSync(markerPath, JSON.stringify({...marker(), startedAtMs:Date.now()+60000})), /Malformed/);
const external=path.join(temp,'external.ets');fs.writeFileSync(external,'external');
const linked=path.join(root,'linked.ets');fs.symlinkSync(external,linked);
rejects(() => fs.writeFileSync(reportPath,JSON.stringify([{filePath:linked,messages:[message('warn')]}])),/different project/);
rejects(() => fs.writeFileSync(markerPath, JSON.stringify({...marker(), minimumSourceFiles: 2})), /Incomplete/);

const installer = path.resolve(__dirname, '../ci/install-clt.sh');
const fakeBin = path.join(temp, 'bin'); fs.mkdirSync(fakeBin);
const calls = path.join(temp, 'curl-calls');
fs.writeFileSync(path.join(fakeBin, 'curl'), `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> "$CURL_CALLS"\nwhile [[ $# -gt 0 ]]; do if [[ "$1" == --output ]]; then printf fake > "$2"; shift; fi; shift; done\n`);
fs.chmodSync(path.join(fakeBin, 'curl'), 0o755);
const approved = 'https://github.com/aichi-chishan/snap-hutao-data/releases/download/clt-26.0.0.821/clt-part-00';
let index = 0;
for (const url of ['', 'https://example.invalid/clt-part-00', approved + '?other=1', approved.replace('821','822'), approved.replace('part-00','part-01')]) {
  const run = spawnSync('bash', [installer, path.join(temp, `install-${index++}`)], { env: {...process.env, DEVECO_CLT_URL: url, PATH: fakeBin + path.delimiter + process.env.PATH, CURL_CALLS: calls} });
  assert.notEqual(run.status, 0); assert.equal(fs.existsSync(calls), false, 'Unknown URL must fail before any network request');
}
const destination = path.join(temp, 'install-approved');
const attempted = spawnSync('bash', [installer, destination], { env: {...process.env, DEVECO_CLT_URL: approved, PATH: fakeBin + path.delimiter + process.env.PATH, CURL_CALLS: calls}, encoding:'utf8' });
assert.notEqual(attempted.status, 0); assert.match(attempted.stderr, /Unexpected size/, 'Fake bytes fail before extraction or execution');
const requests = fs.readFileSync(calls, 'utf8').trim().split('\n');
assert.equal(requests.length, 2); assert.ok(requests[0].endsWith(approved)); assert.ok(requests[1].endsWith(approved.replace('part-00','part-01')));
assert.equal(fs.existsSync(path.join(destination, 'clt')), false);
const verifySource = fs.readFileSync(path.resolve(__dirname, '../ci/verify-clt.py'), 'utf8');
for (const pin of ['2cb88715aa489620da78bd664660af97fc3b645320e998ae4fedd33e8b2c736d','5f44978744f1c3d8ef82175963fb0087a7e831ac48f5b7cbe36668b8b3e41838','58da7359019e9360a8bb82da0cd1d3b3b26fedc338379f257849f2162e3ac1fc','1992294400','355587885']) assert.ok(verifySource.includes(pin));
const workflow = fs.readFileSync(path.resolve(__dirname, '../.github/workflows/ci.yml'),'utf8');
assert.doesNotMatch(workflow, /devecocli (check lint|build)|if-no-files-found: warn/);
assert.match(workflow, /hvigorw clean --no-daemon/); assert.match(workflow, /ci\/check-hap.py/);

const hapChecker = path.resolve(__dirname, '../ci/check-hap.py');
const hapPath = path.join(temp, 'fixture.hap');
const manifest = {app:{minAPIVersion:60101024,targetAPIVersion:260000026,apiReleaseType:'Release'},module:{deviceTypes:['phone','tablet','2in1']}};
function makeHap(value) {
  const generated=spawnSync('python3',['-c',"import json,sys,zipfile; z=zipfile.ZipFile(sys.argv[1],'w'); z.writestr('module.json',sys.argv[2]); z.close()",hapPath,JSON.stringify(value)]);
  assert.equal(generated.status,0);
}
const checkHap=()=>spawnSync('python3',[hapChecker,hapPath]);
assert.notEqual(checkHap().status,0,'Missing HAP fails');
fs.writeFileSync(hapPath,'');assert.notEqual(checkHap().status,0,'Empty HAP fails');
fs.writeFileSync(hapPath,'not a zip');assert.notEqual(checkHap().status,0,'Corrupt HAP fails');
makeHap(manifest);assert.equal(checkHap().status,0);
makeHap({...manifest,app:{...manifest.app,minAPIVersion:260000026}});assert.notEqual(checkHap().status,0,'Raised minimum API fails');
makeHap({...manifest,module:{deviceTypes:['phone']}});assert.notEqual(checkHap().status,0,'Dropped devices fail');

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
for(const crash of [false,true]) {
  const evidence=path.join(temp,crash?'runner-failure':'runner-success');
  const result=spawnSync(process.execPath,[runner,evidence],{cwd:root,env:{...process.env,DEVECO_CLI_CLT_PATH:fakeClt,FIXTURE_CLT:fakeClt,FIXTURE_CRASH:crash?'1':''},encoding:'utf8'});
  assert.equal(result.status,crash?1:0,result.stderr);
  assert.ok(fs.existsSync(path.join(evidence,'run.json')));
  assert.ok(fs.existsSync(path.join(evidence,'lint-scan.log')));
  if(crash)assert.match(result.stderr,/coverage is incomplete/);
  const repeated=spawnSync(process.execPath,[runner,evidence],{cwd:root,env:{...process.env,DEVECO_CLI_CLT_PATH:fakeClt,FIXTURE_CLT:fakeClt}});
  assert.notEqual(repeated.status,0,'Existing evidence directory cannot be reused');
}
console.log('lint-report-gate: PASS (fresh project-bound evidence, scanner crashes, malformed/empty/stale reports, canary errors, warning policy, exact release pins)');
