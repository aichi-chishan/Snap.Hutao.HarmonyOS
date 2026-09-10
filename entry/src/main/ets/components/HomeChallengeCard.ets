/**
 * HomeChallengeCard.ets
 * 主页周期挑战进度卡（对齐 Windows 主页挑战概览）：三格
 *   深境螺旋（最深层/总星）| 幻想真境剧诗（奖章/历战）| 幽境危战（最佳难度/秒数）
 * 登录未拉取时显示占位；点击进入对应页面。
 */
import { HomeChallengeSummary } from '../viewmodel/HomeViewModel';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';

@Component
export struct HomeChallengeCard {
  /** 数据（HomeViewModel.challenge） */
  @Prop data: HomeChallengeSummary = new HomeChallengeSummary();
  /** 点击事件（opener 决定跳转页面） */
  onTap: (index: number) => void = () => {
  };

  build() {
    PressCard({
      onTap: () => {
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          NavIcon({ name: 'SpiralAbyss', iconSize: 18 })
          Text('周期挑战')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text('点击进入 ›')
            .fontSize(12)
            .fontColor($r('app.color.app_primary'))
        }
        .width('100%')

        if (!this.data.loaded) {
          Text('加载中...')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 10, bottom: 10 })
        } else {
          Row({ space: 8 }) {
            this.slotCell(HomeChallengeCard.SLOT_ABYSS)
            this.slotCell(HomeChallengeCard.SLOT_ROLE_COMBAT)
            this.slotCell(HomeChallengeCard.SLOT_HARD)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
      .width('100%')
      .padding(4)
    }
  }

  private abyssText(): string {
    if (this.data.abyssStar > 0 || this.data.abyssFloor.length > 0) {
      return `${this.data.abyssStar}★ ${this.data.abyssFloor}`;
    }
    return '暂无数据';
  }

  private roleCombatText(): string {
    if (this.data.roleCombatMedals > 0 || this.data.roleCombatMaxRound > 0) {
      if (this.data.roleCombatMaxRound > 0) {
        return `奖章 ${this.data.roleCombatMedals} · 历战 ${this.data.roleCombatMaxRound}`;
      }
      return `奖章 ${this.data.roleCombatMedals}`;
    }
    return '暂无数据';
  }

  private hardChallengeText(): string {
    if (this.data.hardChallengeBest.length > 0 || this.data.hardChallengeSecond > 0) {
      return `${this.data.hardChallengeBest.length > 0 ? this.data.hardChallengeBest : '挑战'} ${this.data.hardChallengeSecond > 0 ? HomeChallengeCard.sec(this.data.hardChallengeSecond) : ''}`;
    }
    return '暂无数据';
  }

  static sec(second: number): string {
    const m: number = Math.floor(second / 60);
    const s: number = second % 60;
    return m > 0 ? `${m}分${s}秒` : `${s}秒`;
  }

  /** 槽位常量（@Builder 多参数不参与刷新：数值在渲染期经方法读 this.data） */
  private static readonly SLOT_ABYSS: number = 0;
  private static readonly SLOT_ROLE_COMBAT: number = 1;
  private static readonly SLOT_HARD: number = 2;

  private slotIcon(slot: number): string {
    if (slot === HomeChallengeCard.SLOT_ABYSS) {
      return 'SpiralAbyss';
    }
    return slot === HomeChallengeCard.SLOT_ROLE_COMBAT ? 'RoleCombat' : 'HardChallenge';
  }

  private slotLabel(slot: number): string {
    if (slot === HomeChallengeCard.SLOT_ABYSS) {
      return '深境螺旋';
    }
    return slot === HomeChallengeCard.SLOT_ROLE_COMBAT ? '幻想真境剧诗' : '幽境危战';
  }

  private slotValue(slot: number): string {
    if (slot === HomeChallengeCard.SLOT_ABYSS) {
      return this.abyssText();
    }
    return slot === HomeChallengeCard.SLOT_ROLE_COMBAT ? this.roleCombatText() : this.hardChallengeText();
  }

  @Builder
  slotCell(slot: number) {
    Column({ space: 3 }) {
      Row({ space: 3 }) {
        NavIcon({ name: this.slotIcon(slot), iconSize: 12 })
        Text(this.slotLabel(slot))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      Text(this.slotValue(slot))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.app_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .padding(8)
    .borderRadius(8)
    .backgroundColor($r('app.color.page_background'))
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onTap(slot);
    })
  }
}
