import { GachaType } from '../model/GachaType';

/** UI labels for query pools. Persisted types and exported strings remain unchanged. */
export function gachaPoolLabel(type: number): ResourceStr {
  switch (GachaType.queryTypeOf(type)) {
    case GachaType.NOVICE: return $r('app.string.ui_gacha_pool_novice');
    case GachaType.PERMANENT: return $r('app.string.ui_gacha_pool_permanent');
    case GachaType.AVATAR_EVENT: return $r('app.string.ui_gacha_pool_avatar_event');
    case GachaType.WEAPON_EVENT: return $r('app.string.ui_gacha_pool_weapon_event');
    case GachaType.CHRONICLE: return $r('app.string.ui_gacha_pool_chronicled');
    case GachaType.UGC_STANDARD: return $r('app.string.ui_gacha_pool_beyond_permanent');
    case GachaType.UGC_AVATAR_EVENT: return $r('app.string.ui_gacha_pool_beyond_event');
    default: return GachaType.nameOf(type);
  }
}
