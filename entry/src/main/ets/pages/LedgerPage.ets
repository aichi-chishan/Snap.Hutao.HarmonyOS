import { LedgerIncomeSource } from '../model/Ledger';
import { incomeColor, LedgerIncomeRing } from '../components/LedgerIncomeRing';
import { LedgerViewModel } from '../viewmodel/LedgerViewModel';
import { RegionUtil } from '../common/Constants';
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';
import { NavIcon } from '../components/NavIcon';
import { ErrorHint } from '../components/ErrorHint';
import { Loading } from '../components/Loading';
import { AppButtonModifier, CardSurfaceModifier, SelectMaterialModifier } from '../common/UiSurface';

@Entry
@Component
export struct LedgerPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('currentUid') @Watch('onOwnerChanged') currentUid: string = '';
  @StorageProp('isLoggedIn') @Watch('onOwnerChanged') isLoggedIn: boolean = false;
  @StorageProp('currentUserId') @Watch('onOwnerChanged') currentUserId: number = 0;
  @Prop embedMode: boolean = false;
  @State vm: LedgerViewModel = new LedgerViewModel();
  @State isWide: boolean = false;
  private attached: boolean = false;

  aboutToAppear(): void {
    this.attached = true;
    this.vm.activate();
    this.reload();
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.vm.dispose();
  }

  onOwnerChanged(): void {
    this.vm.clear();
    this.reload();
  }

  reload(): void {
    if (!this.attached || !this.isLoggedIn || this.currentUid.length === 0) { return; }
    const uid: string = this.currentUid;
    const userId: number = this.currentUserId;
    this.vm.load(uid, userId, (): boolean => this.attached && this.isLoggedIn &&
      this.currentUid === uid && this.currentUserId === userId);
  }

  private monthOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '最新月份' }];
    for (const month of this.vm.availableMonths) {
      const option: SelectOption = { value: `${month} 月` };
      options.push(option);
    }
    return options;
  }

  private selectMonth(index: number): void {
    const month: number | undefined = index === 0 ? 0 : this.vm.availableMonths[index - 1];
    if (month === undefined || month === this.vm.month) { return; }
    this.vm.month = month;
    this.reload();
  }

  private accountLabel(): string {
    const region: string = RegionUtil.regionOfUid(this.currentUid);
    const server: string = region === 'cn_gf01' ? '天空岛' : (region === 'cn_qd01' ? '世界树' : '其他区服');
    const name: string = this.vm.ledger?.nickname ?? '';
    return `${name.length > 0 ? `${name} · ` : ''}${server} · UID ${this.currentUid}`;
  }

  private static rateText(rate: number | undefined): string {
    if (rate === undefined) { return '环比 —'; }
    if (rate > 0) { return `环比 ↑ ${rate}%`; }
    if (rate < 0) { return `环比 ↓ ${-rate}%`; }
    return '环比 0%';
  }

  private static rateColor(rate: number | undefined): Resource {
    if (rate === undefined || rate === 0) { return $r('app.color.text_secondary'); }
    return rate > 0 ? $r('app.color.success') : $r('app.color.danger');
  }

  private static fmt(amount: number): string {
    return amount.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }

  @Builder
  accountGuide() {
    Column({ space: 12 }) {
      NavIcon({ name: 'TravelersDiary', iconSize: 56 })
      Text(this.isLoggedIn ? $r('app.string.ui_account_insights_no_account') : $r('app.string.ui_settings_not_logged_in'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Button(this.isLoggedIn ? $r('app.string.ui_cultivation_navigate_action')
        : $r('app.string.ui_spiral_abyss_upload_record_homa_not_login_primary_button_text'), { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
        .height(44)
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: this.isLoggedIn ? 'pages/UserPage' : 'pages/LoginPage' });
        })
    }
    .width('100%')
    .padding({ top: 56, bottom: 56 })
  }

  @Builder
  summary() {
    Column({ space: 12 }) {
      if (this.vm.ledger?.dayData !== undefined) {
        Column({ space: 8 }) {
          Text((this.vm.ledger?.date.length ?? 0) > 0 ? (this.vm.ledger?.date ?? '') : $r('app.string.ui_travelers_diary_today'))
            .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          Row({ space: 12 }) {
            Text(`原石 ${LedgerPage.fmt(this.vm.ledger?.dayData?.currentPrimogems ?? 0)}`)
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.app_primary_text')).layoutWeight(1)
            Text(`摩拉 ${LedgerPage.fmt(this.vm.ledger?.dayData?.currentMora ?? 0)}`)
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%').padding(14).borderRadius(12)
        .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
        .border({ width: 1, color: $r('app.color.card_stroke') })
      }

      Column({ space: 10 }) {
        Text(`${this.vm.ledger?.month ?? 0} 月累计`)
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('原石').fontSize(12).fontColor($r('app.color.app_primary_text'))
            Text(LedgerPage.fmt(this.vm.ledger?.monthData.currentPrimogems ?? 0))
              .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text(`上月 ${LedgerPage.fmt(this.vm.ledger?.monthData.lastPrimogems ?? 0)}`)
              .fontSize(12).fontColor($r('app.color.text_secondary'))
            Text(LedgerPage.rateText(this.vm.ledger?.monthData.primogemsRate))
              .fontSize(12).fontColor(LedgerPage.rateColor(this.vm.ledger?.monthData.primogemsRate))
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1)
          Column({ space: 4 }) {
            Text('摩拉').fontSize(12).fontColor($r('app.color.text_primary'))
            Text(LedgerPage.fmt(this.vm.ledger?.monthData.currentMora ?? 0))
              .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
            Text(`上月 ${LedgerPage.fmt(this.vm.ledger?.monthData.lastMora ?? 0)}`)
              .fontSize(12).fontColor($r('app.color.text_secondary'))
            Text(LedgerPage.rateText(this.vm.ledger?.monthData.moraRate))
              .fontSize(12).fontColor(LedgerPage.rateColor(this.vm.ledger?.monthData.moraRate))
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1)
        }
        .alignItems(VerticalAlign.Top).width('100%')
        if ((this.vm.ledger?.monthData.currentPrimogemsLevel ?? 0) > 0) {
          Text(`原石收入等级 ${this.vm.ledger?.monthData.currentPrimogemsLevel ?? 0}`)
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        }
      }
      .width('100%').padding(14).borderRadius(12)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      .border({ width: 1, color: $r('app.color.card_stroke') })
    }
    .width('100%')
  }

  @Builder
  incomeBreakdown() {
    Column({ space: 10 }) {
      Text('当月原石来源')
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      if ((this.vm.ledger?.monthData.groupBy.length ?? 0) === 0) {
        Text(this.vm.ledger?.monthData.currentPrimogems === 0
          ? $r('app.string.ui_travelers_diary_no_income_source_hint') : $r('app.string.common_empty'))
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      } else {
        Stack({ alignContent: Alignment.Center }) {
          LedgerIncomeRing({ sources: this.vm.ledger?.monthData.groupBy ?? [] })
          Text(LedgerPage.fmt(this.vm.ledger?.monthData.currentPrimogems ?? 0))
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        }
        .width('100%').padding({ top: 4, bottom: 8 })
        ForEach(this.vm.ledger?.monthData.groupBy ?? [], (source: LedgerIncomeSource, index: number) => {
          Row({ space: 8 }) {
            Circle({ width: 8, height: 8 }).fill(incomeColor(index)).accessibilityLevel('no')
            Text(source.action).fontSize(12).fontColor($r('app.color.text_primary')).layoutWeight(1)
            Text(`${LedgerPage.fmt(source.num)} · ${source.percent}%`)
              .fontSize(12).fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }, (source: LedgerIncomeSource, index: number) => `${index}_${source.actionId}_${source.action}_${source.num}_${source.percent}`)
      }
    }
    .width('100%').padding(14).borderRadius(12)
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  report() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.accountLabel()).fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        if (this.vm.availableMonths.length > 0) {
          Select(this.monthOptions())
            .selected(this.vm.month === 0 ? 0 : this.vm.availableMonths.indexOf(this.vm.month) + 1)
            .value(this.vm.month === 0 ? '最新月份' : `${this.vm.month} 月`)
            .attributeModifier(new SelectMaterialModifier(this.surfaceMode, this.surfaceLevel))
            .hoverEffect(HoverEffect.Highlight)
            .onSelect((index: number) => this.selectMonth(index))
        }
      }
      .width('100%')
      if (this.vm.stale) {
        Text(`显示上次获取的 ${this.vm.ledger?.month ?? 0} 月数据 · ${this.vm.message}`)
          .fontSize(12).fontColor($r('app.color.danger')).width('100%')
      } else if (this.vm.loading && this.vm.ledger !== undefined) {
        Text($r('app.string.common_loading')).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.vm.ledger !== undefined) {
        GridRow({ columns: 2, gutter: 12 }) {
          GridCol({ span: this.isWide ? 1 : 2 }) { this.summary() }
          GridCol({ span: this.isWide ? 1 : 2 }) { this.incomeBreakdown() }
        }
        .width('100%')
      } else if (this.vm.loading) {
        Loading()
      } else {
        ErrorHint({ text: this.vm.message.length > 0 ? this.vm.message : '暂无札记数据', onRetry: () => this.reload() })
      }
    }
    .width('100%')
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column() {
        PageHeader({ title: $r('app.string.ui_nav_ledger'), embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
          if (this.isLoggedIn && this.currentUid.length > 0) {
            Button($r('app.string.ui_daily_note_refresh'), { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).enabled(!this.vm.loading)
              .onClick(() => this.reload())
          }
        }
        Scroll() {
          Column() {
            if (!this.isLoggedIn || this.currentUid.length === 0) {
              this.accountGuide()
            } else {
              this.report()
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
      }
      .width('100%').height('100%')
      .onAreaChange((_oldValue: Area, area: Area) => {
        this.isWide = (area.width as number) >= 840;
      })
    }
    .width('100%').height('100%')
  }
}
