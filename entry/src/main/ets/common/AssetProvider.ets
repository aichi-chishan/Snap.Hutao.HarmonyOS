/**
 * AssetProvider.ets
 * 本地/打包素材提供者（不拉取任何外部服务器资源）。
 *
 * 设计：祈愿角色/武器等图标素材后续可通过以下方式提供，UI 无需改动：
 *  - 打包进应用：将图片放入 entry/src/main/resources/base/media/ ，
 *    并在 assetIdOf() 中返回对应资源名；
 *  - 二次下载：将下载的图片写入 filesDir/icons/ 目录，setResourceDir()
 *    注册后将优先读取该目录。
 * 当前版本未内置素材，返回空标识，UI 显示占位（不显示破图）。
 */
import { fileIo } from '@kit.CoreFileKit';
import { AppContextProvider } from './AppContext';
import { Logger } from './Logger';

const TAG: string = 'AssetProvider';

export class AssetProvider {
  /** 二次下载素材目录（相对 filesDir）；未设置则跳过 */
  private static resourceSubDir: string = '';

  /** 注册二次下载素材目录（如 'icons'），调用后本地素材优先 */
  static setResourceDir(subDir: string): void {
    AssetProvider.resourceSubDir = subDir;
  }

  static getResourceDir(): string {
    return AssetProvider.resourceSubDir;
  }

  /**
   * 根据 itemId/名称返回本地素材标识：
   *  - 若已构建本地映射，返回 'asset://xxx' 形式标识；
   *  - 否则返回 ''，UI 显示占位图标。
   * 注意：本函数不发起任何网络请求。
   */
  static iconKeyForGacha(itemId: number, name: string): string {
    // 预留：未来在此维护 itemId → 本地资源名 的映射表（打包素材或二次下载）。
    // 当前未内置素材，返回空 → UI 用占位。
    return '';
  }

  /** 读取二次下载素材文件是否存在（供未来使用） */
  static hasLocalFile(fileName: string): boolean {
    if (AssetProvider.resourceSubDir.length === 0) {
      return false;
    }
    try {
      const dir: string = `${AppContextProvider.getFilesDir()}/${AssetProvider.resourceSubDir}`;
      const path: string = `${dir}/${fileName}`;
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      fileIo.closeSync(file);
      return true;
    } catch (e) {
      Logger.debug(TAG, `local asset missing: ${fileName}`);
      return false;
    }
  }
}
