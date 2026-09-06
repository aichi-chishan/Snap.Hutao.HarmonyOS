/**
 * WikiMetaService.ets
 * 本地图鉴元数据（rawfile/metadata/*.json，提取自 Snap.Metadata 公开仓库，无运行时云依赖）：
 * 角色 118（技能/命座/养成材料/语音/故事/CV）、武器 246（精炼/材料）、怪物 560、被引用材料 498、曲线表。
 */
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';
import { Curve3 } from './BaseValueService';

const TAG: string = 'WikiMetaService';

/** 技能/命座条目 */
export class MetaSkill {
  n: string = '';
  d: string = '';
  i: string = '';
  /** A普攻 E战技 Q爆发 P被动 X其他 */
  k: string = '';
}

/** 语音/故事条目 */
export class MetaText {
  t: string = '';
  c: string = '';
}

/** 角色元数据 */
export class WikiAvatarMeta {
  id: number = 0;
  name: string = '';
  icon: string = '';
  sideIcon: string = '';
  quality: number = 0;
  weapon: number = 0;
  /** 基础属性曲线（数值滑条卡；1 级基础值 + 突破组 + 成长曲线） */
  hpBase: number = 0;
  attackBase: number = 0;
  defenseBase: number = 0;
  promoteId: number = 0;
  growCurves: Curve3[] = [];
  /** 名片（我的角色详情专属背景） */
  nameCardIcon: string = '';
  nameCardPic: string = '';
  sort: number = 0;
  begin: string = '';
  title: string = '';
  detail: string = '';
  native: string = '';
  birth: string = '';
  constellation: string = '';
  vision: string = '';
  cv: string[] = [];
  skills: MetaSkill[] = [];
  talents: MetaSkill[] = [];
  cultivationItems: number[] = [];
  cook: Record<string, number> | null = null;
  fetters: MetaText[] = [];
  stories: MetaText[] = [];
}

/** 武器元数据 */
export class WikiWeaponMeta {
  id: number = 0;
  name: string = '';
  icon: string = '';
  awakenIcon: string = '';
  weaponType: number = 0;
  rankLevel: number = 0;
  sort: number = 0;
  description: string = '';
  affixName: string = '';
  affixDesc: string[] = [];
  cultivationItems: number[] = [];
}

/** 怪物元数据 */
export class WikiMonsterMeta {
  id: number = 0;
  describeId: number = 0;
  name: string = '';
  title: string = '';
  icon: string = '';
  type: number = 0;
  arkhe: number = 0;
  description: string = '';
  affixes: string[] = [];
  drops: number[] = [];
  hpBase: number = 0;
  attackBase: number = 0;
  defenseBase: number = 0;
  /** 基础属性成长曲线（数值滑条卡） */
  growCurves: Curve3[] = [];
  /** 8 项抗性(%): 火/水/草/雷/冰/岩/风/物理 */
  subHurts: number[] = [];
}

/** 材料条目 */
export class MetaMaterial {
  n: string = '';
  i: string = '';
  r: number = 0;
}

export class WikiMetaService {
  private static avatars: WikiAvatarMeta[] | undefined = undefined;
  private static weapons: WikiWeaponMeta[] | undefined = undefined;
  private static monsters: WikiMonsterMeta[] | undefined = undefined;
  private static materials: Map<number, MetaMaterial> | undefined = undefined;

  private static async readRawJson(name: string): Promise<Record<string, Object> | Object[]> {
    const rm = AppContextProvider.getResourceManager();
    const raw: Uint8Array = await rm.getRawFileContent(`metadata/${name}`);
    return JSON.parse(util.TextDecoder.create('utf-8').decodeToString(raw)) as Record<string, Object> | Object[];
  }

  /** 角色列表（按 Sort 降序，新角色在前） */
  static async getAvatars(): Promise<WikiAvatarMeta[]> {
    if (WikiMetaService.avatars !== undefined) {
      return WikiMetaService.avatars;
    }
    try {
      const arr = await WikiMetaService.readRawJson('avatar_meta.json') as Object[];
      const list: WikiAvatarMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const a: WikiAvatarMeta = new WikiAvatarMeta();
        a.id = Number(o['id'] ?? 0);
        a.name = String(o['name'] ?? '');
        a.icon = String(o['icon'] ?? '');
        a.sideIcon = String(o['sideIcon'] ?? '');
        a.quality = Number(o['quality'] ?? 0);
        a.weapon = Number(o['weapon'] ?? 0);
        a.sort = Number(o['sort'] ?? 0);
        a.hpBase = Number(o['hpBase'] ?? 0);
        a.attackBase = Number(o['attackBase'] ?? 0);
        a.defenseBase = Number(o['defenseBase'] ?? 0);
        a.promoteId = Number(o['promoteId'] ?? 0);
        a.nameCardIcon = String(o['nameCardIcon'] ?? '');
        a.nameCardPic = String(o['nameCardPic'] ?? '');
        const gcs = (o['growCurves'] as Object[]) ?? [];
        for (const g of gcs) {
          const go = g as Record<string, Object>;
          const c: Curve3 = new Curve3();
          c.i = Number(go['i'] ?? 0);
          c.t = Number(go['t'] ?? 0);
          c.v = Number(go['v'] ?? 0);
          a.growCurves.push(c);
        }
        a.begin = String(o['begin'] ?? '');
        a.title = String(o['title'] ?? '');
        a.detail = WikiMetaService.cleanText(String(o['detail'] ?? ''));
        a.native = String(o['native'] ?? '');
        a.birth = String(o['birth'] ?? '');
        a.constellation = String(o['constellation'] ?? '');
        a.vision = String(o['vision'] ?? '');
        const cv = (o['cv'] as Object[]) ?? [];
        for (const c of cv) {
          a.cv.push(String(c));
        }
        a.skills = WikiMetaService.readSkills(o['skills']);
        a.talents = WikiMetaService.readSkills(o['talents']);
        const items = (o['cultivationItems'] as Object[]) ?? [];
        for (const it of items) {
          a.cultivationItems.push(Number(it));
        }
        a.cook = (o['cook'] as Record<string, number>) ?? null;
        a.fetters = WikiMetaService.readTexts(o['fetters']);
        a.stories = WikiMetaService.readTexts(o['stories']);
        list.push(a);
      }
      WikiMetaService.avatars = list;
      Logger.info(TAG, `avatars loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load avatars fail: ${(e as Error).message}`);
      WikiMetaService.avatars = [];
    }
    return WikiMetaService.avatars;
  }

  private static readSkills(raw: Object | undefined): MetaSkill[] {
    const list: MetaSkill[] = [];
    const arr = (raw as Object[]) ?? [];
    for (const r of arr) {
      const o: Record<string, Object> = r as Record<string, Object>;
      const s: MetaSkill = new MetaSkill();
      s.n = String(o['n'] ?? '');
      s.d = WikiMetaService.cleanText(String(o['d'] ?? ''));
      s.i = String(o['i'] ?? '');
      s.k = String(o['k'] ?? '');
      list.push(s);
    }
    return list;
  }

  /** 清洗米哈游富文本标记：<color=#>…</color> → 内容；{LINK#id}…(/LINK) → 内容；保留其余 */
  static cleanText(t: string): string {
    if (t.length === 0) {
      return t;
    }
    let s: string = t;
    // <color=#XXXXXX> 与 </color> → 剥离标签保留内容
    s = s.replace(/<color[^>]*>/g, '');
    s = s.replace(/<\/color>/g, '');
    // {LINK#xxx} 与 (/LINK) → 剥离标记保留内容
    s = s.replace(/\{LINK#[^}]*\}/g, '');
    s = s.replace(/\(\/LINK\)/g, '');
    // 保留 {param} 占位符（由 UI 按需替换）；剥离多余空白首尾
    return s.trim();
  }

  private static readTexts(raw: Object | undefined): MetaText[] {
    const list: MetaText[] = [];
    const arr = (raw as Object[]) ?? [];
    for (const r of arr) {
      const o: Record<string, Object> = r as Record<string, Object>;
      const t: MetaText = new MetaText();
      t.t = String(o['t'] ?? '');
      t.c = String(o['c'] ?? '');
      list.push(t);
    }
    return list;
  }

  /** 武器列表 */
  static async getWeapons(): Promise<WikiWeaponMeta[]> {
    if (WikiMetaService.weapons !== undefined) {
      return WikiMetaService.weapons;
    }
    try {
      const arr = await WikiMetaService.readRawJson('weapon_meta.json') as Object[];
      const list: WikiWeaponMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const w: WikiWeaponMeta = new WikiWeaponMeta();
        w.id = Number(o['id'] ?? 0);
        w.name = String(o['name'] ?? '');
        w.icon = String(o['icon'] ?? '');
        w.awakenIcon = String(o['awakenIcon'] ?? '');
        w.weaponType = Number(o['weaponType'] ?? 0);
        w.rankLevel = Number(o['rankLevel'] ?? 0);
        w.sort = Number(o['sort'] ?? 0);
        w.description = String(o['description'] ?? '');
        w.affixName = String(o['affixName'] ?? '');
        const affixes = (o['affixDesc'] as Object[]) ?? [];
        for (const ad of affixes) {
          w.affixDesc.push(String(ad));
        }
        const items = (o['cultivationItems'] as Object[]) ?? [];
        for (const it of items) {
          w.cultivationItems.push(Number(it));
        }
        list.push(w);
      }
      WikiMetaService.weapons = list;
      Logger.info(TAG, `weapons loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load weapons fail: ${(e as Error).message}`);
      WikiMetaService.weapons = [];
    }
    return WikiMetaService.weapons;
  }

  /** 怪物列表（按 DescribeId 升序，对齐 Windows 排序） */
  static async getMonsters(): Promise<WikiMonsterMeta[]> {
    if (WikiMetaService.monsters !== undefined) {
      return WikiMetaService.monsters;
    }
    try {
      const arr = await WikiMetaService.readRawJson('monster_meta.json') as Object[];
      const list: WikiMonsterMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const m: WikiMonsterMeta = new WikiMonsterMeta();
        m.id = Number(o['id'] ?? 0);
        m.describeId = Number(o['describeId'] ?? 0);
        m.name = String(o['name'] ?? '');
        m.title = String(o['title'] ?? '');
        m.icon = String(o['icon'] ?? '');
        m.type = Number(o['type'] ?? 0);
        m.arkhe = Number(o['arkhe'] ?? 0);
        m.description = WikiMetaService.cleanText(String(o['description'] ?? ''));
        const affixes = (o['affixes'] as Object[]) ?? [];
        for (const af of affixes) {
          m.affixes.push(String(af));
        }
        const drops = (o['drops'] as Object[]) ?? [];
        for (const dr of drops) {
          m.drops.push(Number(dr));
        }
        const mgs = (o['growCurves'] as Object[]) ?? [];
        for (const g of mgs) {
          const go = g as Record<string, Object>;
          const c: Curve3 = new Curve3();
          c.i = Number(go['i'] ?? 0);
          c.t = Number(go['t'] ?? 0);
          c.v = Number(go['v'] ?? 0);
          m.growCurves.push(c);
        }
        m.hpBase = Number(o['hpBase'] ?? 0);
        m.attackBase = Number(o['attackBase'] ?? 0);
        m.defenseBase = Number(o['defenseBase'] ?? 0);
        const hurts = (o['subHurts'] as Object[]) ?? [];
        for (const h of hurts) {
          m.subHurts.push(Number(h));
        }
        list.push(m);
      }
      WikiMetaService.monsters = list;
      for (const mo of list) {
        WikiMetaService.monsterNameMap.set(mo.name, mo.icon);
      }
      const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
      for (const av of avatars) {
        if (av.nameCardPic.length > 0) {
          WikiMetaService.avatarNameCardPicMap.set(av.name, av.nameCardPic);
        }
      }
      Logger.info(TAG, `monsters loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load monsters fail: ${(e as Error).message}`);
      WikiMetaService.monsters = [];
    }
    return WikiMetaService.monsters;
  }

  /** 材料表（id → 名称/图标/品质） */
  static async getMaterials(): Promise<Map<number, MetaMaterial>> {
    if (WikiMetaService.materials !== undefined) {
      return WikiMetaService.materials;
    }
    try {
      const root = await WikiMetaService.readRawJson('material_meta.json') as Record<string, Object>;
      const map: Map<number, MetaMaterial> = new Map();
      const keys = Object.keys(root);
      for (const key of keys) {
        const o: Record<string, Object> = root[key] as Record<string, Object>;
        const m: MetaMaterial = new MetaMaterial();
        m.n = String(o['n'] ?? '');
        m.i = String(o['i'] ?? '');
        m.r = Number(o['r'] ?? 0);
        map.set(Number(key), m);
      }
      WikiMetaService.materials = map;
      Logger.info(TAG, `materials loaded: ${map.size}`);
    } catch (e) {
      Logger.warn(TAG, `load materials fail: ${(e as Error).message}`);
      WikiMetaService.materials = new Map();
    }
    return WikiMetaService.materials;
  }

  /** 武器类型数字 → 中文 */
  static weaponTypeName(t: number): string {
    switch (t) {
      case 1: return '单手剑';
      case 2: return '双手剑';
      case 3: return '长柄武器';
      case 4: return '法器';
      case 5: return '弓';
      default: return `类型${t}`;
    }
  }

  // ============ id → 图标名映射（祈愿/深渊等页面头像真图标）============

  private static avatarIconMap: Map<number, string> = new Map();
  private static avatarSideIconMap: Map<number, string> = new Map();
  private static weaponIconMap: Map<number, string> = new Map();
  private static avatarNameMap: Map<string, string> = new Map();
  private static weaponNameMap: Map<string, string> = new Map();
  private static monsterNameMap: Map<string, string> = new Map();
  private static avatarNameCardPicMap: Map<string, string> = new Map();

  /** 预载 id→icon 映射（轻量，页面 aboutToAppear 调用一次） */
  static async ensureIconMaps(): Promise<void> {
    if (WikiMetaService.avatarIconMap.size > 0) {
      return;
    }
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    for (const a of avatars) {
      WikiMetaService.avatarIconMap.set(a.id, a.icon);
      WikiMetaService.avatarSideIconMap.set(a.id, a.sideIcon);
      WikiMetaService.avatarNameMap.set(a.name, a.icon);
    }
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    for (const w of weapons) {
      WikiMetaService.weaponIconMap.set(w.id, w.icon);
      WikiMetaService.weaponNameMap.set(w.name, w.icon);
    }
    Logger.info(TAG, `icon maps: ${WikiMetaService.avatarIconMap.size} avatars, ${WikiMetaService.weaponIconMap.size} weapons`);
  }

  /** 角色 item_id(avatarId) → 头像图标名（未命中返回空）。
   *  兼容 item_id 风格（如 1015=七七）与 Enka avatarId 风格（10000035）：低位数字 id + 1e7 换算 */
  static iconOfAvatar(id: number): string {
    let n: string | undefined = WikiMetaService.avatarIconMap.get(id);
    if (n === undefined && id > 0 && id < 1000000) {
      n = WikiMetaService.avatarIconMap.get(id + 10000000);
    }
    if (n === undefined && id > 1000) {
      n = WikiMetaService.avatarIconMap.get(id - 10000000);
    }
    return n !== undefined ? n : '';
  }

  /** 角色 item_id(avatarId) → 侧脸图标名（未命中返回空；幽境/剧诗最强一击等用） */
  static sideIconOfAvatar(id: number): string {
    const n: string | undefined = WikiMetaService.avatarSideIconMap.get(id);
    return n !== undefined ? n : '';
  }

  /** 武器 item_id → 图标名（未命中返回空） */
  static iconOfWeapon(id: number): string {
    const n: string | undefined = WikiMetaService.weaponIconMap.get(id);
    return n !== undefined ? n : '';
  }

  /** 角色中文名 → 头像图标名（未命中返回空；容忍全角空格/首尾空白） */
  static iconOfAvatarName(name: string): string {
    if (name.length === 0) {
      return '';
    }
    let n: string | undefined = WikiMetaService.avatarNameMap.get(name);
    if (n === undefined) {
      // 尝试去除空格（部分接口返回" 七七"或"七七 "）
      n = WikiMetaService.avatarNameMap.get(name.trim());
      if (n === undefined) {
        const trimmed: string = name.replace(/\s+/g, '');
        for (const key of WikiMetaService.avatarNameMap.keys()) {
          if (key.replace(/\s+/g, '') === trimmed) {
            n = WikiMetaService.avatarNameMap.get(key);
            break;
          }
        }
      }
    }
    return n !== undefined ? n : '';
  }

  /** 武器中文名 → 图标名（未命中返回空） */
  static iconOfWeaponName(name: string): string {
    const n: string | undefined = WikiMetaService.weaponNameMap.get(name);
    return n !== undefined ? n : '';
  }

  /** 角色名 → 名片大图名（NameCardPic，我的角色专属背景；未命中返回空） */
  static nameCardPicOf(avatarName: string): string {
    const n: string | undefined = WikiMetaService.avatarNameCardPicMap.get(avatarName);
    return n !== undefined ? n : '';
  }

  /** 角色名 → 天赋/技能列表（我的角色详情天赋区用；未命中返回空数组） */
  static skillsOfAvatar(name: string): MetaSkill[] {
    // 遍历缓存的角色列表（getAvatars 已缓存，不重复解析）
    const avatars = WikiMetaService.avatars;
    if (avatars !== undefined) {
      for (const a of avatars) {
        if (a.name === name) {
          return a.skills;
        }
      }
    }
    return [];
  }

  /** 怪物中文名 → MonsterIcon 图标名（未命中返回空；剧诗/幽境敌人头像用） */
  static iconOfMonsterName(name: string): string {
    const n: string | undefined = WikiMetaService.monsterNameMap.get(name);
    if (n !== undefined) {
      return n;
    }
    // API 名可能带词缀后缀或截断：前缀互含兜底
    let found: string = '';
    WikiMetaService.monsterNameMap.forEach((icon: string, key: string) => {
      if (found.length === 0 && name.length > 0 && (key.startsWith(name) || name.startsWith(key))) {
        found = icon;
      }
    });
    return found;
  }

  /** 抽卡记录条目 → 图标名（角色走 AvatarIcon、武器走 EquipIcon；未命中返回空） */
  static iconOfItemName(name: string, itemType: string): string {
    if (itemType === '武器') {
      const w: string | undefined = WikiMetaService.weaponNameMap.get(name);
      return w ?? '';
    }
    const a: string | undefined = WikiMetaService.avatarNameMap.get(name);
    return a ?? '';
  }

  /** 元素英文 → 中文 */
  static elementName(e: string): string {
    switch (e) {
      case 'Pyro': return '火';
      case 'Hydro': return '水';
      case 'Anemo': return '风';
      case 'Electro': return '雷';
      case 'Dendro': return '草';
      case 'Cryo': return '冰';
      case 'Geo': return '岩';
      default: return e;
    }
  }
}
