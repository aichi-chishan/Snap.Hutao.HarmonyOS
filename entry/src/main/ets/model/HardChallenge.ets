/**
 * HardChallenge.ets
 * 强敌挑战（hard_challenge 接口）模型。
 * 对齐 Windows HardChallenge.cs：data[]（数组，每期一条）；data: schedule/single/mp/blings。
 * single/mp 是 HardChallengeDataEntry（hasData/best/challenges[]）；challenge：name/second/teams/best_avatar/monster。
 */
/** 怪物词缀标签（对齐 Windows HardChallengeMonsterTag） */
export class HardChallengeMonsterTag {
  type: number = 0;
  desc: string = '';
}

export class HardChallengeMonster {
  name: string = '';
  icon: string = '';
  level: number = 0;
  /** 怪物描述（富文本，展示前清洗） */
  desc: string = '';
  /** 词缀标签 */
  tags: HardChallengeMonsterTag[] = [];
}

export class HardChallengeSimpleAvatar {
  avatarId: number = 0;
  name: string = '';
  element: string = '';
  image: string = '';
  rarity: number = 0;
  /** 命座数（对齐 Windows HardChallengeAvatar.Rank） */
  rank: number = 0;
  level: number = 0;
  isPlus: boolean = false;
}

/** 最速队伍 */
export class HardChallengeTeam {
  avatars: HardChallengeSimpleAvatar[] = [];
}

/** 最佳角色伤害 */
export class HardChallengeBestAvatar {
  avatarId: number = 0;
  name: string = '';
  image: string = '';
  rarity: number = 0;
  value: number = 0;
  type: string = '';
}

/** 单个挑战（DataEntry 内） */
export class HardChallengeChallenge {
  name: string = '';
  second: number = 0;
  teams: HardChallengeTeam[] = [];
  bestAvatars: HardChallengeBestAvatar[] = [];
  monster: HardChallengeMonster = new HardChallengeMonster();
}

/** 最佳成绩（DataEntry.best） */
export class HardChallengeBest {
  /** 难度级别（1-6） */
  difficulty: number = 0;
  /** 秒数（330 = 最速） */
  second: number = 0;
  /** 图标名（逗号分隔取最后段） */
  icon: string = '';
  /** 难度名（本地化） */
  name: string = '';
}

/** 单挑/联机数据组（DataEntry） */
export class HardChallengeDataEntry {
  hasData: boolean = false;
  best: HardChallengeBest = new HardChallengeBest();
  challenges: HardChallengeChallenge[] = [];
}

/** 档期 */
export class HardChallengeScheduleItem {
  scheduleId: number = 0;
  startTime: number = 0;
  endTime: number = 0;
  startDateTime: string = '';
  endDateTime: string = '';
  isValid: boolean = false;
  name: string = '';
}

export class HardChallengeData {
  schedule: HardChallengeScheduleItem[] = [];
  single: HardChallengeDataEntry = new HardChallengeDataEntry();
  mp: HardChallengeDataEntry = new HardChallengeDataEntry();
  blings: HardChallengeSimpleAvatar[] = [];
}

export class HardChallengeRoot {
  data: HardChallengeData = new HardChallengeData();
  /** 全部可返回档期，data 保留首项兼容首页调用。 */
  periods: HardChallengeData[] = [];
  itemRawJson: string[] = [];
  isUnlock: boolean = false;
  /** 内层 data 原始 JSON（service 填充；期数历史入库用，仅内存） */
  rawJson: string = '';

  static fromJson(obj: Object): HardChallengeRoot {
    const root: HardChallengeRoot = new HardChallengeRoot();
    const wrapper = obj as Record<string, Object>;
    root.isUnlock = HardChallengeRoot.bool(wrapper['is_unlock']);
    const raw: Object = wrapper['data'];
    const items: Object[] = Array.isArray(raw) ? raw as Object[] :
      (raw !== undefined && raw !== null ? [raw] : []);
    for (const item of items) {
      root.periods.push(HardChallengeRoot.parseData(item));
      const saved: Record<string, Object> = { 'is_unlock': root.isUnlock, 'data': [item] };
      root.itemRawJson.push(JSON.stringify(saved));
    }
    if (root.periods.length > 0) {
      root.data = root.periods[0];
    }
    return root;
  }

  private static parseData(obj: Object): HardChallengeData {
    const data: Record<string, Object> = obj as Record<string, Object>;
    const result: HardChallengeData = new HardChallengeData();
    result.single = HardChallengeRoot.parseEntry(data['single']);
    result.mp = HardChallengeRoot.parseEntry(data['mp']);
    result.blings = HardChallengeRoot.avatarListFromJson(data['blings']);
    const schedRaw: Object = data['schedule'];
    if (schedRaw !== undefined && schedRaw !== null) {
      const schedules: Object[] = Array.isArray(schedRaw) ? schedRaw as Object[] : [schedRaw];
      for (const schedule of schedules) {
        result.schedule.push(HardChallengeRoot.parseSchedule(schedule));
      }
    }
    return result;
  }

  /** 档期条目解析（schedule_id 为期数历史键） */
  private static parseSchedule(obj: Object): HardChallengeScheduleItem {
    const s = obj as Record<string, Object>;
    const item: HardChallengeScheduleItem = new HardChallengeScheduleItem();
    item.scheduleId = HardChallengeRoot.number(s['schedule_id'], 0);
    item.startTime = HardChallengeRoot.number(s['start_time'], 0);
    item.endTime = HardChallengeRoot.number(s['end_time'], 0);
    item.startDateTime = HardChallengeRoot.dtStr(s['start_date_time']);
    item.endDateTime = HardChallengeRoot.dtStr(s['end_date_time']);
    item.isValid = HardChallengeRoot.bool(s['is_valid']);
    item.name = HardChallengeRoot.str(s['name']);
    return item;
  }

  private static parseEntry(obj: Object | undefined): HardChallengeDataEntry {
    const entry: HardChallengeDataEntry = new HardChallengeDataEntry();
    if (obj === undefined || obj === null) {
      return entry;
    }
    const o = obj as Record<string, Object>;
    entry.hasData = HardChallengeRoot.bool(o['has_data']);
    const best = o['best'] as Record<string, Object>;
    if (best !== undefined && best !== null) {
      entry.best.difficulty = HardChallengeRoot.number(best['difficulty'], 0);
      entry.best.second = HardChallengeRoot.number(best['second'], 0);
      entry.best.icon = HardChallengeRoot.str(best['icon']);
      entry.best.name = HardChallengeRoot.str(best['name']);
    }
    const challenges = o['challenge'] as Array<Object>;
    if (challenges === undefined || challenges === null) {
      // 兼容复数字段名
      const alt = o['challenges'] as Array<Object>;
      if (alt !== undefined && alt !== null) {
        for (let i = 0; i < alt.length; i++) {
          entry.challenges.push(HardChallengeRoot.parseChallenge(alt[i]));
        }
      }
    } else {
      for (let i = 0; i < challenges.length; i++) {
        entry.challenges.push(HardChallengeRoot.parseChallenge(challenges[i]));
      }
    }
    return entry;
  }

  private static parseChallenge(obj: Object): HardChallengeChallenge {
    const o = obj as Record<string, Object>;
    const c: HardChallengeChallenge = new HardChallengeChallenge();
    c.name = HardChallengeRoot.str(o['name']);
    c.second = HardChallengeRoot.number(o['second'], 0);
    const teams = o['teams'] as Array<Object>;
    if (teams !== undefined && teams !== null) {
      const flatTeam: HardChallengeTeam = new HardChallengeTeam();
      for (const raw of teams) {
        const t: Record<string, Object> = raw as Record<string, Object>;
        const avatars: Object = t['avatars'];
        if (Array.isArray(avatars)) {
          const team: HardChallengeTeam = new HardChallengeTeam();
          team.avatars = HardChallengeRoot.avatarListFromJson(avatars);
          c.teams.push(team);
        } else {
          // 官方 teams 是 HardChallengeAvatar[]，并非队伍对象数组。
          flatTeam.avatars.push(HardChallengeRoot.parseAvatarSimple(raw));
        }
      }
      if (flatTeam.avatars.length > 0) {
        c.teams.unshift(flatTeam);
      }
    }
    const bests = o['best_avatar'] as Array<Object>;
    if (bests !== undefined && bests !== null) {
      for (let i = 0; i < bests.length; i++) {
        const b = bests[i] as Record<string, Object>;
        const best: HardChallengeBestAvatar = new HardChallengeBestAvatar();
        best.avatarId = HardChallengeRoot.number(b['avatar_id'], 0);
        best.name = HardChallengeRoot.str(b['name']);
        // Windows 字段名 side_icon（URL）；兼容 image
        const iconRaw: string = HardChallengeRoot.str(b['side_icon']);
        best.image = iconRaw.length > 0 ? iconRaw : HardChallengeRoot.str(b['image']);
        best.rarity = HardChallengeRoot.number(b['rarity'], 0);
        // 实际字段名 dps（兼容旧 value）
        const dps: number = HardChallengeRoot.number(b['dps'], -1);
        best.value = dps >= 0 ? dps : HardChallengeRoot.number(b['value'], 0);
        best.type = HardChallengeRoot.bestType(b['type']);
        c.bestAvatars.push(best);
      }
    }
    const monster = o['monster'] as Record<string, Object>;
    if (monster !== undefined && monster !== null) {
      c.monster.name = HardChallengeRoot.str(monster['name']);
      c.monster.icon = HardChallengeRoot.str(monster['icon']);
      c.monster.level = HardChallengeRoot.number(monster['level'], 0);
      c.monster.desc = HardChallengeRoot.str(monster['desc']);
      const tags = monster['tags'] as Array<Object>;
      if (tags !== undefined && tags !== null) {
        for (let i = 0; i < tags.length; i++) {
          const t = tags[i] as Record<string, Object>;
          const tag: HardChallengeMonsterTag = new HardChallengeMonsterTag();
          tag.type = HardChallengeRoot.number(t['type'], 0);
          tag.desc = HardChallengeRoot.str(t['desc']);
          c.monster.tags.push(tag);
        }
      }
    }
    return c;
  }

  static avatarListFromJson(obj: Object | undefined): HardChallengeSimpleAvatar[] {
    const list: HardChallengeSimpleAvatar[] = [];
    if (obj === undefined || obj === null) {
      return list;
    }
    const arr = obj as Array<Object>;
    for (let i = 0; i < arr.length; i++) {
      list.push(HardChallengeRoot.parseAvatarSimple(arr[i]));
    }
    return list;
  }

  private static parseAvatarSimple(obj: Object): HardChallengeSimpleAvatar {
    const o = obj as Record<string, Object>;
    const a: HardChallengeSimpleAvatar = new HardChallengeSimpleAvatar();
    a.avatarId = HardChallengeRoot.number(o['avatar_id'], 0);
    a.name = HardChallengeRoot.str(o['name']);
    a.element = HardChallengeRoot.str(o['element']);
    a.image = HardChallengeRoot.str(o['image']);
    a.rarity = HardChallengeRoot.number(o['rarity'], 0);
    a.rank = HardChallengeRoot.number(o['rank'], 0);
    a.level = HardChallengeRoot.number(o['level'], 0);
    a.isPlus = HardChallengeRoot.bool(o['is_plus']);
    if (a.image.length === 0) {
      a.image = HardChallengeRoot.str(o['side_icon']);
    }
    return a;
  }

  private static number(v: Object, def: number): number {
    if (v === undefined || v === null) {
      return def;
    }
    const n: number = Number(v);
    return Number.isNaN(n) ? def : n;
  }

  private static str(v: Object): string {
    if (v === undefined || v === null) {
      return '';
    }
    return String(v);
  }

  /** 米哈游日期对象 {year,month,day,...} → "YYYY/MM/DD"；字符串原样返回 */
  private static dtStr(v: Object): string {
    if (v === undefined || v === null) {
      return '';
    }
    if (typeof v === 'string') {
      return String(v);
    }
    const o = v as Record<string, Object>;
    const y: number = Number(o['year'] ?? 0);
    const mo: number = Number(o['month'] ?? 0);
    const d: number = Number(o['day'] ?? 0);
    if (y <= 0) {
      return '';
    }
    return `${y}/${mo}/${d}`;
  }

  private static bool(v: Object): boolean {
    if (v === undefined || v === null) {
      return false;
    }
    return v === true || v === 1 || v === '1' || v === 'true';
  }

  /** best_avatar type → 标签（1=最强一击，2=最高总伤害；兼容字符串） */
  private static bestType(v: Object): string {
    if (v === undefined || v === null) {
      return '';
    }
    const n: number = Number(v);
    if (!Number.isNaN(n)) {
      return n === 1 ? 'oneAttack' : n === 2 ? 'allAttack' : '';
    }
    return String(v);
  }
}
