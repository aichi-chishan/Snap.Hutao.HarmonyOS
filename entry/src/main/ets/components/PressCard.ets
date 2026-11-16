/**
 * PressCard.ets
 * 按压反馈容器卡（QTapButton 的容器形态）：
 * 外壳承担圆角、UiSurface 材质与按压缩放；内容保持透明。
 */
import { Motion } from '../common/Motion';
import { CardSurfaceModifier } from '../common/UiSurface';

@Component
export struct PressCard {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  /** 内容插槽 */
  @BuilderParam content: () => void;
  /** 点击回调 */
  onTap: () => void = () => {
  };
  /** 按下缩放（默认 0.97） */
  @Prop pressScaleTo: number = 0.97;
  @StorageProp('reduceMotion') @Watch('onMotionChanged') reduceMotion: boolean = false;
  /** 卡片壳圆角（默认 12） */
  @Prop radius: number = 12;
  /** 是否启用柔和投影（对齐 Windows Acrylic 卡片层次；默认开启） */
  @Prop shadowEnabled: boolean = true;
  /** 是否撑满父容器高度（Grid 显式行高下行内等高用） */
  @Prop fillHeight: boolean = false;

  /** 按压缩放（回弹） */
  @State pressScale: number = 1;

  aboutToAppear(): void {
    this.pressScale = 1;
  }

  onMotionChanged(): void {
    if (this.reduceMotion) {
      this.pressScale = 1;
    }
  }

  /** 处理按压状态：缩放动画切换 */
  private handleTouch(type: TouchType): void {
    if (this.reduceMotion) {
      this.pressScale = 1;
      return;
    }
    if (type === TouchType.Down) {
      this.getUIContext().animateTo({ duration: 90, curve: Curve.EaseOut }, () => {
        this.pressScale = this.pressScaleTo;
      });
    } else if (type === TouchType.Up || type === TouchType.Cancel) {
      this.getUIContext().animateTo({ duration: 260, curve: Motion.springFast() }, () => {
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
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, this.shadowEnabled))
    .scale({ x: this.reduceMotion ? 1 : this.pressScale, y: this.reduceMotion ? 1 : this.pressScale })
    .hoverEffect(HoverEffect.Highlight)
    .animation({ duration: this.reduceMotion ? 0 : 90, curve: Curve.EaseOut })
    .onBlur(() => {
      this.pressScale = 1;
    })
    .onTouch((event: TouchEvent) => {
      this.handleTouch(event.type);
    })
    .onClick(() => {
      this.onTap();
    })
  }
}
