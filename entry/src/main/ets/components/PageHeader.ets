/**
 * PageHeader.ets
 * 统一页面标题栏（全项目复用）：
 *  - embedMode：宽屏内嵌时隐藏返回按钮、去除状态栏避让（由 Shell 统一处理）
 *  - 标题 + 右侧操作区（@BuilderParam slot）
 *  - 对齐 Windows 页面头部：标题左置、操作右置、安全区避让
 * 用法：
 *   PageHeader({ title: '我的角色', embedMode: this.embedMode }) {
 *     Button('刷新')...
 *   }
 */
import { AppBackButton } from './AppBackButton';

@Component
export struct PageHeader {
  /** 标题 */
  @Prop title: string = '';
  /** 宽屏内嵌模式：隐藏返回按钮、去状态栏避让 */
  @Prop embedMode: boolean = false;
  /** 状态栏避让高度（embedMode 时忽略） */
  @Prop topAvoidVp: number = 0;

  /** 标题内联衬线（供左侧额外元素如返回气泡之后）；默认空实现（未传 builder 不崩溃） */
  @BuilderParam actions: () => void = PageHeader.emptyActions;

  @Builder
  static emptyActions() {
  }

  build() {
    Row() {
      if (!this.embedMode) {
        AppBackButton()
      }
      Text(this.title)
        .fontSize($r('app.float.page_title_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: this.embedMode ? 0 : 10 })
      Blank()
      this.actions()
    }
    .width('100%')
    .padding({
      left: 16,
      right: 12,
      top: (this.embedMode ? 0 : this.topAvoidVp) + 10,
      bottom: 10,
    })
    .alignItems(VerticalAlign.Center)
  }
}
