import { CardSurfaceModifier } from '../common/UiSurface';
import { AppBackButton } from './AppBackButton';

/** 页签、筛选与页面操作共用的紧凑工具栏。 */
@Component
export struct PageToolbar {
  @Prop embedMode: boolean = true;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @BuilderParam leading: () => void = PageToolbar.emptySlot;
  @BuilderParam trailing: () => void = PageToolbar.emptySlot;

  @Builder
  static emptySlot() {}

  build() {
    Row({ space: 8 }) {
      if (!this.embedMode) {
        AppBackButton()
      }
      Row({ space: 8 }) {
        this.leading()
      }
      .layoutWeight(1)
      Row({ space: 4 }) {
        this.trailing()
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Center)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .borderRadius(8)
    .margin({ top: this.embedMode ? 0 : this.topAvoidVp })
  }
}
