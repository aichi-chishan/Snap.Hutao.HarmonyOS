/**
 * GachaType.ets
 * 祈愿类型枚举与展示名/查询顺序映射。
 */
export class GachaType {
  static readonly NOVICE: number = 100;
  static readonly PERMANENT: number = 200;
  static readonly AVATAR_EVENT: number = 301;
  static readonly WEAPON_EVENT: number = 302;
  static readonly CHRONICLE: number = 500;

  /** 常规查询顺序（含集录） */
  static readonly QUERY_ORDER: number[] = [
    GachaType.NOVICE,
    GachaType.PERMANENT,
    GachaType.AVATAR_EVENT,
    GachaType.WEAPON_EVENT,
    GachaType.CHRONICLE,
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
      default:
        return `卡池 ${gachaType}`;
    }
  }

  /** 是否有效卡池类型 */
  static isValid(gachaType: number): boolean {
    return gachaType === GachaType.NOVICE || gachaType === GachaType.PERMANENT ||
      gachaType === GachaType.AVATAR_EVENT || gachaType === GachaType.WEAPON_EVENT ||
      gachaType === GachaType.CHRONICLE;
  }
}
