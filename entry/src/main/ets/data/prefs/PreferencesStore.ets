/**
 * PreferencesStore.ets
 * @ohos.data.preferences 封装：设置项读写（当前账号/UID、刷新间隔、自动刷新、主题、设备ID、阈值）。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../../common/Logger';

const TAG: string = 'Prefs';

export class PreferencesStore {
  static readonly PREFS_NAME: string = 'snap_hutao_prefs';

  // ---- keys ----
  static readonly KEY_CURRENT_USER_ID: string = 'app.current_user_id';
  static readonly KEY_CURRENT_UID: string = 'app.current_uid';
  static readonly KEY_REFRESH_INTERVAL: string = 'dailynote.refresh_interval_minutes';
  static readonly KEY_AUTO_REFRESH: string = 'dailynote.auto_refresh_enabled';
  static readonly KEY_THEME_MODE: string = 'theme.mode';
  static readonly KEY_DEVICE_ID: string = 'app.device_id';
  static readonly KEY_BBS_DEVICE_ID: string = 'app.bbs_device_id';
  static readonly KEY_AMBIENT_STRENGTH: string = 'app.ambient_strength';
  static readonly KEY_DAILY_BG_ENABLED: string = 'app.daily_bg_enabled';
  static readonly KEY_BG_IMAGE_TYPE: string = 'app.bg_image_type';
  static readonly KEY_BG_FOLDER_PATH: string = 'app.bg_folder_path';
  static readonly KEY_DEVICE_FP: string = 'app.device_fp';
  static readonly KEY_DEVICE_FP_TIME: string = 'app.device_fp_time';

  // ---- defaults ----
  static readonly DEFAULT_REFRESH_INTERVAL: number = 30;
  static readonly DEFAULT_AUTO_REFRESH: boolean = true;
  static readonly DEFAULT_THEME_MODE: string = 'system';
  /** 沉浸光感强度 0~1（0=关闭），默认 0.25 */
  static readonly DEFAULT_AMBIENT_STRENGTH: number = 0.25;
  static readonly DEFAULT_DAILY_BG_ENABLED: boolean = true;

  private static prefs: preferences.Preferences | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (PreferencesStore.prefs !== undefined) {
      return;
    }
    const p: preferences.Preferences = await preferences.getPreferences(context, PreferencesStore.PREFS_NAME);
    PreferencesStore.prefs = p;
    Logger.info(TAG, 'preferences initialized');
  }

  private static getStore(): preferences.Preferences {
    if (PreferencesStore.prefs === undefined) {
      throw new Error('preferences not initialized');
    }
    return PreferencesStore.prefs;
  }

  // ---- 通用 ----
  static getString(key: string, def: string): string {
    return PreferencesStore.getStore().getSync(key, def) as string;
  }

  static getNumber(key: string, def: number): number {
    return PreferencesStore.getStore().getSync(key, def) as number;
  }

  static getBool(key: string, def: boolean): boolean {
    return PreferencesStore.getStore().getSync(key, def) as boolean;
  }

  static setString(key: string, value: string): void {
    const store = PreferencesStore.getStore();
    store.putSync(key, value);
    store.flush().catch((e: Error) => {
      Logger.warn(TAG, `flush fail ${e.message}`);
    });
  }

  static setNumber(key: string, value: number): void {
    const store = PreferencesStore.getStore();
    store.putSync(key, value);
    store.flush().catch((e: Error) => {
      Logger.warn(TAG, `flush fail ${e.message}`);
    });
  }

  static setBool(key: string, value: boolean): void {
    const store = PreferencesStore.getStore();
    store.putSync(key, value);
    store.flush().catch((e: Error) => {
      Logger.warn(TAG, `flush fail ${e.message}`);
    });
  }

  // ---- 业务便捷方法 ----
  static getCurrentUserId(): number {
    return PreferencesStore.getNumber(PreferencesStore.KEY_CURRENT_USER_ID, 0);
  }

  static setCurrentUserId(id: number): void {
    PreferencesStore.setNumber(PreferencesStore.KEY_CURRENT_USER_ID, id);
  }

  static getCurrentUid(): string {
    return PreferencesStore.getString(PreferencesStore.KEY_CURRENT_UID, '');
  }

  static setCurrentUid(uid: string): void {
    PreferencesStore.setString(PreferencesStore.KEY_CURRENT_UID, uid);
  }

  static getRefreshIntervalMinutes(): number {
    return PreferencesStore.getNumber(PreferencesStore.KEY_REFRESH_INTERVAL, PreferencesStore.DEFAULT_REFRESH_INTERVAL);
  }

  static setRefreshIntervalMinutes(min: number): void {
    PreferencesStore.setNumber(PreferencesStore.KEY_REFRESH_INTERVAL, min);
  }

  static getAutoRefreshEnabled(): boolean {
    return PreferencesStore.getBool(PreferencesStore.KEY_AUTO_REFRESH, PreferencesStore.DEFAULT_AUTO_REFRESH);
  }

  static setAutoRefreshEnabled(enabled: boolean): void {
    PreferencesStore.setBool(PreferencesStore.KEY_AUTO_REFRESH, enabled);
  }

  static getThemeMode(): string {
    return PreferencesStore.getString(PreferencesStore.KEY_THEME_MODE, PreferencesStore.DEFAULT_THEME_MODE);
  }

  static setThemeMode(mode: string): void {
    PreferencesStore.setString(PreferencesStore.KEY_THEME_MODE, mode);
  }

  static getDeviceId(): string {
    let id: string = PreferencesStore.getString(PreferencesStore.KEY_DEVICE_ID, '');
    if (id.length === 0) {
      id = PreferencesStore.genDeviceId();
      PreferencesStore.setString(PreferencesStore.KEY_DEVICE_ID, id);
    }
    return id;
  }

  /** BBS 登录链路稳定 device_id（GUID 形态）。固定设备身份可显著降低登录风控触发率 */
  static getBbsDeviceId(): string {
    let id: string = PreferencesStore.getString(PreferencesStore.KEY_BBS_DEVICE_ID, '');
    if (id.length === 0) {
      id = PreferencesStore.genDeviceId();
      PreferencesStore.setString(PreferencesStore.KEY_BBS_DEVICE_ID, id);
    }
    // GUID 形态：8-4-4-4-12（genDeviceId 生成 53 位 hex，裁取 32 位按段拼接）
    const hex: string = id.replace(/-/g, '').substring(0, 32);
    return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}`;
  }

  static getAmbientStrength(): number {
    return PreferencesStore.getNumber(PreferencesStore.KEY_AMBIENT_STRENGTH, PreferencesStore.DEFAULT_AMBIENT_STRENGTH);
  }

  static setAmbientStrength(v: number): void {
    PreferencesStore.setNumber(PreferencesStore.KEY_AMBIENT_STRENGTH, v);
  }

  static getDailyBgEnabled(): boolean {
    return PreferencesStore.getBool(PreferencesStore.KEY_DAILY_BG_ENABLED, PreferencesStore.DEFAULT_DAILY_BG_ENABLED);
  }

  static setDailyBgEnabled(v: boolean): void {
    PreferencesStore.setBool(PreferencesStore.KEY_DAILY_BG_ENABLED, v);
  }

  // ---- 背景图片（对齐 Windows BackgroundImageType：none/local/bing）----

  /** 背景来源类型；未设置时按旧版"每日背景"开关迁移（开=local 内置图 / 关=none） */
  static getBackgroundImageType(): string {
    const saved: string = PreferencesStore.getString(PreferencesStore.KEY_BG_IMAGE_TYPE, '');
    if (saved.length > 0) {
      return saved;
    }
    // 默认 none：主题渐变（最稳妥，避免本地/内置图与浅色主题叠加产生偏色）
    return 'none';
  }

  static setBackgroundImageType(v: string): void {
    PreferencesStore.setString(PreferencesStore.KEY_BG_IMAGE_TYPE, v);
  }

  static getBackgroundFolderPath(): string {
    return PreferencesStore.getString(PreferencesStore.KEY_BG_FOLDER_PATH, '');
  }

  static setBackgroundFolderPath(v: string): void {
    PreferencesStore.setString(PreferencesStore.KEY_BG_FOLDER_PATH, v);
  }

  // ---- 设备指纹（device_fp，降风控）----

  static getDeviceFp(): string {
    return PreferencesStore.getString(PreferencesStore.KEY_DEVICE_FP, '');
  }

  static setDeviceFp(fp: string): void {
    PreferencesStore.setString(PreferencesStore.KEY_DEVICE_FP, fp);
    PreferencesStore.setNumber(PreferencesStore.KEY_DEVICE_FP_TIME, Date.now());
  }

  static getDeviceFpTime(): number {
    return PreferencesStore.getNumber(PreferencesStore.KEY_DEVICE_FP_TIME, 0);
  }

  /** 生成 32 位 hex 设备 ID（x-rpc-device_id） */
  private static genDeviceId(): string {
    const chars: string[] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
    let result: string = '';
    for (let i = 0; i < 32; i++) {
      result += chars[Math.floor(Math.random() * 16)];
    }
    return result;
  }
}
