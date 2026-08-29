/**
 * HomeAchievementCard.ets
 * 主页成就管理卡（对齐 Windows AchievementCard）：
 * 头部（图标+标题）、主体：完成度环形进度 + 完成/总数 + 原石进度。整卡可点击 → 成就管理页。
 */
import { AchievementService } from '../service/AchievementService';
import { AchievementArchive, AchievementStats } from '../model/AchievementData';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';

@Component
export struct HomeAchievementCard {
  @State stats: AchievementStats = new AchievementStats();
  @State loaded: boolean = false;
  onTap: () => void = () => {
  };

  aboutToAppear(): void {
    this.reload();
  }

  async reload(): Promise<void> {
    try {
      const archives: AchievementArchive[] = await AchievementService.ensureDefaultArchive();
      let target: AchievementArchive | undefined = undefined;
      for (const a of archives) {
        if (a.isSelected) {
          target = a;
          break;
        }
      }
      if (target === undefined) {
        target = archives[0];
      }
      this.stats = await AchievementService.getOverallStats(target.id);
      this.loaded = true;
    } catch (e) {
      this.loaded = true;
    }
  }

  build() {
    PressCard({
      onTap: () => {
        this.onTap();
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Column({ space: 10 }) {
        // 头部
        Row({ space: 8 }) {
          NavIcon({ name: 'Achievement', iconSize: 20 })
          Text('成就管理')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(`${this.stats.percent()}%`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_primary'))
        }
        .width('100%')

        if (!this.loaded) {
          Row({ space: 10 }) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color($r('app.color.app_primary'))
            Text('成就统计加载中...')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .height(84)
          .justifyContent(FlexAlign.Center)
        } else {
          Row({ space: 14 }) {
            // 完成度环形
            Stack({ alignContent: Alignment.Center }) {
              Progress({
                value: this.stats.done,
                total: this.stats.total > 0 ? this.stats.total : 1,
                type: ProgressType.Ring,
              })
                .width(74)
                .height(74)
                .color($r('app.color.app_primary'))
                .style({ strokeWidth: 7 })
              Column({ space: 0 }) {
                Text(`${this.stats.done}`)
                  .fontSize(17)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                Text(`/ ${this.stats.total}`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
            }

            Column({ space: 6 }) {
              Text('成就完成度')
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
              Progress({
                value: this.stats.done,
                total: this.stats.total > 0 ? this.stats.total : 1,
                type: ProgressType.Linear,
              })
                .width('100%')
                .color($r('app.color.app_primary'))
                .backgroundColor($r('app.color.divider'))
              Text(`原石 ${this.stats.primogemsEarned} / ${this.stats.primogemsTotal}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
    }
  }
}
