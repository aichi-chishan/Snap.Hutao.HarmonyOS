import { common } from '@kit.AbilityKit';
import { router, UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { AppConstants } from '../common/Constants';
import { AppButtonModifier, UiSurface } from '../common/UiSurface';
import { PageHeader } from '../components/PageHeader';
import { OfficialWebActions, OfficialWebBridgeService, OfficialWebCallback, OfficialWebShareRequest } from '../service/OfficialWebBridgeService';
import { OfficialWebShareMode } from '../service/OfficialWebShareService';
import { OfficialWebViewModel } from '../viewmodel/OfficialWebViewModel';

class OfficialWebProxy {
  private receive: (message: string) => void;
  constructor(receive: (message: string) => void) { this.receive = receive; }
  postMessage(message: string): void { this.receive(message); }
}

class OfficialWebPageActions implements OfficialWebActions {
  private close: () => void;
  private open: (target: string) => void;
  private showShare: (request: OfficialWebShareRequest) => Promise<boolean>;

  constructor(close: () => void, open: (target: string) => void,
    showShare: (request: OfficialWebShareRequest) => Promise<boolean>) {
    this.close = close;
    this.open = open;
    this.showShare = showShare;
  }

  closePage(): void { this.close(); }
  openPage(target: string): void { this.open(target); }
  share(request: OfficialWebShareRequest): Promise<boolean> { return this.showShare(request); }
}

@Entry
@Component
export struct OfficialWebPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @StorageProp('currentUid') @Watch('ownerChanged') currentUid: string = '';
  @StorageProp('currentUserId') @Watch('ownerChanged') ownerId: number = 0;
  @State title: string = '米游社';
  @State showWeb: boolean = false;
  @State loading: boolean = true;
  @State failure: string = '';

  private vm: OfficialWebViewModel = new OfficialWebViewModel();
  private controller: webview.WebviewController = new webview.WebviewController();
  private attached: boolean = false;
  private active: boolean = false;
  private registered: boolean = false;
  private firstDocument: boolean = true;
  private documentVersion: number = 0;
  private documentUrl: string = '';
  private webWidth: number = 0;
  private preparingShare: boolean = false;

  aboutToAppear(): void {
    try {
      const params: Record<string, Object> | undefined = router.getParams() as Record<string, Object> | undefined;
      this.title = this.vm.select(params?.['kind'], this.currentUid);
      webview.WebviewController.enableWholeWebPageDrawing();
      this.active = true;
      this.showWeb = true;
    } catch (e) {
      this.failure = (e as Error).message;
      this.loading = false;
    }
  }

  onPageShow(): void { this.ownerChanged(); }

  aboutToDisappear(): void {
    const refreshSignIn: boolean = this.active && this.vm.isCurrent() && this.vm.isSignIn();
    this.dispose();
    if (refreshSignIn) {
      const version: number = AppStorage.get<number>('officialSignInVersion') ?? 0;
      AppStorage.setOrCreate<number>('officialSignInVersion', version + 1);
    }
  }

  ownerChanged(): void {
    if (this.active && !this.vm.isCurrent()) {
      this.dispose();
      this.showWeb = false;
      this.loading = false;
      this.failure = '账号或角色已切换，请重新打开官方页面';
    }
  }

  private dispose(): void {
    this.active = false;
    this.documentVersion++;
    this.vm.close();
    if (this.attached) {
      try { if (this.registered) { this.controller.deleteJavaScriptRegister(OfficialWebBridgeService.PROXY); } } catch (e) {}
      try { this.controller.stop(); } catch (e) {}
      try { webview.WebCookieManager.clearAllCookiesSync(true); } catch (e) {}
    }
    this.attached = false;
    this.registered = false;
  }

  private async load(): Promise<void> {
    if (!this.attached || !this.active || !this.vm.isCurrent()) { return; }
    this.loading = true;
    this.failure = '';
    this.documentVersion++;
    try {
      if (!this.registered) {
        webview.WebCookieManager.clearAllCookiesSync(true);
        this.controller.setCustomUserAgent(AppConstants.UA_MOBILE);
        const proxy: OfficialWebProxy = new OfficialWebProxy((message: string): void => { this.onMessage(message); });
        this.controller.registerJavaScriptProxy(proxy, OfficialWebBridgeService.PROXY, [], ['postMessage'], OfficialWebBridgeService.PERMISSION);
        this.registered = true;
      }
      await this.vm.prepare((): boolean => this.active && this.vm.isCurrent());
      if (!this.active || !this.vm.isCurrent()) { return; }
      this.documentUrl = this.vm.source();
      this.controller.loadUrl(this.documentUrl);
    } catch (e) {
      if (this.active) {
        this.loading = false;
        this.failure = '无法打开官方页面，请重试';
      }
    }
  }

  private async onMessage(message: string): Promise<void> {
    const version: number = this.documentVersion;
    const current = (): boolean => this.active && this.vm.isCurrent() && this.documentVersion === version &&
      OfficialWebViewModel.canLoad(this.documentUrl);
    if (!current()) { return; }
    const actions: OfficialWebPageActions = new OfficialWebPageActions(
      (): void => {
        if (!current()) { return; }
        if (!this.firstDocument && this.controller.accessBackward()) { this.controller.backward(); }
        else { router.back(); }
      },
      (target: string): void => {
        if (current()) { this.open(target); }
      },
      (request: OfficialWebShareRequest): Promise<boolean> => this.share(request, current),
    );
    const result: OfficialWebCallback | undefined = await this.vm.receive(message, actions, current);
    if (result === undefined || !current()) { return; }
    const script: string = `if (typeof window.mhyWebBridge === 'function') { window.mhyWebBridge(${JSON.stringify(result.name)},${result.result}); }`;
    try { await this.controller.runJavaScript(script); } catch (e) {}
  }

  private open(target: string): void {
    if (OfficialWebViewModel.canLoad(target)) {
      this.documentVersion++;
      this.documentUrl = target;
      this.controller.loadUrl(target);
      return;
    }
    const context: common.UIAbilityContext | undefined = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    context?.openLink(target).catch(() => { this.toast('无法打开米游社文章'); });
  }

  private async share(request: OfficialWebShareRequest, current: () => boolean): Promise<boolean> {
    if (this.preparingShare || !current()) { return false; }
    this.preparingShare = true;
    let pixelMap: image.PixelMap | undefined;
    try {
      const mode: OfficialWebShareMode = this.vm.shareMode();
      let width: number = 0;
      let height: number = 0;
      if (request.type === 'screenshot') {
        const ui: UIContext = this.getUIContext();
        width = ui.vp2px(this.webWidth);
        height = ui.vp2px(this.controller.getPageHeight());
      }
      pixelMap = await this.vm.shareImage(request, this.controller, width, height);
      if (!current()) { return false; }
      if (mode === OfficialWebShareMode.Copy) {
        await this.vm.copy(pixelMap);
        if (current()) { this.toast('已复制图片'); }
        return true;
      }
      const context: common.UIAbilityContext | undefined = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context === undefined) { return false; }
      const saved: boolean = await this.vm.save(pixelMap, context, current);
      if (saved && current()) { this.toast('图片已另存'); }
      return saved;
    } catch (e) {
      if (current()) { this.toast((e as Error).message || '分享图片失败'); }
      return false;
    } finally {
      if (pixelMap !== undefined) { await pixelMap.release().catch(() => {}); }
      this.preparingShare = false;
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message });
  }

  build() {
    Column() {
      PageHeader({ title: this.title, embedMode: false, topAvoidVp: this.topAvoidVp })
      if (this.failure.length > 0) {
        Text(this.failure).fontSize(14).fontColor($r('app.color.text_secondary')).margin({ top: 16, bottom: 8 })
        if (this.showWeb) {
          Button('重试', { type: ButtonType.Normal })
            .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
            .height(44).onClick(() => { this.load(); })
        }
      } else if (this.loading) {
        LoadingProgress().width(24).height(24).color($r('app.color.app_primary')).margin({ top: 8, bottom: 8 })
      }
      if (this.showWeb) {
        Web({ src: 'about:blank', controller: this.controller, incognitoMode: true })
          .width('100%').layoutWeight(1)
          .javaScriptAccess(true).domStorageAccess(true).fileAccess(false).mixedMode(MixedMode.None)
          .runJavaScriptOnDocumentStart([{ script: OfficialWebBridgeService.SCRIPT,
            scriptRules: ['https://webstatic.mihoyo.com', 'https://act.mihoyo.com'] }])
          .onControllerAttached(() => { this.attached = true; this.load(); })
          .onAreaChange((_old: Area, area: Area) => { this.webWidth = Number(area.width); })
          .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
            const target: string = event.data.getRequestUrl();
            return event.data.isMainFrame() && target !== 'about:blank' && (!this.active || !OfficialWebViewModel.canLoad(target));
          })
          .onPageBegin((event: OnPageBeginEvent) => {
            if (event !== undefined && OfficialWebViewModel.canLoad(event.url)) {
              this.documentVersion++;
              this.documentUrl = event.url;
              this.loading = true;
              this.failure = '';
            }
          })
          .onPageEnd((event: OnPageEndEvent) => {
            if (event !== undefined && OfficialWebViewModel.canLoad(event.url)) {
              this.loading = false;
              if (this.firstDocument) {
                this.firstDocument = false;
                try { this.controller.clearHistory(); } catch (e) {}
              }
            }
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            if (event !== undefined && event.request.isMainFrame()) {
              this.loading = false;
              this.failure = '官方页面加载失败，请重试';
            }
          })
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.page_background'))
  }
}
