/**
 * SignInPage.ets（@Entry）
 * 每日签到：奖励日历/列表、本月累计天数、签到按钮、已签状态、未登录引导。
 */
import { router, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { SignInViewModel } from '../viewmodel/SignInViewModel';
import { SignInInfo, SignInReward } from '../model/SignInInfo';
import { SignInResult, ResignInfo } from '../service/SignInService';
import { AppBackButton } from '../components/AppBackButton';
import { NavIcon } from '../components/NavIcon';

@Entry
@Component
export struct SignInPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') currentUid: string = '';
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @State vm: SignInViewModel = new SignInViewModel();
  @State todayDay: number = new Date().getDate();

  aboutToAppear(): void {
    this.loadData();
  }

  loadData(): void {
    if (this.isLoggedIn && this.currentUid.length > 0) {
      this.vm.load(this.currentUid).then(() => {
      });
    }
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
  }

  @Builder
  header() {
    Row() {
      if (!this.embedMode) {
        AppBackButton()
      }
      Text('每日签到')
        .fontSize($r('app.float.page_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: this.embedMode ? 0 : 10 })
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: (this.embedMode ? 0 : this.topAvoidVp) + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'CheckIn', iconSize: 60 })
      Text('需登录后签到')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Button('去登录')
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          router.pushUrl({ url: 'pages/LoginPage' });
        })
    }
    .width('100%')
    .padding({ top: 80, bottom: 80 })
  }

  @Builder
  summaryCard(info: SignInInfo) {
    Row() {
      Column({ space: 2 }) {
        Text(`${info.signedDays}`)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_primary'))
        Text('本月已签')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .layoutWeight(1)
      Column({ space: 2 }) {
        Text(`${info.rewards.length}`)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('奖励天数')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .layoutWeight(1)
      Column({ space: 2 }) {
        Text(info.isTodaySigned(this.todayDay) ? '已签' : '未签')
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(info.isTodaySigned(this.todayDay) ? $r('app.color.success') : $r('app.color.notice_on'))
        Text('今日状态')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /**
   * 补签卡（对齐 Windows ClaimResignInRewardCommand：漏签/配额/米游币确认后补签；
   * 服务端自动补最近漏签日，无需选日期）。信息拉取失败时不显示。
   */
  @Builder
  resignCard(resign: ResignInfo) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text('补签')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`本月漏签 ${resign.missedDays} 天 · 配额 ${resign.usedCount}/${resign.limitCount}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Text(`每次补签消耗 米游币 ${resign.coinCost}（当前 ${resign.coinCount}），自动补最近漏签的一天`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Button(this.vm.resigning ? '补签中...' : '补签一天')
        .width('100%')
        .height(38)
        .fontSize(14)
        .backgroundColor(resign.canResign() ? $r('app.color.app_primary') : $r('app.color.card_background'))
        .fontColor(resign.canResign() ? Color.White : $r('app.color.text_secondary'))
        .borderRadius(10)
        .border({ width: 1, color: $r('app.color.divider') })
        .enabled(resign.canResign() && !this.vm.resigning)
        .onClick(() => {
          this.confirmResign(resign);
        })
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  /** 补签确认（对齐 Windows 补签确认弹窗：展示花费与剩余配额） */
  confirmResign(resign: ResignInfo): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认补签',
      message: `将消耗 米游币 ${resign.coinCost}（剩余补签次数 ${resign.leftCount()}），补签最近漏签的一天。是否继续？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '补签', color: $r('app.color.app_primary') },
      ],
    }).then((dlg: ShowDialogSuccessResponse) => {
      if (dlg.index !== 1) {
        return;
      }
      this.vm.doResign(this.currentUid).then((r: SignInResult) => {
        this.toast(r.rewardText.length > 0 ? `${r.message}，${r.rewardText}` : r.message);
      });
    });
  }

  @Builder
  rewardCell(reward: SignInReward) {
    Column({ space: 4 }) {
      if (reward.icon.length > 0) {
        Image(reward.icon)
          .width(44)
          .height(44)
          .objectFit(ImageFit.Contain)
          .backgroundColor($r('app.color.app_primary_bg'))
          .borderRadius(8)
      } else {
        Column() {
          NavIcon({ name: 'CheckIn', iconSize: 26 })
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .borderRadius(8)
        .backgroundColor($r('app.color.app_primary_bg'))
      }
      Text(reward.name.length > 6 ? reward.name.substring(0, 6) : reward.name)
        .fontSize(10)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`×${reward.count}`)
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
      if (this.isSignedDay(reward.day)) {
        Text('已签')
          .fontSize(9)
          .fontColor(Color.White)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .borderRadius(6)
          .backgroundColor($r('app.color.success'))
      } else {
        Text('未签')
          .fontSize(9)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .padding(8)
    .borderRadius(12)
    .backgroundColor(this.isSignedDay(reward.day) ? $r('app.color.success_bg') : $r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
  }

  isSignedDay(day: number): boolean {
    if (this.vm.info === undefined) {
      return false;
    }
    return this.vm.info.isSigned(day);
  }

  build() {
    Column() {
      this.header()
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else if (this.currentUid.length === 0) {
        Column({ space: 14 }) {
          Text('请先在「账号与数据」选择默认 UID')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
          Button('前往')
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .onClick(() => {
              router.pushUrl({ url: 'pages/UserPage' });
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            if (this.vm.info === undefined) {
              Column({ space: 12 }) {
                LoadingProgress()
                  .width(40)
                  .height(40)
                  .color($r('app.color.app_primary'))
                Text('加载中...')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                if (this.vm.message.length > 0) {
                  Text(this.vm.message)
                    .fontSize(13)
                    .fontColor($r('app.color.danger'))
                }
                Button('重试')
                  .fontSize(13)
                  .backgroundColor($r('app.color.app_primary'))
                  .fontColor(Color.White)
                  .onClick(() => {
                    this.loadData();
                  })
              }
              .width('100%')
              .padding({ top: 60, bottom: 60 })
            } else {
              this.summaryCard(this.vm.info)
              if (this.vm.resign !== undefined) {
                this.resignCard(this.vm.resign)
              }
              Text('每日奖励')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .margin({ top: 2 })
              Grid() {
                ForEach(this.vm.info.rewards, (reward: SignInReward) => {
                  GridItem() {
                    this.rewardCell(reward)
                  }
                }, (reward: SignInReward) => `${reward.day}`)
              }
              .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
              .columnsGap(8)
              .rowsGap(8)
              .width('100%')

              Button(this.vm.info.isTodaySigned(this.todayDay) ? '今日已签到' : (this.vm.signing ? '签到中...' : '立即签到'))
                .width('100%')
                .height(46)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .backgroundColor(this.vm.info.isTodaySigned(this.todayDay) ? $r('app.color.card_background') : $r('app.color.app_primary'))
                .fontColor(this.vm.info.isTodaySigned(this.todayDay) ? $r('app.color.text_secondary') : Color.White)
                .borderRadius(12)
                .border({ width: 1, color: $r('app.color.divider') })
                .enabled(!this.vm.info.isTodaySigned(this.todayDay) && !this.vm.signing)
                .onClick(() => {
                  this.vm.doSign(this.currentUid).then((r: SignInResult) => {
                    const text: string = r.rewardText.length > 0 ? `，${r.rewardText}` : '';
                    this.toast(r.alreadySigned ? '今日已签到' : `${r.message}${text}`);
                  });
                })
            }
          }
          .width('100%')
          .padding(16)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
  }
}
