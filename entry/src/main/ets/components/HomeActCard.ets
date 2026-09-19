/**
 * HomeActCard.ets
 * 主页活动/卡池卡（Windows：活动网格 + 卡池横幅）：
 * 名称、类型标记、状态（进行中/剩 N 天）、卡池显示角色头像行；
 * 活动卡显示首奖励图标（对齐 Windows AnnouncementPage.xaml:202-251 首奖励按钮），
 * 点击奖励区弹出奖励网格半窗（Windows 同位置 Flyout，UniformGridColumns4）；
 * 卡片底部按活动类型显示进度行（深境螺旋星数/剧诗最高回合/幽境危战/探索度）。
 * 可点击 → 活动日历。
 */
import { ActCalendarEntry, ActCalendarType, ActRewardEntry } from '../model/ActCalendarEntry';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';
import { MetaIcon } from './MetaIcon';

@Component
export struct HomeActCard {
  @Prop entry: ActCalendarEntry = new ActCalendarEntry();
  @State showRewardSheet: boolean = false;
  onTap: () => void = () => {
  };

  isCardPool(): boolean {
    return this.entry.type === ActCalendarType.CARD_POOL;
  }

  statusText(): string {
    const now: number = Date.now();
    return this.entry.statusText(now);
  }

  /** 首奖励（Windows RewardList[0]） */
  firstReward(): ActRewardEntry | undefined {
    return this.entry.rewards.length > 0 ? this.entry.rewards[0] : undefined;
  }

  @Builder
  rewardCell(reward: ActRewardEntry) {
    Column({ space: 4 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        MetaIcon({ category: 'ItemIcon', name: reward.iconName(), iconSize: 48, remoteFallback: true })
        Text(reward.num > 0 ? `×${reward.num}` : '')
          .fontSize(10)
          .fontColor(Color.White)
          .width('100%')
          .textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.reward_badge_scrim'))
          .padding({ top: 1, bottom: 1 })
      }
      .width(56)
      .height(56)
      Text(reward.name)
        .fontSize(11)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(6)
    .borderRadius(8)
    .backgroundColor($r('app.color.card_inner_tint'))
  }

  /** 奖励网格半窗（对齐 Windows 活动卡 Flyout：UniformGridColumns4Spacing6，图标 + 数量角标） */
  @Builder
  rewardSheet() {
    Column({ space: 10 }) {
      Text(this.entry.name)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(`共 ${this.entry.rewards.length} 项奖励`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Scroll() {
        Grid() {
          ForEach(this.entry.rewards, (reward: ActRewardEntry) => {
            GridItem() {
              this.rewardCell(reward)
            }
          }, (reward: ActRewardEntry) => `rw_${reward.itemId}_${reward.name}_${reward.num}`)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }

  build() {
    PressCard({ onTap: () => {
      this.onTap()
    } }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          // 官方 Database/活动图标（Windows 素材），无 emoji
          NavIcon({ name: this.isCardPool() ? 'GachaLog' : 'Database', iconSize: 20 })
            .width(36)
            .height(36)
            .padding(8)
            .borderRadius(10)
            .backgroundColor(this.isCardPool() ? $r('app.color.app_primary_bg') : $r('app.color.notice_bg'))
          Column({ space: 2 }) {
            Text(this.entry.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.isCardPool() ? `${this.entry.versionName}` : this.entry.desc.length > 12 ? `${this.entry.desc.substring(0, 12)}…` : this.entry.desc)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          // 首奖励图标（Windows AnnouncementPage 活动卡右上按钮；点击弹奖励网格半窗）
          if (this.firstReward() !== undefined) {
            Stack({ alignContent: Alignment.Bottom }) {
              MetaIcon({ category: 'ItemIcon', name: this.firstReward()!.iconName(), iconSize: 28, remoteFallback: true })
              Text(this.firstReward()!.num > 0 ? `×${this.firstReward()!.num}` : '')
                .fontSize(9)
                .fontColor(Color.White)
                .width('100%')
                .textAlign(TextAlign.Center)
                .backgroundColor($r('app.color.reward_badge_scrim'))
            }
            .width(30)
            .height(30)
            .borderRadius(7)
            .clip(true)
            .hoverEffect(HoverEffect.Highlight)
            // 子组件手势优先：此处点击不会触发外层 PressCard 的日历跳转
            .onClick(() => {
              this.showRewardSheet = true;
            })
          }
          Text(this.statusText())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.entry.isOngoing(Date.now()) ? $r('app.color.success') : $r('app.color.notice_on'))
        }
        .width('100%')

        if (this.entry.avatarIcons.length > 0) {
          Row({ space: 4 }) {
            ForEach(this.entry.avatarIcons, (icon: string) => {
              Image(icon.length > 0 ? icon : '')
                .width(26)
                .height(26)
                .borderRadius(13)
                .objectFit(ImageFit.Cover)
                .backgroundColor($r('app.color.app_primary_bg'))
            }, (icon: string, idx: number) => `act_av_${idx}_${icon}`)
            Blank()
            Text(HomeActCard.formatDate(this.entry.endTime))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        } else {
          Row() {
            Blank()
            Text(HomeActCard.formatDate(this.entry.endTime))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }

        // 按活动类型的进度行（tower/role_combat/hard_challenge/explore detail 存在才显示）
        if (this.entry.progressLine().length > 0) {
          Text(this.entry.progressLine())
            .fontSize(11)
            .fontColor($r('app.color.notice_on'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .padding(12)
      .borderRadius($r('app.float.card_radius'))
      .backgroundColor($r('app.color.card_background'))
      .border({ width: 1, color: this.isCardPool() ? $r('app.color.app_primary') : $r('app.color.divider') })
      // 奖励网格半窗（$$ 双向同步下滑关闭）
      .bindSheet($$this.showRewardSheet, this.rewardSheet(), {
        title: { title: '活动奖励' },
        showClose: true,
        dragBar: true,
        height: 420,
        backgroundColor: $r('app.color.card_background'),
      })
    }
  }

  private static formatDate(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d: Date = new Date(ts);
    return `${d.getMonth() + 1}.${d.getDate()} 结束`;
  }
}
