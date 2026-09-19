/**
 * CalendarPage.ets（@Entry）
 * 活动日历：周视图（生日角色 + 当日可刷天赋/武器材料，对齐 Windows CalendarCard）
 * + 按时间排序列表（活动/卡池/签到条目）；周视图与材料不依赖登录。
 */
import { router, LengthMetrics } from '@kit.ArkUI';
import { CalendarViewModel } from '../viewmodel/CalendarViewModel';
import { ActCalendarEntry, ActCalendarType } from '../model/ActCalendarEntry';
import { DateUtil } from '../common/DateUtil';
import { CalendarWeekData, CalendarWeekDay, CalendarWeekService, CalendarBirthday } from '../service/CalendarWeekService';
import { Loading } from '../components/Loading';
import { EmptyState } from '../components/EmptyState';
import { ErrorHint } from '../components/ErrorHint';
import { AppBackButton } from '../components/AppBackButton';
import { NavIcon } from '../components/NavIcon';
import { MetaIcon } from '../components/MetaIcon';

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
  /** 周视图数据（生日 + 材料轮换；不依赖登录） */
  @State week: CalendarWeekData | undefined = undefined;
  /** 选中的周历日下标 */
  @State weekSelIdx: number = 0;

  aboutToAppear(): void {
    this.loadWeek();
    this.loadData();
  }

  loadWeek(): void {
    CalendarWeekService.loadWeek().then((w: CalendarWeekData) => {
      this.week = w;
      // 默认选中今日
      for (let i = 0; i < w.days.length; i++) {
        if (w.days[i].isToday) {
          this.weekSelIdx = i;
          break;
        }
      }
    });
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

  /** 周条（7 天切换；生日角色有角标，对齐 Windows CalendarCard 周历） */
  @Builder
  weekStrip() {
    if (this.week !== undefined) {
      Row({ space: 6 }) {
        ForEach(this.week.days, (day: CalendarWeekDay, idx: number) => {
          Column({ space: 2 }) {
            Text(day.dayName)
              .fontSize(10)
              .fontColor(this.weekSelIdx === idx ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
            Text(day.monthDay)
              .fontSize(13)
              .fontWeight(day.isToday ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.weekSelIdx === idx ? $r('app.color.app_primary') : $r('app.color.text_primary'))
            // 生日角标（🎂）与今日圆点
            Text(this.week !== undefined && this.week.birthdayFlags[idx] ? '🎂' : (day.isToday ? '·' : ''))
              .fontSize(10)
              .height(14)
          }
          .layoutWeight(1)
          .padding({ top: 8, bottom: 6 })
          .borderRadius(10)
          .backgroundColor(this.weekSelIdx === idx ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))
          .border({
            width: 1,
            color: this.weekSelIdx === idx ? $r('app.color.app_primary') : $r('app.color.divider')
          })
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.weekSelIdx = idx;
          })
        }, (day: CalendarWeekDay, idx: number) => `wd_${day.dateMs}_${this.weekSelIdx === idx}`)
      }
      .width('100%')
    }
  }

  /** 生日头像（MetaIcon 本地图标） */
  @Builder
  birthdayCell(b: CalendarBirthday) {
    Column({ space: 2 }) {
      if (b.icon.length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: b.icon, iconSize: 36 })
          .borderRadius(18)
          .clip(true)
      } else {
        Text(b.name.substring(0, 1))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor($r('app.color.app_primary'))
      }
      Text(b.name)
        .fontSize(9)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
    }
    .width(44)
  }

  /** 当前选中的周历日（未就绪返回 undefined） */
  private curWeekDay(): CalendarWeekDay | undefined {
    if (this.week === undefined || this.weekSelIdx < 0 || this.weekSelIdx >= this.week.days.length) {
      return undefined;
    }
    return this.week.days[this.weekSelIdx];
  }

  /** 选中日详情：生日角色 + 当日可刷材料（天赋/武器两段，对齐 Windows CalendarCard 内容） */
  @Builder
  weekDetail() {
    if (this.curWeekDay() !== undefined) {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Text(`${this.curWeekDay()?.dayName ?? ''} ${this.curWeekDay()?.monthDay ?? ''}${this.curWeekDay()?.isToday === true ? '（今日）' : ''}`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          if ((this.curWeekDay()?.birthdays.length ?? 0) > 0) {
            Text(`${this.curWeekDay()?.birthdays.length ?? 0} 位角色生日`)
              .fontSize(11)
              .fontColor($r('app.color.notice_on'))
          }
        }
        .width('100%')

        if ((this.curWeekDay()?.birthdays.length ?? 0) > 0) {
          Row({ space: 6 }) {
            ForEach(this.curWeekDay()?.birthdays ?? [], (b: CalendarBirthday) => {
              this.birthdayCell(b)
            }, (b: CalendarBirthday) => `bd_${b.name}`)
          }
          .width('100%')
        }

        if ((this.curWeekDay()?.talentNames.length ?? 0) === 0
          && (this.curWeekDay()?.weaponNames.length ?? 0) === 0) {
          Text('周日秘境全开，无固定轮换材料')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        } else {
          Text('天赋书')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Flex({
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Start,
            space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) }
          }) {
            ForEach(this.curWeekDay()?.talentNames ?? [], (name: string, idx: number) => {
              Text(name)
                .fontSize(10)
                .fontColor($r('app.color.text_primary'))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(8)
                .backgroundColor($r('app.color.page_background'))
                .border({ width: 1, color: $r('app.color.divider') })
            }, (name: string, idx: number) => `tal_${idx}_${name}`)
          }
          .width('100%')
          Text('武器突破材料')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Flex({
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Start,
            space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) }
          }) {
            ForEach(this.curWeekDay()?.weaponNames ?? [], (name: string, idx: number) => {
              Text(name)
                .fontSize(10)
                .fontColor($r('app.color.text_primary'))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(8)
                .backgroundColor($r('app.color.page_background'))
                .border({ width: 1, color: $r('app.color.divider') })
            }, (name: string, idx: number) => `wea_${idx}_${name}`)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 1, color: $r('app.color.divider') })
    }
  }

  build() {
    Column() {
      this.header()
      // 周视图（生日 + 材料轮换）不依赖登录，未登录也可见
      Column({ space: 8 }) {
        this.weekStrip()
        this.weekDetail()
      }
      .width('100%')
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
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Row() {
            Text('近期活动 / 卡池')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .padding({ left: 16, top: 6 })
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
          .layoutWeight(1)
          .align(Alignment.Top)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
  }
}
