import { CardSurfaceModifier } from '../common/UiSurface';

@Component
export struct WikiFilterGroup {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @Prop title: ResourceStr = '';
  @Prop options: string[] = [];
  @Prop selected: string[] = [];
  onChange: (selection: string[]) => void = () => {};

  private optionLabel(option: string): ResourceStr {
    switch (option) {
      case '一星': return $r('app.string.ui_model_intrinsic_item_quality_white');
      case '二星': return $r('app.string.ui_model_intrinsic_item_quality_green');
      case '三星': return $r('app.string.ui_model_intrinsic_item_quality_blue');
      case '四星': return $r('app.string.ui_model_intrinsic_item_quality_purple');
      case '五星': return $r('app.string.ui_model_intrinsic_item_quality_orange');
      case '限定五星': return $r('app.string.ui_model_intrinsic_item_quality_red');
      case '火': return $r('app.string.ui_model_intrinsic_element_name_fire');
      case '水': return $r('app.string.ui_model_intrinsic_element_name_water');
      case '风': return $r('app.string.ui_model_intrinsic_element_name_wind');
      case '雷': return $r('app.string.ui_model_intrinsic_element_name_elec');
      case '草': return $r('app.string.ui_model_intrinsic_element_name_grass');
      case '冰': return $r('app.string.ui_model_intrinsic_element_name_ice');
      case '岩': return $r('app.string.ui_model_intrinsic_element_name_rock');
      default: return option;
    }
  }

  private toggle(option: string): void {
    this.onChange(this.selected.includes(option)
      ? this.selected.filter((value: string): boolean => value !== option)
      : this.selected.concat(option));
  }

  build() {
    Column({ space: 6 }) {
      Text(this.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.options, (option: string) => {
          Button(this.optionLabel(option), { type: ButtonType.Normal }).height(44).fontSize(13).buttonStyle(ButtonStyleMode.NORMAL)
            .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
            .fontColor(this.selected.includes(option) ? $r('app.color.app_primary_text') : $r('app.color.text_primary'))
            .border({ width: 1, radius: 10,
              color: this.selected.includes(option) ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
            .margin({ right: 8, bottom: 8 }).hoverEffect(HoverEffect.Highlight)
            .accessibilityDescription(this.selected.includes(option) ? $r('app.string.ui_option_selected') : $r('app.string.ui_option_unselected'))
            .onClick(() => this.toggle(option))
        }, (option: string): string => option)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
