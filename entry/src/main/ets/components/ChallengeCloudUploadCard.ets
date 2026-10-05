import { router } from '@kit.ArkUI';
import { ChallengeCloudViewModel } from '../viewmodel/ChallengeCloudViewModel';

/** Shared native review/confirmation surface; collection alone never uploads. */
@Component
export struct ChallengeCloudUploadCard {
  @Prop @Watch('invalidate') uid: string = '';
  @Prop @Watch('invalidate') scheduleId: number = 0;
  @Prop @Watch('invalidate') kind: string = 'abyss';
  @Prop @Watch('invalidate') available: boolean = false;
  @StorageProp('currentUserId') @Watch('invalidate') currentUserId: number = 0;
  @StorageProp('currentUid') @Watch('invalidate') selectedUid: string = '';
  @State vm: ChallengeCloudViewModel = new ChallengeCloudViewModel();
  invalidate(): void { this.vm.cancel(); }
  aboutToDisappear(): void { this.vm.cancel(); }
  build() {
    Column({ space: 8 }) {
      Text('上传当期战绩至胡桃统计').fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary')).width('100%')
      Text('先重新采集并预览，再由你确认提交。仅支持实时当期，历史存档不可上传。')
        .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.vm.preview !== undefined) {
        Text(`UID ${this.vm.preview.uid} · ${this.vm.preview.region} · 第 ${this.vm.preview.scheduleId} 期`)
          .fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
        Text(this.vm.preview.content).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Text(`接收方：homa.snaphutaorp.org${this.vm.preview.endpoint}；用于胡桃数据库统计，会替换该 UID 的当前记录。`)
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        if (this.kind === 'abyss') {
          Text(this.vm.preview.passport.length > 0 ? `附带胡桃通行证账号：${this.vm.preview.passport}` :
            '不关联胡桃通行证，可继续上传；不会领取账号关联奖励。也可先去登录，再重新预览。')
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          Text('根据服务端公开实现，持有角色和符合条件的战绩还可能以混淆 UID 转送披萨小助手统计。')
            .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
          if (this.vm.preview.passport.length === 0) {
            Button('去胡桃通行证').fontSize(12).hoverEffect(HoverEffect.Highlight)
              .onClick(() => { this.vm.cancel(); router.pushUrl({ url: 'pages/HutaoCloudPage' }); })
          }
        }
        Text('不会发送游戏 Cookie 或通行证令牌。以下是完整发送内容：')
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Scroll() {
          Text(this.vm.preview.body).fontSize(11).copyOption(CopyOptions.InApp)
            .fontColor($r('app.color.text_secondary')).width('100%')
        }.height(160).width('100%')
        Text(`SHA-256 ${this.vm.preview.digest}`).fontSize(10).fontColor($r('app.color.text_secondary')).width('100%')
        Text('本机只保留最近 100 条成功收据，不随数据备份迁移。发送后无法撤回。')
          .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
        Row({ space: 8 }) {
          Button(this.vm.submitting ? '正在提交…' : '确认发送以上内容').fontSize(12)
            .enabled(!this.vm.submitting && !this.vm.preview.duplicate).hoverEffect(HoverEffect.Highlight)
            .onClick(() => { this.vm.confirm(); })
          Button('取消').fontSize(12).enabled(!this.vm.submitting).hoverEffect(HoverEffect.Highlight)
            .onClick(() => { this.vm.cancel(); })
        }
      } else {
        Button(this.vm.preparing ? '正在采集…' : '采集并预览').fontSize(12)
          .enabled(this.available && this.scheduleId > 0 && !this.vm.preparing && !this.vm.submitting)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => { this.vm.prepare(this.kind, this.uid, this.scheduleId); })
        if (this.vm.preparing) {
          Button('取消采集').fontSize(12).hoverEffect(HoverEffect.Highlight).onClick(() => { this.vm.cancel(); })
        }
      }
      if (this.vm.receipt !== undefined) {
        Text(`本机成功收据 · UID ${this.vm.receipt.uid} · 第 ${this.vm.receipt.scheduleId} 期\n${new Date(this.vm.receipt.uploadedAt).toLocaleString()}\nSHA-256 ${this.vm.receipt.digest}`)
          .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.vm.message.length > 0) {
        Text(this.vm.message).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      }
    }.width('100%').padding(14).borderRadius(12).backgroundColor($r('app.color.card_surface'))
      .border({ width: 1, color: $r('app.color.card_stroke') })
  }
}
