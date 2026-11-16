import { parseMarkdown } from '../data/markdown/parseMarkdown';

interface AiMarkdownCell {
  text: string;
  html: string;
  alignment: string;
}

interface AiMarkdownBlock {
  kind: string;
  source: string;
  html?: string;
  text?: string;
  language?: string;
  rows?: AiMarkdownCell[][];
}

@Component
struct AiRichText {
  @Prop html: string = '';
  @Prop source: string = '';
  @Prop alignment: TextAlign = TextAlign.Start;
  @Prop bold: boolean = false;
  private readonly controller: TextController = new TextController();
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.controller.setStyledString(new StyledString(this.source));
    if (this.html.length === 0) { return; }
    StyledString.fromHtml(this.html).then((value: StyledString): void => {
      if (this.active) { this.controller.setStyledString(value); }
    }).catch(() => {});
  }

  aboutToDisappear(): void { this.active = false; }

  build() {
    Text(undefined, { controller: this.controller })
      .width('100%')
      .fontSize(15)
      .fontColor($r('app.color.text_primary'))
      .fontWeight(this.bold ? FontWeight.Medium : FontWeight.Regular)
      .textAlign(this.alignment)
      .copyOption(CopyOptions.LocalDevice)
  }
}

@Component
export struct AiMarkdown {
  @Prop @Watch('onTextChanged') text: string = '';
  @Prop streaming: boolean = false;
  @StorageProp('isDarkMode') @Watch('onTextChanged') isDarkMode: boolean = false;
  @State blocks: AiMarkdownBlock[] = [];
  private renderTimer: number = -1;
  private highlightColor: string = '';

  aboutToAppear(): void { this.updateBlocks(); }

  aboutToDisappear(): void {
    if (this.renderTimer !== -1) {
      clearTimeout(this.renderTimer);
      this.renderTimer = -1;
    }
  }

  onTextChanged(): void {
    if (!this.streaming) {
      this.updateBlocks();
    } else if (this.renderTimer === -1) {
      this.renderTimer = setTimeout(() => {
        this.renderTimer = -1;
        this.updateBlocks();
      }, 48);
    }
  }

  private updateBlocks(): void {
    const resourceColor: number | undefined = this.getUIContext().getHostContext()?.resourceManager.getColorSync(
      $r('app.color.app_primary_bg').id);
    this.highlightColor = resourceColor === undefined ? '' : `#${(resourceColor & 0xffffff).toString(16).padStart(6, '0')}`;
    try {
      this.blocks = JSON.parse(parseMarkdown(this.text, this.highlightColor)) as AiMarkdownBlock[];
    } catch (_) {
      const fallback: AiMarkdownBlock = { kind: 'rich', source: this.text };
      this.blocks = [fallback];
    }
  }

  private tableAlignment(alignment: string): TextAlign {
    if (alignment === 'center') { return TextAlign.Center; }
    return alignment === 'right' ? TextAlign.End : TextAlign.Start;
  }

  @Builder
  codeBlock(block: AiMarkdownBlock) {
    Column({ space: 4 }) {
      if ((block.language ?? '').length > 0) {
        Text(block.language).fontSize(12).fontColor($r('app.color.text_secondary')).padding({ left: 8, top: 6 })
      }
      Scroll() {
        Text(block.text ?? '').fontSize(14).fontFamily('monospace').fontColor($r('app.color.text_primary'))
          .copyOption(CopyOptions.LocalDevice).padding(8)
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
    }.width('100%').alignItems(HorizontalAlign.Start).borderRadius(6)
      .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  tableBlock(block: AiMarkdownBlock) {
    Scroll() {
      Column() {
        ForEach(block.rows ?? [], (row: AiMarkdownCell[], rowIndex: number) => {
          Row() {
            ForEach(row, (cell: AiMarkdownCell) => {
              Column() {
                AiRichText({
                  html: cell.html, source: cell.text, alignment: this.tableAlignment(cell.alignment), bold: rowIndex === 0,
                })
              }.width(140).padding(8).border({ width: { right: 1 }, color: $r('app.color.card_stroke') })
            }, (_cell: AiMarkdownCell, index: number): string => String(index))
          }.alignItems(VerticalAlign.Top).border({ width: { bottom: 1 }, color: $r('app.color.card_stroke') })
        }, (_row: AiMarkdownCell[], index: number): string => String(index))
      }.alignItems(HorizontalAlign.Start)
    }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
      .borderRadius(6).border({ width: 1, color: $r('app.color.card_stroke') })
  }

  build() {
    Column({ space: 6 }) {
      ForEach(this.blocks, (block: AiMarkdownBlock) => {
        if (block.kind === 'code') {
          this.codeBlock(block)
        } else if (block.kind === 'table') {
          this.tableBlock(block)
        } else if (block.kind === 'rule') {
          Divider().color($r('app.color.card_stroke')).width('100%')
        } else if (block.kind === 'quote') {
          Column() {
            AiRichText({ html: block.html ?? '', source: block.source })
          }.width('100%').padding({ left: 8 }).border({ width: { left: 2 }, color: $r('app.color.text_secondary') })
        } else {
          AiRichText({ html: block.html ?? '', source: block.source })
        }
      }, (block: AiMarkdownBlock, index: number): string => `${index}:${this.highlightColor}:${block.source}`)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
