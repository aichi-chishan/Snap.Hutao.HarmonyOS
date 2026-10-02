import { BackgroundMediaService } from '../service/BackgroundMediaService';
import { PreferencesStore } from '../data/prefs/PreferencesStore';

/** API7 Video/VideoController only; API26 async video controls are deliberately not used. */
@Component
export struct BackgroundVideoLayer {
  @StorageProp('backgroundMediaVersion') @Watch('loadSource') version: number = 0;
  @StorageProp('appForeground') @Watch('syncPlayback') foreground: boolean = true;
  @State source: string = '';
  @State muted: boolean = true;
  @State looping: boolean = true;
  private controller: VideoController = new VideoController();
  private visible: boolean = true;
  private sequence: number = 0;

  aboutToAppear(): void { this.loadSource(); }
  aboutToDisappear(): void {
    this.sequence++;
    this.controller.pause();
  }

  async loadSource(): Promise<void> {
    const sequence: number = ++this.sequence;
    this.controller.pause();
    this.source = '';
    this.muted = PreferencesStore.getBool(BackgroundMediaService.MUTED_KEY, true);
    this.looping = PreferencesStore.getBool(BackgroundMediaService.LOOP_KEY, true);
    try {
      const source: string = await BackgroundMediaService.source();
      if (sequence !== this.sequence) { return; }
      this.source = source;
      const enabled: boolean = PreferencesStore.getString(BackgroundMediaService.TYPE_KEY, 'none') !== 'none';
      AppStorage.setOrCreate('backgroundMediaStatus', source.length > 0
        ? '视频已就绪' : (enabled ? '未获取到视频，继续显示背景图片' : '已关闭背景视频'));
    } catch (_) {
      if (sequence === this.sequence) {
        AppStorage.setOrCreate('backgroundMediaStatus', '视频不可用，继续显示背景图片');
      }
    }
  }

  syncPlayback(): void {
    if (this.source.length === 0) { return; }
    if (this.foreground && this.visible) { this.controller.start(); } else { this.controller.pause(); }
  }

  build() {
    Stack() {
      if (this.source.length > 0) {
        Video({ src: this.source, controller: this.controller })
          .width('100%').height('100%').objectFit(ImageFit.Cover)
          .controls(false).autoPlay(this.foreground).muted(this.muted).loop(this.looping)
          .onPrepared(() => { this.syncPlayback(); })
          .onError(() => {
            this.source = '';
            AppStorage.setOrCreate('backgroundMediaStatus', '视频播放失败，继续显示背景图片');
          })
          .onVisibleAreaChange([0, 1], (_visible: boolean, ratio: number) => {
            this.visible = ratio > 0;
            this.syncPlayback();
          })
        Column().width('100%').height('100%').backgroundColor($r('app.color.wallpaper_mask'))
      }
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
  }
}
