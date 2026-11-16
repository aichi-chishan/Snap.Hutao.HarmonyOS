const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const { test } = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

function harness() {
  let source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/HomeSignInCard.ets'), 'utf8');
  source = source.slice(0, source.indexOf('  @Builder')) + '}';
  source = source.replace(/@Component\s+export struct/, 'export class');
  const code = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true,
  } }).outputText;
  const module = { exports: {} }, frames = [], scrolls = [];
  vm.runInNewContext(code, {
    module, exports: module.exports, Component() {}, Prop() {}, State() {},
    Watch: () => () => {}, StorageProp: () => () => {}, ScrollAlign: { START: 0 },
    Scroller: class { scrollToIndex(...args) { scrolls.push(args); } },
    require: name => name === '@kit.ArkUI' ? { FrameCallback: class {} } :
      name.endsWith('/WikiMetaService') ? { WikiMetaService: { getMaterials: async () => new Map() } } : {},
  });
  const card = new module.exports.HomeSignInCard();
  card.getUIContext = () => ({ postFrameCallback: frame => frames.push(frame) });
  card.fillHeight = true; card.loaded = true; card.uid = '100000001';
  card.info = { signedDays: 19, currentMonth: 11, rewards: Array.from({ length: 30 }, (_, day) => ({ day: day + 1 })) };
  return { card, frames, scrolls, present() { const pending = frames.splice(0); for (const frame of pending) frame.onIdle(0); } };
}

test('initial reward view positions the next reward row after layout and preserves manual scrolling', () => {
  const h = harness(); h.card.aboutToAppear();
  assert.equal(h.scrolls.length, 0);
  h.card.scheduleRewardScroll(); assert.equal(h.frames.length, 1);
  h.present(); assert.deepEqual(h.scrolls, [[14, false, 0]]);
  h.card.scheduleRewardScroll(); h.present();
  assert.equal(h.scrolls.length, 1, 'an unchanged data refresh does not reset a manual scroll');
});

test('claiming the seventh reward retains its row; a new month starts at the next unclaimed reward', () => {
  const h = harness(); h.card.info.signedDays = 6; h.card.aboutToAppear(); h.present();
  h.card.info = { ...h.card.info, signedDays: 7 }; h.card.scheduleRewardScroll(); h.present();
  assert.equal(h.scrolls.at(-1)[0], 0, 'successful claim focuses the current reward rather than day 8');
  h.card.info = { ...h.card.info, currentMonth: 12, signedDays: 7 }; h.card.scheduleRewardScroll(); h.present();
  assert.equal(h.scrolls.at(-1)[0], 7);
  h.card.uid = '100000002'; h.card.info = { ...h.card.info, signedDays: 30 }; h.card.scheduleRewardScroll(); h.present();
  assert.equal(h.scrolls.at(-1)[0], 28, 'completed month stays within valid reward indices');
});

test('natural-height, unloaded and detached grids never receive a scroll request', () => {
  const h = harness(); h.card.fillHeight = false; h.card.aboutToAppear();
  assert.equal(h.frames.length, 0);
  h.card.fillHeight = true; h.card.loaded = false; h.card.scheduleRewardScroll();
  assert.equal(h.frames.length, 0);
  h.card.loaded = true; h.card.scheduleRewardScroll(); h.card.aboutToDisappear(); h.present();
  assert.equal(h.scrolls.length, 0);
});
