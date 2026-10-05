import { common } from '@kit.AbilityKit';
import { PageHeader } from '../components/PageHeader';
import { AppRelease, UpdateChannel, UpdateStatus } from '../model/AppUpdate';
import { UpdateViewModel } from '../viewmodel/UpdateViewModel';

@Entry
@Component
export struct UpdatePage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State vm: UpdateViewModel = new UpdateViewModel();
  @State isWide: boolean = false;
  private attached: boolean = false;
  aboutToAppear(): void { this.activate(); }
  onPageShow(): void { this.activate(); }
  onPageHide(): void { this.detach(); }
  aboutToDisappear(): void { this.detach(); }
  private activate(): void { if (!this.attached) { this.attached = true; this.vm.activate(); } }
  private detach(): void { this.attached = false; this.vm.invalidate(); }
  private async open(project: boolean): Promise<void> {
    if (!this.attached) { return; }
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) { this.vm.openFailed = true; return; }
    await this.vm.open(context as common.UIAbilityContext, project);
  }
  private status(): string {
    switch (this.vm.result.status) {
      case UpdateStatus.Idle: return '手动检查公开发布版本';
      case UpdateStatus.Checking: return '正在读取项目发布信息…';
      case UpdateStatus.Newer: return '发现较新的发布版本';
      case UpdateStatus.Equal: return '公开发布版本与本机版本相同';
      case UpdateStatus.LocalNewer: return '本机版本高于此通道的公开发布版本，无需降级';
      case UpdateStatus.NoRelease: return '项目尚无可用的公开发布版本';
      case UpdateStatus.NoChannelRelease: return '此通道尚无发布版本；可切换至含预发布的通道查看';
      case UpdateStatus.Unknown: return this.vm.result.metadataConflict
        ? '版本名称与版本代码矛盾，无法判断升级关系' : '版本或发布信息不完整，无法确定更新关系';
      case UpdateStatus.NetworkError: return '网络检查失败，请稍后重试';
      case UpdateStatus.RateLimited: return 'GitHub 拒绝或限制了请求，请稍后重试';
      case UpdateStatus.Unavailable: return '发布仓库暂不可访问，不能据此判断是否已有新版本';
      case UpdateStatus.InvalidResponse: return '发布信息格式或来源不符合预期，未采用此响应';
      case UpdateStatus.Cancelled: return '检查已取消';
      default: return '尚未检查';
    }
  }
  private release(): AppRelease | undefined { return this.vm.result.release; }
  private releaseTitle(): string { const release: AppRelease | undefined = this.release(); return release === undefined ? '' : release.name; }
  private releaseNotes(): string { const release: AppRelease | undefined = this.release(); return release === undefined || release.notes.length === 0 ? '此版本未提供发布说明' : release.notes; }
  private releaseTag(): string { const release: AppRelease | undefined = this.release(); return release === undefined ? '' : `${release.tag}${release.prerelease ? ' · 预发布' : ' · 稳定发布'}`; }
  private apiAdvice(): string {
    const release: AppRelease | undefined = this.release();
    if (release === undefined) { return ''; }
    if (release.manifestState === 'invalid') { return '附带的更新元数据无效，最低 API 和安装兼容性未知'; }
    if (release.manifest === undefined) { return '未提供有效的项目更新元数据，最低 API 和安装兼容性未知'; }
    if (this.vm.result.apiState === 'requires-newer-api') {
      return `该发布声明最低 API ${release.manifest.minimumApi}，高于本机 API ${this.vm.client.api}。请勿在此设备安装该版本`;
    }
    if (this.vm.result.apiState === 'api-requirement-met') {
      return `满足项目元数据声明的最低 API ${release.manifest.minimumApi}；这不代表设备、架构、签名或安装兼容性已经验证`;
    }
    return `项目声明最低 API ${release.manifest.minimumApi}；本机 API 或应用身份无法确认，兼容性未知`;
  }
  private packageAdvice(): string {
    const release: AppRelease | undefined = this.release();
    return release !== undefined && release.harmonyAssetCount > 0
      ? '此发布列出了 HarmonyOS 包名，但未验证签名、完整性或安装资格。请向维护者确认可信分发渠道'
      : '此发布没有可识别的 HarmonyOS 包；不能将 Windows 安装器或源码压缩包作为本机更新';
  }

  @Builder
  checkPanel() {
    Column({ space: 14 }) {
      Text('应用更新').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Text(`本机版本：${this.vm.client.versionName || '未知'} · versionCode ${this.vm.client.versionCode || '未知'}`)
        .fontSize(14).fontColor($r('app.color.text_primary'))
      Text(`系统 API：${this.vm.client.api || '未知'}`).fontSize(13).fontColor($r('app.color.text_secondary'))
      Text('发布通道').fontSize(14).fontColor($r('app.color.text_primary'))
      Select([{ value: '稳定发布' }, { value: '包含预发布（测试版本）' }])
        .selected(this.vm.channel === UpdateChannel.Stable ? 0 : 1)
        .value(this.vm.channel === UpdateChannel.Stable ? '稳定发布' : '包含预发布（测试版本）')
        .width('100%').height(44).fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.card_surface')).hoverEffect(HoverEffect.Highlight)
        .accessibilityText('更新发布通道').onSelect((index: number) => {
          if (index === 0 || index === 1) { this.vm.setChannel(index === 0 ? UpdateChannel.Stable : UpdateChannel.Preview); }
        })
      Text(this.status()).fontSize(15).fontColor($r('app.color.text_primary')).width('100%')
      if (this.vm.busy) {
        Button('取消检查').width('100%').height(44).hoverEffect(HoverEffect.Highlight)
          .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
          .onClick(() => { this.vm.cancel(); })
      } else {
        Button('检查更新').width('100%').height(44).hoverEffect(HoverEffect.Highlight)
          .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
          .onClick(() => { this.vm.check(); })
      }
      if (this.vm.result.checkedAt > 0) {
        Text(`检查时间：${new Date(this.vm.result.checkedAt).toLocaleString()}`)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      if (!this.vm.result.complete) {
        Text('发布记录过多，本次仅检查最近 300 条；不能保证已经覆盖所有历史版本')
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      if (this.vm.result.unknownVersions > 0) {
        Text(`有 ${this.vm.result.unknownVersions} 条记录无法安全比较，未将它们认定为更新`)
          .fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      Text('仅向项目 GitHub 仓库读取公开发布信息，不附带账号凭据。不自动检查、下载安装包或启动安装')
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      Text('当前未配置经验证的鸿蒙分发渠道。发布页仅供阅读说明；安装请通过维护者确认的合法渠道，并由系统检查签名及确认')
        .fontSize(13).fontColor($r('app.color.text_secondary'))
      Button('打开项目发布列表').width('100%').height(44).enabled(!this.vm.busy && !this.vm.opening)
        .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
        .hoverEffect(HoverEffect.Highlight).onClick(() => { this.open(true); })
      if (this.vm.openFailed) {
        Text('无法打开发布页面，请稍后重试').fontSize(13).fontColor($r('app.color.text_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(14)
      .backgroundColor($r('app.color.card_surface'))
  }
  @Builder
  releasePanel() {
    Column({ space: 14 }) {
      if (this.vm.result.release !== undefined) {
        Text(this.releaseTitle()).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text(this.releaseTag()).fontSize(14).fontColor($r('app.color.text_secondary'))
        Text(this.apiAdvice()).fontSize(14).fontColor($r('app.color.text_primary'))
        Text(this.packageAdvice()).fontSize(13).fontColor($r('app.color.text_secondary'))
        Button('阅读此版本发布说明').width('100%').height(44).enabled(!this.vm.busy && !this.vm.opening)
          .fontColor($r('app.color.app_primary')).backgroundColor($r('app.color.app_primary_bg'))
          .hoverEffect(HoverEffect.Highlight).onClick(() => { this.open(false); })
        Text('下方为项目发布说明（最多显示 8,000 字符），其中外部链接不会自动打开')
          .fontSize(12).fontColor($r('app.color.text_secondary'))
        Text(this.releaseNotes()).fontSize(14).fontColor($r('app.color.text_primary')).width('100%')
      } else {
        Text('检查后可在此查看可比较版本及发布说明').fontSize(14).fontColor($r('app.color.text_secondary'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(14)
      .backgroundColor($r('app.color.card_surface'))
  }
  build() {
    Column() {
      PageHeader({ title: '应用更新', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp })
      Scroll() {
        if (this.isWide) {
          Row({ space: 16 }) {
            Column() { this.checkPanel() }.width('40%')
            Column() { this.releasePanel() }.layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Top).padding(16)
        } else {
          Column({ space: 16 }) { this.checkPanel(); this.releasePanel() }.width('100%').padding(16)
        }
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }.width('100%').height('100%').backgroundColor($r('app.color.wallpaper_base'))
      .onAreaChange((_old: Area, area: Area) => { this.isWide = Number(area.width) >= 840; })
  }
}
