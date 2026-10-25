/**
 * UiSurface.ets
 * 全局界面材质令牌层（对齐 Windows ControlMaterial/MaterialTheme 的统一令牌 + 设置页
 * 「材质：默认 / 液态玻璃」二态切换）：
 *   - 模式：普通材质（磨砂半透明 + 发丝描边 + 柔和阴影，非纯色）/ 高级材质（沉浸光感 systemMaterial）
 *   - 级别（仅高级材质）：跟随系统推荐 / 低 / 中 / 高
 *   - 同一类界面（导航壳层 / 悬浮页签 / 全局浮层 / 内容卡片）使用同一材质槽位；
 *     设备间（手机/平板/PC）槽位一致，仅呈现表面不同（侧栏 vs 底部页签）。
 * 状态经 AppStorage（materialMode / materialLevel）发布，壳层与页面即时响应；
 * 偏好持久化在 PreferencesStore，并回写旧键 app.ambient_strength 保证旧备份兼容。
 */
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { Logger } from './Logger';

const TAG: string = 'UiSurface';

/** 界面材质模式 */
export enum MaterialMode {
  /** 普通材质：磨砂半透明 + 阴影（非纯色） */
  NORMAL = 0,
  /** 高级材质：沉浸光感 systemMaterial（API26+；低版本自动回退普通材质） */
  IMMERSIVE = 1
}

/** 高级材质级别（-1 跟随系统推荐） */
export enum MaterialLevel {
  ADAPTIVE = -1,
  LOW = 0,
  MID = 1,
  HIGH = 2
}

/** 材质槽位（一类界面一个槽位；同类跨设备同槽位） */
export enum SurfaceClass {
  /** 导航壳层：宽屏侧边栏 */
  SHELL_NAV = 0,
  /** 悬浮页签：手机底部栏 */
  FLOATING_BAR = 1,
  /** 全局浮层：风控验证等 Overlay */
  OVERLAY_MODAL = 2,
  /** 内容表面：卡片 / 中性按钮 / 弹窗面板 */
  CONTENT_SURFACE = 3
}

/** 卡片/中性表面的柔和阴影（普通材质的高级感来源之一；避免大片纯色扁平） */
export class UiSurface {
  private static apiImmersive: boolean | undefined = undefined;

  /** API26 沉浸光感能力（进程内缓存；探测失败视为不可用） */
  static immersiveApiAvailable(): boolean {
    if (UiSurface.apiImmersive === undefined) {
      try {
        UiSurface.apiImmersive = deviceInfo.apiAvailable('26.0.0');
      } catch (e) {
        Logger.warn(TAG, `api probe fail: ${(e as Error).message}`);
        UiSurface.apiImmersive = false;
      }
    }
    return UiSurface.apiImmersive === true;
  }

  /** 当前模式（AppStorage 实时值；未发布时读偏好） */
  static mode(): MaterialMode {
    const cached: number = AppStorage.get<number>('materialMode') ?? -1;
    if (cached >= 0) {
      return cached === MaterialMode.IMMERSIVE ? MaterialMode.IMMERSIVE : MaterialMode.NORMAL;
    }
    return PreferencesStore.getMaterialMode();
  }

  /** 当前级别 */
  static level(): MaterialLevel {
    const cached: number = AppStorage.get<number>('materialLevel') ?? -99;
    if (cached !== -99) {
      return cached as MaterialLevel;
    }
    return PreferencesStore.getMaterialLevel();
  }

  /** 高级材质是否实际生效（模式开启且 API 支持） */
  static immersiveActive(): boolean {
    return UiSurface.mode() === MaterialMode.IMMERSIVE && UiSurface.immersiveApiAvailable();
  }

  /** 读取偏好并发布到 AppStorage（启动与设置变更时调用） */
  static publish(): void {
    AppStorage.setOrCreate<number>('materialMode', PreferencesStore.getMaterialMode());
    AppStorage.setOrCreate<number>('materialLevel', PreferencesStore.getMaterialLevel());
  }

  /** 设置模式（持久化 + 发布 + 旧键回写保持备份兼容） */
  static setMode(mode: MaterialMode): void {
    PreferencesStore.setMaterialMode(mode);
    UiSurface.syncLegacyAmbient();
    UiSurface.publish();
  }

  /** 设置级别 */
  static setLevel(level: MaterialLevel): void {
    PreferencesStore.setMaterialLevel(level);
    UiSurface.syncLegacyAmbient();
    UiSurface.publish();
  }

  /** 旧键 app.ambient_strength 回写（旧备份导入链与旧版本回滚兼容） */
  private static syncLegacyAmbient(): void {
    if (UiSurface.mode() === MaterialMode.NORMAL) {
      PreferencesStore.setAmbientStrength(0);
      return;
    }
    const level: MaterialLevel = UiSurface.level();
    PreferencesStore.setAmbientStrength(level === MaterialLevel.HIGH ? 1 : 0.5);
  }

  /** 槽位 → ImmersiveStyle：同类同风格；级别整体抬升/降低所有槽位（壳层比内容表面厚一档） */
  private static styleOf(surface: SurfaceClass, level: MaterialLevel): uiMaterial.ImmersiveStyle {
    const thickShell: boolean = surface !== SurfaceClass.CONTENT_SURFACE;
    switch (level) {
      case MaterialLevel.LOW:
        return thickShell ? uiMaterial.ImmersiveStyle.THIN : uiMaterial.ImmersiveStyle.ULTRA_THIN;
      case MaterialLevel.MID:
        return thickShell ? uiMaterial.ImmersiveStyle.REGULAR : uiMaterial.ImmersiveStyle.THIN;
      case MaterialLevel.HIGH:
      case MaterialLevel.ADAPTIVE: // 跟随系统推荐：取系统常规沉浸档
      default:
        return thickShell ? uiMaterial.ImmersiveStyle.THICK : uiMaterial.ImmersiveStyle.REGULAR;
    }
  }

  private static cachedMaterials: Map<number, uiMaterial.Material> = new Map();

  /** 取槽位材质实例（按槽位+级别缓存；普通模式或 API 不支持返回 undefined） */
  static material(surface: SurfaceClass): uiMaterial.Material | undefined {
    if (!UiSurface.immersiveActive()) {
      return undefined;
    }
    const level: MaterialLevel = UiSurface.level();
    const key: number = surface * 16 + (level + 2);
    let material: uiMaterial.Material | undefined = UiSurface.cachedMaterials.get(key);
    if (material === undefined) {
      try {
        material = new uiMaterial.ImmersiveMaterial({
          style: UiSurface.styleOf(surface, level),
          // 全局浮层带投影悬浮感；其余槽位交给系统默认
          applyShadow: surface === SurfaceClass.OVERLAY_MODAL
        });
        UiSurface.cachedMaterials.set(key, material);
      } catch (e) {
        Logger.warn(TAG, `create material fail: ${(e as Error).message}`);
        return undefined;
      }
    }
    return material;
  }
}

/**
 * 统一表面修饰器：一类界面一个实例类，全部经 UiSurface 槽位取材质。
 * 普通材质：磨砂底色（card_surface 半透明）+ 柔和阴影（非纯色扁平）；
 * 高级材质：systemMaterial（沉浸光感）。组件重建时 applyNormalAttribute 重读当前模式。
 */
export class SurfaceModifier implements AttributeModifier<CommonAttribute> {
  private readonly surface: SurfaceClass;

  constructor(surface: SurfaceClass) {
    this.surface = surface;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    const material: uiMaterial.Material | undefined = UiSurface.material(this.surface);
    if (material !== undefined) {
      instance.systemMaterial(material);
      return;
    }
    // 普通材质（或高级材质不可用回退）：非纯色高级感 = 半透明表面 + 柔和阴影
    instance.backgroundColor($r('app.color.card_surface'));
    instance.shadow(SurfaceModifier.shadowOf(this.surface));
  }

  private static shadowOf(surface: SurfaceClass): ShadowOptions {
    if (surface === SurfaceClass.OVERLAY_MODAL) {
      return { radius: 24, offsetY: 8, color: $r('app.color.card_shadow') };
    }
    if (surface === SurfaceClass.SHELL_NAV || surface === SurfaceClass.FLOATING_BAR) {
      return { radius: 10, offsetY: 2, color: $r('app.color.card_shadow') };
    }
    return { radius: 6, offsetY: 2, color: $r('app.color.card_shadow') };
  }
}

/** 内容表面（卡片/中性按钮/弹窗面板）统一修饰器 */
export class CardSurfaceModifier extends SurfaceModifier {
  constructor() {
    super(SurfaceClass.CONTENT_SURFACE);
  }
}

/** 导航壳层统一修饰器 */
export class ShellSurfaceModifier extends SurfaceModifier {
  constructor() {
    super(SurfaceClass.SHELL_NAV);
  }
}

/** 全局浮层统一修饰器 */
export class OverlaySurfaceModifier extends SurfaceModifier {
  constructor() {
    super(SurfaceClass.OVERLAY_MODAL);
  }
}
