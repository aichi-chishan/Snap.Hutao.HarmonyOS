/**
 * RoleCombat.ets
 * 幻象真境剧诗/幽境危战（role_combat 接口）模型。
 * 对齐 Windows RoleCombat.cs：data[] + is_unlock + links。
 * data[] 每项：detail（rounds_data / backup_avatars / fight_statistics）+ stat + schedule + has_data。
 */

/** 每回合出战角色 */
export class RoleCombatAvatar {
  avatarId: number = 0;
  avatarType: number = 0;
  name: string = '';
  element: string = '';
  image: string = '';
  level: number = 0;
  rarity: number = 0;
}

/** 敌方怪物 */
export class RoleCombatEnemy {
  name: string = '';
  icon: string = '';
  level: number = 0;
}

/** 卡牌/祝福 */
export class RoleCombatBuff {
  id: number = 0;
  icon: string = '';
  name: string = '';
  desc: string = '';
  isEnhanced: boolean = false;
}

/** 单回合数据 */
export class RoleCombatRoundData {
  roundId: number = 0;
  avatars: RoleCombatAvatar[] = [];
  choiceCards: RoleCombatBuff[] = [];
  buffs: RoleCombatBuff[] = [];
  enemies: RoleCombatEnemy[] = [];
  isGetMedal: boolean = false;
  finishTime: number = 0;
}

/** 战斗统计（最大伤害/最快通关等，对齐 Windows RoleCombatFightStatistics） */
export class RoleCombatAvatarStat {
  /** 角色 id（avatar_id；用于本地元数据图标映射，对齐 Windows IdAvatarMap） */
  avatarId: number = 0;
  /** 角色图标名（avatar_icon） */
  icon: string = '';
  /** 数值（value） */
  value: string = '';
}

/** 战斗统计（最大伤害/最快通关等，对齐 Windows RoleCombatFightStatistics） */
export class RoleCombatFightStatistics {
  /** 最多击破（max_defeat_avatar） */
  maxDefeat: RoleCombatAvatarStat = new RoleCombatAvatarStat();
  /** 最强一击（max_damage_avatar） */
  maxDamage: RoleCombatAvatarStat = new RoleCombatAvatarStat();
  /** 最多承伤（max_take_damage_avatar） */
  maxTakeDamage: RoleCombatAvatarStat = new RoleCombatAvatarStat();
  /** 消弭「幻剧之花」（total_coin_consumed） */
  totalCoinConsumed: RoleCombatAvatarStat = new RoleCombatAvatarStat();
  /** 最快演出角色列表（shortest_avatar_list：avatar_icon + value） */
  shortestAvatarList: RoleCombatAvatarStat[] = [];
  /** 演出总时长（秒） */
  totalUseTime: number = 0;
  /** 是否展示战斗统计（is_show_battle_stats） */
  isShowBattleStats: boolean = false;
}

/** 详情 */
export class RoleCombatDetail {
  roundsData: RoleCombatRoundData[] = [];
  backupAvatars: RoleCombatAvatar[] = [];
  fightStatistics: RoleCombatFightStatistics = new RoleCombatFightStatistics();
}

/** 难度/奖章 */
export class RoleCombatStat {
  difficultyId: number = 0;
  /** 圣牌等级（heraldry：III/II/I） */
  heraldry: number = 0;
  maxRoundId: number = 0;
  medalNumber: number = 0;
  coinNumber: number = 0;
  /** 助演次数（avatar_bonus_num） */
  avatarBonusNumber: number = 0;
  /** 场外声援（rent_cnt） */
  rentCount: number = 0;
  /** 塔罗完成数（tarot_finished_cnt） */
  tarotFinishedCount: number = 0;
  getMedalRoundList: number[] = [];
}

/** 周期 */
export class RoleCombatSchedule {
  scheduleType: number = 0;
  scheduleId: number = 0;
  startTime: number = 0;
  endTime: number = 0;
  /** 'yyyy-MM-dd HH:mm:ss'（服务端 ISO） */
  startDateTime: string = '';
  endDateTime: string = '';
}

/** data[] 元素 */
export class RoleCombatDataItem {
  detail: RoleCombatDetail = new RoleCombatDetail();
  stat: RoleCombatStat = new RoleCombatStat();
  schedule: RoleCombatSchedule = new RoleCombatSchedule();
  hasData: boolean = false;
  hasDetailData: boolean = false;
}

/** 顶层 */
export class RoleCombatRoot {
  data: RoleCombatDataItem[] = [];
  isUnlock: boolean = false;

  static fromJson(obj: Object): RoleCombatRoot {
    const root: RoleCombatRoot = new RoleCombatRoot();
    const wrapper = obj as Record<string, Object>;
    root.isUnlock = RoleCombatRoot.bool(wrapper['is_unlock']);
    const list = wrapper['data'] as Array<Object>;
    if (list !== undefined && list !== null) {
      for (let i = 0; i < list.length; i++) {
        const item: RoleCombatDataItem = RoleCombatRoot.parseDataItem(list[i]);
        root.data.push(item);
      }
    }
    return root;
  }

  private static parseDataItem(obj: Object): RoleCombatDataItem {
    const o = obj as Record<string, Object>;
    const item: RoleCombatDataItem = new RoleCombatDataItem();
    item.hasData = RoleCombatRoot.bool(o['has_data']);
    item.hasDetailData = RoleCombatRoot.bool(o['has_detail_data']);
    const detail = o['detail'] as Record<string, Object>;
    if (detail !== undefined && detail !== null) {
      const rounds = detail['rounds_data'] as Array<Object>;
      if (rounds !== undefined && rounds !== null) {
        for (let i = 0; i < rounds.length; i++) {
          item.detail.roundsData.push(RoleCombatRoot.parseRound(rounds[i]));
        }
      }
      const backups = detail['backup_avatars'] as Array<Object>;
      if (backups !== undefined && backups !== null) {
        for (let i = 0; i < backups.length; i++) {
          item.detail.backupAvatars.push(RoleCombatRoot.parseAvatar(backups[i]));
        }
      }
      const fight = detail['fight_statisic'] as Record<string, Object>;
      if (fight !== undefined && fight !== null) {
        item.detail.fightStatistics = RoleCombatRoot.parseFight(fight);
      }
    }
    const stat = o['stat'] as Record<string, Object>;
    if (stat !== undefined && stat !== null) {
      item.stat.difficultyId = RoleCombatRoot.number(stat['difficulty_id'], 0);
      item.stat.heraldry = RoleCombatRoot.number(stat['heraldry'], 0);
      item.stat.maxRoundId = RoleCombatRoot.number(stat['max_round_id'], 0);
      item.stat.medalNumber = RoleCombatRoot.number(stat['medal_num'], 0);
      item.stat.coinNumber = RoleCombatRoot.number(stat['coin_num'], 0);
      item.stat.avatarBonusNumber = RoleCombatRoot.number(stat['avatar_bonus_num'], 0);
      item.stat.rentCount = RoleCombatRoot.number(stat['rent_cnt'], 0);
      item.stat.tarotFinishedCount = RoleCombatRoot.number(stat['tarot_finished_cnt'], 0);
      const medals = stat['get_medal_round_list'] as Array<Object>;
      if (medals !== undefined && medals !== null) {
        for (let i = 0; i < medals.length; i++) {
          item.stat.getMedalRoundList.push(Number(medals[i]) || 0);
        }
      }
    }
    const schedule = o['schedule'] as Record<string, Object>;
    if (schedule !== undefined && schedule !== null) {
      item.schedule.scheduleType = RoleCombatRoot.number(schedule['schedule_type'], 0);
      item.schedule.scheduleId = RoleCombatRoot.number(schedule['schedule_id'], 0);
      item.schedule.startTime = RoleCombatRoot.number(schedule['start_time'], 0);
      item.schedule.endTime = RoleCombatRoot.number(schedule['end_time'], 0);
      item.schedule.startDateTime = RoleCombatRoot.str(schedule['start_date_time']);
      item.schedule.endDateTime = RoleCombatRoot.str(schedule['end_date_time']);
    }
    return item;
  }

  private static parseRound(obj: Object): RoleCombatRoundData {
    const o = obj as Record<string, Object>;
    const round: RoleCombatRoundData = new RoleCombatRoundData();
    round.roundId = RoleCombatRoot.number(o['round_id'], 0);
    round.isGetMedal = RoleCombatRoot.bool(o['is_get_medal']);
    round.finishTime = RoleCombatRoot.number(o['finish_time'], 0);
    const avatars = o['avatars'] as Array<Object>;
    if (avatars !== undefined && avatars !== null) {
      for (let i = 0; i < avatars.length; i++) {
        round.avatars.push(RoleCombatRoot.parseAvatar(avatars[i]));
      }
    }
    const choices = o['choice_cards'] as Array<Object>;
    if (choices !== undefined && choices !== null) {
      const cards = choices[0] as Record<string, Object>;
      if (cards !== undefined && cards !== null) {
        round.choiceCards.push(RoleCombatRoot.parseBuff(cards));
      }
    }
    const buffs = o['buffs'] as Array<Object>;
    if (buffs !== undefined && buffs !== null) {
      for (let i = 0; i < buffs.length; i++) {
        round.buffs.push(RoleCombatRoot.parseBuff(buffs[i]));
      }
    }
    const enemies = o['enemies'] as Array<Object>;
    if (enemies !== undefined && enemies !== null) {
      for (let i = 0; i < enemies.length; i++) {
        round.enemies.push(RoleCombatRoot.parseEnemy(enemies[i]));
      }
    }
    return round;
  }

  private static parseAvatar(obj: Object): RoleCombatAvatar {
    const o = obj as Record<string, Object>;
    const a: RoleCombatAvatar = new RoleCombatAvatar();
    a.avatarId = RoleCombatRoot.number(o['avatar_id'], 0);
    a.avatarType = RoleCombatRoot.number(o['avatar_type'], 0);
    a.name = RoleCombatRoot.str(o['name']);
    a.element = RoleCombatRoot.str(o['element']);
    a.image = RoleCombatRoot.str(o['image']);
    a.level = RoleCombatRoot.number(o['level'], 0);
    a.rarity = RoleCombatRoot.number(o['rarity'], 0);
    return a;
  }

  private static parseEnemy(obj: Object): RoleCombatEnemy {
    const o = obj as Record<string, Object>;
    const e: RoleCombatEnemy = new RoleCombatEnemy();
    e.name = RoleCombatRoot.str(o['name']);
    e.icon = RoleCombatRoot.str(o['icon']);
    e.level = RoleCombatRoot.number(o['level'], 0);
    return e;
  }

  private static parseBuff(obj: Object): RoleCombatBuff {
    const o = obj as Record<string, Object>;
    const b: RoleCombatBuff = new RoleCombatBuff();
    b.id = RoleCombatRoot.number(o['id'], 0);
    b.icon = RoleCombatRoot.str(o['icon']);
    b.name = RoleCombatRoot.str(o['name']);
    b.desc = RoleCombatRoot.str(o['desc']);
    b.isEnhanced = RoleCombatRoot.bool(o['is_enhanced']);
    return b;
  }

  private static parseFight(obj: Object): RoleCombatFightStatistics {
    const o = obj as Record<string, Object>;
    const f: RoleCombatFightStatistics = new RoleCombatFightStatistics();
    f.totalUseTime = RoleCombatRoot.number(o['total_use_time'], 0);
    f.isShowBattleStats = RoleCombatRoot.bool(o['is_show_battle_stats']);
    f.maxDefeat = RoleCombatRoot.parseAvatarStat(o['max_defeat_avatar']);
    f.maxDamage = RoleCombatRoot.parseAvatarStat(o['max_damage_avatar']);
    f.maxTakeDamage = RoleCombatRoot.parseAvatarStat(o['max_take_damage_avatar']);
    f.totalCoinConsumed = RoleCombatRoot.parseAvatarStat(o['total_coin_consumed']);
    const shortest = o['shortest_avatar_list'] as Array<Object>;
    if (shortest !== undefined && shortest !== null) {
      for (let i = 0; i < shortest.length; i++) {
        f.shortestAvatarList.push(RoleCombatRoot.parseAvatarStat(shortest[i]));
      }
    }
    return f;
  }

  private static parseAvatarStat(obj: Object): RoleCombatAvatarStat {
    const s: RoleCombatAvatarStat = new RoleCombatAvatarStat();
    if (obj === undefined || obj === null) {
      return s;
    }
    const o = obj as Record<string, Object>;
    s.avatarId = RoleCombatRoot.number(o['avatar_id'], 0);
    s.icon = RoleCombatRoot.str(o['avatar_icon']);
    s.value = RoleCombatRoot.str(o['value']);
    return s;
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

  private static bool(v: Object): boolean {
    if (v === undefined || v === null) {
      return false;
    }
    return v === true || v === 1 || v === '1' || v === 'true';
  }
}
