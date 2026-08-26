/**
 * HomeHeroBanner.ets
 * 主页欢迎横幅（对齐 Windows 版："旅行者，欢迎来到提瓦特大陆！" + 副标题装饰线）。
 */
@Component
export struct HomeHeroBanner {
  @Prop title: string = '旅行者，欢迎来到提瓦特大陆！';
  @Prop subtitle: string = '胡桃工具箱 · 祈愿记录 / 实时便笺 / 签到日历';

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('◆')
          .fontSize(12)
          .fontColor($r('app.color.app_primary'))
        Text(this.title)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Row({ space: 8 }) {
        Divider()
          .color($r('app.color.app_primary'))
          .strokeWidth(2)
          .width(36)
        Text(this.subtitle)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
    }
    .width('100%')
    .padding(2)
    .alignItems(HorizontalAlign.Start)
  }
}
