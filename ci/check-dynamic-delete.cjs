// Equivalent-or-stricter replacement for the CLT 6.0.240 matcher crash.
// Semantics: https://typescript-eslint.io/rules/no-dynamic-delete/
// Parse original source; never strip decorators, structs, UI bodies or delete expressions.
const fs = require('node:fs');
const path = require('node:path');

function compilers() {
  const host = require(process.env.TYPESCRIPT_PATH || path.join(__dirname, 'node_modules/typescript'));
  if (host.version !== '5.9.3') throw new Error('The AST gate requires pinned TypeScript 5.9.3');
  const result = { host, ark: undefined, arkOptions: undefined };
  const clt = process.env.DEVECO_CLI_CLT_PATH;
  if (clt) {
    const sdk = path.join(clt, 'sdk/default');
    const loader = path.join(sdk, 'openharmony/ets/build-tools/ets-loader');
    if (fs.existsSync(path.join(loader, 'node_modules/typescript'))) {
      const ark = require(path.join(loader, 'node_modules/typescript'));
      if (!Number.isInteger(ark.ScriptKind.ETS) || typeof ark.isEtsComponentExpression !== 'function') {
        throw new Error('SDK parser does not expose the native ArkTS grammar');
      }
      const read = filename => {
        const parsed = ark.readConfigFile(filename, ark.sys.readFile);
        if (parsed.error || !parsed.config?.compilerOptions?.ets) throw new Error(`Invalid SDK syntax configuration: ${filename}`);
        return parsed.config.compilerOptions;
      };
      const options = read(path.join(loader, 'tsconfig.json'));
      const external = read(path.join(sdk, 'hms/ets/build-tools/ets-loader/components/externalconfig.json'));
      // This is the SDK loader's concatenateEtsOptions behavior, including HdsTabs.
      options.ets.components = [...options.ets.components, ...external.ets.components];
      options.ets.extend.components = [...options.ets.extend.components, ...external.ets.extend.components];
      result.ark = ark;
      result.arkOptions = options;
    }
  }
  return result;
}
function unwrap(ts, node) {
  while (ts.isParenthesizedExpression(node) || ts.isAsExpression(node) || ts.isTypeAssertionExpression(node) || ts.isNonNullExpression(node)) {
    node = node.expression;
  }
  return node;
}
function literalKey(ts, node) {
  while (ts.isParenthesizedExpression(node)) node = node.expression;
  if (ts.isStringLiteral(node) || ts.isNumericLiteral(node)) return true;
  return ts.isPrefixUnaryExpression(node) && node.operator === ts.SyntaxKind.MinusToken && ts.isNumericLiteral(node.operand);
}
function inspectSource(filename, text, parsers = compilers()) {
  const ets = filename.endsWith('.ets');
  if (ets && !parsers.ark) throw new Error('Native SDK ArkTS parser is required to verify .ets source');
  const ts = ets && parsers.ark ? parsers.ark : parsers.host;
  const kind = ets && parsers.ark ? ts.ScriptKind.ETS
    : /\.(?:jsx)$/.test(filename) ? ts.ScriptKind.JSX
    : /\.(?:tsx)$/.test(filename) ? ts.ScriptKind.TSX
    : /\.(?:js|cjs|mjs)$/.test(filename) ? ts.ScriptKind.JS : ts.ScriptKind.TS;
  const source = ts.createSourceFile(filename, text, ts.ScriptTarget.Latest, true, kind,
    ets && parsers.ark ? parsers.arkOptions : undefined);
  if (source.parseDiagnostics.length > 0) {
    const diagnostics = source.parseDiagnostics.map(d => {
      const position = source.getLineAndCharacterOfPosition(d.start || 0);
      return `${filename}:${position.line + 1}:${position.character + 1}: ${ts.flattenDiagnosticMessageText(d.messageText, ' ')}`;
    });
    const hint = ets && !parsers.ark ? ' Native SDK ArkTS parser is required for non-TypeScript syntax.' : '';
    throw new Error(`AST gate cannot verify ambiguous/invalid syntax.${hint}\n${diagnostics.join('\n')}`);
  }
  const violations = [];
  let deleteExpressions = 0;
  function visit(node) {
    if (ts.isDeleteExpression(node)) {
      deleteExpressions++;
      // Parentheses are erased by ESTree. Also unwrap TS-only assertions to avoid a bypass.
      const operand = unwrap(ts, node.expression);
      if (ts.isElementAccessExpression(operand) && (!operand.argumentExpression || !literalKey(ts, operand.argumentExpression))) {
        const position = source.getLineAndCharacterOfPosition(node.getStart(source));
        violations.push({filePath:filename, line:position.line+1, column:position.character+1,
          rule:'@typescript-eslint/no-dynamic-delete', message:'Do not delete dynamically computed property keys.'});
      }
    }
    ts.forEachChild(node, visit);
  }
  visit(source);
  return {deleteExpressions, violations, parser:ets && parsers.ark ? `ArkTS SDK ${ts.version}` : `TypeScript ${ts.version}`};
}
function checkProject(projectRoot) {
  const root = fs.realpathSync(projectRoot);
  const sourceRoot = path.join(root, 'entry/src/main');
  const files = [];
  function walk(directory) {
    for (const entry of fs.readdirSync(directory, {withFileTypes:true})) {
      const filename = path.join(directory, entry.name);
      if (entry.isSymbolicLink()) throw new Error(`Unexpected source symlink: ${filename}`);
      if (entry.isDirectory()) walk(filename);
      else if (entry.isFile() && /\.(?:ets|ts|tsx|js|jsx|cjs|mjs)$/.test(filename)) files.push(filename);
    }
  }
  walk(sourceRoot);
  if (files.length === 0) throw new Error('No production source files found');
  const parsers = compilers();
  const summary = {rule:'@typescript-eslint/no-dynamic-delete', files:files.length, deleteExpressions:0, violations:[], parsers:[]};
  for (const filename of files.sort()) {
    const result = inspectSource(filename, fs.readFileSync(filename,'utf8'),parsers);
    summary.deleteExpressions += result.deleteExpressions;
    summary.violations.push(...result.violations);
    if (!summary.parsers.includes(result.parser)) summary.parsers.push(result.parser);
  }
  return summary;
}
if (require.main === module) {
  try {
    const result = checkProject(process.argv[2] || process.cwd());
    console.log(JSON.stringify(result,null,2));
    process.exitCode = result.violations.length > 0 ? 1 : 0;
  } catch(error) {
    console.error(`Dynamic-delete AST gate failed: ${error.message}`);
    process.exitCode = 1;
  }
}
module.exports = {compilers,inspectSource,checkProject};
