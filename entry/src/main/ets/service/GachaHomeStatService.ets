/**
 * GachaHomeStatService.ets
 * 主页祈愿统计卡「多归档翻页」数据源（对齐 Windows GachaStatisticsCard FlipView+PipsPager 多存档切换）：
 * 遍历全部祈愿归档（GachaRepo.getAllArchives），逐池产出轻量统计行（总数/距保底橙紫）。
 * 仅读本地库不触网；uid 为空的归档跳过（空 UID 归档坑，见 AGENTS.md）。
 */
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaArchive } from '../model/GachaArchive';
import { GachaType } from '../model/GachaType';
import { GachaItem } from '../model/GachaItem';

/** 单池轻量统计行（Swiper 页内面板：名称/总抽/距保底橙紫，无重图） */
export class HomePoolSummary {
  gachaType: number = 0;
  typeName: string = '';
  totalCount: number = 0;
  fiveStarCount: number = 0;
  fourStarCount: number = 0;
  sinceLastFive: number = 0;
  sinceLastFour: number = 0;
}

/** 单归档统计页（FlipView 一页 = 一个 UID 的各池面板） */
export class GachaArchiveStatPage {
  uid: string = '';
  pools: HomePoolSummary[] = [];

  /** 面板总抽数（页脚指示可选用） */
  totalCount(): number {
    let total: number = 0;
    for (let i = 0; i < this.pools.length; i++) {
      total += this.pools[i].totalCount;
    }
    return total;
  }
}

export class GachaHomeStatService {
  /**
   * 全部归档统计页（归档 id 升序；空 uid 跳过；无任何归档返回空数组）。
   * Index 仅在归档数 >= 2 时把结果交给主页祈愿卡翻页，单归档维持原单 UID 展示。
   */
  static async loadArchivePages(): Promise<GachaArchiveStatPage[]> {
    const archives: GachaArchive[] = (await GachaRepo.getAllArchives())
      .filter((archive: GachaArchive): boolean => archive.uid.length > 0);
    // 单归档直接使用主页已有统计，不为不会显示的翻页再扫描一次记录。
    if (archives.length < 2) { return []; }
    const pages: GachaArchiveStatPage[] = [];
    for (let i = 0; i < archives.length; i++) {
      pages.push(await GachaHomeStatService.buildPage(archives[i]));
    }
    return pages;
  }

  /** 单归档页构建：常规池顺序（QUERY_ORDER）逐池统计，仅保留有数据的池 */
  private static async buildPage(archive: GachaArchive): Promise<GachaArchiveStatPage> {
    const page: GachaArchiveStatPage = new GachaArchiveStatPage();
    page.uid = archive.uid;
    page.pools = GachaHomeStatService.summarize(await GachaRepo.getItemsByArchive(archive.id));
    return page;
  }

  /** 输入按祈愿 ID 从旧到新排列。五星会累加四星垫数，四星只重置自身垫数。 */
  static summarize(items: GachaItem[]): HomePoolSummary[] {
    const pools: Map<number, HomePoolSummary> = new Map<number, HomePoolSummary>();
    for (const type of GachaType.QUERY_ORDER) {
      const row: HomePoolSummary = new HomePoolSummary();
      row.gachaType = type;
      row.typeName = GachaType.nameOf(type);
      pools.set(type, row);
    }
    for (const item of items) {
      const row: HomePoolSummary | undefined = pools.get(GachaType.queryTypeOf(item.gachaType));
      if (row === undefined) { continue; }
      row.totalCount++;
      if (item.rankType === 5) {
        row.fiveStarCount++;
        row.sinceLastFive = 0;
        row.sinceLastFour++;
      } else if (item.rankType === 4) {
        row.fourStarCount++;
        row.sinceLastFive++;
        row.sinceLastFour = 0;
      } else if (item.rankType === 3) {
        row.sinceLastFive++;
        row.sinceLastFour++;
      }
    }
    return Array.from(pools.values()).filter((row: HomePoolSummary): boolean => row.totalCount > 0);
  }
}
