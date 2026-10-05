/**
 * Game-data facade: one verified metadata/icon cohort is pinned for this process.
 * Updates/reset/rollback change the next-launch selection, never existing consumers.
 * Legacy community domains retain their bundled compatibility fallback; old per-file
 * caches and Preferences version strings are not evidence of a complete snapshot.
 */
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../common/AppContext';
import { GameDataUpdater, UpdateProgress } from '../data/remote/GameDataUpdater';
import { GameDataManifestPolicy, ItemType } from '../data/remote/GameDataManifestPolicy';
import { Logger } from '../common/Logger';
import { GameDataUpdateStatus } from '../model/GameDataUpdateStatus';
export { GameDataUpdateStatus } from '../model/GameDataUpdateStatus';

const TAG: string = 'GameDataService';

/** 数据域枚举（新增域在此扩展，路径约定在 pathOf） */
export enum GameDataDomain {
  WikiAvatar = 'wiki_avatar',
  WikiWeapon = 'wiki_weapon',
  WikiMonster = 'wiki_monster',
  Achievement = 'achievement',
  AvatarCurve = 'avatar_curve',
}

export class GameDataService {
  private static instance: GameDataService = new GameDataService();

  static getInstance(): GameDataService {
    return GameDataService.instance;
  }

  /** Coalesce startup validation before any metadata consumer or page is mounted. */
  static initializeSnapshot(): Promise<void> { return GameDataUpdater.initializeSnapshot(); }
  static updateStatus(): GameDataUpdateStatus { return GameDataUpdater.updateStatus(); }
  static subscribeUpdate(listener: (status: GameDataUpdateStatus) => void): () => void {
    return GameDataUpdater.subscribeUpdate(listener);
  }
  static cancelUpdate(expectedId?: number): Promise<GameDataUpdateStatus> { return GameDataUpdater.cancelUpdate(expectedId); }

  pendingVersion(): string { return GameDataUpdater.pendingVersion(); }
  pendingState(): string { return GameDataUpdater.pendingState(); }
  canRollback(): boolean { return GameDataUpdater.canRollback(); }
  static rollbackRemote(): Promise<boolean> { return GameDataUpdater.rollback(); }

  /** 该域对应 rawfile 内置文件名（回退源；与远端同名，远端成功后覆盖语义） */
  private static rawfileOf(domain: GameDataDomain): string {
    switch (domain) {
      case GameDataDomain.WikiAvatar:
        return 'wiki_avatar.json';
      case GameDataDomain.WikiWeapon:
        return 'wiki_weapon.json';
      case GameDataDomain.WikiMonster:
        return 'wiki_monster.json';
      case GameDataDomain.Achievement:
        return 'achievement_zh.json';
      case GameDataDomain.AvatarCurve:
        return 'avatar_curve.json';
      default:
        return '';
    }
  }

  /** 该域远端相对路径（GameDataUpdater.metadataPath 用） */
  private static remotePathOf(domain: GameDataDomain): string {
    switch (domain) {
      case GameDataDomain.WikiAvatar:
        return 'wiki_avatar.json';
      case GameDataDomain.WikiWeapon:
        return 'wiki_weapon.json';
      case GameDataDomain.WikiMonster:
        return 'wiki_monster.json';
      case GameDataDomain.Achievement:
        return 'achievement.json';
      case GameDataDomain.AvatarCurve:
        return 'avatar_curve.json';
      default:
        return '';
    }
  }

  /**
   * 读取某域元数据文本（远端更新优先，空则回退 rawfile）。
   * 返回值可能为空串（两者皆无）——调用方自行兜底。
   */
  async readText(domain: GameDataDomain): Promise<string> {
    await GameDataService.initializeSnapshot();
    // 1) 远端更新版
    const remote: string = GameDataUpdater.readMetadata(GameDataService.remotePathOf(domain));
    if (remote.length > 0) {
      return remote;
    }
    // 2) rawfile 内置版
    try {
      const rm = AppContextProvider.getResourceManager();
      const raw: Uint8Array = await rm.getRawFileContent(GameDataService.rawfileOf(domain));
      return util.TextDecoder.create('utf-8').decodeToString(raw);
    } catch (e) {
      Logger.warn(TAG, `rawfile ${domain} not found`);
      return '';
    }
  }

  /** 是否已用远端更新版（判断是否可用远端数据） */
  hasRemote(domain: GameDataDomain): boolean {
    return GameDataUpdater.readMetadata(GameDataService.remotePathOf(domain)).length > 0;
  }

  /**
   * 读取远端更新图标（file:// 前缀供 Image 组件用）；未下载返回空串。
   * 远端图标路径约定：icons/{Category}/{Name}.png（与 rawfile/icons 同构）
   * @param category 类别目录（AvatarIcon/EquipIcon/MonsterIcon/Skill/Talent/ItemIcon/AchievementIcon）
   * @param name 图标名（不含扩展名）
   */
  readIcon(category: string, name: string): string {
    if (category.length === 0 || name.length === 0) {
      return '';
    }
    return GameDataUpdater.readImage(`icons/${category}/${name}.png`);
  }

  /** 是否有远端图标（已下载过） */
  hasIcon(category: string, name: string): boolean {
    return this.readIcon(category, name).length > 0;
  }

  /** 发布清单的 path 保留 metadata/ 前缀；与下载器 itemPath 的落盘规则一致。 */
  static async readMetadataFile(name: string): Promise<string> {
    await GameDataService.initializeSnapshot();
    GameDataManifestPolicy.validatePath(`metadata/${name}`, ItemType.Text);
    const remote: string = GameDataUpdater.readMetadata(`metadata/${name}`);
    if (remote.length > 0) { return remote; } // Entire selected cohort was verified together at startup.
    const raw: Uint8Array = await AppContextProvider.getResourceManager().getRawFileContent(`metadata/${name}`);
    return util.TextDecoder.create('utf-8').decodeToString(raw);
  }

  /** 当前远端版本号（无则 ''） */
  remoteVersion(): string {
    return GameDataUpdater.localVersion();
  }

  /** 从 GitHub 触发一次全量更新（进度回调给 UI） */
  async updateAll(onProgress?: (done: number, total: number, current: string) => void): Promise<string> {
    const manifest = await GameDataUpdater.update((p: UpdateProgress) => {
      if (onProgress !== undefined) {
        onProgress(p.done, p.total, p.current);
      }
    });
    return manifest.channelVersion;
  }

  /** 检查是否有更新可用（清单可拉取；失败返回 null 表示网络/地址问题） */
  async checkUpdateAvailable(): Promise<boolean | null> {
    try {
      await GameDataService.initializeSnapshot();
      const manifest = await GameDataUpdater.fetchManifest();
      return GameDataUpdater.hasUpdate(manifest);
    } catch (e) {
      Logger.warn(TAG, `check update fail: ${(e as Error).message}`);
      return null;
    }
  }

  /** 下次启动回退整版内置数据；保留当前读者和既有文件。 */
  static clearRemote(): void {
    GameDataUpdater.clearAll();
  }
}
