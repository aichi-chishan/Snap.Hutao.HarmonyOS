/**
 * AccountInsightsPage.ets（@Entry）
 * 账号洞察（对齐 Windows AccountInsightsWindow）：本地历史聚合图表——
 * 祈愿/颂愿按月与按池、深境螺旋每期星数、幻想真境剧诗每期勋章、幽境危战按难度最快通关。
 * 只读本地库；入口在祈愿/深渊/剧诗/幽战/设置五处（对齐 Windows）。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { AccountInsightsService } from '../service/AccountInsightsService';
import { InsightBundle, InsightDirection, InsightPoint, InsightSeries } from '../model/AccountInsights';
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';
import { AiWorkspace } from '../components/AiWorkspace';
import { AppButtonModifier, CardSurfaceModifier, UiSurface } from '../common/UiSurface';
import { AiWorkspaceViewModel } from '../viewmodel/AiWorkspaceViewModel';

@Entry
@Component
export struct AccountInsightsPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('currentUid') @Watch('onUidChanged') currentUid: string = '';
  @State insightUid: string = '';
  @State workspace: AiWorkspaceViewModel = new AiWorkspaceViewModel();
  @State loading: boolean = false;
  @State bundle: InsightBundle | undefined = undefined;
  @State showAi: boolean = false;
  @State isWide: boolean = false;
  @State snapshot: string = '';
  private active: boolean = false;
  private visible: boolean = false;
  private invalidated: boolean = false;
  private sequence: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.insightUid = this.currentUid;
    this.workspace.load(this.insightUid, '');
    this.reload();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.visible = false;
    this.sequence++;
    this.workspace.leave();
  }

  onPageShow(): void {
    this.visible = true;
    if (this.invalidated) {
      this.closeRoute();
    } else {
      this.reload();
    }
  }

  onPageHide(): void { this.visible = false; }

  onUidChanged(): void {
    if (!this.active || this.invalidated || this.insightUid === this.currentUid) { return; }
    this.invalidated = true;
    this.sequence++;
    this.workspace.leave();
    this.insightUid = '';
    this.loading = false;
    this.bundle = undefined;
    this.snapshot = '';
    if (this.visible) { this.closeRoute(); }
  }

  private closeRoute(): void {
    if (this.embedMode) { return; }
    this.visible = false;
    this.getUIContext().getRouter().back();
  }

  reload(): void {
    if (!this.active || this.loading || this.insightUid.length === 0) {
      return;
    }
    const sequence: number = ++this.sequence;
    this.loading = true;
    AccountInsightsService.getInstance().build(this.insightUid).then((bundle: InsightBundle): void => {
      if (this.active && sequence === this.sequence) {
        this.bundle = bundle;
        if (bundle.series.length > 0) {
          this.snapshot = AccountInsightsService.anonymousJson(bundle);
          this.workspace.setSnapshot(this.snapshot, AccountInsightsService.anonymousJson(bundle, false));
        } else {
          this.snapshot = '';
          this.workspace.setSnapshot('', '');
        }
        this.loading = false;
      }
    }).catch(() => {
      if (this.active && sequence === this.sequence) {
        this.loading = false;
      }
    });
  }

  private async copySnapshot(): Promise<void> {
    if (this.snapshot.length === 0) { return; }
    let message: ResourceStr = $r('app.string.ui_account_insights_copied_json');
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.snapshot);
      await pasteboard.getSystemPasteboard().setData(data);
    } catch (_) {
      message = $r('app.string.ui_ai_copy_error');
    }
    if (this.active && !this.invalidated) {
      this.getUIContext().getPromptAction().showToast({ message, systemMaterial: UiSurface.dialogMaterial() });
    }
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
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  charts() {
    if (this.loading) {
      Column({ space: 10 }) {
        LoadingProgress().width(40).height(40).color($r('app.color.app_primary'))
        Text($r('app.string.ui_account_insights_loading')).fontColor($r('app.color.text_secondary'))
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else if (this.bundle === undefined || this.bundle.series.length === 0) {
      Column() {
        Text($r('app.string.ui_account_insights_no_records')).fontColor($r('app.color.text_secondary'))
      }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    } else {
      Button($r('app.string.ui_account_insights_copy_json'), { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(44).enabled(this.snapshot.length > 0)
        .onClick(() => { this.copySnapshot(); })
      Scroll() {
        Column({ space: 10 }) {
          if (this.bundle!.failedSources.length > 0) {
            Text(`部分数据源读取失败：${this.bundle!.failedSources.join('、')}`)
              .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
          }
          ForEach(this.bundle!.series, (series: InsightSeries) => {
            this.seriesCard(series)
          }, (series: InsightSeries): string => `${series.title}_${series.metric}_${series.difficulty ?? 0}_${series.points.length}`)
          if (this.bundle!.featuredChart !== undefined) {
            this.seriesCard(this.bundle!.featuredChart!)
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    }
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column({ space: 10 }) {
        PageHeader({ title: $r('app.string.ui_ai_insights'), embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
          if (!this.isWide && this.insightUid.length > 0) {
            Button(this.showAi ? $r('app.string.ui_history_charts') : $r('app.string.ui_ai_workspace'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44)
              .onClick(() => { this.showAi = !this.showAi; })
          }
          Button($r('app.string.common_refresh'), { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).enabled(!this.loading && this.insightUid.length > 0)
            .onClick(() => { this.reload(); })
        }
        if (this.insightUid.length === 0) {
          Column({ space: 12 }) {
            Text($r('app.string.ui_account_insights_no_account')).fontColor($r('app.color.text_secondary'))
            Button($r('app.string.ui_spiral_abyss_upload_record_homa_not_login_primary_button_text'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
              .height(44)
              .onClick(() => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/LoginPage' }).catch(() => {
                });
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Text(`UID ${this.insightUid}`).fontSize(12).fontColor($r('app.color.text_secondary'))
            .width('100%').padding({ left: 16, right: 16 })
          Row({ space: 12 }) {
            Column({ space: 10 }) {
              this.charts()
            }.layoutWeight(4).height('100%').alignItems(HorizontalAlign.Start)
              .visibility(this.isWide || !this.showAi ? Visibility.Visible : Visibility.None)
            Column() {
              AiWorkspace({ vm: this.workspace, hasSnapshot: this.snapshot.length > 0 })
            }.layoutWeight(6).height('100%').visibility(this.isWide || this.showAi ? Visibility.Visible : Visibility.None)
          }.width('100%').layoutWeight(1).padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old: Area, area: Area) => { this.isWide = Number(area.width) >= 840; })
  }
}
