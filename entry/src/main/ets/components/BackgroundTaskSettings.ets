import { BackgroundTaskKind, BackgroundTaskState } from '../model/BackgroundTask';
import { BackgroundTaskService } from '../service/BackgroundTaskService';
import { BackgroundEnableReview, BackgroundTaskSettingsViewModel } from '../viewmodel/BackgroundTaskSettingsViewModel';
import { AppButtonModifier, CardSurfaceModifier, UiSurface } from '../common/UiSurface';

@Component
export struct BackgroundTaskSettings {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @Prop @Watch('visibilityChanged') active: boolean = true;
  @StorageProp('backgroundTaskStatusVersion') @Watch('statusChanged') statusVersion: number = 0;
  @State vm: BackgroundTaskSettingsViewModel = new BackgroundTaskSettingsViewModel();
  @State isWide: boolean = false;
  private attached: boolean = false;

  aboutToAppear(): void { this.attached = true; this.visibilityChanged(); }
  aboutToDisappear(): void { this.attached = false; this.vm.invalidate(); }
  private visibilityChanged(): void {
    if (this.attached && this.active) { this.vm.activate(); } else { this.vm.invalidate(); }
  }
  private statusChanged(): void { this.vm.refresh(); }
  private state(kind: BackgroundTaskKind): BackgroundTaskState {
    return kind === BackgroundTaskKind.DAILY_NOTE ? this.vm.daily : this.vm.signIn;
  }
  private title(kind: BackgroundTaskKind): string { return kind === BackgroundTaskKind.DAILY_NOTE ? '后台便笺刷新' : '后台每日签到'; }
  private coverage(kind: BackgroundTaskKind): string {
    return kind === BackgroundTaskKind.DAILY_NOTE ? '刷新所有已追踪的国服角色' : '为本机保存的所有国服角色签到';
  }
  private owner(kind: BackgroundTaskKind): string {
    const state: BackgroundTaskState = this.state(kind);
    return state.enabled && !state.allAccounts() ? `已授权 UID ${state.uid} · ${state.region}` : this.coverage(kind);
  }
  private enabledLabel(kind: BackgroundTaskKind): string {
    const state: BackgroundTaskState = this.state(kind);
    return state.enabled ? `已开启 · ${state.queued ? '已排队' : '等待排队'}` : '已关闭';
  }
  private timestamp(value: number): string { return value > 0 ? new Date(value).toLocaleString() : '暂无'; }
  private history(kind: BackgroundTaskKind): string {
    const state: BackgroundTaskState = this.state(kind);
    return `最近执行：${this.timestamp(state.lastRunAt)}\n最近成功：${this.timestamp(state.lastSuccessAt)}`;
  }
  private enable(kind: BackgroundTaskKind): void {
    const review: BackgroundEnableReview | undefined = this.vm.prepareEnable(kind);
    if (review === undefined) { return; }
    const note: string = kind === BackgroundTaskKind.DAILY_NOTE
      ? '\n\n阈值提醒沿用通知授权。已配置 Webhook 时，刷新后的便笺会发送到该地址。' : '';
    try {
      this.getUIContext().showAlertDialog({ systemMaterial: UiSurface.dialogMaterial(),
        title: `开启${this.title(kind)}`,
        message: `${this.coverage(kind)}。\n\n${BackgroundTaskService.EXPLANATION}${note}`,
        primaryButton: { value: '取消', action: () => { this.vm.cancelEnable(review); } },
        secondaryButton: { value: '确认开启', action: () => { this.vm.confirmEnable(review); } },
        cancel: () => { this.vm.cancelEnable(review); },
      });
    } catch (e) { this.vm.cancelEnable(review); }
  }

  @Builder
  taskCard(kind: BackgroundTaskKind) {
    Column({ space: 10 }) {
      Text(this.title(kind)).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(this.enabledLabel(kind)).fontSize(13).fontColor($r('app.color.text_primary'))
      Text(this.owner(kind)).fontSize(12).fontColor($r('app.color.text_secondary'))
      Text(this.state(kind).message).fontSize(13).fontColor($r('app.color.text_secondary'))
      Text(this.history(kind)).fontSize(12).fontColor($r('app.color.text_secondary'))
      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.state(kind).enabled) {
          if (!this.state(kind).allAccounts()) {
            Button('扩大到所有适用角色', { type: ButtonType.Normal })
              .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
              .height(44).margin({ right: 8, bottom: 6 }).enabled(!this.vm.busy)
              .onClick(() => { this.enable(kind); })
          }
          Button('重新排队', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ right: 8, bottom: 6 }).enabled(!this.vm.busy)
            .onClick(() => { this.vm.retry(kind); })
          Button('关闭后台任务', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
            .height(44).margin({ bottom: 6 }).enabled(!this.vm.busy)
            .onClick(() => { this.vm.disable(kind); })
        } else {
          Button('查看说明并开启', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
            .height(44).enabled(!this.vm.busy)
            .onClick(() => { this.enable(kind); })
        }
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(14)
      .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
      .border({ width: 1, color: $r('app.color.card_stroke'), radius: 12 })
  }

  build() {
    Column({ space: 12 }) {
      Text('系统后台任务').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text('系统择机运行，每项任务可单独开启或关闭。')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      if (this.isWide) {
        Row({ space: 12 }) {
          Column() { this.taskCard(BackgroundTaskKind.DAILY_NOTE) }.layoutWeight(1)
          Column() { this.taskCard(BackgroundTaskKind.SIGN_IN) }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        this.taskCard(BackgroundTaskKind.DAILY_NOTE)
        this.taskCard(BackgroundTaskKind.SIGN_IN)
      }
      Button('重试当前 UID 签到', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(44).enabled(!this.vm.busy)
        .onClick(() => { this.vm.retryCurrentSignIn(); })
      Text('手动重试不会弹出验证窗口。若需要验证或重新登录，请先前往签到或账号页面处理，再重试。')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      Button('刷新任务状态', { type: ButtonType.Normal })
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .height(44).enabled(!this.vm.busy)
        .onClick(() => { this.vm.refresh(); })
      if (this.vm.message.length > 0) { Text(this.vm.message).fontSize(13).fontColor($r('app.color.text_secondary')) }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .onAreaChange((_old: Area, area: Area) => { this.isWide = Number(area.width) >= 840; })
  }
}
