/**
 * LaunchGamePage.ets（@Entry）
 * 启动游戏（对齐 Windows 入口，仅拉起本机已安装原神 APP）：
 * 顶部状态：已安装/未安装检测；大按钮"启动游戏"；下方游戏列表（可切换）。
 * 不做注入/进程链/账号切换（鸿蒙版仅拉起，其余由游戏 App 自身处理）。
 */
import { router } from '@kit.ArkUI';
import { GameLauncherService, GamePackage, GameLaunchResult } from '../service/GameLauncherService';
import { AppBackButton } from '../components/AppBackButton';
import { NavIcon } from '../components/NavIcon';
import { PageHeader } from '../components/PageHeader';
import { PressCard } from '../components/PressCard';
import { Logger } from '../common/Logger';

const TAG: string = 'LaunchGamePage';

@Entry
@Component
export struct LaunchGamePage {
  /** 宽屏内嵌模式：隐藏返回按钮、去除状态栏避让（由内容区统一处理） */
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('isLoggedIn') isLoggedIn: boolean = false;
  /** 已安装游戏列表 */
  @State games: GamePackage[] = [];
  /** 当前选中游戏（默认第一个） */
  @State selected: GamePackage = new GamePackage();
  /** 检测/启动状态 */
  @State checking: boolean = true;
  @State launching: boolean = false;
  @State message: string = '';

  aboutToAppear(): void {
    this.detect();
  }

  async detect(): Promise<void> {
    this.checking = true;
    this.message = '';
    try {
      const list: GamePackage[] = await GameLauncherService.detectInstalled();
      this.games = list;
      if (list.length > 0) {
        this.selected = list[0];
      } else {
        this.message = '未检测到原神 APP。请先通过应用市场安装「原神」后重试';
      }
    } catch (e) {
      this.message = `检测失败：${(e as Error).message}`;
    } finally {
      this.checking = false;
    }
  }

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2200 });
  }

  launch(): void {
    if (this.launching) {
      return;
    }
    this.launching = true;
    this.message = '';
    GameLauncherService.launch(this.selected.packageName).then((r: GameLaunchResult) => {
      this.toast(r.ok ? `已拉起 ${r.bundleName}` : r.message);
      if (!r.ok) {
        this.message = r.message;
      }
    }).catch((e: Error) => {
      this.message = `拉起失败：${e.message}`;
    }).finally(() => {
      this.launching = false;
    });
  }

  @Builder
  header() {
    PageHeader({ title: '启动游戏', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp }) {
      Button('重新检测')
        .fontSize(12)
        .height(28)
        .backgroundColor($r('app.color.app_primary_bg'))
        .fontColor($r('app.color.app_primary'))
        .onClick(() => {
          this.detect();
        })
    }
  }

  build() {
    Column() {
      this.header()
      if (this.checking) {
        Column({ space: 10 }) {
          LoadingProgress().width(36).height(36).color($r('app.color.app_primary'))
          Text('正在检测米哈游游戏...')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 14 }) {
            // 启动主卡（包装 Column：自定义组件后接 .width 在 @Builder 中受限）
            Column() {
              PressCard({
                onTap: () => {
                  if (!this.launching && this.selected.packageName.length > 0) {
                    this.launch();
                  }
                },
                cardBg: $r('app.color.card_background'),
                radius: 14,
              }) {
                Column({ space: 12 }) {
                  Row({ space: 12 }) {
                    NavIcon({ name: 'LaunchGame', iconSize: 44 })
                    Column({ space: 3 }) {
                      Text(this.selected.displayName.length > 0 ? `启动 ${this.selected.displayName}` : '启动游戏')
                        .fontSize(19)
                        .fontWeight(FontWeight.Bold)
                        .fontColor($r('app.color.text_primary'))
                      Text('拉起本机已安装的原神 APP（鸿蒙版不注入不改进程）')
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    if (this.launching) {
                      LoadingProgress().width(22).height(22).color($r('app.color.app_primary'))
                    } else {
                      Text('启动 ›')
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Color.White)
                        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                        .borderRadius(18)
                        .backgroundColor($r('app.color.app_primary'))
                    }
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(18)
              }
            }
            .width('100%')

            if (this.message.length > 0) {
              Row({ space: 8 }) {
                Circle({ width: 6, height: 6 })
                  .fill($r('app.color.danger'))
                Text(this.message)
                  .fontSize(12)
                  .fontColor($r('app.color.danger'))
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .borderRadius(10)
              .backgroundColor($r('app.color.danger_bg'))
              .border({ width: 1, color: $r('app.color.danger') })
            }

            // 已检测到的游戏列表
            if (this.games.length > 1) {
              Column({ space: 8 }) {
                Text('检测到的米哈游游戏')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                ForEach(this.games, (g: GamePackage) => {
                  Row({ space: 10 }) {
                    NavIcon({ name: 'LaunchGame', iconSize: 22 })
                    Text(g.displayName)
                      .fontSize(14)
                      .fontColor(this.selected.packageName === g.packageName ? $r('app.color.app_primary') : $r('app.color.text_primary'))
                      .layoutWeight(1)
                    Text(this.selected.packageName === g.packageName ? '选中' : '')
                      .fontSize(10)
                      .fontColor($r('app.color.app_primary'))
                  }
                  .width('100%')
                  .padding(12)
                  .borderRadius(12)
                  .backgroundColor($r('app.color.page_background'))
                  .border({
                    width: 1,
                    color: this.selected.packageName === g.packageName ? $r('app.color.app_primary') : $r('app.color.divider'),
                  })
                  .onClick(() => {
                    this.selected = g;
                  })
                }, (g: GamePackage) => `gp_${g.packageName}`)
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.embedMode ? Color.Transparent : $r('app.color.page_background'))
  }
}
