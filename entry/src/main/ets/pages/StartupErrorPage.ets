import { common } from '@kit.AbilityKit';

/** 核心初始化失败时的独立页面，不依赖尚未就绪的业务服务。 */
@Entry
@Component
struct StartupErrorPage {
  @StorageProp('startupRetrying') retrying: boolean = false;

  private retry(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.eventHub.emit('hutao.startup.retry');
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        Text($r('app.string.ui_startup_failed_title'))
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .width('100%')
        Text($r('app.string.ui_startup_failed_body'))
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .width('100%')
        Button({ type: ButtonType.Normal }) {
          Text(this.retrying ? $r('app.string.common_loading') : $r('app.string.common_retry'))
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
        }
        .width('100%')
        .height(48)
        .borderRadius(10)
        .backgroundColor($r('app.color.app_primary'))
        .enabled(!this.retrying)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => { this.retry(); })
      }
      .width('100%')
      .constraintSize({ maxWidth: 480 })
      .padding(32)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.wallpaper_base'))
  }
}
