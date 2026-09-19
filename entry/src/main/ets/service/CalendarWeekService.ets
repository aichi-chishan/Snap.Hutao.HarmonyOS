/**
 * CalendarWeekService.ets
 * 周历数据（对齐 Windows CalendarViewModel + MaterialIds）：
 * - 天赋书/武器突破材料轮换（周一四 / 二五 / 三六，取各系列最高阶 id，对齐 Windows RotationalMaterialIdEntry）
 * - 角色生日（avatar_meta.birth "M/D"，按月日归组，对齐 Windows AvatarBirthdays）
 * - 生成包含今日的周视图（周一起始），周日密境全开不列材料（对齐 Windows dailyMaterials 无周日键）
 * - 本地养成计划联动高亮（对齐 Windows InitializeHighlightItems：当前计划命中的系列/角色全高亮）
 */
import { WikiMetaService, MetaMaterial, WikiAvatarMeta, WikiWeaponMeta } from './WikiMetaService';
import { CultivationRepo, CultivateProject, CultivateEntry } from '../data/repo/CultivationRepo';

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
  // 天赋书（1043xx，3 阶）
  series(1, 104303, '「自由」'), series(1, 104312, '「繁荣」'), series(1, 104322, '「浮世」'),
  series(1, 104331, '「诤言」'), series(1, 104340, '「公平」'), series(1, 104349, '「角逐」'),
  series(1, 104358, '「月光」'),
  series(2, 104306, '「抗争」'), series(2, 104315, '「勤劳」'), series(2, 104325, '「风雅」'),
  series(2, 104334, '「巧思」'), series(2, 104343, '「正义」'), series(2, 104352, '「焚燔」'),
  series(2, 104361, '「乐园」'),
  series(3, 104309, '「诗文」'), series(3, 104318, '「黄金」'), series(3, 104328, '「天光」'),
  series(3, 104337, '「笃行」'), series(3, 104346, '「秩序」'), series(3, 104355, '「纷争」'),
  series(3, 104364, '「浪迹」'),
  // 武器突破材料（114xxx，4 阶）
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
  /** 当前养成计划命中（高亮底色，对齐 Windows material.Highlight） */
  highlighted: boolean = false;
  /** 需要该材料的角色/武器（详情弹层展示） */
  consumers: CalendarMaterialConsumer[] = [];
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
  /** 当日可刷天赋书 */
  talentMats: CalendarWeekMaterial[] = [];
  /** 当日可刷武器材料 */
  weaponMats: CalendarWeekMaterial[] = [];
}

/** 周视图数据 */
export class CalendarWeekData {
  days: CalendarWeekDay[] = [];
  /** 本周包含生日角色的日期（月日 → true，供周条做角标） */
  birthdayFlags: boolean[] = [];
}

/** 本地养成计划高亮集合（对齐 Windows CultivateEntryView.RotationalItemIds 聚合） */
class CultivateHighlight {
  /** 计划所需全部材料 id（含低阶；系列族命中即高亮） */
  materialIds: Set<number> = new Set<number>();
  /** 计划培养的角色/武器 id（消费者高亮，对齐 Windows view.Id） */
  avatarIds: Set<number> = new Set<number>();

  isEmpty(): boolean {
    return this.materialIds.size === 0 && this.avatarIds.size === 0;
  }
}

export class CalendarWeekService {
  private static loaded: boolean = false;
  /** 月日 → 生日角色 */
  private static birthdays: Map<string, CalendarBirthday[]> = new Map();
  /** 系列最高阶 id → 显示名（material_meta 优先，缺省用表内名） */
  private static seriesNames: Map<number, string> = new Map();
  /** 系列最高阶 id → 图标名 */
  private static seriesIcons: Map<number, string> = new Map();
  /** 系列最高阶 id → 品质（material_meta.r） */
  private static seriesRanks: Map<number, number> = new Map();
  /** 系列最高阶 id → 消费者（角色/武器，品质降序，对齐 Windows MaterialItems 查询） */
  private static seriesConsumers: Map<number, CalendarMaterialConsumer[]> = new Map();
  /** 本地养成计划高亮集（加载失败为空集） */
  private static highlight: CultivateHighlight = new CultivateHighlight();

  /** 系列图标名（MetaIcon ItemIcon 类目；最高阶图标已随包内置） */
  static iconOf(id: number): string {
    return CalendarWeekService.seriesIcons.get(id) ?? `UI_ItemIcon_${id}`;
  }

  /** 惰性装载：生日表 + 材料名表 + 消费者表 */
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
      CalendarWeekService.seriesRanks.set(s.highestId, m !== undefined ? m.r : 0);
    }
    await CalendarWeekService.buildConsumers();
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
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

  /**
   * 构建系列 → 消费者（角色 cultivationItems[4]=天赋书，武器 cultivationItems[0]=突破材料；
   * 品质降序，对齐 Windows GetMaterialItemLookup + OrderByDescending(Quality)）。
   */
  private static async buildConsumers(): Promise<void> {
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    const groups: Map<number, CalendarMaterialConsumer[]> = new Map();
    const add = (matId: number, c: CalendarMaterialConsumer): void => {
      let list: CalendarMaterialConsumer[] | undefined = groups.get(matId);
      if (list === undefined) {
        list = [];
        groups.set(matId, list);
      }
      list.push(c);
    };
    for (const a of avatars) {
      if (a.cultivationItems.length < 5) {
        continue;
      }
      const c: CalendarMaterialConsumer = new CalendarMaterialConsumer();
      c.id = a.id;
      c.name = a.name;
      c.category = 'AvatarIcon';
      c.icon = a.icon;
      c.quality = a.quality;
      add(a.cultivationItems[4], c);
    }
    for (const w of weapons) {
      if (w.cultivationItems.length < 1) {
        continue;
      }
      const c: CalendarMaterialConsumer = new CalendarMaterialConsumer();
      c.id = w.id;
      c.name = w.name;
      c.category = 'EquipIcon';
      c.icon = w.icon;
      c.quality = w.rankLevel;
      add(w.cultivationItems[0], c);
    }
    groups.forEach((list: CalendarMaterialConsumer[]) => {
      list.sort((x: CalendarMaterialConsumer, y: CalendarMaterialConsumer) => y.quality - x.quality);
    });
    CalendarWeekService.seriesConsumers = groups;
  }

  /** 读取本地养成计划材料/角色集合（逐项目聚合；失败静默为空集，不阻塞周历） */
  private static async loadHighlight(): Promise<void> {
    const result: CultivateHighlight = new CultivateHighlight();
    try {
      const projects: CultivateProject[] = await CultivationRepo.getProjects();
      for (const p of projects) {
        const entries: CultivateEntry[] = await CultivationRepo.getEntries(p.id);
        for (const e of entries) {
          if (e.avatarId > 0) {
            result.avatarIds.add(e.avatarId);
          }
          for (const it of e.items) {
            if (it.itemId > 0) {
              result.materialIds.add(it.itemId);
            }
          }
        }
      }
    } catch (e) {
      // 本地库异常时周历仍可展示，仅无高亮
    }
    CalendarWeekService.highlight = result;
  }

  /** 系列族（该系列全部阶 id）：天赋书 3 阶 / 武器材料 4 阶 */
  private static familyIds(highestId: number): number[] {
    const tiers: number = highestId >= 114000 && highestId < 115000 ? 4 : 3;
    const ids: number[] = [];
    for (let i = tiers - 1; i >= 0; i--) {
      ids.push(highestId - i);
    }
    return ids;
  }

  /** 系列是否被当前养成计划命中（族内任一阶在所需材料集合即命中） */
  private static isHighlighted(highestId: number): boolean {
    if (CalendarWeekService.highlight.materialIds.size === 0) {
      return false;
    }
    const family: number[] = CalendarWeekService.familyIds(highestId);
    for (const id of family) {
      if (CalendarWeekService.highlight.materialIds.has(id)) {
        return true;
      }
    }
    return false;
  }

  /** 组装系列材料条目（含消费者高亮标记，对齐 Windows InitializeHighlightItems） */
  private static buildMaterial(s: RotationalSeries): CalendarWeekMaterial {
    const m: CalendarWeekMaterial = new CalendarWeekMaterial();
    m.id = s.highestId;
    m.name = CalendarWeekService.seriesNames.get(s.highestId) ?? s.fallbackName;
    m.icon = CalendarWeekService.seriesIcons.get(s.highestId) ?? `UI_ItemIcon_${s.highestId}`;
    m.rank = CalendarWeekService.seriesRanks.get(s.highestId) ?? 0;
    m.isTalent = s.highestId >= 104300 && s.highestId < 114000;
    m.highlighted = CalendarWeekService.isHighlighted(s.highestId);
    const consumers: CalendarMaterialConsumer[] =
      CalendarWeekService.seriesConsumers.get(s.highestId) ?? [];
    for (const c of consumers) {
      c.highlighted = CalendarWeekService.highlight.avatarIds.has(c.id);
      m.consumers.push(c);
    }
    return m;
  }

  /** 构建包含今日的周视图（周一起始，7 天；材料/生日/本地养成高亮不依赖登录） */
  static async loadWeek(): Promise<CalendarWeekData> {
    await CalendarWeekService.ensureLoaded();
    // 养成计划每次进入都重新聚合（本地库查询代价小，新增计划后回日历即时生效）
    await CalendarWeekService.loadHighlight();
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
          const mat: CalendarWeekMaterial = CalendarWeekService.buildMaterial(s);
          if (mat.isTalent) {
            day.talentMats.push(mat);
          } else {
            day.weaponMats.push(mat);
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
