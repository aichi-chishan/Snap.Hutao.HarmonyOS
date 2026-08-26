/**
 * Loading.ets
 * 统一加载态组件。
 */
@Component
export struct Loading {
  text: string = '加载中...';

  build() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.app_primary'))
      Text(this.text)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }
}
