/**
 * HomeSignInCard.ets
 * 主页签到卡（对齐 Windows HomeCardSignInCard）：
 * 头部（图标+累计天数+UID）、本月奖励网格（7 列，已签置灰打勾）、底部签到/补签按钮。
 * 整卡可点击，底部按钮独立触发签到。
 */
import { SignInInfo, SignInReward } from '../model/SignInInfo';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';
import { MetaIcon } from './MetaIcon';
import { WikiMetaService } from '../service/WikiMetaService';

/** 材料名→rawfile 图标名 缓存（进程内存，阻塞一次加载后常驻） */
export class SignInCardCache {
  private static map: Map<string, string> = new Map();
  private static loading: boolean = false;

  static materialNameToIcon(name: string): string {
    if (name.length === 0) {
      return '';
    }
    if (SignInCardCache.map.size === 0 && !SignInCardCache.loading) {
      SignInCardCache.loading = true;
      WikiMetaService.getMaterials().then((m) => {
        m.forEach((v, k) => {
          if (v.n.length > 0 && v.i.length > 0) {
            SignInCardCache.map.set(v.n, v.i);
          }
        });
        SignInCardCache.loading = false;
      }).catch(() => {
        SignInCardCache.loading = false;
      });
    }
    return SignInCardCache.map.get(name) ?? '';
  }
}

@Component
export struct HomeSignInCard {
  @Prop uid: string = '';
  @Prop info: SignInInfo | undefined = undefined;
  @Prop loaded: boolean = false;
  @Prop signing: boolean = false;
  /** 今日日期（天） */
  @Prop todayDay: number = 1;
  /** 点击整卡 */
  onTap: () => void = () => {
  };
  /** 点击签到 */
  onSignIn: () => void = () => {
  };
  /** 点击补签 */
  onResignIn: () => void = () => {
  };

  @Builder
  loadingView() {
    Column({ space: 8 }) {
      LoadingProgress()
        .width(24)
        .height(24)
        .color($r('app.color.app_primary'))
      Text('签到信息加载中...')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  emptyView() {
    Column({ space: 8 }) {
      NavIcon({ name: 'CheckIn', iconSize: 28 })
      Text('暂无签到数据')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(140)
    .justifyContent(FlexAlign.Center)
  }

  /** 单个奖励格 */
  @Builder
  awardCell(reward: SignInReward, isSigned: boolean) {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (reward.icon.startsWith('http')) {
          Image(reward.icon)
            .width(26)
            .height(26)
            .objectFit(ImageFit.Contain)
            .borderRadius(7)
            .backgroundColor($r('app.color.app_primary_bg'))
            .opacity(isSigned ? 0.35 : 1)
        } else {
          // 图标为物品 ID/名：尝试 rawfile ItemIcon 材料映射，未命中显示礼包图标
          MetaIcon({ category: 'ItemIcon', name: HomeSignInCard.itemIconOf(reward.name), iconSize: 26, remoteFallback: true })
            .opacity(isSigned ? 0.35 : 1)
        }
        if (isSigned) {
          Text('✓')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.success'))
        }
        Stack({ alignContent: Alignment.BottomEnd }) {
          Text(`×${reward.count}`)
            .fontSize(8)
            .fontColor($r('app.color.text_secondary'))
        }
        .width(24)
        .height(24)
      }
      .width(26)
      .height(26)
      Text(`${reward.day}日`)
        .fontSize(9)
        .fontColor(isSigned ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
        .opacity(isSigned ? 0.6 : 1)
    }
    .padding(2)
    .borderRadius(8)
    .backgroundColor(isSigned ? $r('app.color.card_background') : Color.Transparent)
  }

  /** 奖励网格高度：按行数动态（7 列，每行 34vp），避免多行被裁剪（对齐 Windows UniformGrid） */
  static gridHeight(count: number): number {
    const rows: number = Math.ceil(count / 7);
    return rows * 34;
  }

  /** 奖励名（原神通用材料名）→ rawfile ItemIcon 文件名（去 UI_ 前缀映射失败则用通用）
   *  材料元数据已含名称→图标映射（WikiMetaService.materials.n/i） */
  static itemIconOf(name: string): string {
    const icon: string = SignInCardCache.materialNameToIcon(name);
    return icon;
  }

  build() {
    PressCard({
      onTap: () => {
        this.onTap()
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'CheckIn', iconSize: 20 })
          Column({ space: 0 }) {
            Text('每日签到')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            if (this.info !== undefined) {
              Text(`本月已签 ${this.info.signedDays} 天`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.uid.length > 0) {
            Text(this.uid)
              .fontSize(12)
              .fontColor($r('app.color.app_primary'))
          }
        }
        .width('100%')

        if (!this.loaded) {
          this.loadingView()
        } else if (this.info === undefined || this.info.rewards.length === 0) {
          this.emptyView()
        } else {
          // 奖励网格（7 列）
          Grid() {
            ForEach(this.info.rewards, (reward: SignInReward) => {
              GridItem() {
                this.awardCell(reward, this.info !== undefined && reward.day <= this.info.signedDays)
              }
            }, (reward: SignInReward) => `sign_${reward.day}_${reward.count}`)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
          .columnsGap(2)
          .rowsGap(2)
          .width('100%')
          .height(this.info !== undefined ? HomeSignInCard.gridHeight(this.info.rewards.length) : 44)

          Divider()
            .width('100%')
            .color($r('app.color.divider'))

          Row({ space: 8 }) {
            Button(this.info.isTodaySigned(this.todayDay) ? '今日已签' : '签到')
              .fontSize(13)
              .height(32)
              .layoutWeight(1)
              .backgroundColor(this.info.isTodaySigned(this.todayDay) ? $r('app.color.card_background') : $r('app.color.app_primary'))
              .fontColor(this.info.isTodaySigned(this.todayDay) ? $r('app.color.text_secondary') : Color.White)
              .enabled(!this.info.isTodaySigned(this.todayDay) && !this.signing)
              .onClick(() => {
                this.onSignIn()
              })
            Button('补签')
              .fontSize(13)
              .height(32)
              .layoutWeight(1)
              .backgroundColor($r('app.color.app_primary_bg'))
              .fontColor($r('app.color.app_primary'))
              .onClick(() => {
                this.onResignIn()
              })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
    }
  }
}
