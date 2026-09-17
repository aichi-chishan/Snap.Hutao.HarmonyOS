/**
 * HomeTravelersDiaryCard.ets
 * 主页·旅行者札记卡（对齐 Windows TravelersDiaryCard）：
 * 当月原石 + 摩拉收入摘要，点击进札记页。
 */
import { Ledger } from '../model/Ledger';
import { LedgerService } from '../service/LedgerService';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';

@Component
export struct HomeTravelersDiaryCard {
  onTap: () => void = () => {
  };
  @StorageLink('currentUid') currentUid: string = '';
  @State ledger: Ledger | undefined = undefined;
  @State loaded: boolean = false;

  aboutToAppear(): void {
    if (this.currentUid.length === 0) {
      this.loaded = true;
      return;
    }
    LedgerService.getInstance().fetchMonth(0, this.currentUid).then((l: Ledger) => {
      this.ledger = l;
      this.loaded = true;
    }).catch(() => {
      this.loaded = true;
    });
  }

  static fmt(n: number): string {
    return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
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
      // 统一 12vp 内边距；fillHeight 时撑满父级 204vp 行高，正文区纵向均衡
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'TravelersDiary', iconSize: 20 })
          Text('旅行者札记')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(this.loaded
            ? (this.currentUid.length === 0 ? '未登录' : (this.ledger !== undefined ? this.ledger.nickname : '未获取'))
            : '...')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(24)
        .flexShrink(0)

        if (this.loaded && this.ledger !== undefined) {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(`◆ ${HomeTravelersDiaryCard.fmt(this.ledger.monthData.currentPrimogems)}`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.app_primary'))
              Text('当月原石')
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column({ space: 2 }) {
              Text(`◉ ${HomeTravelersDiaryCard.fmt(this.ledger.monthData.currentMora)}`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text('当月摩拉')
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .alignSelf(ItemAlign.Stretch)
          .layoutWeight(this.fillHeight ? 1 : 0)
          .alignItems(this.fillHeight ? VerticalAlign.Center : VerticalAlign.Top)
        } else if (this.loaded) {
          Text('暂无札记数据')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .layoutWeight(this.fillHeight ? 1 : 0)
            .textAlign(this.fillHeight ? TextAlign.Center : TextAlign.Start)
        } else {
          Row() {
            LoadingProgress()
              .width(18)
              .height(18)
              .color($r('app.color.app_primary'))
          }
          .width('100%')
          .layoutWeight(this.fillHeight ? 1 : 0)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height(this.fillHeight ? '100%' : undefined)
      .padding(12)
    }
  }
}
