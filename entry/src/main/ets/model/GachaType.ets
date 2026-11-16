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
  private static readonly AVATAR_EVENT_TYPES: number[] = [GachaType.AVATAR_EVENT, 400];
  private static readonly UGC_AVATAR_EVENT_TYPES: number[] = [GachaType.UGC_AVATAR_EVENT, 20011, 20012, 20021, 20022];

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
      case 400:
        return '角色活动祈愿-2';
      case GachaType.WEAPON_EVENT:
        return '武器活动祈愿';
      case GachaType.CHRONICLE:
        return '集录祈愿';
      case GachaType.UGC_STANDARD:
        return '常驻颂愿';
      case GachaType.UGC_AVATAR_EVENT:
        return '活动颂愿';
      case 20011:
      case 20012:
        return '活动颂愿-男';
      case 20021:
      case 20022:
        return '活动颂愿-女';
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
    return gachaType === GachaType.UGC_STANDARD || GachaType.UGC_AVATAR_EVENT_TYPES.includes(gachaType);
  }

  /** 用查询池聚合历史，记录中保留原始池号。 */
  static queryTypeOf(gachaType: number): number {
    if (GachaType.AVATAR_EVENT_TYPES.includes(gachaType)) { return GachaType.AVATAR_EVENT; }
    if (GachaType.UGC_AVATAR_EVENT_TYPES.includes(gachaType)) { return GachaType.UGC_AVATAR_EVENT; }
    return gachaType;
  }

  static storedTypes(queryType: number): number[] {
    if (queryType === GachaType.AVATAR_EVENT) { return GachaType.AVATAR_EVENT_TYPES.slice(); }
    if (queryType === GachaType.UGC_AVATAR_EVENT) { return GachaType.UGC_AVATAR_EVENT_TYPES.slice(); }
    return [queryType];
  }

  /** 是否有效卡池类型 */
  static isValid(gachaType: number): boolean {
    return GachaType.isStandard(gachaType) || GachaType.isBeyond(gachaType);
  }
}
