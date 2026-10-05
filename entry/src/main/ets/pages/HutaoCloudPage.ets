/**
 * HutaoCloudPage.ets
 * 胡桃通行证与云 —— **入口占位页**。
 *
 * 范围约定（见 AGENTS.md / PORTING_PLAN.md）：本移植版不接入胡桃云服务器功能
 * （通行证登录、云存档、云统计、云备份、云攻略、云壁纸、反馈页）。
 * 因此本页只保留导航/首页入口占位，说明不提供该能力：
 *   - 不发任何网络请求，不读写凭据，不落库；
 *   - 与米游社（游戏账号）登录、本地归档完全独立，不受影响。
 * 如需恢复云能力，需在独立分支重新引入实现并单独评审。
 */
import { PageHeader } from '../components/PageHeader';
import { PageBackdrop } from '../components/PageBackdrop';

@Entry
@Component
export struct HutaoCloudPage {
  @Prop embedMode: boolean = false;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;

  build() {
    Stack() {
      PageBackdrop({ embedMode: this.embedMode })
      Column({ space: 10 }) {
        PageHeader({ title: '胡桃通行证与云', embedMode: this.embedMode, topAvoidVp: this.topAvoidVp })
        Column({ space: 10 }) {
          Text('本移植版不提供胡桃云功能').fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).width('100%')
          Text('通行证登录、云存档、云统计、云备份、云攻略、云壁纸与反馈页均不在移植范围内，本页为入口占位，不含任何实现，也不会发起网络请求。')
            .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
          Text('游戏账号（米游社）登录与本地归档不受影响：见「系统 → 账号与数据」。')
            .fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start).padding(14)
          .borderRadius($r('app.float.card_radius')).backgroundColor($r('app.color.card_surface'))
          .border({ width: 1, color: $r('app.color.card_stroke') })
      }
      .width('100%').height('100%').alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, bottom: 16 })
    }.width('100%').height('100%')
  }
}
