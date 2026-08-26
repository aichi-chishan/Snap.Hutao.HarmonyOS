/**
 * GameDataService.ets
 * 游戏元数据服务（业务封装层，对接 GameDataUpdater 的"取与存"）：
 *  - 每类元数据：远端更新文件（filesDir/gamedata/metadata/{域}.json）优先，缺省回退 rawfile 内置
 *  - 版本戳统一由 GameDataUpdater 管理（channelVersion），本服务只做"读最优源"
 *  - 数据域（新增域只需加一个枚举）+ path 约定：
 *      WikiAvatar  -> metadata/wiki_avatar.json      （角色图鉴元数据）
 *      WikiWeapon  -> metadata/wiki_weapon.json      （武器图鉴元数据）
 *      WikiMonster -> metadata/wiki_monster.json     （怪物图鉴元数据）
 *      Achievement -> metadata/achievement.json      （成就新数据集，含分类）
 *      曲线表      -> metadata/avatar_curve.json     （头像/武器等级曲线表）
 */
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../common/AppContext';
import { GameDataUpdater, UpdateProgress } from '../data/remote/GameDataUpdater';
import { Logger } from '../common/Logger';

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
      const manifest = await GameDataUpdater.fetchManifest();
      return GameDataUpdater.hasUpdate(manifest);
    } catch (e) {
      Logger.warn(TAG, `check update fail: ${(e as Error).message}`);
      return null;
    }
  }

  /** 清空远端数据（回退 rawfile 内置；用于恢复出厂） */
  static clearRemote(): void {
    GameDataUpdater.clearAll();
  }
}
