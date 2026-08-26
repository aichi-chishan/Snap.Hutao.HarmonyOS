/**
 * QTapButton.ets
 * Q弹感按钮组件：官方 hdsEffect pointLight 按压光效（手指跟随光源）+ 弹性缩放回弹。
 * 官方 API：@kit.UIDesignKit hdsEffect（API 20+，本工程 API23 可用）。
 * 用法：
 *   QTapButton({ label: '刷新', icon: '✨', capsule: true, onTap: () => { ... } })
 */
import { hdsEffect } from '@kit.UIDesignKit';
import { curves } from '@kit.ArkUI';

@Component
export struct QTapButton {
  /** 按钮文字 */
  label: string = '';
  /** 可选图标（emoji） */
  icon: string = '';
  /** 胶囊形态（默认矩形圆角） */
  capsule: boolean = false;
  /** 禁用态 */
  disabled: boolean = false;
  /** 主题色按钮（默认主色背景白字） */
  primary: boolean = true;
  /** 点击回调 */
  onTap: () => void = () => {
  };

  /** 按压光源状态 */
  @State pressed: boolean = false;
  /** 按压缩放（0.93 → 1 回弹） */
  @State pressScale: number = 1;

  /** 处理按压状态：切换光源 + 触发弹性缩放动画 */
  private handleTouch(type: TouchType): void {
    const uiContext = this.getUIContext();
    if (type === TouchType.Down) {
      this.pressed = true;
      uiContext.animateTo({ duration: 90, curve: Curve.EaseOut }, () => {
        this.pressScale = 0.93;
      });
    } else if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
      // 回弹：Spring 曲线产生轻微过冲
      uiContext.animateTo({ duration: 260, curve: curves.springCurve(0.1, 1, 228, 30) }, () => {
        this.pressScale = 1;
      });
    }
  }

  build() {
    Row({ space: 6 }) {
      if (this.icon.length > 0) {
        Text(this.icon)
          .fontSize(15)
      }
      Text(this.label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primary ? Color.White : $r('app.color.text_primary'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({
      left: this.capsule ? 20 : 14,
      right: this.capsule ? 20 : 14,
      top: this.capsule ? 10 : 8,
      bottom: this.capsule ? 10 : 8,
    })
    .borderRadius(this.capsule ? 22 : 12)
    .backgroundColor(this.primary ? $r('app.color.app_primary') : $r('app.color.card_background'))
    .border({ width: this.primary ? 0 : 1, color: $r('app.color.divider') })
    .opacity(this.disabled ? 0.5 : 1)
    .scale({ x: this.pressScale, y: this.pressScale })
    // 官方按压光效：按下时点光源变亮（跟随手指），支持组件范围含 Row
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.pressed ? hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
      })
      .buildEffect())
    .animation({ duration: 90, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      this.handleTouch(event.type);
    })
    .onClick(() => {
      if (!this.disabled) {
        this.onTap();
      }
    })
  }
}
