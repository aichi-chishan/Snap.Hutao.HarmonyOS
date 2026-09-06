/**
 * LedgerPage.ets（@Entry）
 * 旅行者札记（对齐 Windows TravelersDiary）：
 *   月份切换（optional_month）+ 当日收入 + 当月原石/摩拉（含上月环比）+ 分类来源条形明细。
 * 数据源：hk4e-api ys_ledger/monthInfo（CookieToken + DS Gen2/X4）。
 */
import { router } from '@kit.ArkUI';
import { Ledger } from '../model/Ledger';
import { LedgerIncomeSource } from '../model/Ledger';
import { LedgerService } from '../service/LedgerService';
import { AppBackButton } from '../components/AppBackButton';
import { PageHeader } from '../components/PageHeader';
import { NavIcon } from '../components/NavIcon';
import { Logger } from '../common/Logger';

const TAG: string = 'LedgerPage';

@Entry
@Component
export struct LedgerPage {
  @Prop embedMode: boolean = false;
  @StorageLink('currentUid') currentUid: string = '';
  @StorageLink('isLoggedIn') isLoggedIn: boolean = false;
  @State ledger: Ledger | undefined = undefined;
  @State loading: boolean = false;
  @State month: number = 0;
  @State message: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  reload(): void {
    this.loading = true;
    this.message = '';
    LedgerService.getInstance().fetchMonth(this.month, this.currentUid).then((l: Ledger) => {
      this.ledger = l;
      if (this.month === 0) {
        this.month = l.month > 0 ? l.month : new Date().getMonth() + 1;
      }
    }).catch((e: Error) => {
      this.message = e.message;
    }).finally(() => {
      this.loading = false;
    });
  }

  /** 环比文案（正=↑绿不利，负=↓）——原石收入涨为橙、跌为绿，对齐直观感受 */
  rateText(rate: number): string {
    if (rate > 0) {
      return `↑ ${rate}%`;
    }
    if (rate < 0) {
      return `↓ ${-rate}%`;
    }
    return '—';
  }

  /** 数字千分位 */
  static fmt(n: number): string {
    return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  @Builder
  loadingView() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color($r('app.color.app_primary'))
      Text(this.message.length > 0 ? this.message : '加载中...')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ top: 60, bottom: 60 })
  }

  @Builder
  loginGuide() {
    Column({ space: 12 }) {
      NavIcon({ name: 'TravelersDiary', iconSize: 56 })
      Text('登录后查看旅行者札记')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('札记记录每月原石与摩拉的获取明细')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Button('去登录')
        .backgroundColor($r('app.color.app_primary'))
        .fontColor(Color.White)
        .onClick(() => {
          router.pushUrl({ url: 'pages/LoginPage' });
        })
    }
    .width('100%')
    .padding({ top: 80, bottom: 80 })
  }

  build() {
    Column() {
      if (this.embedMode) {
        PageHeader({ title: '旅行者札记' })
      } else {
        Row({ space: 10 }) {
          AppBackButton()
          Text('旅行者札记')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Blank()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else if (this.loading && this.ledger === undefined) {
        this.loadingView()
      } else if (this.ledger === undefined) {
        Column({ space: 8 }) {
          Text(this.message.length > 0 ? this.message : '暂无札记数据')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Button('重试')
            .onClick(() => {
              this.reload();
            })
        }
        .width('100%')
        .padding({ top: 60, bottom: 60 })
      } else {
        Scroll() {
          Column({ space: 12 }) {
            // 月份切换（optional_month 提供可选月份，1-12 倒序）
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.ledger.optionalMonth.length > 0 ? this.ledger.optionalMonth : [this.ledger.month],
                  (m: number) => {
                    Text(`${m} 月`)
                      .fontSize(12)
                      .fontColor(this.month === m ? Color.White : $r('app.color.text_primary'))
                      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                      .borderRadius(14)
                      .backgroundColor(this.month === m ? $r('app.color.app_primary') : $r('app.color.card_background'))
                      .border({ width: 1, color: this.month === m ? $r('app.color.app_primary') : $r('app.color.divider') })
                      .onClick(() => {
                        this.month = m;
                        this.reload();
                      })
                  }, (m: number) => `lm_${m}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')

            // 当日收入
            Row({ space: 10 }) {
              Column({ space: 2 }) {
                Text('今日原石')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                Text(`◆ ${LedgerPage.fmt(this.ledger.dayData.currentPrimogems)}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.app_primary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              Column({ space: 2 }) {
                Text('今日摩拉')
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                Text(`◉ ${LedgerPage.fmt(this.ledger.dayData.currentMora)}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(12)
            .borderRadius(12)
            .backgroundColor($r('app.color.card_background'))
            .border({ width: 1, color: $r('app.color.divider') })

            // 当月原石
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Text('◆ 当月原石')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.app_primary'))
                Blank()
                Text(this.rateText(this.ledger.monthData.primogemsRate))
                  .fontSize(12)
                  .fontColor(this.ledger.monthData.primogemsRate >= 0 ? $r('app.color.danger') : $r('app.color.success'))
              }
              .width('100%')
              Text(LedgerPage.fmt(this.ledger.monthData.currentPrimogems))
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(`上月 ${LedgerPage.fmt(this.ledger.monthData.lastPrimogems)} · 等级 ${this.ledger.monthData.currentPrimogemsLevel}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor($r('app.color.card_background'))
            .border({ width: 1, color: $r('app.color.divider') })

            // 当月摩拉
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Text('◉ 当月摩拉')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(this.rateText(this.ledger.monthData.moraRate))
                  .fontSize(12)
                  .fontColor(this.ledger.monthData.moraRate >= 0 ? $r('app.color.danger') : $r('app.color.success'))
              }
              .width('100%')
              Text(LedgerPage.fmt(this.ledger.monthData.currentMora))
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(`上月 ${LedgerPage.fmt(this.ledger.monthData.lastMora)}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor($r('app.color.card_background'))
            .border({ width: 1, color: $r('app.color.divider') })

            // 分类来源明细（group_by 条形）
            Column({ space: 8 }) {
              Text('当月来源明细')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              ForEach(this.ledger.monthData.groupBy, (src: LedgerIncomeSource) => {
                Column({ space: 4 }) {
                  Row() {
                    Text(src.action)
                      .fontSize(12)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    Text(`${LedgerPage.fmt(src.num)} · ${src.percent}%`)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .width('100%')
                  Progress({
                    value: Math.max(1, src.percent),
                    total: 100,
                    type: ProgressType.Linear,
                  })
                    .width('100%')
                    .color($r('app.color.app_primary'))
                    .style({ strokeWidth: 6 })
                }
                .width('100%')
              }, (src: LedgerIncomeSource) => `src_${src.actionId}_${src.action}`)
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor($r('app.color.card_background'))
            .border({ width: 1, color: $r('app.color.divider') })
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
  }
}
