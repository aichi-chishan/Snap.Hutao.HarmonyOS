/**
 * ErrorHint.ets
 * 统一错误态组件（含重试）。
 */
import { AppButtonModifier } from '../common/UiSurface';

@Component
export struct ErrorHint {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
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
          .fontColor($r('app.color.on_accent'))
          .textAlign(TextAlign.Center)
      }
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
        .constraintSize({ minHeight: 44 })
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
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
