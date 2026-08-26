/**
 * HomeDailyNoteCard.ets
 * 主页实时便笺卡（对齐 Windows HomeCardDailyNoteCard）：
 * 头部（图标+UID+刷新时间）、主体三分块：树脂/宝钱+委托/折扣+参变仪，带阈值红点提示。
 * 整卡可点击 → 便笺页。
 */
import { DailyNote, Expedition } from '../model/DailyNote';
import { PressCard } from './PressCard';
import { NavIcon } from './NavIcon';
import { MetaIcon } from './MetaIcon';

@Component
export struct HomeDailyNoteCard {
  @Prop uid: string = '';
  @Prop note: DailyNote | undefined = undefined;
  @Prop refreshTime: string = '';
  @Prop loaded: boolean = false;
  /** 树脂阈值提示（默认 120） */
  @Prop resinThreshold: number = 120;
  /** 洞天宝钱阈值提示（默认 1800） */
  @Prop homeCoinThreshold: number = 1800;
  onTap: () => void = () => {
  };

  @Builder
  loadingView() {
    Column({ space: 8 }) {
      LoadingProgress()
        .width(24)
        .height(24)
        .color($r('app.color.app_primary'))
      Text('便笺加载中...')
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
      NavIcon({ name: 'DailyNote', iconSize: 28 })
      Text('暂无便笺数据')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Text('登录后自动拉取树脂/派遣/宝钱')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(140)
    .justifyContent(FlexAlign.Center)
  }

  /** 圆点提示（阈值达成显示主题色圆点） */
  @Builder
  dot(visible: boolean) {
    Circle()
      .width(7)
      .height(7)
      .fill($r('app.color.app_primary'))
      .margin({ top: 2 })
      .opacity(visible ? 1 : 0)
  }

  /** 游戏素材图标块（对齐 Windows DailyNoteCard：UI_ItemIcon_106/UI_MarkQuest_* 等） */
  @Builder
  block(category: string, icon: string, text: string, sub: string, dotVisible: boolean, wide: boolean) {
    Row({ space: 8 }) {
      MetaIcon({ category: category, name: icon, iconSize: wide ? 22 : 18, remoteFallback: true })
      Column({ space: 1 }) {
        Text(text)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(sub)
          .fontSize(10)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      this.dot(dotVisible)
    }
    .width('100%')
    .height(wide ? 64 : 28)
    .padding({ left: 8, right: 8, top: wide ? 0 : 4, bottom: wide ? 0 : 4 })
    .borderRadius(8)
    .backgroundColor($r('app.color.page_background'))
  }

  build() {
    PressCard({
      onTap: () => {
        this.onTap()
      },
      cardBg: $r('app.color.card_background'),
      radius: 12,
    }) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          NavIcon({ name: 'DailyNote', iconSize: 20 })
          Text('实时便笺')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          if (this.refreshTime.length > 0) {
            Text(`刷新 ${this.refreshTime}`)
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')

        if (!this.loaded) {
          this.loadingView()
        } else if (this.note === undefined) {
          this.emptyView()
        } else {
          Row({ space: 8 }) {
            // 列1：树脂（大块）
            this.block('ItemIcon', 'UI_ItemIcon_106', `${this.note.currentResin}/${this.note.maxResin}`,
              `树脂${this.note.resinReached(this.resinThreshold) ? '·已达标' : ''}`,
              this.note.resinReached(this.resinThreshold), true)
          }
          .width('100%')

          Row({ space: 8 }) {
            // 列2：宝钱 / 委托
            Column({ space: 4 }) {
              this.block('ItemIcon', 'UI_ItemIcon_204', `${this.note.currentHomeCoin}/${this.note.maxHomeCoin}`,
                '洞天宝钱', this.note.homeCoinReached(this.homeCoinThreshold), false)
              this.block('Mark', 'UI_MarkQuest_Events_Proce', `${this.note.finishedTaskNum}/${this.note.totalTaskNum}`,
                this.note.totalTaskNum > 0 && this.note.finishedTaskNum >= this.note.totalTaskNum ? '每日任务已完成' : '每日委托',
                this.note.dailyTask.isAllFinished(), false)
            }
            .layoutWeight(1)
            .padding(0)

            // 列3：周本折扣 / 参变仪
            Column({ space: 4 }) {
              this.block('Mark', 'UI_MarkTower', `${this.note.remainResinDiscountNum}/${this.note.resinDiscountNumLimit}`,
                '周本折扣', this.note.remainResinDiscountNum > 0, false)
              this.block('ItemIcon', 'UI_ItemIcon_220021', this.note.transformer.text(),
                this.note.transformer.isReady() ? '参变仪已就绪' : '参变仪恢复中',
                this.note.transformer.isReady(), false)
            }
            .layoutWeight(1)
            .padding(0)
          }
          .width('100%')

          if (this.note.expeditions.length > 0) {
            Row({ space: 6 }) {
              NavIcon({ name: 'DailyNote', iconSize: 14 })
              Text(`派遣 ${this.note.currentExpeditionNum}/${this.note.maxExpeditionNum}`)
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
              ForEach(this.note.expeditions, (exp: Expedition, idx: number) => {
                Text(exp.isFinished() ? '已归' : '进行中')
                  .fontSize(10)
                  .fontColor(exp.isFinished() ? $r('app.color.success') : $r('app.color.notice_on'))
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(6)
                  .backgroundColor($r('app.color.page_background'))
                  .maxLines(1)
              }, (exp: Expedition, idx: number) => `exp_${idx}_${exp.status}`)
              Blank()
            }
            .width('100%')
          }
        }
      }
      .width('100%')
      .padding(14)
    }
  }
}
