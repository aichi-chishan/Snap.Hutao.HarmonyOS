/**
 * LedgerPage.ets（@Entry）
 * 旅行者札记（对齐 Windows TravelersDiary）：
 *   月份切换（optional_month）+ 当日收入 + 当月原石/摩拉（含上月环比）+ 分类来源条形明细。
 * 数据源：hk4e-api ys_ledger/monthInfo（CookieToken + DS Gen2/X4）。
 */
import { router } from '@kit.ArkUI';
import { Ledger } from '../model/Ledger';
import { LedgerIncomeSource } from '../model/Ledger';
import { LedgerViewModel } from '../viewmodel/LedgerViewModel';
import { AnnouncementContext } from '../model/RegionalContent';
import { RegionUtil } from '../common/Constants';
import { AppBackButton } from '../components/AppBackButton';
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';
import { NavIcon } from '../components/NavIcon';
import { Logger } from '../common/Logger';

const TAG: string = 'LedgerPage';

@Entry
@Component
export struct LedgerPage {
  @Prop embedMode: boolean = false;
  @StorageLink('currentUid') @Watch('onOwnerChanged') currentUid: string = '';
  @StorageLink('isLoggedIn') @Watch('onOwnerChanged') isLoggedIn: boolean = false;
  @StorageLink('currentUserId') @Watch('onOwnerChanged') currentUserId: number = 0;
  @State vm: LedgerViewModel = new LedgerViewModel();
  private attached: boolean = false;

  aboutToAppear(): void { this.attached = true; this.vm.activate(); this.reload(); }
  aboutToDisappear(): void { this.attached = false; this.vm.dispose(); }
  onOwnerChanged(): void { this.vm.clear(); if (this.attached) { this.reload(); } }
  reload(): void {
    if (!this.attached || !this.isLoggedIn || this.currentUid.length === 0) { return; }
    const uid: string = this.currentUid;
    const userId: number = this.currentUserId;
    this.vm.load(uid, userId, (): boolean => this.attached && this.currentUid === uid && this.currentUserId === userId && this.isLoggedIn);
  }
  regionLabel(): string {
    const region: string = RegionUtil.regionOfUid(this.currentUid);
    const index: number = AnnouncementContext.REGIONS.indexOf(region);
    return index < 0 ? '未知区服' : AnnouncementContext.REGION_NAMES[index];
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
      Text(this.vm.message.length > 0 ? this.vm.message : '加载中...')
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
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
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
      if (this.isLoggedIn && this.currentUid.length > 0) {
        Row({ space: 8 }) {
          Text(`${this.regionLabel()} · UID ${this.currentUid}`).fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          Button('刷新').height(44).hoverEffect(HoverEffect.Highlight).enabled(!this.vm.loading).onClick(() => this.reload())
        }.width('100%').padding({ left: 16, right: 16, top: 6 })
      }
      if (this.vm.stale) {
        Text(`上次数据 · 本次未刷新：${this.vm.message}`).fontSize(12).fontColor($r('app.color.danger')).padding(12)
      } else if (this.vm.loading && this.vm.ledger !== undefined) {
        Text('正在刷新札记…').fontSize(12).fontColor($r('app.color.text_secondary')).padding(8)
      }
      if (!this.isLoggedIn) {
        this.loginGuide()
      } else if (this.currentUid.length === 0) {
        Column({ space: 12 }) {
          NavIcon({ name: 'TravelersDiary', iconSize: 56 })
          Text('请先在「账号与数据」绑定角色')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Button('去「账号与数据」选择')
            .backgroundColor($r('app.color.app_primary'))
            .fontColor(Color.White)
            .onClick(() => {
              router.pushUrl({ url: 'pages/UserPage' });
            })
        }
        .width('100%')
        .padding({ top: 80, bottom: 80 })
      } else if (this.vm.loading && this.vm.ledger === undefined) {
        this.loadingView()
      } else if (this.vm.ledger === undefined) {
        Column({ space: 8 }) {
          Text(this.vm.message.length > 0 ? this.vm.message : '暂无札记数据')
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
            // 昵称 / UID（对齐 Windows TravelersDiaryCard 头部右侧 Uid）
            Row() {
              Blank()
              Text(this.vm.ledger.nickname.length > 0
                ? `${this.vm.ledger.nickname} · UID ${this.vm.ledger.uid}` : `UID ${this.vm.ledger.uid}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')

            // 月份切换（optional_month 提供可选月份，1-12 倒序）
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.vm.ledger.optionalMonth.length > 0 ? this.vm.ledger.optionalMonth : [this.vm.ledger.month],
                  (m: number) => {
                    Text(`${m} 月`)
                      .fontSize(12)
                      .fontColor(this.vm.month === m ? Color.White : $r('app.color.text_primary'))
                      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                      .hoverEffect(HoverEffect.Highlight)
                      .borderRadius(14)
                      .backgroundColor(this.vm.month === m ? $r('app.color.app_primary') : $r('app.color.card_inner_tint'))
                      .border({ width: 1, color: this.vm.month === m ? $r('app.color.app_primary') : $r('app.color.divider') })
                      .onClick(() => {
                        this.vm.month = m;
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
                Text(`◆ ${LedgerPage.fmt(this.vm.ledger.dayData.currentPrimogems)}`)
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
                Text(`◉ ${LedgerPage.fmt(this.vm.ledger.dayData.currentMora)}`)
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
            .backgroundColor($r('app.color.card_surface'))
            .border({ width: 1, color: $r('app.color.card_stroke') })

            // 当月原石
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Text('◆ 当月原石')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.app_primary'))
                Blank()
                Text(this.rateText(this.vm.ledger.monthData.primogemsRate))
                  .fontSize(12)
                  .fontColor(this.vm.ledger.monthData.primogemsRate >= 0 ? $r('app.color.danger') : $r('app.color.success'))
              }
              .width('100%')
              Text(LedgerPage.fmt(this.vm.ledger.monthData.currentPrimogems))
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(`上月 ${LedgerPage.fmt(this.vm.ledger.monthData.lastPrimogems)} · 等级 ${this.vm.ledger.monthData.currentPrimogemsLevel}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor($r('app.color.card_surface'))
            .border({ width: 1, color: $r('app.color.card_stroke') })

            // 当月摩拉
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Text('◉ 当月摩拉')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(this.rateText(this.vm.ledger.monthData.moraRate))
                  .fontSize(12)
                  .fontColor(this.vm.ledger.monthData.moraRate >= 0 ? $r('app.color.danger') : $r('app.color.success'))
              }
              .width('100%')
              Text(LedgerPage.fmt(this.vm.ledger.monthData.currentMora))
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(`上月 ${LedgerPage.fmt(this.vm.ledger.monthData.lastMora)}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor($r('app.color.card_surface'))
            .border({ width: 1, color: $r('app.color.card_stroke') })

            // 分类来源明细（group_by 条形）
            Column({ space: 8 }) {
              Text('当月来源明细')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              ForEach(this.vm.ledger.monthData.groupBy, (src: LedgerIncomeSource) => {
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
            .backgroundColor($r('app.color.card_surface'))
            .border({ width: 1, color: $r('app.color.card_stroke') })
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
    .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
  }
}
