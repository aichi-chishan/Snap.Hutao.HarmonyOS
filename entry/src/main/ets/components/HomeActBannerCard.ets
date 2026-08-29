/**
 * HomeActBannerCard.ets
 * 主页活动横幅卡（对齐 Windows 主页活动卡：渊月螺旋/幽境危战·星芒之役 等）：
 * 顶部类型图标 + 名称、剩余时间、日期区间、进度徽标。整卡可点击 → 活动日历。
 */
import { ActCalendarEntry, ActCalendarType } from '../model/ActCalendarEntry';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';

@Component
export struct HomeActBannerCard {
  @Prop entry: ActCalendarEntry = new ActCalendarEntry();
  onTap: () => void = () => {
  };

  isOngoing(): boolean {
    return this.entry.isOngoing(Date.now());
  }

  /** 剩余时间（进行中=距结束；否则距开始） */
  remainText(): string {
    const now: number = Date.now();
    if (!this.isOngoing()) {
      if (this.entry.startTime > now) {
        return `剩余时间：${ActCalendarEntry.timeSpan(this.entry.startTime - now)}`;
      }
      return '已结束';
    }
    return `剩余时间：${ActCalendarEntry.timeSpan(this.entry.endTime - now)}`;
  }

  build() {
    PressCard({
      onTap: () => {
        this.onTap()
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Row({ space: 10 }) {
        // 左侧类型图标块（官方素材；活动→Database，卡池→GachaLog）
        Stack({ alignContent: Alignment.Center }) {
          NavIcon({ name: this.entry.type === ActCalendarType.CARD_POOL ? 'GachaLog' : 'Database', iconSize: 24 })
        }
        .width(52)
        .height(52)
        .borderRadius(12)
        .backgroundColor(this.isOngoing() ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))

        Column({ space: 5 }) {
          Row({ space: 6 }) {
            Text(this.entry.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.entry.statusText(Date.now()))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isOngoing() ? $r('app.color.success') : $r('app.color.notice_on'))
          }
          .width('100%')

          Text(this.remainText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(`${HomeActBannerCard.timestamp(this.entry.startTime)} 至 ${HomeActBannerCard.timestamp(this.entry.endTime)}`)
            .fontSize(9)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(12)
    }
  }

  private static timestamp(ts: number): string {
    if (ts <= 0) {
      return '--';
    }
    const d: Date = new Date(ts);
    return `${d.getFullYear()}/${HomeActBannerCard.pad(d.getMonth() + 1)}/${HomeActBannerCard.pad(d.getDate())}`;
  }

  private static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }
}
