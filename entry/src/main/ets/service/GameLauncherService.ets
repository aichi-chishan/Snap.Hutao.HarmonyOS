/**
 * GameLauncherService.ets
 * 拉起本机已安装的原神 APP（对齐 Windows 启动游戏入口，但仅"拉起"，不做注入/进程链）：
 *  - 查询已知米哈游游戏包名（原神国服/国际服/云原神），返回安装状态
 *  - 通过 bundleManager.getBundleInfo + startAbility 拉起主 Ability
 *  - 未安装时返回明确提示（引导到应用市场）
 */
import { bundleManager, common } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';

const TAG: string = 'GameLauncherService';

/** 已知米哈游游戏包名（按优先级：国服原神优先） */
export class GamePackage {
  packageName: string = '';
  displayName: string = '';
}

export class GameLaunchResult {
  ok: boolean = false;
  message: string = '';
  /** 找到的游戏包名 */
  bundleName: string = '';
}

export class GameLauncherService {
  private static instance: GameLauncherService = new GameLauncherService();

  static getInstance(): GameLauncherService {
    return GameLauncherService.instance;
  }

  /** 已知米哈游游戏（鸿蒙上架：米哈游云端化应用为 com.MiHoYo.xxx；此处尝试常见包名） */
  private static readonly candidates: GamePackage[] = [
    { packageName: 'com.miHoYo.Yuanshen', displayName: '原神' },
    { packageName: 'com.miHoYo.hkrpg', displayName: '崩坏：星穹铁道' },
    { packageName: 'com.miHoYo.bh3', displayName: '崩坏3' },
  ];

  /** 查询本机已安装的米哈游游戏（返回列表） */
  static async detectInstalled(): Promise<GamePackage[]> {
    const out: GamePackage[] = [];
    for (const cand of GameLauncherService.candidates) {
      try {
        await bundleManager.getBundleInfo(cand.packageName, bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
        out.push(cand);
      } catch (e) {
        // 未安装
      }
    }
    Logger.info(TAG, `detectInstalled: ${out.map((g) => g.packageName).join(', ')}`);
    return out;
  }

  /** 检测指定包名是否已安装 */
  static async isInstalled(packageName: string): Promise<boolean> {
    try {
      await bundleManager.getBundleInfo(packageName, bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 拉起游戏（首个已安装；指定包名可传递） */
  static async launch(packageName?: string): Promise<GameLaunchResult> {
    const result: GameLaunchResult = new GameLaunchResult();
    let target: string = packageName ?? '';
    if (target.length === 0) {
      const installed: GamePackage[] = await GameLauncherService.detectInstalled();
      if (installed.length === 0) {
        result.ok = false;
        result.message = '未安装原神 APP。请通过应用市场安装后重试';
        return result;
      }
      target = installed[0].packageName;
    }
    try {
      const context: common.UIAbilityContext = AppContextProvider.getAppContext() as common.UIAbilityContext;
      const want: Want = {
        bundleName: target,
        abilityName: 'EntryAbility',
        parameters: {
          'caller': 'com.example.snaphutaoharmonyos',
        },
      };
      Logger.info(TAG, `launch ${target} via startAbility`);
      await context.startAbility(want);
      result.ok = true;
      result.message = target;
      result.bundleName = target;
      return result;
    } catch (e) {
      Logger.warn(TAG, `launch ${target} fail: ${(e as Error).message}`);
      result.ok = false;
      result.message = '拉起失败，可能未安装或未登录米哈游账号，请先安装并启动一次游戏';
      result.bundleName = target;
      return result;
    }
  }

  /** 应用市场跳转（未安装时引导；华为应用市场包名） */
  static marketUrl(packageName: string): string {
    return `https://appgallery.huawei.com/app/C100023552`;
  }
}
