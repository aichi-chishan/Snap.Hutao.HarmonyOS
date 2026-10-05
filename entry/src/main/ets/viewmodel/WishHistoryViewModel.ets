import { WishHistoryCategory, WishHistoryItem, WishHistorySnapshot } from '../model/WishHistory';
import { WishHistoryService } from '../service/WishHistoryService';

@Observed
export class WishHistoryViewModel {
  snapshot: WishHistorySnapshot = new WishHistorySnapshot();
  items: WishHistoryItem[] = [];
  category: WishHistoryCategory = WishHistoryCategory.FiveStarAvatar;
  keyword: string = '';
  selectedId: number = 0;
  loading: boolean = false;
  loaded: boolean = false;
  message: string = '';
  private attached: boolean = false;
  private sequence: number = 0;

  activate(): void { this.attached = true; this.sequence++; this.loading = false; }
  invalidate(): void { this.attached = false; this.sequence++; }

  async load(now: number = Date.now()): Promise<boolean> {
    if (!this.attached) { return false; }
    const sequence: number = ++this.sequence;
    this.loading = true;
    this.message = '';
    try {
      const result: WishHistorySnapshot = await WishHistoryService.load(now);
      if (!this.current(sequence)) { return false; }
      this.snapshot = result;
      this.applyFilter();
      if (!result.metadataAvailable) {
        this.message = '本地祈愿元数据为空或无法读取，请在设置中检查游戏数据后重启应用';
      }
      this.loaded = true;
      return true;
    } catch (error) {
      if (!this.current(sequence)) { return false; }
      this.snapshot = new WishHistorySnapshot();
      this.items = [];
      this.selectedId = 0;
      this.message = '无法读取本地祈愿元数据，请重试';
      this.loaded = true;
      return true;
    } finally {
      if (this.current(sequence)) { this.loading = false; }
    }
  }

  setFilter(category: WishHistoryCategory, keyword: string): void {
    this.category = category;
    this.keyword = keyword;
    this.applyFilter();
  }

  select(id: number): void {
    this.selectedId = this.items.some((item: WishHistoryItem): boolean => item.id === id) ? id : 0;
  }

  selected(): WishHistoryItem | undefined {
    return this.items.find((item: WishHistoryItem): boolean => item.id === this.selectedId);
  }

  private current(sequence: number): boolean { return this.attached && this.sequence === sequence; }
  private applyFilter(): void {
    this.items = WishHistoryService.filter(this.snapshot.items, this.category, this.keyword);
    if (!this.items.some((item: WishHistoryItem): boolean => item.id === this.selectedId)) { this.selectedId = 0; }
  }
}
