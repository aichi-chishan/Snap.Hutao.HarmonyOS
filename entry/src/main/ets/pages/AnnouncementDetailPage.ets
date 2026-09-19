/**
 * AnnouncementDetailPage.ets（@Entry）
 * 公告详情：Web 组件渲染完整 HTML 正文（对齐 Windows AnnouncementWebView2ContentProvider.GenerateHtml）：
 * - 剥离 vertical-align 内联样式、rem 尺寸放大 10 倍（米哈游正文按移动端 rem 排版）
 * - 深色模式按 Windows DarkLightReverts 表反色
 * - 正文顶部 banner 图 + 标题
 * - baseUrl 用 https 米游社域，避免 data: 文档源下图片加载受 CORS 限制
 * getAnnContent 失败时回退提示 + 「打开原文」（官方页面）。
 */
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AnnouncementDetailParams } from '../model/RouteParams';
import { AnnouncementService } from '../service/AnnouncementService';
import { Logger } from '../common/Logger';

const TAG: string = 'AnnDetail';

/** 深色模式反色表（对齐 Windows DarkLightReverts） */
const DARK_LIGHT_REVERTS: string[][] = [
  ['color:rgba(0,0,0,1)', 'color:rgba(255,255,255,1)'],
  ['color:rgba(17,17,17,1)', 'color:rgba(238,238,238,1)'],
  ['color:rgba(51,51,51,1)', 'color:rgba(204,204,204,1)'],
  ['color:rgba(57,59,64,1)', 'color:rgba(198,196,191,1)'],
  ['color:rgba(73,73,73,1)', 'color:rgba(182,182,182,1)'],
  ['color:rgba(85,85,85,1)', 'color:rgba(170,170,170,1)'],
  ['background-color: rgb(255, 215, 185)', 'background-color: rgb(0,40,70)'],
  ['background-color: rgb(254, 245, 231)', 'background-color: rgb(1,40,70)'],
  ['background-color:rgb(244, 244, 245)', 'background-color:rgba(11, 11, 10)'],
];

@Entry
@Component
struct AnnouncementDetailPage {
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('isDarkMode') @Watch('onDarkChanged') isDark: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  @State title: string = '公告详情';
  /** 渲染就绪的完整 HTML（内容拉取成功后置位） */
  @State htmlReady: boolean = false;
  @State html: string = '';
  @State isLoading: boolean = true;
  /** 官方原文链接（Web 兜底） */
  @State officialUrl: string = '';
  /** Web 模式开关（打开原文时切换） */
  @State showWeb: boolean = false;
  @State webUrl: string = '';
  private annId: number = 0;
  private banner: string = '';
  /** 正文滚动区视口高度（vp，onAreaChange 读取；Web 模式按它自适应） */
  @State bodyAreaH: number = 0;
  /** 正文滚动区底部内边距（与下方 Column.padding bottom 一致，Web 高度需扣除） */
  private static readonly BODY_BOTTOM_PAD: number = 24;

  aboutToAppear(): void {
    const params = router.getParams() as AnnouncementDetailParams;
    this.title = params?.title ?? '公告详情';
    this.annId = params?.annId ?? 0;
    this.banner = params?.banner ?? '';
    // 备用外链优先（外部卡片直接跳原文），否则用 annId 拼米游社文章页
    this.officialUrl = params?.url && params.url.length > 0
      ? params.url
      : (this.annId > 0 ? `https://www.miyoushe.com/ys/article/${this.annId}` : '');
    this.loadAndRender();
  }

  /** 深浅色切换：正文重新生成（Windows OnActualThemeChanged 同款行为） */
  onDarkChanged(): void {
    if (this.htmlReady && this.lastContent.length > 0) {
      this.html = AnnouncementDetailPage.buildDocument(this.lastContent, this.title, this.banner, this.isDark);
    }
  }

  /** 原始正文缓存（主题切换重排时复用，避免重复请求） */
  private lastContent: string = '';

  async loadAndRender(): Promise<void> {
    this.isLoading = true;
    if (this.annId > 0) {
      try {
        const content: string = await AnnouncementService.getInstance().fetchContent(this.annId, 'cn_gf01', 60);
        if (content.length > 0) {
          this.lastContent = content;
          this.html = AnnouncementDetailPage.buildDocument(content, this.title, this.banner, this.isDark);
          this.htmlReady = true;
          Logger.info(TAG, `rendered html len=${content.length}`);
        }
      } catch (e) {
        Logger.warn(TAG, `fetch content fail ${(e as Error).message}`);
      }
    }
    // 官方原文链接兜底（loadAndRender 中未被备用外链覆盖时）
    if (this.officialUrl.length === 0 && this.annId > 0) {
      this.officialUrl = `https://www.miyoushe.com/ys/article/${this.annId}`;
    }
    this.isLoading = false;
  }

  /**
   * 生成完整 HTML 文档（对齐 Windows GenerateHtml）：
   * style 剥离 + rem 放大 + 深色反色 + banner 顶部展示
   */
  private static buildDocument(content: string, title: string, banner: string, isDark: boolean): string {
    let c: string = content;
    // 剥离 vertical-align:middle 内联样式（Windows StyleRegex 意图）
    c = c.replace(/\s?style="[^"]*vertical-align:middle;"/gi, '');
    // rem 尺寸放大 10 倍（Windows RemRegex → calc($0 * 10)；$& 为 JS 整匹配）
    c = c.replace(/[0-9]+\.[0-9]+rem/g, 'calc($& * 10)');
    // 深色模式反色
    if (isDark) {
      for (let i = 0; i < DARK_LIGHT_REVERTS.length; i++) {
        c = c.split(DARK_LIGHT_REVERTS[i][0]).join(DARK_LIGHT_REVERTS[i][1]);
      }
    }
    const bodyColor: string = isDark ? 'color:rgba(255,255,255,1)' : 'color:rgba(0,0,0,1)';
    const bannerPart: string = banner.length > 0 ? `<img src="${banner}"/>` : '';
    return `<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title}</title>
<style>
  body::-webkit-scrollbar { display: none; }
  img { border: none; vertical-align: middle; width: 100%; }
</style>
</head>
<body style="${bodyColor}; background-color: transparent;">
<h3>${title}</h3>
${bannerPart}
<br>
${c}
</body>
</html>`;
  }

  /** 打开官方原文（Web 兜底）：本页切换为 Web 模式 */
  openOfficial(): void {
    if (this.officialUrl.length > 0) {
      this.showWeb = true;
      this.webUrl = this.officialUrl;
    }
  }

  /** Web 兜底高度：正文区视口高扣除底部 padding 与 Column 间距。
   *  未测量（首帧）前退回 600（原写死值，保证不闪）；下限 240 防止极窄横屏下压没内容。
   *  高度跟随窗口/分屏变化实时更新；Web 组件内部自带滚动，故给足高度不破坏查看完整原文。 */
  webHeight(): number {
    if (this.bodyAreaH <= 0) {
      return 600;
    }
    const h: number = this.bodyAreaH - AnnouncementDetailPage.BODY_BOTTOM_PAD - 10;
    return h > 240 ? h : 240;
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
              // 按正文区视口高度自适应（手机约 700-800vp 视口减去 header，写死 600 会超出；
              // 平板偏矮）。Web 组件自带内部滚动，给足高度后仍能查看完整原文。
              .height(this.webHeight())
          } else if (this.htmlReady) {
            Web({ src: 'about:blank', controller: this.controller })
              .javaScriptAccess(true)
              .darkMode(this.isDark ? WebDarkMode.On : WebDarkMode.Off)
              .forceDarkAccess(this.isDark)
              .width('100%')
              .height(this.webHeight())
              .onControllerAttached(() => {
                // loadData 必须在 controller 就绪后调用（17100001）；baseUrl 用 https 域
                // 避免 data: 文档源下远程图片被 CORS 拦截
                try {
                  this.controller.loadData(this.html, 'text/html', 'UTF-8',
                    'https://www.miyoushe.com/', 'https://www.miyoushe.com/');
                } catch (e) {
                  Logger.warn(TAG, `loadData fail ${(e as Error).message}`);
                }
              })
          } else {
            Column({ space: 10 }) {
              Text('该公告正文暂不可用，可点击右上角「打开原文」查看官方页面。')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding({ top: 60, bottom: 60 })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      // 读正文滚动区自身高度（视口高，由 layoutWeight 决定，与内容无关，不会形成布局回环）
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.bodyAreaH = Number(newValue.height);
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
