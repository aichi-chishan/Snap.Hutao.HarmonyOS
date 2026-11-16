/**
 * CalendarWeekService.ets
 * 周历数据（对齐 Windows CalendarViewModel + MaterialIds）：
 * - 天赋书/武器突破材料轮换（周一四 / 二五 / 三六，取各系列最高阶 id，对齐 Windows RotationalMaterialIdEntry）
 * - 角色生日（avatar_meta.birth "M/D"，按月日归组，对齐 Windows AvatarBirthdays）
 * - 按当前养成项目或手动选择的服务器时区生成本周，周日及卡池全开期间不列轮换材料
 * - 本地养成计划联动高亮（对齐 Windows InitializeHighlightItems：当前计划命中的系列/角色全高亮）
 */
import { i18n } from '@kit.LocalizationKit';
import { AppLocaleService } from './AppLocaleService';
import { WikiMetaService, GachaEventMeta, MetaMaterial, WikiAvatarMeta, WikiWeaponMeta } from './WikiMetaService';
import { GameCalendarRules, RotationalMaterialSeries, ROTATIONAL_SERIES } from './GameCalendarRules';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { CultivationRepo, CultivateProject, CultivateEntry } from '../data/repo/CultivationRepo';

const GLOBAL_OFFSET_KEY: string = 'app.calendar_server_time_zone_offset';
const FIRST_DAY_OF_WEEK_KEY: string = 'calendar.first_day_of_week';

/** 生日角色条目 */
export class CalendarBirthday {
  name: string = '';
  /** AvatarIcon 图标名（rawfile） */
  icon: string = '';
}

/** 材料消费者（该材料用于哪些角色/武器养成，对齐 Windows CalendarItem） */
export class CalendarMaterialConsumer {
  /** 角色 id / 武器 id */
  id: number = 0;
  name: string = '';
  /** MetaIcon 类目（AvatarIcon / EquipIcon） */
  category: string = '';
  /** 图标名（rawfile） */
  icon: string = '';
  /** 品质（描边框颜色） */
  quality: number = 0;
  /** 在当前养成计划中（全不透明高亮，对齐 Windows item.Highlight） */
  highlighted: boolean = false;
}

/** 周历材料条目（一个轮换系列，对齐 Windows CalendarMaterial） */
export class CalendarWeekMaterial {
  /** 系列最高阶素材 id */
  id: number = 0;
  name: string = '';
  /** ItemIcon 图标名 */
  icon: string = '';
  /** 品质（rankLevel，描边框颜色） */
  rank: number = 0;
  /** true=天赋书 false=武器突破材料（详情类型描述用） */
  isTalent: boolean = true;
  dayPair: number = 0;
  /** 当前养成计划命中（高亮底色，对齐 Windows material.Highlight） */
  highlighted: boolean = false;
  /** 需要该材料的角色/武器（详情弹层展示） */
  consumers: CalendarMaterialConsumer[] = [];
}

/** 周历单日 */
export class CalendarWeekDay {
  /** 所选服务器时区的当日零点，epoch ms */
  dateMs: number = 0;
  dayInMonth: number = 0;
  /** 所选服务器时区的星期，0 为周日。 */
  weekday: number = 0;
  /** M/D 文案 */
  monthDay: string = '';
  isToday: boolean = false;
  allMaterialsOpen: boolean = false;
  /** 当日生日角色 */
  birthdays: CalendarBirthday[] = [];
  /** 当日可刷天赋书 */
  talentMats: CalendarWeekMaterial[] = [];
  /** 当日可刷武器材料 */
  weaponMats: CalendarWeekMaterial[] = [];
}

/** 周视图数据 */
export class CalendarWeekData {
  days: CalendarWeekDay[] = [];
  offsetHours: number = GameCalendarRules.DEFAULT_OFFSET_HOURS;
  globalOffsetHours: number = GameCalendarRules.DEFAULT_OFFSET_HOURS;
  projectId: number = 0;
  projectName: string = '';
}

export class CalendarWeekService {
  static getGlobalOffset(): number {
    return GameCalendarRules.normalizeOffset(PreferencesStore.getNumber(GLOBAL_OFFSET_KEY,
      GameCalendarRules.DEFAULT_OFFSET_HOURS));
  }

  static setGlobalOffset(offsetHours: number): void {
    PreferencesStore.setNumber(GLOBAL_OFFSET_KEY, GameCalendarRules.normalizeOffset(offsetHours));
  }

  /** 显式设置优先，否则按应用语言或系统地区取默认值。0 为周日。 */
  static firstDayOfWeek(): number {
    const saved: number = PreferencesStore.getNumber(FIRST_DAY_OF_WEEK_KEY, -1);
    if (CalendarWeekService.isWeekday(saved)) { return saved; }

    try {
      const locale: string = AppLocaleService.requested();
      // Calendar 的周日为 1，周历沿用 Date.getUTCDay() 的周日为 0。
      const weekday: number = i18n.getCalendar(locale, 'gregory').getFirstDayOfWeek() - 1;
      if (CalendarWeekService.isWeekday(weekday)) { return weekday; }
    } catch (_) {}
    return 1;
  }

  static setFirstDayOfWeek(weekday: number): void {
    if (CalendarWeekService.isWeekday(weekday)) {
      PreferencesStore.setNumber(FIRST_DAY_OF_WEEK_KEY, weekday);
    }
  }

  private static isWeekday(weekday: number): boolean {
    return Number.isInteger(weekday) && weekday >= 0 && weekday <= 6;
  }

  private static async currentProject(): Promise<CultivateProject | undefined> {
    try {
      const projects: CultivateProject[] = await CultivationRepo.getProjects();
      const selectedId: number = PreferencesStore.getNumber('cultivation.current_project_id', 0);
      return projects.find((project: CultivateProject): boolean => project.id === selectedId) ?? projects[0];
    } catch (e) {
      return undefined;
    }
  }

  /** 逐条匹配同系列的轮换材料，标记该系列及条目所对应的角色或武器。 */
  private static async loadHighlight(project: CultivateProject | undefined): Promise<Map<number, Set<number>>> {
    const highlighted: Map<number, Set<number>> = new Map<number, Set<number>>();
    if (project === undefined) { return highlighted; }
    let entries: CultivateEntry[];
    try {
      entries = await CultivationRepo.getEntries(project.id);
    } catch (e) {
      return highlighted;
    }
    for (const entry of entries) {
      const families: Set<RotationalMaterialSeries> = new Set<RotationalMaterialSeries>();
      for (const item of entry.items) {
        const match: RotationalMaterialSeries | undefined = GameCalendarRules.materialSeries(item.itemId);
        if (match !== undefined) { families.add(match); }
      }
      if (families.size !== 1) { continue; }
      for (const family of families) {
        const ids: Set<number> = highlighted.get(family.highestId) ?? new Set<number>();
        ids.add(entry.avatarId);
        highlighted.set(family.highestId, ids);
      }
    }
    return highlighted;
  }

  private static addConsumer(material: CalendarWeekMaterial | undefined, id: number, name: string, icon: string,
    quality: number, category: string, highlighted: Map<number, Set<number>>): void {
    if (material === undefined) { return; }
    const consumer: CalendarMaterialConsumer = new CalendarMaterialConsumer();
    consumer.id = id;
    consumer.name = name;
    consumer.icon = icon;
    consumer.category = category;
    consumer.quality = quality;
    consumer.highlighted = highlighted.get(material.id)?.has(id) ?? false;
    material.consumers.push(consumer);
  }

  private static buildMaterials(metadata: Map<number, MetaMaterial>, avatars: WikiAvatarMeta[], weapons: WikiWeaponMeta[],
    highlighted: Map<number, Set<number>>): CalendarWeekMaterial[] {
    const materials: Map<number, CalendarWeekMaterial> = new Map<number, CalendarWeekMaterial>();
    for (const series of ROTATIONAL_SERIES) {
      const meta: MetaMaterial | undefined = metadata.get(series.highestId);
      if (meta === undefined) { continue; }
      const material: CalendarWeekMaterial = new CalendarWeekMaterial();
      material.id = series.highestId;
      material.name = meta.n;
      material.icon = meta.i;
      material.rank = meta.r;
      material.isTalent = series.isTalent();
      material.dayPair = series.dayPair;
      material.highlighted = highlighted.has(material.id);
      materials.set(material.id, material);
    }
    // Windows 使用角色 cultivationItems[4]、武器 cultivationItems[0] 查找最高阶素材。
    for (const avatar of avatars) {
      CalendarWeekService.addConsumer(materials.get(avatar.cultivationItems[4]), avatar.id, avatar.name, avatar.icon,
        avatar.quality, 'AvatarIcon', highlighted);
    }
    for (const weapon of weapons) {
      CalendarWeekService.addConsumer(materials.get(weapon.cultivationItems[0]), weapon.id, weapon.name, weapon.icon,
        weapon.rankLevel, 'EquipIcon', highlighted);
    }
    const list: CalendarWeekMaterial[] = Array.from(materials.values());
    for (const material of list) {
      material.consumers.sort((a: CalendarMaterialConsumer, b: CalendarMaterialConsumer): number => b.quality - a.quality);
    }
    return list;
  }

  private static buildBirthdays(avatars: WikiAvatarMeta[]): Map<string, CalendarBirthday[]> {
    const birthdays: Map<string, CalendarBirthday[]> = new Map<string, CalendarBirthday[]>();
    for (const avatar of avatars) {
      const parts: string[] = avatar.birth.split('/');
      if (parts.length !== 2) { continue; }
      const month: number = Number(parts[0]);
      const day: number = Number(parts[1]);
      if (!(month >= 1 && month <= 12 && day >= 1 && day <= 31)) { continue; }
      const key: string = `${month}/${day}`;
      const entries: CalendarBirthday[] = birthdays.get(key) ?? [];
      const birthday: CalendarBirthday = new CalendarBirthday();
      birthday.name = avatar.name;
      birthday.icon = avatar.icon;
      entries.push(birthday);
      birthdays.set(key, entries);
    }
    return birthdays;
  }

  /** 构建包含服务器今日的周视图，材料、生日及养成高亮可离线读取。 */
  static async loadWeek(nowMs: number = Date.now()): Promise<CalendarWeekData> {
    const project: CultivateProject | undefined = await CalendarWeekService.currentProject();
    const data: CalendarWeekData = new CalendarWeekData();
    data.globalOffsetHours = CalendarWeekService.getGlobalOffset();
    data.offsetHours = data.globalOffsetHours;
    if (project !== undefined) {
      data.projectId = project.id;
      data.projectName = project.name;
      data.offsetHours = GameCalendarRules.normalizeOffset(project.serverTimeZoneOffset);
    }
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    const materials: Map<number, MetaMaterial> = await WikiMetaService.getMaterials();
    const events: GachaEventMeta[] = await WikiMetaService.getGachaEvents();
    const highlighted: Map<number, Set<number>> = await CalendarWeekService.loadHighlight(project);
    const rotation: CalendarWeekMaterial[] = CalendarWeekService.buildMaterials(materials, avatars, weapons, highlighted);
    const birthdays: Map<string, CalendarBirthday[]> = CalendarWeekService.buildBirthdays(avatars);
    const first: number = CalendarWeekService.firstDayOfWeek();
    const today: number = GameCalendarRules.serverDay(nowMs, data.offsetHours);
    const dow: number = new Date(today * GameCalendarRules.DAY_MS).getUTCDay();
    const start: number = today - (dow - first + 7) % 7;
    for (let i = 0; i < 7; i++) {
      const ordinal: number = start + i;
      const d: Date = new Date(ordinal * GameCalendarRules.DAY_MS);
      const weekday: number = d.getUTCDay();
      const day: CalendarWeekDay = new CalendarWeekDay();
      day.dateMs = GameCalendarRules.startOfServerDay(ordinal, data.offsetHours);
      day.weekday = weekday;
      day.dayInMonth = d.getUTCDate();
      day.monthDay = `${d.getUTCMonth() + 1}/${day.dayInMonth}`;
      day.isToday = ordinal === today;
      day.allMaterialsOpen = weekday === 0 || GameCalendarRules.allMaterialsOpen(day.dateMs, events, data.offsetHours);
      if (!day.allMaterialsOpen) {
        const pair: number = weekday <= 3 ? weekday : weekday - 3;
        for (const mat of rotation) {
          if (mat.dayPair !== pair) { continue; }
          if (mat.isTalent) {
            day.talentMats.push(mat);
          } else {
            day.weaponMats.push(mat);
          }
        }
      }
      day.birthdays = birthdays.get(day.monthDay) ?? [];
      data.days.push(day);
    }
    return data;
  }
}
