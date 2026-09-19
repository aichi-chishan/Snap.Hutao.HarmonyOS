/**
 * PageBackdrop.ets
 * 页面级壁纸衬底（对齐 Windows「全透明页面栈 + 系统材质」观感）：
 * router 独立页的根 Stack 底层铺一层 WallpaperLayer，让推入页与壳层一样透出壁纸。
 * embed 内嵌时由 Index 壳层统一铺壁纸，此处跳过，避免壁纸图双份加载。
 */
import { WallpaperLayer } from './WallpaperLayer';

@Component
export struct PageBackdrop {
  /** 宽屏内嵌模式：壳层已铺壁纸，此组件渲染为空（透明透出壳层壁纸） */
  @Prop embedMode: boolean = false;
  @StorageProp('bgType') bgType: string = 'local';
  @StorageProp('bgFolderPath') bgFolderPath: string = '';

  build() {
    Stack() {
      if (!this.embedMode) {
        WallpaperLayer({ bgType: this.bgType, folderPath: this.bgFolderPath })
      }
    }
    .width('100%')
    .height('100%')
  }
}
