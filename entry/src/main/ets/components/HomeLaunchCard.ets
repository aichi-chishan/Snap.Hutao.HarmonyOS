import { router } from '@kit.ArkUI';
import { AppButtonModifier } from '../common/UiSurface';
import { GameLauncherService, GamePackage, GameLaunchResult } from '../service/GameLauncherService';
import { NavIcon } from './NavIcon';
import { PressCard } from './PressCard';

/** 卡面进入启动设置，底部按钮使用已配置的公开启动入口。 */
@Component
export struct HomeLaunchCard {
  @Prop fillHeight: boolean = false;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('gameLaunchTargetVersion') @Watch('loadTarget') targetVersion: number = 0;
  @State private configuredGameName: string | undefined = undefined;
  @State private launching: boolean = false;
  onLaunched: (ok: boolean, message: string) => void = () => {};

  aboutToAppear(): void {
    this.loadTarget();
  }

  private loadTarget(): void {
    const target: GamePackage = GameLauncherService.getTarget();
    this.configuredGameName = GameLauncherService.validationMessage(target).length === 0 ? target.displayName : undefined;
  }

  private actionLabel(): Resource {
    if (this.launching) { return $r('app.string.ui_common_loading'); }
    return this.configuredGameName === undefined ? $r('app.string.ui_settings_configure') : $r('app.string.ui_nav_launch');
  }

  private openLaunchPage(): void {
    if (this.launching) { return; }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/LaunchGamePage' }, router.RouterMode.Single)
      .catch((error: Error): void => { this.onLaunched(false, error.message); });
  }

  private async launch(): Promise<void> {
    if (this.launching) { return; }
    if (this.configuredGameName === undefined) {
      this.openLaunchPage();
      return;
    }
    this.launching = true;
    try {
      const result: GameLaunchResult = await GameLauncherService.launch();
      this.onLaunched(result.ok, result.message);
    } catch (e) {
      this.onLaunched(false, `拉起失败：${(e as Error).message}`);
    } finally {
      this.launching = false;
    }
  }

  build() {
    PressCard({
      fillHeight: this.fillHeight,
      onTap: (): void => this.openLaunchPage(),
    }) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'LaunchGame', iconSize: 18 })
          Text($r('app.string.ui_nav_launch'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .height(48)
        .flexShrink(0)

        Text(this.configuredGameName ?? $r('app.string.ui_desc_launch'))
          .width('100%')
          .constraintSize({ minHeight: 40 })
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button(this.actionLabel(), { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .width('100%')
          .constraintSize({ minHeight: 48 })
          .layoutWeight(this.fillHeight ? 1 : 0)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .enabled(!this.launching)
          .onClick((): void => { this.launch(); })
      }
      .width('100%')
      .height(this.fillHeight ? '100%' : undefined)
      .padding(12)
      .alignItems(HorizontalAlign.Start)
    }
  }
}
