import { router } from '@kit.ArkUI';
import { WishHistoryCategory, WishHistoryItem, WishHistoryOccurrence, WishHistoryPool,
  WishHistoryWikiParams } from '../model/WishHistory';
import { WishHistoryViewModel } from '../viewmodel/WishHistoryViewModel';
import { WishHistoryService } from '../service/WishHistoryService';
import { CachedImageService } from '../service/CachedImageService';
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';
import { MetaIcon } from '../components/MetaIcon';
import { EmptyState } from '../components/EmptyState';
import { SimpleDataSource } from '../components/SimpleDataSource';
import { CardSurfaceModifier } from '../common/UiSurface';

/** 期次横幅图缓存命中（url → 沙盒本地路径） */
class WishBannerPath {
  url: string = '';
  path: string = '';
}

@Entry
@Component
export struct WishHistoryPage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('isDarkMode') isDark: boolean = false;
  @State vm: WishHistoryViewModel = new WishHistoryViewModel();
  @State isWide: boolean = false;
  @State selected: WishHistoryItem | undefined = undefined;
  @State bannerPaths: WishBannerPath[] = [];
  private source: SimpleDataSource<WishHistoryItem> = new SimpleDataSource<WishHistoryItem>([]);
  private historySource: SimpleDataSource<WishHistoryOccurrence> = new SimpleDataSource<WishHistoryOccurrence>([]);
  private categoryOptions: SelectOption[] = [
    { value: '五星角色' }, { value: '四星角色' }, { value: '五星武器' }, { value: '四星武器' }
  ];
  private attached: boolean = false;
  private pageSequence: number = 0;
  private refreshTimer: number = -1;

  aboutToAppear(): void { this.activate(); }
  aboutToDisappear(): void { this.detach(); }
  onPageShow(): void { this.activate(); }
  onPageHide(): void { this.detach(); }

  private activate(): void {
    if (this.attached) { return; }
    this.attached = true;
    this.vm.activate();
    this.reload();
    // Rebuild against the current clock so starts/ends change without navigation or networking.
    this.refreshTimer = setInterval(() => {
      if (this.attached && !this.vm.loading) { this.reload(); }
    }, 60000);
  }

  private detach(): void {
    this.attached = false;
    this.pageSequence++;
    this.vm.invalidate();
    if (this.refreshTimer >= 0) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
  }

  private async reload(): Promise<void> {
    if (!this.attached) { return; }
    const sequence: number = ++this.pageSequence;
    const accepted: boolean = await this.vm.load();
    if (accepted && this.attached && sequence === this.pageSequence) { this.syncSources(); }
  }

  private syncSources(): void {
    this.selected = this.vm.selected();
    this.source.notifyDataReload(this.vm.items);
    this.historySource.notifyDataReload(this.selected?.histories ?? []);
    this.preloadBanners(this.selected);
  }

  /**
   * 预载选中物品的期次横幅到沙盒缓存（对齐 Windows CountdownHistory.Banner）：
   * 完成后整体替换 @State 数组触发行补绘；失败留空则该行不显示横幅。
   * 与祈愿历史 Tab 共享同一 URL 缓存。
   */
  private preloadBanners(item: WishHistoryItem | undefined): void {
    if (item === undefined) { return; }
    const sequence: number = this.pageSequence;
    const known: Set<string> = new Set<string>();
    for (const cached of this.bannerPaths) {
      known.add(cached.url);
    }
    const jobs: Promise<WishBannerPath | undefined>[] = [];
    for (const history of item.histories) {
      for (const pool of history.pools) {
        if (pool.banner.length === 0 || known.has(pool.banner)) { continue; }
        known.add(pool.banner);
        const url: string = pool.banner;
        jobs.push(CachedImageService.fetchToCache(url).then((p: string): WishBannerPath | undefined => {
          if (!this.attached || sequence !== this.pageSequence || p.length === 0) { return undefined; }
          const hit: WishBannerPath = new WishBannerPath();
          hit.url = url;
          hit.path = p;
          return hit;
        }));
      }
    }
    if (jobs.length === 0) { return; }
    Promise.all(jobs).then((loaded: (WishBannerPath | undefined)[]) => {
      const snapshot: WishBannerPath[] = this.bannerPaths.slice();
      let added: number = 0;
      for (const entry of loaded) {
        if (entry !== undefined) {
          snapshot.push(entry);
          added++;
        }
      }
      if (added === 0) { return; }
      this.bannerPaths = snapshot;
    }).catch(() => {
    });
  }

  /** 横幅 URL → 本地缓存路径（未命中返回空串） */
  private bannerPathOf(url: string): string {
    for (let i = 0; i < this.bannerPaths.length; i++) {
      if (this.bannerPaths[i].url === url) {
        return this.bannerPaths[i].path;
      }
    }
    return '';
  }

  private filter(category: number, keyword: string): void {
    if (category < 0 || category > 3) { return; }
    this.vm.setFilter(category as WishHistoryCategory, keyword);
    this.syncSources();
  }

  private select(item: WishHistoryItem): void {
    this.vm.select(item.id);
    this.syncSources();
  }

  private clearSelection(): void { this.vm.select(0); this.syncSources(); }

  private openWiki(): void {
    const item: WishHistoryItem | undefined = this.selected;
    if (!this.attached || item === undefined || !item.known) { return; }
    const params: WishHistoryWikiParams = { itemId: item.id };
    router.pushUrl({ url: item.iconCategory === 'AvatarIcon' ? 'pages/WikiAvatarPage' : 'pages/WikiWeaponPage',
      params: params }).catch(() => {
      if (this.attached) { this.getUIContext().getPromptAction().showToast({ message: '无法打开图鉴，请稍后重试' }); }
    });
  }

  private metadataText(): string {
    const count: number = this.vm.snapshot.startedEventCount;
    if (count === 0) { return '离线元数据 · 不需要登录或个人抽卡记录'; }
    return `本地元数据：${WishHistoryService.dateText(this.vm.snapshot.earliestFrom)} 至 ${WishHistoryService.dateText(this.vm.snapshot.latestTo)} · ${count} 个已开始卡池`;
  }

  private ignoredText(): string {
    const invalid: number = this.vm.snapshot.ignoredInvalidEvents;
    const future: number = this.vm.snapshot.ignoredFutureEvents;
    const unknown: number = this.vm.snapshot.unknownItemCount;
    const ids: number = this.vm.snapshot.ignoredItemIds;
    return `未开始 ${future} 期不计入 · 无效期次 ${invalid} · 无效物品 ${ids} · 未知名称 ${unknown} 项`;
  }

  private latestPeriod(item: WishHistoryItem): string {
    const pool: WishHistoryPool | undefined = item.histories[0]?.pools[0];
    return pool === undefined ? '期次未知' : WishHistoryService.periodText(pool);
  }

  @Builder
  controls() {
    Column({ space: 8 }) {
      Select(this.categoryOptions)
        .selected(this.vm.category)
        .value(this.categoryOptions[this.vm.category].value)
        .height(44)
        .width('100%')
        .fontColor($r('app.color.text_primary'))
        .attributeModifier(new CardSurfaceModifier())
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('筛选五星角色、四星角色、五星武器或四星武器')
        .onSelect((index: number) => { this.filter(index, this.vm.keyword); })
      Search({ value: this.vm.keyword, placeholder: '搜索名称或物品 ID' })
        .height(44)
        .maxLength(80)
        .fontColor($r('app.color.text_primary'))
        .attributeModifier(new CardSurfaceModifier())
        .onChange((value: string) => { this.filter(this.vm.category, value); })
      Text(`距上次 UP 结束最久优先 · ${this.vm.items.length} 项`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }.width('100%')
  }

  @Builder
  itemRow(item: WishHistoryItem) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        MetaIcon({ category: item.iconCategory, name: item.icon, iconSize: 48, remoteFallback: false })
        Column({ space: 5 }) {
          Text(item.name).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).maxLines(2)
          Text(WishHistoryService.countdown(item, this.vm.snapshot.asOf))
            .fontSize(13)
            .fontColor(WishHistoryService.ongoing(item, this.vm.snapshot.asOf)
              ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
          Text(`${this.latestPeriod(item)} · ${item.histories.length} 次 UP`)
            .fontSize(12).fontColor($r('app.color.text_secondary'))
          Text(`最近结束：${WishHistoryService.dateText(item.lastTime)}`)
            .fontSize(12).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding(12)
    }
    .width('100%')
    .constraintSize({ minHeight: 80 })
    .borderRadius(12)
    .backgroundColor(this.vm.selectedId === item.id ? $r('app.color.app_primary_bg') : $r('app.color.card_surface'))
    .border({ width: 1, color: this.vm.selectedId === item.id ? $r('app.color.app_primary') : $r('app.color.card_stroke') })
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText(`${item.name}，${WishHistoryService.countdown(item, this.vm.snapshot.asOf)}，查看 ${item.histories.length} 次 UP 历史`)
    .onClick(() => { this.select(item); })
  }

  @Builder
  itemList() {
    Column({ space: 10 }) {
      this.controls()
      if (this.vm.items.length === 0) {
        EmptyState({ text: this.vm.keyword.trim().length > 0 ? '没有匹配的名称或 ID' : '该分类暂无已开始的 UP 记录' })
      } else {
        List({ space: 8 }) {
          LazyForEach(this.source, (item: WishHistoryItem) => {
            ListItem() { this.itemRow(item) }
          }, (item: WishHistoryItem): string => `${item.id}_${this.vm.snapshot.asOf}_${this.vm.selectedId === item.id}`)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).cachedCount(5)
      }
    }.width('100%').height('100%')
  }

  @Builder
  historyRow(history: WishHistoryOccurrence) {
    Column({ space: 8 }) {
      Text(`${WishHistoryService.dateText(history.from)} 至 ${WishHistoryService.dateText(history.to)}`)
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      ForEach(history.pools, (pool: WishHistoryPool) => {
        Column({ space: 3 }) {
          // 期次横幅图（对齐 Windows CountdownHistoryTemplate：横幅 + 深色遮罩，文字置下）
          if (pool.banner.length > 0 && this.bannerPathOf(pool.banner).length > 0) {
            Stack() {
              Image(`file://${this.bannerPathOf(pool.banner)}`)
                .width('100%')
                .height(118)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
              if (this.isDark) {
                Column()
                  .width('100%')
                  .height(118)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.wallpaper_mask'))
              }
            }.width('100%')
          }
          Text(pool.name.length > 0 ? pool.name : '未命名卡池')
            .fontSize(14).fontColor($r('app.color.text_primary'))
          Text(`${WishHistoryService.periodText(pool)} · ${WishHistoryService.poolTypeText(pool.type)}`)
            .fontSize(12).fontColor($r('app.color.text_secondary'))
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (pool: WishHistoryPool): string => `${pool.type}_${pool.version}_${pool.order}_${pool.name}_${this.bannerPathOf(pool.banner).length > 0}`)
      if (history.pools.length > 1) {
        Text(`同期 ${history.pools.length} 个卡池，UP 次数计为 1 次`)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
      .borderRadius(12).attributeModifier(new CardSurfaceModifier())
      .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  historyDetail() {
    Column({ space: 12 }) {
      if (this.selected !== undefined) {
        Row({ space: 10 }) {
          if (!this.isWide) {
            Button('返回列表').height(44).hoverEffect(HoverEffect.Highlight)
              .fontColor($r('app.color.app_primary_text')).backgroundColor($r('app.color.app_primary_bg'))
              .onClick(() => { this.clearSelection(); })
          }
          Text(this.selected.name).fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(2)
        }.width('100%')
        Text(WishHistoryService.countdown(this.selected, this.vm.snapshot.asOf))
          .fontSize(14).fontColor($r('app.color.app_primary_text')).width('100%')
        Text(`${this.selected.histories.length} 次 UP · 相同物品在相同起止日期的卡池合并计数`)
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        if (this.selected.known) {
          Button(this.selected.iconCategory === 'AvatarIcon' ? '打开角色图鉴' : '打开武器图鉴')
            .height(44).width('100%').hoverEffect(HoverEffect.Highlight)
            .fontColor($r('app.color.app_primary_text')).backgroundColor($r('app.color.app_primary_bg'))
            .onClick(() => { this.openWiki(); })
        } else {
          Text('本地尚无该物品资料，保留原始 ID；更新游戏数据后可查看名称和图鉴')
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        }
        List({ space: 10 }) {
          LazyForEach(this.historySource, (history: WishHistoryOccurrence) => {
            ListItem() { this.historyRow(history) }
          }, (history: WishHistoryOccurrence): string => `${this.vm.selectedId}_${history.from}_${history.to}_${this.vm.snapshot.asOf}`)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).cachedCount(5)
      } else {
        EmptyState({ text: '选择角色或武器，查看历次 UP 卡池' })
      }
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column({ space: 10 }) {
        PageHeader({ title: '祈愿 UP 历史', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
          Button('刷新').height(44).enabled(!this.vm.loading).hoverEffect(HoverEffect.Highlight)
            .fontColor($r('app.color.app_primary_text')).backgroundColor($r('app.color.app_primary_bg'))
            .onClick(() => { this.reload(); })
        }
        Column({ space: 5 }) {
          Text(this.metadataText()).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Text('按卡池结束时间计算间隔，日期为东八区；仅展示已有记录，不预测未来复刻')
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          if (this.vm.loaded && this.vm.snapshot.metadataAvailable) {
            Text(this.ignoredText()).fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          }
        }.width('100%').padding({ left: 16, right: 16 })
        if (this.vm.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(40).height(40).color($r('app.color.app_primary'))
            Text('正在读取本地祈愿元数据').fontColor($r('app.color.text_secondary'))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.vm.message.length > 0) {
          Column({ space: 12 }) {
            Text(this.vm.message).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
            Button('重试').height(44).hoverEffect(HoverEffect.Highlight)
              .fontColor($r('app.color.app_primary_text')).backgroundColor($r('app.color.app_primary_bg'))
              .onClick(() => { this.reload(); })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(24)
        } else if (this.isWide) {
          Row({ space: 16 }) {
            Column() { this.itemList() }.width('42%').height('100%')
            Column() { this.historyDetail() }.layoutWeight(1).height('100%')
          }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
        } else if (this.selected !== undefined) {
          Column() { this.historyDetail() }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
        } else {
          Column() { this.itemList() }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
        }
      }.width('100%').height('100%')
    }.width('100%').height('100%')
      .onAreaChange((_old: Area, area: Area) => { this.isWide = Number(area.width) >= 840; })
  }
}
