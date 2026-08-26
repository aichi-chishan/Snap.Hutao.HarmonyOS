/**
 * Calculate.ets
 * 养成计算（e20200928calculate 接口）模型。
 * avatar/list → 角色清单（等级/元素/突破/技能等级）；
 * batch_compute → 养成材料消耗（items: avatar_consume/weapon_consume/skills_consume）。
 */

/** 单个素材 */
export class CalItem {
  id: number = 0;
  name: string = '';
  icon: string = '';
  num: number = 0;
  level: number = 0;
  lackNum: number = 0;
}

/** 技能消耗 */
export class CalSkillConsume {
  /** 技能 id（skill_info.id） */
  skillId: number = 0;
  levelCurrent: number = 0;
  levelTarget: number = 0;
  consumeList: CalItem[] = [];
}

/** 单角色消耗 */
export class CalAvatarConsume {
  avatarConsume: CalItem[] = [];
  avatarSkillConsume: CalItem[] = [];
  weaponConsume: CalItem[] = [];
  skillsConsume: CalSkillConsume[] = [];
}

/** batch_compute 响应 */
export class CalBatchResult {
  items: CalAvatarConsume[] = [];
  overallConsume: CalItem[] = [];
  hasUserInfo: boolean = false;

  static fromJson(obj: Object): CalBatchResult {
    const o = obj as Record<string, Object>;
    const r: CalBatchResult = new CalBatchResult();
    const items = o['items'] as Array<Object>;
    if (items !== undefined && items !== null) {
      for (let i = 0; i < items.length; i++) {
        const it = items[i] as Record<string, Object>;
        const c: CalAvatarConsume = new CalAvatarConsume();
        c.avatarConsume = CalBatchResult.parseItems(it['avatar_consume']);
        c.avatarSkillConsume = CalBatchResult.parseItems(it['avatar_skill_consume']);
        c.weaponConsume = CalBatchResult.parseItems(it['weapon_consume']);
        const skills = it['skills_consume'] as Array<Object>;
        if (skills !== undefined && skills !== null) {
          for (let j = 0; j < skills.length; j++) {
            const s = skills[j] as Record<string, Object>;
            const sk: CalSkillConsume = new CalSkillConsume();
            const info = s['skill_info'] as Record<string, Object>;
            if (info !== undefined && info !== null) {
              sk.skillId = CalBatchResult.num(info['id']);
              sk.levelCurrent = CalBatchResult.num(info['level_current']);
              sk.levelTarget = CalBatchResult.num(info['level_target']);
            }
            sk.consumeList = CalBatchResult.parseItems(s['consume_list']);
            c.skillsConsume.push(sk);
          }
        }
        r.items.push(c);
      }
    }
    r.overallConsume = CalBatchResult.parseItems(o['overall_consume']);
    r.hasUserInfo = CalBatchResult.bool(o['has_user_info']);
    return r;
  }

  private static parseItems(obj: Object): CalItem[] {
    const list: CalItem[] = [];
    if (obj === undefined || obj === null) {
      return list;
    }
    const arr = obj as Array<Object>;
    for (let i = 0; i < arr.length; i++) {
      const o = arr[i] as Record<string, Object>;
      const item: CalItem = new CalItem();
      item.id = CalBatchResult.num(o['id']);
      item.name = CalBatchResult.str(o['name']);
      item.icon = CalBatchResult.str(o['icon_url'] ?? o['icon']);
      item.num = CalBatchResult.num(o['num']);
      item.level = CalBatchResult.num(o['level']);
      item.lackNum = CalBatchResult.num(o['lack_num']);
      list.push(item);
    }
    return list;
  }

  private static num(v: Object, def: number = 0): number {
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

/** 角色清单条目（sync/avatar/list 或本地模拟） */
export class CalAvatarListItem {
  avatarId: number = 0;
  name: string = '';
  elementAttrId: number = 0;
  element: string = '';
  image: string = '';
  rarity: number = 0;
  avatarLevel: number = 0;
  promoteLevel: number = 0;
  weaponCatId: number = 0;
}
