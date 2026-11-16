import { KeyCode } from '@kit.InputKit';
import { CardSurfaceModifier, SurfaceClass, UiSurface } from '../common/UiSurface';
import { CharacterFilterToken } from '../viewmodel/CharacterFilter';

let nextFilterInputId: number = 0;

@Component
export struct CharacterFilterBox {
  @Link @Watch('onTokensChanged') tokens: CharacterFilterToken[];
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @State query: string = '';
  @State candidates: CharacterFilterToken[] = [];
  @State selectedKey: string = '';
  @State activeSuggestion: number = -1;
  @State popupVisible: boolean = false;
  @State popupWidth: number = 280;
  private readonly inputId: string = `character-filter-${++nextFilterInputId}`;
  private attached: boolean = false;
  private focused: boolean = false;
  private composing: boolean = false;
  private insertionIndex: number = -1;
  private suggestionScroller: Scroller = new Scroller();

  aboutToAppear(): void { this.attached = true; }

  aboutToDisappear(): void {
    this.attached = false;
    this.focused = false;
    this.popupVisible = false;
  }

  onTokensChanged(): void {
    if (!this.tokens.some((token: CharacterFilterToken): boolean => token.key === this.selectedKey)) {
      this.selectedKey = '';
    }
    this.refreshSuggestions();
  }

  focusInput(): void {
    if (!this.attached) { return; }
    this.focused = true;
    this.refreshSuggestions();
  }

  blurInput(): void {
    this.focused = false;
    this.popupVisible = false;
    this.activeSuggestion = -1;
  }

  private requestInputFocus(): void {
    if (!this.attached) { return; }
    this.getUIContext().getFocusController().requestFocus(this.inputId);
    this.focusInput();
  }

  private refreshSuggestions(): void {
    this.candidates = CharacterFilterToken.suggestions(this.query, this.tokens);
    this.activeSuggestion = -1;
    this.popupVisible = this.attached && this.focused && this.candidates.length > 0 &&
      (this.tokens.length < CharacterFilterToken.LIMIT || this.selectedKey.length > 0);
  }

  selectToken(token: CharacterFilterToken): void {
    if (!this.attached) { return; }
    this.selectedKey = token.key;
    this.query = '';
    this.composing = false;
    this.insertionIndex = -1;
    this.requestInputFocus();
  }

  private startReplacement(): void {
    if (this.selectedKey.length === 0) { return; }
    const index: number = this.tokens.findIndex((token: CharacterFilterToken): boolean =>
      token.key === this.selectedKey);
    this.selectedKey = '';
    if (index < 0) { return; }
    this.insertionIndex = index;
    this.tokens = this.tokens.filter((_token: CharacterFilterToken, position: number): boolean => position !== index);
  }

  changeText(text: string, preview?: PreviewText): void {
    if (!this.attached) { return; }
    this.query = text;
    this.composing = (preview?.value.length ?? 0) > 0;
    if (!this.composing && text.length > 0) {
      this.startReplacement();
      const parts: string[] = text.split(/\s+/);
      const count: number = /\s$/.test(text) ? parts.length : parts.length - 1;
      for (let index: number = 0; index < count; index++) {
        if (parts[index].length === 0) { continue; }
        const token: CharacterFilterToken | undefined = CharacterFilterToken.fromText(parts[index]);
        if (token !== undefined && !this.commitToken(token)) {
          this.query = parts.slice(index).join(' ').trim();
          this.refreshSuggestions();
          return;
        }
      }
      this.query = /\s$/.test(text) ? '' : parts[parts.length - 1];
    }
    this.refreshSuggestions();
  }

  private commitToken(token: CharacterFilterToken): boolean {
    const replaced: number = this.tokens.findIndex((entry: CharacterFilterToken): boolean =>
      entry.key === this.selectedKey);
    const next: CharacterFilterToken[] = this.tokens.filter((_entry: CharacterFilterToken, index: number): boolean =>
      index !== replaced);
    if (next.length >= CharacterFilterToken.LIMIT || next.some((entry: CharacterFilterToken): boolean =>
      entry.key === token.key)) { return false; }
    const position: number = replaced >= 0 ? replaced : this.insertionIndex >= 0
      ? Math.min(this.insertionIndex, next.length) : next.length;
    next.splice(position, 0, token);
    this.selectedKey = '';
    this.insertionIndex = position + 1;
    this.tokens = next;
    return true;
  }

  chooseSuggestion(token: CharacterFilterToken): void {
    if (!this.attached || this.composing || !this.commitToken(token)) { return; }
    this.query = '';
    this.insertionIndex = -1;
    this.refreshSuggestions();
    this.requestInputFocus();
  }

  submitQuery(): void {
    if (!this.attached || this.composing) { return; }
    const selected: CharacterFilterToken | undefined = this.candidates[this.activeSuggestion];
    const token: CharacterFilterToken | undefined = selected ?? CharacterFilterToken.fromText(this.query);
    if (token !== undefined) {
      this.chooseSuggestion(token);
    } else {
      this.requestInputFocus();
    }
  }

  removeToken(token: CharacterFilterToken): void {
    if (!this.attached) { return; }
    const key: string = token.key;
    const index: number = this.tokens.findIndex((entry: CharacterFilterToken): boolean => entry.key === key);
    if (index < 0) { return; }
    if (this.selectedKey === key) { this.selectedKey = ''; }
    if (this.insertionIndex > index) { this.insertionIndex--; }
    this.tokens = this.tokens.filter((_entry: CharacterFilterToken, position: number): boolean => position !== index);
    this.refreshSuggestions();
  }

  clearAll(): void {
    if (!this.attached) { return; }
    this.query = '';
    this.selectedKey = '';
    this.insertionIndex = -1;
    this.composing = false;
    if (this.tokens.length > 0) { this.tokens = []; }
    this.requestInputFocus();
  }

  handleKey(event: KeyEvent): void {
    if (!this.attached || event.type !== KeyType.Down || this.composing) { return; }
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.popupVisible = false;
      this.activeSuggestion = -1;
      this.selectedKey = '';
      event.stopPropagation();
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN || event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      if (this.candidates.length === 0 || (this.tokens.length >= CharacterFilterToken.LIMIT && this.selectedKey.length === 0)) { return; }
      this.popupVisible = true;
      const direction: number = event.keyCode === KeyCode.KEYCODE_DPAD_DOWN ? 1 : -1;
      this.activeSuggestion = this.activeSuggestion < 0 ? (direction > 0 ? 0 : this.candidates.length - 1)
        : (this.activeSuggestion + direction + this.candidates.length) % this.candidates.length;
      this.scrollToSuggestion();
      event.stopPropagation();
    } else if ((event.keyCode === KeyCode.KEYCODE_DEL || event.keyCode === KeyCode.KEYCODE_FORWARD_DEL) &&
      this.query.length === 0) {
      const selected: CharacterFilterToken | undefined = this.tokens.find((token: CharacterFilterToken): boolean =>
        token.key === this.selectedKey);
      if (selected !== undefined) { this.removeToken(selected); }
      else if (event.keyCode === KeyCode.KEYCODE_DEL && this.tokens.length > 0) {
        this.selectToken(this.tokens[this.tokens.length - 1]);
      } else { return; }
      event.stopPropagation();
    }
  }

  private scrollToSuggestion(): void {
    this.suggestionScroller.scrollTo({ xOffset: 0, yOffset: Math.max(0, this.activeSuggestion - 3) * 44, animation: false });
  }

  @Builder
  private suggestionList() {
    Scroll(this.suggestionScroller) {
      Column() {
        ForEach(this.candidates, (token: CharacterFilterToken, index: number) => {
          Button(token.label, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
            .width('100%').height(44).fontSize(14).fontColor($r('app.color.text_primary'))
            .borderRadius(6).hoverEffect(HoverEffect.Highlight)
            .backgroundColor(this.activeSuggestion === index ? $r('app.color.card_inner_tint') : Color.Transparent)
            .focusable(false).focusOnTouch(false).accessibilityText(`添加筛选 ${token.label}`)
            .onClick(() => this.chooseSuggestion(token))
        }, (token: CharacterFilterToken): string => token.key)
      }.width('100%')
    }
    .width('100%').height(Math.min(220, this.candidates.length * 44))
    .scrollBar(BarState.Auto)
    .onAppear(() => this.scrollToSuggestion())
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        TextInput({ text: this.query, placeholder: $r('app.string.ui_wi_ki_avatar_auto_suggest_box_place_holder') })
          .id(this.inputId).layoutWeight(1).height(44).fontSize(14)
          .fontColor($r('app.color.text_primary')).placeholderColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent).borderRadius(6)
          .padding({ left: 10, right: 0 }).enterKeyType(EnterKeyType.Search)
          .accessibilityText('筛选角色，最多五个词条')
          .onFocus(() => this.focusInput()).onBlur(() => this.blurInput())
          .onChange((text: string, preview?: PreviewText) => this.changeText(text, preview))
          .onSubmit((_key: EnterKeyType, event: SubmitEvent) => {
            event.keepEditableState();
            this.submitQuery();
          })
          .onKeyEvent((event: KeyEvent) => this.handleKey(event))
        if (this.query.length > 0 || this.tokens.length > 0) {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([$r('app.color.text_secondary')])
          }
          .width(44).height(44).padding(0).borderRadius(6).hoverEffect(HoverEffect.Highlight)
          .focusOnTouch(false).accessibilityText('清除全部角色筛选').onClick(() => this.clearAll())
        }
        Text(`${this.tokens.length}/${CharacterFilterToken.LIMIT}`).fontSize(12)
          .fontColor($r('app.color.text_secondary')).accessibilityText(`已添加 ${this.tokens.length} 项，最多五项`)
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(18).fontColor([$r('app.color.text_secondary')])
        }
        .width(44).height(44).padding(0).borderRadius(6).hoverEffect(HoverEffect.Highlight)
        .focusOnTouch(false).accessibilityText('提交角色筛选').onClick(() => this.submitQuery())
      }
      .width('100%').height(44).padding({ right: 4 })
      .bindPopup(this.popupVisible, {
        builder: (): void => { this.suggestionList(); },
        width: this.popupWidth,
        radius: 6,
        placement: Placement.Bottom,
        enableArrow: false,
        focusable: false,
        autoCancel: true,
        systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
        backgroundBlurStyle: UiSurface.blurStyle(SurfaceClass.OVERLAY_MODAL, this.surfaceMode, this.surfaceLevel),
        popupColor: UiSurface.immersiveActive() ? Color.Transparent : $r('app.color.sheet_material_tint'),
        onStateChange: (event: PopupStateChangeParam): void => {
          if (this.attached && !event.isVisible) { this.popupVisible = false; }
        },
      })
      if (this.tokens.length > 0) {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.tokens, (token: CharacterFilterToken) => {
              Row() {
                Button(token.label, { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
                  .height(44).constraintSize({ maxWidth: 150 }).fontSize(13)
                  .fontColor($r('app.color.text_primary')).padding({ left: 10, right: 4 })
                  .borderRadius(6).hoverEffect(HoverEffect.Highlight)
                  .accessibilityText(`编辑筛选 ${token.label}`).onClick(() => this.selectToken(token))
                Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(12).fontColor([$r('app.color.text_secondary')])
                }
                .width(44).height(44).padding(0).borderRadius(6).hoverEffect(HoverEffect.Highlight)
                .focusOnTouch(false).accessibilityText(`删除筛选 ${token.label}`).onClick(() => this.removeToken(token))
              }
              .borderRadius(6)
              .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
              .border({ width: this.selectedKey === token.key ? 1 : 0.5,
                color: this.selectedKey === token.key ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
            }, (token: CharacterFilterToken): string => token.key)
          }.padding({ left: 4, right: 4 })
        }
        .width('100%').height(48).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
    }
    .width('100%').borderRadius(6)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
    .border({ width: 0.5, color: $r('app.color.card_stroke') })
    .onAreaChange((_oldArea: Area, area: Area) => {
      const widthVp: number = Number(area.width);
      if (widthVp > 0) { this.popupWidth = Math.min(480, widthVp); }
    })
  }
}
