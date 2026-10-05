/** Versioned, lossless cultivation inputs. Unknown legacy progress is never inferred. */
export class CultivationSkillDraft {
  id: number = 0;
  groupId: number = 0;
  label: string = '';
  current: number = 1;
  target: number = 10;
}

export class CultivationDraft {
  version: number = 1;
  kind: string = 'avatar';
  itemId: number = 0;
  avatarId: number = 0;
  name: string = '';
  icon: string = '';
  sourceUid: string = '';
  sourceAt: number = 0;
  current: number = 1;
  target: number = 90;
  promote: number = 0;
  targetPromote: number = 6;
  maxLevel: number = 100;
  elementAttrId: number = 0;
  skills: CultivationSkillDraft[] = [];
  /** UI-only identity and optimistic concurrency token, excluded from persisted JSON. */
  entryId: number = 0;
  expectedInput: string = '';

  static encode(draft: CultivationDraft): string {
    const copy: CultivationDraft = CultivationDraft.copy(draft);
    copy.entryId = 0;
    copy.expectedInput = '';
    CultivationDraft.validate(copy);
    const encoded: string = JSON.stringify(copy);
    if (encoded.length > 65536) { throw new Error('养成输入快照过大，未保存'); }
    return encoded;
  }

  static decode(text: string): CultivationDraft {
    if (text.length > 65536) { throw new Error('养成输入快照过大，未读取'); }
    if (text.length === 0) {
      throw new Error('旧计划未保存完整输入，需要重新确认当前进度与目标；原材料仍保留');
    }
    const raw: CultivationDraft = JSON.parse(text) as CultivationDraft;
    CultivationDraft.validate(raw);
    return CultivationDraft.copy(raw);
  }

  static copy(value: CultivationDraft): CultivationDraft {
    const result: CultivationDraft = new CultivationDraft();
    result.version = value.version;
    result.kind = value.kind;
    result.itemId = value.itemId;
    result.avatarId = value.avatarId;
    result.name = value.name;
    result.icon = value.icon;
    result.sourceUid = value.sourceUid;
    result.sourceAt = value.sourceAt;
    result.current = value.current;
    result.target = value.target;
    result.promote = value.promote;
    result.targetPromote = value.targetPromote;
    result.maxLevel = value.maxLevel;
    result.elementAttrId = value.elementAttrId;
    result.entryId = value.entryId ?? 0;
    result.expectedInput = value.expectedInput ?? '';
    result.skills = value.skills.map((skill: CultivationSkillDraft): CultivationSkillDraft => {
      const item: CultivationSkillDraft = new CultivationSkillDraft();
      item.id = skill.id; item.groupId = skill.groupId; item.label = skill.label;
      item.current = skill.current; item.target = skill.target;
      return item;
    });
    return result;
  }

  static promoteFor(level: number, maxLevel: number = 100): number {
    return Math.min(maxLevel === 70 ? 4 : 6, [20, 40, 50, 60, 70, 80].filter((value: number): boolean => value <= level).length);
  }

  static validate(draft: CultivationDraft): void {
    if (draft === null || typeof draft !== 'object' || draft.version !== 1
      || (draft.kind !== 'avatar' && draft.kind !== 'weapon')
      || !Number.isSafeInteger(draft.itemId) || draft.itemId <= 0
      || !Number.isSafeInteger(draft.avatarId) || draft.avatarId < 0
      || typeof draft.name !== 'string' || typeof draft.icon !== 'string'
      || typeof draft.sourceUid !== 'string' || !Number.isSafeInteger(draft.sourceAt) || draft.sourceAt < 0
      || [70, 90, 100].indexOf(draft.maxLevel) < 0 || !Array.isArray(draft.skills)) {
      throw new Error('养成输入不完整或版本不支持；原计划未修改');
    }
    CultivationDraft.level(draft.current, draft.maxLevel);
    CultivationDraft.level(draft.target, draft.maxLevel);
    // A refreshed current value may exceed the chosen target. The target remains unchanged.
    for (const value of [draft.promote, draft.targetPromote]) {
      if (!Number.isInteger(value) || value < 0 || value > (draft.maxLevel === 70 ? 4 : 6)) { throw new Error('突破阶段必须为 0–6'); }
    }
    const minimum: number = [20, 40, 50, 60, 70, 80].filter((value: number): boolean => value < draft.current).length;
    if (draft.promote < minimum || draft.promote > CultivationDraft.promoteFor(draft.current, draft.maxLevel)
      || draft.targetPromote < [20, 40, 50, 60, 70, 80].filter((value: number): boolean => value < draft.target).length
      || draft.targetPromote > CultivationDraft.promoteFor(draft.target, draft.maxLevel)) {
      throw new Error('等级与突破阶段不匹配，请确认突破关口的当前状态');
    }
    const ids: Set<number> = new Set<number>();
    for (const skill of draft.skills) {
      if (!Number.isSafeInteger(skill.id) || skill.id <= 0 || ids.has(skill.id)
        || !Number.isSafeInteger(skill.groupId) || skill.groupId <= 0 || typeof skill.label !== 'string') {
        throw new Error('天赋映射不完整或重复，未保存');
      }
      ids.add(skill.id);
      CultivationDraft.level(skill.current, 10); CultivationDraft.level(skill.target, 10);
    }
    if (draft.kind === 'avatar' && draft.skills.length !== 3) {
      throw new Error('需要准确的三项可升级天赋输入，未保存不完整计划');
    }
    if (draft.kind === 'weapon' && draft.skills.length !== 0) { throw new Error('武器计划不能包含角色天赋'); }
  }

  private static level(value: number, max: number): void {
    if (!Number.isInteger(value) || value < 1 || value > max) { throw new Error(`等级必须为 1–${max} 的整数`); }
  }
}
