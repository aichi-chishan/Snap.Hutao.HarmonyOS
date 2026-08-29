/**
 * HomeLaunchCard.ets
 * 主页·启动游戏卡（对齐 Windows 启动游戏仪表板卡）：
 * 标题 + 状态副文（已安装游戏名 / 未检测到）+ 大启动按钮。
 * 仅拉起本机已安装的米哈游游戏 APP（鸿蒙版不注入不改进程）。
 */
import { GameLauncherService, GamePackage, GameLaunchResult } from '../service/GameLauncherService';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';
import { Logger } from '../common/Logger';

const TAG: string = 'HomeLaunchCard';

@Component
export struct HomeLaunchCard {
  /** 启动完成回调（成功后提示） */
  onLaunched: (ok: boolean, message: string) => void = () => {
  };

  @State game: GamePackage = new GamePackage();
  @State detected: boolean = false;
  @State launching: boolean = false;

  aboutToAppear(): void {
    this.detect();
  }

  async detect(): Promise<void> {
    try {
      const list: GamePackage[] = await GameLauncherService.detectInstalled();
      if (list.length > 0) {
        this.game = list[0];
        this.detected = true;
      }
    } catch (e) {
      Logger.warn(TAG, `detect fail ${(e as Error).message}`);
    }
  }

  launch(): void {
    if (this.launching || !this.detected) {
      return;
    }
    this.launching = true;
    GameLauncherService.launch(this.game.packageName).then((r: GameLaunchResult) => {
      this.onLaunched(r.ok, r.ok ? `已拉起 ${r.bundleName}` : r.message);
    }).catch((e: Error) => {
      this.onLaunched(false, `拉起失败：${e.message}`);
    }).finally(() => {
      this.launching = false;
    });
  }

  build() {
    PressCard({
      onTap: () => {
        this.launch();
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'LaunchGame', iconSize: 18 })
          Text('启动游戏')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')

        Column({ space: 2 }) {
          Text(this.detected ? this.game.displayName : '未检测到游戏')
            .fontSize(13)
            .fontColor(this.detected ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.detected ? '点击直接拉起游戏' : '请先通过应用市场安装')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row() {
          Text(this.launching ? '启动中...' : '启动游戏')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width('100%')
        .height(44)
        .borderRadius(10)
        .backgroundColor($r('app.color.app_primary'))
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
