/**
 * CalendarPage.ets（@Entry）
 * 活动日历：周视图（生日角色 + 当日可刷天赋/武器材料，对齐 Windows CalendarCard）
 * + 按时间排序列表（活动/卡池/签到条目）；周视图与材料不依赖登录。
 */
import { LengthMetrics } from '@kit.ArkUI';
import { CalendarViewModel } from '../viewmodel/CalendarViewModel';
import { ActCalendarEntry, ActCalendarType, ActRewardEntry } from '../model/ActCalendarEntry';
import { GameCalendarRules } from '../service/GameCalendarRules';
import { CalendarWeekDay, CalendarWeekService, CalendarBirthday,
  CalendarWeekMaterial, CalendarMaterialConsumer } from '../service/CalendarWeekService';
import { Loading } from '../components/Loading';
import { EmptyState } from '../components/EmptyState';
import { ErrorHint } from '../components/ErrorHint';
import { PageHeader } from '../components/PageHeader';
import { NavIcon } from '../components/NavIcon';
import { MetaIcon } from '../components/MetaIcon';
import { PageBackdrop } from '../components/PageBackdrop';
import { calendarDateLabel, calendarWeekdayLabel } from '../components/CalendarWeekdayLabel';
import { AppButtonModifier, CardSurfaceModifier, SelectMaterialModifier, UiSurface } from '../common/UiSurface';

const OFFSET_OPTIONS: SelectOption[] = GameCalendarRules.OFFSET_HOURS.map((hours: number): SelectOption =>
  ({ value: GameCalendarRules.offsetLabel(hours) }));

@Entry
@Component
export struct CalendarPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('currentUid') @Watch('onOwnerChanged') currentUid: string = '';
  @StorageProp('currentUserId') @Watch('onOwnerChanged') currentUserId: number = 0;
  @StorageProp('isLoggedIn') @Watch('onOwnerChanged') isLoggedIn: boolean = false;
  @StorageProp('calendarSettingsVersion') @Watch('onCalendarSettingsChanged') calendarVersion: number = 0;
  @StorageProp('helpLocaleVersion') @Watch('onCalendarSettingsChanged') localeVersion: number = 0;
  @State vm: CalendarViewModel = new CalendarViewModel();
  @State now: number = Date.now();
  @State isWide: boolean = false;
  /** 材料详情弹层（点击材料图标打开，展示消费者角色/武器） */
  @State selectedMat: CalendarWeekMaterial | undefined = undefined;
  @State showMatSheet: boolean = false;
  private attached: boolean = false;
  private clockTimer: number = -1;

  aboutToAppear(): void {
    this.attached = true;
    this.vm.clearActivities();
    this.refresh();
    this.clockTimer = setInterval(() => {
      this.now = Date.now();
      const today: CalendarWeekDay | undefined = this.vm.week?.days.find((day: CalendarWeekDay): boolean => day.isToday);
      if (today !== undefined && GameCalendarRules.serverDay(this.now, this.displayOffset()) !==
        GameCalendarRules.serverDay(today.dateMs, this.displayOffset())) {
        this.loadWeek();
      }
    }, 60000);
  }

  aboutToDisappear(): void {
    this.attached = false;
    clearInterval(this.clockTimer);
    this.vm.dispose();
  }

  onOwnerChanged(): void {
    this.vm.clearActivities();
    this.loadData();
  }

  onCalendarSettingsChanged(): void {
    if (this.attached) { this.loadWeek(); }
  }

  private refresh(): void {
    this.loadWeek();
    this.loadData();
  }

  loadWeek(): void {
    this.now = Date.now();
    this.vm.loadWeek(this.now);
  }

  loadData(): void {
    if (!this.attached || !this.isLoggedIn || this.currentUid.length === 0) { return; }
    const uid: string = this.currentUid;
    const userId: number = this.currentUserId;
    this.vm.load(uid, (): boolean => this.attached && this.isLoggedIn &&
      this.currentUid === uid && this.currentUserId === userId);
  }

  private displayOffset(): number {
    return this.vm.week?.offsetHours ?? GameCalendarRules.DEFAULT_OFFSET_HOURS;
  }

  private changeGlobalOffset(index: number): void {
    const hours: number | undefined = GameCalendarRules.OFFSET_HOURS[index];
    if (hours === undefined || hours === this.vm.week?.globalOffsetHours) { return; }
    CalendarWeekService.setGlobalOffset(hours);
    const version: number = AppStorage.get<number>('calendarSettingsVersion') ?? 0;
    AppStorage.setOrCreate<number>('calendarSettingsVersion', version + 1);
  }

  @Builder
  header() {
    PageHeader({ title: $r('app.string.ui_section_calendar'), embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
      Button($r('app.string.ui_daily_note_refresh'), { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .fontSize(12)
        .height(44)
        .onClick(() => {
          this.refresh();
        })
    }
  }

  @Builder
  loginGuide() {
    Column({ space: 14 }) {
      NavIcon({ name: 'Database', iconSize: 60 })
      Text($r('app.string.ui_settings_not_logged_in'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Button($r('app.string.ui_spiral_abyss_upload_record_homa_not_login_primary_button_text'), { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true)).constraintSize({ minHeight: 44 })
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/LoginPage' });
        })
    }
    .width('100%')
    .padding({ top: 40, bottom: 40 })
  }

  @Builder
  calendarRow(entry: ActCalendarEntry) {
    Row({ space: 10 }) {
      Column() {
        Text(entry.type === ActCalendarType.SIGN_IN ? $r('app.string.ui_section_sign_in') : entry.typeName)
          .fontSize(11)
          .fontColor($r('app.color.on_accent'))
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
            .fontColor($r('app.color.app_primary_text'))
        }
        Text(`${GameCalendarRules.formatMonthDay(entry.startTime, this.displayOffset())} ~ ` +
          GameCalendarRules.formatMonthDay(entry.endTime, this.displayOffset()))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        if (entry.isOngoing(this.now)) {
          Text(`剩余 ${ActCalendarEntry.timeSpan(entry.endTime - this.now)}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        if (entry.desc.length > 0 && entry.type !== ActCalendarType.CARD_POOL) {
          Text(entry.desc)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (entry.progressLine().length > 0) {
          Text(entry.progressLine()).fontSize(12).fontColor($r('app.color.app_primary_text'))
        }
        if (entry.avatarIcons.length > 0 || entry.weaponIcons.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(4), cross: LengthMetrics.vp(4) } }) {
            ForEach(entry.avatarIcons.concat(entry.weaponIcons), (icon: string) => {
              Image(icon)
                .width(32)
                .height(32)
                .borderRadius(8)
                .objectFit(ImageFit.Contain)
                .backgroundColor($r('app.color.app_primary_bg'))
            }, (icon: string, idx: number) => `${idx}_${icon}`)
          }
          .margin({ top: 4 })
        }
        if (entry.rewards.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
            ForEach(entry.rewards, (reward: ActRewardEntry) => {
              Row({ space: 2 }) {
                MetaIcon({ category: 'ItemIcon', name: reward.iconName(), iconSize: 22, remoteFallback: true })
                Text(`×${reward.num}`).fontSize(10).fontColor($r('app.color.text_secondary'))
              }
              .accessibilityText(`${reward.name} ${reward.num}`)
            }, (reward: ActRewardEntry, idx: number) => `${reward.itemId}_${idx}`)
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
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  /** 周条（7 天切换；生日角色有角标，对齐 Windows CalendarCard 周历） */
  @Builder
  weekStrip() {
    if (this.vm.week !== undefined) {
      Row({ space: 6 }) {
        ForEach(this.vm.week.days, (day: CalendarWeekDay) => {
          Column({ space: 2 }) {
            Text(calendarWeekdayLabel(day.weekday))
              .fontSize(10)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(this.vm.selectedDateMs === day.dateMs ? $r('app.color.app_primary_text') : $r('app.color.text_secondary'))
            Text(day.monthDay)
              .fontSize(13)
              .fontWeight(day.isToday ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.vm.selectedDateMs === day.dateMs ? $r('app.color.app_primary_text') : $r('app.color.text_primary'))
            Text(day.birthdays.length > 0 ? '🎂' : (day.isToday ? '·' : ''))
              .fontSize(10)
              .height(14)
          }
          .layoutWeight(1)
          .padding({ top: 8, bottom: 6 })
          .borderRadius(10)
          .backgroundColor(this.vm.selectedDateMs === day.dateMs ? $r('app.color.app_primary_bg') : $r('app.color.card_inner_tint'))
          .border({
            width: 1,
            color: this.vm.selectedDateMs === day.dateMs ? $r('app.color.app_primary') : $r('app.color.card_stroke')
          })
          .focusable(true)
          .accessibilitySelected(this.vm.selectedDateMs === day.dateMs)
          .accessibilityText(`${calendarDateLabel(this.getUIContext(), day)}${day.birthdays.length > 0 ? ' 有角色生日' : ''}`)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.vm.selectedDateMs = day.dateMs;
          })
        }, (day: CalendarWeekDay) => `wd_${day.dateMs}_${day.isToday}_${day.birthdays.length}_${this.localeVersion}`)
      }
      .width('100%')
    }
  }

  /** 生日头像（MetaIcon 本地图标；头像+名字区加高亮底色，对齐 Windows 本周生日高亮） */
  @Builder
  birthdayCell(b: CalendarBirthday) {
    Column({ space: 2 }) {
      if (b.icon.length > 0) {
        MetaIcon({ category: 'AvatarIcon', name: b.icon, iconSize: 36, remoteFallback: true })
          .borderRadius(18)
          .clip(true)
      } else {
        Text(b.name.substring(0, 1))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_accent'))
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
    .width(52)
    .padding(4)
    .borderRadius(10)
    .backgroundColor($r('app.color.cultivate_highlight'))
  }

  /** 品质描边色（对齐 Windows ItemIcon Quality：金/紫/灰） */
  private static matColor(rank: number): Resource {
    if (rank >= 5) {
      return $r('app.color.five_star');
    }
    if (rank === 4) {
      return $r('app.color.four_star');
    }
    return $r('app.color.text_secondary');
  }

  private openMaterial(id: number): void {
    const day: CalendarWeekDay | undefined = this.vm.selectedDay();
    const material: CalendarWeekMaterial | undefined = day?.talentMats.find((item: CalendarWeekMaterial): boolean => item.id === id)
      ?? day?.weaponMats.find((item: CalendarWeekMaterial): boolean => item.id === id);
    if (material === undefined) { return; }
    this.selectedMat = material;
    this.showMatSheet = true;
  }

  /** 材料图标格（品质描边 + 名称；养成计划命中加高亮底色，对齐 Windows CalendarMaterial.Highlight） */
  @Builder
  matCell(mat: CalendarWeekMaterial) {
    Column({ space: 3 }) {
      MetaIcon({ category: 'ItemIcon', name: mat.icon, iconSize: 34, remoteFallback: true })
        .padding(3)
        .border({ width: 1.5, color: CalendarPage.matColor(mat.rank) })
        .borderRadius(8)
        .backgroundColor($r('app.color.card_background'))
      Text(mat.name)
        .fontSize(9)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width(56)
    .padding(4)
    .borderRadius(8)
    .backgroundColor(mat.highlighted ? $r('app.color.cultivate_highlight') : $r('app.color.card_inner_tint'))
    .focusable(true)
    .accessibilityText(mat.name)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.openMaterial(mat.id);
    })
  }

  /** 材料图标网格（一类材料一段） */
  @Builder
  matGrid(mats: CalendarWeekMaterial[]) {
    Flex({
      wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.Start,
      space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) }
    }) {
      ForEach(mats, (mat: CalendarWeekMaterial) => {
        this.matCell(mat)
      }, (mat: CalendarWeekMaterial) => `m_${mat.id}_${mat.name}_${mat.icon}_${mat.highlighted}_${mat.rank}`)
    }
    .width('100%')
  }

  /** 材料详情弹层：图标+名称+类型描述 + 需要该材料的角色/武器（对齐 Windows Flyout） */
  @Builder
  matSheet() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        MetaIcon({
          category: 'ItemIcon',
          name: this.selectedMat !== undefined ? this.selectedMat.icon : '',
          iconSize: 48,
          remoteFallback: true
        })
          .padding(3)
          .border({ width: 1.5, color: this.selectedMat !== undefined ? CalendarPage.matColor(this.selectedMat.rank) : $r('app.color.divider') })
          .borderRadius(10)
        Column({ space: 3 }) {
          Text(this.selectedMat !== undefined ? this.selectedMat.name : '')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.selectedMat !== undefined
            ? (this.selectedMat.isTalent ? '角色天赋培养素材' : $r('app.string.ui_model_metadata_material_weapon_ascension_material'))
            : '')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          if (this.selectedMat !== undefined && this.selectedMat.highlighted) {
            Text('当前养成计划所需')
              .fontSize(11)
              .fontColor($r('app.color.app_primary_text'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('需要该材料的角色 / 武器')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      if ((this.selectedMat?.consumers.length ?? 0) === 0) {
        Text('暂无角色 / 武器需要该材料')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 20 })
      } else {
      Scroll() {
        Flex({
          wrap: FlexWrap.Wrap,
          justifyContent: FlexAlign.Start,
          space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) }
        }) {
          ForEach(this.selectedMat !== undefined ? this.selectedMat.consumers : [],
            (c: CalendarMaterialConsumer) => {
              Column({ space: 3 }) {
                MetaIcon({ category: c.category, name: c.icon, iconSize: 42, remoteFallback: true })
                  .padding(3)
                  .border({ width: 1.5, color: CalendarPage.matColor(c.quality) })
                  .borderRadius(9)
                Text(c.name)
                  .fontSize(10)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width(56)
                  .textAlign(TextAlign.Center)
              }
              .width(60)
              .opacity(c.highlighted ? 1 : 0.3)
            }, (c: CalendarMaterialConsumer) => `cs_${c.id}_${c.highlighted}`)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  /** 选中日详情：生日角色 + 当日可刷材料（天赋/武器两段，对齐 Windows CalendarCard 内容） */
  @Builder
  weekDetail() {
    if (this.vm.selectedDay() !== undefined) {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Text(calendarDateLabel(this.getUIContext(), this.vm.selectedDay()))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          if ((this.vm.selectedDay()?.birthdays.length ?? 0) > 0) {
            Text(`${this.vm.selectedDay()?.birthdays.length ?? 0} 位角色生日`)
              .fontSize(11)
              .fontColor($r('app.color.notice_on'))
          }
        }
        .width('100%')

        if ((this.vm.selectedDay()?.birthdays.length ?? 0) > 0) {
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
            ForEach(this.vm.selectedDay()?.birthdays ?? [], (b: CalendarBirthday) => {
              this.birthdayCell(b)
            }, (b: CalendarBirthday) => `bd_${b.name}_${b.icon}`)
          }
          .width('100%')
        }

        if (this.vm.selectedDay()?.allMaterialsOpen === true) {
          Text($r('app.string.ui_card_calendar_all_materials_hint'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        } else if ((this.vm.selectedDay()?.talentMats.length ?? 0) === 0 &&
          (this.vm.selectedDay()?.weaponMats.length ?? 0) === 0) {
          Text('暂无轮换材料数据')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        } else {
          if ((this.vm.selectedDay()?.talentMats.length ?? 0) > 0) {
            Text('天赋书').fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
            this.matGrid(this.vm.selectedDay()?.talentMats ?? [])
          }
          if ((this.vm.selectedDay()?.weaponMats.length ?? 0) > 0) {
            Text($r('app.string.ui_model_metadata_material_weapon_ascension_material'))
              .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
            this.matGrid(this.vm.selectedDay()?.weaponMats ?? [])
          }
        }
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      .border({ width: 1, color: $r('app.color.card_stroke') })
    }
  }

  @Builder
  weekPanel() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('默认日历时区')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Select(OFFSET_OPTIONS)
          .selected(GameCalendarRules.OFFSET_HOURS.indexOf(this.vm.week?.globalOffsetHours ?? this.displayOffset()))
          .value(GameCalendarRules.offsetLabel(this.vm.week?.globalOffsetHours ?? this.displayOffset()))
          .attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
          .hoverEffect(HoverEffect.Highlight)
          .onSelect((index: number) => this.changeGlobalOffset(index))
      }
      .width('100%')
      if ((this.vm.week?.projectId ?? 0) > 0) {
        Text(`当前养成项目「${this.vm.week?.projectName ?? ''}」 · ${GameCalendarRules.offsetLabel(this.displayOffset())}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      if (this.vm.weekMessage.length > 0) {
        ErrorHint({ text: this.vm.weekMessage, onRetry: () => this.loadWeek() })
      }
      if (this.vm.week !== undefined) {
        this.weekStrip()
        this.weekDetail()
      } else if (this.vm.weekMessage.length === 0) {
        Loading()
      }
    }
    .width('100%')
  }

  @Builder
  activityPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text($r('app.string.ui_home_recent'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.isLoggedIn && this.currentUid.length > 0) {
          Text(GameCalendarRules.offsetLabel(this.displayOffset()))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .width('100%')
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else if (this.currentUid.length === 0) {
        Column({ space: 14 }) {
          Text($r('app.string.ui_account_insights_no_account'))
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
          Button($r('app.string.ui_cultivation_navigate_action'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true)).constraintSize({ minHeight: 44 })
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/UserPage' });
            })
        }
        .width('100%')
        .padding({ top: 40, bottom: 40 })
      } else if (this.vm.loading) {
        Loading()
      } else {
        if (this.vm.message.length > 0) {
          ErrorHint({ text: this.vm.message, onRetry: () => this.loadData() })
        } else if (this.vm.entries.length === 0) {
          EmptyState({
            icon: '🗓️',
            text: this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.ui_home_no_events').id) ?? ''
          })
        }
        ForEach(this.vm.entries, (entry: ActCalendarEntry) => {
          this.calendarRow(entry)
        }, (entry: ActCalendarEntry) => `${entry.type}_${entry.id}_${entry.name}_${entry.startTime}`)
      }
    }
    .width('100%')
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
        this.header()
        Scroll() {
          GridRow({ columns: 2, gutter: 16 }) {
            GridCol({ span: this.isWide ? 1 : 2 }) {
              this.weekPanel()
            }
            GridCol({ span: this.isWide ? 1 : 2 }) {
              this.activityPanel()
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldValue: Area, area: Area) => {
        this.isWide = (area.width as number) >= 840;
      })
      .bindSheet($$this.showMatSheet, this.matSheet(), {
        title: { title: '材料详情' },
        showClose: true,
        dragBar: true,
        height: '70%',
        blurStyle: BlurStyle.Regular,
        systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
        backgroundColor: UiSurface.immersiveActive() ? Color.Transparent : $r('app.color.sheet_material_tint'),
      })
    }
    .width('100%')
    .height('100%')
  }
}
