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

  aboutToAppear(): void {
    const target: GamePackage = GameLauncherService.getTarget();
    this.gameName = target.displayName;
    this.bundleName = target.packageName;
    this.abilityName = target.abilityName;
    this.launchUri = target.uri;
    this.message = GameLauncherService.targetStatus(target);
  }

  private save(): boolean {
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
    if (this.launching || !this.save()) {
      return;
    }
    this.launching = true;
    try {
      const result: GameLaunchResult = await GameLauncherService.launch();
      this.message = result.message;
    } finally {
      this.launching = false;
    }
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
            .onChange((value: string) => { this.gameName = value; })
          TextInput({ text: this.launchUri, placeholder: '公开启动链接（优先使用）' })
            .onChange((value: string) => { this.launchUri = value; })
          Text('没有启动链接时，填写应用提供的 Bundle 与 Ability 名称。')
            .fontSize(13).fontColor($r('app.color.text_secondary'))
          TextInput({ text: this.bundleName, placeholder: 'HarmonyOS Bundle 名称' })
            .onChange((value: string) => { this.bundleName = value; })
          TextInput({ text: this.abilityName, placeholder: '公开 Ability 名称' })
            .onChange((value: string) => { this.abilityName = value; })
          Row({ space: 12 }) {
            Button('保存').onClick(() => { this.save(); }).hoverEffect(HoverEffect.Highlight)
            Button(this.launching ? '正在启动…' : '启动游戏')
              .enabled(!this.launching).onClick(() => { this.launch(); }).hoverEffect(HoverEffect.Highlight)
            Button('清除').onClick(() => {
              GameLauncherService.clearTarget();
              this.aboutToAppear();
            }).hoverEffect(HoverEffect.Highlight)
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
