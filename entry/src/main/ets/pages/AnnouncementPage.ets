/**
 * AnnouncementPage.ets（@Entry）
 * 游戏公告：动态类型页签（Windows Announcement Pivot style）+ 网格卡片，点击打开详情。
 */
import { router } from '@kit.ArkUI';
import { AnnouncementViewModel } from '../viewmodel/AnnouncementViewModel';
import { Announcement, AnnouncementGroup } from '../model/Announcement';
import { AnnouncementDetailParams } from '../model/RouteParams';
import { DateUtil } from '../common/DateUtil';
import { Loading } from '../components/Loading';
import { EmptyState } from '../components/EmptyState';
import { ErrorHint } from '../components/ErrorHint';
import { AppBackButton } from '../components/AppBackButton';

@Entry
@Component
export struct AnnouncementPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State vm: AnnouncementViewModel = new AnnouncementViewModel();

  aboutToAppear(): void {
    this.vm.load().then(() => {
    });
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1500 });
  }

  @Builder
  header() {
    Row() {
      if (!this.embedMode) {
        AppBackButton()
      }
      Text('游戏公告')
        .fontSize($r('app.float.page_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: this.embedMode ? 0 : 10 })
      Blank()
      Button('刷新')
        .fontSize(12)
        .height(28)
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          this.vm.load().then(() => {
          });
        })
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: (this.embedMode ? 0 : this.topAvoidVp) + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  categoryTabs() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.vm.groups, (g: AnnouncementGroup, idx: number) => {
          Text(g.label)
            .fontSize(13)
            .fontColor(this.vm.currentIndex === idx ? Color.White : $r('app.color.text_primary'))
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(12)
            .backgroundColor(this.vm.currentIndex === idx ? $r('app.color.app_primary') : $r('app.color.card_background'))
            .border({ width: 1, color: $r('app.color.divider') })
            .onClick(() => {
              this.vm.selectGroup(idx);
            })
        }, (g: AnnouncementGroup, idx: number) => `tab_${g.typeId}_${idx}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  /** 剩余天数角标（活动进行中显示"剩余 N 天"，已结束/未开始显示日期） */
  private static remainText(item: Announcement): string {
    const now: number = Date.now();
    if (item.startTime > 0) {
      const days: number = Math.ceil((item.startTime - now) / (24 * 3600 * 1000));
      if (days > 730) {
        return `${DateUtil.formatDate(item.startTime)}`;
      }
      if (days > 0) {
        return `${days} 天后开始`;
      }
      if (days > -730) {
        const left: number = Math.abs(days);
        return `${left} 天后结束`;
      }
    }
    return '';
  }

  @Builder
  announcementCard(item: Announcement) {
    Column({ space: 0 }) {
      // 顶部 banner 图区（无图时用渐变兜底）
      Stack({ alignContent: Alignment.TopStart }) {
        Image(item.banner.length > 0 ? item.banner : '')
          .width('100%')
          .height(110)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.app_primary_bg'))
          .onError((err: ImageError) => {
            // 加载失败：保持占位渐变
          })
        // 剩余天数角标
        if (AnnouncementPage.remainText(item).length > 0) {
          Text(AnnouncementPage.remainText(item))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius({ topLeft: 0, bottomLeft: 6, bottomRight: 0, topRight: 6 })
            .backgroundColor('#66000000')
        }
        // 类型徽章
        if (item.typeName.length > 0) {
          Text(item.typeName)
            .fontSize(9)
            .fontColor(Color.White)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .backgroundColor($r('app.color.notice_on'))
            .margin({ left: 8, top: 8 })
        }
      }
      .width('100%')
      // 标题/描述区
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (item.subtitle.length > 0) {
          Text(item.subtitle)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .padding(12)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.divider') })
    .clip(true)
    .onClick(() => {
      // 优先传 annId 拼官方详情页；无 annId 时用外链
      const params: AnnouncementDetailParams = {
        annId: item.id,
        title: item.title,
        url: item.url,
      };
      router.pushUrl({ url: 'pages/AnnouncementDetailPage', params: params });
    })
  }

  build() {
    Column() {
      this.header()
      this.categoryTabs()
      Scroll() {
        Column({ space: 10 }) {
          if (this.vm.loading) {
            Loading()
          } else if (this.vm.filtered.length === 0) {
            if (this.vm.message.length > 0) {
              ErrorHint({ text: this.vm.message, onRetry: () => {
                this.vm.load().then(() => {
                });
              } })
            } else {
              EmptyState({ icon: '📢', text: '暂无公告' })
            }
          } else {
            Grid() {
              ForEach(this.vm.filtered, (item: Announcement) => {
                GridItem() {
                  this.announcementCard(item)
                }
              }, (item: Announcement) => `ann_${item.id}`)
            }
            .columnsTemplate(this.vm.isWide ? '1fr 1fr 1fr' : '1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.vm.isWide = (newValue.width as number) >= 840;
    })
  }
}
