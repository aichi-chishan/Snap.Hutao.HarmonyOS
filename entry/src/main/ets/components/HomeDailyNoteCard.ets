/**
 * HomeDailyNoteCard.ets
 * 主页实时便笺卡（对齐 Windows HomeCardDailyNoteCard）：
 * 头部（图标+UID+刷新时间）、主体三分块：树脂/宝钱+委托/折扣+参变仪，带阈值红点提示。
 * 整卡可点击 → 便笺页。
 *
 * ⚠ ArkUI @Builder 传参规则（官方文档）：「@Builder 按引用传递且仅传入一个参数时才会触发动态渲染」，
 * 传入两个及以上参数时 @Builder 内部 UI 不会随状态刷新。因此本组件所有会变的文案/红点
 * 一律在渲染期通过私有方法读取组件状态（this.note / 阈值），@Builder 参数只传常量槽位。
 * 历史 bug：便笺自动刷新后卡面数值不更新（刷新时间变了、树脂数值没变）。
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

  /** 分块槽位常量（@Builder 参数必须恒定，动态内容走组件状态） */
  private static readonly SLOT_RESIN: number = 0;
  private static readonly SLOT_HOME_COIN: number = 1;
  private static readonly SLOT_TASK: number = 2;
  private static readonly SLOT_DISCOUNT: number = 3;
  private static readonly SLOT_TRANSFORMER: number = 4;

  /** note 为空时的占位对象（避免 builder 内做 undefined 分支） */
  private placeholder: DailyNote = new DailyNote();

  /** 当前便笺（渲染期读取组件状态 → 参与依赖收集） */
  private cur(): DailyNote {
    return this.note !== undefined ? this.note : this.placeholder;
  }

  private blockCategory(slot: number): string {
    if (slot === HomeDailyNoteCard.SLOT_HOME_COIN || slot === HomeDailyNoteCard.SLOT_TRANSFORMER) {
      return 'ItemIcon';
    }
    return slot === HomeDailyNoteCard.SLOT_RESIN ? 'ItemIcon' : 'Mark';
  }

  private blockIcon(slot: number): string {
    if (slot === HomeDailyNoteCard.SLOT_RESIN) {
      return 'UI_ItemIcon_106';
    }
    if (slot === HomeDailyNoteCard.SLOT_HOME_COIN) {
      return 'UI_ItemIcon_204';
    }
    if (slot === HomeDailyNoteCard.SLOT_TASK) {
      return 'UI_MarkQuest_Events_Proce';
    }
    if (slot === HomeDailyNoteCard.SLOT_DISCOUNT) {
      return 'UI_MarkTower';
    }
    return 'UI_ItemIcon_220021';
  }

  private blockText(slot: number): string {
    const n: DailyNote = this.cur();
    if (slot === HomeDailyNoteCard.SLOT_RESIN) {
      return `${n.currentResin}/${n.maxResin}`;
    }
    if (slot === HomeDailyNoteCard.SLOT_HOME_COIN) {
      return `${n.currentHomeCoin}/${n.maxHomeCoin}`;
    }
    if (slot === HomeDailyNoteCard.SLOT_TASK) {
      return `${n.finishedTaskNum}/${n.totalTaskNum}`;
    }
    if (slot === HomeDailyNoteCard.SLOT_DISCOUNT) {
      return `${n.remainResinDiscountNum}/${n.resinDiscountNumLimit}`;
    }
    return n.transformer.text();
  }

  private blockSub(slot: number): string {
    const n: DailyNote = this.cur();
    if (slot === HomeDailyNoteCard.SLOT_RESIN) {
      return `树脂${n.resinReached(this.resinThreshold) ? '·已达标' : ''}`;
    }
    if (slot === HomeDailyNoteCard.SLOT_HOME_COIN) {
      return '洞天宝钱';
    }
    if (slot === HomeDailyNoteCard.SLOT_TASK) {
      return n.totalTaskNum > 0 && n.finishedTaskNum >= n.totalTaskNum ? '每日任务已完成' : '每日委托';
    }
    if (slot === HomeDailyNoteCard.SLOT_DISCOUNT) {
      return '周本折扣';
    }
    return n.transformer.isReady() ? '参变仪已就绪' : '参变仪恢复中';
  }

  private blockDot(slot: number): boolean {
    const n: DailyNote = this.cur();
    if (slot === HomeDailyNoteCard.SLOT_RESIN) {
      return n.resinReached(this.resinThreshold);
    }
    if (slot === HomeDailyNoteCard.SLOT_HOME_COIN) {
      return n.homeCoinReached(this.homeCoinThreshold);
    }
    if (slot === HomeDailyNoteCard.SLOT_TASK) {
      return n.dailyTask.isAllFinished();
    }
    if (slot === HomeDailyNoteCard.SLOT_DISCOUNT) {
      return n.remainResinDiscountNum > 0;
    }
    return n.transformer.isReady();
  }

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
        .fontSize(12)
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

  /** 游戏素材图标块（对齐 Windows DailyNoteCard：UI_ItemIcon_106/UI_MarkQuest_* 等）。
   *  slot 为常量槽位；文案/红点在渲染期读组件状态，保证便笺刷新后同步。 */
  @Builder
  block(slot: number, wide: boolean) {
    Row({ space: 8 }) {
      MetaIcon({ category: this.blockCategory(slot), name: this.blockIcon(slot), iconSize: wide ? 22 : 18, remoteFallback: true })
      Column({ space: 1 }) {
        Text(this.blockText(slot))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.blockSub(slot))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Circle()
        .width(7)
        .height(7)
        .fill($r('app.color.app_primary'))
        .margin({ top: 2 })
        .opacity(this.blockDot(slot) ? 1 : 0)
    }
    .width('100%')
    .height(wide ? 64 : 28)
    .padding({ left: 8, right: 8, top: wide ? 0 : 4, bottom: wide ? 0 : 4 })
    .borderRadius(8)
    .backgroundColor($r('app.color.card_inner_tint'))
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
              .fontSize(12)
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
            this.block(HomeDailyNoteCard.SLOT_RESIN, true)
          }
          .width('100%')

          Row({ space: 8 }) {
            // 列2：宝钱 / 委托
            Column({ space: 4 }) {
              this.block(HomeDailyNoteCard.SLOT_HOME_COIN, false)
              this.block(HomeDailyNoteCard.SLOT_TASK, false)
            }
            .layoutWeight(1)
            .padding(0)

            // 列3：周本折扣 / 参变仪
            Column({ space: 4 }) {
              this.block(HomeDailyNoteCard.SLOT_DISCOUNT, false)
              this.block(HomeDailyNoteCard.SLOT_TRANSFORMER, false)
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
                  .fontSize(12)
                  .fontColor(exp.isFinished() ? $r('app.color.success') : $r('app.color.notice_on'))
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(6)
                  .backgroundColor($r('app.color.card_inner_tint'))
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
