import { GameLauncherService, GamePackage, GameLaunchResult } from '../service/GameLauncherService';
import { PageHeader } from '../components/PageHeader';

@Entry
@Component
export struct LaunchGamePage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State gameName: string = '原神';
  @State bundleName: string = '';
  @State abilityName: string = '';
  @State launchUri: string = '';
  @State message: string = '';
  @State launching: boolean = false;
  private active: boolean = false;
  private generation: number = 0;
  private launchPending: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.generation++;
    this.launching = this.launchPending;
    this.loadTarget();
  }

  aboutToDisappear(): void { this.active = false; this.generation++; }

  private loadTarget(): void {
    const target: GamePackage = GameLauncherService.getTarget();
    this.gameName = target.displayName;
    this.bundleName = target.packageName;
    this.abilityName = target.abilityName;
    this.launchUri = target.uri;
    this.message = GameLauncherService.targetStatus(target);
  }

  private save(): boolean {
    if (this.launchPending) { return false; }
    const target: GamePackage = new GamePackage();
    target.displayName = this.gameName;
    target.packageName = this.bundleName;
    target.abilityName = this.abilityName;
    target.uri = this.launchUri;
    const error: string = GameLauncherService.saveTarget(target);
    this.message = error.length > 0 ? error : GameLauncherService.targetStatus(target);
    return error.length === 0;
  }

  private async launch(): Promise<void> {
    if (!this.active || this.launchPending || !this.save()) {
      return;
    }
    const generation: number = this.generation;
    this.launchPending = true;
    this.launching = true;
    try {
      const result: GameLaunchResult = await GameLauncherService.launch();
      if (this.active && generation === this.generation) { this.message = result.message; }
    } catch (_) {
      if (this.active && generation === this.generation) { this.message = '无法发送启动请求，请稍后重试'; }
    } finally {
      this.launchPending = false;
      if (this.active) { this.launching = false; }
    }
  }

  private clear(): void {
    if (this.launchPending) { return; }
    GameLauncherService.clearTarget();
    this.loadTarget();
  }

  build() {
    Column() {
      PageHeader({ title: '启动游戏', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp })
      Scroll() {
        Column({ space: 16 }) {
          Text('配置游戏入口')
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Text('填写游戏提供的公开启动链接，或已确认的 HarmonyOS 应用入口。配置后可从主页一键启动。')
            .fontSize(14).fontColor($r('app.color.text_secondary'))
          TextInput({ text: this.gameName, placeholder: '游戏名称' })
            .maxLength(80).enabled(!this.launching)
            .onChange((value: string) => { this.gameName = value; })
          TextInput({ text: this.launchUri, placeholder: '公开启动链接（优先使用）' })
            .maxLength(2048).enabled(!this.launching)
            .onChange((value: string) => { this.launchUri = value; })
          Text('没有启动链接时，填写应用提供的 Bundle 与 Ability 名称。')
            .fontSize(13).fontColor($r('app.color.text_secondary'))
          TextInput({ text: this.bundleName, placeholder: 'HarmonyOS Bundle 名称' })
            .maxLength(255).enabled(!this.launching)
            .onChange((value: string) => { this.bundleName = value; })
          TextInput({ text: this.abilityName, placeholder: '公开 Ability 名称' })
            .maxLength(255).enabled(!this.launching)
            .onChange((value: string) => { this.abilityName = value; })
          Row({ space: 12 }) {
            Button('保存').enabled(!this.launching).onClick(() => { this.save(); }).hoverEffect(HoverEffect.Highlight)
            Button(this.launching ? '正在启动…' : '启动游戏')
              .enabled(!this.launching).onClick(() => { this.launch(); }).hoverEffect(HoverEffect.Highlight)
            Button('清除').enabled(!this.launching).onClick(() => { this.clear(); }).hoverEffect(HoverEffect.Highlight)
          }
          Text(this.message).fontSize(14).fontColor($r('app.color.text_secondary'))
          Text('游戏安装、更新和游戏内账号切换由游戏或应用市场管理。')
            .fontSize(13).fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start).width('100%').padding(20)
      }.layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
  }
}
