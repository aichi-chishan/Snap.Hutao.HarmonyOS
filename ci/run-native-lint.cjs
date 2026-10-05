const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { verifyLint } = require('./check-lint-report.cjs');
const { checkProject } = require('./check-dynamic-delete.cjs');

function countSources(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).reduce((total, entry) => {
    const filename = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error('Unexpected source symlink');
    return total + (entry.isDirectory() ? countSources(filename) : Number(entry.isFile() && entry.name.endsWith('.ets')));
  }, 0);
}
let ownedLock;
try {
  const projectRoot = fs.realpathSync(process.cwd());
  const evidence = path.resolve(process.argv[2] || '.local/ci-lint');
  // Never reuse evidence from another run, including a previously failed run.
  fs.mkdirSync(path.dirname(evidence), { recursive: true });
  fs.mkdirSync(evidence, { recursive: false });
  const dynamicDelete = checkProject(projectRoot);
  fs.writeFileSync(path.join(evidence, 'dynamic-delete.json'), JSON.stringify(dynamicDelete, null, 2));
  if (dynamicDelete.violations.length > 0) throw new Error('Dynamic-delete AST gate rejected computed property deletion');
  const clt = process.env.DEVECO_CLI_CLT_PATH;
  if (!clt || !path.isAbsolute(clt)) throw new Error('DEVECO_CLI_CLT_PATH must be an absolute CLT path');
  const scan = path.join(clt, 'codelinter/linter/result/arkPerfCheck.log');
  // The vendor log is shared by all invocations of one CLT installation.
  fs.mkdirSync(path.dirname(scan), { recursive: true });
  if (fs.lstatSync(path.dirname(scan)).isSymbolicLink()) throw new Error('Unexpected native log directory symlink');
  const lock = scan + '.hutao-lock';
  fs.mkdirSync(lock); // Existing locks fail closed; never steal another run's evidence.
  ownedLock = lock;
  if (fs.existsSync(scan)) {
    const previous = fs.lstatSync(scan);
    if (!previous.isFile() || previous.isSymbolicLink()) throw new Error('Unexpected native scan log type');
    // SDK and evidence may be on different mounts. Preserve before removing our old runtime log.
    fs.copyFileSync(scan, path.join(evidence, 'previous-scan.log'), fs.constants.COPYFILE_EXCL);
    fs.unlinkSync(scan);
  }
  const markerPath = path.join(evidence, 'run.json');
  fs.writeFileSync(markerPath, JSON.stringify({ version: 1, projectRoot,
    minimumSourceFiles: countSources(path.join(projectRoot, 'entry/src/main/ets')), startedAtMs: Date.now() }));
  const reportPath = path.join(evidence, 'lint-report.json');
  const log = fs.openSync(path.join(evidence, 'lint-console.log'), 'wx');
  const run = spawnSync(path.join(clt, 'bin/codelinter'),
    ['--exit-on', 'error', '-c', 'code-linter.json5', '-f', 'json', '-o', reportPath, '.'],
    { cwd: projectRoot, env: process.env, stdio: ['ignore', log, log] });
  fs.closeSync(log);
  fs.writeFileSync(path.join(evidence, 'process.json'), JSON.stringify({ status: run.status, signal: run.signal,
    error: run.error ? run.error.message : null }));
  const copiedScan = path.join(evidence, 'lint-scan.log');
  if (fs.existsSync(scan)) {
    fs.copyFileSync(scan, copiedScan);
    const original = fs.statSync(scan);
    fs.utimesSync(copiedScan, original.atime, original.mtime);
  }
  // Check evidence even when the process fails, so partial reports remain diagnosable.
  const result = verifyLint(reportPath, copiedScan, markerPath);
  fs.writeFileSync(path.join(evidence, 'summary.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
  if (run.error || run.status !== 0 || result.error > 0) process.exitCode = 1;
} catch (error) {
  console.error(`Native lint verification failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  if (ownedLock) {
    try { fs.rmdirSync(ownedLock); }
    catch (error) { console.error(`Cannot release native lint lock: ${error.message}`); process.exitCode = 1; }
  }
}
