import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { OfficialWebActions, OfficialWebBridgeService, OfficialWebCallback,
  OfficialWebKind, OfficialWebShareRequest } from '../service/OfficialWebBridgeService';
import { OfficialWebShareMode, OfficialWebShareService } from '../service/OfficialWebShareService';

export class OfficialWebViewModel {
  private bridge: OfficialWebBridgeService | undefined = undefined;

  select(kind: Object | undefined, uid: string): string {
    if (kind !== OfficialWebKind.Toolbox && kind !== OfficialWebKind.DailyNote && kind !== OfficialWebKind.SignIn) {
      throw new Error('官方页面不可用');
    }
    this.bridge = new OfficialWebBridgeService(kind as OfficialWebKind, uid);
    return this.bridge.title();
  }

  source(): string { return this.bridge?.source() ?? ''; }

  isCurrent(): boolean { return this.bridge?.owner.isCurrent() === true; }

  isSignIn(): boolean { return this.bridge?.kind === OfficialWebKind.SignIn; }

  close(): void { this.bridge = undefined; }

  async prepare(active: () => boolean): Promise<void> {
    const bridge: OfficialWebBridgeService | undefined = this.bridge;
    if (bridge === undefined) { throw new Error('官方页面已关闭'); }
    await bridge.prepare(active);
  }

  async receive(raw: string, actions: OfficialWebActions, active: () => boolean): Promise<OfficialWebCallback | undefined> {
    return this.bridge?.receive(raw, actions, active);
  }

  static canLoad(target: string): boolean { return OfficialWebBridgeService.allowsPage(target); }

  shareMode(): OfficialWebShareMode { return OfficialWebShareService.shareMode(); }

  async shareImage(request: OfficialWebShareRequest, controller: webview.WebviewController,
    widthPx: number, heightPx: number): Promise<image.PixelMap> {
    if (request.type === 'screenshot') { return OfficialWebShareService.screenshot(controller, widthPx, heightPx); }
    return OfficialWebShareService.imageFor(request);
  }

  async copy(pixelMap: image.PixelMap): Promise<void> { await OfficialWebShareService.copy(pixelMap); }

  async save(pixelMap: image.PixelMap, context: common.UIAbilityContext, active: () => boolean): Promise<boolean> {
    return OfficialWebShareService.save(pixelMap, context, active);
  }
}
