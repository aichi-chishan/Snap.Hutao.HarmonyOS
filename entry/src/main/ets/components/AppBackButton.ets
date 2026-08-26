/**
 * AppBackButton.ets
 * 全局统一返回按钮：左上角气泡 + 箭头。
 * 供各页面 header 复用，风格统一。
 */
import { router } from '@kit.ArkUI';

@Component
export struct AppBackButton {
  /** 自定义返回动作（默认 router.back） */
  onBack: (() => void) = () => {
    router.back();
  };

  build() {
    Button() {
      Text('‹')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width(22)
        .textAlign(TextAlign.Center)
    }
    .type(ButtonType.Circle)
    .width(38)
    .height(38)
    .backgroundColor($r('app.color.card_background'))
    .shadow({
      radius: 10,
      color: '#26000000',
      offsetX: 0,
      offsetY: 2,
    })
    .border({ width: 1, color: $r('app.color.divider') })
    .onClick(() => {
      this.onBack();
    })
  }
}
