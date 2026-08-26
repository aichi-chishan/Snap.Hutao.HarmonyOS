/**
 * ErrorHint.ets
 * 统一错误态组件（含重试）。
 */
@Component
export struct ErrorHint {
  text: string = '加载失败';
  icon: string = '⚠️';
  onRetry: () => void = () => {
  };

  build() {
    Column({ space: 10 }) {
      Text(this.icon)
        .fontSize(44)
      Text(this.text)
        .fontSize(13)
        .fontColor($r('app.color.danger'))
        .textAlign(TextAlign.Center)
        .width('100%')
      Button('重试')
        .fontSize(13)
        .height(32)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          this.onRetry();
        })
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }
}
