import { ChallengePeriod } from '../model/ChallengePeriod';
import { UiSurface } from '../common/UiSurface';

/** 深渊、剧诗和幽战共用的期次列表。 */
@Component
export struct ChallengePeriodRail {
  @Prop periods: ChallengePeriod[] = [];
  @Prop @Watch('onSelectedChanged') selectedId: number = 0;
  @Prop split: boolean = false;
  @Prop showNames: boolean = false;
  onSelect: (scheduleId: number) => void = (_scheduleId: number): void => {};
  private readonly scroller: Scroller = new Scroller();
  private awaitingInitialSelection: boolean = false;

  aboutToAppear(): void {
    this.awaitingInitialSelection = this.selectedId === 0;
  }

  onSelectedChanged(): void {
    if (this.awaitingInitialSelection && this.selectedId > 0) {
      this.awaitingInitialSelection = false;
      this.scroller.scrollToIndex(this.firstVisible(), false, ScrollAlign.START);
    }
  }

  private periodTitle(period: ChallengePeriod): string {
    const number: number = this.showNames ? ChallengePeriod.hardChallengeNumber(period.scheduleId) : period.scheduleId;
    const name: string = this.showNames && period.name.length > 0 ? `：${period.name}` : '';
    return `第 ${number} 期${name}`;
  }

  private dateRange(period: ChallengePeriod): string {
    return ChallengePeriod.detailedRange(period.startTime, period.endTime);
  }

  private firstVisible(): number {
    const selected: number = this.periods.findIndex((period: ChallengePeriod): boolean => period.scheduleId === this.selectedId);
    return Math.max(0, selected - 2);
  }

  build() {
    List({ space: 2, initialIndex: this.firstVisible(), scroller: this.scroller }) {
      ForEach(this.periods, (period: ChallengePeriod) => {
        ListItem() {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 8 }) {
              Column()
                .width(3)
                .height(16)
                .borderRadius(2)
                .backgroundColor(this.selectedId === period.scheduleId ? $r('app.color.app_primary') : Color.Transparent)
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Text(this.periodTitle(period))
                    .layoutWeight(1)
                    .fontSize(14)
                    .fontWeight(this.selectedId === period.scheduleId ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (period.summary.length > 0) {
                    Text(period.summary)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .maxLines(1)
                  }
                }.width('100%')
                if (this.dateRange(period).length > 0) {
                  Text(this.dateRange(period))
                    .width('100%')
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 4, right: 8, top: 6, bottom: 6 })
          }
          .width('100%')
          .constraintSize({ minHeight: 50 })
          .padding(0)
          .borderRadius(6)
          .backgroundColor(this.selectedId === period.scheduleId ? $r('app.color.card_inner_tint') : Color.Transparent)
          .accessibilitySelected(this.selectedId === period.scheduleId)
          .accessibilityGroup(true)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onSelect(period.scheduleId))
        }
      }, (period: ChallengePeriod): string => `${period.scheduleId}:${period.recordTime}:${period.summary}`)
    }
    .width(this.split ? 230 : '100%')
    .height('100%')
    .padding(4)
    .scrollBar(BarState.Auto)
    .backgroundColor($r('app.color.card_inner_tint'))
  }
}

@Component
export struct ChallengePeriodTabs {
  @Prop statistics: boolean = false;
  onSelect: (statistics: boolean) => void = (_statistics: boolean): void => {};

  @Builder
  tab(statistics: boolean) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 6 }) {
        Text(statistics ? $r('app.string.ui_spiral_abyss_hutao_statistics') : '分期详情')
          .fontSize(14)
          .fontWeight(this.statistics === statistics ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.statistics === statistics ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Divider().width(32).strokeWidth(2)
          .color(this.statistics === statistics ? $r('app.color.app_primary') : Color.Transparent)
      }.justifyContent(FlexAlign.Center)
    }
    .height(44)
    .padding({ left: 8, right: 8 })
    .borderRadius(6)
    .backgroundColor(Color.Transparent)
    .accessibilitySelected(this.statistics === statistics)
    .accessibilityGroup(true)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onSelect(statistics))
  }

  build() {
    Row({ space: 2 }) {
      this.tab(false)
      this.tab(true)
    }
  }
}

@Component
export struct ChallengePeriodActions {
  @Prop split: boolean = false;
  @Prop refreshEnabled: boolean = false;
  @Prop detailOpen: boolean = false;
  @Prop statistics: boolean = false;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  onInsights: () => void = () => {};
  onRefresh: () => void = () => {};
  onSwitchTab: () => void = () => {};

  private actions(): MenuElement[] {
    const items: MenuElement[] = [
      { value: $r('app.string.ui_account_insights_open'), action: (): void => { this.onInsights(); } },
    ];
    if (this.refreshEnabled) {
      items.push({ value: $r('app.string.common_refresh'), action: (): void => { this.onRefresh(); } });
    }
    if (this.detailOpen) {
      items.push({
        value: this.statistics ? '分期详情' : $r('app.string.ui_spiral_abyss_hutao_statistics'),
        action: (): void => { this.onSwitchTab(); },
      });
    }
    return items;
  }

  build() {
    Row({ space: 4 }) {
      if (this.split) {
        Button($r('app.string.ui_account_insights_open'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44).fontSize(13).fontColor($r('app.color.text_primary')).borderRadius(6)
          .backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onInsights())
        Button($r('app.string.common_refresh'), { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(44).fontSize(13).fontColor($r('app.color.text_primary')).borderRadius(6)
          .backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Highlight)
          .enabled(this.refreshEnabled).onClick(() => this.onRefresh())
      } else {
        Button('⋯', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .width(44).height(44).fontSize(20).fontColor($r('app.color.text_primary')).borderRadius(6)
          .backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Highlight)
          .accessibilityText('战绩操作')
          .bindMenu(this.actions(), { systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel) })
      }
    }
  }
}
