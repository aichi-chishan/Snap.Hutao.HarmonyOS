/**
 * ErrorHint.ets
 * 统一错误态组件（含重试）。
 */
@Component
export struct ErrorHint {
  @Prop text: string = '';
  @Prop icon: string = '⚠️';
  onRetry: () => void = () => {
  };

  build() {
    Column({ space: 10 }) {
      Text(this.icon)
        .fontSize(44)
        .accessibilityLevel('no')
      Text(this.text.length > 0 ? this.text : $r('app.string.common_error'))
        .fontSize(13)
        .fontColor($r('app.color.danger'))
        .textAlign(TextAlign.Center)
        .width('100%')
      Button({ type: ButtonType.Normal }) {
        Text($r('app.string.common_retry'))
          .fontSize(13)
          .fontColor($r('sys.color.font_on_primary'))
          .textAlign(TextAlign.Center)
      }
        .constraintSize({ minHeight: 44 })
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .borderRadius(12)
        .backgroundColor($r('app.color.app_primary'))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText($r('app.string.common_retry'))
        .onClick(() => {
          this.onRetry();
        })
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }
}
