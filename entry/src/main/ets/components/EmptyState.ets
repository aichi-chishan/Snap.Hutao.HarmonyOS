/**
 * EmptyState.ets
 * 统一空态组件。
 */
@Component
export struct EmptyState {
  @Prop icon: string = '📭';
  @Prop text: string = '';

  build() {
    Column({ space: 10 }) {
      Text(this.icon)
        .fontSize(52)
        .accessibilityLevel('no')
      Text(this.text.length > 0 ? this.text : $r('app.string.common_empty'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }
}
