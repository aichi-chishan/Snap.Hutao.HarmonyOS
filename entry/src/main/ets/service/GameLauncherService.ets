/** Native game routing through the target app's public HarmonyOS entry point. */
import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContextProvider } from '../common/AppContext';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { Logger } from '../common/Logger';

export class GamePackage {
  packageName: string = '';
  displayName: string = '原神';
  abilityName: string = '';
  uri: string = '';
}

export class GameLaunchResult {
  ok: boolean = false;
  message: string = '';
  bundleName: string = '';
  /** unconfigured / unknown / launched / unavailable / failed */
  status: string = 'unknown';
  errorCode: number = 0;
}

export class GameLauncherService {
  private static readonly KEY_BUNDLE: string = 'launcher.bundle';
  private static readonly KEY_ABILITY: string = 'launcher.ability';
  private static readonly KEY_URI: string = 'launcher.uri';
  private static readonly KEY_NAME: string = 'launcher.name';

  static getTarget(): GamePackage {
    const target: GamePackage = new GamePackage();
    target.packageName = PreferencesStore.getString(GameLauncherService.KEY_BUNDLE, '');
    target.abilityName = PreferencesStore.getString(GameLauncherService.KEY_ABILITY, '');
    target.uri = PreferencesStore.getString(GameLauncherService.KEY_URI, '');
    target.displayName = PreferencesStore.getString(GameLauncherService.KEY_NAME, '原神');
    return target;
  }

  static validationMessage(target: GamePackage): string {
    if (target.displayName.length > 80 || target.uri.length > 2048 ||
      target.packageName.length > 255 || target.abilityName.length > 255) {
      return '启动入口文字超过允许长度';
    }
    if (target.uri.trim().length > 0) {
      // A route is supplied by the user/vendor; do not guess a game scheme or scan packages.
      if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(target.uri.trim()) || /\s/.test(target.uri.trim())) {
        return '请输入完整的公开启动链接（scheme://…）';
      }
      if (/^(file|content|javascript|data):/i.test(target.uri.trim())) {
        return '该链接类型不能用于启动游戏';
      }
      return '';
    }
    if (target.packageName.trim().length === 0 && target.abilityName.trim().length === 0) {
      return '请先配置游戏公开的启动链接或 HarmonyOS 应用入口';
    }
    if (target.packageName.trim().length === 0 || target.abilityName.trim().length === 0) {
      return 'Bundle 名称和 Ability 名称须同时填写';
    }
    if (/\s/.test(target.packageName.trim()) || /\s/.test(target.abilityName.trim())) {
      return '应用入口名称不能包含空白字符';
    }
    return '';
  }

  static saveTarget(target: GamePackage): string {
    const message: string = GameLauncherService.validationMessage(target);
    if (message.length > 0) {
      return message;
    }
    PreferencesStore.setString(GameLauncherService.KEY_NAME, target.displayName.trim() || '原神');
    PreferencesStore.setString(GameLauncherService.KEY_BUNDLE, target.packageName.trim());
    PreferencesStore.setString(GameLauncherService.KEY_ABILITY, target.abilityName.trim());
    PreferencesStore.setString(GameLauncherService.KEY_URI, target.uri.trim());
    AppStorage.setOrCreate('gameLaunchTargetVersion', Date.now());
    return '';
  }

  static clearTarget(): void {
    PreferencesStore.setString(GameLauncherService.KEY_BUNDLE, '');
    PreferencesStore.setString(GameLauncherService.KEY_ABILITY, '');
    PreferencesStore.setString(GameLauncherService.KEY_URI, '');
    AppStorage.setOrCreate('gameLaunchTargetVersion', Date.now());
  }

  /** Ordinary applications cannot query arbitrary installed bundles. No query is attempted. */
  static targetStatus(target: GamePackage): string {
    return GameLauncherService.validationMessage(target).length > 0
      ? '尚未配置启动入口' : '已配置入口；安装状态无法直接查询';
  }

  static async launch(): Promise<GameLaunchResult> {
    const result: GameLaunchResult = new GameLaunchResult();
    const target: GamePackage = GameLauncherService.getTarget();
    const validation: string = GameLauncherService.validationMessage(target);
    if (validation.length > 0) {
      result.status = 'unconfigured';
      result.message = validation;
      return result;
    }
    const want: Want = target.uri.length > 0
      ? { action: 'ohos.want.action.viewData', uri: target.uri }
      : { bundleName: target.packageName, abilityName: target.abilityName };
    result.bundleName = target.packageName;
    try {
      const context: common.UIAbilityContext = AppContextProvider.getAppContext() as common.UIAbilityContext;
      await context.startAbility(want);
      result.ok = true;
      result.status = 'launched';
      result.message = `已发送 ${target.displayName} 启动请求`;
    } catch (error) {
      const code: number = (error as BusinessError).code;
      result.errorCode = code;
      // An unavailable entry may mean absent app OR changed/private Ability. Do not claim absence.
      result.status = code === 16000001 ? 'unavailable' : 'failed';
      result.message = code === 16000001
        ? '未找到可用入口：应用可能未安装，或入口名称已变更'
        : `启动失败（${code}），请核对游戏公开的启动入口`;
      Logger.warn('GameLauncherService', `launch failed code=${code}`);
    }
    return result;
  }
}
