/**
 * GachaType.ets
 * 祈愿类型枚举与展示名/查询顺序映射（含千星奇域"颂愿"池，对齐 Windows GachaType 枚举）。
 */
export class GachaType {
  static readonly NOVICE: number = 100;
  static readonly PERMANENT: number = 200;
  static readonly AVATAR_EVENT: number = 301;
  static readonly WEAPON_EVENT: number = 302;
  static readonly CHRONICLE: number = 500;
  /** 千星奇域（颂愿）：常驻颂愿 */
  static readonly UGC_STANDARD: number = 1000;
  /** 千星奇域（颂愿）：活动颂愿 */
  static readonly UGC_AVATAR_EVENT: number = 2000;

  /** 常规查询顺序（含集录） */
  static readonly QUERY_ORDER: number[] = [
    GachaType.NOVICE,
    GachaType.PERMANENT,
    GachaType.AVATAR_EVENT,
    GachaType.WEAPON_EVENT,
    GachaType.CHRONICLE,
  ];

  /** 千星奇域查询顺序（走 getBeyondGachaLog，对齐 Windows BeyondGachaLog.QueryTypes） */
  static readonly BEYOND_ORDER: number[] = [
    GachaType.UGC_STANDARD,
    GachaType.UGC_AVATAR_EVENT,
  ];

  static nameOf(gachaType: number): string {
    switch (gachaType) {
      case GachaType.NOVICE:
        return '新手祈愿';
      case GachaType.PERMANENT:
        return '常驻祈愿';
      case GachaType.AVATAR_EVENT:
        return '角色活动祈愿';
      case GachaType.WEAPON_EVENT:
        return '武器活动祈愿';
      case GachaType.CHRONICLE:
        return '集录祈愿';
      case GachaType.UGC_STANDARD:
        return '常驻颂愿';
      case GachaType.UGC_AVATAR_EVENT:
        return '活动颂愿';
      default:
        return `卡池 ${gachaType}`;
    }
  }

  /** 是否常规卡池类型 */
  static isStandard(gachaType: number): boolean {
    return gachaType === GachaType.NOVICE || gachaType === GachaType.PERMANENT ||
      gachaType === GachaType.AVATAR_EVENT || gachaType === GachaType.WEAPON_EVENT ||
      gachaType === GachaType.CHRONICLE;
  }

  /** 是否千星奇域卡池类型 */
  static isBeyond(gachaType: number): boolean {
    return gachaType === GachaType.UGC_STANDARD || gachaType === GachaType.UGC_AVATAR_EVENT;
  }

  /** 是否有效卡池类型 */
  static isValid(gachaType: number): boolean {
    return GachaType.isStandard(gachaType) || GachaType.isBeyond(gachaType);
  }
}
