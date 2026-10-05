import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { BackpackScoreProfile, BackpackScoreSettings } from '../model/BackpackScore';

/** Local non-secret preferences; this key participates in the existing portable app.* backup. */
export class BackpackScoreService {
  static readonly KEY: string = 'app.backpack.score_profiles.v1';

  static load(): BackpackScoreSettings {
    const raw: string = PreferencesStore.getString(BackpackScoreService.KEY, '');
    if (raw.length === 0) { return new BackpackScoreSettings(); }
    try {
      if (raw.length > 65536) { throw new Error('评分配置过大'); }
      const settings: BackpackScoreSettings = JSON.parse(raw) as BackpackScoreSettings;
      if (settings === null || settings.version !== 1 || !Number.isSafeInteger(settings.revision) || settings.revision < 0 ||
        typeof settings.activeId !== 'string' || !Array.isArray(settings.profiles) || settings.profiles.length > 100) {
        throw new Error('评分配置结构不受支持');
      }
      const seen: Set<string> = new Set<string>();
      for (const profile of settings.profiles) {
        BackpackScoreProfile.validate(profile);
        if (profile.id.length === 0 || seen.has(profile.id)) { throw new Error('评分配置标识重复'); }
        seen.add(profile.id);
      }
      if (settings.activeId.length > 0 && !seen.has(settings.activeId)) { throw new Error('活动评分配置不存在'); }
      settings.warning = '';
      return settings;
    } catch (e) {
      const fallback: BackpackScoreSettings = new BackpackScoreSettings();
      fallback.warning = '已保存评分配置损坏或版本不支持；暂用默认评分，原设置未覆盖';
      return fallback;
    }
  }

  static active(settings: BackpackScoreSettings): BackpackScoreProfile {
    const profile: BackpackScoreProfile | undefined = settings.profiles.find((value: BackpackScoreProfile): boolean => value.id === settings.activeId);
    return profile === undefined ? BackpackScoreProfile.create(0) : BackpackScoreProfile.clone(profile);
  }

  static save(profile: BackpackScoreProfile, revision: number): BackpackScoreSettings {
    BackpackScoreProfile.validate(profile);
    const settings: BackpackScoreSettings = BackpackScoreService.forEdit(revision);
    const next: BackpackScoreProfile = BackpackScoreProfile.clone(profile);
    next.name = next.name.trim();
    const index: number = settings.profiles.findIndex((value: BackpackScoreProfile): boolean => value.id === next.id);
    if (next.id.length > 0 && index < 0) { throw new Error('评分配置已删除，请重新打开编辑'); }
    if (index >= 0) { settings.profiles[index] = next; }
    else {
      if (settings.profiles.length >= 100) { throw new Error('最多保存 100 个评分配置'); }
      next.id = `score_${Date.now()}_${settings.revision + 1}`;
      settings.profiles.push(next);
    }
    settings.activeId = next.id;
    BackpackScoreService.persist(settings);
    return settings;
  }

  static remove(id: string, revision: number): BackpackScoreSettings {
    const settings: BackpackScoreSettings = BackpackScoreService.forEdit(revision);
    if (!settings.profiles.some((profile: BackpackScoreProfile): boolean => profile.id === id)) {
      throw new Error('评分配置不存在');
    }
    settings.profiles = settings.profiles.filter((profile: BackpackScoreProfile): boolean => profile.id !== id);
    if (settings.activeId === id) { settings.activeId = ''; }
    BackpackScoreService.persist(settings);
    return settings;
  }

  private static forEdit(revision: number): BackpackScoreSettings {
    const settings: BackpackScoreSettings = BackpackScoreService.load();
    if (settings.warning.length > 0) { throw new Error(settings.warning); }
    if (settings.revision !== revision) { throw new Error('评分设置已改变，请重新打开编辑'); }
    return settings;
  }

  private static persist(settings: BackpackScoreSettings): void {
    settings.revision++;
    PreferencesStore.setString(BackpackScoreService.KEY, JSON.stringify(settings));
  }
}
