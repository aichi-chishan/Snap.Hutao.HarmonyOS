/**
 * Motion.ets
 * 全局动效令牌与构建器（对齐鸿蒙官方动效规范：弹簧曲线驱动、非对称转场、错峰进场）：
 *   - springs：统一弹性曲线（响应快、回弹自然，达终点速度归零不"戛然而止"）
 *   - pageSwitch()：内嵌页面切换的非对称转场（进场 上浮+渐显+轻缩放 / 出场 渐隐+轻缩放）
 *   - staggerDelay()：列表/卡片错峰进场的逐项延迟
 *   - riseIn()：卡片进场转场（配合 transition 用）
 */
import { curves } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

export class Motion {
  /** API 26 沉浸光感可用性（运行时门控，失败回退） */
  static detectImmersive(): boolean {
    try {
      return deviceInfo.apiAvailable('26.0.0');
    } catch (e) {
      return false;
    }
  }

  /** 常规弹性（卡片按压/选择态切换） */
  static spring(): curves.ICurve {
    return curves.springMotion(0.34, 0.86);
  }

  /** 稍快弹性（小元素） */
  static springFast(): curves.ICurve {
    return curves.springMotion(0.28, 0.9);
  }

  /** 柔和弹性（大面板/页面级） */
  static springSoft(): curves.ICurve {
    return curves.springMotion(0.42, 0.82);
  }

  /** 标准缓出（非弹性的确定动画，如蒙层渐变） */
  static easeOut(duration: number): AnimateParam {
    return { duration: duration, curve: Curve.Friction };
  }

  /**
   * 内嵌内容页切换转场：进场 = 上浮 12vp + 渐显 + 0.98→1 缩放（springSoft）；
   * 出场 = 渐隐 + 轻缩放（快）。用于 wideContent if/else 分支的容器。
   */
  static pageSwitch(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ y: 14 })
        .combine(TransitionEffect.scale({ x: 0.985, y: 0.985 }))
        .combine(TransitionEffect.OPACITY)
        .animation({ curve: Motion.springSoft() }),
      TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.995, y: 0.995 }))
        .animation({ duration: 140, curve: Curve.Sharp })
    );
  }

  /**
   * 卡片/条目进场：上浮 + 渐显（spring）。配合 staggerDelay(index) 使用。
   * repeat 标记 false 时首次进场后不再触发（if 挂载驱动）。
   */
  static riseIn(offsetVp: number = 18): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ y: offsetVp })
        .combine(TransitionEffect.OPACITY)
        .animation({ curve: Motion.springSoft() }),
      TransitionEffect.IDENTITY.animation({ duration: 0 })
    );
  }

  /** 错峰进场延迟（ms）：index 从 0 起，步进 40ms，封顶 320ms */
  static staggerDelay(index: number, stepMs: number = 40, capMs: number = 320): number {
    return Math.min(capMs, Math.max(0, index) * stepMs);
  }
}
