/**
 * HomeActCard.ets
 * 主页活动/卡池卡（Windows：活动网格 + 卡池横幅）：
 * 名称、类型标记、状态（进行中/剩 N 天）、卡池显示角色头像行。可点击 → 活动日历。
 */
import { ActCalendarEntry, ActCalendarType } from '../model/ActCalendarEntry';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';

@Component
export struct HomeActCard {
  @Prop entry: ActCalendarEntry = new ActCalendarEntry();
  onTap: () => void = () => {
  };

  isCardPool(): boolean {
    return this.entry.type === ActCalendarType.CARD_POOL;
  }

  statusText(): string {
    const now: number = Date.now();
    return this.entry.statusText(now);
  }

  build() {
    PressCard({ onTap: () => {
      this.onTap()
    } }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          // 官方 Database/活动图标（Windows 素材），无 emoji
          NavIcon({ name: this.isCardPool() ? 'GachaLog' : 'Database', iconSize: 20 })
            .width(36)
            .height(36)
            .padding(8)
            .borderRadius(10)
            .backgroundColor(this.isCardPool() ? $r('app.color.app_primary_bg') : $r('app.color.notice_bg'))
          Column({ space: 2 }) {
            Text(this.entry.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.isCardPool() ? `${this.entry.versionName}` : this.entry.desc.length > 12 ? `${this.entry.desc.substring(0, 12)}…` : this.entry.desc)
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(this.statusText())
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.entry.isOngoing(Date.now()) ? $r('app.color.success') : $r('app.color.notice_on'))
        }
        .width('100%')

        if (this.entry.avatarIcons.length > 0) {
          Row({ space: 4 }) {
            ForEach(this.entry.avatarIcons, (icon: string, idx: number) => {
              Image(icon.length > 0 ? icon : '')
                .width(26)
                .height(26)
                .borderRadius(13)
                .objectFit(ImageFit.Cover)
                .backgroundColor($r('app.color.app_primary_bg'))
            }, (icon: string, idx: number) => `act_av_${idx}_${icon}`)
            Blank()
            Text(HomeActCard.formatDate(this.entry.endTime))
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        } else {
          Row() {
            Blank()
            Text(HomeActCard.formatDate(this.entry.endTime))
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(12)
      .borderRadius($r('app.float.card_radius'))
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 1, color: this.isCardPool() ? $r('app.color.app_primary') : $r('app.color.divider') })
    }
  }

  private static formatDate(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d: Date = new Date(ts);
    return `${d.getMonth() + 1}.${d.getDate()} 结束`;
  }
}
