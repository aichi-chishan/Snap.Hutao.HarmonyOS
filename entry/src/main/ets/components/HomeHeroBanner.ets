import { CardSurfaceModifier } from '../common/UiSurface';

/** 主页欢迎横幅。 */
@Component
export struct HomeHeroBanner {
  @Prop title: ResourceStr = $r('app.string.ui_home_greeting');
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;

  build() {
    Row() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .borderRadius(8)
  }
}
