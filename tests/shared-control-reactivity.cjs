// Execute production handlers on the host; @Prop synchronization, native focus,
// screen-reader announcements and layout still require HarmonyOS SDK/device QA.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main');
const source = name => fs.readFileSync(path.join(root, 'ets/components', `${name}.ets`), 'utf8');
const routes = [];
let backs = 0;
const decoratorFactory = () => () => {};
function component(name) {
  let text = source(name).replace('@Component\n', '').replace(`export struct ${name}`, `export class ${name}`);
  // ArkUI's declarative build grammar is not TypeScript. Compile only handlers.
  text = text.slice(0, text.indexOf('  build() {')) + '}';
  const compiled = ts.transpileModule(text, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022,
      experimentalDecorators: true }, reportDiagnostics: true,
  });
  assert.equal(compiled.diagnostics.filter(item => item.category === ts.DiagnosticCategory.Error).length, 0, name);
  const module = { exports: {} };
  const environment = { Prop: () => {}, State: () => {}, StorageProp: decoratorFactory,
    Watch: decoratorFactory, TouchType: { Down: 0, Up: 1, Cancel: 2, Move: 3 } };
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`, environment)(id => {
    if (id.endsWith('/Motion')) return { Motion: {
      springFast: () => 'shared-spring', easeOut: duration => ({ duration, curve: 'shared-ease' }),
    } };
    if (id === '@kit.ArkUI') return { router: { back: () => { backs++; }, pushUrl: route => { routes.push(route.url); } } };
    throw Error(`Unexpected dependency: ${id}`);
  }, module, module.exports);
  return module.exports[name];
}

const TapButton = component('QTapButton');
const button = new TapButton();
const animations = [];
let taps = 0;
button.getUIContext = () => ({ animateTo(options, update) { animations.push(options); update(); } });
button.onTap = () => { taps++; };
button.handleTouch(0);
assert.equal(button.pressScale, .98);
assert.equal(button.pressed, true);
assert.equal(animations[0].curve, 'shared-ease');
button.disabled = true;
button.onEnabledChanged();
assert.equal(button.pressScale, 1);
assert.equal(button.pressed, false);
for (const type of [0, 1, 2, 3]) button.handleTouch(type);
button.handleClick();
assert.equal(taps, 0, 'disabled controls never dispatch an action');
assert.equal(animations.length, 1, 'disabled controls never animate');

button.disabled = false;
button.onEnabledChanged();
for (const end of [1, 2]) {
  button.handleTouch(0);
  assert.equal(button.pressed, true);
  button.handleTouch(end);
  assert.equal(button.pressed, false);
  assert.equal(button.pressScale, 1);
  assert.equal(animations.at(-1).curve, 'shared-spring');
}
const beforeMove = animations.length;
button.handleTouch(3);
assert.equal(animations.length, beforeMove, 'moving does not repeatedly schedule animations');
button.handleClick();
assert.equal(taps, 1, 'native keyboard/accessibility activation uses the same enabled handler');

button.handleTouch(0);
button.reduceMotion = true;
button.onMotionChanged();
assert.equal(button.pressScale, 1);
assert.equal(button.pressed, false);
const beforeReduction = animations.length;
for (const type of [0, 1, 2, 3]) button.handleTouch(type);
assert.equal(animations.length, beforeReduction, 'explicit reduction disables press animation');
button.handleClick();
assert.equal(taps, 2, 'reduced motion preserves the action');
button.reduceMotion = false;
button.onMotionChanged();
button.handleTouch(0);
assert.equal(button.pressScale, .98, 'motion can be restored without recreating the control');
button.aboutToAppear();
assert.equal(button.pressScale, 1);
assert.equal(button.pressed, false);
button.handleTouch(0);
button.resetPress();
assert.equal(button.pressScale, 1, 'focus loss resets the same press state');

const BackButton = component('AppBackButton');
const backButton = new BackButton();
backButton.onBack();
assert.equal(backs, 1);
backButton.onBack = () => { taps++; };
backButton.onBack();
assert.equal(taps, 3, 'custom back action remains supported');
assert.equal(backs, 1);

const LoginStatusBar = component('LoginStatusBar');
const login = new LoginStatusBar();
login.openAccount();
login.isLoggedIn = true;
login.currentUserName = 'A';
login.openAccount();
login.currentUserName = 'B';
login.openAccount();
login.isLoggedIn = false;
login.openAccount();
assert.deepEqual(routes, ['pages/LoginPage', 'pages/UserPage', 'pages/UserPage', 'pages/LoginPage'],
  'login/logout/account changes are read at activation, without a captured stale route');

const reactiveProperties = {
  QTapButton: ['label', 'icon', 'capsule', 'disabled', 'primary', 'reduceMotion'],
  AppBackButton: ['accessibilityLabel'], EmptyState: ['icon', 'text'], Loading: ['text'],
  ErrorHint: ['text', 'icon'], PageHeader: ['title', 'embedMode', 'topAvoidVp'],
  NavIcon: ['name', 'iconSize'], AssetIcon: ['name', 'iconSize'],
};
for (const [name, properties] of Object.entries(reactiveProperties)) {
  for (const property of properties) assert.match(source(name),
    new RegExp(`@Prop(?: @Watch\\('[^']+'\\))? ${property}:`), `${name}.${property} must sync from the parent`);
}
const tapSource = source('QTapButton');
assert.match(tapSource, /Button\(\{ type: ButtonType.Normal, stateEffect: false \}\)/);
assert.match(tapSource, /\.enabled\(!this.disabled\)/);
assert.match(tapSource, /@Watch\('onEnabledChanged'\) disabled/);
assert.match(tapSource, /@Watch\('onMotionChanged'\) reduceMotion/);
assert.match(tapSource, /\.onBlur\(\(\) => \{\s*this.resetPress\(\)/);
assert.doesNotMatch(tapSource, /aboutToDisappear\(/, 'do not mutate decorated state during component teardown');
assert.match(tapSource, /Text\(this.label\)[\s\S]*?\.flexShrink\(1\)/,
  'label shrinks and wraps without pushing the icon away from centered content');
assert.match(tapSource, /\.onClick\(\(\) => \{\s*this.handleClick\(\)/);
assert.match(tapSource, /\.accessibilityText\(this.label.length > 0 \? this.label : this.icon\)/);
assert.doesNotMatch(tapSource, /\.animation\(/, 'no implicit animation may delay disabled/reduced-motion reset');

for (const [name, key] of [['Loading', 'common_loading'], ['EmptyState', 'common_empty'], ['ErrorHint', 'common_error']]) {
  assert.ok(source(name).includes(`this.text.length > 0 ? this.text : $r('app.string.${key}')`),
    `${name} must preserve caller text and use native fallback resources`);
  assert.match(source(name), /\.textAlign\(TextAlign.Center\)/);
  assert.match(source(name), /\.width\('100%'\)/);
}
const back = source('AppBackButton');
assert.match(back, /\.width\(44\)\s*\.height\(44\)/);
assert.match(back, /\.accessibilityText\(this.accessibilityLabel\)/);
assert.match(back, /\.hoverEffect\(HoverEffect.Highlight\)/);
assert.match(back, /Image\(\$r\('app.media.hutao_back'\)\)/);
assert.match(back, /\.fillColor\(\$r\('app.color.text_primary'\)\)/);
assert.match(back, /\.accessibilityLevel\('no'\)/);
assert.doesNotMatch(back, /Text\('‹'\)|color: '#/);
const svg = fs.readFileSync(path.join(root, 'resources/base/media/hutao_back.svg'), 'utf8');
assert.match(svg, /viewBox="0 0 24 24"/);
assert.match(svg, /<path fill="#[0-9A-Fa-f]{6}" d="[^"]+"\/>/);
assert.doesNotMatch(svg, /<script|href=|<image/i, 'the bundled glyph has no external payload');

for (const name of ['QTapButton', 'ErrorHint', 'LoginStatusBar']) {
  const text = source(name);
  assert.match(text, /\.constraintSize\(\{ minHeight: 44 \}\)/);
  assert.match(text, /\.hoverEffect\(/);
  assert.doesNotMatch(text, /\.height\((?:30|32|44)\)|\.maxLines\(/, `${name} text can grow with font scale`);
}
assert.equal((source('LoginStatusBar').match(/\bButton\(/g) || []).length, 1,
  'one native account/login action, without nested interactive controls');
assert.equal((source('LoginStatusBar').match(/\.onClick\(/g) || []).length, 1);
assert.match(source('LoginStatusBar'), /\.accessibilityGroup\(true\)/);
assert.match(source('ErrorHint'), /Button\(\{ type: ButtonType.Normal \}\) \{\s*Text\(/,
  'retry uses flexible child text rather than the default single-line Button label');
const header = source('PageHeader');
assert.match(header, /Text\(this.title\)[\s\S]*?\.layoutWeight\(1\)/);
assert.doesNotMatch(header, /Blank\(\)|\.maxLines\(/, 'the header title wraps in remaining space');

// Reject references to resources/services absent from the recovered baseline.
const resources = new Set();
for (const file of fs.readdirSync(path.join(root, 'resources/base/element'))) {
  const data = JSON.parse(fs.readFileSync(path.join(root, 'resources/base/element', file), 'utf8'));
  for (const [type, rows] of Object.entries(data)) for (const row of rows) resources.add(`app.${type}.${row.name}`);
}
for (const file of fs.readdirSync(path.join(root, 'resources/base/media'))) resources.add(`app.media.${path.parse(file).name}`);
for (const name of [...Object.keys(reactiveProperties), 'LoginStatusBar']) {
  const text = source(name);
  assert.doesNotMatch(text, /LocalizationService|VisualEffects/, 'do not import unrecovered services');
  for (const match of text.matchAll(/\$r\('(app\.[A-Za-z0-9_.]+)'\)/g)) assert.ok(resources.has(match[1]), `${name}: missing ${match[1]}`);
}
console.log('shared-control-reactivity: PASS (production press/click/reset and account routing handlers; reactive-input, native-action, resource, 44vp, vector and flexible-text source contracts; native UI QA still required)');
