import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { OfficialWebBridgeService, OfficialWebShareRequest } from './OfficialWebBridgeService';

export enum OfficialWebShareMode {
  Copy = 'copy',
  SavePng = 'save-png',
}

export class OfficialWebShareService {
  private static readonly MAX_BYTES: number = 12 * 1024 * 1024;
  private static readonly MAX_PIXELS: number = 16 * 1024 * 1024;
  private static readonly SHARE_MODE_KEY: string = 'official_web.share_mode';

  static shareMode(): OfficialWebShareMode {
    const value: string = PreferencesStore.getString(OfficialWebShareService.SHARE_MODE_KEY, OfficialWebShareMode.Copy);
    return value === OfficialWebShareMode.SavePng ? OfficialWebShareMode.SavePng : OfficialWebShareMode.Copy;
  }

  static setShareMode(mode: OfficialWebShareMode): void {
    PreferencesStore.setString(OfficialWebShareService.SHARE_MODE_KEY, mode);
  }

  static async imageFor(request: OfficialWebShareRequest): Promise<image.PixelMap> {
    const bytes: ArrayBuffer = request.imageUrl.length > 0 ? await OfficialWebShareService.download(request.imageUrl)
      : OfficialWebShareService.decode(request.imageBase64);
    if (bytes.byteLength === 0 || bytes.byteLength > OfficialWebShareService.MAX_BYTES) {
      throw new Error('分享图片大小超限');
    }
    const source: image.ImageSource = image.createImageSource(bytes);
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      if (info.size.width * info.size.height > OfficialWebShareService.MAX_PIXELS) {
        throw new Error('分享图片分辨率超限');
      }
      return await source.createPixelMap();
    } finally {
      await source.release();
    }
  }

  private static decode(value: string): ArrayBuffer {
    const base64: string = value.replace(/^data:image\/[a-zA-Z0-9.+-]+;base64,/, '');
    if (base64.length === 0 || base64.length > Math.ceil(OfficialWebShareService.MAX_BYTES / 3) * 4) {
      throw new Error('分享图片大小超限');
    }
    return new util.Base64Helper().decodeSync(base64).buffer;
  }

  private static async download(value: string): Promise<ArrayBuffer> {
    if (!OfficialWebBridgeService.allowsImage(value)) { throw new Error('分享图片来源不可用'); }
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(value, {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxLimit: OfficialWebShareService.MAX_BYTES, maxRedirects: 0, usingCache: false,
        connectTimeout: 10000, readTimeout: 20000,
      });
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer)) {
        throw new Error('无法取得分享图片');
      }
      return response.result;
    } finally {
      request.destroy();
    }
  }

  static screenshot(controller: webview.WebviewController, width: number, height: number): Promise<image.PixelMap> {
    if (width <= 0 || height <= 0 || width > 16000 || height > 16000 || width * height > OfficialWebShareService.MAX_PIXELS) {
      return Promise.reject(new Error('网页截图尺寸超限'));
    }
    const options: webview.SnapshotInfo = {
      id: `hutao-share-${Date.now()}`, size: { width: `${Math.ceil(width)}px`, height: `${Math.ceil(height)}px` },
    };
    return new Promise<image.PixelMap>((resolve, reject) => {
      controller.webPageSnapshot(options, (error: BusinessError, result: webview.SnapshotResult): void => {
        const pixelMap: image.PixelMap | undefined = result?.imagePixelMap;
        if (error !== undefined || pixelMap === undefined || result.status === false) {
          pixelMap?.release().catch(() => {});
          reject(new Error('无法截取官方网页'));
          return;
        }
        resolve(pixelMap);
      });
    });
  }

  static async copy(pixelMap: image.PixelMap): Promise<void> {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
    await pasteboard.getSystemPasteboard().setData(data);
  }

  static async save(pixelMap: image.PixelMap, context: common.UIAbilityContext, active: () => boolean): Promise<boolean> {
    const packer: image.ImagePacker = image.createImagePacker();
    let bytes: ArrayBuffer;
    try { bytes = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 }); }
    finally { await packer.release(); }
    if (!active()) { return false; }
    const options: picker.DocumentSaveOptions = { newFileNames: ['share.png'] };
    const targets: string[] = await new picker.DocumentViewPicker(context).save(options);
    if (targets.length === 0 || !active()) { return false; }
    const file: fileIo.File = await fileIo.open(targets[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC | fileIo.OpenMode.CREATE);
    try {
      if (await fileIo.write(file.fd, bytes) !== bytes.byteLength) { throw new Error('分享图片未写入完整'); }
    } finally {
      await fileIo.close(file);
    }
    return true;
  }
}
