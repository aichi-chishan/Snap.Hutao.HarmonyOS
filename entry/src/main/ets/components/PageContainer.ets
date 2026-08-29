/**
 * PageContainer.ets
 * 内容页容器：为内嵌页面（自定义组件无法直接挂通用属性）提供统一的
 * 进出场转场载体（配合 Motion.pageSwitch 实现宽屏内容切换动画）。
 */
import { Motion } from '../common/Motion';

@Component
export struct PageContainer {
  @BuilderParam content: () => void = emptyContent;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .transition(Motion.pageSwitch())
  }
}

@Builder
function emptyContent() {
}
