/**
 * NavIcon.ets
 * Windows 版胡桃启动器导航图标（64x64 原版 assets，复制为 media/nav_*.png）。
 * 注意：使用 $r('app.media.nav_*') 静态资源引用（rawfile 方式在当前构建不可用）。
 * 用法：NavIcon({ name: 'GachaLog' }) / NavIcon({ name: 'DailyNote', iconSize: 22 })
 *
 * 系统符号：Windows 用系统图标字体画设置等系统级图标，本项目对应鸿蒙 SymbolGlyph
 * （$r('sys.symbol.*')）。符号名由 NavIcon.usesSymbol() 判定，避免用 emoji 当图标
 * （emoji 随字体漂移、无法跟随主题色）。
 */
import { SymbolGlyphModifier } from '@kit.ArkUI';

@Component
export struct NavIcon {
  /** 图标名（对应 media/nav_{name}.png；'Setting' 等系统图标走 sys.symbol） */
  @Prop name: string = '';
  /** 显示尺寸（宽高一致） */
  @Prop iconSize: number = 20;
  /** 符号颜色（仅系统符号生效；默认品牌强调色） */
  @Prop symbolColor: ResourceColor = $r('app.color.app_primary_text');

  build() {
    if (NavIcon.usesSymbol(this.name)) {
      SymbolGlyph(NavIcon.symbolOf(this.name))
        .fontSize(this.iconSize)
        .fontColor([this.symbolColor])
        .width(this.iconSize)
        .height(this.iconSize)
    } else {
      Image(NavIcon.resolve(this.name))
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
    }
  }

  /** 是否系统符号（非 Windows 导航素材的图标） */
  static usesSymbol(name: string): boolean {
    return NavIcon.symbolOf(name) !== undefined;
  }

  /** 系统符号资源映射（$r 不可模板化，逐一显式映射） */
  static symbolOf(name: string): Resource | undefined {
    if (name === 'Setting') {
      return $r('sys.symbol.gearshape');
    }
    if (name === 'Menu') {
      return $r('sys.symbol.line_3_horizontal');
    }
    if (name === 'Delete') {
      return $r('sys.symbol.trash');
    }
    if (name === 'Warning') {
      return $r('sys.symbol.exclamationmark_triangle');
    }
    if (name === 'Close') {
      return $r('sys.symbol.xmark');
    }
    if (name === 'Check') {
      return $r('sys.symbol.checkmark');
    }
    if (name === 'Airplane') {
      return $r('sys.symbol.airplane');
    }
    if (name === 'Calendar') {
      return $r('sys.symbol.calendar');
    }
    return undefined;
  }

  /** 静态资源名解析（$r 不可模板化，逐一显式映射） */
  static resolve(name: string): Resource {
    if (name === 'Achievement') {
      return $r('app.media.nav_Achievement');
    }
    if (name === 'Announcement') {
      return $r('app.media.nav_Announcement');
    }
    if (name === 'AvatarProperty') {
      return $r('app.media.nav_AvatarProperty');
    }
    if (name === 'Backpack') {
      return $r('app.media.nav_Backpack');
    }
    if (name === 'CheckIn') {
      return $r('app.media.nav_CheckIn');
    }
    if (name === 'Cultivation') {
      return $r('app.media.nav_Cultivation');
    }
    if (name === 'DailyNote') {
      return $r('app.media.nav_DailyNote');
    }
    if (name === 'Database') {
      return $r('app.media.nav_Database');
    }
    if (name === 'Documentation') {
      return $r('app.media.nav_Documentation');
    }
    if (name === 'Feedback') {
      return $r('app.media.nav_Feedback');
    }
    if (name === 'GachaLog') {
      return $r('app.media.nav_GachaLog');
    }
    if (name === 'HardChallenge') {
      return $r('app.media.nav_HardChallenge');
    }
    if (name === 'LaunchGame') {
      return $r('app.media.nav_LaunchGame');
    }
    if (name === 'Passport') {
      return $r('app.media.nav_Passport');
    }
    if (name === 'Plugin') {
      return $r('app.media.nav_Plugin');
    }
    if (name === 'RoleCombat') {
      return $r('app.media.nav_RoleCombat');
    }
    if (name === 'SpiralAbyss') {
      return $r('app.media.nav_SpiralAbyss');
    }
    if (name === 'TravelersDiary') {
      return $r('app.media.nav_TravelersDiary');
    }
    if (name === 'WikiAvatar') {
      return $r('app.media.nav_WikiAvatar');
    }
    if (name === 'WikiMonster') {
      return $r('app.media.nav_WikiMonster');
    }
    if (name === 'WikiWeapon') {
      return $r('app.media.nav_WikiWeapon');
    }
    return $r('app.media.nav_GachaLog');
  }
}
