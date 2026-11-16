/**
 * HomeCalendarCard.ets
 * 主页日历卡（对齐 Windows CalendarCard）：
 * 七日周历及活动结束标记，支持在首页查看所选日的轮换材料和角色生日。
 */
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';
import { MetaIcon } from './MetaIcon';
import { calendarDateLabel, calendarWeekdayLabel } from './CalendarWeekdayLabel';
import { CalendarWeekService, CalendarWeekData, CalendarWeekDay, CalendarWeekMaterial,
  CalendarBirthday, CalendarMaterialConsumer } from '../service/CalendarWeekService';
import { GameCalendarRules } from '../service/GameCalendarRules';
import { AppButtonModifier, SurfaceClass, UiSurface } from '../common/UiSurface';
import { WishHistoryWikiParams } from '../model/WishHistory';

@Component
export struct HomeCalendarCard {
  /** 活动或卡池结束时间戳，按周历时区归入对应日期。 */
  @Prop eventDays: number[] = [];
  /** 今日活动名称（最多 2 条） */
  @Prop todayActs: string[] = [];
  onTap: () => void = () => {
  };
  @State week: CalendarWeekData | undefined = undefined;
  @State selectedDateMs: number = 0;
  @State private popupMaterial: CalendarWeekMaterial | undefined = undefined;
  @State private popupWidth: number = 320;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('calendarSettingsVersion') @Watch('loadWeek') calendarVersion: number = 0;
  @StorageProp('helpLocaleVersion') @Watch('loadWeek') localeVersion: number = 0;
  private sequence: number = 0;
  private attached: boolean = false;
  private clockTimer: number = -1;

  aboutToAppear(): void {
    this.attached = true;
    this.loadWeek();
    this.clockTimer = setInterval(() => {
      const offset: number = this.week?.offsetHours ?? GameCalendarRules.DEFAULT_OFFSET_HOURS;
      const today: CalendarWeekDay | undefined = this.week?.days.find((day: CalendarWeekDay): boolean => day.isToday);
      if (today !== undefined && GameCalendarRules.serverDay(Date.now(), offset) !==
        GameCalendarRules.serverDay(today.dateMs, offset)) {
        this.loadWeek();
      }
    }, 60000);
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.sequence++;
    this.popupMaterial = undefined;
    clearInterval(this.clockTimer);
  }

  async loadWeek(): Promise<void> {
    if (!this.attached) { return; }
    const sequence: number = ++this.sequence;
    try {
      const week: CalendarWeekData = await CalendarWeekService.loadWeek();
      if (sequence !== this.sequence) { return; }
      const selected: CalendarWeekDay | undefined = this.selectedDay();
      this.week = week;
      if (selected === undefined || selected.isToday ||
        !week.days.some((day: CalendarWeekDay): boolean => day.dateMs === this.selectedDateMs)) {
        this.selectDate(week.days.find((day: CalendarWeekDay): boolean => day.isToday)?.dateMs ?? 0);
      }
      if (this.popupMaterial !== undefined) {
        this.popupMaterial = this.materialOnDay(this.popupMaterial.id);
      }
    } catch (e) {
      if (sequence === this.sequence) {
        this.week = undefined;
        this.popupMaterial = undefined;
      }
    }
  }

  private selectedDay(): CalendarWeekDay | undefined {
    return this.week?.days.find((day: CalendarWeekDay): boolean => day.dateMs === this.selectedDateMs);
  }

  private selectedMaterials(): CalendarWeekMaterial[] {
    const day: CalendarWeekDay | undefined = this.selectedDay();
    return day === undefined ? [] : day.talentMats.concat(day.weaponMats);
  }

  private selectDate(dateMs: number): void {
    if (dateMs !== this.selectedDateMs) {
      this.popupMaterial = undefined;
      this.selectedDateMs = dateMs;
    }
  }

  private materialOnDay(id: number): CalendarWeekMaterial | undefined {
    const day: CalendarWeekDay | undefined = this.selectedDay();
    return day?.talentMats.find((item: CalendarWeekMaterial): boolean => item.id === id) ??
      day?.weaponMats.find((item: CalendarWeekMaterial): boolean => item.id === id);
  }

  private openMaterial(id: number): void {
    if (this.attached) { this.popupMaterial = this.materialOnDay(id); }
  }

  private dismissMaterial(id: number): void {
    if (this.popupMaterial?.id === id) { this.popupMaterial = undefined; }
  }

  private async openConsumer(materialId: number, consumer: CalendarMaterialConsumer): Promise<void> {
    const material: CalendarWeekMaterial | undefined = this.popupMaterial;
    if (!this.attached || material === undefined || material.id !== materialId) { return; }
    const listed: boolean = material.consumers.some((item: CalendarMaterialConsumer): boolean =>
      item.id === consumer.id && item.category === consumer.category);
    if (!listed) { return; }
    const params: WishHistoryWikiParams = { itemId: consumer.id };
    const url: string = material.isTalent ? 'pages/WikiAvatarPage' : 'pages/WikiWeaponPage';
    this.popupMaterial = undefined;
    try {
      await this.getUIContext().getRouter().pushUrl({ url: url, params: params });
    } catch (_) {
      if (this.attached) {
        this.getUIContext().getPromptAction().showToast({ message: '无法打开图鉴，请稍后重试', systemMaterial: UiSurface.dialogMaterial() });
      }
    }
  }

  private qualityColor(rank: number): Resource {
    if (rank >= 5) { return $r('app.color.five_star'); }
    if (rank === 4) { return $r('app.color.four_star'); }
    if (rank === 3) { return $r('app.color.three_star'); }
    return $r('app.color.divider');
  }

  private hasEvent(day: CalendarWeekDay): boolean {
    const offset: number = this.week?.offsetHours ?? GameCalendarRules.DEFAULT_OFFSET_HOURS;
    const ordinal: number = GameCalendarRules.serverDay(day.dateMs, offset);
    return this.eventDays.some((endMs: number): boolean => GameCalendarRules.serverDay(endMs, offset) === ordinal);
  }

  /** 是否撑满 Grid 单元格高度（行内等高） */
  @Prop fillHeight: boolean = false;

  build() {
    PressCard({
      fillHeight: this.fillHeight,
      onTap: () => {
        if (this.popupMaterial === undefined) { this.onTap(); }
      },
      radius: 12,
    }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'Database', iconSize: 20 })
          Text($r('app.string.ui_section_calendar'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text($r('app.string.ui_setting_key_shortcut_virtual_key_code_action'))
            .fontSize(12)
            .fontColor($r('app.color.app_primary_text'))
        }
        .width('100%')
        .height(24)
        .flexShrink(0)
        .focusable(true)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.onTap();
        })

        // 子日期按钮优先响应点击，卡片其他区域继续打开活动日历页。
        Row({ space: 4 }) {
          ForEach(this.week?.days ?? [], (day: CalendarWeekDay) => {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 2 }) {
                Text(calendarWeekdayLabel(day.weekday))
                  .fontSize(10)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor(this.selectedDateMs === day.dateMs ? $r('app.color.app_primary_text') : $r('app.color.text_secondary'))
                Text(`${day.dayInMonth}${this.hasEvent(day) ? '·' : ''}`)
                  .fontSize(14)
                  .fontWeight(day.isToday ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.selectedDateMs === day.dateMs ? $r('app.color.app_primary_text') : $r('app.color.text_primary'))
              }
            }
            .layoutWeight(1)
            .height(44)
            .padding(0)
            .borderRadius(8)
            .backgroundColor(this.selectedDateMs === day.dateMs ? $r('app.color.app_primary_bg') : $r('app.color.card_inner_tint'))
            .hoverEffect(HoverEffect.Highlight)
            .accessibilitySelected(this.selectedDateMs === day.dateMs)
            .accessibilityText(`${calendarDateLabel(this.getUIContext(), day)}${this.hasEvent(day) ? ' 有活动结束' : ''}`)
            .onClick(() => {
              this.selectDate(day.dateMs);
            })
          }, (day: CalendarWeekDay) => `wk_${day.dateMs}_${day.isToday}_${this.localeVersion}`)
        }
        .width('100%')
        .height(48)
        .padding(2)
        .borderRadius(10)
        .backgroundColor($r('app.color.card_inner_tint'))


        // 正文独立纵向视口兜底；每行横滚保留完整名称，不截掉材料、生日或活动。
        Scroll() {
          Column({ space: 4 }) {
            if (this.selectedDay()?.allMaterialsOpen === true) {
              Text($r('app.string.ui_card_calendar_all_materials_hint'))
                .fontSize(12).fontColor($r('app.color.text_secondary'))
            }
            if (this.selectedMaterials().length > 0) {
              Row({ space: 6 }) {
                Text('轮换素材')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                Scroll() {
                  Row({ space: 10 }) {
                    ForEach(this.selectedMaterials(), (m: CalendarWeekMaterial) => {
                      this.materialButton(m.id)
                    }, (m: CalendarWeekMaterial) => `dm_${this.selectedDateMs}_${m.id}`)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .layoutWeight(1)
                .height(44)
                .align(Alignment.Start)
              }
              .width('100%')
              .height(44)
            }
            if ((this.selectedDay()?.birthdays.length ?? 0) > 0) {
              Row({ space: 6 }) {
                Text('角色生日')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                Scroll() {
                  Row({ space: 10 }) {
                    ForEach(this.selectedDay()?.birthdays ?? [], (b: CalendarBirthday) => {
                      Row({ space: 3 }) {
                        MetaIcon({ category: 'AvatarIcon', name: b.icon, iconSize: 22, circular: true })
                        Text(b.name)
                          .fontSize(12)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                      }
                    }, (b: CalendarBirthday) => `bd_${b.name}_${b.icon}`)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .layoutWeight(1)
                .height(24)
                .align(Alignment.Start)
              }
              .width('100%')
              .height(24)
            }
            if (this.selectedDay()?.isToday === true && this.todayActs.length > 0) {
              Scroll() {
                Text(`今日活动：${this.todayActs.join(' / ')}`)
                  .fontSize(12)
                  .fontColor($r('app.color.app_primary_text'))
                  .maxLines(1)
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(24)
              .align(Alignment.Start)
            }
          }
          .width('100%')
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
        .width('100%')
        .height(this.fillHeight ? 92 : undefined)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height(this.fillHeight ? '100%' : undefined)
      .padding(12)
      .onAreaChange((_old: Area, area: Area): void => {
        this.popupWidth = Math.min(320, Math.floor(Number(area.width)));
      })
    }
  }

  @Builder
  materialButton(id: number) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 4 }) {
        MetaIcon({ category: 'ItemIcon', name: this.materialOnDay(id)?.icon ?? '', iconSize: 24, remoteFallback: true })
        Text(this.materialOnDay(id)?.name ?? '').fontSize(12).fontColor($r('app.color.text_primary')).maxLines(1)
      }
    }
    .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
    .height(44).padding({ left: 6, right: 6 })
    .backgroundColor(this.materialOnDay(id)?.highlighted ? $r('app.color.cultivate_highlight') : Color.Transparent)
    .accessibilityText(this.materialOnDay(id)?.name ?? '')
    .onClick(() => { this.openMaterial(id); })
    .bindPopup(this.popupMaterial?.id === id, {
      builder: (): void => { this.materialPopup(id); },
      width: this.popupWidth,
      placement: Placement.Bottom,
      focusable: true,
      autoCancel: true,
      systemMaterial: UiSurface.dialogMaterial(this.surfaceMode, this.surfaceLevel),
      backgroundBlurStyle: UiSurface.blurStyle(SurfaceClass.OVERLAY_MODAL, this.surfaceMode, this.surfaceLevel),
      popupColor: UiSurface.immersiveActive() ? Color.Transparent : $r('app.color.sheet_material_tint'),
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible) { this.dismissMaterial(id); }
      }
    })
  }

  @Builder
  materialPopup(materialId: number) {
    if (this.popupMaterial !== undefined && this.popupMaterial.id === materialId) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          MetaIcon({ category: 'ItemIcon', name: this.popupMaterial.icon, iconSize: 44 })
            .border({ width: 1, color: this.qualityColor(this.popupMaterial.rank), radius: 6 })
          Column({ space: 2 }) {
            Text(this.popupMaterial.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(this.popupMaterial.isTalent ? $r('app.string.ui_wi_ki_avatar_ascension_materials_header') :
              $r('app.string.ui_model_metadata_material_weapon_ascension_material'))
              .fontSize(12).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            NavIcon({ name: 'Close', iconSize: 16, symbolColor: $r('app.color.text_secondary') })
          }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).width(44).height(44).padding(0)
            .accessibilityText($r('app.string.ui_action_close')).onClick(() => { this.popupMaterial = undefined; })
        }.width('100%')
        Text(this.popupMaterial.isTalent ? $r('app.string.ui_nav_wiki_avatar') : $r('app.string.ui_nav_wiki_weapon'))
          .width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
        if (this.popupMaterial.consumers.length === 0) {
          Text($r('app.string.common_empty')).width('100%').fontSize(12).fontColor($r('app.color.text_secondary'))
        } else {
          Scroll() {
            GridRow({ columns: this.popupWidth >= 280 ? 4 : 3, gutter: { x: 4, y: 6 } }) {
              ForEach(this.popupMaterial.consumers, (consumer: CalendarMaterialConsumer) => {
                GridCol() {
                  Button({ type: ButtonType.Normal }) {
                    Column({ space: 3 }) {
                      MetaIcon({ category: consumer.category, name: consumer.icon, iconSize: 40 })
                        .border({ width: 1, color: this.qualityColor(consumer.quality), radius: 6 })
                      Text(consumer.name).fontSize(11).fontColor($r('app.color.text_primary')).maxLines(2)
                        .textAlign(TextAlign.Center).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }.width('100%').padding(3)
                  }.attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel)).padding(0).width('100%')
                    .backgroundColor(consumer.highlighted ? $r('app.color.cultivate_highlight') : Color.Transparent)
                    .accessibilityText(consumer.name)
                    .onClick(() => { this.openConsumer(materialId, consumer); })
                }
              }, (consumer: CalendarMaterialConsumer): string =>
                `${consumer.category}_${consumer.id}_${consumer.name}_${consumer.highlighted}`)
            }.width('100%')
          }.width('100%').constraintSize({ maxHeight: 224 }).scrollBar(BarState.Auto)
        }
      }.width('100%').padding(12).alignItems(HorizontalAlign.Start)
    }
  }

}
