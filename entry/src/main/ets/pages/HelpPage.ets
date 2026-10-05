import { router } from '@kit.ArkUI';
import { PageHeader } from '../components/PageHeader';
import { HelpDocument } from '../model/HelpDocument';
import { HelpText } from '../model/HelpText';
import { CommonOutcome, CommonOutcomeId } from '../model/CommonOutcome';
import { AppLocaleService } from '../service/AppLocaleService';
import { HelpViewModel } from '../viewmodel/HelpViewModel';

@Entry
@Component
export struct HelpPage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('helpLocaleVersion') @Watch('localeChanged') localeVersion: number = 0;
  @State vm: HelpViewModel = new HelpViewModel();
  @State selected: HelpDocument | undefined = undefined;
  @State previewText: string = '';
  @State localeIndex: number = 0;
  @State fallback: boolean = false;
  @State isWide: boolean = false;
  private attached: boolean = false;
  private pageSequence: number = 0;
  private localeKeys: string[] = ['system', 'zh-Hans', 'zh-Hant', 'en'];
  private issues: CommonOutcomeId[] = [CommonOutcomeId.Failed, CommonOutcomeId.NetworkUnavailable,
    CommonOutcomeId.PermissionRequired, CommonOutcomeId.InvalidFile, CommonOutcomeId.LoginExpired, CommonOutcomeId.Unsupported];

  aboutToAppear(): void { this.activate(); }
  onPageShow(): void { this.activate(); }
  onPageHide(): void { this.detach(); }
  aboutToDisappear(): void { this.detach(); }
  private activate(): void {
    if (this.attached) { return; }
    this.attached = true; this.vm.activate(AppLocaleService.current()); this.localeChanged();
  }
  private detach(): void {
    this.attached = false; this.pageSequence++; this.vm.invalidate(); this.previewText = '';
  }
  private localeChanged(): void {
    if (!this.attached) { return; }
    this.localeIndex = this.localeKeys.indexOf(AppLocaleService.preference());
    this.fallback = AppLocaleService.usingFallback();
    this.vm.setLocale(AppLocaleService.current()); this.sync();
  }
  private sync(): void { this.selected = this.vm.selected(); this.previewText = this.vm.previewText(); }
  private label(key: string): string { return HelpText.text(key, this.vm.locale); }
  private locales(): SelectOption[] {
    return [{ value: this.label('system') }, { value: '简体中文' }, { value: '繁體中文' }, { value: 'English' }];
  }
  private issueOptions(): SelectOption[] {
    return [{ value: this.label('general') }, { value: this.label('network') }, { value: this.label('permission') },
      { value: this.label('file') }, { value: this.label('login') }, { value: this.label('unsupported') }];
  }
  private chooseLocale(index: number): void {
    if (!this.attached || index < 0 || index >= this.localeKeys.length) { return; }
    if (!AppLocaleService.select(this.localeKeys[index])) { this.vm.outcome = new CommonOutcome(CommonOutcomeId.LocaleFailed); return; }
    this.localeChanged();
  }
  private select(id: string): void { if (this.attached) { this.vm.select(id); this.sync(); } }
  private async generate(): Promise<void> {
    if (!this.attached) { return; }
    const sequence: number = this.pageSequence;
    const accepted: boolean = await this.vm.generatePreview();
    if (accepted && this.attached && sequence === this.pageSequence) { this.sync(); }
  }
  private async copy(): Promise<void> {
    if (!this.attached) { return; }
    const sequence: number = this.pageSequence;
    const accepted: boolean = await this.vm.copyPreview();
    if (accepted && this.attached && sequence === this.pageSequence) { this.sync(); }
  }
  private openRelated(): void {
    const route: string = this.vm.route();
    if (!this.attached || route.length === 0) { return; }
    const sequence: number = this.pageSequence;
    router.pushUrl({ url: route }).catch(() => {
      if (this.attached && sequence === this.pageSequence) { this.vm.outcome = new CommonOutcome(CommonOutcomeId.Failed); }
    });
  }

  @Builder
  controls() {
    Column({ space: 8 }) {
      Text(this.label('local')).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text(this.label('language')).fontSize(13).fontColor($r('app.color.text_primary'))
      Select(this.locales()).selected(this.localeIndex).value(this.locales()[this.localeIndex].value)
        .height(44).width('100%').fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.card_surface')).hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.label('language')).onSelect((index: number) => { this.chooseLocale(index); })
      Text(this.label('scope')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.fallback) {
        Text(this.label('fallback')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.vm.outcome.id === CommonOutcomeId.LocaleFailed) {
        Text(this.vm.message()).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      Search({ value: this.vm.query, placeholder: this.label('search') }).height(44)
        .maxLength(120).fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.card_surface'))
        .onChange((value: string) => { this.vm.setQuery(value); this.sync(); })
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, bottom: 12 })
  }

  @Builder
  articles() {
    Scroll() {
      Column({ space: 8 }) {
        if (this.vm.documents.length === 0) {
          Text(this.label('empty')).fontColor($r('app.color.text_secondary')).padding(16)
        }
        ForEach(this.vm.documents, (doc: HelpDocument) => {
          Column({ space: 6 }) {
            Text(doc.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(doc.summary).fontSize(13).fontColor($r('app.color.text_secondary'))
          }.width('100%').alignItems(HorizontalAlign.Start).padding(14).constraintSize({ minHeight: 64 })
            .borderRadius(12).backgroundColor($r('app.color.card_surface')).hoverEffect(HoverEffect.Highlight)
            .accessibilityText(doc.title).onClick(() => { this.select(doc.id); })
        }, (doc: HelpDocument) => `${this.vm.locale}_${doc.id}`)
      }.width('100%')
    }.width('100%').height('100%').scrollBar(BarState.Auto)
  }

  @Builder
  diagnostics() {
    Column({ space: 10 }) {
      Text(this.label('diagnostics')).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(this.label('privacy')).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text(this.label('problem')).fontSize(13).fontColor($r('app.color.text_primary'))
      Select(this.issueOptions()).selected(this.issues.indexOf(this.vm.issue))
        .value(this.issueOptions()[this.issues.indexOf(this.vm.issue)].value)
        .height(44).width('100%').fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.card_surface')).hoverEffect(HoverEffect.Highlight)
        .accessibilityText(this.label('problem')).onSelect((index: number) => {
          if (index >= 0 && index < this.issues.length) { this.vm.setIssue(this.issues[index]); this.sync(); }
        })
      Text(this.vm.advice()).fontSize(13).fontColor($r('app.color.text_secondary'))
      Row({ space: 10 }) {
        Text(this.label('environment')).fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.vm.includeEnvironment })
          .accessibilityText(this.label('environment')).onChange((value: boolean) => { this.vm.setEnvironment(value); this.sync(); })
      }.width('100%').constraintSize({ minHeight: 44 })
      Button(this.label('generate')).height(44).width('100%').enabled(!this.vm.busy)
        .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
        .hoverEffect(HoverEffect.Highlight).onClick(() => { this.generate(); })
      if (this.previewText.length > 0) {
        Text(this.label('readFirst')).fontSize(12).fontColor($r('app.color.text_secondary'))
        Text(this.previewText).fontSize(12).fontColor($r('app.color.text_primary')).width('100%')
        Button(this.label('copy')).height(44).width('100%').enabled(!this.vm.busy)
          .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
          .hoverEffect(HoverEffect.Highlight).onClick(() => { this.copy(); })
        Button(this.label('clear')).height(44).width('100%')
          .fontColor($r('app.color.text_secondary')).backgroundColor($r('app.color.card_surface'))
          .hoverEffect(HoverEffect.Highlight).onClick(() => { this.vm.clearPreview(); this.sync(); })
      }
      if (this.vm.message().length > 0) {
        Text(this.vm.message()).fontSize(13).fontColor($r('app.color.text_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(14).borderRadius(12)
      .backgroundColor($r('app.color.card_surface'))
  }

  @Builder
  detail() {
    Scroll() {
      Column({ space: 14 }) {
        if (this.selected !== undefined) {
          if (!this.isWide) {
            Button(this.label('back')).height(44).width('100%')
              .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
              .hoverEffect(HoverEffect.Highlight).onClick(() => { this.select(''); })
          }
          Text(this.selected.title).fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text(this.selected.summary).fontSize(14).fontColor($r('app.color.text_secondary'))
          ForEach(this.selected.steps, (step: string, index: number) => {
            Text(`${index + 1}. ${step}`).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
          }, (step: string) => `${this.vm.locale}_${step}`)
          if (this.vm.route().length > 0) {
            Button(this.label('open')).height(44).width('100%')
              .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
              .hoverEffect(HoverEffect.Highlight).onClick(() => { this.openRelated(); })
          }
          this.diagnostics()
        } else {
          Text(this.label('choose')).fontColor($r('app.color.text_secondary')).padding(24)
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Auto)
  }

  build() {
    Column() {
      PageHeader({ title: this.label('title'), embedMode: this.embedMode, topAvoidVp: this.topAvoidVp })
      this.controls()
      if (this.isWide) {
        Row({ space: 16 }) {
          Column() { this.articles() }.width('38%').height('100%')
          Column() { this.detail() }.layoutWeight(1).height('100%')
        }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
      } else if (this.selected !== undefined) {
        Column() { this.detail() }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
      } else {
        Column() { this.articles() }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.wallpaper_base'))
      .onAreaChange((_old: Area, area: Area) => { this.isWide = Number(area.width) >= 840; })
  }
}
