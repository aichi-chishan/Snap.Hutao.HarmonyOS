const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.TYPESCRIPT_PATH || '../ci/node_modules/typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const keyCodes = { KEYCODE_DPAD_UP:2012, KEYCODE_DPAD_DOWN:2013, KEYCODE_DEL:2055,
  KEYCODE_ESCAPE:2070, KEYCODE_FORWARD_DEL:2071 };

function harness(initial = []) {
  const modules = new Map();
  const state = { updates:[], focusRequests:[], scrollRequests:[] };
  const source = fs.readFileSync(path.join(root, 'components/CharacterFilterBox.ets'), 'utf8');
  function load(name) {
    if (modules.has(name)) return modules.get(name);
    let text = fs.readFileSync(path.join(root, name + '.ets'), 'utf8');
    if (name === 'components/CharacterFilterBox') {
      // Execute the component's lifecycle and event methods. Native builders stay in the SDK parser check.
      text = text.slice(0, text.indexOf('  @Builder')) + '\n}';
      text = text.replace(/@(?:Component|Link|State|StorageProp\([^)]*\)|Watch\([^)]*\))\s*/g, '')
        .replace('export struct CharacterFilterBox', 'export class CharacterFilterBox');
    }
    const compiled = ts.transpileModule(text, { fileName:name + '.ts', reportDiagnostics:true,
      compilerOptions:{ module:ts.ModuleKind.CommonJS, target:ts.ScriptTarget.ES2022 } });
    assert.equal(compiled.diagnostics.length, 0, name);
    const module = { exports:{} };
    const requireLocal = id => {
      if (id === '@kit.InputKit') return { KeyCode:keyCodes };
      if (id.endsWith('/UiSurface')) return {};
      assert.ok(id.startsWith('.'), id);
      return load(path.posix.normalize(path.posix.join(path.posix.dirname(name), id)));
    };
    vm.runInNewContext('(function(require,module,exports){' + compiled.outputText + '\n})', {
      KeyType:{ Down:0, Up:1 },
      Scroller:class { scrollTo(options) { state.scrollRequests.push(options); } }
    })(requireLocal, module, module.exports);
    modules.set(name, module.exports);
    return module.exports;
  }
  const { CharacterFilterToken:Token, CharacterFilterKind:Kind } = load('viewmodel/CharacterFilter');
  const { CharacterFilterBox } = load('components/CharacterFilterBox');
  const box = new CharacterFilterBox();
  let tokens = initial.map(label => Token.fromText(label));
  Object.defineProperty(box, 'tokens', {
    get:() => tokens,
    set:next => {
      assert.notEqual(next, tokens, 'commit must replace the array for the parent Watch');
      tokens = next;
      state.updates.push(Array.from(next, token => token.label));
      box.onTokensChanged();
    }
  });
  box.getUIContext = () => ({ getFocusController:() => ({ requestFocus:id => state.focusRequests.push(id) }) });
  box.aboutToAppear();
  function callback(method, occurrence = 0) {
    const marker = '.' + method + '(';
    let offset = -1;
    for (let index = 0; index <= occurrence; index++) offset = source.indexOf(marker, offset + 1);
    assert.ok(offset >= 0, 'native event attachment ' + method);
    const start = offset + marker.length;
    const scanner = ts.createScanner(ts.ScriptTarget.Latest, false, ts.LanguageVariant.Standard, source.slice(start));
    let depth = 1;
    while (depth > 0) {
      const token = scanner.scan();
      assert.notEqual(token, ts.SyntaxKind.EndOfFileToken, method);
      if (token === ts.SyntaxKind.OpenParenToken) depth++;
      if (token === ts.SyntaxKind.CloseParenToken) depth--;
    }
    const argument = source.slice(start, start + scanner.getTokenPos());
    const script = ts.transpileModule('module.exports = ' + argument + ';', {
      compilerOptions:{ module:ts.ModuleKind.CommonJS, target:ts.ScriptTarget.ES2022 }
    }).outputText;
    const target = { exports:{} };
    vm.runInNewContext('(function(module){' + script + '\n})').call(box, target);
    return target.exports;
  }
  return { box, state, Token, Kind, callback, labels:() => Array.from(box.tokens, token => token.label),
    key(code, type = 0) {
      const event = { type, keyCode:keyCodes[code], stopped:0, stopPropagation() { this.stopped++; } };
      box.handleKey(event);
      return event;
    }
  };
}

test('focus and actual text-change callback only update suggestions until the user submits', () => {
  const h = harness();
  h.callback('onFocus')();
  assert.equal(h.box.popupVisible, true);
  assert.equal(h.box.candidates.length, 15);
  assert.equal(h.box.candidates[0].label, '四星');
  h.callback('onChange')('火');
  assert.deepEqual(Array.from(h.box.candidates, token => token.label), ['火']);
  assert.deepEqual(h.labels(), []);
  assert.equal(h.state.updates.length, 0);
  h.callback('onBlur')();
  assert.equal(h.box.popupVisible, false);
  assert.equal(h.box.query, '火');
  h.callback('onFocus')();
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['火']);
  assert.equal(h.box.query, '');
  assert.equal(h.box.tokens[0].kind, h.Kind.Element);
});

test('suggestion clicks and free-name submission commit one new parent array each', () => {
  const h = harness();
  h.box.focusInput();
  h.box.chooseSuggestion(h.box.candidates[0]);
  assert.deepEqual(h.labels(), ['四星']);
  const snapshot = h.box.tokens;
  h.box.changeText('胡桃');
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['四星', '胡桃']);
  assert.deepEqual(Array.from(snapshot, token => token.label), ['四星']);
  assert.equal(h.box.tokens[1].kind, h.Kind.Name);
  assert.equal(h.state.updates.length, 2);
  h.box.changeText('四星');
  h.box.submitQuery();
  assert.equal(h.state.updates.length, 2);
  assert.deepEqual(h.labels(), ['四星', '胡桃']);
});

test('space-delimited input commits complete words and keeps the final word as a draft', () => {
  const h = harness();
  h.box.focusInput();
  h.box.changeText('  四星 火 胡');
  assert.deepEqual(h.labels(), ['四星', '火']);
  assert.equal(h.box.query, '胡');
  h.box.changeText('胡桃 ');
  assert.deepEqual(h.labels(), ['四星', '火', '胡桃']);
  assert.equal(h.box.query, '');
  h.box.changeText('   ');
  assert.equal(h.state.updates.length, 3);
});

test('the fifth token commits and a sixth token remains editable without updating parent filters', () => {
  const h = harness();
  h.box.focusInput();
  h.box.changeText('四星 火 弓 胡桃 五星 ');
  assert.equal(h.labels().length, h.Token.LIMIT);
  assert.equal(h.box.popupVisible, false);
  h.box.changeText('水 ');
  assert.equal(h.box.query, '水');
  h.box.submitQuery();
  h.box.chooseSuggestion(h.Token.fromText('雷'));
  assert.deepEqual(h.labels(), ['四星', '火', '弓', '胡桃', '五星']);
  assert.equal(h.state.updates.length, 5);
  h.box.removeToken(h.box.tokens[3]);
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['四星', '火', '弓', '五星', '水']);
});

test('native submit callback retains editing focus and commits the current query once', () => {
  const h = harness();
  h.callback('onChange')('胡桃');
  const event = { kept:0, keepEditableState() { this.kept++; } };
  h.callback('onSubmit')(0, event);
  assert.equal(event.kept, 1);
  assert.deepEqual(h.labels(), ['胡桃']);
  assert.equal(h.state.updates.length, 1);
});

test('selected-token typing replaces its original position even when all five slots are occupied', () => {
  const h = harness(['四星', '火', '弓', '胡桃', '五星']);
  h.box.selectToken(h.box.tokens[1]);
  assert.equal(h.state.updates.length, 0);
  assert.equal(h.box.popupVisible, true);
  h.box.changeText('水');
  assert.deepEqual(h.labels(), ['四星', '弓', '胡桃', '五星']);
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['四星', '水', '弓', '胡桃', '五星']);
  h.box.selectToken(h.box.tokens[3]);
  h.box.chooseSuggestion(h.Token.fromText('雷'));
  assert.deepEqual(h.labels(), ['四星', '水', '弓', '雷', '五星']);
});

test('IME preview text never commits partial words or removes the selected token', () => {
  const h = harness(['火']);
  h.box.selectToken(h.box.tokens[0]);
  h.callback('onChange')('水 ', { offset:0, value:'shui' });
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['火']);
  assert.equal(h.state.updates.length, 0);
  h.callback('onChange')('水 ', { offset:0, value:'' });
  assert.deepEqual(h.labels(), ['水']);
  assert.equal(h.box.query, '');
});

test('arrow navigation selects the first or last candidate and Escape preserves committed tokens', () => {
  const h = harness();
  h.box.focusInput();
  assert.equal(h.key('KEYCODE_DPAD_UP').stopped, 1);
  assert.equal(h.box.activeSuggestion, 14);
  assert.equal(h.state.scrollRequests.at(-1).yOffset, 11 * 44);
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['岩']);
  h.key('KEYCODE_DPAD_DOWN');
  assert.equal(h.box.activeSuggestion, 0);
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['岩', '四星']);
  assert.equal(h.key('KEYCODE_ESCAPE').stopped, 1);
  assert.equal(h.box.popupVisible, false);
  assert.deepEqual(h.labels(), ['岩', '四星']);
  h.key('KEYCODE_DPAD_DOWN', 1);
  assert.equal(h.box.activeSuggestion, -1);
});

test('Backspace selects then deletes a token, and Delete removes an explicitly selected token', () => {
  const h = harness(['四星', '火', '弓']);
  h.box.focusInput();
  h.key('KEYCODE_DEL');
  assert.deepEqual(h.labels(), ['四星', '火', '弓']);
  assert.equal(h.box.selectedKey, h.box.tokens[2].key);
  h.key('KEYCODE_DEL');
  assert.deepEqual(h.labels(), ['四星', '火']);
  h.box.selectToken(h.box.tokens[0]);
  h.key('KEYCODE_FORWARD_DEL');
  assert.deepEqual(h.labels(), ['火']);
});

test('clear removes all tokens and draft in one update, while detached handlers cannot update filters', () => {
  const h = harness(['四星', '火']);
  h.box.changeText('胡');
  h.box.clearAll();
  assert.deepEqual(h.labels(), []);
  assert.equal(h.box.query, '');
  assert.equal(h.box.selectedKey, '');
  assert.equal(h.state.updates.length, 1);
  h.box.aboutToDisappear();
  h.box.chooseSuggestion(h.Token.fromText('五星'));
  h.box.changeText('胡桃 ');
  h.box.clearAll();
  h.box.submitQuery();
  assert.equal(h.state.updates.length, 1);
  assert.equal(h.box.popupVisible, false);
});

test('a stale candidate click and externally removed token do not create duplicate or missing entries', () => {
  const h = harness();
  h.box.focusInput();
  const stale = h.box.candidates[0];
  h.box.chooseSuggestion(stale);
  h.box.chooseSuggestion(stale);
  assert.deepEqual(h.labels(), ['四星']);
  h.box.selectToken(h.box.tokens[0]);
  h.box.tokens = [h.Token.fromText('水')];
  assert.equal(h.box.selectedKey, '');
  h.box.changeText('胡桃');
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['水', '胡桃']);
});

test('two equal free-text submissions each occupy a slot and can be removed independently', () => {
  const h = harness();
  h.box.changeText('胡桃');
  h.box.submitQuery();
  h.box.changeText('胡桃');
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['胡桃', '胡桃']);
  const [first, second] = h.box.tokens;
  h.box.selectToken(second);
  h.box.removeToken(first);
  assert.equal(h.box.tokens.length, 1);
  assert.equal(h.box.selectedKey, second.key);
  h.box.changeText('宵宫');
  h.box.submitQuery();
  assert.deepEqual(h.labels(), ['宵宫']);
});
