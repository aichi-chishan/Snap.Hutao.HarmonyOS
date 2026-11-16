import { common } from '@kit.AbilityKit';
import { PageHeader } from '../components/PageHeader';
import { AppRelease, UpdateChannel, UpdateStatus } from '../model/AppUpdate';
import { UpdateViewModel } from '../viewmodel/UpdateViewModel';
import { AppUpdateService } from '../service/AppUpdateService';
import { AppButtonModifier, CardSurfaceModifier, SelectMaterialModifier } from '../common/UiSurface';

@Entry
@Component
export struct UpdatePage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State vm: UpdateViewModel = new UpdateViewModel();
  @State isWide: boolean = false;
  /** 跳过此版本（对齐 Windows ViewTitleUpdatePackageSkipVersion：被跳过的 tag 不再提示，出现更新版本后自动恢复） */
  @State skippedTag: string = '';
  private attached: boolean = false;
  aboutToAppear(): void { this.activate(); }
  onPageShow(): void { this.activate(); }
  onPageHide(): void { this.detach(); }
  aboutToDisappear(): void { this.detach(); }
  private activate(): void {
    if (!this.attached) {
      this.attached = true;
      this.skippedTag = AppUpdateService.skippedTag();
      this.vm.activate();
    }
  }
  private detach(): void { this.attached = false; this.vm.invalidate(); }
  private releaseSkipped(): boolean {
    const release: AppRelease | undefined = this.vm.result.release;
    return this.vm.result.status === UpdateStatus.Newer && release !== undefined
      && release.tag.length > 0 && release.tag === this.skippedTag;
  }
  private async open(project: boolean): Promise<void> {
    if (!this.attached) { return; }
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) { this.vm.openFailed = true; return; }
    await this.vm.open(context as common.UIAbilityContext, project);
  }
  private status(): ResourceStr {
    switch (this.vm.result.status) {
      case UpdateStatus.Checking: return $r('app.string.ui_update_checking');
      case UpdateStatus.Newer: return this.releaseSkipped()
        ? $r('app.string.ui_update_skipped', this.skippedTag)
        : $r('app.string.ui_update_available', this.releaseTag());
      case UpdateStatus.Equal: return $r('app.string.ui_update_current');
      case UpdateStatus.LocalNewer: return $r('app.string.ui_update_local_newer');
      case UpdateStatus.NoRelease:
      case UpdateStatus.NoChannelRelease: return $r('app.string.ui_update_no_release');
      case UpdateStatus.Unknown: return this.vm.result.metadataConflict
        ? $r('app.string.ui_update_conflict') : $r('app.string.ui_update_compare_unknown');
      case UpdateStatus.NetworkError: return $r('app.string.ui_update_check_failed');
      case UpdateStatus.RateLimited: return $r('app.string.ui_update_rate_limit');
      case UpdateStatus.Unavailable: return $r('app.string.ui_update_unavailable');
      case UpdateStatus.InvalidResponse: return $r('app.string.ui_update_invalid');
      case UpdateStatus.Cancelled: return $r('app.string.ui_update_cancelled');
      default: return '';
    }
  }
  private release(): AppRelease | undefined { return this.vm.result.release; }
  private releaseTitle(): string { const release: AppRelease | undefined = this.release(); return release === undefined ? '' : release.name; }
  private releaseNotes(): ResourceStr {
    const release: AppRelease | undefined = this.release();
    return release === undefined || release.notes.length === 0 ? $r('app.string.ui_update_no_notes') : release.notes;
  }
  private releaseTag(): string { return this.release()?.tag ?? ''; }
  private apiAdvice(): ResourceStr {
    const release: AppRelease | undefined = this.release();
    return release?.manifest === undefined ? $r('app.string.ui_update_compatibility_unknown')
      : $r('app.string.ui_update_required_api', release.manifest.minimumApi);
  }
  private packageAdvice(): Resource {
    const release: AppRelease | undefined = this.release();
    return release !== undefined && release.harmonyAssetCount > 0
      ? $r('app.string.ui_update_hap_listed') : $r('app.string.ui_update_no_hap');
  }

  @Builder
  checkPanel() {
    Column({ space: 14 }) {
      Text($r('app.string.ui_update_installed', this.vm.client.versionName || '—'))
        .fontSize(14).fontColor($r('app.color.text_primary'))
      Text(`API ${this.vm.client.api || '—'} · versionCode ${this.vm.client.versionCode || '—'}`)
        .fontSize(13).fontColor($r('app.color.text_secondary'))
      Text($r('app.string.ui_update_channel')).fontSize(14).fontColor($r('app.color.text_primary'))
      Select([{ value: $r('app.string.ui_update_stable') }, { value: $r('app.string.ui_update_preview') }]).attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
        .selected(this.vm.channel === UpdateChannel.Stable ? 0 : 1)
        .value(this.vm.channel === UpdateChannel.Stable ? $r('app.string.ui_update_stable') : $r('app.string.ui_update_preview'))
        .width('100%').height(44).fontColor($r('app.color.text_primary'))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText($r('app.string.ui_update_channel')).onSelect((index: number) => {
          if (index === 0 || index === 1) { this.vm.setChannel(index === 0 ? UpdateChannel.Stable : UpdateChannel.Preview); }
        })
      if (this.vm.result.status !== UpdateStatus.Idle) {
        Text(this.status()).fontSize(15).fontColor($r('app.color.text_primary')).width('100%')
      }
      if (this.vm.busy) {
        Button($r('app.string.ui_update_cancel'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44)
          .onClick(() => { this.vm.cancel(); })
      } else {
        Button($r('app.string.ui_check_update'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
          .height(44)
          .onClick(() => { this.vm.check(); })
      }
      if (this.vm.result.checkedAt > 0) {
        Text(new Date(this.vm.result.checkedAt).toLocaleString())
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      if (!this.vm.result.complete) {
        Text($r('app.string.ui_update_recent_only'))
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      if (this.vm.result.unknownVersions > 0) {
        Text(`有 ${this.vm.result.unknownVersions} 条记录无法安全比较，未将它们认定为更新`)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      Button($r('app.string.ui_update_project_releases'), { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(44).enabled(!this.vm.busy && !this.vm.opening)
        .onClick(() => { this.open(true); })
      if (this.vm.openFailed) {
        Text($r('app.string.ui_update_notes_error')).fontSize(13).fontColor($r('app.color.text_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(14)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }
  @Builder
  releasePanel() {
    Column({ space: 14 }) {
      if (this.vm.result.release !== undefined) {
        Text(this.releaseTitle()).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text(this.releaseTag()).fontSize(14).fontColor($r('app.color.text_secondary'))
        Text(this.apiAdvice()).fontSize(14).fontColor($r('app.color.text_primary'))
        Text(this.packageAdvice()).fontSize(13).fontColor($r('app.color.text_secondary'))
        Button($r('app.string.ui_update_notes'), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44).enabled(!this.vm.busy && !this.vm.opening)
          .onClick(() => { this.open(false); })
        if (this.vm.result.status === UpdateStatus.Newer) {
          if (this.releaseSkipped()) {
            Button($r('app.string.ui_update_unskip'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).enabled(!this.vm.busy)
              .onClick(() => {
                this.skippedTag = '';
                AppUpdateService.setSkippedTag('');
              })
          } else {
            Button($r('app.string.ui_update_skip'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).enabled(!this.vm.busy)
              .accessibilityText($r('app.string.ui_update_skip'))
              .onClick(() => {
                const release: AppRelease | undefined = this.release();
                this.skippedTag = release !== undefined ? release.tag : '';
                AppUpdateService.setSkippedTag(this.skippedTag);
              })
          }
        }
        Text(this.releaseNotes()).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(14)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }
  build() {
    Column() {
      PageHeader({ title: $r('app.string.ui_update_title'), embedMode: this.embedMode, topAvoidVp: this.topAvoidVp })
      Scroll() {
        if (this.isWide && this.vm.result.release !== undefined) {
          Row({ space: 16 }) {
            Column() { this.checkPanel() }.width('40%')
            Column() { this.releasePanel() }.layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Top).padding(16)
        } else {
          Column({ space: 16 }) {
            this.checkPanel()
            if (this.vm.result.release !== undefined) { this.releasePanel() }
          }.width('100%').padding(16)
        }
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }.width('100%').height('100%').backgroundColor($r('app.color.wallpaper_base'))
      .onAreaChange((_old: Area, area: Area) => { this.isWide = Number(area.width) >= 840; })
  }
}
