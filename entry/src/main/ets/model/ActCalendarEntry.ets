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

/**
 * act_calendar 奖励项（对齐 Windows Web/Hoyolab/Takumi/GameRecord/ActCalendar/ActReward.cs）：
 * item_id / name / icon / wiki_url / num / rarity(QUALITY_* 字符串枚举) / homepage_show。
 */
export class ActRewardEntry {
  itemId: string = '';
  name: string = '';
  /** 图标 URL（webstatic） */
  icon: string = '';
  /** 数量（响应字段 num） */
  num: number = 0;
  /** 品质：1 白 2 绿 3 蓝 4 紫 5 橙（QUALITY_* 解析；失败 0） */
  rarity: number = 0;

  /** 从图标 URL 提取 rawfile ItemIcon 图标名（UI_ItemIcon_201001）；非 URL 原样返回 */
  iconName(): string {
    if (this.icon.length === 0) {
      return '';
    }
    if (this.icon.startsWith('http') || this.icon.startsWith('file://')) {
      const slash: number = this.icon.lastIndexOf('/');
      const file: string = slash >= 0 ? this.icon.substring(slash + 1) : this.icon;
      const dot: number = file.lastIndexOf('.');
      return dot > 0 ? file.substring(0, dot) : file;
    }
    return this.icon;
  }
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

  // ===== 进度详情（字段名对齐 Windows ActCalendar/*.cs 模型，optional 兜底） =====
  /** 奖励列表（act_list 项的 reward_list；卡池无） */
  rewards: ActRewardEntry[] = [];

  /** 深境螺旋 tower_detail：is_unlock / max_star / total_star / has_data（ActTowerDetail.cs） */
  hasTowerDetail: boolean = false;
  towerUnlocked: boolean = false;
  towerMaxStar: number = 0;
  towerTotalStar: number = 0;

  /** 幻想真境剧诗 role_combat_detail：is_unlock / max_round_id / has_data（ActRoleCombatDetail.cs） */
  hasRoleCombatDetail: boolean = false;
  roleCombatUnlocked: boolean = false;
  roleCombatMaxRound: number = 0;
  roleCombatHasData: boolean = false;

  /** 幽境危战 hard_challenge_detail：is_unlock / sub{x,y}（ActHardChallengeDetail.cs） */
  hasHardDetail: boolean = false;
  hardUnlocked: boolean = false;
  hardSubX: number = 0;
  hardSubY: number = 0;

  /** 探索 explore_detail：explore_percent（ActExploreDetail.cs） */
  hasExploreDetail: boolean = false;
  explorePercent: number = 0;

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

  /**
   * 按活动类型的进度行文案（对齐 Windows AnnouncementPage.xaml 各类型模板：
   * TowerTemplate 星数 / RoleCombatTemplate 最高回合 / HardChallengeTemplate 进度 / ExploreTemplate 探索度）。
   * 仅当响应带对应 detail 块才显示；无 detail 返回空串。
   */
  progressLine(): string {
    if (this.hasTowerDetail) {
      return this.towerUnlocked ? `深境螺旋 ${this.towerMaxStar}/${this.towerTotalStar} 星` : '深境螺旋 未解锁';
    }
    if (this.hasRoleCombatDetail) {
      if (!this.roleCombatUnlocked) {
        return '剧诗 未解锁';
      }
      return this.roleCombatMaxRound > 0 ? `剧诗 第${this.roleCombatMaxRound}幕` : '剧诗 暂无数据';
    }
    if (this.hasHardDetail) {
      return this.hardUnlocked ? `幽境危战 ${this.hardSubX}/${this.hardSubY}` : '幽境危战 未解锁';
    }
    if (this.hasExploreDetail) {
      return `探索度 ${this.explorePercent}%`;
    }
    return '';
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
    // 奖励列表 + 各类型进度详情（optional 兜底，字段名对齐 Windows ActCalendar 模型）
    ActCalendarEntry.parseRewards(entry, item['reward_list']);
    const tower = item['tower_detail'] as Record<string, Object>;
    if (tower !== undefined && tower !== null) {
      entry.hasTowerDetail = true;
      entry.towerUnlocked = ActCalendarEntry.toBool(tower['is_unlock']);
      entry.towerMaxStar = Number(tower['max_star'] ?? 0);
      entry.towerTotalStar = Number(tower['total_star'] ?? 0);
    }
    const roleCombat = item['role_combat_detail'] as Record<string, Object>;
    if (roleCombat !== undefined && roleCombat !== null) {
      entry.hasRoleCombatDetail = true;
      entry.roleCombatUnlocked = ActCalendarEntry.toBool(roleCombat['is_unlock']);
      entry.roleCombatMaxRound = Number(roleCombat['max_round_id'] ?? 0);
      entry.roleCombatHasData = ActCalendarEntry.toBool(roleCombat['has_data']);
    }
    const hard = item['hard_challenge_detail'] as Record<string, Object>;
    if (hard !== undefined && hard !== null) {
      entry.hasHardDetail = true;
      entry.hardUnlocked = ActCalendarEntry.toBool(hard['is_unlock']);
      const sub = hard['sub'] as Record<string, Object>;
      if (sub !== undefined && sub !== null) {
        entry.hardSubX = Number(sub['x'] ?? 0);
        entry.hardSubY = Number(sub['y'] ?? 0);
      }
    }
    const explore = item['explore_detail'] as Record<string, Object>;
    if (explore !== undefined && explore !== null) {
      entry.hasExploreDetail = true;
      entry.explorePercent = Number(explore['explore_percent'] ?? 0);
    }
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

  /** reward_list 数组解析（act_list 项；卡池无此字段） */
  private static parseRewards(entry: ActCalendarEntry, raw: Object): void {
    const list = raw as Array<Object>;
    if (list === undefined || list === null) {
      return;
    }
    for (let i = 0; i < list.length; i++) {
      const r = list[i] as Record<string, Object>;
      const reward: ActRewardEntry = new ActRewardEntry();
      reward.itemId = String(r['item_id'] ?? '');
      reward.name = String(r['name'] ?? '');
      reward.icon = String(r['icon'] ?? '');
      reward.num = Number(r['num'] ?? 0);
      reward.rarity = ActCalendarEntry.rarityOf(r['rarity']);
      entry.rewards.push(reward);
    }
  }

  /** 品质解析：QUALITY_* 字符串枚举（ActReward rarity，JsonStringEnumConverter）或数字 */
  private static rarityOf(v: Object): number {
    if (v === undefined || v === null) {
      return 0;
    }
    const s: string = String(v);
    if (s.indexOf('ORANGE_SP') >= 0) {
      return 105;
    }
    if (s.indexOf('ORANGE') >= 0) {
      return 5;
    }
    if (s.indexOf('PURPLE') >= 0) {
      return 4;
    }
    if (s.indexOf('BLUE') >= 0) {
      return 3;
    }
    if (s.indexOf('GREEN') >= 0) {
      return 2;
    }
    if (s.indexOf('WHITE') >= 0) {
      return 1;
    }
    const n: number = Number(s);
    return Number.isNaN(n) ? 0 : n;
  }

  /** 布尔字段兜底解析（响应 true/false 或 1/0） */
  private static toBool(v: Object): boolean {
    if (v === undefined || v === null) {
      return false;
    }
    if (typeof v === 'boolean') {
      return v as boolean;
    }
    const s: string = String(v).toLowerCase();
    return s === 'true' || s === '1';
  }
}
