/**
 * Loading.ets
 * 统一加载态组件。
 */
@Component
export struct Loading {
  @Prop text: string = '';

  build() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.app_primary'))
        .accessibilityLevel('no')
      Text(this.text.length > 0 ? this.text : $r('app.string.common_loading'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }
}
