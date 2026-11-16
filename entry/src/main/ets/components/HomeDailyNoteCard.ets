import { DailyNote, Expedition } from '../model/DailyNote';
import { HomeNoteEntry } from '../viewmodel/HomeViewModel';
import { CardSurfaceModifier } from '../common/UiSurface';
import { DateUtil } from '../common/DateUtil';
import { MetaIcon } from './MetaIcon';
import { NavIcon } from './NavIcon';

@Component
export struct HomeDailyNoteCard {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('reduceMotion') reduceMotion: boolean = false;
  @Prop @Watch('onEntriesChanged') entries: HomeNoteEntry[] = [];
  @Prop loaded: boolean = false;
  @Prop refreshing: boolean = false;
  @Prop fillHeight: boolean = false;
  onTap: () => void = () => {};
  onRefresh: () => void = () => {};

  @State pageIndex: number = 0;
  @State cardWidth: number = 0;
  private displayedKey: string = '';

  private static readonly LABELS: string[] = ['树脂', '洞天宝钱', '每日委托', '周本折扣', '参变仪'];
  private static readonly ICONS: string[] = ['UI_ItemIcon_106', 'UI_ItemIcon_204',
    'UI_MarkQuest_Events_Proce', 'UI_MarkTower', 'UI_ItemIcon_220021'];

  aboutToAppear(): void {
    this.onEntriesChanged();
  }

  onEntriesChanged(): void {
    if (this.entries.length === 0) {
      this.pageIndex = 0;
      return;
    }
    const displayedKey: string = this.displayedKey;
    const index: number = this.entries.findIndex((entry: HomeNoteEntry): boolean =>
      HomeDailyNoteCard.ownerKey(entry) === displayedKey);
    this.selectPage(Math.max(0, index));
  }

  private selectPage(index: number): void {
    const entry: HomeNoteEntry | undefined = this.entries[index];
    if (entry === undefined) { return; }
    this.pageIndex = index;
    this.displayedKey = HomeDailyNoteCard.ownerKey(entry);
  }

  private static ownerKey(entry: HomeNoteEntry): string {
    return `${entry.userId}:${entry.uid}`;
  }

  private static value(entry: HomeNoteEntry, slot: number): string {
    const note: DailyNote | undefined = entry.note;
    if (note === undefined) { return ''; }
    switch (slot) {
      case 0: return `${note.currentResin}/${note.maxResin}`;
      case 1: return note.formattedHomeCoin();
      case 2: return note.formattedTask();
      case 3: return note.formattedResinDiscount();
      default: return note.transformerMainText();
    }
  }

  private static hasDot(entry: HomeNoteEntry, slot: number): boolean {
    const note: DailyNote | undefined = entry.note;
    if (note === undefined) { return false; }
    switch (slot) {
      case 0: return note.resinReached(entry.resinThreshold);
      case 1: return note.homeCoinReached(entry.homeCoinThreshold);
      case 2: return note.dailyTask.isAllFinished();
      case 4: return note.transformer.isReady();
      default: return false;
    }
  }

  private static expeditionSummary(note: DailyNote): string {
    const finished: number = note.expeditions.filter((entry: Expedition): boolean => entry.isFinished()).length;
    return `派遣 ${note.currentExpeditionNum}/${note.maxExpeditionNum} · 已完成 ${finished}`;
  }

  private static entryKey(entry: HomeNoteEntry): string {
    const note: DailyNote | undefined = entry.note;
    if (note === undefined) { return HomeDailyNoteCard.ownerKey(entry); }
    const blocks: string[] = HomeDailyNoteCard.LABELS.map((_label: string, slot: number): string =>
      `${HomeDailyNoteCard.value(entry, slot)}:${HomeDailyNoteCard.hasDot(entry, slot)}`);
    return `${HomeDailyNoteCard.ownerKey(entry)}_${note.refreshTime}_${blocks.join('|')}_${HomeDailyNoteCard.expeditionSummary(note)}`;
  }

  private currentEntry(): HomeNoteEntry | undefined {
    return this.entries[this.pageIndex] ?? this.entries[0];
  }

  private heading(): ResourceStr {
    return this.currentEntry()?.uid ?? $r('app.string.card_daily_note_title');
  }

  private refreshTimeText(): string {
    const refreshTime: number = this.currentEntry()?.note?.refreshTime ?? 0;
    return refreshTime > 0 ? `刷新于 ${DateUtil.formatTimestamp(refreshTime).substring(5).replace('-', '.')}` : '尚未刷新';
  }

  private static blockDescription(entry: HomeNoteEntry, slot: number): string {
    if (slot === 0) { return entry.note?.resinRecoveryTargetText() ?? ''; }
    if (slot === 4) { return entry.note?.transformerSubText() ?? ''; }
    return '';
  }

  @Builder
  noteBlock(entry: HomeNoteEntry, slot: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: slot === 0 ? 5 : 2 }) {
        MetaIcon({ category: slot === 2 || slot === 3 ? 'Mark' : 'ItemIcon',
          name: HomeDailyNoteCard.ICONS[slot], iconSize: slot === 0 ? 64 : 24, remoteFallback: true })
        Text(HomeDailyNoteCard.value(entry, slot))
          .fontSize(slot === 0 ? 15 : 12).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .minFontSize(10).maxFontSize(slot === 0 ? 15 : 12)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
          .width('100%')
      }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      if (HomeDailyNoteCard.hasDot(entry, slot)) {
        Row().width(6).height(6).borderRadius(3).backgroundColor($r('app.color.app_primary')).margin(5)
      }
    }
    .width('100%').height(slot === 0 ? '100%' : undefined).layoutWeight(slot === 0 ? 0 : 1)
    .padding({ left: 4, right: 4, top: 3, bottom: 3 })
    .backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 1, radius: 6, color: $r('app.color.card_stroke') })
    .accessibilityGroup(true)
    .accessibilityText(`${HomeDailyNoteCard.LABELS[slot]} ${HomeDailyNoteCard.value(entry, slot)}`)
    .accessibilityDescription(HomeDailyNoteCard.blockDescription(entry, slot))
  }

  @Builder
  notePage(entry: HomeNoteEntry) {
    Column({ space: 6 }) {
      if (entry.note !== undefined) {
        Row({ space: 6 }) {
          Column() { this.noteBlock(entry, 0) }.layoutWeight(1).height('100%')
          Column({ space: 6 }) {
            this.noteBlock(entry, 1)
            this.noteBlock(entry, 2)
          }.layoutWeight(1).height('100%')
          Column({ space: 6 }) {
            this.noteBlock(entry, 3)
            this.noteBlock(entry, 4)
          }.layoutWeight(1).height('100%')
        }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Top)
        if (!this.fillHeight) {
          Text(HomeDailyNoteCard.expeditionSummary(entry.note!)).fontSize(11)
            .fontColor($r('app.color.text_secondary')).width('100%')
        }
      } else {
        Text('尚未刷新便笺').fontSize(12).fontColor($r('app.color.text_secondary'))
          .width('100%').layoutWeight(1).textAlign(TextAlign.Center)
      }
    }.width('100%').height('100%').padding({ bottom: this.entries.length > 1 ? 16 : 0 })
      .focusable(true).hoverEffect(HoverEffect.Highlight).onClick(() => this.onTap())
  }

  @Builder
  header() {
    Row({ space: 4 }) {
      Row({ space: 6 }) {
        NavIcon({ name: 'DailyNote', iconSize: 22 })
        if (this.cardWidth >= 320) {
          Text(this.heading()).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.refreshTimeText()).fontSize(10).fontColor($r('app.color.text_secondary'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).textAlign(TextAlign.End)
        } else {
          Column({ space: 1 }) {
            Text(this.heading()).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.refreshTimeText()).fontSize(10).fontColor($r('app.color.text_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
      }
      .layoutWeight(1).height(44).padding({ left: 8, right: 2 })
      .focusable(true).hoverEffect(HoverEffect.Highlight).accessibilityGroup(true)
      .accessibilityDescription('打开实时便笺').onClick(() => this.onTap())
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        if (this.refreshing) {
          LoadingProgress().width(18).height(18).color($r('app.color.app_primary'))
        } else {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(18).fontColor([$r('app.color.text_primary')])
        }
      }
      .width(44).height(44).padding(0).borderRadius(6).backgroundColor(Color.Transparent)
      .hoverEffect(HoverEffect.Highlight).enabled(this.entries.length > 0 && !this.refreshing)
      .accessibilityText(this.refreshing ? '便笺刷新中' : '刷新全部追踪便笺').onClick(() => this.onRefresh())
    }
    .width('100%').height(44).flexShrink(0)
    .backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 1, radius: 6, color: $r('app.color.card_stroke') })
  }

  build() {
    Column({ space: 6 }) {
      this.header()

      if (!this.loaded) {
        Column({ space: 8 }) {
          LoadingProgress().width(24).height(24).color($r('app.color.app_primary'))
          Text('便笺加载中').fontSize(12).fontColor($r('app.color.text_secondary'))
        }.width('100%').height(this.fillHeight ? undefined : 120)
          .layoutWeight(this.fillHeight ? 1 : 0).justifyContent(FlexAlign.Center)
      } else if (this.entries.length === 0) {
        Text('在实时便笺页添加追踪角色').fontSize(12).fontColor($r('app.color.text_secondary'))
          .width('100%').height(this.fillHeight ? undefined : 120)
          .layoutWeight(this.fillHeight ? 1 : 0).textAlign(TextAlign.Center)
      } else {
        Swiper() {
          ForEach(this.entries, (entry: HomeNoteEntry) => {
            this.notePage(entry)
          }, (entry: HomeNoteEntry): string => HomeDailyNoteCard.entryKey(entry))
        }
        .index(this.pageIndex).loop(false).indicator(this.entries.length > 1)
        .displayArrow(this.entries.length > 1, true).disableSwipe(this.entries.length < 2)
        .duration(this.reduceMotion ? 0 : 240)
        .effectMode(this.reduceMotion ? EdgeEffect.None : EdgeEffect.Spring)
        .onChange((index: number) => {
          this.selectPage(index);
        })
        .width('100%').height(this.fillHeight ? undefined : 162).layoutWeight(this.fillHeight ? 1 : 0)
      }
    }.width('100%').height(this.fillHeight ? '100%' : undefined).padding(12).borderRadius(12)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      .onAreaChange((_old: Area, area: Area): void => { this.cardWidth = Number(area.width); })
  }
}
