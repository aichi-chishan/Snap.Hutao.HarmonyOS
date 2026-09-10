/**
 * DailyNoteCard.ets — 实时便笺桌面卡片（ArkTS 卡片, rootId: DailyNoteCard）
 * 紧凑布局：树脂恢复进度（环形 + 当前/上限）+ 恢复时间 + 每日委托 + 派遣。
 *
 * 数据链路（API 23+ V2 卡片，依据官方《卡片状态变量迁移》文档）：
 * FormExtensionAbility 通过 createFormBindingData/updateForm 推送的数据键：
 *   nickname / resin / maxResin / expeditionText / dailyText / homeCoinText
 *   / refreshText / resinRecoveryText / tipText
 * 手动刷新：卡片右上角 ⟳ → postCardAction(message) → FormExtensionAbility.onFormEvent。
 * 卡片侧使用 @Entry @ComponentV2（无需 LocalStorage），@Local 变量名与推送键一一对应，
 * 系统按变量名匹配注入刷新数据。注意：@ComponentV2 不支持 LocalStorage 相关能力，
 * 严禁回退为 @Entry(storage) + storage.get('formData') 的写法。
 */
/** 卡片 → FormExtensionAbility 的 message 事件参数（ArkTS 禁止未类型化对象字面量） */
interface CardMessageParams {
  method: string;
}

interface CardMessageAction {
  action: string;
  params: CardMessageParams;
}

@Entry
@ComponentV2
struct DailyNoteCard {
  @Local nickname: string = '--';
  @Local resin: string = '--';
  @Local maxResin: string = '--';
  @Local expeditionText: string = '--';
  @Local dailyText: string = '--';
  @Local homeCoinText: string = '--';
  @Local refreshText: string = '--';
  @Local resinRecoveryText: string = '--';
  /** 卡片内状态提示（刷新中/失败原因），由提供方推送；空串表示无提示 */
  @Local tipText: string = '';

  private resinNum(): number {
    const n: number = Number(this.resin);
    return Number.isNaN(n) ? 0 : n;
  }

  /** 手动刷新：message 事件 → FormExtensionAbility.onFormEvent（拉取最新便笺并回推卡片） */
  private requestRefresh(): void {
    const action: CardMessageAction = { action: 'message', params: { method: 'refresh' } };
    postCardAction(this, action);
  }

  private maxResinNum(): number {
    const n: number = Number(this.maxResin);
    return Number.isNaN(n) || n <= 0 ? 160 : n;
  }

  build() {
    Column() {
      // 标题行
      Row() {
        Text('树脂')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.nickname)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 手动刷新按钮（对齐系统卡片交互：点击触发提供方拉取最新数据）
        Text('⟳')
          .fontSize(13)
          .fontColor($r('app.color.app_primary'))
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .borderRadius(11)
          .backgroundColor($r('app.color.app_primary_bg'))
          .margin({ left: 6 })
          .onClick(() => {
            this.requestRefresh();
          })
      }
      .width('100%')
      .height(20)

      // 树脂：环形 + 数值/进度 + 恢复时间
      Row({ space: 10 }) {
        Progress({ value: this.resinNum(), total: this.maxResinNum(), type: ProgressType.Ring })
          .width(62)
          .height(62)
          .color($r('app.color.app_primary'))
          .style({ strokeWidth: 7 })
        Column({ space: 2 }) {
          Row() {
            Text(this.resin)
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(`/ ${this.maxResin}`)
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
          }
          Text(this.resinRecoveryText)
            .fontSize(12)
            .fontColor($r('app.color.app_primary'))
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height(66)

      // 每日委托
      Row({ space: 8 }) {
        Text(this.dailyText)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(22)

      // 派遣
      Row({ space: 8 }) {
        Text(this.expeditionText)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(22)

      // 洞天 / 状态提示 + 更新时间
      Row() {
        if (this.tipText.length > 0) {
          Text(this.tipText)
            .fontSize(11)
            .fontColor($r('app.color.app_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Text(`洞天 ${this.homeCoinText}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(`更新 ${this.refreshText}`)
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
      }
      .width('100%')
      .height(18)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }
}
