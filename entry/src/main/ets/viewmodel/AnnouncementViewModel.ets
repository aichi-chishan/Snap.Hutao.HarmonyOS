/**
 * AnnouncementViewModel.ets
 * 公告页状态容器：按 type 分组的页签 + 当前组列表（对齐 Windows AnnouncementWrapper）。
 */
import { AnnouncementService } from '../service/AnnouncementService';
import { Announcement, AnnouncementGroup } from '../model/Announcement';

@Observed
export class AnnouncementViewModel {
  /** 分组页签（groups[0] = 全部，后续为 API type_list 动态顺序） */
  groups: AnnouncementGroup[] = [];
  /** 当前选中页签（0=全部） */
  currentIndex: number = 0;
  /** 当前页签展示列表（全部组时按时间倒序合并） */
  filtered: Announcement[] = [];
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 宽屏双列（由页面 onAreaChange 驱动） */
  isWide: boolean = false;

  async load(): Promise<void> {
    this.loading = true;
    try {
      const groups: AnnouncementGroup[] = await AnnouncementService.getInstance().fetchGroups('cn_gf01', 60);
      // 全部组（typeId=0）置顶，其余保持 API 顺序（Windows Pivot 顺序）
      const all: AnnouncementGroup = new AnnouncementGroup();
      all.typeId = 0;
      all.label = '全部';
      const merged: Announcement[] = [];
      for (let i = 0; i < groups.length; i++) {
        for (let j = 0; j < groups[i].items.length; j++) {
          merged.push(groups[i].items[j]);
        }
      }
      merged.sort((a: Announcement, b: Announcement) => b.startTime - a.startTime);
      all.items = merged;
      // 仅当无数据时保留空页签（避免"全部"空页签占位）
      this.groups = [];
      this.groups.push(all);
      for (let i = 0; i < groups.length; i++) {
        this.groups.push(groups[i]);
      }
      if (this.currentIndex >= this.groups.length) {
        this.currentIndex = 0;
      }
      this.applyFilter();
    } catch (e) {
      this.message = (e as Error).message;
    } finally {
      this.loading = false;
      this.loaded = true;
    }
  }

  selectGroup(index: number): void {
    this.currentIndex = index;
    this.applyFilter();
  }

  private applyFilter(): void {
    if (this.currentIndex === 0) {
      // 全部
      for (const g of this.groups) {
        if (g.typeId === 0) {
          this.filtered = g.items.slice();
          return;
        }
      }
      this.filtered = [];
      return;
    }
    if (this.currentIndex < this.groups.length) {
      this.filtered = this.groups[this.currentIndex].items.slice();
    } else {
      this.filtered = [];
    }
  }
}
