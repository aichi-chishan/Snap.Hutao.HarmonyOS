/**
 * ActCalendarEntry.ets
 * 活动日历条目：对齐米哈游 act_calendar 响应（act_list/fixed_act_list + 卡池列表）。
 */
export class ActCalendarType {
  static readonly ACTIVITY: number = 1;
  static readonly CARD_POOL: number = 2;
  static readonly SIGN_IN: number = 3;
  static readonly OTHER: number = 100;

  static nameOf(type: number): string {
    switch (type) {
      case ActCalendarType.ACTIVITY:
        return '活动';
      case ActCalendarType.CARD_POOL:
        return '卡池';
      case ActCalendarType.SIGN_IN:
        return '签到';
      default:
        return '其他';
    }
  }
}

/** 活动状态：1 未开始 / 2 进行中 */
export enum ActStatus {
  Upcoming = 1,
  Ongoing = 2,
}

export class ActCalendarEntry {
  /** 展示类型（1 活动 2 卡池） */
  type: number = 0;
  typeName: string = '';
  /** 名称（活动 name / 卡池 pool_name） */
  name: string = '';
  /** 描述 */
  desc: string = '';
  /** 服务端活动类型（ActType 枚举） */
  actType: number = 0;
  /** 起止时间戳（毫秒） */
  startTime: number = 0;
  endTime: number = 0;
  /** 活动状态 1 未开始 2 进行中 */
  status: number = 0;
  /** 倒计时秒 */
  countdownSeconds: number = 0;
  /** 卡池版本名 */
  versionName: string = '';
  /** 卡池内角色头像 URL 列表 */
  avatarIcons: string[] = [];
  /** 卡池内武器图标 URL 列表 */
  weaponIcons: string[] = [];
  /** 跳转链接 */
  jumpUrl: string = '';

  /** 是否进行中 */
  isOngoing(nowMs: number): boolean {
    return this.startTime <= nowMs && nowMs <= this.endTime;
  }

  /** 状态文案 */
  statusText(nowMs: number): string {
    if (this.countdownSeconds > 0) {
      const span: number = this.countdownSeconds;
      if (span >= 3600 * 24) {
        return `${Math.floor(span / 3600 / 24)}天后开始`;
      }
      if (span >= 3600) {
        return `${Math.floor(span / 3600)}小时后开始`;
      }
      if (span > 0) {
        return `${Math.floor(span / 60)}分钟后开始`;
      }
    }
    if (this.isOngoing(nowMs)) {
      return '进行中';
    }
    return this.startTime > nowMs ? '未开始' : '已结束';
  }

  /** 时间跨度文案（对齐 Windows "9 天 18 小时"；默认按天/时/分/秒降级） */
  static timeSpan(ms: number): string {
    const sec: number = Math.max(0, Math.floor(ms / 1000));
    const day: number = Math.floor(sec / 3600 / 24);
    const hour: number = Math.floor(sec / 3600 % 24);
    const min: number = Math.floor(sec / 60 % 60);
    if (day > 0) {
      return `${day} 天 ${hour} 小时`;
    }
    if (hour > 0) {
      return `${hour} 小时 ${min} 分钟`;
    }
    if (min > 0) {
      return `${min} 分钟`;
    }
    return `${sec} 秒`;
  }

  /** 解析活动项（act_list/fixed_act_list 元素） */
  static fromAct(obj: Object): ActCalendarEntry {
    const item = obj as Record<string, Object>;
    const entry: ActCalendarEntry = new ActCalendarEntry();
    entry.type = ActCalendarType.ACTIVITY;
    entry.typeName = ActCalendarType.nameOf(entry.type);
    entry.actType = Number(item['type'] ?? 0);
    entry.name = String(item['name'] ?? '');
    entry.desc = String(item['desc'] ?? '');
    entry.startTime = ActCalendarEntry.toMs(item['start_timestamp']);
    entry.endTime = ActCalendarEntry.toMs(item['end_timestamp']);
    entry.status = Number(item['status'] ?? 0);
    entry.countdownSeconds = Number(item['countdown_seconds'] ?? 0);
    entry.jumpUrl = String(item['strategy'] ?? '');
    return entry;
  }

  /** 解析卡池项（*_card_pool_list 元素） */
  static fromCardPool(obj: Object): ActCalendarEntry {
    const item = obj as Record<string, Object>;
    const entry: ActCalendarEntry = new ActCalendarEntry();
    entry.type = ActCalendarType.CARD_POOL;
    entry.typeName = ActCalendarType.nameOf(entry.type);
    entry.name = String(item['pool_name'] ?? '');
    entry.versionName = String(item['version_name'] ?? '');
    entry.desc = String(item['version_name'] ?? '');
    entry.startTime = ActCalendarEntry.toMs(item['start_timestamp']);
    entry.endTime = ActCalendarEntry.toMs(item['end_timestamp']);
    entry.countdownSeconds = Number(item['countdown_seconds'] ?? 0);
    entry.jumpUrl = String(item['jump_url'] ?? '');
    const avatars = item['avatars'] as Array<Object>;
    if (avatars !== undefined && avatars !== null) {
      for (let i = 0; i < avatars.length; i++) {
        const av = avatars[i] as Record<string, Object>;
        const icon: string = String(av['icon'] ?? '');
        if (icon.length > 0) {
          entry.avatarIcons.push(icon);
        }
      }
    }
    const weapons = item['weapon'] as Array<Object>;
    if (weapons !== undefined && weapons !== null) {
      for (let i = 0; i < weapons.length; i++) {
        const w = weapons[i] as Record<string, Object>;
        const icon: string = String(w['icon'] ?? '');
        if (icon.length > 0) {
          entry.weaponIcons.push(icon);
        }
      }
    }
    return entry;
  }

  private static toMs(v: Object): number {
    if (v === undefined || v === null) {
      return 0;
    }
    const n: number = Number(v);
    const ts: number = Number.isNaN(n) ? 0 : n;
    return ts > 100000000000 ? ts : ts * 1000;
  }
}
