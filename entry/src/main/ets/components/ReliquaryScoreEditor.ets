import { AppButtonModifier, ControlMaterialModifier, SelectMaterialModifier } from '../common/UiSurface';
import { BackpackScoreProfile } from '../model/BackpackScore';

@Component
export struct ReliquaryScoreEditor {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @Prop initialProfile: BackpackScoreProfile = new BackpackScoreProfile();
  @Prop savedProfiles: BackpackScoreProfile[] = [];
  @Prop warning: string = '';
  onConfirm: (profile: BackpackScoreProfile, deletedIds: string[]) => void = () => {};
  onCancel: () => void = () => {};

  @State draft: BackpackScoreProfile = new BackpackScoreProfile();
  @State profiles: BackpackScoreProfile[] = [];
  @State selectedIndex: number = -1;
  @State nameText: string = '';
  private deletedIds: string[] = [];

  aboutToAppear(): void {
    this.profiles = this.savedProfiles.slice();
    const savedIndex: number = this.profiles.findIndex((profile: BackpackScoreProfile): boolean =>
      profile.id === this.initialProfile.id);
    this.selectedIndex = savedIndex >= 0 ? BackpackScoreProfile.CUSTOM_PRESET + savedIndex
      : this.initialProfile.preset < BackpackScoreProfile.CUSTOM_PRESET ? this.initialProfile.preset : -1;
    this.loadDraft(BackpackScoreProfile.clone(this.initialProfile));
  }

  private loadDraft(profile: BackpackScoreProfile): void {
    this.draft = profile;
    this.nameText = profile.preset === BackpackScoreProfile.CUSTOM_PRESET
      ? profile.name : BackpackScoreProfile.displayName(profile);
  }

  private optionNames(): string[] {
    return BackpackScoreProfile.PRESETS.slice(0, BackpackScoreProfile.CUSTOM_PRESET).concat(
      this.profiles.map((profile: BackpackScoreProfile): string => BackpackScoreProfile.displayName(profile)));
  }

  private options(): SelectOption[] {
    return this.optionNames().map((name: string): SelectOption => ({ value: name }));
  }

  private selectProfile(index: number): void {
    if (index < BackpackScoreProfile.CUSTOM_PRESET) {
      const profile: BackpackScoreProfile = BackpackScoreProfile.create(index);
      profile.id = this.draft.id;
      this.loadDraft(profile);
    } else {
      this.loadDraft(BackpackScoreProfile.clone(this.profiles[index - BackpackScoreProfile.CUSTOM_PRESET]));
    }
    this.selectedIndex = index;
  }

  private addProfile(): void {
    this.selectedIndex = -1;
    this.loadDraft(BackpackScoreProfile.create(BackpackScoreProfile.CUSTOM_PRESET));
  }

  private stageDelete(): void {
    const index: number = this.selectedIndex - BackpackScoreProfile.CUSTOM_PRESET;
    const id: string = this.profiles[index].id;
    this.deletedIds.push(id);
    this.profiles = this.profiles.filter((profile: BackpackScoreProfile): boolean => profile.id !== id);
    this.selectedIndex = 0;
    this.loadDraft(BackpackScoreProfile.create(0));
  }

  private rename(value: string): void {
    if (value === this.nameText) { return; }
    const profile: BackpackScoreProfile = BackpackScoreProfile.clone(this.draft);
    profile.name = value;
    this.nameText = value;
    this.draft = profile;
  }

  private setWeight(index: number, value: number): void {
    const weight: number = Math.round(value * 10) / 10;
    if (this.draft.weights[index] === weight) { return; }
    const profile: BackpackScoreProfile = BackpackScoreProfile.clone(this.draft);
    profile.weights[index] = weight;
    profile.preset = BackpackScoreProfile.CUSTOM_PRESET;
    this.draft = profile;
  }

  @Builder
  weightRow(index: number) {
    Row({ space: 8 }) {
      Text(BackpackScoreProfile.LABELS[index]).fontSize(13).fontColor($r('app.color.text_primary')).width(100)
      Slider({ value: this.draft.weights[index], min: 0, max: 1, step: 0.1 }).attributeModifier(new ControlMaterialModifier(this.surfaceMode, this.surfaceLevel)).layoutWeight(1)
        .accessibilityText(BackpackScoreProfile.LABELS[index])
        .onChange((value: number) => this.setWeight(index, value))
      Text(this.draft.weights[index].toFixed(1)).fontSize(13).fontColor($r('app.color.text_secondary')).width(28)
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Text('圣遗物评分配置').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Select(this.options()).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel)).selected(this.selectedIndex).value(this.optionNames()[this.selectedIndex] ?? '选择评分配置')
        .width('100%').hoverEffect(HoverEffect.Highlight).onSelect((index: number) => this.selectProfile(index))
      Row({ space: 8 }) {
        Button($r('app.string.ui_backpack_reliquary_score_config_new_config'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44)
          .onClick(() => this.addProfile())
        if (this.selectedIndex >= BackpackScoreProfile.CUSTOM_PRESET) {
          Button('删除配置', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).fontColor($r('app.color.danger'))
            .height(44)
            .onClick(() => this.stageDelete())
        }
      }.width('100%')
      TextInput({ text: this.nameText, placeholder: $r('app.string.ui_backpack_reliquary_score_config_name_header') }).maxLength(80).width('100%')
        .onChange((value: string) => this.rename(value))
      this.weightRow(0)
      this.weightRow(1)
      this.weightRow(2)
      this.weightRow(3)
      this.weightRow(4)
      this.weightRow(5)
      this.weightRow(6)
      Text('固定生命值、攻击力和防御力不计分。').fontSize(12).fontColor($r('app.color.text_secondary'))
      if (this.warning.length > 0) {
        Text(this.warning).fontSize(12).fontColor($r('app.color.danger'))
      }
      Row({ space: 8 }) {
        Button($r('app.string.common_cancel'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44).layoutWeight(1)
          .onClick(() => this.onCancel())
        Button($r('app.string.common_confirm'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .height(44).layoutWeight(1).enabled(this.warning.length === 0)
          .onClick(() => this.onConfirm(this.draft, this.deletedIds))
      }.width('100%')
    }.width('100%').constraintSize({ maxWidth: 520 }).alignItems(HorizontalAlign.Start)
  }
}
