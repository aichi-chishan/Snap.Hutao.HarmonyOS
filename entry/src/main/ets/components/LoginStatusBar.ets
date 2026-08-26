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

  build() {
    Row({ space: 12 }) {
      if (this.isLoggedIn) {
        if (this.currentUserAvatar.length > 0) {
          Image(this.currentUserAvatar)
            .width(40)
            .height(40)
            .borderRadius(20)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.app_primary_bg'))
        } else {
          Text(this.currentUserName.length > 0 ? this.currentUserName.substring(0, 1) : '?')
            .fontSize(18)
            .fontColor(Color.White)
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .borderRadius(20)
            .backgroundColor($r('app.color.app_primary'))
        }
        Column({ space: 2 }) {
          Text(this.currentUserName.length > 0 ? this.currentUserName : '已登录')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('点击管理账号')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(' ›')
          .fontSize(22)
          .fontColor($r('app.color.text_secondary'))
      } else {
        Column() {
          Image($r('app.media.UI_Icon_Paimon'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
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
          Text('登录后同步祈愿与便笺数据')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('去登录')
          .fontSize(13)
          .height(30)
          .backgroundColor($r('app.color.app_primary'))
          .fontColor(Color.White)
          .onClick(() => {
            router.pushUrl({ url: 'pages/LoginPage' });
          })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      if (this.isLoggedIn) {
        router.pushUrl({ url: 'pages/UserPage' });
      }
    })
  }
}
