import { router } from '@kit.ArkUI';
import { HutaoCloudViewModel } from '../viewmodel/HutaoCloudViewModel';
import { HutaoCloudEntry, HutaoCloudMetric } from '../model/HutaoCloud';
import { GachaArchive } from '../model/GachaArchive';

@Entry
@Component
export struct HutaoCloudPage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State vm: HutaoCloudViewModel = new HutaoCloudViewModel();
  @State tab: number = 0;
  @State last: boolean = false;
  @State statisticKind: string = 'overview';

  aboutToAppear(): void { this.vm.load(); }

  private async confirm(action: string, title: string, message: string): Promise<void> {
    const response = await this.getUIContext().getPromptAction().showDialog({
      title: title, message: message,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '确认', color: $r('app.color.app_primary') },
      ],
    });
    if (response.index === 1) { await this.vm.execute(action); }
  }

  @Builder
  action(label: string, command: string) {
    Button(label).fontSize(13).height(36).enabled(!this.vm.busy)
      .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
      .hoverEffect(HoverEffect.Highlight).onClick(() => { this.vm.execute(command); })
  }

  @Builder
  account() {
    Column({ space: 12 }) {
      Text(this.vm.loggedIn ? `已登录：${this.vm.userName}` : '登录胡桃通行证')
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Text('服务提供方：Snap.Hutao.Remastered（homa.snaphutaorp.org）。使用此服务的通行证邮箱；与米游社、HoYoLAB 账号独立。')
        .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      TextInput({ placeholder: '通行证邮箱', text: this.vm.email }).type(InputType.Email)
        .onChange((value: string) => { this.vm.email = value; })
      TextInput({ placeholder: '密码（注册 / 重置至少 8 位）', text: this.vm.password }).type(InputType.Password)
        .onChange((value: string) => { this.vm.password = value; })
      TextInput({ placeholder: '邮件验证码', text: this.vm.code })
        .onChange((value: string) => { this.vm.code = value; })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.action('登录', 'login')
        this.action('注册验证码', 'verifyRegister')
        this.action('注册', 'register')
        this.action('重置验证码', 'verifyReset')
        this.action('重置密码', 'reset')
      }.width('100%')
      if (this.vm.loggedIn) {
        this.action('刷新服务状态', 'userInfo')
        ForEach(this.vm.info, (row: HutaoCloudMetric) => {
          Row() {
            Text(row.label).fontColor($r('app.color.text_secondary')).fontSize(13)
            Blank()
            Text(row.value).fontColor($r('app.color.text_primary')).fontSize(13).textAlign(TextAlign.End).layoutWeight(1)
          }.width('100%')
        }, (row: HutaoCloudMetric) => `${row.label}:${row.value}`)
        TextInput({ placeholder: '服务兑换码', text: this.vm.redeemCode })
          .onChange((value: string) => { this.vm.redeemCode = value; })
        this.action('兑换', 'redeem')
        Divider().color($r('app.color.divider'))
        Text('更换邮箱').fontSize(16).fontColor($r('app.color.text_primary')).width('100%')
        TextInput({ placeholder: '新邮箱', text: this.vm.newEmail }).type(InputType.Email)
          .onChange((value: string) => { this.vm.newEmail = value; })
        TextInput({ placeholder: '新邮箱验证码（旧邮箱验证码填写在上方）', text: this.vm.newCode })
          .onChange((value: string) => { this.vm.newCode = value; })
        Flex({ wrap: FlexWrap.Wrap }) {
          this.action('旧邮箱验证码', 'verifyOldEmail')
          this.action('新邮箱验证码', 'verifyNewEmail')
          this.action('确认更换邮箱', 'resetEmail')
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          this.action('撤销本机登录并退出', 'logout')
          this.action('仅清除本机登录', 'forget')
          Button('撤销全部设备').enabled(!this.vm.busy).hoverEffect(HoverEffect.Highlight)
            .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.card_background'))
            .onClick(() => { this.confirm('revokeAll', '撤销全部设备登录？', '此通行证在所有设备上的登录凭据将失效。'); })
          this.action('注销验证码', 'verifyCancel')
          Button('注销通行证').enabled(!this.vm.busy).hoverEffect(HoverEffect.Highlight)
            .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.card_background'))
            .onClick(() => { this.confirm('unregister', '永久注销通行证？', '请先填写当前密码和注销验证码。注销会影响此账号的云服务及云数据，无法通过本地备份恢复。'); })
        }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  sync() {
    Column({ space: 12 }) {
      Text('祈愿云存档').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text('点击上传后，仅发送所选 UID 的祈愿记录。下载与本地记录合并；不会替换本地归档。服务权限及到期时间由服务器决定。')
        .fontSize(13).fontColor($r('app.color.text_secondary'))
      TextInput({ placeholder: '游戏 UID', text: this.vm.uid }).type(InputType.Number).maxLength(10)
        .onChange((value: string) => { this.vm.uid = value; })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.vm.archives, (archive: GachaArchive) => {
          Button(archive.uid).fontSize(12).hoverEffect(HoverEffect.Highlight)
            .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
            .onClick(() => { this.vm.uid = archive.uid; })
        }, (archive: GachaArchive) => archive.uid)
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        this.action('读取云存档', 'entries')
        this.action('下载并合并', 'retrieve')
        Button('上传新增记录').enabled(!this.vm.busy).hoverEffect(HoverEffect.Highlight)
          .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
          .onClick(() => { this.confirm('upload', '上传祈愿记录？', `将 UID ${this.vm.uid} 的新增祈愿记录上传到 Snap.Hutao.Remastered 胡桃云。`); })
        Button('删除此 UID 云记录').enabled(!this.vm.busy).hoverEffect(HoverEffect.Highlight)
          .fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.card_background'))
          .onClick(() => { this.confirm('delete', '删除云存档？', `永久删除云端 UID ${this.vm.uid} 的祈愿记录。本地记录仍保留。`); })
      }.width('100%')
      ForEach(this.vm.entries, (entry: HutaoCloudEntry) => {
        Row() {
          Column({ space: 4 }) {
            Text(`UID ${entry.uid}`).fontColor($r('app.color.text_primary'))
            Text(`${entry.count} 条${entry.excluded ? ' · 不参与全球统计' : ''}`).fontSize(12).fontColor($r('app.color.text_secondary'))
          }.alignItems(HorizontalAlign.Start)
          Blank()
          Button('选择').hoverEffect(HoverEffect.Highlight)
            .onClick(() => { this.vm.uid = entry.uid; })
        }.width('100%').padding(12).backgroundColor($r('app.color.card_background')).borderRadius(12)
      }, (entry: HutaoCloudEntry) => `${entry.uid}:${entry.count}`)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  statistics() {
    Column({ space: 12 }) {
      Text('胡桃数据库').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Select([
        { value: '深渊概览' }, { value: '角色出场率' }, { value: '角色使用率' }, { value: '角色持有率' },
        { value: '角色搭配' }, { value: '武器搭配' }, { value: '队伍组合' }, { value: '幻想真境剧诗' },
        { value: '当前祈愿统计' }, { value: '角色池分布' }, { value: '武器池分布' }, { value: '常驻池分布' },
        { value: '集录池分布' }, { value: '常驻颂愿分布' }, { value: '活动颂愿分布' },
      ]).selected(0).value('选择统计类别').onSelect((index: number) => {
        const kinds: string[] = ['overview', 'attendance', 'utilization', 'holding', 'collocation', 'weapon', 'team',
          'roleCombat', 'events', 'avatarDistribution', 'weaponDistribution', 'standardDistribution',
          'chronicledDistribution', 'beyondStandardDistribution', 'beyondEventDistribution'];
        this.statisticKind = kinds[index];
      })
      Row({ space: 12 }) {
        Text('上一期').fontColor($r('app.color.text_secondary'))
        Toggle({ type: ToggleType.Switch, isOn: this.last }).onChange((value: boolean) => { this.last = value; })
        Button('加载统计').enabled(!this.vm.busy).hoverEffect(HoverEffect.Highlight)
          .onClick(() => { this.vm.statistics(this.statisticKind, this.last); })
      }
      ForEach(this.vm.metrics, (row: HutaoCloudMetric) => {
        Row({ space: 12 }) {
          Text(row.label).fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1)
          Text(row.value).fontSize(13).fontColor($r('app.color.text_primary')).textAlign(TextAlign.End).layoutWeight(1)
        }.width('100%').padding({ top: 5, bottom: 5 })
      }, (row: HutaoCloudMetric) => `${row.label}:${row.value}`)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        if (!this.embedMode) {
          Button('返回').hoverEffect(HoverEffect.Highlight).onClick(() => { router.back(); })
        }
        Text('胡桃通行证与云').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      }.width('100%').padding({ top: this.embedMode ? 0 : this.topAvoidVp })
      Row({ space: 12 }) {
        Button('通行证').hoverEffect(HoverEffect.Highlight).onClick(() => { this.tab = 0; })
        Button('云存档').hoverEffect(HoverEffect.Highlight).onClick(() => { this.tab = 1; })
        Button('数据库').hoverEffect(HoverEffect.Highlight).onClick(() => { this.tab = 2; })
      }.width('100%')
      if (this.vm.busy) { LoadingProgress().height(28).width(28) }
      if (this.vm.message.length > 0) {
        Text(this.vm.message).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      }
      Scroll() {
        Column() {
          if (this.tab === 0) { this.account() }
          else if (this.tab === 1) { this.sync() }
          else { this.statistics() }
        }.width('100%').constraintSize({ maxWidth: 1100 }).padding({ bottom: 24 })
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(16)
      .backgroundColor($r('app.color.page_background'))
  }
}
