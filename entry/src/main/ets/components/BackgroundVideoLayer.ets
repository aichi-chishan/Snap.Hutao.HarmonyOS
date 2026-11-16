import { BackgroundMediaService } from '../service/BackgroundMediaService';
import { PreferencesStore } from '../data/prefs/PreferencesStore';

/** 一个源对应一个控制器；旧 Video 的晚到回调只能访问自己的播放器。 */
class BackgroundVideoSource {
  id: number;
  path: string;
  controller: VideoController = new VideoController();
  prepared: boolean = false;
  visible: boolean = false;

  constructor(id: number, path: string) {
    this.id = id;
    this.path = path;
  }
}

@Component
export struct BackgroundVideoLayer {
  @StorageProp('backgroundMediaVersion') @Watch('loadSource') version: number = 0;
  @StorageProp('appForeground') @Watch('syncPlayback') foreground: boolean = true;
  @State sources: BackgroundVideoSource[] = [];
  @State muted: boolean = true;
  @State looping: boolean = true;
  private sequence: number = 0;
  private attached: boolean = false;

  aboutToAppear(): void {
    this.attached = true;
    this.loadSource();
  }
  aboutToDisappear(): void {
    this.attached = false;
    this.sequence++;
    this.stopCurrent();
  }

  async loadSource(): Promise<void> {
    if (!this.attached) { return; }
    const sequence: number = ++this.sequence;
    this.stopCurrent();
    this.sources = [];
    this.muted = PreferencesStore.getBool(BackgroundMediaService.MUTED_KEY, true);
    this.looping = PreferencesStore.getBool(BackgroundMediaService.LOOP_KEY, true);
    try {
      const source: string = await BackgroundMediaService.source();
      if (sequence !== this.sequence) { return; }
      if (source.length > 0) { this.sources = [new BackgroundVideoSource(sequence, source)]; }
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
    const source: BackgroundVideoSource | undefined = this.sources[0];
    if (source === undefined || !this.isCurrent(source) || !source.prepared) { return; }
    if (this.foreground && source.visible) { source.controller.start(); } else { source.controller.pause(); }
  }

  private isCurrent(source: BackgroundVideoSource): boolean {
    return this.attached && source.id === this.sequence;
  }

  private stopCurrent(): void {
    const source: BackgroundVideoSource | undefined = this.sources[0];
    if (source !== undefined && source.prepared) { source.controller.stop(); }
  }

  private onPrepared(source: BackgroundVideoSource): void {
    if (!this.isCurrent(source)) { return; }
    source.prepared = true;
    this.syncPlayback();
  }

  private onVisibilityChanged(source: BackgroundVideoSource, ratio: number): void {
    if (!this.isCurrent(source)) { return; }
    source.visible = ratio > 0;
    this.syncPlayback();
  }

  private onStarted(source: BackgroundVideoSource): void {
    // start 请求提交后也可能立即切后台/离页，不能让晚到的开始事件恢复播放。
    if (!this.isCurrent(source) || !this.foreground || !source.visible) { source.controller.pause(); }
  }

  private onPlaybackError(source: BackgroundVideoSource): void {
    if (!this.isCurrent(source)) { return; }
    this.sequence++;
    this.sources = [];
    AppStorage.setOrCreate('backgroundMediaStatus', '视频播放失败，继续显示背景图片');
  }

  build() {
    Stack() {
      ForEach(this.sources, (source: BackgroundVideoSource) => {
        Video({ src: source.path, controller: source.controller })
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .controls(false)
          .autoPlay(false)
          .muted(this.muted)
          .loop(this.looping)
          .onPrepared(() => { this.onPrepared(source); })
          .onStart(() => { this.onStarted(source); })
          .onError(() => { this.onPlaybackError(source); })
          .onVisibleAreaChange([0, 1], (_visible: boolean, ratio: number) => { this.onVisibilityChanged(source, ratio); })
      }, (source: BackgroundVideoSource): string => source.id.toString())
      if (this.sources.length > 0) {
        Column().width('100%').height('100%').backgroundColor($r('app.color.wallpaper_mask'))
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .hitTestBehavior(HitTestMode.None)
  }
}
