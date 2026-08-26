/**
 * AssetIcon.ets
 * Windows 版官方素材图标（复制自 Snap.Hutao Resource/Icon，存为 media/*.png）。
 * 元素图标：elem_Electric/Fire/Grass/Ice/Rock/Water/Wind（UI_Gcg_Buff_Common_Element_*）。
 * 指定名称显示：如 Image($r('app.media.UI_Icon_Paimon')) 由本组件统一封装。
 */
@Component
export struct AssetIcon {
  /** 素材名（media 文件名，可省略后缀） */
  name: string = '';
  /** 显示尺寸 */
  iconSize: number = 24;

  build() {
    Image(AssetIcon.resolve(this.name))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
  }

  static resolve(name: string): Resource {
    return AssetIcon.map.get(name) ?? $r('app.media.nav_Announcement');
  }

  /** 元素名（Pyro/Hydro/火/水/...）→ 素材名（elem_Fire/elem_Water/...） */
  static elemName(element: string): string {
    switch (element) {
      case 'Pyro':
      case '火':
        return 'elem_Fire';
      case 'Hydro':
      case '水':
        return 'elem_Water';
      case 'Dendro':
      case '草':
        return 'elem_Grass';
      case 'Electro':
      case '雷':
        return 'elem_Electric';
      case 'Cryo':
      case '冰':
        return 'elem_Ice';
      case 'Anemo':
      case '风':
        return 'elem_Wind';
      case 'Geo':
      case '岩':
        return 'elem_Rock';
      default:
        return '';
    }
  }

  /** 元素/通用素材静态映射 */
  private static map: Map<string, Resource> = AssetIcon.buildMap();

  private static buildMap(): Map<string, Resource> {
    const m: Map<string, Resource> = new Map();
    m.set('elem_Fire', $r('app.media.UI_Gcg_Buff_Common_Element_Fire'));
    m.set('elem_Water', $r('app.media.UI_Gcg_Buff_Common_Element_Water'));
    m.set('elem_Grass', $r('app.media.UI_Gcg_Buff_Common_Element_Grass'));
    m.set('elem_Electric', $r('app.media.UI_Gcg_Buff_Common_Element_Electric'));
    m.set('elem_Ice', $r('app.media.UI_Gcg_Buff_Common_Element_Ice'));
    m.set('elem_Wind', $r('app.media.UI_Gcg_Buff_Common_Element_Wind'));
    m.set('elem_Rock', $r('app.media.UI_Gcg_Buff_Common_Element_Rock'));
    m.set('towerStar', $r('app.media.UI_Icon_Tower_Star'));
    m.set('towerStar1', $r('app.media.UI_Icon_Tower_Star1'));
    m.set('towerStar2', $r('app.media.UI_Icon_Tower_Star2'));
    m.set('tarot4', $r('app.media.UI_Icon_RoleCombat_Reward_Tarot_04'));
    m.set('tarot5', $r('app.media.UI_Icon_RoleCombat_Reward_Tarot_05'));
    m.set('paimon', $r('app.media.UI_Icon_Paimon'));
    m.set('fetter', $r('app.media.UI_Icon_Fetter'));
    m.set('locked', $r('app.media.UI_Icon_Locked'));
    m.set('unlock', $r('app.media.UI_Icon_Unlock'));
    m.set('relic1', $r('app.media.UI_Icon_RelicType1'));
    m.set('relic2', $r('app.media.UI_Icon_RelicType2'));
    m.set('relic3', $r('app.media.UI_Icon_RelicType3'));
    m.set('relic4', $r('app.media.UI_Icon_RelicType4'));
    m.set('relic5', $r('app.media.UI_Icon_RelicType5'));
    m.set('ugcBeyond', $r('app.media.UI_Icon_UGC_Beyond'));
    return m;
  }
}
