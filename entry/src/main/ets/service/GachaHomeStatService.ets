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
export class GachaArchivePoolRow {
  gachaType: number = 0;
  typeName: string = '';
  totalCount: number = 0;
  sinceLastFive: number = 0;
  sinceLastFour: number = 0;
}

/** 单归档统计页（FlipView 一页 = 一个 UID 的各池面板） */
export class GachaArchiveStatPage {
  uid: string = '';
  pools: GachaArchivePoolRow[] = [];

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
    const archives = await GachaRepo.getAllArchives();
    const pages: GachaArchiveStatPage[] = [];
    for (let i = 0; i < archives.length; i++) {
      const uid: string = archives[i].uid;
      if (uid.length === 0) {
        continue;
      }
      pages.push(await GachaHomeStatService.buildPage(uid));
    }
    return pages;
  }

  /** 单归档页构建：常规池顺序（QUERY_ORDER）逐池统计，仅保留有数据的池 */
  private static async buildPage(uid: string): Promise<GachaArchiveStatPage> {
    const page: GachaArchiveStatPage = new GachaArchiveStatPage();
    page.uid = uid;
    const archiveId: number = await GachaRepo.getOrCreateArchive(uid).then((a: GachaArchive) => a.id);
    for (let i = 0; i < GachaType.QUERY_ORDER.length; i++) {
      const type: number = GachaType.QUERY_ORDER[i];
      const items: GachaItem[] = await GachaRepo.getItemsByType(archiveId, type);
      if (items.length <= 0) {
        continue;
      }
      const row: GachaArchivePoolRow = new GachaArchivePoolRow();
      row.gachaType = type;
      row.typeName = GachaType.nameOf(type);
      row.totalCount = items.length;
      // 距上次五星/四星的垫抽数（与 HomeViewModel.loadGacha 同口径）
      for (let j = items.length - 1; j >= 0; j--) {
        if (items[j].rankType === 5) {
          break;
        }
        row.sinceLastFive++;
      }
      for (let j = items.length - 1; j >= 0; j--) {
        if (items[j].rankType === 4) {
          break;
        }
        row.sinceLastFour++;
      }
      page.pools.push(row);
    }
    return page;
  }
}
