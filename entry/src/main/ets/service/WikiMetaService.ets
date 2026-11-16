/**
 * WikiMetaService.ets
 * 本地图鉴元数据（rawfile/metadata/*.json，提取自 Snap.Metadata 公开仓库，无运行时云依赖）：
 * 角色 118（技能/命座/养成材料/语音/故事/CV）、武器 246（精炼/材料）、怪物 560、被引用材料 498、曲线表。
 */
import { GameDataService } from './GameDataService';
import { LocalizedGameDataService } from './LocalizedGameDataService';
import { GameTextTokens } from '../model/GameTextCatalog';
import { Logger } from '../common/Logger';
import { Curve3 } from './BaseValueService';

const TAG: string = 'WikiMetaService';

/** 技能/命座条目 */
export class MetaSkill {
  n: string = '';
  canonicalName: string = '';
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
  /** Original Chinese name for saved records, official CN APIs and external links. */
  canonicalName: string = '';
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
  association: number = 0;
  birth: string = '';
  birthText: string = '';
  constellation: string = '';
  vision: string = '';
  visionName: string = '';
  cv: string[] = [];
  skills: MetaSkill[] = [];
  talents: MetaSkill[] = [];
  cultivationItems: number[] = [];
  cook: Record<string, number> | null = null;
  fetters: MetaText[] = [];
  stories: MetaText[] = [];
  /** 体型（BodyType：0 未知/1 少年/2 少女/3 成女/4 成男/5 萝莉；旧元数据缺省为 0） */
  body: number = 0;
  /** 服装（默认款在前；默认款无 frontIcon，用默认立绘呈现） */
  costumes: AvatarCostumeMeta[] = [];
}

/** 角色服装（对齐 Snap.Metadata Avatar.Costumes） */
export class AvatarCostumeMeta {
  id: number = 0;
  name: string = '';
  canonicalName: string = '';
  description: string = '';
  isDefault: boolean = false;
  /** 皮肤正面图标名（UI_AvatarIcon_XxxCostumeYyy；默认款为空串） */
  frontIcon: string = '';
}

/** 武器元数据 */
export class WikiWeaponMeta {
  id: number = 0;
  name: string = '';
  canonicalName: string = '';
  icon: string = '';
  awakenIcon: string = '';
  weaponType: number = 0;
  secondaryProperty: number = 0;
  rankLevel: number = 0;
  promoteId: number = 0;
  growCurves: Curve3[] = [];
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
  canonicalName: string = '';
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
  /** 8 项抗性比例，供视图按火/水/草/雷/冰/岩/风/物理渲染。 */
  subHurts: number[] = [];
}

/** 材料条目 */
export class MetaMaterial {
  n: string = '';
  canonicalName: string = '';
  i: string = '';
  r: number = 0;
}

/** 名片条目（对齐 Snap.Metadata Namecard；Picture 与 avatar_meta.nameCardPic 同名） */
export class NameCardMeta {
  name: string = '';
  canonicalName: string = '';
  description: string = '';
  icon: string = '';
  picture: string = '';
}

/** 祈愿卡池期次（对齐 Snap.Metadata GachaEvent，时间已转 epoch ms） */
export class GachaEventMeta {
  name: string = '';
  canonicalName: string = '';
  version: string = '';
  order: number = 0;
  /** 起始 epoch ms */
  from: number = 0;
  /** 结束 epoch ms */
  to: number = 0;
  /** 卡池类型（301 角色 / 400 角色二 UP / 302 武器 / 500 集录） */
  type: number = 0;
  /** 卡池横幅图 URL（对齐 Windows HistoryWish.BannerImage；旧数据无此字段为空串） */
  banner: string = '';
  upOrange: number[] = [];
  upPurple: number[] = [];
}

/** 千星奇域（颂愿）专属物品（对齐 Windows BeyondItem：Id/Name/Icon/Type/RankLevel） */
export class BeyondItemMeta {
  id: number = 0;
  name: string = '';
  canonicalName: string = '';
  /** 图标名（UI_ItemIcon_{id}，走 BeyondItemIcon 静态 CDN，对齐 Windows BeyondItemNameIconConverter） */
  icon: string = '';
  /** 物品内部分类 */
  type: number = 0;
  /** 品质等级 1-5 */
  rank: number = 0;
}

/** 幻想真境剧诗期次元数据（对齐 Snap.Metadata RoleCombatSchedule，时间已转 epoch ms） */
export class RoleCombatScheduleMeta {
  id: number = 0;
  begin: number = 0;
  end: number = 0;
  /** 本期限定元素（ElementType 数字，见 elementNameById） */
  elements: number[] = [];
  /** 特邀角色 */
  specialAvatars: number[] = [];
  /** 初始可选角色 */
  initialAvatars: number[] = [];
}

class WikiMetadataCache {
  locale: string;
  avatars: WikiAvatarMeta[] | undefined = undefined;
  avatarsLoading: Promise<void> | undefined = undefined;
  weapons: WikiWeaponMeta[] | undefined = undefined;
  weaponsLoading: Promise<void> | undefined = undefined;
  monsters: WikiMonsterMeta[] | undefined = undefined;
  monstersLoading: Promise<void> | undefined = undefined;
  materials: Map<number, MetaMaterial> | undefined = undefined;
  monsterDrops: Map<number, MetaMaterial> | undefined = undefined;
  nameCards: NameCardMeta[] | undefined = undefined;
  nameCardByPic: Map<string, NameCardMeta> = new Map<string, NameCardMeta>();
  gachaEvents: GachaEventMeta[] | undefined = undefined;
  roleCombatSchedules: RoleCombatScheduleMeta[] | undefined = undefined;
  beyondItems: BeyondItemMeta[] | undefined = undefined;
  beyondIconByName: Map<string, string> = new Map<string, string>();
  beyondNameById: Map<number, string> = new Map<number, string>();
  beyondIconById: Map<number, string> = new Map<number, string>();
  avatarIconMap: Map<number, string> = new Map<number, string>();
  avatarSideIconMap: Map<number, string> = new Map<number, string>();
  weaponIconMap: Map<number, string> = new Map<number, string>();
  avatarNameMap: Map<string, string> = new Map<string, string>();
  weaponNameMap: Map<string, string> = new Map<string, string>();
  monsterNameMap: Map<string, string> = new Map<string, string>();
  avatarNameCardPicMap: Map<string, string> = new Map<string, string>();

  constructor(locale: string) { this.locale = locale; }
}

export class WikiMetaService {
  private static activeCache: WikiMetadataCache | undefined = undefined;

  private static cache(): WikiMetadataCache {
    const locale: string = LocalizedGameDataService.current();
    if (WikiMetaService.activeCache === undefined || WikiMetaService.activeCache.locale !== locale) {
      WikiMetaService.activeCache = new WikiMetadataCache(locale);
    }
    return WikiMetaService.activeCache;
  }

  // Snap.Metadata FetterInfo.Association, named as in the Windows localized association tokens.
  private static readonly ASSOCIATIONS: string[] = ['', '蒙德', '璃月', '', '愚人众', '稻妻', '游侠', '须弥',
    '枫丹', '纳塔', '至冬', '寰宇劫灭', '挪德卡莱', '', '魔女会', '愚人众'];
  static readonly WEAPON_TYPES: string[] = ['单手剑', '双手剑', '长柄武器', '法器', '弓'];
  static readonly BODY_TYPES: string[] = ['少年', '少女', '成女', '成男', '萝莉'];

  private static async readRawJson(name: string, locale: string): Promise<Record<string, Object> | Object[]> {
    return await LocalizedGameDataService.readJson(name, locale) as Record<string, Object> | Object[];
  }

  /** 角色列表（按 Sort 降序，新角色在前） */
  static async getAvatars(): Promise<WikiAvatarMeta[]> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.avatars === undefined) {
      if (cache.avatarsLoading === undefined) { cache.avatarsLoading = WikiMetaService.loadAvatars(cache); }
      const loading: Promise<void> = cache.avatarsLoading;
      await loading;
    }
    return cache === WikiMetaService.cache() ? cache.avatars ?? [] : WikiMetaService.getAvatars();
  }

  private static async loadAvatars(cache: WikiMetadataCache): Promise<void> {
    try {
      const arr = await WikiMetaService.readRawJson('avatar_meta.json', cache.locale) as Object[];
      const associations = JSON.parse(await GameDataService.readMetadataFile('avatar_associations.json')) as Record<string, Object>;
      const list: WikiAvatarMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const a: WikiAvatarMeta = new WikiAvatarMeta();
        a.id = Number(o['id'] ?? 0);
        a.name = String(o['name'] ?? '');
        a.canonicalName = String(o['canonicalName'] ?? a.name);
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
        a.association = Number(o['association'] ?? associations[String(a.id)] ?? 0);
        a.birth = String(o['birth'] ?? '');
        a.birthText = String(o['birthText'] ?? a.birth);
        a.constellation = String(o['constellation'] ?? '');
        a.vision = String(o['vision'] ?? '');
        a.visionName = String(o['visionName'] ?? a.vision);
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
        a.body = Number(o['body'] ?? 0);
        const costumes = (o['costumes'] as Object[]) ?? [];
        for (const c of costumes) {
          const co = c as Record<string, Object>;
          const cm: AvatarCostumeMeta = new AvatarCostumeMeta();
          cm.id = Number(co['id'] ?? 0);
          cm.name = String(co['name'] ?? '');
          cm.canonicalName = String(co['canonicalName'] ?? cm.name);
          cm.description = WikiMetaService.cleanText(String(co['description'] ?? ''));
          cm.isDefault = co['isDefault'] === true;
          cm.frontIcon = String(co['frontIcon'] ?? '');
          a.costumes.push(cm);
        }
        // 默认款在前、皮肤按 id 升序（对齐 Windows CostumesView 默认页居首）
        a.costumes.sort((x: AvatarCostumeMeta, y: AvatarCostumeMeta): number =>
          (Number(x.isDefault === true) - Number(y.isDefault === true)) * -1 || x.id - y.id);
        if (a.nameCardPic.length > 0) {
          cache.avatarNameCardPicMap.set(a.name, a.nameCardPic);
          cache.avatarNameCardPicMap.set(a.canonicalName, a.nameCardPic);
        }
        list.push(a);
      }
      cache.avatars = list;
      Logger.info(TAG, `avatars loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load avatars fail: ${(e as Error).message}`);
      cache.avatars = [];
    }
  }

  private static readSkills(raw: Object | undefined): MetaSkill[] {
    const list: MetaSkill[] = [];
    const arr = (raw as Object[]) ?? [];
    for (const r of arr) {
      const o: Record<string, Object> = r as Record<string, Object>;
      const s: MetaSkill = new MetaSkill();
      s.n = String(o['n'] ?? '');
      s.canonicalName = String(o['canonicalName'] ?? s.n);
      s.d = WikiMetaService.cleanText(String(o['d'] ?? ''));
      s.i = String(o['i'] ?? '');
      s.k = String(o['k'] ?? '');
      list.push(s);
    }
    return list;
  }

  /**
   * 清洗米哈游富文本/特殊名标记（对齐 Windows SpecialNameHandling.Handle + MiHoYoSyntaxLexer 语法，
   * 纯文本渲染无法还原斜体/内联图标/参数注入，一律剥离标记保留内容）：
   * - <color=#xxx>…</color> → 内容（Windows 按色渲染，浅色模式还会调亮）
   * - <i>…</i> 及其余 HTML 标签 → 内容
   * - {LINK#id}…{/LINK} / (/LINK) → 内容（Windows 渲染为可点 Flyout）
   * - {M#X}{F#Y} / {F#Y}{M#X} → "X/Y"（Windows 渲染为蓝/粉双色的性别代词对）
   * - {PLAYERAVATAR#SEXPRO[…HE|…SHE]} → "他/她"；{MATEAVATAR#…BOYFIRST} → "我"；{MATEAVATAR#…BOYD} → "王子/公主"
   * - {NICKNAME} / {REALNAME[ID(1)]} / {TIMEZONE} → Windows SH 当前语言的专名
   * - {LAYOUT_MOBILE#A}{LAYOUT_PC#B}{LAYOUT_PS#C} → B（Windows 取 PC 版）
   * - {SPRITE_PRESET#}/{PARAM#}/{SPELL#} 及其余 {XXX#…} → 剥离（内联元素图标/参数注入无法纯文本表达）
   * - 首字符 # 剥离（Windows Handle 对首字符为 # 的元数据描述剥离后再处理）
   */
  static cleanText(t: string): string {
    if (t.length === 0) {
      return t;
    }
    let s: string = t;
    const tokens: GameTextTokens = LocalizedGameDataService.textTokens();
    // 性别代词对（必须先于通用 {XXX#…} 剥离，否则连内容一起丢）
    s = s.replace(/\{M#([^}]*)\}\{F#([^}]*)\}/g, '$1/$2');
    s = s.replace(/\{F#([^}]*)\}\{M#([^}]*)\}/g, '$1/$2');
    // SEXPRO 与专名使用当前语言的 Windows 资源词条。
    s = s.replace(/\{PLAYERAVATAR#SEXPRO\[INFO_MALE_PRONOUN_HE\|INFO_FEMALE_PRONOUN_SHE\]\}/g, tokens.heShe);
    s = s.replace(/\{MATEAVATAR#SEXPRO\[INFO_MALE_PRONOUN_BOYFIRST\|INFO_FEMALE_PRONOUN_GIRLFIRST\]\}/g, tokens.firstPerson);
    s = s.replace(/\{MATEAVATAR#SEXPRO\[INFO_MALE_PRONOUN_BOYD\|INFO_FEMALE_PRONOUN_GIRLD\]\}/g, tokens.princePrincess);
    s = s.replace(/\{(PLAYERAVATAR|MATEAVATAR)#SEXPRO\[[^}]*\]\}/g, '');
    s = s.replace(/\{NICKNAME\}/g, tokens.nickname);
    s = s.replace(/\{REALNAME\[ID\(1\)(\|HOSTONLY\(true\))?\]\}/g, tokens.realName);
    s = s.replace(/\{TIMEZONE\}/g, tokens.timeZone);
    s = s.replace(/\{NON_BREAK_SPACE\}/g, '\u00A0');
    // 布局选择取 PC 版
    s = s.replace(/\{LAYOUT_MOBILE#(.+?)\}\{LAYOUT_PC#(.+?)\}\{LAYOUT_PS#(.+?)\}/g, '$2');
    // <color=#XXXXXX> 与 </color> → 剥离标签保留内容
    s = s.replace(/<color[^>]*>/g, '');
    s = s.replace(/<\/color>/g, '');
    // 斜体与其余 HTML 标签 → 剥离标签保留内容
    s = s.replace(/<\/?[a-z]+[^>]*>/gi, '');
    // {LINK#xxx} 与 {/LINK}（新数据闭合格式）与 (/LINK) → 剥离标记保留内容
    s = s.replace(/\{LINK#[^}]*\}/g, '');
    s = s.replace(/\{\/LINK\}/g, '');
    s = s.replace(/\(\/LINK\)/g, '');
    // 内联元素图标 / 参数注入 / 残余 {XXX#…} 标记 → 整体剥离
    s = s.replace(/\{SPRITE_PRESET#[^}]*\}/g, '');
    s = s.replace(/\{PARAM#[^}]*\}/g, '');
    s = s.replace(/\{SPELL#[^}]*\}/g, '');
    s = s.replace(/\{[A-Za-z_]+#[^}]*\}/g, '');
    s = s.replace(/\{SPACE\}/g, ' ');
    // 尾部未闭合标记兜底（源数据偶见在标记中间截断的描述）
    s = s.replace(/<[^>]*$/, '');
    s = s.replace(/\{[A-Za-z_]+#[^}]*$/, '');
    // 首字符 # 标记剥离（对齐 Windows Handle）
    if (s.startsWith('#')) {
      s = s.substring(1);
    }
    // 剥离后可能残留连续空行，压缩
    s = s.replace(/\n{3,}/g, '\n\n');
    // 剥离多余空白首尾
    return s.trim();
  }

  private static readTexts(raw: Object | undefined): MetaText[] {
    const list: MetaText[] = [];
    const arr = (raw as Object[]) ?? [];
    for (const r of arr) {
      const o: Record<string, Object> = r as Record<string, Object>;
      const t: MetaText = new MetaText();
      // 语音/故事含 {M#}{F#} 性别代词、{NICKNAME}、<i> 等标记，一并清洗
      t.t = WikiMetaService.cleanText(String(o['t'] ?? ''));
      t.c = WikiMetaService.cleanText(String(o['c'] ?? ''));
      list.push(t);
    }
    return list;
  }

  /** 武器列表 */
  static async getWeapons(): Promise<WikiWeaponMeta[]> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.weapons === undefined) {
      if (cache.weaponsLoading === undefined) { cache.weaponsLoading = WikiMetaService.loadWeapons(cache); }
      const loading: Promise<void> = cache.weaponsLoading;
      await loading;
    }
    return cache === WikiMetaService.cache() ? cache.weapons ?? [] : WikiMetaService.getWeapons();
  }

  private static async loadWeapons(cache: WikiMetadataCache): Promise<void> {
    try {
      const arr = await WikiMetaService.readRawJson('weapon_meta.json', cache.locale) as Object[];
      const list: WikiWeaponMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const w: WikiWeaponMeta = new WikiWeaponMeta();
        w.id = Number(o['id'] ?? 0);
        w.name = String(o['name'] ?? '');
        w.canonicalName = String(o['canonicalName'] ?? w.name);
        w.icon = String(o['icon'] ?? '');
        w.awakenIcon = String(o['awakenIcon'] ?? '');
        w.weaponType = Number(o['weaponType'] ?? 0);
        w.promoteId = Number(o['promoteId'] ?? 0);
        const curves: Object[] = (o['growCurves'] as Object[]) ?? [];
        for (const rawCurve of curves) {
          const curve = rawCurve as Record<string, Object>;
          const g: Curve3 = new Curve3();
          g.i = Number(curve['i'] ?? 0);
          g.t = Number(curve['t'] ?? 0);
          g.v = Number(curve['v'] ?? 0);
          w.growCurves.push(g);
        }
        w.secondaryProperty = w.growCurves[1]?.t ?? 0;
        w.rankLevel = Number(o['rankLevel'] ?? 0);
        w.sort = Number(o['sort'] ?? 0);
        w.description = WikiMetaService.cleanText(String(o['description'] ?? ''));
        w.affixName = String(o['affixName'] ?? '');
        const affixes = (o['affixDesc'] as Object[]) ?? [];
        for (const ad of affixes) {
          w.affixDesc.push(WikiMetaService.cleanText(String(ad)));
        }
        const items = (o['cultivationItems'] as Object[]) ?? [];
        for (const it of items) {
          w.cultivationItems.push(Number(it));
        }
        list.push(w);
      }
      cache.weapons = list;
      Logger.info(TAG, `weapons loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load weapons fail: ${(e as Error).message}`);
      cache.weapons = [];
    }
  }

  /** 怪物列表（按 DescribeId 升序，对齐 Windows 排序） */
  static async getMonsters(): Promise<WikiMonsterMeta[]> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.monsters === undefined) {
      if (cache.monstersLoading === undefined) { cache.monstersLoading = WikiMetaService.loadMonsters(cache); }
      const loading: Promise<void> = cache.monstersLoading;
      await loading;
    }
    return cache === WikiMetaService.cache() ? cache.monsters ?? [] : WikiMetaService.getMonsters();
  }

  private static async loadMonsters(cache: WikiMetadataCache): Promise<void> {
    try {
      const arr = await WikiMetaService.readRawJson('monster_meta.json', cache.locale) as Object[];
      const list: WikiMonsterMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const m: WikiMonsterMeta = new WikiMonsterMeta();
        m.id = Number(o['id'] ?? 0);
        m.describeId = Number(o['describeId'] ?? 0);
        m.name = String(o['name'] ?? '');
        m.canonicalName = String(o['canonicalName'] ?? m.name);
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
        // Compact files (including older remote cohorts) store wind before ice and rock.
        if (hurts.length >= 8) {
          const displayOrder: number[] = [0, 1, 2, 3, 5, 6, 4, 7];
          for (const index of displayOrder) { m.subHurts.push(Number(hurts[index])); }
        }
        list.push(m);
      }
      cache.monsters = list;
      for (const mo of list) {
        cache.monsterNameMap.set(mo.name, mo.icon);
        cache.monsterNameMap.set(mo.canonicalName, mo.icon);
      }
      Logger.info(TAG, `monsters loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load monsters fail: ${(e as Error).message}`);
      cache.monsters = [];
    }
  }

  /** 材料表（id → 名称/图标/品质） */
  static async getMaterials(): Promise<Map<number, MetaMaterial>> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.materials !== undefined) {
      return cache.materials;
    }
    try {
      const root = await WikiMetaService.readRawJson('material_meta.json', cache.locale) as Record<string, Object>;
      const map: Map<number, MetaMaterial> = new Map<number, MetaMaterial>();
      const keys = Object.keys(root);
      for (const key of keys) {
        const o: Record<string, Object> = root[key] as Record<string, Object>;
        const m: MetaMaterial = new MetaMaterial();
        m.n = String(o['n'] ?? '');
        m.canonicalName = String(o['canonicalName'] ?? m.n);
        m.i = String(o['i'] ?? '');
        m.r = Number(o['r'] ?? 0);
        map.set(Number(key), m);
      }
      cache.materials = map;
      Logger.info(TAG, `materials loaded: ${map.size}`);
    } catch (e) {
      Logger.warn(TAG, `load materials fail: ${(e as Error).message}`);
      cache.materials = new Map();
    }
    return cache === WikiMetaService.cache() ? cache.materials : WikiMetaService.getMaterials();
  }

  /** Monster drops also include DisplayItem relic sets; keep these out of the material catalog. */
  static async getMonsterDrops(): Promise<Map<number, MetaMaterial>> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.monsterDrops !== undefined) { return cache.monsterDrops; }
    const map: Map<number, MetaMaterial> = new Map<number, MetaMaterial>(await WikiMetaService.getMaterials());
    try {
      const rows: Object[] = await WikiMetaService.readRawJson('monster_drop_meta.json', cache.locale) as Object[];
      const names: Map<number, string> = await LocalizedGameDataService.names('ReliquarySet.json', cache.locale);
      for (const raw of rows) {
        const row: Record<string, Object> = raw as Record<string, Object>;
        const id: number = Number(row['Id'] ?? 0);
        if (id <= 0 || map.has(id)) { continue; }
        const item: MetaMaterial = new MetaMaterial();
        item.canonicalName = String(row['Name'] ?? '');
        item.n = names.get(Number(row['SetId'] ?? 0)) ?? item.canonicalName;
        item.i = String(row['Icon'] ?? '');
        item.r = Number(row['RankLevel'] ?? 0);
        map.set(id, item);
      }
    } catch (error) {
      Logger.warn(TAG, `monster display items unavailable: ${(error as Error).message}`);
    }
    if (cache !== WikiMetaService.cache()) { return WikiMetaService.getMonsterDrops(); }
    cache.monsterDrops = map;
    return map;
  }

  /** 武器类型数字 → 中文 */
  static weaponTypeName(t: number): string {
    switch (t) {
      case 1: return '单手剑';
      case 11: return '双手剑';
      case 13: return '长柄武器';
      case 10: return '法器';
      case 12: return '弓';
      default: return `类型${t}`;
    }
  }

  static qualityName(quality: number): string {
    const names: string[] = ['', '一星', '二星', '三星', '四星', '五星'];
    return quality === 105 ? '限定五星' : names[quality] ?? '';
  }

  static associationName(association: number): string {
    return WikiMetaService.ASSOCIATIONS[association] ?? '';
  }

  static associationOptions(): string[] {
    return Array.from(new Set(WikiMetaService.ASSOCIATIONS.filter((name: string): boolean => name.length > 0)));
  }

  // ============ id → 图标名映射（祈愿/深渊等页面头像真图标）============


  /** 预载 id→icon 映射（轻量，页面 aboutToAppear 调用一次） */
  static async ensureIconMaps(): Promise<void> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.avatarIconMap.size > 0 && cache.weaponIconMap.size > 0) {
      return;
    }
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    if (cache !== WikiMetaService.cache()) { return WikiMetaService.ensureIconMaps(); }
    for (const a of avatars) {
      cache.avatarIconMap.set(a.id, a.icon);
      cache.avatarSideIconMap.set(a.id, a.sideIcon);
      cache.avatarNameMap.set(a.name, a.icon);
      cache.avatarNameMap.set(a.canonicalName, a.icon);
      if (a.nameCardPic.length > 0) {
        cache.avatarNameCardPicMap.set(a.name, a.nameCardPic);
        cache.avatarNameCardPicMap.set(a.canonicalName, a.nameCardPic);
      }
    }
    for (const w of weapons) {
      cache.weaponIconMap.set(w.id, w.icon);
      cache.weaponNameMap.set(w.name, w.icon);
      cache.weaponNameMap.set(w.canonicalName, w.icon);
    }
    Logger.info(TAG, `icon maps: ${cache.avatarIconMap.size} avatars, ${cache.weaponIconMap.size} weapons`);
  }

  /** 角色 item_id(avatarId) → 头像图标名（未命中返回空）。
   *  兼容 item_id 风格（如 1015=七七）与 Enka avatarId 风格（10000035）：低位数字 id + 1e7 换算 */
  static iconOfAvatar(id: number): string {
    let n: string | undefined = WikiMetaService.cache().avatarIconMap.get(id);
    if (n === undefined && id > 0 && id < 1000000) {
      n = WikiMetaService.cache().avatarIconMap.get(id + 10000000);
    }
    if (n === undefined && id > 1000) {
      n = WikiMetaService.cache().avatarIconMap.get(id - 10000000);
    }
    return n !== undefined ? n : '';
  }

  /** 角色 item_id(avatarId) → 侧脸图标名（未命中返回空；幽境/剧诗最强一击等用） */
  static sideIconOfAvatar(id: number): string {
    const n: string | undefined = WikiMetaService.cache().avatarSideIconMap.get(id);
    return n !== undefined ? n : '';
  }

  /** 角色 id → 名称（未命中返回空；剧期限定角色行用） */
  static nameOfAvatarId(id: number): string {
    return WikiMetaService.avatarOf(id)?.name ?? '';
  }

  static avatarOf(id: number): WikiAvatarMeta | undefined {
    return WikiMetaService.cache().avatars?.find((avatar: WikiAvatarMeta): boolean => avatar.id === id);
  }

  /** 武器 item_id → 图标名（未命中返回空） */
  static iconOfWeapon(id: number): string {
    const n: string | undefined = WikiMetaService.cache().weaponIconMap.get(id);
    return n !== undefined ? n : '';
  }

  /** 角色中文名 → 头像图标名（未命中返回空；容忍全角空格/首尾空白） */
  /** 体型中文名（对齐 Windows BodyType 本地化：少年/少女/成女/成男/萝莉） */
  static bodyTypeName(body: number): string {
    if (body === 1) { return '少年'; }
    if (body === 2) { return '少女'; }
    if (body === 3) { return '成女'; }
    if (body === 4) { return '成男'; }
    if (body === 5) { return '萝莉'; }
    return '未知体型';
  }

  /** 皮肤立绘 CDN 图名：FrontIcon(UI_AvatarIcon_X) → Costume 类目 UI_Costume_X（对齐 Windows CostumeConverter） */
  static costumeArtName(frontIcon: string): string {
    if (frontIcon.startsWith('UI_AvatarIcon_')) {
      return `UI_Costume_${frontIcon.slice('UI_AvatarIcon_'.length)}`;
    }
    return '';
  }

  static iconOfAvatarName(name: string): string {
    if (name.length === 0) {
      return '';
    }
    let n: string | undefined = WikiMetaService.cache().avatarNameMap.get(name);
    if (n === undefined) {
      // 尝试去除空格（部分接口返回" 七七"或"七七 "）
      n = WikiMetaService.cache().avatarNameMap.get(name.trim());
      if (n === undefined) {
        const trimmed: string = name.replace(/\s+/g, '');
        for (const key of WikiMetaService.cache().avatarNameMap.keys()) {
          if (key.replace(/\s+/g, '') === trimmed) {
            n = WikiMetaService.cache().avatarNameMap.get(key);
            break;
          }
        }
      }
    }
    return n !== undefined ? n : '';
  }

  /** 武器中文名 → 图标名（未命中返回空） */
  static iconOfWeaponName(name: string): string {
    const n: string | undefined = WikiMetaService.cache().weaponNameMap.get(name);
    return n !== undefined ? n : '';
  }

  /** 角色名 → 名片大图名（NameCardPic，我的角色专属背景；未命中返回空） */
  static nameCardPicOf(avatarName: string): string {
    const n: string | undefined = WikiMetaService.cache().avatarNameCardPicMap.get(avatarName);
    return n !== undefined ? n : '';
  }

  /** 角色名 → 天赋/技能列表（我的角色详情天赋区用；未命中返回空数组） */
  static skillsOfAvatar(name: string): MetaSkill[] {
    // 遍历缓存的角色列表（getAvatars 已缓存，不重复解析）
    const avatars = WikiMetaService.cache().avatars;
    if (avatars !== undefined) {
      for (const a of avatars) {
        if (a.name === name || a.canonicalName === name) {
          return a.skills;
        }
      }
    }
    return [];
  }

  /** 名片列表（懒加载 metadata/NameCard.json；description 经富文本清洗） */
  static async getNameCards(): Promise<NameCardMeta[]> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.nameCards !== undefined) {
      return cache.nameCards;
    }
    try {
      const arr = await WikiMetaService.readRawJson('NameCard.json', cache.locale) as Object[];
      const list: NameCardMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const c: NameCardMeta = new NameCardMeta();
        c.name = String(o['Name'] ?? '');
        c.canonicalName = String(o['canonicalName'] ?? c.name);
        c.description = WikiMetaService.cleanText(String(o['Description'] ?? ''));
        c.icon = String(o['Icon'] ?? '');
        c.picture = String(o['Picture'] ?? '');
        if (c.picture.length > 0) {
          cache.nameCardByPic.set(c.picture, c);
        }
        list.push(c);
      }
      cache.nameCards = list;
      Logger.info(TAG, `namecards loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load namecards fail: ${(e as Error).message}`);
      cache.nameCards = [];
    }
    return cache === WikiMetaService.cache() ? cache.nameCards : WikiMetaService.getNameCards();
  }

  /** 名片大图名 → 名片条目（名称/描述/图标；未命中返回 undefined） */
  static async getNameCardByPic(pic: string): Promise<NameCardMeta | undefined> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.nameCards === undefined) {
      await WikiMetaService.getNameCards();
    }
    return cache === WikiMetaService.cache() ? cache.nameCardByPic.get(pic) : WikiMetaService.getNameCardByPic(pic);
  }

  /** 祈愿卡池期次列表（懒加载 metadata/GachaEvent.json，按开始时间升序） */
  static async getGachaEvents(): Promise<GachaEventMeta[]> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.gachaEvents !== undefined) {
      return cache.gachaEvents;
    }
    try {
      const arr = await WikiMetaService.readRawJson('GachaEvent.json', cache.locale) as Object[];
      const list: GachaEventMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const e: GachaEventMeta = new GachaEventMeta();
        e.name = String(o['Name'] ?? '');
        e.canonicalName = String(o['canonicalName'] ?? e.name);
        e.version = String(o['Version'] ?? '');
        e.order = Number(o['Order'] ?? 0);
        // ISO8601 含时区（+08:00），Date.parse 直接解析
        e.from = Date.parse(String(o['From'] ?? ''));
        e.to = Date.parse(String(o['To'] ?? ''));
        e.type = Number(o['Type'] ?? 0);
        e.banner = String(o['Banner'] ?? '');
        const upsO = (o['UpOrangeList'] as Object[]) ?? [];
        for (const id of upsO) {
          e.upOrange.push(Number(id));
        }
        const upsP = (o['UpPurpleList'] as Object[]) ?? [];
        for (const id of upsP) {
          e.upPurple.push(Number(id));
        }
        if (e.from > 0 && e.to > 0) {
          list.push(e);
        }
      }
      list.sort((a: GachaEventMeta, b: GachaEventMeta) => a.from - b.from);
      cache.gachaEvents = list;
      Logger.info(TAG, `gacha events loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load gacha events fail: ${(e as Error).message}`);
      cache.gachaEvents = [];
    }
    return cache === WikiMetaService.cache() ? cache.gachaEvents : WikiMetaService.getGachaEvents();
  }

  /** 千星奇域专属物品映射（懒加载 metadata/BeyondItem.json；祈愿颂愿模式渲染前调用） */
  static async ensureBeyondItemMaps(): Promise<void> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.beyondItems !== undefined) {
      return;
    }
    try {
      const arr = await WikiMetaService.readRawJson('BeyondItem.json', cache.locale) as Object[];
      const list: BeyondItemMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const b: BeyondItemMeta = new BeyondItemMeta();
        b.id = Number(o['Id'] ?? 0);
        b.name = String(o['Name'] ?? '');
        b.canonicalName = String(o['canonicalName'] ?? b.name);
        b.icon = String(o['Icon'] ?? '');
        b.type = Number(o['Type'] ?? 0);
        b.rank = Number(o['RankLevel'] ?? 0);
        if (b.id <= 0 || b.name.length === 0 || b.icon.length === 0) {
          continue;
        }
        list.push(b);
        cache.beyondIconByName.set(b.name, b.icon);
        cache.beyondIconByName.set(b.canonicalName, b.icon);
        cache.beyondNameById.set(b.id, b.name);
        cache.beyondIconById.set(b.id, b.icon);
      }
      cache.beyondItems = list;
      Logger.info(TAG, `beyond items loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load beyond items fail: ${(e as Error).message}`);
      cache.beyondItems = [];
    }
    if (cache !== WikiMetaService.cache()) { await WikiMetaService.ensureBeyondItemMaps(); }
  }

  /** 千星奇域专属物品名 → 图标名（未命中返回空；与角色/武器名空间互斥） */
  static iconOfBeyondName(name: string): string {
    if (name.length === 0) {
      return '';
    }
    let n: string | undefined = WikiMetaService.cache().beyondIconByName.get(name);
    if (n === undefined && name.trim() !== name) {
      n = WikiMetaService.cache().beyondIconByName.get(name.trim());
    }
    return n !== undefined ? n : '';
  }

  /** 千星奇域专属物品 id → 名称（未命中返回空） */
  static nameOfBeyondId(id: number): string {
    const n: string | undefined = WikiMetaService.cache().beyondNameById.get(id);
    return n !== undefined ? n : '';
  }

  /** 千星奇域专属物品 id → 图标名（未命中返回空） */
  static iconOfBeyondId(id: number): string {
    const n: string | undefined = WikiMetaService.cache().beyondIconById.get(id);
    return n !== undefined ? n : '';
  }

  /** 怪物中文名 → MonsterIcon 图标名（未命中返回空；剧诗/幽境敌人头像用） */
  static iconOfMonsterName(name: string): string {
    const n: string | undefined = WikiMetaService.cache().monsterNameMap.get(name);
    if (n !== undefined) {
      return n;
    }
    // API 名可能带词缀后缀或截断：前缀互含兜底
    let found: string = '';
    WikiMetaService.cache().monsterNameMap.forEach((icon: string, key: string) => {
      if (found.length === 0 && name.length > 0 && (key.startsWith(name) || name.startsWith(key))) {
        found = icon;
      }
    });
    return found;
  }

  /** 武器 id → 武器名（我的角色武器行显示；未命中返回空） */
  static nameOfWeapon(id: number): string {
    return WikiMetaService.weaponOf(id)?.name ?? '';
  }

  static weaponOf(id: number): WikiWeaponMeta | undefined {
    return WikiMetaService.cache().weapons?.find((weapon: WikiWeaponMeta): boolean => weapon.id === id);
  }

  /** Display projection for saved CN wish records. Never change GachaItem.name or its export shape. */
  static displayNameOfItem(id: number, originalName: string, itemType: string): string {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    const beyond: string | undefined = cache.beyondNameById.get(id);
    if (beyond !== undefined) { return beyond; }
    if (id > 0) {
      return WikiMetaService.weaponOf(id)?.name ?? WikiMetaService.avatarOf(id)?.name ?? originalName;
    }
    const weapon: WikiWeaponMeta | undefined = cache.weapons?.find((entry: WikiWeaponMeta): boolean =>
      entry.canonicalName === originalName || entry.name === originalName);
    const avatar: WikiAvatarMeta | undefined = cache.avatars?.find((entry: WikiAvatarMeta): boolean =>
      entry.canonicalName === originalName || entry.name === originalName);
    if (itemType === '武器') {
      if (weapon !== undefined) { return weapon.name; }
    }
    if (avatar !== undefined) { return avatar.name; }
    if (weapon !== undefined) { return weapon.name; }
    return cache.beyondItems?.find((entry: BeyondItemMeta): boolean =>
      entry.canonicalName === originalName || entry.name === originalName)?.name ?? originalName;
  }

  /**
   * 抽卡记录条目 → 图标名（角色走 AvatarIcon、武器走 EquipIcon、千星奇域专属物品走 BeyondItemIcon）。
   * 颂愿记录 item_type 服务端不固定（对齐 Windows：不按 item_type 判定专属物品），
   * 名称未命中角色/武器映射时按专属物品映射兜底；未命中返回空。
   */
  static iconOfItemName(name: string, itemType: string): string {
    if (itemType === '武器') {
      const w: string | undefined = WikiMetaService.cache().weaponNameMap.get(name);
      if (w !== undefined) {
        return w;
      }
      return WikiMetaService.iconOfBeyondName(name);
    }
    const a: string | undefined = WikiMetaService.cache().avatarNameMap.get(name);
    if (a !== undefined) {
      return a;
    }
    return WikiMetaService.iconOfBeyondName(name);
  }

  /** 抽卡记录条目 → MetaIcon 类目（与 iconOfItemName 同一判定链；未命中按常规类目兜底占位） */
  static categoryOfItemName(name: string, itemType: string): string {
    if (itemType === '武器') {
      const w: string | undefined = WikiMetaService.cache().weaponNameMap.get(name);
      if (w !== undefined) {
        return 'EquipIcon';
      }
      return WikiMetaService.iconOfBeyondName(name).length > 0 ? 'BeyondItemIcon' : 'EquipIcon';
    }
    const a: string | undefined = WikiMetaService.cache().avatarNameMap.get(name);
    if (a !== undefined) {
      return 'AvatarIcon';
    }
    return WikiMetaService.iconOfBeyondName(name).length > 0 ? 'BeyondItemIcon' : 'AvatarIcon';
  }

  /** 元素英文 → 中文 */
  static elementName(e: string): string {
    // 大小写归一（元数据与 API 大小写可能不一致）
    const key: string = e.length > 0 ? e.charAt(0).toUpperCase() + e.slice(1).toLowerCase() : e;
    switch (key) {
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

  /** 幻想真境剧诗期次元数据（懒加载 metadata/RoleCombatSchedule.json，按 Id 匹配 API scheduleId） */
  static async getRoleCombatSchedules(): Promise<RoleCombatScheduleMeta[]> {
    const cache: WikiMetadataCache = WikiMetaService.cache();
    if (cache.roleCombatSchedules !== undefined) {
      return cache.roleCombatSchedules;
    }
    try {
      const arr = await WikiMetaService.readRawJson('RoleCombatSchedule.json', cache.locale) as Object[];
      const list: RoleCombatScheduleMeta[] = [];
      for (const raw of arr) {
        const o: Record<string, Object> = raw as Record<string, Object>;
        const m: RoleCombatScheduleMeta = new RoleCombatScheduleMeta();
        m.id = Number(o['Id'] ?? 0);
        m.begin = Date.parse(String(o['Begin'] ?? ''));
        m.end = Date.parse(String(o['End'] ?? ''));
        const els = (o['Elements'] as Object[]) ?? [];
        for (const e of els) {
          m.elements.push(Number(e));
        }
        const sp = (o['SpecialAvatars'] as Object[]) ?? [];
        for (const e of sp) {
          m.specialAvatars.push(Number(e));
        }
        const ini = (o['InitialAvatars'] as Object[]) ?? [];
        for (const e of ini) {
          m.initialAvatars.push(Number(e));
        }
        list.push(m);
      }
      cache.roleCombatSchedules = list;
      Logger.info(TAG, `role combat schedules loaded: ${list.length}`);
    } catch (e) {
      Logger.warn(TAG, `load role combat schedules fail: ${(e as Error).message}`);
      cache.roleCombatSchedules = [];
    }
    return cache === WikiMetaService.cache() ? cache.roleCombatSchedules : WikiMetaService.getRoleCombatSchedules();
  }

  /** 剧期限定元素数字 → 元素中文名（对齐 Windows ElementType 枚举） */
  static elementNameById(n: number): string {
    switch (n) {
      case 1: return '火';
      case 2: return '水';
      case 3: return '草';
      case 4: return '雷';
      case 5: return '冰';
      case 7: return '风';
      case 8: return '岩';
      default: return `${n}`;
    }
  }

  /** 剧期限定元素数字 → IconElement 图标名（rawfile/icons/IconElement） */
  static elementIconById(n: number): string {
    switch (n) {
      case 1: return 'UI_Icon_Element_Pyro';
      case 2: return 'UI_Icon_Element_Hydro';
      case 3: return 'UI_Icon_Element_Dendro';
      case 4: return 'UI_Icon_Element_Electro';
      case 5: return 'UI_Icon_Element_Cryo';
      case 7: return 'UI_Icon_Element_Anemo';
      case 8: return 'UI_Icon_Element_Geo';
      default: return '';
    }
  }
}
