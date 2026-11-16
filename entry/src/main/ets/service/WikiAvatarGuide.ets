import { AvatarGuideReference } from '../model/AvatarGuideReference';
import { LocalePolicy } from '../model/LocalePolicy';

/** Public character guide links with bundled publisher IDs and no runtime lookup. */
export class WikiAvatarGuide {
  static label(target: string, locale: string): string {
    const labels: string[] = AvatarGuideReference.labels.get(LocalePolicy.resourceLocale(locale)) ?? [];
    switch (target) {
      case 'mys': return labels[0] ?? '';
      case 'bili': return labels[1] ?? '';
      case 'hoyolab': return labels[2] ?? '';
      default: return '';
    }
  }

  static unavailable(locale: string): string {
    const labels: string[] = AvatarGuideReference.labels.get(LocalePolicy.resourceLocale(locale)) ?? [];
    return labels[3] ?? '';
  }

  static url(target: string, avatarId: number, canonicalName: string, locale: string): string {
    if (!Number.isSafeInteger(avatarId) || avatarId < 10000000 || avatarId > 99999999) { return ''; }
    if (target === 'bili') {
      if (LocalePolicy.resourceLocale(locale) !== 'zh-Hans' || canonicalName.trim().length === 0) { return ''; }
      return `https://wiki.biligame.com/ys/${encodeURIComponent(canonicalName.trim())}/攻略`;
    }
    if (target === 'mys') {
      const guideId: number = AvatarGuideReference.chinese.get(avatarId) ?? 0;
      return guideId > 0
        ? `https://baike.mihoyo.com/ys/strategy/channel/map/39/${guideId}?bbs_presentation_style=no_header`
        : '';
    }
    if (target === 'hoyolab') {
      const guideId: number = AvatarGuideReference.hoyolab.get(avatarId) ?? 0;
      return guideId > 0 ? `https://www.hoyolab.com/guidelist?game_id=2&guide_id=${guideId}` : '';
    }
    return '';
  }
}
