import { GachaType } from './GachaType';

/** Upstream bounded five-star thresholds; 0 means no applicable finite five-star model. */
export class GachaPoolRules {
  static fiveStarThreshold(type: number): number {
    if (type === GachaType.WEAPON_EVENT) { return 80; }
    if (type === GachaType.NOVICE || type === GachaType.PERMANENT ||
      type === GachaType.AVATAR_EVENT || type === 400 || type === GachaType.CHRONICLE ||
      type === GachaType.UGC_AVATAR_EVENT) { return 90; }
    return 0;
  }

  static fourStarThreshold(type: number): number {
    if (type === GachaType.UGC_STANDARD) { return 90; }
    return GachaPoolRules.fiveStarThreshold(type) > 0 ? 10 : 0;
  }

  static distributionKind(type: number): string {
    if (type === GachaType.WEAPON_EVENT) { return 'weaponDistribution'; }
    if (type === GachaType.AVATAR_EVENT || type === 400) { return 'avatarDistribution'; }
    if (type === GachaType.PERMANENT || type === GachaType.NOVICE) { return 'standardDistribution'; }
    if (type === GachaType.CHRONICLE) { return 'chronicledDistribution'; }
    if (type === GachaType.UGC_AVATAR_EVENT) { return 'beyondEventDistribution'; }
    return '';
  }
}
