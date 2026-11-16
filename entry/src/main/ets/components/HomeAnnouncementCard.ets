import { Announcement, AnnouncementGroup, AnnouncementType } from '../model/Announcement';
import { NavIcon } from './NavIcon';
import { AppButtonModifier, CardSurfaceModifier } from '../common/UiSurface';

/** 首页官方公告分类与横幅。 */
@Component
export struct HomeAnnouncementCard {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @Prop @Watch('onGroupsChanged') groups: AnnouncementGroup[] = [];
  @Prop loaded: boolean = false;
  @State selectedTypeId: number = -1;
  @State contentWidth: number = 0;
  private readonly announcementScroller: Scroller = new Scroller();
  onTapAnnouncement: (item: Announcement) => void = (_item: Announcement): void => {};
  onTapMore: () => void = () => {};
  onRedeem: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.onGroupsChanged();
  }

  onGroupsChanged(): void {
    if (this.groups.length > 0 && !this.groups.some((group: AnnouncementGroup): boolean => group.typeId === this.selectedTypeId)) {
      this.selectedTypeId = this.groups[0].typeId;
    }
  }

  private selectedItems(): Announcement[] {
    const selected: AnnouncementGroup | undefined =
      this.groups.find((group: AnnouncementGroup): boolean => group.typeId === this.selectedTypeId) ?? this.groups[0];
    return selected?.items ?? [];
  }

  private selectCategory(typeId: number): void {
    if (typeId === this.selectedTypeId) { return; }
    if (this.selectedItems().length > 0) {
      this.announcementScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    }
    this.selectedTypeId = typeId;
  }

  private columns(): number {
    return this.contentWidth >= 1200 ? 4 : this.contentWidth >= 840 ? 2 : 1;
  }

  @Builder
  categoryTabs() {
    Scroll() {
      Row({ space: 3 }) {
        ForEach(this.groups, (group: AnnouncementGroup) => {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Column({ space: 5 }) {
              Text(group.label)
                .fontSize(14)
                .fontWeight(this.selectedTypeId === group.typeId ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.selectedTypeId === group.typeId ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
                .maxLines(1)
              Divider().width(34).strokeWidth(2)
                .color(this.selectedTypeId === group.typeId ? $r('app.color.app_primary') : Color.Transparent)
            }.justifyContent(FlexAlign.Center)
          }
          .height(44)
          .padding({ left: 8, right: 8 })
          .borderRadius(6)
          .backgroundColor(Color.Transparent)
          .accessibilitySelected(this.selectedTypeId === group.typeId)
          .accessibilityGroup(true)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.selectCategory(group.typeId))
        }, (group: AnnouncementGroup): string => `${group.typeId}_${group.label}`)
      }
    }
    .width(this.contentWidth >= 840 ? undefined : '100%')
    .layoutWeight(this.contentWidth >= 840 ? 1 : 0)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      if (this.contentWidth >= 840 && this.groups.length > 0) {
        this.categoryTabs()
      } else {
        NavIcon({ name: 'Announcement', iconSize: 20 })
        Text($r('app.string.ui_nav_announcements'))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }
      if (this.onRedeem !== undefined) {
        Button('兑换码', { type: ButtonType.Normal })
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .height(44)
          .onClick(() => { this.onRedeem?.(); })
      }
      Button('查看全部', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(44)
        .onClick(() => this.onTapMore())
    }
    .width('100%')
  }

  @Builder
  itemCard(item: Announcement) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column() {
        Stack({ alignContent: Alignment.BottomEnd }) {
          if (item.banner.length > 0) {
            Image(item.banner).width('100%').aspectRatio(1080 / 390).objectFit(ImageFit.Cover)
          } else {
            Stack() {
              NavIcon({ name: 'Announcement', iconSize: 36 })
            }.width('100%').aspectRatio(1080 / 390).backgroundColor($r('app.color.card_inner_tint'))
          }
          if (item.type === AnnouncementType.ACTIVITY && item.endTime > 0) {
            Text(HomeAnnouncementCard.formatDate(item.endTime))
              .fontSize(11).fontColor($r('app.color.image_foreground'))
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .backgroundColor($r('app.color.image_scrim')).borderRadius(5).margin(5)
          }
        }.width('100%')
        Column({ space: 4 }) {
          Text(item.subtitle || item.title).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).width('100%')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.subtitle.length > 0 && item.title !== item.subtitle) {
            Text(item.title).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }.width('100%').constraintSize({ minHeight: 58 }).padding(8).alignItems(HorizontalAlign.Start)
      }.width('100%')
    }
    .width('100%')
    .padding(0)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel, false))
    .border({ width: 1, radius: 8, color: $r('app.color.card_stroke') })
    .borderRadius(8)
    .clip(true)
    .accessibilityText(item.title)
    .accessibilityGroup(true)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onTapAnnouncement(item))
  }

  build() {
    Column({ space: 8 }) {
      this.header()
      if (this.contentWidth < 840 && this.groups.length > 0) {
        this.categoryTabs()
      }
      if (!this.loaded && this.groups.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress().width(16).height(16).color($r('app.color.app_primary'))
          Text($r('app.string.ui_common_loading')).fontSize(12).fontColor($r('app.color.text_secondary'))
        }.width('100%').padding({ top: 8, bottom: 8 })
      } else if (this.selectedItems().length === 0) {
        Text('暂无公告').fontSize(12).fontColor($r('app.color.text_secondary'))
          .width('100%').padding({ top: 8, bottom: 8 })
      } else {
        Scroll(this.announcementScroller) {
          GridRow({ columns: this.columns(), gutter: 8 }) {
            ForEach(this.selectedItems(), (item: Announcement) => {
              GridCol() { this.itemCard(item) }
            }, (item: Announcement): string => `${item.sourceRegion}_${item.sourceLanguage}_${item.sourceLevel}_${item.id}_` +
              `${item.type}_${item.subtitle}_${item.title}_${item.startTime}_${item.endTime}_${item.banner}`)
          }.width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: this.contentWidth >= 840 ? 380 : 330 })
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(8)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .onAreaChange((_old: Area, area: Area): void => { this.contentWidth = Number(area.width); })
  }

  private static formatDate(ms: number): string {
    const date: Date = new Date(ms);
    return `${date.getMonth() + 1}.${date.getDate()}`;
  }
}
