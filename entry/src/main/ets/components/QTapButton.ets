/**
 * QTapButton.ets
 * Q弹感按钮组件：官方 hdsEffect pointLight 按压光效（手指跟随光源）+ 弹性缩放回弹。
 * 官方 API：@kit.UIDesignKit hdsEffect（API 20+，本工程最低 API 24）。
 * 用法：
 *   QTapButton({ label: '刷新', icon: '✨', capsule: true, onTap: () => { ... } })
 */
import { hdsEffect } from '@kit.UIDesignKit';
import { Motion } from '../common/Motion';

@Component
export struct QTapButton {
  /** 按钮文字 */
  @Prop label: string = '';
  /** 可选图标（emoji） */
  @Prop icon: string = '';
  /** 胶囊形态（默认矩形圆角） */
  @Prop capsule: boolean = false;
  /** 禁用态 */
  @Prop @Watch('onEnabledChanged') disabled: boolean = false;
  /** 主题色按钮（默认主色背景白字） */
  @Prop primary: boolean = true;
  /** 调用方可关闭按压缩放与点光源；本组件不自行读取系统设置。 */
  @Prop @Watch('onMotionChanged') reduceMotion: boolean = false;
  /** 点击回调 */
  onTap: () => void = () => {
  };

  /** 按压光源状态 */
  @State pressed: boolean = false;
  /** 按压缩放（0.98 → 1 回弹） */
  @State pressScale: number = 1;

  private resetPress(): void {
    this.pressed = false;
    this.pressScale = 1;
  }

  onEnabledChanged(): void {
    if (this.disabled) {
      this.resetPress();
    }
  }

  onMotionChanged(): void {
    if (this.reduceMotion) {
      this.resetPress();
    }
  }

  aboutToAppear(): void {
    this.resetPress();
  }

  private handleClick(): void {
    if (!this.disabled) {
      this.onTap();
    }
  }

  /** 处理按压状态：光源与缩放在同一 animateTo 闭包内切换（避免动画间隙更新状态） */
  private handleTouch(type: TouchType): void {
    if (this.disabled || this.reduceMotion) {
      this.resetPress();
      return;
    }
    if (type === TouchType.Down) {
      this.getUIContext().animateTo(Motion.easeOut(90), () => {
        this.pressed = true;
        this.pressScale = 0.98;
      });
    } else if (type === TouchType.Up || type === TouchType.Cancel) {
      this.getUIContext().animateTo({ curve: Motion.springFast() }, () => {
        this.resetPress();
      });
    }
  }

  build() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 6 }) {
        if (this.icon.length > 0) {
          Text(this.icon)
            .fontSize(15)
            .flexShrink(0)
            .accessibilityLevel('no')
        }
        Text(this.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primary ? $r('sys.color.font_on_primary') : $r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .flexShrink(1)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding({
      left: this.capsule ? 20 : 14,
      right: this.capsule ? 20 : 14,
      top: this.capsule ? 10 : 8,
      bottom: this.capsule ? 10 : 8,
    })
    .backgroundColor(this.primary ? $r('app.color.app_primary') : $r('app.color.card_surface'))
    .border({ width: this.primary ? 0 : 1, color: $r('app.color.card_stroke') })
    .borderRadius(this.capsule ? 22 : 12)
    .enabled(!this.disabled)
    .accessibilityGroup(true)
    .accessibilityText(this.label.length > 0 ? this.label : this.icon)
    .opacity(this.disabled ? 0.5 : 1)
    .hoverEffect(this.disabled ? HoverEffect.None : HoverEffect.Highlight)
    .scale({ x: this.disabled || this.reduceMotion ? 1 : this.pressScale,
      y: this.disabled || this.reduceMotion ? 1 : this.pressScale })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.pressed && !this.disabled && !this.reduceMotion ?
          hdsEffect.PointLightSourceType.BRIGHT : hdsEffect.PointLightSourceType.NONE,
        illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
      })
      .buildEffect())
    .onBlur(() => {
      this.resetPress();
    })
    .onTouch((event: TouchEvent) => {
      this.handleTouch(event.type);
    })
    .onClick(() => {
      this.handleClick();
    })
  }
}
