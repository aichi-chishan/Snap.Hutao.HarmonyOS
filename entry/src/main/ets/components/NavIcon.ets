/**
 * NavIcon.ets
 * Windows 版胡桃启动器导航图标（64x64 原版 assets，复制为 media/nav_*.png）。
 * 注意：使用 $r('app.media.nav_*') 静态资源引用（rawfile 方式在当前构建不可用）。
 * 用法：NavIcon({ name: 'GachaLog' }) / NavIcon({ name: 'DailyNote', iconSize: 22 })
 */
@Component
export struct NavIcon {
  /** 图标名（对应 media/nav_{name}.png） */
  name: string = '';
  /** 显示尺寸（宽高一致） */
  iconSize: number = 20;

  build() {
    Image(NavIcon.resolve(this.name))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
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
