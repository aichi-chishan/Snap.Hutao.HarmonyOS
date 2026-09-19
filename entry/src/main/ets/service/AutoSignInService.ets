/**
 * AutoSignInService.ets
 * 启动自动签到（对齐 Windows AutoSignInService）：
 * - 设置默认开启（AutoSignInEnabled 默认 true）
 * - 按 UID 记录：已完成服务器日 key（区服时区口径，东八）+ 上次失败时间（10 分钟冷却）+ 区服（变更重置）
 * - EntryAbility bootstrap（恢复登录态后）调用；今日已签/冷却中直接跳过
 */
import { UserService } from './UserService';
import { SignInService, SignInResult } from './SignInService';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { RegionUtil } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'AutoSignIn';
/** 失败冷却（对齐 Windows FailureCooldown = 10min） */
const FAILURE_COOLDOWN_MS: number = 10 * 60 * 1000;

export class AutoSignInService {
  private static instance: AutoSignInService = new AutoSignInService();

  static getInstance(): AutoSignInService {
    return AutoSignInService.instance;
  }

  /** 应用启动时调用：开关开启且已登录则尝试一次 */
  async bootstrapAutoSignIn(): Promise<void> {
    if (!PreferencesStore.getAutoSignInEnabled()) {
      return;
    }
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      return;
    }
    const uid: string = PreferencesStore.getCurrentUid();
    if (uid.length === 0) {
      return;
    }
    await this.runOnce(uid);
  }

  /** 单次尝试（已完成/冷却中跳过；结果记入偏好，静默失败不抛出） */
  async runOnce(uid: string): Promise<void> {
    if (!PreferencesStore.getAutoSignInEnabled()) {
      return;
    }
    try {
      const region: string = RegionUtil.regionOfUid(uid);
      // 区服变更：重置该 UID 进度（对齐 Windows LastRegion 处理）
      if (PreferencesStore.getAutoSignInRegion(uid) !== region) {
        PreferencesStore.setAutoSignInCompletedDay(uid, '');
        PreferencesStore.setAutoSignInLastFail(uid, 0);
        PreferencesStore.setAutoSignInRegion(uid, region);
      }
      const dayKey: string = `${region}:${AutoSignInService.serverDay()}`;
      if (PreferencesStore.getAutoSignInCompletedDay(uid) === dayKey) {
        return;
      }
      const lastFail: number = PreferencesStore.getAutoSignInLastFail(uid);
      if (lastFail > 0 && Date.now() - lastFail < FAILURE_COOLDOWN_MS) {
        Logger.info(TAG, `cooldown, skip uid=${uid}`);
        return;
      }
      const result: SignInResult = await SignInService.getInstance().sign(uid);
      if (result.ok || result.alreadySigned) {
        PreferencesStore.setAutoSignInCompletedDay(uid, dayKey);
        PreferencesStore.setAutoSignInLastFail(uid, 0);
        Logger.info(TAG, `auto sign ok uid=${uid}${result.rewardText.length > 0 ? ` ${result.rewardText}` : ''}`);
      } else {
        PreferencesStore.setAutoSignInLastFail(uid, Date.now());
        Logger.warn(TAG, `auto sign fail uid=${uid} msg=${result.message}`);
      }
    } catch (e) {
      // 静默失败：仅记录日志（对齐 Windows RunOnceAsync 捕获不外抛）
      Logger.warn(TAG, `runOnce fail uid=${uid} ${(e as Error).message}`);
    }
  }

  /** 服务器日 key 的日期部分（东八区，与签到口径一致） */
  private static serverDay(): string {
    return new Date(Date.now() + 8 * 3600 * 1000).toISOString().substring(0, 10);
  }
}
