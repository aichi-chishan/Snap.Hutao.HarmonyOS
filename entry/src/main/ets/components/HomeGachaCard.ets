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
    .height(96)
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
    .height(112)
    .justifyContent(FlexAlign.Center)
  }

  /** 紧凑单池面板：标题 + 总抽数 + 两行保底进度（单行式，面板自然高度 <=150） */
  @Builder
  poolPanel(summary: HomePoolSummary) {
    Column({ space: 5 }) {
      Text(summary.typeName)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Row({ space: 4 }) {
        Text(`${summary.totalCount}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('抽')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 橙色（五星）保底进度（单行：进度条 + 距保底计数）
      Row({ space: 6 }) {
        Progress({
          value: Math.min(summary.sinceLastFive, ORANGE_GUARANTEE),
          total: ORANGE_GUARANTEE,
          type: ProgressType.Linear,
        })
          .width('100%')
          .layoutWeight(1)
          .color($r('app.color.five_star'))
          .style({ strokeWidth: 4 })
        Text(`五星 ${summary.sinceLastFive}/90 · 余${Math.max(0, ORANGE_GUARANTEE - summary.sinceLastFive)}抽`)
          .fontSize(12)
          .fontColor($r('app.color.five_star'))
      }
      .width('100%')

      // 紫色（四星）保底进度（单行：进度条 + 距保底计数）
      Row({ space: 6 }) {
        Progress({
          value: Math.min(summary.sinceLastFour, PURPLE_GUARANTEE),
          total: PURPLE_GUARANTEE,
          type: ProgressType.Linear,
        })
          .width('100%')
          .layoutWeight(1)
          .color($r('app.color.four_star'))
          .style({ strokeWidth: 4 })
        Text(`四星 ${summary.sinceLastFour}/10 · 余${Math.max(0, PURPLE_GUARANTEE - summary.sinceLastFour)}抽`)
          .fontSize(12)
          .fontColor($r('app.color.four_star'))
      }
      .width('100%')
    }
    .width(224)
    .height(142)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 1, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Start)
  }

    /** 是否撑满 Grid 单元格高度（行内等高） */
    @Prop fillHeight: boolean = false;

  build() {
    PressCard({
      fillHeight: this.fillHeight,
      onTap: () => {
        this.onTap()
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      // 统一 12vp 内边距；fillHeight 时撑满父级 204vp 行高，横向滚动池区占剩余空间
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
        .height(24)
        .flexShrink(0)

        if (this.loaded && this.pools.length === 0) {
          this.emptyView()
        } else if (!this.loaded) {
          this.loadingView()
        } else {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.pools, (pool: HomePoolSummary) => {
                this.poolPanel(pool)
              }, (pool: HomePoolSummary) => `${pool.gachaType}_${pool.typeName}_${pool.totalCount}_${pool.sinceLastFive}_${pool.sinceLastFour}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .width('100%')
          .alignSelf(ItemAlign.Stretch)
          .layoutWeight(this.fillHeight ? 1 : 0)
          .align(Alignment.TopStart)
        }
      }
      .width('100%')
      .height(this.fillHeight ? '100%' : undefined)
      .padding(12)
    }
  }
}
