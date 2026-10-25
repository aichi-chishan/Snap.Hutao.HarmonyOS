/**
 * AccountInsightsPage.ets（@Entry）
 * 账号洞察（对齐 Windows AccountInsightsWindow）：本地历史聚合图表——
 * 祈愿/颂愿按月与按池、深境螺旋每期星数、幻想真境剧诗每期勋章、幽境危战按难度最快通关。
 * 只读本地库；入口在祈愿/深渊/剧诗/幽战/设置五处（对齐 Windows）。
 */
import { router } from '@kit.ArkUI';
import { AccountInsightsService } from '../service/AccountInsightsService';
import { AiAnalysisService, AiAnalysisResult } from '../service/AiAnalysisService';
import { InsightBundle, InsightDirection, InsightPoint, InsightSeries } from '../model/AccountInsights';
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';
import { EmptyState } from '../components/EmptyState';
import { CardSurfaceModifier } from '../common/UiSurface';

@Entry
@Component
export struct AccountInsightsPage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageLink('currentUid') @Watch('onUidChanged') currentUid: string = '';
  @State loading: boolean = false;
  @State bundle: InsightBundle | undefined = undefined;
  @State aiBusy: boolean = false;
  @State aiShow: boolean = false;
  @State aiContent: string = '';
  @State aiProviderName: string = '';
  private active: boolean = false;
  private sequence: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.reload();
  }

  aboutToDisappear(): void { this.active = false; }

  onPageShow(): void { this.reload(); }

  onUidChanged(): void { this.reload(); }

  reload(): void {
    if (!this.active || this.loading || this.currentUid.length === 0) {
      return;
    }
    const sequence: number = ++this.sequence;
    this.loading = true;
    AccountInsightsService.getInstance().build(this.currentUid).then((bundle: InsightBundle): void => {
      if (this.active && sequence === this.sequence) {
        this.bundle = bundle;
        this.loading = false;
      }
    }).catch(() => {
      if (this.active && sequence === this.sequence) {
        this.loading = false;
      }
    });
  }

  /** 序列方向提示（↑ 越高越好 / ↓ 越低越好） */
  private static directionText(series: InsightSeries): string {
    if (series.direction === InsightDirection.HigherIsBetter) {
      return '↑ 越高越好';
    }
    if (series.direction === InsightDirection.LowerIsBetter) {
      return '↓ 越低越好';
    }
    return '';
  }

  /** 序列最大值（条形长度归一化；0 防除零） */
  private static maxValue(series: InsightSeries): number {
    let max: number = 0;
    for (const point of series.points) {
      if (point.value > max) {
        max = point.value;
      }
    }
    return max <= 0 ? 1 : max;
  }

  /** 数值格式（秒序列保留 1 位小数，其余整数） */
  private static valueText(series: InsightSeries, value: number): string {
    return series.unit === '秒' ? value.toFixed(1) : `${value}`;
  }

  /** AI 分析（双通道：系统 AI / 自定义 API，设置页可切换） */
  private runAiAnalysis(): void {
    if (this.aiBusy || this.currentUid.length === 0) {
      return;
    }
    const target: InsightBundle | undefined = this.bundle;
    if (target === undefined || target.series.length === 0) {
      this.aiShow = true;
      this.aiProviderName = '';
      this.aiContent = '暂无可分析的数据：请先在祈愿/深渊/剧诗/幽战页面刷新记录';
      return;
    }
    this.aiBusy = true;
    this.aiShow = true;
    this.aiContent = '正在分析（匿名数据，不含 UID）…';
    const providerName: string = AiAnalysisService.provider() === 1 ? '自定义 API' : '系统 AI';
    this.aiProviderName = providerName;
    const json: string = AccountInsightsService.anonymousJson(target);
    AiAnalysisService.getInstance().analyze(json).then((result: AiAnalysisResult): void => {
      if (!this.active) {
        return;
      }
      this.aiProviderName = result.providerName.length > 0 ? result.providerName : providerName;
      this.aiContent = result.content;
      this.aiBusy = false;
    }).catch((e: Error): void => {
      if (!this.active) {
        return;
      }
      this.aiContent = `分析失败：${e.message}`;
      this.aiBusy = false;
    });
  }

  @Builder
  aiResultCard() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text('AI 分析')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.aiProviderName.length > 0) {
          Text(this.aiProviderName)
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
        }
        Blank()
        if (!this.aiBusy) {
          Text('关闭')
            .fontSize(12)
            .fontColor($r('app.color.app_primary'))
            .hoverEffect(HoverEffect.Highlight)
            .accessibilityText('关闭 AI 分析结果')
            .onClick(() => {
              this.aiShow = false;
            })
        }
      }
      .width('100%')
      if (this.aiBusy) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color($r('app.color.app_primary'))
          Text(this.aiContent)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
        }
        .width('100%')
      } else {
        Text(this.aiContent)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .lineHeight(18)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier())
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  seriesCard(series: InsightSeries) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        Text(series.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(`${series.metric}（${series.unit}）`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(AccountInsightsPage.directionText(series))
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      ForEach(series.points, (point: InsightPoint) => {
        Row({ space: 8 }) {
          Text(point.period)
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .width(84)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row() {
            Column()
              .width(`${Math.max(2, Math.round((point.value / AccountInsightsPage.maxValue(series)) * 100))}%`)
              .height(10)
              .borderRadius(5)
              .backgroundColor($r('app.color.app_primary'))
          }
          .layoutWeight(1)
          .width('100%')
          Text(AccountInsightsPage.valueText(series, point.value))
            .fontSize(10)
            .fontColor($r('app.color.text_primary'))
            .width(48)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .constraintSize({ minHeight: 20 })
      }, (point: InsightPoint): string => `${series.title}_${series.metric}_${series.difficulty ?? 0}_${point.period}_${point.value}`)
    }
    .width('100%')
    .padding(14)
    .borderRadius($r('app.float.card_radius'))
    .attributeModifier(new CardSurfaceModifier())
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column({ space: 10 }) {
        PageHeader({ title: '账号洞察', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
          Button('AI 分析').height(44).enabled(!this.aiBusy && this.currentUid.length > 0)
            .hoverEffect(HoverEffect.Highlight)
            .fontColor($r('app.color.on_accent')).backgroundColor($r('app.color.app_primary'))
            .accessibilityText('用 AI 分析账号历史')
            .onClick(() => { this.runAiAnalysis(); })
          Button('刷新').height(44).enabled(!this.loading && this.currentUid.length > 0)
            .hoverEffect(HoverEffect.Highlight)
            .fontColor($r('app.color.app_primary_text')).backgroundColor($r('app.color.app_primary_bg'))
            .onClick(() => { this.reload(); })
        }
        Text('本地历史聚合（祈愿/颂愿/深境螺旋/幻想真境剧诗/幽境危战），时间序列取最近 12 期；不发网络请求')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16 })

        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress().width(40).height(40).color($r('app.color.app_primary'))
            Text('正在聚合本地历史').fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.currentUid.length === 0) {
          Column({ space: 12 }) {
            EmptyState({ text: '登录并选择账号后查看洞察' })
            Button('前往登录').height(44).hoverEffect(HoverEffect.Highlight)
              .fontColor($r('app.color.app_primary_text')).backgroundColor($r('app.color.app_primary_bg'))
              .onClick(() => {
                router.pushUrl({ url: 'pages/LoginPage' }).catch(() => {
                });
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.bundle === undefined || this.bundle.series.length === 0) {
          Column() {
            EmptyState({ text: '暂无可用历史：先在祈愿/深渊/剧诗/幽战页面刷新数据' })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              if (this.aiShow) {
                this.aiResultCard()
              }
              if (this.bundle!.failedSources.length > 0) {
                Text(`部分数据源读取失败：${this.bundle!.failedSources.join('、')}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              ForEach(this.bundle!.series, (series: InsightSeries) => {
                this.seriesCard(series)
              }, (series: InsightSeries): string => `${series.title}_${series.metric}_${series.difficulty ?? 0}_${series.points.length}`)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 16 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
