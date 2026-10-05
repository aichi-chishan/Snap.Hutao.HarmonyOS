import { BackgroundTaskKind, BackgroundTaskState } from '../model/BackgroundTask';
import { BackgroundTaskService } from '../service/BackgroundTaskService';
import { BackgroundEnableReview, BackgroundTaskSettingsViewModel } from '../viewmodel/BackgroundTaskSettingsViewModel';

@Component
export struct BackgroundTaskSettings {
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
  private owner(kind: BackgroundTaskKind): string {
    const state: BackgroundTaskState = this.state(kind);
    return state.uid.length > 0 ? `绑定 UID ${state.uid} · ${state.region}` : '尚未绑定账号与 UID';
  }
  private enabledLabel(kind: BackgroundTaskKind): string {
    const state: BackgroundTaskState = this.state(kind);
    return state.enabled ? `已保存开启意愿 · ${state.queued ? '系统已接受排队' : '尚未排队'}` : '已关闭';
  }
  private timestamp(value: number): string { return value > 0 ? new Date(value).toLocaleString() : '暂无'; }
  private history(kind: BackgroundTaskKind): string {
    const state: BackgroundTaskState = this.state(kind);
    return `最近执行：${this.timestamp(state.lastRunAt)}\n最近成功：${this.timestamp(state.lastSuccessAt)}`;
  }
  private enable(kind: BackgroundTaskKind): void {
    const review: BackgroundEnableReview | undefined = this.vm.prepareEnable(kind);
    if (review === undefined) { return; }
    try {
      this.getUIContext().showAlertDialog({
        title: `开启${this.title(kind)}`,
        message: `仅为当前账号的 UID ${review.binding.uid}（${review.binding.region}）开启。\n\n${BackgroundTaskService.EXPLANATION}\n\n不会申请新的通知权限；通知仍遵循已有授权。`,
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
      if (this.state(kind).enabled) {
        Button('重新排队').width('100%').height(44).enabled(!this.vm.busy)
          .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
          .hoverEffect(HoverEffect.Highlight).onClick(() => { this.vm.retry(kind); })
        Button('关闭后台任务').width('100%').height(44).enabled(!this.vm.busy)
          .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.card_surface'))
          .hoverEffect(HoverEffect.Highlight).onClick(() => { this.vm.disable(kind); })
      } else {
        Button('查看说明并开启').width('100%').height(44).enabled(!this.vm.busy)
          .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
          .hoverEffect(HoverEffect.Highlight).onClick(() => { this.enable(kind); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(14).borderRadius(12)
      .backgroundColor($r('app.color.card_surface')).border({ width: 1, color: $r('app.color.card_stroke') })
  }

  build() {
    Column({ space: 12 }) {
      Text('系统后台任务').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text('默认关闭，需逐项确认。系统择机执行，不能保证固定间隔或零点签到。保存开启意愿与系统接受排队是不同状态。')
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
      Button('重试当前 UID 签到').width('100%').height(44).enabled(!this.vm.busy)
        .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
        .hoverEffect(HoverEffect.Highlight).onClick(() => { this.vm.retryCurrentSignIn(); })
      Text('手动重试不会弹出验证窗口。若需要验证或重新登录，请先前往签到或账号页面处理，再重试。')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      Button('刷新任务状态').width('100%').height(44).enabled(!this.vm.busy)
        .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.card_surface'))
        .hoverEffect(HoverEffect.Highlight).onClick(() => { this.vm.refresh(); })
      if (this.vm.message.length > 0) { Text(this.vm.message).fontSize(13).fontColor($r('app.color.text_secondary')) }
    }.width('100%').alignItems(HorizontalAlign.Start)
      .onAreaChange((_old: Area, area: Area) => { this.isWide = Number(area.width) >= 840; })
  }
}
