// CodeLinter 6.0.240 can exit 0 with findings or internal scanner failures.
// A JSON count is only useful together with fresh, complete scan evidence.
const fs = require('node:fs');
const path = require('node:path');

function verifyLint(reportPath, scanPath, markerPath) {
  const marker = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
  if (marker.version !== 1 || !Number.isFinite(marker.startedAtMs) || marker.startedAtMs <= 0 || marker.startedAtMs > Date.now() ||
      !Number.isInteger(marker.minimumSourceFiles) || marker.minimumSourceFiles <= 0 ||
      typeof marker.projectRoot !== 'string' || !path.isAbsolute(marker.projectRoot)) {
    throw new Error('Malformed lint run marker');
  }
  const projectRoot = fs.realpathSync(marker.projectRoot);
  const markerStat = fs.lstatSync(markerPath);
  if (!markerStat.isFile() || Math.abs(markerStat.mtimeMs - marker.startedAtMs) > 2000) throw new Error('Stale or invalid run marker');
  for (const filename of [reportPath, scanPath]) {
    const stat = fs.lstatSync(filename);
    if (!stat.isFile() || stat.size === 0) throw new Error(`Missing/empty regular evidence file: ${filename}`);
    if (stat.mtimeMs < marker.startedAtMs) throw new Error(`Stale lint evidence: ${filename}`);
  }
  const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
  if (!Array.isArray(report) || report.length === 0) throw new Error('Missing or empty report array');
  const scan = fs.readFileSync(scanPath, 'utf8');
  const projectPaths = [...scan.matchAll(/"projectPath"\s*:\s*("(?:[^"\\]|\\.)*")/g)]
    .map(match => JSON.parse(match[1]));
  if (projectPaths.length === 0 || projectPaths.some(value => path.resolve(value) !== projectRoot)) {
    throw new Error('Scan evidence does not belong to this project');
  }
  const counts = [...scan.matchAll(/File count:\s*(\d+)/g)].map(match => Number(match[1]));
  const scanned = counts.length === 1 ? counts[0] : 0;
  if (scanned < marker.minimumSourceFiles) throw new Error(`Incomplete source scan: ${scanned}/${marker.minimumSourceFiles}`);
  if (!scan.includes('Checking completed.')) throw new Error('Native scanner did not complete');
  const scannerErrors = scan.split(/\r?\n/).filter(line =>
    /\[(?:ERROR|FATAL)\]|Error running file check|UnhandledPromiseRejection|uncaught exception/i.test(line));
  if (scannerErrors.length > 0) {
    throw new Error(`Internal scanner/configuration errors (${scannerErrors.length}); lint coverage is incomplete\n${scannerErrors.join('\n')}`);
  }
  const totals = { error: 0, warn: 0, suggestion: 0 };
  const errors = [];
  for (const file of report) {
    if (!file || typeof file.filePath !== 'string' || !file.filePath || !Array.isArray(file.messages)) {
      throw new Error('Malformed file report');
    }
    const filename = path.resolve(projectRoot, file.filePath);
    const resolved = fs.existsSync(filename) ? fs.realpathSync(filename) : filename;
    const relative = path.relative(projectRoot, resolved);
    if (relative.startsWith('..' + path.sep) || relative === '..' || path.isAbsolute(relative) || !fs.existsSync(filename)) {
      throw new Error('Report refers to a missing file or a different project');
    }
    for (const message of file.messages) {
      if (!message || !Object.hasOwn(totals, message.severity) || typeof message.rule !== 'string' || !message.rule ||
          typeof message.message !== 'string' || !message.message || !Number.isInteger(message.line) || message.line <= 0) {
        throw new Error('Malformed lint message or unknown severity');
      }
      totals[message.severity]++;
      if (message.severity === 'error') errors.push(`${file.filePath}:${message.line}: ${message.rule}: ${message.message}`);
    }
  }
  if (totals.error + totals.warn + totals.suggestion === 0) throw new Error('Empty findings report');
  return { scanned, ...totals, errors };
}

if (require.main === module) {
  try {
    const result = verifyLint(...process.argv.slice(2));
    console.log(`Lint report: ${result.scanned} source files scanned; ${result.error} errors, ${result.warn} warnings, ${result.suggestion} suggestions`);
    for (const error of result.errors) console.error(error);
    process.exitCode = result.error > 0 ? 1 : 0;
  } catch (error) {
    console.error(`Cannot verify complete lint coverage: ${error.message}`);
    process.exitCode = 1;
  }
}
module.exports = { verifyLint };
