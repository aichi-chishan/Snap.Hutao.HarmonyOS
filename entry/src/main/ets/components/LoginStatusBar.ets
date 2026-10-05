/**
 * LoginStatusBar.ets
 * 全局登录状态展示：已登录显示昵称/头像，未登录显示「去登录」，点击跳转。
 */
import { router } from '@kit.ArkUI';

@Component
export struct LoginStatusBar {
  @StorageProp('isLoggedIn') isLoggedIn: boolean = false;
  @StorageProp('currentUserName') currentUserName: string = '';
  @StorageProp('currentUserAvatar') currentUserAvatar: string = '';

  private openAccount(): void {
    router.pushUrl({ url: this.isLoggedIn ? 'pages/UserPage' : 'pages/LoginPage' });
  }

  build() {
    // 一个原生按钮承载整张卡片，避免可点 Row 和嵌套按钮产生重复焦点。
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        if (this.isLoggedIn) {
          if (this.currentUserAvatar.length > 0) {
            Image(this.currentUserAvatar)
              .width(40)
              .height(40)
              .borderRadius(20)
              .objectFit(ImageFit.Cover)
              .draggable(false)
              .accessibilityLevel('no')
              .backgroundColor($r('app.color.app_primary_bg'))
          } else {
            Text(this.currentUserName.length > 0 ? this.currentUserName.substring(0, 1) : '?')
              .fontSize(18)
              .fontColor($r('sys.color.font_on_primary'))
              .width(40)
              .height(40)
              .textAlign(TextAlign.Center)
              .borderRadius(20)
              .backgroundColor($r('app.color.app_primary'))
              .accessibilityLevel('no')
          }
          Column({ space: 2 }) {
            Text(this.currentUserName.length > 0 ? this.currentUserName : $r('app.string.common_logged_in_as'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.setting_account'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(' ›')
            .fontSize(22)
            .fontColor($r('app.color.text_secondary'))
            .accessibilityLevel('no')
        } else {
          Column() {
            Image($r('app.media.UI_Icon_Paimon'))
              .width(24)
              .height(24)
              .objectFit(ImageFit.Contain)
              .draggable(false)
              .accessibilityLevel('no')
          }
          .width(40)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .borderRadius(20)
          .backgroundColor($r('app.color.app_primary_bg'))
          Column({ space: 2 }) {
            Text('未登录')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.common_login_hint'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text($r('app.string.common_go_login'))
            .fontSize(13)
            .textAlign(TextAlign.Center)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .borderRadius(12)
            .constraintSize({ maxWidth: '40%' })
            .backgroundColor($r('app.color.app_primary'))
            .fontColor($r('sys.color.font_on_primary'))
        }
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_surface'))
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityGroup(true)
    .onClick(() => {
      this.openAccount();
    })
  }
}
