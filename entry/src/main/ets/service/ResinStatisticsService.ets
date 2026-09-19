/**
 * ResinStatisticsService.ets
 * 树脂换算统计（对齐 Windows Snap.Hutao Remastered 养成页统计区）。
 *
 * 换算规则与 Windows 同源同值，来源（Snap.Hutao.Remastered 源码）：
 * - 世界等级期望掉落表：Model/Metadata/Item/MaterialDropDistribution.cs:10-33
 *   （MoraPerResin=50；BlossomOfWealth 期望 = 裸期望 + 20树脂×50，构造器 :21）
 * - 分类聚合规则：Service/Cultivation/CultivationResinStatisticsService.cs:18-123
 *   按材料 Rank 分桶：Rank 10=摩拉→藏金之花；100=经验书→启示之花（仅紫色书未毕业才计入，
 *   绿1000/蓝5000/紫20000 经验/本）；11101=Boss掉落（紫4星→世界BOSS、橙5星→周常BOSS）；
 *   其余 (Rank/1000)%10==3→天赋本、==5→武器突破本，四阶按 AlchemyCrafting.UnWeighted
 *   （Service/Cultivation/AlchemyCrafting.cs:10-13，橙×27+紫×9+蓝×3+绿，线性可全局聚合）
 *   折算为绿色品质等效数量。
 * - 指标公式：ViewModel/Cultivation/ResinStatisticsItem.cs:47-111
 *   次数 RawTimes=ceil(需求/期望)；总树脂=次数×单次树脂(花/本20、世界BOSS40、周常60)；
 *   脆弱树脂=ceil(总树脂/60)；自然恢复天数=ceil(总树脂/(1440/8))（1树脂/8分钟=180/天）；
 *   各分类附带产出摩拉 = 次数×期望摩拉 + 总树脂×50，从藏金之花摩拉需求中扣减
 *   （ViewModel/Cultivation/ResinStatistics.cs:96-104）。
 * - 今日可刷：Material.IsItemOfToday（Model/Metadata/Item/Material.cs:80-90，
 *   服务器时区-4h 取星期；周日天赋/武器本全开视为可刷），轮换表
 *   Model/Metadata/Item/MaterialIds.cs:25-73（周一四/二五/三六）。
 *
 * 鸿蒙差异：计划库无库存数量（Windows Current=游戏背包），材料勾选 finished 视为已满足
 * （折算需求量记 0）；无法表达"库存富余低阶书"的负需求，行为取保守值。
 * 材料 id→分类用静态 id 段判定（鸿蒙 material_meta.json 无 Windows 的 Rank 字段）：
 * 202=摩拉；104001-104003=经验书；113xxx=Boss掉落（r==5 橙→周常，否则世界）；
 * 1043xx（除 104300/104319）=天赋书；114xxx=武器突破材料。
 */
import { WikiMetaService, MetaMaterial } from './WikiMetaService';
import { CultivateEntry } from '../data/repo/CultivationRepo';

/** 世界等级期望掉落（对齐 Windows MaterialDropDistribution） */
export class ResinDropDistribution {
  worldLevel: number = 9;
  /** 每次 20 树脂藏金之花期望摩拉（已含 +1000 贴补） */
  blossomOfWealth: number = 0;
  /** 每次 20 树脂启示之花期望经验 */
  blossomOfRevelation: number = 0;
  /** 每次 20 树脂天赋本期望绿色书数量 */
  talentBooks: number = 0;
  talentBooksMora: number = 0;
  /** 每次 20 树脂武器本期望绿色材料数量 */
  weaponAscension: number = 0;
  weaponAscensionMora: number = 0;
  /** 每次 40 树脂世界 BOSS 期望紫材料数量 */
  normalBoss: number = 0;
  normalBossMora: number = 0;
  /** 每次 60 树脂周常 BOSS 期望橙材料数量 */
  weeklyBoss: number = 0;
  weeklyBossMora: number = 0;

  constructor(worldLevel: number, rawWealth: number, revelation: number, talent: number,
    talentMora: number, weapon: number, weaponMora: number, normal: number,
    normalMora: number, weekly: number, weeklyMora: number) {
    this.worldLevel = worldLevel;
    // Windows 构造器把 20 树脂×50 摩拉贴补进藏金之花期望（MaterialDropDistribution.cs:21）
    this.blossomOfWealth = rawWealth + 20 * ResinStatisticsService.MORA_PER_RESIN;
    this.blossomOfRevelation = revelation;
    this.talentBooks = talent;
    this.talentBooksMora = talentMora;
    this.weaponAscension = weapon;
    this.weaponAscensionMora = weaponMora;
    this.normalBoss = normal;
    this.normalBossMora = normalMora;
    this.weeklyBoss = weekly;
    this.weeklyBossMora = weeklyMora;
  }
}

/** 分类 kind（对齐 Windows ResinStatisticsItemKind） */
export class ResinCategoryKind {
  static readonly WEALTH: number = 0;        // 藏金之花（摩拉）
  static readonly REVELATION: number = 1;    // 启示之花（经验书）
  static readonly TALENT: number = 2;        // 角色天赋素材（天赋本）
  static readonly WEAPON: number = 3;        // 武器突破素材（武器本）
  static readonly NORMAL_BOSS: number = 4;   // 世界 BOSS
  static readonly WEEKLY_BOSS: number = 5;   // 周常 BOSS
}

/** 单分类统计行（对齐 Windows ResinStatisticsItem 的展示字段） */
export class ResinCategoryRow {
  kind: number = 0;
  title: string = '';
  /** 单次副本树脂（花/本 20、世界 40、周常 60） */
  resinPerBlossom: number = 20;
  /** 副本次数 */
  runs: number = 0;
  /** 总树脂需求 */
  totalResin: number = 0;
  /** 脆弱树脂换算 */
  fragileResin: number = 0;
  /** 自然恢复天数 */
  days: number = 0;
  /** 需求量描述（摩拉/经验/绿书等效/材料个数） */
  demandText: string = '';
}

/** 树脂统计结果（当前项目聚合） */
export class ResinStatisticsResult {
  worldLevel: number = 9;
  /** 有数据的分类行（顺序对齐 Windows ItemsSource：花→本→BOSS） */
  rows: ResinCategoryRow[] = [];
  totalResin: number = 0;
  totalFragile: number = 0;
  totalDays: number = 0;
}

/** 聚合期间的材料累计 */
class MaterialAgg {
  count: number = 0;
  quality: number = 0;
}

export class ResinStatisticsService {
  /** 每树脂可换摩拉（Windows MaterialDropDistribution.MoraPerResin） */
  static readonly MORA_PER_RESIN: number = 50;
  /** 自然恢复速率：1 树脂 / 8 分钟（1440/8=180 每日，Windows ResinStatisticsItem.Days） */
  static readonly RESIN_PER_DAY: number = 180;
  /** 每本经验书折算经验（CultivationResinStatisticsService.cs:50-56） */
  static readonly EXP_GREEN: number = 1000;
  static readonly EXP_BLUE: number = 5000;
  static readonly EXP_PURPLE: number = 20000;

  private static readonly ID_MORA: number = 202;
  private static readonly ID_EXP_GREEN: number = 104001;
  private static readonly ID_EXP_BLUE: number = 104002;
  private static readonly ID_EXP_PURPLE: number = 104003;
  private static readonly ID_CROWN: number = 104319; // 智识之冕（不计树脂）

  /** 天赋书系列基 id → 轮换日（1=周一四 2=周二五 3=周三六 0=未知；MaterialIds.cs:25-45） */
  private static readonly TALENT_BASES: number[] = [
    104301, 104304, 104307, 104310, 104313, 104316, 104320, 104323, 104326,
    104329, 104332, 104335, 104338, 104341, 104344, 104347, 104350, 104353,
    104356, 104359, 104362,
  ];
  private static readonly TALENT_NEW_BASES: number[] = [104365, 104368];
  /** 武器材料系列基 id → 轮换日（MaterialIds.cs:46-73） */
  private static readonly WEAPON_BASES: number[] = [
    114001, 114005, 114009, 114013, 114017, 114021, 114025, 114029, 114033,
    114037, 114041, 114045, 114049, 114053, 114057, 114061, 114065, 114069,
    114073, 114077, 114081,
  ];

  /** 世界等级 5-9 期望掉落（数值取自 MaterialDropDistribution.cs:12-16） */
  static distributions(): ResinDropDistribution[] {
    const list: ResinDropDistribution[] = [];
    list.push(new ResinDropDistribution(5, 52000, 102500, 7.8, 2050, 16.708, 2200, 2.2, 4450, 1.0, 7600));
    list.push(new ResinDropDistribution(6, 60000, 122500, 10.12, 2375, 16.708, 2200, 2.2, 4725, 1.55, 8000));
    list.push(new ResinDropDistribution(7, 60000, 122500, 10.12, 2375, 16.708, 2200, 2.56, 5200, 2.1, 8100));
    list.push(new ResinDropDistribution(8, 60000, 122500, 10.12, 2375, 16.708, 2200, 2.56, 6000, 2.4, 8100));
    list.push(new ResinDropDistribution(9, 60000, 122500, 10.12, 2375, 16.708, 2200, 3, 6000, 2.4, 8100));
    return list;
  }

  static distributionOf(worldLevel: number): ResinDropDistribution {
    const all: ResinDropDistribution[] = ResinStatisticsService.distributions();
    for (const d of all) {
      if (d.worldLevel === worldLevel) {
        return d;
      }
    }
    return all[all.length - 1];
  }

  /** 材料轮换日：1=周一四 2=周二五 3=周三六 0=非轮换/未知（对齐 Windows MaterialIds 轮换表） */
  static dayPairOf(itemId: number): number {
    for (let i = 0; i < ResinStatisticsService.TALENT_BASES.length; i++) {
      const base: number = ResinStatisticsService.TALENT_BASES[i];
      if (itemId >= base && itemId <= base + 2) {
        return (i % 3) + 1;
      }
    }
    for (let i = 0; i < ResinStatisticsService.WEAPON_BASES.length; i++) {
      const base: number = ResinStatisticsService.WEAPON_BASES[i];
      if (itemId >= base && itemId <= base + 3) {
        return (i % 3) + 1;
      }
    }
    // 新系列（104365+，Windows 轮换表未收录）日对未知
    return 0;
  }

  /** 当日是否可刷（dow=Date.getDay()，0=周日；周日全开对齐 Windows treatSundayAsTrue） */
  static isItemOfToday(itemId: number, dow: number): boolean {
    const pair: number = ResinStatisticsService.dayPairOf(itemId);
    if (pair === 0) {
      return false;
    }
    if (dow === 0) {
      return true;
    }
    const todayPair: number = dow <= 3 ? dow : dow - 3;
    return todayPair === pair;
  }

  /** 天赋书品质阶：0 绿 1 蓝 2 紫（未匹配按紫，避免漏算） */
  private static talentTierOf(itemId: number): number {
    for (const base of ResinStatisticsService.TALENT_BASES) {
      if (itemId >= base && itemId <= base + 2) {
        return itemId - base;
      }
    }
    for (const base of ResinStatisticsService.TALENT_NEW_BASES) {
      if (itemId >= base && itemId <= base + 2) {
        return itemId - base;
      }
    }
    return 2;
  }

  /** 武器材料品质阶：0 绿 1 蓝 2 紫 3 橙（114001-114084 连续，(id-1)%4 对齐系列） */
  private static weaponTierOf(itemId: number): number {
    return (itemId - 1) % 4;
  }

  /**
   * 聚合当前项目全部未完成材料并折算树脂需求。
   * entries：当前项目的全部培养条目（含材料清单）。
   */
  static async compute(entries: CultivateEntry[], dist: ResinDropDistribution): Promise<ResinStatisticsResult> {
    // id → 未完成需求合计；Boss 材料品质取自 material_meta（r==5 橙=周常）
    const aggs: Map<number, MaterialAgg> = new Map();
    for (const entry of entries) {
      for (const item of entry.items) {
        if (item.finished) {
          continue;
        }
        if (item.itemId <= 0 && item.name.length === 0) {
          continue;
        }
        let agg: MaterialAgg | undefined = aggs.get(item.itemId);
        if (agg === undefined) {
          agg = new MaterialAgg();
          aggs.set(item.itemId, agg);
        }
        agg.count += item.count;
      }
    }
    // Boss 品质批量补齐
    if (aggs.size > 0) {
      const materials: Map<number, MetaMaterial> | null = await ResinStatisticsService.tryMaterials();
      if (materials !== null) {
        aggs.forEach((agg: MaterialAgg, id: number) => {
          if (id >= 113001 && id <= 113099) {
            const m: MetaMaterial | undefined = materials.get(id);
            agg.quality = m !== undefined ? m.r : 4;
          }
        });
      }
    }

    // 分类累计（对齐 CultivationResinStatisticsService.GetResinStatisticsAsync）
    const rawWealth: number = aggs.get(ResinStatisticsService.ID_MORA)?.count ?? 0;
    const expGreen: number = aggs.get(ResinStatisticsService.ID_EXP_GREEN)?.count ?? 0;
    const expBlue: number = aggs.get(ResinStatisticsService.ID_EXP_BLUE)?.count ?? 0;
    const expPurpleAgg: MaterialAgg | undefined = aggs.get(ResinStatisticsService.ID_EXP_PURPLE);
    // Windows：仅当紫色经验书存在且未毕业才把经验折算进启示之花（:46）
    const expRaw: number = (expPurpleAgg !== undefined && expPurpleAgg.count > 0)
      ? expGreen * ResinStatisticsService.EXP_GREEN + expBlue * ResinStatisticsService.EXP_BLUE
      + expPurpleAgg.count * ResinStatisticsService.EXP_PURPLE
      : 0;

    let talentGreen: number = 0;
    let talentBlue: number = 0;
    let talentPurple: number = 0;
    let weaponGreen: number = 0;
    let weaponBlue: number = 0;
    let weaponPurple: number = 0;
    let weaponOrange: number = 0;
    let normalBossCount: number = 0;
    let weeklyBossCount: number = 0;

    aggs.forEach((agg: MaterialAgg, id: number) => {
      if (id === ResinStatisticsService.ID_MORA || id === ResinStatisticsService.ID_EXP_GREEN
        || id === ResinStatisticsService.ID_EXP_BLUE || id === ResinStatisticsService.ID_EXP_PURPLE) {
        return;
      }
      if (id >= 104301 && id <= 104370 && id !== ResinStatisticsService.ID_CROWN) {
        const tier: number = ResinStatisticsService.talentTierOf(id);
        if (tier === 0) {
          talentGreen += agg.count;
        } else if (tier === 1) {
          talentBlue += agg.count;
        } else {
          talentPurple += agg.count;
        }
        return;
      }
      if (id >= 114001 && id <= 114099) {
        const tier: number = ResinStatisticsService.weaponTierOf(id);
        if (tier === 0) {
          weaponGreen += agg.count;
        } else if (tier === 1) {
          weaponBlue += agg.count;
        } else if (tier === 2) {
          weaponPurple += agg.count;
        } else {
          weaponOrange += agg.count;
        }
        return;
      }
      if (id >= 113001 && id <= 113099) {
        if (agg.quality >= 5) {
          weeklyBossCount += agg.count;
        } else {
          normalBossCount += agg.count;
        }
      }
      // 其余（突破矿石/宝石/特产/摩拉以外素材）非树脂消耗，不计入
    });

    // 四阶→绿色等效（AlchemyCrafting.UnWeighted：27橙+9紫+3蓝+绿，线性）
    const talentRaw: number = 9 * talentPurple + 3 * talentBlue + talentGreen;
    const weaponRaw: number = 27 * weaponOrange + 9 * weaponPurple + 3 * weaponBlue + weaponGreen;

    const result: ResinStatisticsResult = new ResinStatisticsResult();
    result.worldLevel = dist.worldLevel;

    const revelationRow: ResinCategoryRow | null =
      ResinStatisticsService.buildRow(ResinCategoryKind.REVELATION, '启示之花', 20, expRaw,
      dist.blossomOfRevelation, ResinStatisticsService.formatNumber(expRaw));
    const talentRow: ResinCategoryRow | null =
      ResinStatisticsService.buildRow(ResinCategoryKind.TALENT, '角色天赋素材', 20, talentRaw,
      dist.talentBooks, `${ResinStatisticsService.formatNumber(talentRaw)} 本（绿书等效）`);
    const weaponRow: ResinCategoryRow | null =
      ResinStatisticsService.buildRow(ResinCategoryKind.WEAPON, '武器突破素材', 20, weaponRaw,
      dist.weaponAscension, `${ResinStatisticsService.formatNumber(weaponRaw)} 个（绿材等效）`);
    const normalRow: ResinCategoryRow | null =
      ResinStatisticsService.buildRow(ResinCategoryKind.NORMAL_BOSS, '世界 BOSS', 40, normalBossCount,
      dist.normalBoss, `× ${ResinStatisticsService.formatNumber(normalBossCount)}`);
    const weeklyRow: ResinCategoryRow | null =
      ResinStatisticsService.buildRow(ResinCategoryKind.WEEKLY_BOSS, '周常 BOSS', 60, weeklyBossCount,
      dist.weeklyBoss, `× ${ResinStatisticsService.formatNumber(weeklyBossCount)}`);

    // 其他分类的附产摩拉从藏金之花需求中扣减（ResinStatistics.RefreshBlossomOfWealth）
    const miscMora: number = ResinStatisticsService.moraOf(revelationRow, 0)
      + ResinStatisticsService.moraOf(talentRow, dist.talentBooksMora)
      + ResinStatisticsService.moraOf(weaponRow, dist.weaponAscensionMora)
      + ResinStatisticsService.moraOf(normalRow, dist.normalBossMora)
      + ResinStatisticsService.moraOf(weeklyRow, dist.weeklyBossMora);
    const wealthDemand: number = Math.max(0, rawWealth - miscMora);
    const wealthRow: ResinCategoryRow | null =
      ResinStatisticsService.buildRow(ResinCategoryKind.WEALTH, '藏金之花', 20, wealthDemand,
      dist.blossomOfWealth, ResinStatisticsService.formatNumber(wealthDemand));

    const ordered: (ResinCategoryRow | null)[] =
      [wealthRow, revelationRow, talentRow, weaponRow, normalRow, weeklyRow];
    for (const row of ordered) {
      if (row !== null) {
        result.rows.push(row);
        result.totalResin += row.totalResin;
        result.totalFragile += row.fragileResin;
      }
    }
    result.totalDays = Math.ceil(result.totalResin / ResinStatisticsService.RESIN_PER_DAY);
    return result;
  }

  /** 单行构建（需求 <=0 返回 null，对齐 Windows HasData 过滤） */
  private static buildRow(kind: number, title: string, resinPerBlossom: number, demand: number,
    expectation: number, demandText: string): ResinCategoryRow | null {
    if (demand <= 0 || expectation <= 0) {
      return null;
    }
    const row: ResinCategoryRow = new ResinCategoryRow();
    row.kind = kind;
    row.title = title;
    row.resinPerBlossom = resinPerBlossom;
    row.runs = Math.ceil(demand / expectation);
    row.totalResin = row.runs * resinPerBlossom;
    row.fragileResin = Math.ceil(row.totalResin / 60);
    row.days = Math.ceil(row.totalResin / ResinStatisticsService.RESIN_PER_DAY);
    row.demandText = demandText;
    return row;
  }

  /** 分类附产摩拉 = 次数×期望摩拉 + 总树脂×50（ResinStatisticsItem.Mora） */
  private static moraOf(row: ResinCategoryRow | null, expectationMora: number): number {
    if (row === null) {
      return 0;
    }
    return row.runs * expectationMora + row.totalResin * ResinStatisticsService.MORA_PER_RESIN;
  }

  private static async tryMaterials(): Promise<Map<number, MetaMaterial> | null> {
    try {
      const m: Map<number, MetaMaterial> = await WikiMetaService.getMaterials();
      return m;
    } catch (e) {
      return null;
    }
  }

  /** 千分位格式化（整数） */
  static formatNumber(n: number): string {
    const v: number = Math.round(n);
    const s: string = Math.abs(v).toString();
    let out: string = '';
    for (let i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 === 0) {
        out += ',';
      }
      out += s.charAt(i);
    }
    return (v < 0 ? '-' : '') + out;
  }
}
