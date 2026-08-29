/**
 * PressCard.ets
 * 按压反馈容器卡（QTapButton 的容器形态）：
 * 外壳承担圆角/背景/点光源光效（单组件同时受 12 个光源，光源照亮周围同受光组件）。
 * 使用要点（对齐官方 hdsEffect 文档）：
 *  - 受光组件若设置了 border 颜色/宽度会覆盖点光源效果 → 卡片边框由背景色差/阴影承担，不加 border
 *  - 光效形状跟随组件轮廓 → 圆角设在壳层（radius），保证发光/受光贴合圆角矩形
 *  - 光源位置固定为组件中心，滚动组件内不建议使用
 * 用法：
 *   PressCard({ onTap, cardBg: $r('app.color.card_background'), radius: 12 }) {
 *     Column() { ... }   // 内容透明，不要再画背景/边框
 *   }
 */
import { hdsEffect } from '@kit.UIDesignKit';
import { curves } from '@kit.ArkUI';

@Component
export struct PressCard {
  /** 内容插槽 */
  @BuilderParam content: () => void;
  /** 点击回调 */
  onTap: () => void = () => {
  };
  /** 按下缩放（默认 0.97） */
  pressScaleTo: number = 0.97;
  /** 卡片壳背景（Color.Transparent = 无壳底，由调用方自绘） */
  @Prop cardBg: ResourceColor = Color.Transparent;
  /** 卡片壳圆角（光效造型基准，默认 12） */
  @Prop radius: number = 12;
  /** 发光强度：false=BRIGHT（明亮，大范围）/ true=SOFT（柔和，小范围） */
  @Prop lightSoft: boolean = false;
  /** 是否启用柔和投影（对齐 Windows Acrylic 卡片层次；默认开启） */
  @Prop shadowEnabled: boolean = true;

  /** 按压光源状态 */
  @State pressed: boolean = false;
  /** 按压缩放（回弹） */
  @State pressScale: number = 1;

  /** 处理按压状态：光源与缩放在同一 animateTo 闭包内切换（避免动画间隙更新状态） */
  private handleTouch(type: TouchType): void {
    const uiContext = this.getUIContext();
    if (type === TouchType.Down) {
      uiContext.animateTo({ duration: 90, curve: Curve.EaseOut }, () => {
        this.pressed = true;
        this.pressScale = this.pressScaleTo;
      });
    } else if (type === TouchType.Up || type === TouchType.Cancel) {
      uiContext.animateTo({ duration: 260, curve: curves.springCurve(0.1, 1, 228, 30) }, () => {
        this.pressed = false;
        this.pressScale = 1;
      });
    }
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .borderRadius(this.radius)
    .backgroundColor(this.cardBg)
    .shadow(this.shadowEnabled ? {
      radius: 14,
      color: '#18000000',
      offsetX: 0,
      offsetY: 5,
    } : undefined)
    .scale({ x: this.pressScale, y: this.pressScale })
    .hoverEffect(HoverEffect.Highlight)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pointLight({
        sourceType: this.pressed
          ? (this.lightSoft ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.BRIGHT)
          : hdsEffect.PointLightSourceType.NONE,
        // 羽化边缘受光：光效贴合圆角轮廓（BORDER 直边；羽化版观感更接近 Windows Acrylic 光晕）
        illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER,
      })
      .buildEffect())
    .animation({ duration: 90, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      this.handleTouch(event.type);
    })
    .onClick(() => {
      this.onTap();
    })
  }
}
