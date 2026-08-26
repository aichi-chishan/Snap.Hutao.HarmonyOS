/**
 * AppContext.ets
 * 全局应用上下文持有者：供 Service（无可直接访问 context 的位置）与跨进程(Form 卡片)读取沙盒目录。
 * EntryAbility 与 FormExtensionAbility 各自进程启动时注入。
 */
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { Logger } from './Logger';

const TAG: string = 'AppContext';

export class AppContextProvider {
  private static context: common.Context | undefined = undefined;

  static init(ctx: common.Context): void {
    AppContextProvider.context = ctx;
    Logger.info(TAG, 'context injected');
  }

  private static getContext(): common.Context {
    if (AppContextProvider.context === undefined) {
      throw new Error('AppContextProvider not initialized');
    }
    return AppContextProvider.context;
  }

  static getFilesDir(): string {
    return AppContextProvider.getContext().filesDir;
  }

  /** 公开的应用上下文（供服务层 startAbility/通知等系统能力使用） */
  static getAppContext(): common.Context {
    return AppContextProvider.getContext();
  }

  /** 缓存目录（必应壁纸等下载缓存） */
  static getCacheDir(): string {
    return AppContextProvider.getContext().cacheDir;
  }

  /** 资源管理器（rawfile 读取等） */
  static getResourceManager(): resourceManager.ResourceManager {
    return AppContextProvider.getContext().resourceManager;
  }
}
