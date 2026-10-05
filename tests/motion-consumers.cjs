// Execute production handlers and visual expressions with platform doubles.
// Native scheduling, interrupting an in-flight animation and layout need SDK/device QA.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const source = name => fs.readFileSync(path.join(root, `${name}.ets`), 'utf8');
const noDecorator = () => () => {};
const curves = { springCurve: (...args) => ({ type: 'springCurve', args }),
  springMotion: (...args) => ({ type: 'springMotion', args }) };
const Motion = { springSoft: () => 'soft', springFast: () => 'fast', riseIn: () => ({ type: 'rise' }) };
class Effect {
  constructor(type, value, children = []) { this.type = type; this.value = value; this.children = children; }
  combine(other) { return new Effect('combine', undefined, [this, other]); }
  animation(options) { this.options = options; return this; }
}
const TransitionEffect = {
  get IDENTITY() { return new Effect('identity'); }, get OPACITY() { return new Effect('opacity'); },
  scale: value => new Effect('scale', value), translate: value => new Effect('translate', value),
  asymmetric: (enter, exit) => new Effect('asymmetric', undefined, [enter, exit]),
};
const environment = { State: () => {}, Prop: () => {}, StorageProp: noDecorator, Watch: noDecorator,
  BuilderParam: () => {}, TouchType: { Down: 0, Up: 1, Cancel: 2, Move: 3 },
  Color: { Transparent: 'transparent' }, Curve: { EaseOut: 'easeOut', EaseInOut: 'easeInOut', Linear: 'linear' },
  PlayMode: { Alternate: 'alternate' }, EdgeEffect: { None: 'none', Spring: 'spring' },
  TransitionEffect, Motion, curves, clearInterval() {},
};
function compile(text, name) {
  const compiled = ts.transpileModule(text, { compilerOptions: { module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022, experimentalDecorators: true }, reportDiagnostics: true });
  assert.equal(compiled.diagnostics.filter(item => item.category === ts.DiagnosticCategory.Error).length, 0, name);
  const mod = { exports: {} };
  vm.runInNewContext(`(function(require,module,exports){${compiled.outputText}\n})`, environment)(id => {
    if (id === '@kit.ArkUI') return { curves };
    if (id.endsWith('/Motion')) return { Motion };
    if (id.endsWith('/Logger')) return { Logger: { info() {}, warn() {} } };
    if (id.endsWith('/HutaoDailyImageService')) return { HutaoDailyImageService: {
      getInstance() { throw Error('wallpaper network must not run in this test'); },
    } };
    if (id.startsWith('@kit.')) return {};
    throw Error(`Unexpected runtime dependency: ${id}`);
  }, mod, mod.exports);
  return mod.exports;
}
function component(name) {
  let text = source(`components/${name}`).replace('@Component\n', '')
    .replace(`export struct ${name}`, `export class ${name}`);
  text = text.slice(0, text.indexOf('  build() {')) + '}';
  return compile(text, name)[name];
}
// These expressions contain no template substitutions. Skip strings/comments so
// nested calls and object literals are extracted without executing ArkUI DSL.
function matching(text, start, open, close) {
  let depth = 0, quote = '', lineComment = false, blockComment = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i], next = text[i + 1];
    if (lineComment) { if (c === '\n') lineComment = false; continue; }
    if (blockComment) { if (c === '*' && next === '/') { blockComment = false; i++; } continue; }
    if (quote) { if (c === '\\') i++; else if (c === quote) quote = ''; continue; }
    if (c === '/' && next === '/') { lineComment = true; i++; continue; }
    if (c === '/' && next === '*') { blockComment = true; i++; continue; }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === open) depth++;
    if (c === close && --depth === 0) return i;
  }
  throw Error(`Unbalanced expression at ${start}`);
}
function argumentsFor(text, call) {
  const expressions = [];
  let offset = 0;
  while ((offset = text.indexOf(`${call}(`, offset)) >= 0) {
    const start = offset + call.length;
    const end = matching(text, start, '(', ')');
    expressions.push(text.slice(start + 1, end)); offset = end + 1;
  }
  return expressions;
}
function evaluate(expression, state) {
  return compile(`export function evaluate() { return ${expression}; }`, 'visual expression').evaluate.call(state);
}
function method(text, signature) {
  const start = text.indexOf(signature);
  assert.ok(start >= 0, signature);
  const brace = text.indexOf('{', start);
  return text.slice(start, matching(text, brace, '{', '}') + 1);
}
const animating = target => {
  const calls = [];
  target.getUIContext = () => ({ animateTo(options, update) { calls.push(options); update(); } });
  return calls;
};

(async () => {
  const PressCard = component('PressCard');
  const card = new PressCard();
  const presses = animating(card);
  card.pressScaleTo = .95;
  card.handleTouch(0); assert.equal(card.pressScale, .95); assert.equal(presses.at(-1).duration, 90);
  card.reduceMotion = true; card.onMotionChanged(); assert.equal(card.pressScale, 1);
  const prior = presses.length;
  for (const event of [0, 1, 2, 3]) card.handleTouch(event);
  assert.equal(presses.length, prior, 'reduced press does not schedule animations');
  let clicked = 0; card.onTap = () => { clicked++; }; card.onTap(); assert.equal(clicked, 1);
  card.reduceMotion = false; card.onMotionChanged();
  for (const event of [1, 2]) {
    card.handleTouch(0); card.handleTouch(event); assert.equal(card.pressScale, 1);
    assert.equal(presses.at(-1).duration, 260); assert.equal(presses.at(-1).curve.type, 'springCurve');
  }
  card.pressScale = .95; card.aboutToAppear(); assert.equal(card.pressScale, 1);
  const pressSource = source('components/PressCard');
  assert.match(pressSource, /@StorageProp\('reduceMotion'\) @Watch\('onMotionChanged'\)/);
  assert.match(pressSource, /\.onBlur\(\(\) => \{\s*this.pressScale = 1/);
  assert.doesNotMatch(pressSource, /aboutToDisappear\(/, 'press reset must not mutate state during teardown');
  assert.equal(evaluate(argumentsFor(pressSource, '.scale')[0], { reduceMotion: true, pressScale: .95 }).x, 1);
  assert.equal(evaluate(argumentsFor(pressSource, '.animation')[0], { reduceMotion: true }).duration, 0);

  const index = source('pages/Index');
  const { Shell } = compile(`export class Shell {
    ${method(index, '  private switchTo(')}
    ${method(index, '  private toggleSidebar(')}
  }`, 'shell navigation handlers');
  const shell = new Shell(); const navigation = animating(shell); let refreshes = 0;
  shell.reloadHome = () => { refreshes++; }; shell.sidebarFold = false;
  for (const reduced of [false, true]) {
    shell.reduceMotion = reduced; const before = navigation.length;
    for (const selected of [2, 0, 0, 7]) { shell.switchTo(selected); assert.equal(shell.currentIndex, selected); }
    assert.equal(navigation.length - before, reduced ? 0 : 4);
    const folded = shell.sidebarFold; shell.toggleSidebar(); assert.equal(shell.sidebarFold, !folded);
    assert.equal(navigation.length - before, reduced ? 0 : 5);
  }
  assert.equal(refreshes, 4, 'returning home retains its existing refresh behavior in both modes');
  const indexTransitions = argumentsFor(index, '.transition'); assert.equal(indexTransitions.length, 3);
  for (const expression of indexTransitions) {
    const reduced = evaluate(expression, { reduceMotion: true });
    assert.equal(reduced.type, 'identity'); assert.equal(reduced.options.duration, 0);
    assert.notEqual(evaluate(expression, { reduceMotion: false }).type, 'identity');
  }
  const indexAnimations = argumentsFor(index, '.animation').filter(expression => expression.includes('this.reduceMotion'));
  assert.equal(indexAnimations.length, 3);
  for (const expression of indexAnimations) {
    assert.equal(evaluate(expression, { reduceMotion: true }).duration, 0);
    assert.equal(evaluate(expression, { reduceMotion: false }).curve, 'fast');
  }
  for (const expression of argumentsFor(index, '.geometryTransition')) {
    assert.equal(evaluate(expression.replaceAll('index', '2'), { reduceMotion: true, currentIndex: 2 }), '');
  }

  const home = source('components/HomeGachaCard');
  for (const reduced of [false, true]) {
    const state = { reduceMotion: reduced };
    assert.equal(evaluate(argumentsFor(home, '.duration')[0], state), reduced ? 0 : 240);
    assert.equal(evaluate(argumentsFor(home, '.curve')[0], state), reduced ? 'linear' : 'fast');
    assert.equal(evaluate(argumentsFor(home, '.animation')[0], state).duration, reduced ? 0 : 150);
    assert.equal(evaluate(argumentsFor(home, '.effectMode')[0], state), reduced ? 'none' : 'spring');
    for (const expression of argumentsFor(home, '.edgeEffect'))
      assert.equal(evaluate(expression, state), reduced ? 'none' : 'spring');
  }
  assert.match(home, /\.onChange\(\(idx: number\) => \{\s*this.pageIndex = idx/);

  const risk = source('components/RiskVerifyModal');
  const riskTransitions = argumentsFor(risk, '.transition'); assert.equal(riskTransitions.length, 2);
  for (const expression of riskTransitions) {
    const reduced = evaluate(expression, { reduceMotion: true });
    assert.equal(reduced.type, 'identity'); assert.equal(reduced.options.duration, 0);
    assert.notEqual(evaluate(expression, { reduceMotion: false }).type, 'identity');
  }
  const pulse = argumentsFor(risk, '.animation').find(expression => expression.includes('iterations:'));
  assert.equal(evaluate(pulse, { reduceMotion: true }).duration, 0);
  assert.equal(evaluate(pulse, { reduceMotion: true }).iterations, 1, 'reduced status has no infinite animation');
  assert.equal(evaluate(pulse, { reduceMotion: false }).duration, 700);
  assert.equal(evaluate(pulse, { reduceMotion: false }).iterations, -1);
  assert.equal(evaluate(argumentsFor(risk, '.opacity')[0], { reduceMotion: true, statusText: '' }), 1);
  assert.equal(evaluate(argumentsFor(risk, '.opacity')[0], { reduceMotion: false, statusText: '' }), .35);
  assert.equal((risk.match(/RiskVerifyService.getInstance\(\).cancel\(\)/g) || []).length, 2);
  assert.match(risk, /\.onAppear\(\(\) => \{\s*this.loadCaptcha\(this.req.gt, this.req.challenge\)/);

  const WallpaperLayer = component('WallpaperLayer');
  const wallpaper = new WallpaperLayer(); const fades = animating(wallpaper);
  const waits = new Map();
  WallpaperLayer.luminance = name => new Promise(resolve => waits.set(name, resolve));
  const resolve = async (name, value) => { waits.get(name)(value); await Promise.resolve(); };
  wallpaper.applyImage('first'); await resolve('first', .4);
  assert.equal(wallpaper.imgOpacity, .4); assert.equal(fades.at(-1).duration, 1000);
  const sequence = wallpaper.imageSequence; wallpaper.rotateTimer = 17;
  wallpaper.reduceMotion = true; wallpaper.onMotionChanged();
  assert.equal(fades.at(-1).duration, 0, 'watcher requests zero-duration opacity settlement');
  assert.equal(wallpaper.imageSequence, sequence); assert.equal(wallpaper.rotateTimer, 17);
  assert.equal(wallpaper.imgSrc, 'file://first', 'changing motion does not reload the wallpaper');
  const beforeReduced = fades.length;
  wallpaper.applyImage('second'); await resolve('second', .8);
  assert.equal(wallpaper.imgOpacity, .8); assert.equal(fades.length, beforeReduced);
  wallpaper.applyImage('old'); wallpaper.applyImage('new'); await resolve('old', .1);
  assert.equal(wallpaper.imgOpacity, .8, 'stale luminance still cannot overwrite the newest image');
  wallpaper.isDark = true; await resolve('new', .3);
  assert.equal(wallpaper.imgOpacity, .7);
  wallpaper.reduceMotion = false; wallpaper.onMotionChanged();
  wallpaper.applyImage('pending'); wallpaper.reduceMotion = true; wallpaper.onMotionChanged();
  const beforePending = fades.length; await resolve('pending', .5);
  assert.equal(fades.length, beforePending, 'pending luminance reads the latest motion preference');
  wallpaper.reduceMotion = false; wallpaper.applyImage('normal'); await resolve('normal', .6);
  assert.equal(fades.at(-1).duration, 1000); assert.equal(wallpaper.imgOpacity, .4);
  wallpaper.applyImage('detached'); wallpaper.aboutToDisappear(); await resolve('detached', .2);
  assert.equal(wallpaper.imgOpacity, .4, 'existing teardown invalidation is preserved');

  for (const name of ['components/PressCard', 'components/HomeGachaCard', 'components/RiskVerifyModal',
    'components/WallpaperLayer', 'pages/Index']) assert.match(source(name), /@StorageProp\('reduceMotion'\)/, name);
  console.log('motion-consumers: PASS (press reset, navigation/sidebar behavior, reactive transition/paging/pulse policies, wallpaper immediate/fade and stale-result paths; native animation interruption/rendering still unverified)');
})().catch(error => { console.error(error); process.exitCode = 1; });

const wikiMotionSource = require('node:fs').readFileSync(require('node:path').resolve(__dirname, '../entry/src/main/ets/pages/WikiAvatarPage.ets'), 'utf8');
assert.match(wikiMotionSource, /@StorageProp\('reduceMotion'\) reduceMotion/);
assert.match(wikiMotionSource, /\.duration\(this\.reduceMotion \? 0 : 240\)/);
assert.match(wikiMotionSource, /\.curve\(this\.reduceMotion \? Curve\.Linear : Curve\.Ease\)/);

assert.match(wikiMotionSource, /\.effectMode\(this\.reduceMotion \? EdgeEffect\.None : EdgeEffect\.Spring\)/);
assert.doesNotMatch(wikiMotionSource, /\.edgeEffect\(this\.reduceMotion/);
