/** 首页成就卡：每页对应一个本地档案，翻页浏览，点击打开成就管理。 */
import { DateUtil } from '../common/DateUtil';
import { Logger } from '../common/Logger';
import { Motion } from '../common/Motion';
import { CardSurfaceModifier } from '../common/UiSurface';
import { AchievementArchive } from '../model/AchievementData';
import { AchievementArchiveSummary, AchievementRecentCompletion, AchievementService } from '../service/AchievementService';
import { NavIcon } from './NavIcon';

@Component
export struct HomeAchievementCard {
  @StorageProp('achievementDataVersion') @Watch('onDataChanged') dataVersion: number = 0;
  @StorageProp('helpLocaleVersion') @Watch('onDataChanged') localeVersion: number = 0;
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('reduceMotion') reduceMotion: boolean = false;
  @Prop fillHeight: boolean = false;
  onTap: () => void = () => {};

  @State pages: AchievementArchiveSummary[] = [];
  @State pageIndex: number = 0;
  @State loaded: boolean = false;
  @State loadFailed: boolean = false;
  private attached: boolean = false;
  private loadSequence: number = 0;

  aboutToAppear(): void {
    this.attached = true;
    this.reload();
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.loadSequence++;
  }

  onDataChanged(): void {
    if (this.attached) { this.reload(); }
  }

  private static sameArchive(left?: AchievementArchive, right?: AchievementArchive): boolean {
    return left?.id === right?.id && left?.createdAt === right?.createdAt;
  }

  async reload(): Promise<void> {
    const sequence: number = ++this.loadSequence;
    const isCurrent: () => boolean = (): boolean => this.attached && sequence === this.loadSequence;
    try {
      const pages: AchievementArchiveSummary[] = await AchievementService.getArchiveSummaries(isCurrent);
      if (!isCurrent()) { return; }
      const selectedIndex: number = pages.findIndex((page: AchievementArchiveSummary): boolean => page.archive.isSelected);
      const previous: AchievementArchiveSummary | undefined =
        this.pages.find((page: AchievementArchiveSummary): boolean => page.archive.isSelected);
      // 内容刷新时保留用户翻到的档案，外部改选时跟随新的选中档案。
      let index: number = selectedIndex;
      if (HomeAchievementCard.sameArchive(previous?.archive, pages[selectedIndex]?.archive)) {
        const displayed: AchievementArchive | undefined = this.pages[this.pageIndex]?.archive;
        const retained: number = pages.findIndex((page: AchievementArchiveSummary): boolean =>
          HomeAchievementCard.sameArchive(page.archive, displayed));
        if (retained >= 0) { index = retained; }
      }
      this.pages = pages;
      this.pageIndex = Math.max(0, index);
      this.loadFailed = false;
    } catch (error) {
      if (!isCurrent()) { return; }
      this.loadFailed = true;
      Logger.warn('HomeAchievementCard', `读取成就档案失败: ${(error as Error).message}`);
    } finally {
      if (isCurrent()) { this.loaded = true; }
    }
  }

  private selectPage(index: number): void {
    if (index >= 0 && index < this.pages.length) { this.pageIndex = index; }
  }

  private openArchive(): void {
    if (this.attached) { this.onTap(); }
  }

  private static pageKey(page: AchievementArchiveSummary): string {
    const recent: string[] = page.recent.map((item: AchievementRecentCompletion): string =>
      `${item.entry.id}:${item.entry.name}:${item.timestamp}`);
    return `${page.archive.id}:${page.archive.createdAt}:${page.archive.name}:${page.stats.done}:${page.stats.total}:` +
      `${page.stats.primogemsEarned}:${page.stats.primogemsTotal}:${recent.join('|')}`;
  }

  @Builder
  archivePage(page: AchievementArchiveSummary) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Progress({ value: page.stats.done, total: Math.max(1, page.stats.total), type: ProgressType.Ring })
            .width(62).height(62).color($r('app.color.app_primary')).style({ strokeWidth: 5 })
          Column() {
            Text(`${page.stats.done}`).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text(`/ ${page.stats.total}`).fontSize(11).fontColor($r('app.color.text_secondary'))
          }
        }
        Column({ space: 5 }) {
          Text(`${page.stats.percent()}%`).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.app_primary_text'))
          Progress({ value: page.stats.done, total: Math.max(1, page.stats.total), type: ProgressType.Linear })
            .width('100%').color($r('app.color.app_primary')).backgroundColor($r('app.color.divider'))
          Text(`原石 ${page.stats.primogemsEarned} / ${page.stats.primogemsTotal}`)
            .fontSize(12).fontColor($r('app.color.text_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
      if (page.recent.length > 0) {
        Row({ space: 10 }) {
          ForEach(page.recent, (item: AchievementRecentCompletion) => {
            Column({ space: 2 }) {
              Text(item.entry.name).fontSize(13).fontColor($r('app.color.text_primary'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (item.timestamp > 0) {
                Text(DateUtil.formatTimestamp(item.timestamp * 1000).replace(/-/g, '.'))
                  .fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }, (item: AchievementRecentCompletion): string => String(item.entry.id))
        }.width('100%').alignItems(VerticalAlign.Top)
      }
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .padding({ bottom: this.pages.length > 1 ? 20 : 0 })
      .focusable(true).hoverEffect(HoverEffect.Highlight)
      .accessibilityDescription($r('app.string.ui_nav_achievement')).onClick(() => this.openArchive())
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        NavIcon({ name: 'Achievement', iconSize: 20 })
        Text($r('app.string.ui_nav_achievement')).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).maxLines(1)
        Text(this.pages[this.pageIndex]?.archive.name ?? '').fontSize(12).fontColor($r('app.color.app_primary_text'))
          .layoutWeight(1).textAlign(TextAlign.End).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').height(40).flexShrink(0).focusable(true).hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.openArchive())

      if (!this.loaded) {
        Row({ space: 8 }) {
          LoadingProgress().width(22).height(22).color($r('app.color.app_primary'))
          Text($r('app.string.common_loading')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.width('100%').height(this.fillHeight ? undefined : 84)
          .layoutWeight(this.fillHeight ? 1 : 0).justifyContent(FlexAlign.Center)
      } else if (this.pages.length === 0) {
        Text(this.loadFailed ? $r('app.string.common_error') : '创建成就档案')
          .fontSize(13).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
          .width('100%').height(this.fillHeight ? undefined : 84).layoutWeight(this.fillHeight ? 1 : 0)
          .focusable(true).hoverEffect(HoverEffect.Highlight).onClick(() => {
            if (this.loadFailed) { this.reload(); } else { this.openArchive(); }
          })
      } else {
        Swiper() {
          ForEach(this.pages, (page: AchievementArchiveSummary) => {
            this.archivePage(page)
          }, (page: AchievementArchiveSummary): string => HomeAchievementCard.pageKey(page))
        }
        .index(this.pageIndex).loop(false).disableSwipe(this.pages.length === 1)
        .indicator(this.pages.length > 1 ? new DotIndicator().itemWidth(6).itemHeight(6)
          .selectedItemWidth(16).selectedItemHeight(6).maxDisplayCount(7)
          .color($r('app.color.divider')).selectedColor($r('app.color.app_primary')) : false)
        .displayArrow(this.pages.length > 1, true)
        .duration(this.reduceMotion ? 0 : 240).curve(this.reduceMotion ? Curve.Linear : Motion.springFast())
        .effectMode(this.reduceMotion ? EdgeEffect.None : EdgeEffect.Spring)
        .onChange((index: number): void => this.selectPage(index))
        .width('100%').height(this.fillHeight ? undefined : (this.pages.length > 1 ? 132 : 110))
        .layoutWeight(this.fillHeight ? 1 : 0)
      }
    }.width('100%').height(this.fillHeight ? '100%' : undefined).padding(12).borderRadius(12)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
  }
}
