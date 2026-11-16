const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function harness(available = true, supported = true) {
  const state = { mode: 1, level: 1, ambient: 0.5 };
  const storage = new Map([['materialMode', 1], ['materialLevel', 1]]);
  const uiMaterial = { Material: { empty: 'empty-material' }, ImmersiveStyle: { ULTRA_THIN: 0, THIN: 1, REGULAR: 2, THICK: 3 },
    isImmersiveMaterialSupported: () => supported,
    ImmersiveMaterial: class { constructor(options) { this.options = options; } } };
  const mocks = {
    '@kit.ArkUI': { uiMaterial }, '@kit.BasicServicesKit': { deviceInfo: { apiAvailable: () => available } },
    '../data/prefs/PreferencesStore': { PreferencesStore: {
      getMaterialMode: () => state.mode, getMaterialLevel: () => state.level,
      setMaterialMode: value => state.mode = value, setMaterialLevel: value => state.level = value,
      setAmbientStrength: value => state.ambient = value,
    } }, './Logger': { Logger: { warn() {} } },
  };
  const source = fs.readFileSync(path.join(root, 'common/UiSurface.ets'), 'utf8');
  const compiled = ts.transpileModule(source, { reportDiagnostics: true,
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
  assert.equal(compiled.diagnostics.length, 0);
  const module = { exports: {} };
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports,
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    $r: name => name, Color: { Transparent: 'transparent' }, BlurStyle: { NONE: 'none', COMPONENT_THIN: 'thin',
      COMPONENT_REGULAR: 'regular', COMPONENT_THICK: 'thick', COMPONENT_ULTRA_THICK: 'ultra-thick' },
    ButtonStyleMode: { NORMAL: 'normal' }, ButtonType: { Normal: 'rectangle', Capsule: 'capsule' },
    HoverEffect: { Highlight: 'highlight' },
    require: id => { assert.ok(id in mocks, id); return mocks[id]; } });
  const node = { material: undefined, background: '', blur: undefined, effect: undefined, shadowValue: undefined, nativeCalls: 0,
    systemMaterial(value) { this.material = value; this.nativeCalls++; },
    backgroundColor(value) { this.background = value; },
    backgroundBlurStyle(value) { this.blur = value; this.effect = undefined; },
    backgroundEffect(value) { this.effect = value; this.blur = undefined; },
    shadow(value) { this.shadowValue = value; },
    menuSystemMaterial(value) { this.menuMaterial = value; },
    buttonStyle(value) { this.buttonStyleValue = value; this.background = 'system'; this.foreground = 'system'; },
    type(value) { this.buttonType = value; },
    fontSize(value) { this.buttonFontSize = value; },
    fontColor(value) { this.foreground = value; },
    border(value) { this.stroke = value; this.radius = value.radius ?? 0; },
    borderWidth(value) { this.stroke = { ...this.stroke, width: value }; },
    borderColor(value) { this.stroke = { ...this.stroke, color: value }; },
    borderRadius(value) { this.radius = value; },
    padding(value) { this.insets = value; },
    hoverEffect(value) { this.hover = value; },
  };
  return { ...module.exports, state, storage, node };
}

test('custom cards stay readable and immediately change glass level without unsupported native material', () => {
  const h = harness();
  new h.CardSurfaceModifier(1, 0).applyNormalAttribute(h.node);
  assert.equal(h.node.material, 'empty-material');
  assert.equal(h.node.effect.radius, 12);
  new h.CardSurfaceModifier(1, 2).applyNormalAttribute(h.node);
  assert.equal(h.node.material, 'empty-material');
  assert.equal(h.node.effect.radius, 24);
  new h.CardSurfaceModifier(0, 2).applyNormalAttribute(h.node);
  assert.equal(h.node.material, 'empty-material');
  assert.equal(h.node.background, 'transparent', 'the effect owns the only tinted layer');
  assert.equal(h.node.effect.color, 'app.color.card_surface');
  assert.equal(h.node.effect.radius, 16);
  assert.equal(h.node.blur, undefined, 'do not add another preset material mask');
  assert.equal(h.node.shadowValue.radius, 6);
  new h.CardSurfaceModifier(1, 1).applyNormalAttribute(h.node);
  assert.equal(h.node.material, 'empty-material');
  assert.equal(h.node.effect.radius, 18);
  assert.equal(h.node.effect.color, 'app.color.card_surface');
  assert.equal(h.node.background, 'transparent');
  assert.equal(h.node.shadowValue.radius, 6);
});

test('settings publish the new value before synchronizing legacy ambient settings', () => {
  const h = harness();
  h.UiSurface.setMode(0);
  assert.equal(h.storage.get('materialMode'), 0);
  assert.equal(h.state.ambient, 0);
  h.UiSurface.setMode(1);
  assert.equal(h.state.ambient, 0.5);
  h.UiSurface.setLevel(2);
  assert.equal(h.storage.get('materialLevel'), 2);
  assert.equal(h.state.ambient, 1);
});

test('action buttons use themed text and compact frosted or accent surfaces when the role changes', () => {
  const { AppButtonModifier, node } = harness();
  new AppButtonModifier(1, 2).applyNormalAttribute(node);
  assert.equal(node.buttonStyleValue, 'normal');
  assert.equal(node.buttonType, 'rectangle');
  assert.equal(node.buttonFontSize, 13);
  assert.equal(node.foreground, 'app.color.text_primary');
  assert.equal(node.background, 'transparent');
  assert.equal(node.effect.color, 'app.color.card_surface');
  assert.equal(node.effect.radius, 24);
  assert.equal(node.stroke.color, 'app.color.card_stroke');
  assert.equal(node.radius, AppButtonModifier.CORNER_RADIUS);
  assert.equal(node.insets.left, 12);
  assert.equal(node.hover, 'highlight');
  assert.equal(node.shadowValue.radius, 0);

  new AppButtonModifier(1, 2, true).applyNormalAttribute(node);
  assert.equal(node.background, 'app.color.app_primary');
  assert.equal(node.foreground, 'app.color.on_accent');
  assert.equal(node.effect, undefined, 'switching to primary clears the previous frosted effect');
  assert.equal(node.stroke.width, 0);
  assert.equal(node.shadowValue.radius, 0);
  assert.equal(node.radius, AppButtonModifier.CORNER_RADIUS, 'changing the border must not reset the corner radius');

  new AppButtonModifier(0, 2).applyNormalAttribute(node);
  assert.equal(node.background, 'transparent');
  assert.equal(node.effect.radius, 16);
  assert.equal(node.stroke.width, 0.5);
  new AppButtonModifier(0, 2, false, true).applyNormalAttribute(node);
  assert.equal(node.buttonType, 'capsule', 'explicit capsule variants keep their native shape');
  new AppButtonModifier(0, 2).applyNormalAttribute(node);
  assert.equal(node.buttonType, 'rectangle');
  assert.equal(node.radius, AppButtonModifier.CORNER_RADIUS);
});

test('native controls and Select menus explicitly disable application-default immersive material', () => {
  const h = harness();
  new h.SelectMaterialModifier(1, 2).applyNormalAttribute(h.node);
  assert.equal(h.node.menuMaterial, h.node.material);
  new h.SelectMaterialModifier(0, 2).applyNormalAttribute(h.node);
  assert.equal(h.node.material, 'empty-material');
  assert.equal(h.node.menuMaterial, 'empty-material');
  new h.ControlMaterialModifier(1, 0).applyNormalAttribute(h.node);
  assert.equal(h.node.material.options.style, 0);
  new h.ControlMaterialModifier(0, 0).applyNormalAttribute(h.node);
  assert.equal(h.node.material, 'empty-material');
});

test('shell keeps glass while native dialogs check both API availability and hardware support', () => {
  const h = harness();
  new h.ShellSurfaceModifier(1, -1).applyNormalAttribute(h.node);
  assert.equal(h.node.material, 'empty-material');
  assert.equal(h.node.effect.radius, 4);
  assert.equal(h.node.effect.color, 'app.color.nav_surface');
  assert.equal(h.node.background, 'transparent');
  assert.equal(h.node.shadowValue.radius, 0, 'adjoining shell surfaces must not paint shadows over each other');
  new h.ShellSurfaceModifier(1, 2).applyNormalAttribute(h.node);
  assert.equal(h.node.material, 'empty-material');
  assert.equal(h.node.effect.radius, 8);
  assert.equal(h.UiSurface.material(h.SurfaceClass.OVERLAY_MODAL, 1, 2).options.style, 3);
  const noHardware = harness(true, false);
  assert.equal(noHardware.UiSurface.dialogMaterial(), 'empty-material');
  const unsupported = harness(false);
  new unsupported.CardSurfaceModifier(1, 2).applyNormalAttribute(unsupported.node);
  assert.equal(unsupported.node.nativeCalls, 0);
  assert.equal(unsupported.node.background, 'transparent');
  assert.equal(unsupported.node.effect.color, 'app.color.card_surface');
});

test('UI surface calls read observable settings and homepage cards share the same material path', () => {
  for (const dir of ['components', 'pages']) {
    for (const name of fs.readdirSync(path.join(root, dir)).filter(name => name.endsWith('.ets'))) {
      const source = fs.readFileSync(path.join(root, dir, name), 'utf8');
      assert.doesNotMatch(source, /new (?:Card|Shell|Overlay)SurfaceModifier\(\)/, name);
    }
  }
  const index = fs.readFileSync(path.join(root, 'pages/Index.ets'), 'utf8');
  assert.match(index, /new ShellSurfaceModifier\(this\.materialModeNum, this\.materialLevelNum\)/);
  assert.match(index, /barBackgroundBlurStyle\(this\.materialEffect\(\)\.materialType === hdsMaterial\.MaterialType\.NONE/);
  const press = fs.readFileSync(path.join(root, 'components/PressCard.ets'), 'utf8');
  assert.match(press, /new CardSurfaceModifier\(this\.surfaceMode, this\.surfaceLevel/);
  assert.doesNotMatch(press, /\.backgroundEffect\(/);
});

test('shell uses one continuous backdrop and wallpaper stays sharp like the Windows reference', () => {
  const index = fs.readFileSync(path.join(root, 'pages/Index.ets'), 'utf8');
  const shell = index.slice(index.indexOf('  wideShell() {'), index.indexOf('  shellBackdrop() {'));
  const backdrop = index.slice(index.indexOf('  shellBackdrop() {'), index.indexOf('  topBar() {'));
  const sideNav = index.slice(index.indexOf('  sideNav() {'), index.indexOf('  navItemHome('));
  assert.ok(shell.indexOf('WallpaperLayer(') < shell.indexOf('this.shellBackdrop()'));
  assert.ok(shell.indexOf('this.shellBackdrop()') < shell.indexOf('this.topBar()'));
  assert.match(shell, /\.padding\(\{ top: this\.topAvoidVp \}\)/, 'keep the verified status-bar inset on the foreground');
  assert.equal((backdrop.match(/\.attributeModifier\(this\.panelMaterial\(\)\)/g) || []).length, 2);
  assert.match(backdrop, /\.height\(this\.topAvoidVp \+ 40\)/);
  assert.match(backdrop, /\.layoutWeight\(1\)/, 'the sidebar backdrop occupies only the height below the top strip');
  assert.match(backdrop, /HitTestMode\.BLOCK_DESCENDANTS/, 'decorative materials cannot consume control touches');
  assert.doesNotMatch(sideNav, /\.attributeModifier\(this\.panelMaterial\(\)\)|\.backgroundBlurStyle\(/);
  const wallpaper = fs.readFileSync(path.join(root, 'components/WallpaperLayer.ets'), 'utf8');
  assert.doesNotMatch(wallpaper, /\.blur\(|\.saturate\(|\.brightness\(/);
  assert.match(wallpaper, /\.opacity\(this\.imgOpacity\)/);
  for (const theme of ['base', 'dark']) {
    const colors = JSON.parse(fs.readFileSync(path.join(root, `../resources/${theme}/element/color.json`), 'utf8')).color;
    for (const name of ['nav_surface', 'nav_selected']) {
      const value = colors.find(item => item.name === name)?.value;
      assert.match(value, /^#[0-9a-f]{8}$/i);
      assert.ok(parseInt(value.slice(1, 3), 16) <= 32, `${theme} ${name} keeps a light tint`);
    }
  }
});
