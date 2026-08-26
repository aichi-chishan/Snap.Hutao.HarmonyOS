/**
 * CalendarPage.ets（@Entry）
 * 活动日历：按时间排序列表，活动/卡池/签到条目含起止时间；未登录引导。
 */
import { router } from '@kit.ArkUI';
import { CalendarViewModel } from '../viewmodel/CalendarViewModel';
import { ActCalendarEntry, ActCalendarType } from '../model/ActCalendarEntry';
import { DateUtil } from '../common/DateUtil';
import { Loading } from '../components/Loading';
import { EmptyState } from '../components/EmptyState';
import { ErrorHint } from '../components/ErrorHint';
import { AppBackButton } from '../components/AppBackButton';
import { NavIcon } from '../components/NavIcon';

@Entry
@Component
export struct CalendarPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') currentUid: string = '';
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @State vm: CalendarViewModel = new CalendarViewModel();
  @State now: number = Date.now();

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
      Text('活动日历')
        .fontSize($r('app.float.page_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: this.embedMode ? 0 : 10 })
      Blank()
      Button('刷新')
        .fontSize(12)
        .height(28)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          this.loadData();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: (this.embedMode ? 0 : this.topAvoidVp) + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'Database', iconSize: 60 })
      Text('需登录后查看活动日历')
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
  calendarRow(entry: ActCalendarEntry) {
    Row({ space: 10 }) {
      Column() {
        Text(entry.typeName)
          .fontSize(11)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(8)
          .backgroundColor(entry.type === ActCalendarType.CARD_POOL ? $r('app.color.app_primary') : $r('app.color.notice_on'))
        Text(entry.statusText(this.now))
          .fontSize(10)
          .fontColor(entry.isOngoing(this.now) ? $r('app.color.success') : $r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .width(72)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 3 }) {
        Text(entry.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (entry.type === ActCalendarType.CARD_POOL && entry.versionName.length > 0) {
          Text(entry.versionName)
            .fontSize(11)
            .fontColor($r('app.color.app_primary'))
        }
        Text(`${DateUtil.formatMonthDay(entry.startTime)} ~ ${DateUtil.formatMonthDay(entry.endTime)}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        if (entry.desc.length > 0 && entry.type !== ActCalendarType.CARD_POOL) {
          Text(entry.desc)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        // 卡池角色头像
        if (entry.avatarIcons.length > 0) {
          Row({ space: 4 }) {
            ForEach(entry.avatarIcons, (icon: string, idx: number) => {
              if (idx < 5) {
                Image(icon)
                  .width(32)
                  .height(32)
                  .borderRadius(16)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor($r('app.color.app_primary_bg'))
              }
            }, (icon: string, idx: number) => `${idx}_${icon}`)
          }
          .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
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
          Column({ space: 10 }) {
            if (this.vm.loading) {
              Loading()
            } else if (this.vm.entries.length === 0) {
              if (this.vm.message.length > 0) {
                ErrorHint({ text: this.vm.message, onRetry: () => {
                  this.loadData();
                } })
              } else {
                EmptyState({ icon: '🗓️', text: '暂无活动数据' })
              }
            } else {
              ForEach(this.vm.entries, (entry: ActCalendarEntry) => {
                this.calendarRow(entry)
              }, (entry: ActCalendarEntry) => `${entry.name}_${entry.startTime}`)
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
