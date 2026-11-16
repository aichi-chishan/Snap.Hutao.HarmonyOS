import { HomePoolSummary, GachaArchiveStatPage } from '../service/GachaHomeStatService';
import { GachaType } from '../model/GachaType';
import { GachaPoolRules } from '../model/GachaPoolRules';
import { gachaPoolLabel } from '../common/GachaPoolLabel';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';
import { Motion } from '../common/Motion';

const DASHBOARD_POOLS: number[] = [GachaType.AVATAR_EVENT, GachaType.WEAPON_EVENT, GachaType.PERMANENT];

@Component
export struct HomeGachaCard {
  @StorageProp('reduceMotion') reduceMotion: boolean = false;
  @StorageProp('helpLocaleVersion') localeVersion: number = 0;
  @Prop fillHeight: boolean = false;
  @Prop uid: string = '';
  @Prop pools: HomePoolSummary[] = [];
  @Prop loaded: boolean = false;
  @Prop @Watch('onPagesChanged') pages: GachaArchiveStatPage[] = [];
  @State pageIndex: number = 0;
  private viewedUid: string = '';
  onTap: () => void = () => {};

  aboutToAppear(): void {
    this.onPagesChanged();
  }

  onPagesChanged(): void {
    const previous: number = this.pages.findIndex((page: GachaArchiveStatPage): boolean => page.uid === this.viewedUid);
    const preferred: number = this.pages.findIndex((page: GachaArchiveStatPage): boolean => page.uid === this.uid);
    this.pageIndex = previous >= 0 ? previous : Math.max(0, preferred);
    this.viewedUid = this.pages[this.pageIndex]?.uid ?? '';
  }

  /** GachaStatisticsSlim 固定展示角色、武器和常驻三池；已有归档的空池从零计数。 */
  private static dashboardPools(rows: HomePoolSummary[]): HomePoolSummary[] {
    return DASHBOARD_POOLS.map((type: number): HomePoolSummary => {
      const row: HomePoolSummary | undefined = rows.find((item: HomePoolSummary): boolean => item.gachaType === type);
      if (row !== undefined) { return row; }
      const empty: HomePoolSummary = new HomePoolSummary();
      empty.gachaType = type;
      return empty;
    });
  }

  private static archivePageKey(page: GachaArchiveStatPage): string {
    const counts: string[] = page.pools.map((row: HomePoolSummary): string =>
      `${row.gachaType}:${row.sinceLastFive}:${row.sinceLastFour}`);
    return `${page.uid}:${counts.join('|')}`;
  }

  @Builder
  pityBar(label: Resource, count: number, threshold: number, tint: Resource) {
    Stack() {
      Progress({ value: Math.min(count, threshold), total: threshold, type: ProgressType.Linear })
        .width('100%').height(32).style({ strokeWidth: 32, strokeRadius: 4 })
        .color(tint).backgroundColor(Color.Transparent).opacity(0.23)
      Row({ space: 2 }) {
        Text(label).fontSize(11).fontColor(tint).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`${count}`).fontSize(12).fontWeight(FontWeight.Medium).fontColor(tint).maxLines(1)
      }.width('100%').padding({ left: 5, right: 5 })
    }.width('100%').height(32).border({ width: 1, color: $r('app.color.card_stroke'), radius: 4 })
    .clip(true).accessibilityGroup(true)
  }

  @Builder
  poolPanel(summary: HomePoolSummary) {
    Column({ space: 4 }) {
      Text(gachaPoolLabel(summary.gachaType)).fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center).width('100%')
      this.pityBar($r('app.string.ui_home_pity_five'), summary.sinceLastFive,
        GachaPoolRules.fiveStarThreshold(summary.gachaType), $r('app.color.five_star'))
      this.pityBar($r('app.string.ui_home_pity_four'), summary.sinceLastFour,
        GachaPoolRules.fourStarThreshold(summary.gachaType), $r('app.color.four_star'))
    }.layoutWeight(1).height('100%').padding(4).justifyContent(FlexAlign.End)
    .border({ width: 1, radius: 5, color: $r('app.color.card_stroke') })
  }

  @Builder
  poolRow(rows: HomePoolSummary[]) {
    Row({ space: 6 }) {
      ForEach(HomeGachaCard.dashboardPools(rows), (summary: HomePoolSummary) => {
        this.poolPanel(summary)
      }, (summary: HomePoolSummary): string =>
        `${summary.gachaType}_${summary.sinceLastFive}_${summary.sinceLastFour}_${this.localeVersion}`)
    }.width('100%').height('100%')
  }

  build() {
    PressCard({ fillHeight: this.fillHeight, radius: 8, onTap: this.onTap }) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          NavIcon({ name: 'GachaLog', iconSize: 20 })
          Text($r('app.string.ui_home_pity_title')).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).maxLines(1).layoutWeight(1)
          Text(this.pages[this.pageIndex]?.uid ?? this.uid).fontSize(12)
            .fontColor($r('app.color.text_primary')).maxLines(1)
        }.width('100%').height(44).padding({ left: 7, right: 7 })
        .border({ width: 1, radius: 5, color: $r('app.color.card_stroke') })

        if (this.pages.length > 1) {
          Swiper() {
            ForEach(this.pages, (page: GachaArchiveStatPage) => {
              Column() { this.poolRow(page.pools) }.padding({ bottom: 12 }).width('100%').height('100%')
            }, (page: GachaArchiveStatPage): string => `${HomeGachaCard.archivePageKey(page)}_${this.localeVersion}`)
          }.width('100%').layoutWeight(1).index(this.pageIndex).loop(false)
          .indicator(new DotIndicator().itemWidth(5).itemHeight(5).selectedItemWidth(7).selectedItemHeight(7)
            .color($r('app.color.text_hint')).selectedColor($r('app.color.text_secondary')).bottom(0))
          .duration(this.reduceMotion ? 0 : 240)
          .curve(this.reduceMotion ? Curve.Linear : Motion.springFast())
          .effectMode(this.reduceMotion ? EdgeEffect.None : EdgeEffect.Spring)
          .onChange((idx: number) => {
            this.pageIndex = idx;
            this.viewedUid = this.pages[idx]?.uid ?? '';
          })
        } else if (!this.loaded) {
          Column() { LoadingProgress().width(24).height(24).color($r('app.color.app_primary')) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.uid.length > 0) {
          Column() { this.poolRow(this.pools) }.width('100%').layoutWeight(1)
        } else {
          Column({ space: 4 }) {
            NavIcon({ name: 'GachaLog', iconSize: 40 })
            Text($r('app.string.ui_section_wish')).fontSize(13).fontColor($r('app.color.text_secondary'))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        }
      }.width('100%').height(this.fillHeight ? '100%' : 196).padding(10)
    }
  }
}
