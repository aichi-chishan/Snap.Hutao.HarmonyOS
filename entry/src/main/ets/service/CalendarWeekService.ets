/**
 * CalendarWeekService.ets
 * 周历数据（对齐 Windows CalendarViewModel + MaterialIds）：
 * - 天赋书/武器突破材料轮换（周一四 / 二五 / 三六，取各系列最高阶 id，对齐 Windows RotationalMaterialIdEntry）
 * - 角色生日（avatar_meta.birth "M/D"，按月日归组，对齐 Windows AvatarBirthdays）
 * - 生成包含今日的周视图（周一起始），周日密境全开不列材料（对齐 Windows dailyMaterials 无周日键）
 */
import { WikiMetaService, MetaMaterial } from './WikiMetaService';

/** 轮换材料系列（dayPair：1=周一四 2=周二五 3=周三六） */
class RotationalSeries {
  dayPair: number = 0;
  /** 系列最高阶素材 id（图标/名称来源，对齐 Windows entry.Highest） */
  highestId: number = 0;
  /** 系列名兜底（material_meta 缺失时使用，来自 Windows 表注释） */
  fallbackName: string = '';
}

function series(dayPair: number, id: number, name: string): RotationalSeries {
  const s: RotationalSeries = new RotationalSeries();
  s.dayPair = dayPair;
  s.highestId = id;
  s.fallbackName = name;
  return s;
}

/** Windows MaterialIds.Entries 轮换表（取每系列最高阶） */
const ROTATIONAL_SERIES: RotationalSeries[] = [
  // 天赋书（1043xx）
  series(1, 104303, '「自由」'), series(1, 104312, '「繁荣」'), series(1, 104322, '「浮世」'),
  series(1, 104331, '「诤言」'), series(1, 104340, '「公平」'), series(1, 104349, '「角逐」'),
  series(1, 104358, '「月光」'),
  series(2, 104306, '「抗争」'), series(2, 104315, '「勤劳」'), series(2, 104325, '「风雅」'),
  series(2, 104334, '「巧思」'), series(2, 104343, '「正义」'), series(2, 104352, '「焚燔」'),
  series(2, 104361, '「乐园」'),
  series(3, 104309, '「诗文」'), series(3, 104318, '「黄金」'), series(3, 104328, '「天光」'),
  series(3, 104337, '「笃行」'), series(3, 104346, '「秩序」'), series(3, 104355, '「纷争」'),
  series(3, 104364, '「浪迹」'),
  // 武器突破材料（114xxx）
  series(1, 114004, '高塔孤王'), series(1, 114016, '孤云寒林'), series(1, 114028, '远海夷地'),
  series(1, 114040, '谧林涓露'), series(1, 114052, '悠古弦音'), series(1, 114064, '贡祭炽心'),
  series(1, 114076, '奇巧秘器'),
  series(2, 114008, '凛风奔狼'), series(2, 114020, '雾海云间'), series(2, 114032, '鸣神御灵'),
  series(2, 114044, '绿洲花园'), series(2, 114056, '纯圣露滴'), series(2, 114068, '谵妄圣主'),
  series(2, 114080, '长夜燧火'),
  series(3, 114012, '狮牙斗士'), series(3, 114024, '漆黑陨铁'), series(3, 114036, '今昔剧画'),
  series(3, 114048, '谧林涓露'), series(3, 114060, '无垢之海'), series(3, 114072, '神合秘烟'),
  series(3, 114084, '终北遗嗣'),
];

/** 生日角色条目 */
export class CalendarBirthday {
  name: string = '';
  /** AvatarIcon 图标名（rawfile） */
  icon: string = '';
}

/** 周历单日 */
export class CalendarWeekDay {
  /** 当日零点（本地时区）epoch ms */
  dateMs: number = 0;
  /** 显示名：周一..周日 */
  dayName: string = '';
  /** M/D 文案 */
  monthDay: string = '';
  isToday: boolean = false;
  /** 当日生日角色 */
  birthdays: CalendarBirthday[] = [];
  /** 当日可刷天赋书（系列显示名） */
  talentNames: string[] = [];
  /** 当日可刷武器材料 */
  weaponNames: string[] = [];
}

/** 周视图数据 */
export class CalendarWeekData {
  days: CalendarWeekDay[] = [];
  /** 本周包含生日角色的日期（月日 → true，供周条做角标） */
  birthdayFlags: boolean[] = [];
}

export class CalendarWeekService {
  private static loaded: boolean = false;
  /** 月日 → 生日角色 */
  private static birthdays: Map<string, CalendarBirthday[]> = new Map();
  /** 系列最高阶 id → 显示名（material_meta 优先，缺省用表内名） */
  private static seriesNames: Map<number, string> = new Map();
  /** 系列最高阶 id → 图标名 */
  private static seriesIcons: Map<number, string> = new Map();

  /** 系列图标名（MetaIcon ItemIcon 类目；最高阶图标已随包内置） */
  static iconOf(id: number): string {
    return CalendarWeekService.seriesIcons.get(id) ?? `UI_ItemIcon_${id}`;
  }

  /** 惰性装载：生日表 + 材料名表 */
  private static async ensureLoaded(): Promise<void> {
    if (CalendarWeekService.loaded) {
      return;
    }
    const materials: Map<number, MetaMaterial> = await WikiMetaService.getMaterials();
    for (const s of ROTATIONAL_SERIES) {
      const m: MetaMaterial | undefined = materials.get(s.highestId);
      CalendarWeekService.seriesNames.set(s.highestId,
        m !== undefined && m.n.length > 0 ? m.n : s.fallbackName);
      CalendarWeekService.seriesIcons.set(s.highestId,
        m !== undefined && m.i.length > 0 ? m.i : `UI_ItemIcon_${s.highestId}`);
    }
    const avatars = await WikiMetaService.getAvatars();
    for (const a of avatars) {
      const birth: string = a.birth;
      if (birth.length === 0) {
        continue;
      }
      // birth 格式 "M/D"（如 2/20）
      const slash: number = birth.indexOf('/');
      if (slash <= 0) {
        continue;
      }
      const month: number = Number(birth.substring(0, slash));
      const day: number = Number(birth.substring(slash + 1));
      if (!Number.isFinite(month) || !Number.isFinite(day)) {
        continue;
      }
      const key: string = `${month}-${day}`;
      let list: CalendarBirthday[] | undefined = CalendarWeekService.birthdays.get(key);
      if (list === undefined) {
        list = [];
        CalendarWeekService.birthdays.set(key, list);
      }
      const b: CalendarBirthday = new CalendarBirthday();
      b.name = a.name;
      b.icon = a.icon;
      list.push(b);
    }
    CalendarWeekService.loaded = true;
  }

  /** 构建包含今日的周视图（周一起始，7 天；材料/生日不依赖登录） */
  static async loadWeek(): Promise<CalendarWeekData> {
    await CalendarWeekService.ensureLoaded();
    const data: CalendarWeekData = new CalendarWeekData();
    const dayNames: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    // 本周周一零点（本地时区）
    const now: Date = new Date();
    const todayZero: number = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    const dow: number = now.getDay() === 0 ? 7 : now.getDay();
    const monday: number = todayZero - (dow - 1) * 86400000;
    for (let i = 0; i < 7; i++) {
      const dateMs: number = monday + i * 86400000;
      const d: Date = new Date(dateMs);
      const day: CalendarWeekDay = new CalendarWeekDay();
      day.dateMs = dateMs;
      day.dayName = dayNames[i];
      day.monthDay = `${d.getMonth() + 1}/${d.getDate()}`;
      day.isToday = dateMs === todayZero;
      // 星期几（1=周一..7=周日）→ dayPair；周日(7)无材料（对齐 Windows）
      const weekday: number = i + 1;
      if (weekday <= 6) {
        const pair: number = weekday <= 3 ? weekday : weekday - 3;
        for (const s of ROTATIONAL_SERIES) {
          if (s.dayPair !== pair) {
            continue;
          }
          const name: string | undefined = CalendarWeekService.seriesNames.get(s.highestId);
          if (name === undefined) {
            continue;
          }
          if (s.highestId >= 104300 && s.highestId < 114000) {
            day.talentNames.push(name);
          } else {
            day.weaponNames.push(name);
          }
        }
      }
      const key: string = `${d.getMonth() + 1}-${d.getDate()}`;
      day.birthdays = CalendarWeekService.birthdays.get(key) ?? [];
      data.days.push(day);
      data.birthdayFlags.push(day.birthdays.length > 0);
    }
    return data;
  }
}
