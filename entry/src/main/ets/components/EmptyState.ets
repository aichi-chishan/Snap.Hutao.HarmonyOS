/**
 * EmptyState.ets
 * 统一空态组件。
 */
@Component
export struct EmptyState {
  icon: string = '📭';
  text: string = '暂无数据';

  build() {
    Column({ space: 10 }) {
      Text(this.icon)
        .fontSize(52)
      Text(this.text)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }
}
