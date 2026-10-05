/**
 * AppBackButton.ets
 * 全局统一返回按钮：左上角气泡 + 箭头。
 * 供各页面 header 复用，风格统一。
 */
import { router } from '@kit.ArkUI';

@Component
export struct AppBackButton {
  /** 图标按钮必须提供可读名称；调用方可传入自己的本地化文案。 */
  @Prop accessibilityLabel: string = '返回';
  /** 自定义返回动作（默认 router.back） */
  onBack: (() => void) = () => {
    router.back();
  };

  build() {
    Button() {
      Image($r('app.media.hutao_back'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.text_primary'))
        .draggable(false)
        .accessibilityLevel('no')
    }
    .type(ButtonType.Circle)
    .width(44)
    .height(44)
    .accessibilityText(this.accessibilityLabel)
    .hoverEffect(HoverEffect.Highlight)
    .backgroundColor($r('app.color.card_surface'))
    .shadow({
      radius: 10,
      color: $r('app.color.nav_scrim'),
      offsetX: 0,
      offsetY: 2,
    })
    .border({ width: 1, color: $r('app.color.card_stroke') })
    .onClick(() => {
      this.onBack();
    })
  }
}
