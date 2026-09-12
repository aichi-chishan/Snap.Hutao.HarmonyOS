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
import { WikiMetaService, WikiAvatarMeta, MetaMaterial } from '../service/WikiMetaService';

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
  /** 材料元数据（id → n/i/r） */
  @State materials: Map<number, MetaMaterial> = new Map();
  /** 全部角色元数据（生日：birth = 'M/D'） */
  @State avatars: WikiAvatarMeta[] = [];

  aboutToAppear(): void {
    WikiMetaService.getMaterials().then((m: Map<number, MetaMaterial>) => {
      this.materials = m;
    }).catch(() => {
    });
    WikiMetaService.getAvatars().then((a: WikiAvatarMeta[]) => {
      this.avatars = a;
    }).catch(() => {
    });
  }

  /** 按星期计算今日材料（周一四/周二五/周三六；本地 meta 只含高稀有度，命中即显示） */
  private todayMaterials(): DailyMaterial[] {
    const day: number = new Date().getDay();
    let ids: number[] = [];
    if (day === 1 || day === 4) {
      ids = [104301, 104302, 104303, 114001, 114002, 114003, 114004];
    } else if (day === 2 || day === 5) {
      ids = [104304, 104305, 104306, 114005, 114006, 114007, 114008];
    } else if (day === 3 || day === 6) {
      ids = [104307, 104308, 104309, 114009, 114010, 114011, 114012];
    } else {
      return [];
    }
    const out: DailyMaterial[] = [];
    for (let i = 0; i < ids.length; i++) {
      const m: MetaMaterial | undefined = this.materials.get(ids[i]);
      if (m !== undefined && m.i.length > 0) {
        const dm: DailyMaterial = new DailyMaterial();
        dm.id = ids[i];
        dm.name = m.n;
        dm.icon = m.i;
        out.push(dm);
      }
    }
    return out;
  }

  /** 今日生日角色（avatar_meta.birth 为 'M/D' 字符串） */
  private todayBirthdays(): BirthdayCell[] {
    const now: Date = new Date();
    const key: string = `${now.getMonth() + 1}/${now.getDate()}`;
    const out: BirthdayCell[] = [];
    for (let i = 0; i < this.avatars.length; i++) {
      const a: WikiAvatarMeta = this.avatars[i];
      if (a.birth === key && a.sideIcon.length > 0) {
        const b: BirthdayCell = new BirthdayCell();
        b.name = a.name;
        b.icon = a.sideIcon;
        out.push(b);
      }
    }
    return out;
  }

  private weekDays(): WeekDayCell[] {
    const out: WeekDayCell[] = [];
    const now: Date = new Date();
    // 周一为一周起点
    const dow: number = now.getDay();
    const mondayOffset: number = dow === 0 ? -6 : 1 - dow;
    for (let i = 0; i < 7; i++) {
      const d: Date = new Date(now);
      d.setDate(now.getDate() + mondayOffset + i);
      const cell: WeekDayCell = new WeekDayCell();
      cell.index = i;
      cell.dayNum = d.getDate();
      cell.label = HomeCalendarCard.weekLabel(i);
      cell.isToday = i - mondayOffset === 0;
      out.push(cell);
    }
    return out;
  }

  private static weekLabel(i: number): string {
    const labels: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[i];
  }

  /** 本月日期格（从今天到月末，最多 2 行 14 格） */
  private monthDays(): WeekDayCell[] {
    const out: WeekDayCell[] = [];
    const now: Date = new Date();
    const lastDay: Date = new Date(now.getFullYear(), now.getMonth() + 1, 0);
    let count: number = lastDay.getDate() - now.getDate() + 1;
    if (count > 14) {
      count = 14;
    }
    const d: Date = new Date(now);
    for (let i = 0; i < count; i++) {
      d.setDate(now.getDate() + i);
      const cell: WeekDayCell = new WeekDayCell();
      cell.index = i;
      cell.dayNum = d.getDate();
      cell.label = `${d.getMonth() + 1}.${d.getDate()}`;
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
      Column({ space: 10 }) {
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
            .padding({ top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor(cell.isToday ? $r('app.color.app_primary_bg') : $r('app.color.card_background'))
          }, (cell: WeekDayCell) => `wk_${cell.index}_${cell.isToday}`)
        }
        .width('100%')
        .padding(4)
        .borderRadius(10)
        .backgroundColor($r('app.color.card_inner_tint'))

        // 本月日期格（7 列，有事件的日期显示事件标记点）
        Grid() {
          ForEach(this.monthDays(), (cell: WeekDayCell) => {
            GridItem() {
              Column({ space: 3 }) {
                Text(cell.label)
                  .fontSize(12)
                  .fontColor(cell.isToday ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
                Circle()
                  .width(5)
                  .height(5)
                  .backgroundColor(this.hasEvent(cell) ? $r('app.color.app_primary') : Color.Transparent)
                  .opacity(cell.isToday ? 1 : 0.55)
              }
              .width('100%')
              .padding({ top: 5, bottom: 5 })
              .borderRadius(8)
              .backgroundColor(cell.isToday ? $r('app.color.app_primary_bg') : Color.Transparent)
            }
          }, (cell: WeekDayCell) => `md_${cell.index}_${cell.isToday}_${this.hasEvent(cell)}`)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        .columnsGap(4)
        .rowsGap(4)
        .width('100%')

        // 今日材料（按星期轮换：天赋书/武器矿，图标取自本地元数据）
        if (this.todayMaterials().length > 0) {
          Row({ space: 6 }) {
            Text('今日获取')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            ForEach(this.todayMaterials(), (m: DailyMaterial, idx: number) => {
              Column({ space: 2 }) {
                MetaIcon({ category: 'ItemIcon', name: m.icon, iconSize: 22, remoteFallback: true })
                Text(HomeCalendarCard.shorten(m.name))
                  .fontSize(8)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
              }
            }, (m: DailyMaterial) => `dm_${m.id}`)
            Blank()
          }
          .width('100%')
        }

        // 今日角色生日（头像 + 名字）
        if (this.todayBirthdays().length > 0) {
          Row({ space: 6 }) {
            Text('今日生日')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            ForEach(this.todayBirthdays(), (b: BirthdayCell, idx: number) => {
              Column({ space: 2 }) {
                MetaIcon({ category: 'AvatarIcon', name: b.icon, iconSize: 22, circular: true })
                Text(b.name.length > 4 ? `${b.name.substring(0, 4)}…` : b.name)
                  .fontSize(8)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
              }
            }, (b: BirthdayCell) => `bd_${b.name}`)
            Blank()
          }
          .width('100%')
        }

        // 今日活动名称
        if (this.todayActs.length > 0) {
          Text(`今日活动：${this.todayActs.slice(0, 2).join(' / ')}`)
            .fontSize(12)
            .fontColor($r('app.color.app_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
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
