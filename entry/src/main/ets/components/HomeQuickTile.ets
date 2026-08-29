/**
 * HomeQuickTile.ets
 * 主页快查卡（对齐 Windows 版底部功能卡）：图标 + 大数字 + 描述 + 可点击。
 */
@Component
export struct HomeQuickTile {
  /** 图标 */
  icon: string = '✨';
  /** 大数值 */
  value: string = '--';
  /** 数值描述 */
  label: string = '--';
  /** 点击回调 */
  onTap: () => void = () => {
  };

  build() {
    Row({ space: 12 }) {
      Text(this.icon)
        .fontSize(22)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.app_primary_bg'))
      Column({ space: 2 }) {
        Text(this.value)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.label)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(64)
    .padding(10)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      this.onTap();
    })
  }
}
