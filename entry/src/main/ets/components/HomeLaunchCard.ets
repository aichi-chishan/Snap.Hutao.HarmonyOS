/**
 * HomeLaunchCard.ets
 * 主页·启动游戏卡（对齐 Windows 启动游戏仪表板卡）：
 * 标题 + 状态副文（已安装游戏名 / 未检测到）+ 大启动按钮。
 * 仅拉起本机已安装的米哈游游戏 APP（鸿蒙版不注入不改进程）。
 */
import { GameLauncherService, GamePackage, GameLaunchResult } from '../service/GameLauncherService';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';
import { router } from '@kit.ArkUI';

const TAG: string = 'HomeLaunchCard';

@Component
export struct HomeLaunchCard {
  /** 启动完成回调（成功后提示） */
  onLaunched: (ok: boolean, message: string) => void = () => {
  };

  @State game: GamePackage = new GamePackage();
  @State detected: boolean = false;
  @StorageProp('gameLaunchTargetVersion') @Watch('onTargetChanged') targetVersion: number = 0;
  @State launching: boolean = false;

  aboutToAppear(): void {
    this.detect();
  }

  onTargetChanged(): void {
    this.detect();
  }

  detect(): void {
    this.game = GameLauncherService.getTarget();
    this.detected = GameLauncherService.validationMessage(this.game).length === 0;
  }

  launch(): void {
    if (!this.detected) {
      router.pushUrl({ url: 'pages/LaunchGamePage' });
      return;
    }
    if (this.launching) {
      return;
    }
    this.launching = true;
    GameLauncherService.launch().then((r: GameLaunchResult) => {
      this.onLaunched(r.ok, r.message);
    }).catch((e: Error) => {
      this.onLaunched(false, `拉起失败：${e.message}`);
    }).finally(() => {
      this.launching = false;
    });
  }

    /** 是否撑满 Grid 单元格高度（行内等高） */
    @Prop fillHeight: boolean = false;

  build() {
    PressCard({
      fillHeight: this.fillHeight,
      onTap: () => {
        this.launch();
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      // 统一 12vp 内边距；fillHeight 时撑满父级 204vp 行高：头部/副文/按钮纵向均衡分布
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'LaunchGame', iconSize: 18 })
          Text('启动游戏')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .height(24)
        .flexShrink(0)

        Column({ space: 2 }) {
          Text(this.detected ? this.game.displayName : '配置游戏入口')
            .fontSize(13)
            .fontColor(this.detected ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.detected ? '点击发送启动请求' : '填写游戏公开的启动链接')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .height(this.fillHeight ? 96 : undefined)
        .justifyContent(FlexAlign.Center)

        Row() {
          Text(this.launching ? '启动中...' : (this.detected ? '启动游戏' : '配置入口'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width('100%')
        .height(44)
        .flexShrink(0)
        .hoverEffect(HoverEffect.Highlight)
        .borderRadius(10)
        .backgroundColor($r('app.color.app_primary'))
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(this.fillHeight ? '100%' : undefined)
      .padding(12)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(this.fillHeight ? FlexAlign.SpaceBetween : FlexAlign.Start)
    }
  }
}
