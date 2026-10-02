/**
 * HomeCalendarCard.ets
 * 主页日历卡（对齐 Windows CalendarCard）：
 * 顶部周历（周一~周日 7 格，选中今天）+ 本月日期事件网格（带事件标记）
 * + 今日材料（按星期轮换：天赋书/武器矿，取本地元数据图标）+ 今日角色生日（头像+名字）+ 今日活动。
 * 整卡可点击 → 活动日历页。
 */
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';
import { MetaIcon } from './MetaIcon';
import { CalendarWeekService, CalendarWeekData, CalendarWeekDay } from '../service/CalendarWeekService';
import { GameCalendarRules } from '../service/GameCalendarRules';
import { RegionUtil } from '../common/Constants';

/** 一周 7 天的日期信息 */
class WeekDayCell {
  index: number = 0;
  label: string = '';
  dayNum: number = 0;
  isToday: boolean = false;
}

/** 今日材料行：星期 → 材料 id（对齐 Windows MaterialIds.cs 周一四/周二五/周三六 分组） */
class DailyMaterial {
  id: number = 0;
  name: string = '';
  icon: string = '';
}

/** 今日生日角色 */
class BirthdayCell {
  name: string = '';
  icon: string = '';
}

@Component
export struct HomeCalendarCard {
  /** 事件日期集合（活动/卡池起止日 → 标记日），key = 'M-D' */
  @Prop eventDays: number[] = [];
  /** 今日活动名称（最多 2 条） */
  @Prop todayActs: string[] = [];
  onTap: () => void = () => {
  };
  @State week: CalendarWeekData | undefined = undefined;
  @StorageProp('currentUid') @Watch('loadWeek') currentUid: string = '';
  @StorageProp('calendarSettingsVersion') @Watch('loadWeek') calendarVersion: number = 0;
  private sequence: number = 0;

  aboutToAppear(): void { this.loadWeek(); }
  aboutToDisappear(): void { this.sequence++; }

  async loadWeek(): Promise<void> {
    const sequence: number = ++this.sequence;
    this.week = undefined;
    const week: CalendarWeekData = await CalendarWeekService.loadWeek();
    if (sequence === this.sequence) { this.week = week; }
  }

  private today(): CalendarWeekDay | undefined {
    return this.week?.days.find((day: CalendarWeekDay) => day.isToday);
  }

  private todayMaterials(): DailyMaterial[] {
    const today: CalendarWeekDay | undefined = this.today();
    if (today === undefined) { return []; }
    const out: DailyMaterial[] = [];
    for (const material of today.talentMats.concat(today.weaponMats)) {
      const item: DailyMaterial = new DailyMaterial();
      item.id = material.id;
      item.name = material.name;
      item.icon = material.icon;
      out.push(item);
    }
    return out;
  }

  private todayBirthdays(): BirthdayCell[] {
    const out: BirthdayCell[] = [];
    for (const birthday of this.today()?.birthdays ?? []) {
      const item: BirthdayCell = new BirthdayCell();
      item.name = birthday.name;
      item.icon = birthday.icon;
      out.push(item);
    }
    return out;
  }

  private weekDays(): WeekDayCell[] {
    const out: WeekDayCell[] = [];
    for (const day of this.week?.days ?? []) {
      const cell: WeekDayCell = new WeekDayCell();
      cell.index = out.length;
      cell.dayNum = Number(day.monthDay.split('/')[1]);
      cell.label = day.dayName;
      cell.isToday = day.isToday;
      out.push(cell);
    }
    return out;
  }

  /** 本月日期格（从今天到月末，最多 2 行 14 格） */
  private monthDays(): WeekDayCell[] {
    const out: WeekDayCell[] = [];
    const offset: number = GameCalendarRules.serverOffset(RegionUtil.regionOfUid(this.currentUid));
    const now: Date = new Date(Date.now() + offset * 3600000);
    const lastDay: Date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0));
    let count: number = lastDay.getUTCDate() - now.getUTCDate() + 1;
    if (count > 14) {
      count = 14;
    }
    const d: Date = new Date(now);
    for (let i = 0; i < count; i++) {
      d.setUTCDate(now.getUTCDate() + i);
      const cell: WeekDayCell = new WeekDayCell();
      cell.index = i;
      cell.dayNum = d.getUTCDate();
      cell.label = `${d.getUTCMonth() + 1}.${d.getUTCDate()}`;
      cell.isToday = i === 0;
      out.push(cell);
    }
    return out;
  }

  hasEvent(cell: WeekDayCell): boolean {
    if (cell.dayNum <= 0) {
      return false;
    }
    for (let i = 0; i < this.eventDays.length; i++) {
      if (this.eventDays[i] === cell.dayNum) {
        return true;
      }
    }
    return false;
  }

    /** 是否撑满 Grid 单元格高度（行内等高） */
    @Prop fillHeight: boolean = false;

  build() {
    PressCard({
      fillHeight: this.fillHeight,
      onTap: () => {
        this.onTap()
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'Database', iconSize: 20 })
          Text('日历')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text('查看全部 ›')
            .fontSize(12)
            .fontColor($r('app.color.app_primary'))
        }
        .width('100%')
        .height(24)
        .flexShrink(0)

        // 周历 Segmented（7 格，选中今天）
        Row({ space: 4 }) {
          ForEach(this.weekDays(), (cell: WeekDayCell) => {
            Column({ space: 2 }) {
              Text(cell.label)
                .fontSize(10)
                .fontColor(cell.isToday ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
              Text(`${cell.dayNum}`)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(cell.isToday ? $r('app.color.app_primary') : $r('app.color.text_primary'))
            }
            .layoutWeight(1)
            .padding({ top: 3, bottom: 3 })
            .borderRadius(8)
            .backgroundColor(cell.isToday ? $r('app.color.app_primary_bg') : $r('app.color.card_inner_tint'))
          }, (cell: WeekDayCell) => `wk_${cell.index}_${cell.isToday}`)
        }
        .width('100%')
        .height(48)
        .padding(4)
        .borderRadius(10)
        .backgroundColor($r('app.color.card_inner_tint'))


        // 正文独立纵向视口兜底；每行横滚保留完整名称，不截掉材料、生日或活动。
        Scroll() {
          Column({ space: 4 }) {
            if (this.today()?.allMaterialsOpen === true) {
              Text('全部材料副本均可挑战').fontSize(12).fontColor($r('app.color.text_secondary'))
            }
            if (this.todayMaterials().length > 0) {
              Row({ space: 6 }) {
                Text('今日获取')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                Scroll() {
                  Row({ space: 10 }) {
                    ForEach(this.todayMaterials(), (m: DailyMaterial) => {
                      Row({ space: 3 }) {
                        MetaIcon({ category: 'ItemIcon', name: m.icon, iconSize: 22, remoteFallback: true })
                        Text(m.name)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(1)
                      }
                    }, (m: DailyMaterial) => `dm_${m.id}_${m.name}_${m.icon}`)
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
            if (this.todayBirthdays().length > 0) {
              Row({ space: 6 }) {
                Text('今日生日')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                Scroll() {
                  Row({ space: 10 }) {
                    ForEach(this.todayBirthdays(), (b: BirthdayCell) => {
                      Row({ space: 3 }) {
                        MetaIcon({ category: 'AvatarIcon', name: b.icon, iconSize: 22, circular: true })
                        Text(b.name)
                          .fontSize(12)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                      }
                    }, (b: BirthdayCell) => `bd_${b.name}_${b.icon}`)
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
            if (this.todayActs.length > 0) {
              Scroll() {
                Text(`今日活动：${this.todayActs.join(' / ')}`)
                  .fontSize(12)
                  .fontColor($r('app.color.app_primary'))
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
    }
  }

  /** 材料名太长截断（保留书名号与后段） */
  private static shorten(name: string): string {
    if (name.length <= 6) {
      return name;
    }
    if (name.startsWith('「') && name.endsWith('」')) {
      return name.length > 8 ? `「${name.substring(1, 7)}…」` : name;
    }
    if (name.startsWith('高塔') || name.startsWith('凛风') || name.startsWith('狮牙')) {
      return name;
    }
    return `${name.substring(0, 6)}…`;
  }
}
