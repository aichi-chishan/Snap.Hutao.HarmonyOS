/**
 * GachaTimelineCard.ets
 * 主页卡池时间轴卡（对齐 Windows 版顶部卡池横幅）：横向滚动卡池卡（名称/时间/星级色）。全本地数据。
 */
@Component
export struct GachaTimelineCard {
  /** 池名称 */
  name: string = '--';
  /** 描述 */
  desc: string = '--';
  /** 颜色（星级/主题色） */
  color: string = '#FF6B35';
  /** 剩余文案（如 '进行中'） */
  status: string = '';

  build() {
    Row({ space: 10 }) {
      Text('✦')
        .fontSize(22)
        .fontColor(this.color)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.app_primary_bg'))
      Column({ space: 3 }) {
        Text(this.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.desc)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.status)
          .fontSize(10)
          .fontColor(this.color)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width(230)
    .height(92)
    .padding(12)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }
}
