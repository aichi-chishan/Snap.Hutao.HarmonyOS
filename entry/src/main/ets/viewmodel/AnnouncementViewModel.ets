import { AnnouncementService } from '../service/AnnouncementService';
import { MiyoliveService } from '../service/MiyoliveService';
import { Announcement, AnnouncementGroup } from '../model/Announcement';
import { AnnouncementContext } from '../model/RegionalContent';
import { MiyoliveCode } from '../model/MiyoliveCode';
import { RegionUtil } from '../common/Constants';

@Observed
export class AnnouncementViewModel {
  groups: AnnouncementGroup[] = [];
  currentIndex: number = 0;
  filtered: Announcement[] = [];
  redeemCodes: MiyoliveCode[] = [];
  context: AnnouncementContext = new AnnouncementContext();
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  isWide: boolean = false;
  private generation: number = 0;
  private active: boolean = true;

  activate(): void { this.active = true; }
  dispose(): void { this.active = false; this.generation++; this.loading = false; }

  async load(context: AnnouncementContext = this.context, force: boolean = false): Promise<void> {
    if (!this.active) { return; }
    const next: AnnouncementContext = AnnouncementContext.create(context.region, context.language, context.level);
    const generation: number = ++this.generation;
    if (next.key() !== this.context.key()) { this.groups = []; this.filtered = []; this.currentIndex = 0; }
    this.context = next; this.redeemCodes = []; this.loading = true; this.message = '';
    if (!RegionUtil.isOverseaRegion(next.region)) { this.loadRedeemCodes(generation); }
    try {
      const groups: AnnouncementGroup[] = await AnnouncementService.getInstance().fetchGroups(next.region, next.level, next.language, force);
      if (!this.active || generation !== this.generation) { return; }
      const all: AnnouncementGroup = new AnnouncementGroup(); all.typeId = 0; all.label = '全部';
      const seen: Set<number> = new Set<number>();
      for (const group of groups) {
        for (const item of group.items) { if (!seen.has(item.id)) { seen.add(item.id); all.items.push(item); } }
      }
      all.items.sort((a: Announcement, b: Announcement): number => b.startTime - a.startTime);
      this.groups = [all].concat(groups);
      if (this.currentIndex >= this.groups.length) { this.currentIndex = 0; }
      this.applyFilter();
    } catch (e) {
      if (this.active && generation === this.generation) { this.message = (e as Error).message; }
    } finally {
      if (this.active && generation === this.generation) { this.loading = false; this.loaded = true; }
    }
  }

  selectGroup(index: number): void {
    if (!Number.isInteger(index) || index < 0 || index >= this.groups.length) { return; }
    this.currentIndex = index; this.applyFilter();
  }

  private async loadRedeemCodes(generation: number): Promise<void> {
    try {
      const codes: MiyoliveCode[] = await MiyoliveService.getInstance().fetchRedeemCodes();
      if (this.active && generation === this.generation && !RegionUtil.isOverseaRegion(this.context.region)) { this.redeemCodes = codes; }
    } catch (_) { /* Auxiliary CN-only public feed never changes the selected announcement result. */ }
  }

  private applyFilter(): void { this.filtered = this.groups[this.currentIndex]?.items.slice() ?? []; }
}
