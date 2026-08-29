/**
 * HomeGachaCard.ets
 * 主页祈愿统计卡（对齐 Windows HomeCardGachaStatisticsCard）：
 * 头部（图标+标题+UID）、下方为各池面板——大数字总抽数、橙/紫保底进度条（距上次出金/保底阈值）。
 * 有数据的池横向分块；无数据时显示引导。整卡可点击 → 祈愿页。
 */
import { HomePoolSummary } from '../viewmodel/HomeViewModel';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';

const ORANGE_GUARANTEE: number = 90;
const PURPLE_GUARANTEE: number = 10;

@Component
export struct HomeGachaCard {
  @Prop uid: string = '';
  @Prop pools: HomePoolSummary[] = [];
  @Prop total: number = 0;
  @Prop loaded: boolean = false;
  /** 点击整卡回调（进入祈愿页） */
  onTap: () => void = () => {
  };

  @Builder
  loadingView() {
    Column({ space: 8 }) {
      LoadingProgress()
        .width(24)
        .height(24)
        .color($r('app.color.app_primary'))
      Text('祈愿统计加载中...')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  emptyView() {
    Column({ space: 8 }) {
      NavIcon({ name: 'GachaLog', iconSize: 28 })
      Text('暂无祈愿记录')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Text('进入祈愿页拉取抽卡历史后可在此查看')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(140)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  poolPanel(summary: HomePoolSummary) {
    Column({ space: 6 }) {
      Text(summary.typeName)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 4 }) {
        Text(`${summary.totalCount}`)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('抽')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 橙色（五星）保底进度
      Row({ space: 6 }) {
        Progress({
          value: Math.min(summary.sinceLastFive, ORANGE_GUARANTEE),
          total: ORANGE_GUARANTEE,
          type: ProgressType.Linear,
        })
          .width(28)
          .color($r('app.color.five_star'))
          .style({ strokeWidth: 4 })
        Column({ space: 0 }) {
          Text(`${summary.sinceLastFive}`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.five_star'))
          Text('距五星')
            .fontSize(9)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(`${Math.max(0, ORANGE_GUARANTEE - summary.sinceLastFive)}抽保底`)
          .fontSize(9)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      // 紫色（四星）保底进度
      Row({ space: 6 }) {
        Progress({
          value: Math.min(summary.sinceLastFour, PURPLE_GUARANTEE),
          total: PURPLE_GUARANTEE,
          type: ProgressType.Linear,
        })
          .width(28)
          .color($r('app.color.four_star'))
          .style({ strokeWidth: 4 })
        Column({ space: 0 }) {
          Text(`${summary.sinceLastFour}`)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.four_star'))
          Text('距四星')
            .fontSize(9)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(`${Math.max(0, PURPLE_GUARANTEE - summary.sinceLastFour)}抽保底`)
          .fontSize(9)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
    }
    .width(160)
    .padding(10)
    .borderRadius(10)
    .backgroundColor($r('app.color.page_background'))
    .border({ width: 1, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    PressCard({
      onTap: () => {
        this.onTap()
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Column({ space: 10 }) {
        // 头部
        Row({ space: 8 }) {
          NavIcon({ name: 'GachaLog', iconSize: 20 })
          Text('祈愿记录')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(this.uid)
            .fontSize(12)
            .fontColor($r('app.color.app_primary'))
        }
        .width('100%')

        if (this.loaded && this.pools.length === 0) {
          this.emptyView()
        } else if (!this.loaded) {
          this.loadingView()
        } else {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.pools, (pool: HomePoolSummary) => {
                this.poolPanel(pool)
              }, (pool: HomePoolSummary) => `${pool.gachaType}_${pool.totalCount}_${pool.sinceLastFive}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
    }
  }
}
