import { Motion } from '../common/Motion';
import { LedgerDayData, LedgerIncomeSource, LedgerMonthData } from '../model/Ledger';
import { LedgerViewModel } from '../viewmodel/LedgerViewModel';
import { incomeColor, LedgerIncomeRing } from './LedgerIncomeRing';
import { MetaIcon } from './MetaIcon';
import { NavIcon } from './NavIcon';
import { PressCard } from './PressCard';

/** 两页均读取当前角色的同一份 monthInfo。 */
@Component
export struct HomeTravelersDiaryCard {
  @Prop fillHeight: boolean = false;
  onTap: () => void = () => {};
  @StorageProp('currentUid') @Watch('onOwnerChanged') currentUid: string = '';
  @StorageProp('currentUserId') @Watch('onOwnerChanged') currentUserId: number = 0;
  @StorageProp('reduceMotion') reduceMotion: boolean = false;
  @State vm: LedgerViewModel = new LedgerViewModel();
  @State loaded: boolean = false;
  @State private pageIndex: number = 0;
  private attached: boolean = false;
  private generation: number = 0;

  aboutToAppear(): void { this.attached = true; this.vm.activate(); this.onOwnerChanged(); }
  aboutToDisappear(): void { this.attached = false; this.generation++; this.vm.dispose(); }
  onOwnerChanged(): void {
    this.vm.clear();
    this.pageIndex = 0;
    const generation: number = ++this.generation;
    this.loaded = this.currentUserId <= 0 || this.currentUid.length === 0;
    if (!this.attached || this.loaded) { return; }
    const uid: string = this.currentUid;
    const owner: number = this.currentUserId;
    const owns: () => boolean = (): boolean => this.attached && this.generation === generation && this.currentUid === uid && this.currentUserId === owner;
    this.vm.load(uid, owner, owns).then(() => { if (owns()) { this.loaded = true; } });
  }

  private selectPage(index: number): void { this.pageIndex = index; }

  private formatAmount(value: number): string {
    return value.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  private amount(today: boolean, primogems: boolean): string {
    const data: LedgerDayData | LedgerMonthData | undefined = today ? this.vm.ledger?.dayData : this.vm.ledger?.monthData;
    if (data === undefined) { return '—'; }
    return this.formatAmount(primogems ? data.currentPrimogems : data.currentMora);
  }

  private emptyText(): ResourceStr {
    if (this.currentUserId <= 0) { return $r('app.string.ui_settings_not_logged_in'); }
    if (this.currentUid.length === 0) { return $r('app.string.ui_account_insights_no_account'); }
    return this.vm.message || $r('app.string.common_empty');
  }

  @Builder
  currencyCell(today: boolean, primogems: boolean) {
    Row({ space: 6 }) {
      MetaIcon({ category: 'ItemIcon', name: primogems ? 'UI_ItemIcon_201' : 'UI_ItemIcon_202', iconSize: 20 })
        .accessibilityLevel('no')
      Text(this.amount(today, primogems)).fontSize(13).fontColor($r('app.color.text_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        .accessibilityDescription(primogems ? $r('app.string.ui_travelers_diary_primogems') : $r('app.string.ui_travelers_diary_mora'))
    }.layoutWeight(1)
  }

  @Builder
  incomeRow(today: boolean) {
    Column({ space: 2 }) {
      Text(today ? $r('app.string.ui_travelers_diary_today') : $r('app.string.ui_travelers_diary_month'))
        .fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(1)
      Row({ space: 12 }) {
        this.currencyCell(today, true)
        this.currencyCell(today, false)
      }.width('100%')
    }.width('100%').layoutWeight(1).padding({ left: 8, right: 8 })
      .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center)
      .border({ width: 1, radius: 5, color: $r('app.color.card_stroke') })
  }

  @Builder
  summaryPage() {
    Column({ space: 8 }) {
      this.incomeRow(true)
      this.incomeRow(false)
    }.width('100%').height('100%').padding({ bottom: 14 })
  }

  @Builder
  sourcesPage() {
    Row({ space: 12 }) {
      if ((this.vm.ledger?.monthData.groupBy.length ?? 0) === 0) {
        Text(this.vm.ledger?.monthData.currentPrimogems === 0
          ? $r('app.string.ui_travelers_diary_no_income_source_hint') : $r('app.string.common_empty'))
          .fontSize(13).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
          .width('100%').height('100%')
          .border({ width: 1, radius: 5, color: $r('app.color.card_stroke') })
      } else {
        Stack({ alignContent: Alignment.Center }) {
          LedgerIncomeRing({ sources: this.vm.ledger?.monthData.groupBy ?? [] })
          Column({ space: 2 }) {
            MetaIcon({ category: 'ItemIcon', name: 'UI_ItemIcon_201', iconSize: 20 }).accessibilityLevel('no')
            Text(this.amount(false, true)).fontSize(12).minFontSize(9).maxFontSize(12)
              .width(62).maxLines(1).textAlign(TextAlign.Center).fontColor($r('app.color.text_primary'))
              .accessibilityDescription($r('app.string.ui_travelers_diary_primogems'))
          }
        }.flexShrink(0)
        Scroll() {
          Column({ space: 4 }) {
            ForEach(this.vm.ledger?.monthData.groupBy ?? [], (source: LedgerIncomeSource, index: number) => {
              Row({ space: 4 }) {
                Rect().width(4).height(12).radius(2).fill(incomeColor(index)).accessibilityLevel('no')
                Text(source.action || '—').fontSize(12).fontColor($r('app.color.text_primary'))
                  .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.formatAmount(source.num)).fontSize(12).fontColor($r('app.color.text_primary'))
                Text(`${source.percent}%`).fontSize(12).fontColor($r('app.color.text_secondary'))
              }.width('100%').accessibilityGroup(true)
            }, (source: LedgerIncomeSource, index: number): string => `${index}_${source.actionId}_${source.action}_${source.num}_${source.percent}`)
          }.width('100%')
        }.layoutWeight(1).constraintSize({ maxHeight: '100%' }).scrollBar(BarState.Auto)
          .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      }
    }.width('100%').height('100%').padding({ bottom: 14 })
  }

  build() {
    PressCard({ fillHeight: this.fillHeight, onTap: this.onTap }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'TravelersDiary', iconSize: 28 })
          Text($r('app.string.ui_nav_ledger')).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (this.currentUserId > 0 && this.currentUid.length > 0) {
            Text(this.currentUid).fontSize(13).fontColor($r('app.color.text_primary')).maxLines(1)
          }
        }.width('100%').height(48).padding({ left: 8, right: 8 }).flexShrink(0)
          .border({ width: 1, radius: 5, color: $r('app.color.card_stroke') })

        if (this.loaded && this.vm.ledger !== undefined) {
          Swiper() {
            this.summaryPage()
            this.sourcesPage()
          }.width('100%').height(this.fillHeight ? undefined : 142).layoutWeight(this.fillHeight ? 1 : 0)
            .index(this.pageIndex).loop(false).displayArrow(true, true)
            .indicator(new DotIndicator().itemWidth(5).itemHeight(5).selectedItemWidth(7).selectedItemHeight(7)
              .color($r('app.color.text_hint')).selectedColor($r('app.color.text_secondary')).bottom(0))
            .duration(this.reduceMotion ? 0 : 240).curve(this.reduceMotion ? Curve.Linear : Motion.springFast())
            .effectMode(this.reduceMotion ? EdgeEffect.None : EdgeEffect.Spring)
            .onChange((index: number): void => this.selectPage(index))
        } else {
          Column({ space: 4 }) {
            if (this.loaded) {
              MetaIcon({ category: 'ItemIcon', name: 'UI_ItemIcon_201', iconSize: 36 }).accessibilityLevel('no')
              Text(this.emptyText()).fontSize(12).fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            } else {
              LoadingProgress().width(24).height(24).color($r('app.color.app_primary'))
                .accessibilityText($r('app.string.ui_common_loading'))
            }
          }.width('100%').height(this.fillHeight ? undefined : 110).layoutWeight(this.fillHeight ? 1 : 0)
            .justifyContent(FlexAlign.Center)
        }
      }.width('100%').height(this.fillHeight ? '100%' : undefined).padding(12)
    }
  }
}
