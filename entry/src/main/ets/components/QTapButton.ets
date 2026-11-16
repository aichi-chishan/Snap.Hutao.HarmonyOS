/**
 * QTapButton.ets
 * Q弹感按钮组件：官方 hdsEffect pointLight 按压光效（手指跟随光源）+ 弹性缩放回弹。
 * 官方 API：@kit.UIDesignKit hdsEffect（API 20+，本工程最低 API 24）。
 * 用法：
 *   QTapButton({ label: '刷新', icon: '✨', capsule: true, onTap: () => { ... } })
 */
import { hdsEffect } from '@kit.UIDesignKit';
import { Motion } from '../common/Motion';
import { AppButtonModifier } from '../common/UiSurface';

@Component
export struct QTapButton {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  /** 按钮文字 */
  @Prop label: ResourceStr = '';
  /** 可选图标（emoji） */
  @Prop icon: string = '';
  /** 胶囊形态（默认矩形圆角） */
  @Prop capsule: boolean = false;
  /** 禁用态 */
  @Prop @Watch('onEnabledChanged') disabled: boolean = false;
  /** 主题色按钮（默认主色背景） */
  @Prop primary: boolean = true;
  /** 调用方可额外关闭按压缩放与点光源；不能覆盖应用的减少动态效果设置。 */
  @Prop @Watch('onMotionChanged') reduceMotion: boolean = false;
  @StorageProp('reduceMotion') @Watch('onMotionChanged') appReduceMotion: boolean = false;
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
    if (this.reduceMotion || this.appReduceMotion) {
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
    if (this.disabled || this.reduceMotion || this.appReduceMotion) {
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

  private accessibilityLabel(): string {
    // 资源标签由组内 Text 自动朗读，保留语言切换响应；空字符串按钮仍朗读图标。
    return typeof this.label === 'string' ? (this.label.length > 0 ? this.label : this.icon) : '';
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
          .fontColor(this.primary ? $r('app.color.on_accent') : $r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .flexShrink(1)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width('100%')
    }
    .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, this.primary, this.capsule))
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding({
      left: this.capsule ? 20 : 14,
      right: this.capsule ? 20 : 14,
      top: this.capsule ? 10 : 8,
      bottom: this.capsule ? 10 : 8,
    })
    .enabled(!this.disabled)
    .accessibilityGroup(true)
    .accessibilityText(this.accessibilityLabel())
    .opacity(this.disabled ? 0.5 : 1)
    .hoverEffect(this.disabled ? HoverEffect.None : HoverEffect.Highlight)
    .scale({ x: this.disabled || this.reduceMotion || this.appReduceMotion ? 1 : this.pressScale,
      y: this.disabled || this.reduceMotion || this.appReduceMotion ? 1 : this.pressScale })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.pressed && !this.disabled && !this.reduceMotion && !this.appReduceMotion ?
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
