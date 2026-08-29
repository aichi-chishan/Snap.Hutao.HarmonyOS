/**
 * HomeAnnouncementCard.ets
 * 主页公告预览卡（对齐 Windows 主页公告区）：最新 3-6 条公告标题 + 时间 + 类型徽章，可点击进入公告页。
 */
import { Announcement } from '../model/Announcement';
import { NavIcon } from './NavIcon';
import { PressCard } from './PressCard';

@Component
export struct HomeAnnouncementCard {
  @Prop items: Announcement[] = [];
  @Prop loaded: boolean = false;
  onTapAnnouncement: (id: number) => void = (id: number) => {
  };
  onTapMore: () => void = () => {
  };

  @Builder
  header() {
    Row({ space: 8 }) {
      NavIcon({ name: 'Announcement', iconSize: 20 })
      Text('游戏公告')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text('查看全部 ›')
        .fontSize(12)
        .fontColor($r('app.color.app_primary'))
        .onClick(() => {
          this.onTapMore()
        })
    }
    .width('100%')
  }

  @Builder
  emptyView() {
    Text('暂无公告')
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ top: 8, bottom: 8 })
  }

  @Builder
  itemRow(item: Announcement) {
    Row({ space: 8 }) {
      Text(item.typeName)
        .fontSize(9)
        .fontColor($r('app.color.app_primary'))
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(6)
        .backgroundColor($r('app.color.app_primary_bg'))
      Text(item.title)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(HomeAnnouncementCard.formatDate(item.startTime))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .onClick(() => {
      this.onTapAnnouncement(item.id)
    })
  }

  build() {
    PressCard({
      onTap: () => {
        this.onTapMore()
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Column({ space: 7 }) {
        this.header()
        if (!this.loaded) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color($r('app.color.app_primary'))
            Text('加载中...')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        } else if (this.items.length === 0) {
          this.emptyView()
        } else {
          ForEach(this.items, (item: Announcement) => {
            this.itemRow(item)
          }, (item: Announcement) => `ann_${item.id}_${item.title}`)
        }
      }
      .width('100%')
      .padding(14)
    }
  }

  private static formatDate(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d: Date = new Date(ts);
    return `${d.getMonth() + 1}.${d.getDate()}`;
  }
}
