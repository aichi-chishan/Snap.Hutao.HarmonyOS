/**
 * PressCard.ets
 * 按压反馈容器卡（QTapButton 的容器形态）：
 * 外壳承担圆角/亚克力背景/阴影/按压缩放（无点光源光效，用户要求点击不发光）。
 * 使用要点：
 *  - 卡片边框由背景色差/阴影承担，不加 border
 *  - 亚克力背景走 backgroundEffect，圆角设在壳层（radius）
 * 用法：
 *   PressCard({ onTap, cardBg: $r('app.color.card_background'), radius: 12 }) {
 *     Column() { ... }   // 内容透明，不要再画背景/边框
 *   }
 */
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
  /** 卡片壳圆角（默认 12） */
  @Prop radius: number = 12;
  /** 是否启用柔和投影（对齐 Windows Acrylic 卡片层次；默认开启） */
  @Prop shadowEnabled: boolean = true;
  /** 是否撑满父容器高度（Grid 显式行高下行内等高用） */
  @Prop fillHeight: boolean = false;

  /** 按压缩放（回弹） */
  @State pressScale: number = 1;

  /** 处理按压状态：缩放动画切换 */
  private handleTouch(type: TouchType): void {
    const uiContext = this.getUIContext();
    if (type === TouchType.Down) {
      uiContext.animateTo({ duration: 90, curve: Curve.EaseOut }, () => {
        this.pressScale = this.pressScaleTo;
      });
    } else if (type === TouchType.Up || type === TouchType.Cancel) {
      uiContext.animateTo({ duration: 260, curve: curves.springCurve(0.1, 1, 228, 30) }, () => {
        this.pressScale = 1;
      });
    }
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    // 高度：fillHeight=true 时撑满 Grid 单元格（配合 Grid 显式行高实现行内等高）；
    // 默认自适应内容。百分比高度在 Scroll>Grid 无显式行高场景会被解析为视口高（巨长卡）
    .height(this.fillHeight ? '100%' : undefined)
    .borderRadius(this.radius)
    .clip(true)
    .backgroundColor(this.cardBg)
    // 亚克力卡片（对齐 Windows AcrylicBorderCardStyle / SystemControlAcrylicElementBrush）：
    // 背景模糊 + 主题染色，壁纸透过卡片呈现"一丢丢透明度"的观感
    .backgroundEffect({
      radius: 40,
      color: $r('app.color.card_acrylic_tint'),
      saturation: 1.15,
    })
    .shadow(this.shadowEnabled ? {
      radius: 14,
      color: '#18000000',
      offsetX: 0,
      offsetY: 5,
    } : undefined)
    .scale({ x: this.pressScale, y: this.pressScale })
    .hoverEffect(HoverEffect.Highlight)
    .animation({ duration: 90, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      this.handleTouch(event.type);
    })
    .onClick(() => {
      this.onTap();
    })
  }
}
