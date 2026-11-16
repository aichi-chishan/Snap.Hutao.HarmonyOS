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
  /** plain：无独立卡片壳（嵌入合框时用） */
  @Prop plain: boolean = false;
  /** plain 模式固定行高（0=按内容自适应），与左列池行等高 */
  @Prop rowHeight: number = 0;
  onTap: () => void = () => {
  };

  isOngoing(): boolean {
    return this.entry.isOngoing(Date.now());
  }

  private hasDates(): boolean {
    return this.entry.startTime > 0 && this.entry.endTime > 0;
  }

  /** 剩余时间（进行中=距结束；否则距开始） */
  remainText(): ResourceStr {
    if (!this.hasDates()) { return $r('app.string.ui_calendar_time_pending'); }
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
    if (this.plain) {
      Column() {
        this.bannerBody()
      }
      .width('100%')
      .height(this.rowHeight > 0 ? this.rowHeight : undefined)
      .justifyContent(FlexAlign.Center)
      .padding({ top: 8, bottom: 8 })
    } else {
      PressCard({
        onTap: () => {
          this.onTap()
        },
        radius: 12,
      }) {
        Column() {
          this.bannerBody()
        }
        .width('100%')
        .padding(12)
      }
    }
  }

  @Builder
  bannerBody() {
      Row({ space: 10 }) {
        // 左侧类型图标块（官方素材；活动→Database，卡池→GachaLog）
        Stack({ alignContent: Alignment.Center }) {
          NavIcon({ name: this.entry.type === ActCalendarType.CARD_POOL ? 'GachaLog' : 'Database', iconSize: 24 })
        }
        .width(40)
        .height(40)
        .borderRadius(8)
        .backgroundColor(this.isOngoing() ? $r('app.color.app_primary_bg') : $r('app.color.card_inner_tint'))

        Column({ space: 5 }) {
          Row({ space: 6 }) {
            Text(this.entry.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.hasDates()) {
              Text(this.entry.statusText(Date.now()))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isOngoing() ? $r('app.color.success') : $r('app.color.notice_on'))
            }
          }
          .width('100%')

          Text(this.remainText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.hasDates()) {
            Text(`${HomeActBannerCard.timestamp(this.entry.startTime)} 至 ${HomeActBannerCard.timestamp(this.entry.endTime)}`)
              .fontSize(9)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
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
