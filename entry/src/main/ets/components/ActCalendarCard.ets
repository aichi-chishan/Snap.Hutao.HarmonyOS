/**
 * ActCalendarCard.ets
 * 主页活动卡片（对齐 Windows 版活动网格）：名称/剩余天数/状态色条。
 */
@Component
export struct ActCalendarCard {
  /** 活动名称 */
  name: string = '--';
  /** 状态文案（如 '30 天后结束' / '进行中'） */
  status: string = '';
  /** 活动类型（1 活动 / 2 卡池） */
  isCardPool: boolean = false;

  build() {
    Row({ space: 10 }) {
      Text(this.isCardPool ? '✦' : '🗓️')
        .fontSize(20)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor(this.isCardPool ? $r('app.color.app_primary_bg') : $r('app.color.notice_bg'))
      Column({ space: 3 }) {
        Text(this.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.status)
          .fontSize(11)
          .fontColor(this.isCardPool ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(76)
    .padding(12)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }
}
