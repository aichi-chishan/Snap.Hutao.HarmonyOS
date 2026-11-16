/**
 * UiSurface.ets
 * 全局界面材质令牌层（对齐 Windows ControlMaterial/MaterialTheme 的统一令牌 + 设置页
 * 「材质：默认 / 液态玻璃」二态切换）：
 *   - 自绘内容保持分级磨砂；支持的原生控件、弹窗和悬浮页签使用系统沉浸材质。
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
  private static supportedImmersive: boolean | undefined = undefined;

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

  static immersiveSupported(): boolean {
    if (!UiSurface.immersiveApiAvailable()) { return false; }
    if (UiSurface.supportedImmersive === undefined) {
      try { UiSurface.supportedImmersive = uiMaterial.isImmersiveMaterialSupported(); }
      catch (_) { UiSurface.supportedImmersive = false; }
    }
    return UiSurface.supportedImmersive === true;
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
    return UiSurface.mode() === MaterialMode.IMMERSIVE && UiSurface.immersiveSupported();
  }

  /** 读取偏好并发布到 AppStorage（启动与设置变更时调用） */
  static publish(): void {
    AppStorage.setOrCreate<number>('materialMode', PreferencesStore.getMaterialMode());
    AppStorage.setOrCreate<number>('materialLevel', PreferencesStore.getMaterialLevel());
  }

  /** 设置模式（持久化 + 发布 + 旧键回写保持备份兼容） */
  static setMode(mode: MaterialMode): void {
    PreferencesStore.setMaterialMode(mode);
    UiSurface.publish();
    UiSurface.syncLegacyAmbient();
  }

  /** 设置级别 */
  static setLevel(level: MaterialLevel): void {
    PreferencesStore.setMaterialLevel(level);
    UiSurface.publish();
    UiSurface.syncLegacyAmbient();
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
        return thickShell ? uiMaterial.ImmersiveStyle.THICK : uiMaterial.ImmersiveStyle.REGULAR;
      case MaterialLevel.ADAPTIVE:
      default:
        return uiMaterial.ImmersiveStyle.REGULAR;
    }
  }

  private static cachedMaterials: Map<number, uiMaterial.Material> = new Map();

  /** 仅供支持的原生控件/弹窗/标题栏使用，普通内容容器使用 SurfaceModifier。 */
  static material(surface: SurfaceClass, mode: number = UiSurface.mode(),
    level: number = UiSurface.level()): uiMaterial.Material | undefined {
    if (mode !== MaterialMode.IMMERSIVE || !UiSurface.immersiveSupported()) {
      return undefined;
    }
    const key: number = surface * 16 + (level + 2);
    let material: uiMaterial.Material | undefined = UiSurface.cachedMaterials.get(key);
    if (material === undefined) {
      try {
        material = new uiMaterial.ImmersiveMaterial({
          style: UiSurface.styleOf(surface, level as MaterialLevel),
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

  /** 应用级 ENABLE 下，empty 才能显式关闭 Select/Toggle/弹窗的默认材质。 */
  static controlMaterial(mode: number = UiSurface.mode(), level: number = UiSurface.level()): uiMaterial.Material | undefined {
    if (!UiSurface.immersiveApiAvailable()) { return undefined; }
    return UiSurface.material(SurfaceClass.CONTENT_SURFACE, mode, level) ?? uiMaterial.Material.empty;
  }

  static dialogMaterial(mode: number = UiSurface.mode(), level: number = UiSurface.level()): uiMaterial.Material | undefined {
    if (!UiSurface.immersiveApiAvailable()) { return undefined; }
    return UiSurface.material(SurfaceClass.OVERLAY_MODAL, mode, level) ?? uiMaterial.Material.empty;
  }

  /** 自绘表面只使用一层带底色的局部磨砂，不再叠加预设材质的蒙版。 */
  static surfaceEffect(surface: SurfaceClass, mode: number, level: number): BackgroundEffectOptions {
    const shell: boolean = surface === SurfaceClass.SHELL_NAV;
    let radius: number = shell ? 4 : 16;
    if (mode === MaterialMode.IMMERSIVE) {
      if (level === MaterialLevel.LOW) { radius = shell ? 2 : 12; }
      else if (level === MaterialLevel.HIGH) { radius = shell ? 8 : 24; }
      else { radius = shell ? 4 : 18; }
    }
    if (surface === SurfaceClass.OVERLAY_MODAL) { radius += 8; }
    return {
      radius: radius,
      saturation: 1,
      brightness: 1,
      color: shell ? $r('app.color.nav_surface') : $r('app.color.card_surface'),
    };
  }

  /** 既有浮层调用兼容用的系统磨砂预设，新自绘表面使用 surfaceEffect。 */
  static blurStyle(surface: SurfaceClass, mode: number, level: number): BlurStyle {
    const content: boolean = surface === SurfaceClass.CONTENT_SURFACE;
    if (mode !== MaterialMode.IMMERSIVE || level === MaterialLevel.ADAPTIVE) {
      return content ? BlurStyle.COMPONENT_REGULAR : BlurStyle.COMPONENT_THICK;
    }
    if (level === MaterialLevel.LOW) { return content ? BlurStyle.COMPONENT_THIN : BlurStyle.COMPONENT_REGULAR; }
    if (level === MaterialLevel.HIGH) { return content ? BlurStyle.COMPONENT_THICK : BlurStyle.COMPONENT_ULTRA_THICK; }
    return content ? BlurStyle.COMPONENT_REGULAR : BlurStyle.COMPONENT_THICK;
  }
}

/**
 * 统一表面修饰器：一类界面一个实例类，全部经 UiSurface 槽位取材质。
 * 普通材质：磨砂底色（card_surface 半透明）+ 柔和阴影（非纯色扁平）；
 * 页面把 @StorageProp 模式/级别显式传入，让材质随设置刷新而无需重建页面。
 */
export class SurfaceModifier implements AttributeModifier<CommonAttribute> {
  private readonly surface: SurfaceClass;
  private readonly mode: number;
  private readonly level: number;
  private readonly shadowEnabled: boolean;

  constructor(surface: SurfaceClass, mode: number = UiSurface.mode(), level: number = UiSurface.level(),
    shadowEnabled: boolean = true) {
    this.surface = surface;
    this.mode = mode;
    this.level = level;
    this.shadowEnabled = shadowEnabled;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    this.applyTo(instance);
  }

  applyTo<T>(instance: CommonMethod<T>): void {
    // 官方 API 26：普通 Column/Row/Scroll 不在系统材质生效区域；保持磨砂回退。
    if (UiSurface.immersiveApiAvailable()) { instance.systemMaterial(uiMaterial.Material.empty); }
    instance.backgroundColor(Color.Transparent);
    instance.backgroundEffect(UiSurface.surfaceEffect(this.surface, this.mode, this.level));
    instance.shadow(this.shadowEnabled ? SurfaceModifier.shadowOf(this.surface) : { radius: 0 });
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
  constructor(mode: number = UiSurface.mode(), level: number = UiSurface.level(), shadowEnabled: boolean = true) {
    super(SurfaceClass.CONTENT_SURFACE, mode, level, shadowEnabled);
  }
}

/** 页面工具栏、表单和弹窗共用的原生按钮样式。 */
export class AppButtonModifier implements AttributeModifier<ButtonAttribute> {
  static readonly CORNER_RADIUS: number = 6;
  private readonly surface: CardSurfaceModifier | undefined;
  private readonly capsule: boolean;

  constructor(mode: number, level: number, primary: boolean = false, capsule: boolean = false) {
    this.surface = primary ? undefined : new CardSurfaceModifier(mode, level, false);
    this.capsule = capsule;
  }

  applyNormalAttribute(instance: ButtonAttribute): void {
    instance.type(this.capsule ? ButtonType.Capsule : ButtonType.Normal);
    instance.buttonStyle(ButtonStyleMode.NORMAL);
    instance.fontSize(13);
    instance.padding({ left: 12, right: 12 });
    instance.hoverEffect(HoverEffect.Highlight);
    if (this.surface !== undefined) {
      this.surface.applyTo(instance);
      instance.fontColor($r('app.color.text_primary'));
      instance.borderWidth(0.5);
      instance.borderColor($r('app.color.card_stroke'));
    } else {
      if (UiSurface.immersiveApiAvailable()) { instance.systemMaterial(uiMaterial.Material.empty); }
      instance.backgroundEffect(undefined);
      instance.backgroundColor($r('app.color.app_primary'));
      instance.fontColor($r('app.color.on_accent'));
      instance.borderWidth(0);
      instance.borderColor(Color.Transparent);
      instance.shadow({ radius: 0 });
    }
    // 普通动作只在此定义圆角；明确要求的胶囊由原生 ButtonType 按尺寸处理。
    instance.borderRadius(AppButtonModifier.CORNER_RADIUS);
  }
}

/** 导航壳层统一修饰器 */
export class ShellSurfaceModifier extends SurfaceModifier {
  constructor(mode: number = UiSurface.mode(), level: number = UiSurface.level()) {
    super(SurfaceClass.SHELL_NAV, mode, level, false);
  }
}

/** 全局浮层统一修饰器 */
export class OverlaySurfaceModifier extends SurfaceModifier {
  constructor(mode: number = UiSurface.mode(), level: number = UiSurface.level()) {
    super(SurfaceClass.OVERLAY_MODAL, mode, level);
  }
}

/** 控件只切换原生材质，保留业务设置的尺寸、配色和事件。 */
export class ControlMaterialModifier implements AttributeModifier<CommonAttribute> {
  private mode: number;
  private level: number;
  constructor(mode: number, level: number) { this.mode = mode; this.level = level; }
  applyNormalAttribute(instance: CommonAttribute): void {
    if (UiSurface.immersiveApiAvailable()) { instance.systemMaterial(UiSurface.controlMaterial(this.mode, this.level)); }
  }
}

/** Select 的下拉菜单与按钮各自配置材质。 */
export class SelectMaterialModifier implements AttributeModifier<SelectAttribute> {
  private mode: number;
  private level: number;
  constructor(mode: number, level: number) { this.mode = mode; this.level = level; }
  applyNormalAttribute(instance: SelectAttribute): void {
    if (UiSurface.immersiveApiAvailable()) {
      const material: uiMaterial.Material | undefined = UiSurface.controlMaterial(this.mode, this.level);
      instance.systemMaterial(material);
      instance.menuSystemMaterial(material);
    }
    instance.borderRadius(AppButtonModifier.CORNER_RADIUS);
    instance.fontColor($r('app.color.text_primary'));
    instance.hoverEffect(HoverEffect.Highlight);
  }
}
