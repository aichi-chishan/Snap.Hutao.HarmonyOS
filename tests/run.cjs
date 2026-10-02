// Host regressions supplement, but do not replace, the official ArkTS compiler/device tests.
const { readdirSync } = require('node:fs');
const { resolve } = require('node:path');
const { spawnSync } = require('node:child_process');
const root = resolve(__dirname, '..');
const files = readdirSync(__dirname).filter(file => file !== 'run.cjs' && /\.(cjs|mjs)$/.test(file)).sort();
files.push('../scripts/test-challenge-regressions.cjs');
for (const file of files) {
  const result = spawnSync(process.execPath, [resolve(__dirname, file)], { cwd: root, env: process.env, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}
console.log(`PASS: ${files.length} host regression suites`);
