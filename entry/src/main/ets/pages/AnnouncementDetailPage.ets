/**
 * AnnouncementDetailPage.ets（@Entry）
 * 公告详情：纯 ArkUI 渲染正文（剥离 HTML 标签的文本），不依赖 Web 组件加载时序。
 * getAnnContent 失败时提供"打开官方页面"按钮（Web 兜底，不阻塞正文）。
 */
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AnnouncementDetailParams } from '../model/RouteParams';
import { AnnouncementService } from '../service/AnnouncementService';
import { Logger } from '../common/Logger';

const TAG: string = 'AnnDetail';

@Entry
@Component
struct AnnouncementDetailPage {
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  @State title: string = '公告详情';
  @State bodyText: string = '';
  @State isLoading: boolean = true;
  @State hasContent: boolean = false;
  /** 官方原文链接（Web 兜底） */
  @State officialUrl: string = '';
  /** Web 模式开关（打开原文时切换） */
  @State showWeb: boolean = false;
  @State webUrl: string = '';
  private annId: number = 0;

  aboutToAppear(): void {
    const params = router.getParams() as AnnouncementDetailParams;
    this.title = params?.title ?? '公告详情';
    this.annId = params?.annId ?? 0;
    this.loadAndRender();
  }

  async loadAndRender(): Promise<void> {
    this.isLoading = true;
    if (this.annId > 0) {
      try {
        const html: string = await AnnouncementService.getInstance().fetchContent(this.annId, 'cn_gf01', 60);
        if (html.length > 0) {
          const text: string = AnnouncementDetailPage.stripHtml(html);
          if (text.length > 0) {
            this.bodyText = text;
            this.hasContent = true;
            Logger.info(TAG, `rendered text len=${text.length}`);
          }
        }
      } catch (e) {
        Logger.warn(TAG, `fetch content fail ${(e as Error).message}`);
      }
    }
    // 官方原文链接（米游社文章页，用于"打开原文"）
    this.officialUrl = this.annId > 0 ? `https://www.miyoushe.com/ys/article/${this.annId}` : '';
    if (this.bodyText.length === 0) {
      this.bodyText = '该公告正文暂不可用，可点击下方「打开原文」查看官方页面。';
    }
    this.isLoading = false;
  }

  /** 剥离 HTML 标签与样式，保留正文文本（含换行） */
  private static stripHtml(html: string): string {
    let s: string = html;
    // 去除 style/script 块
    s = s.replace(/<style[\s\S]*?<\/style>/gi, '');
    s = s.replace(/<script[\s\S]*?<\/script>/gi, '');
    // 块级标签转换行
    s = s.replace(/<(br|p|div|li|h1|h2|h3|h4|tr|img)[^>]*>/gi, '\n');
    // 剩余标签去除
    s = s.replace(/<[^>]+>/g, '');
    // 空格实体与连续换行整理
    s = s.replace(/&nbsp;/gi, ' ');
    s = s.replace(/&amp;/gi, '&');
    s = s.replace(/&lt;/gi, '<');
    s = s.replace(/&gt;/gi, '>');
    s = s.replace(/\n{3,}/g, '\n\n');
    s = s.replace(/[ \t]{2,}/g, ' ');
    return s.trim();
  }

  /** 打开官方原文（Web 兜底）：本页切换为 Web 模式 */
  openOfficial(): void {
    if (this.officialUrl.length > 0) {
      this.showWeb = true;
      this.webUrl = this.officialUrl;
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(26)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 10 })
          .layoutWeight(1)
        if (this.officialUrl.length > 0) {
          Text('打开原文')
            .fontSize(13)
            .fontColor($r('app.color.app_primary'))
            .onClick(() => {
              this.openOfficial();
            })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.topAvoidVp + 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.card_background'))

      Scroll() {
        Column({ space: 10 }) {
          if (this.isLoading) {
            Column({ space: 10 }) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color($r('app.color.app_primary'))
              Text('加载正文中...')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding({ top: 80, bottom: 60 })
          } else if (this.showWeb) {
            Web({ src: this.webUrl, controller: this.controller })
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .width('100%')
              .height(600)
          } else {
            Text(this.bodyText)
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .lineHeight(24)
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
