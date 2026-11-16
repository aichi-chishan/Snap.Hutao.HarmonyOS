import { common } from '@kit.AbilityKit';
import { AppButtonModifier, CardSurfaceModifier } from '../common/UiSurface';
import { AppRelease, AppUpdateResult } from '../model/AppUpdate';
import { AppUpdateService } from '../service/AppUpdateService';

@Component
export struct HomeUpdateNotice {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('appUpdateSkippedTag') skippedTag: string = '';
  @State release: AppRelease | undefined = undefined;
  @State openFailed: boolean = false;
  private attached: boolean = false;

  aboutToAppear(): void {
    this.attached = true;
    AppUpdateService.startupCheck().then((result: AppUpdateResult): void => {
      if (this.attached) { this.release = AppUpdateService.releaseForNotice(result); }
    });
  }

  aboutToDisappear(): void { this.attached = false; }

  private async openDetails(): Promise<void> {
    const release: AppRelease | undefined = this.release;
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (release === undefined || context === undefined) { return; }
    this.openFailed = false;
    try {
      await AppUpdateService.openDetails(context as common.UIAbilityContext, release.url, release.tag);
    } catch (_) {
      if (this.attached) { this.openFailed = true; }
    }
  }

  build() {
    if (this.release !== undefined && this.release.tag !== this.skippedTag) {
      Column({ space: 6 }) {
        Text($r('app.string.ui_update_available', this.release.tag)).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          Button($r('app.string.ui_update_notes'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
            .height(44).margin({ right: 8, bottom: 4 })
            .onClick(() => { this.openDetails(); })
          Button($r('app.string.ui_update_skip'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ right: 8, bottom: 4 })
            .onClick(() => { if (this.release !== undefined) { AppUpdateService.setSkippedTag(this.release.tag); } })
        }.width('100%')
        if (this.openFailed) {
          Text($r('app.string.ui_update_notes_error')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }
      }.width('100%').padding(12).borderRadius($r('app.float.card_radius'))
        .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    }
  }
}
