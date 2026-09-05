/**
 * SpiralAbyss.ets
 * 深境螺旋数据模型（对齐米哈游 spiralAbyss 接口字段）。
 */

/** 深渊出战角色 */
export class SpiralAbyssAvatar {
  id: number = 0;
  icon: string = '';
  level: number = 0;
  rarity: number = 0;
}

/** 深渊每半场战斗 */
export class SpiralAbyssBattle {
  index: number = 0;
  timestamp: number = 0;
  avatars: SpiralAbyssAvatar[] = [];

  /** 从 API item 解析 */
  static fromJson(obj: Object): SpiralAbyssBattle {
    const item = obj as Record<string, Object>;
    const b: SpiralAbyssBattle = new SpiralAbyssBattle();
    b.index = num(item['index']);
    b.timestamp = num(item['timestamp']) * 1000;
    const avatars = item['avatars'] as Array<Object>;
    if (avatars !== undefined && avatars !== null) {
      for (let i = 0; i < avatars.length; i++) {
        const av = avatars[i] as Record<string, Object>;
        const a: SpiralAbyssAvatar = new SpiralAbyssAvatar();
        a.id = num(av['id']);
        a.icon = String(av['icon'] ?? '');
        a.level = num(av['level']);
        a.rarity = num(av['rarity']);
        b.avatars.push(a);
      }
    }
    return b;
  }
}

/** 深渊间目 */
export class SpiralAbyssLevel {
  index: number = 0;
  star: number = 0;
  maxStar: number = 0;
  battles: SpiralAbyssBattle[] = [];
}

/** 深渊层 */
export class SpiralAbyssFloor {
  index: number = 0;
  icon: string = '';
  isUnlock: boolean = false;
  star: number = 0;
  maxStar: number = 0;
  levels: SpiralAbyssLevel[] = [];

  /** 从 API item 解析 */
  static fromJson(obj: Object): SpiralAbyssFloor {
    const item = obj as Record<string, Object>;
    const f: SpiralAbyssFloor = new SpiralAbyssFloor();
    f.index = num(item['index']);
    f.icon = String(item['icon'] ?? '');
    f.star = num(item['star']);
    f.maxStar = num(item['max_star']);
    f.isUnlock = item['is_unlock'] === true;
    const levels = item['levels'] as Array<Object>;
    if (levels !== undefined && levels !== null) {
      for (let i = 0; i < levels.length; i++) {
        const lv = levels[i] as Record<string, Object>;
        const l: SpiralAbyssLevel = new SpiralAbyssLevel();
        l.index = num(lv['index']);
        l.star = num(lv['star']);
        l.maxStar = num(lv['max_star']);
        const battles = lv['battles'] as Array<Object>;
        if (battles !== undefined && battles !== null) {
          for (let j = 0; j < battles.length; j++) {
            l.battles.push(SpiralAbyssBattle.fromJson(battles[j]));
          }
        }
        f.levels.push(l);
      }
    }
    return f;
  }
}

/** 深渊统计排行（击败/伤害/承伤/普攻/元素爆发/满星，对齐 Windows SpiralAbyssRank） */
export class SpiralAbyssRank {
  avatarId: number = 0;
  /** avatar_icon 名（Enka/米哈游 CDN 可用） */
  avatarIcon: string = '';
  value: number = 0;
  rarity: number = 0;

  static fromJson(obj: Object): SpiralAbyssRank {
    const item = obj as Record<string, Object>;
    const r: SpiralAbyssRank = new SpiralAbyssRank();
    r.avatarId = num(item['avatar_id']);
    r.avatarIcon = String(item['avatar_icon'] ?? '');
    r.value = num(item['value']);
    r.rarity = num(item['rarity']);
    return r;
  }
}

/** 深渊整体数据 */
export class SpiralAbyssData {
  /** 多语言字段取值：优先 zh-cn，回退首个字符串值 */
  static pickText(v: Object): string {
    if (v === undefined || v === null) {
      return '';
    }
    if (typeof v === 'string') {
      return String(v);
    }
    const o = v as Record<string, Object>;
    const zh = o['zh-cn'];
    if (zh !== undefined && zh !== null) {
      return String(zh);
    }
    for (const k of Object.keys(o)) {
      const val = o[k];
      if (typeof val === 'string' && (val as string).length > 0) {
        return String(val);
      }
    }
    return '';
  }

  scheduleId: number = 0;
  startTime: number = 0;
  endTime: number = 0;
  totalBattleTimes: number = 0;
  totalWinTimes: number = 0;
  maxFloor: string = '';
  totalStar: number = 0;
  isUnlock: boolean = false;
  floors: SpiralAbyssFloor[] = [];
  /** 原始响应 JSON（深渊期数历史入库用，service 填充） */
  rawJson: string = '';
  /** 渊月祝福（对齐 Windows 攻辉之月卡：名称 + 效果描述） */
  buffName: string = '';
  buffDesc: string = '';
  /** 本期统计排行（对齐 Windows 详情页 5 卡：满星/击败/伤害/承伤/普攻/元素爆发） */
  revealRank: SpiralAbyssRank[] = [];
  defeatRank: SpiralAbyssRank[] = [];
  damageRank: SpiralAbyssRank[] = [];
  takeDamageRank: SpiralAbyssRank[] = [];
  normalSkillRank: SpiralAbyssRank[] = [];
  energySkillRank: SpiralAbyssRank[] = [];

  /** 从 API data 解析 */
  static fromJson(data: Object): SpiralAbyssData {
    const obj = data as Record<string, Object>;
    const s: SpiralAbyssData = new SpiralAbyssData();
    s.scheduleId = num(obj['schedule_id']);
    s.startTime = num(obj['start_time']) * 1000;
    s.endTime = num(obj['end_time']) * 1000;
    s.totalBattleTimes = num(obj['total_battle_times']);
    s.totalWinTimes = num(obj['total_win_times']);
    s.maxFloor = String(obj['max_floor'] ?? '');
    s.totalStar = num(obj['total_star']);
    s.isUnlock = obj['is_unlock'] === true;
    s.revealRank = SpiralAbyssData.parseRanks(obj['reveal_rank']);
    s.defeatRank = SpiralAbyssData.parseRanks(obj['defeat_rank']);
    s.damageRank = SpiralAbyssData.parseRanks(obj['damage_rank']);
    s.takeDamageRank = SpiralAbyssData.parseRanks(obj['take_damage_rank']);
    s.normalSkillRank = SpiralAbyssData.parseRanks(obj['normal_skill_rank']);
    s.energySkillRank = SpiralAbyssData.parseRanks(obj['energy_skill_rank']);
    const floors = obj['floors'] as Array<Object>;
    if (floors !== undefined && floors !== null) {
      for (let i = 0; i < floors.length; i++) {
        s.floors.push(SpiralAbyssFloor.fromJson(floors[i]));
      }
    }

    // 渊月祝福（buff 为多语言对象：name/description 取 zh-cn 或首个字符串值）
    const buffArr = obj['buff'] as Array<Object>;
    if (buffArr !== undefined && buffArr !== null && buffArr.length > 0) {
      const b0 = buffArr[0] as Record<string, Object>;
      const nm = b0['name'];
      const ds = b0['description'];
      s.buffName = SpiralAbyssData.pickText(nm);
      s.buffDesc = SpiralAbyssData.pickText(ds);
    }
    return s;
  }

  private static parseRanks(v: Object): SpiralAbyssRank[] {
    const out: SpiralAbyssRank[] = [];
    const arr = v as Array<Object>;
    if (arr !== undefined && arr !== null) {
      for (let i = 0; i < arr.length; i++) {
        out.push(SpiralAbyssRank.fromJson(arr[i]));
      }
    }
    return out;
  }
}

/** 数字安全解析 */
function num(v: Object): number {
  if (v === undefined || v === null) {
    return 0;
  }
  const n: number = Number(v);
  return Number.isNaN(n) ? 0 : n;
}
