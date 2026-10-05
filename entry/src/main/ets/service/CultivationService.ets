import { AvatarSkillReference } from '../model/AvatarSkillReference';
import { CultivationDraft, CultivationSkillDraft } from '../model/CultivationDraft';
import { CalAvatarDelta, CalSkillDelta, CalWeaponDelta, CalculateService } from './CalculateService';
import { CharacterListItem } from '../model/CharacterData';
import { OfflineCultivationService } from './OfflineCultivationService';
import { SkillLevelService } from './SkillLevelService';
import { WikiMetaService, WikiAvatarMeta, WikiWeaponMeta } from './WikiMetaService';
import { CultivationPreparedEntry, CultivationRepo, CultivationSaveReport } from '../data/repo/CultivationRepo';
import { CalBatchResult } from '../model/Calculate';

/** Shared by character, wiki and saved-plan editors. No network operation mutates saved plans. */
export class CultivationService {
  static elementId(element: string): number {
    const ids: Record<string, number> = { 'Pyro': 1, 'Hydro': 2, 'Electro': 4, 'Dendro': 6, 'Cryo': 7, 'Anemo': 8, 'Geo': 9 };
    return ids[element] ?? 0;
  }

  static async fromCharacters(uid: string, characters: CharacterListItem[], weaponOnly: boolean = false, allowManualWeapon: boolean = true): Promise<CultivationDraft[]> {
    if (uid.length === 0 || characters.length === 0) { throw new Error('请先选择角色与 UID'); }
    const promotes: Map<number, number> = weaponOnly ? new Map<number, number>() : await CalculateService.getInstance().fetchPromoteLevels(uid);
    const drafts: CultivationDraft[] = [];
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    for (const character of characters) {
      if ((!weaponOnly && !promotes.has(character.id)) || character.level < 1) { throw new Error(`${character.name} 的当前进度不完整`); }
      const delta: CalAvatarDelta = new CalAvatarDelta();
      delta.avatarId = character.id; delta.levelCurrent = character.level;
      delta.avatarPromoteLevel = promotes.get(character.id) ?? -1;
      let manuallyConfirmWeapon: boolean = false;
      try {
        await CalculateService.getInstance().fillSyncedDetails(uid, delta, weaponOnly ? 0 : 10, weaponOnly ? 90 : 0);
      } catch (e) {
        if (!weaponOnly || !allowManualWeapon || character.weapon.id <= 0 || character.weapon.level < 1) { throw new Error(e instanceof Error ? e.message : '当前进度同步失败'); }
        const weapon: CalWeaponDelta = new CalWeaponDelta();
        weapon.id = character.weapon.id; weapon.levelCurrent = character.weapon.level; weapon.weaponPromoteLevel = -1;
        delta.weapon = weapon; manuallyConfirmWeapon = true;
      }
      const draft: CultivationDraft = new CultivationDraft();
      draft.avatarId = character.id; draft.itemId = character.id;
      draft.sourceUid = uid; draft.sourceAt = manuallyConfirmWeapon ? 0 : Date.now();
      draft.elementAttrId = CultivationService.elementId(character.element);
      if (weaponOnly) {
        const weapon: CalWeaponDelta | undefined = delta.weapon;
        if (weapon === undefined || weapon.id !== character.weapon.id) { throw new Error(`${character.name} 的当前武器未准确同步`); }
        const meta: WikiWeaponMeta | undefined = weapons.find((item: WikiWeaponMeta): boolean => item.id === weapon.id);
        if (meta === undefined) { throw new Error('缺少武器元数据'); }
        draft.kind = 'weapon'; draft.itemId = weapon.id; draft.name = meta.name; draft.icon = meta.icon;
        draft.current = weapon.levelCurrent; draft.promote = weapon.weaponPromoteLevel;
        draft.maxLevel = meta.rankLevel <= 2 ? 70 : 90; draft.target = draft.maxLevel;
        draft.targetPromote = CultivationDraft.promoteFor(draft.target, draft.maxLevel);
      } else {
        draft.name = character.name; draft.icon = WikiMetaService.iconOfAvatar(character.id) || character.icon;
        draft.current = character.level; draft.promote = delta.avatarPromoteLevel;
        draft.target = Math.max(character.level, 90); draft.targetPromote = CultivationDraft.promoteFor(draft.target, draft.maxLevel);
        for (const skill of delta.skills) {
          const input: CultivationSkillDraft = new CultivationSkillDraft();
          input.id = skill.id; input.groupId = skill.id;
          const reference = SkillLevelService.referenceSkills(character.id).find((item: AvatarSkillReference): boolean => item.groupId === skill.id);
          input.label = reference?.kind === 'A' ? '普通攻击' : reference?.kind === 'E' ? '元素战技'
            : reference?.kind === 'Q' ? '元素爆发' : `天赋 ${skill.id}`;
          input.current = skill.levelCurrent; input.target = skill.levelTarget;
          draft.skills.push(input);
        }
      }
      if (!manuallyConfirmWeapon) { CultivationDraft.validate(draft); }
      drafts.push(draft);
    }
    return drafts;
  }

  static async offlineAvatar(id: number): Promise<CultivationDraft> {
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    const avatar: WikiAvatarMeta | undefined = avatars.find((item: WikiAvatarMeta): boolean => item.id === id);
    if (avatar === undefined) { throw new Error('角色元数据不可用'); }
    const draft: CultivationDraft = new CultivationDraft();
    draft.itemId = id; draft.avatarId = id; draft.name = avatar.name; draft.icon = avatar.icon;
    const skills = SkillLevelService.referenceSkills(id);
    for (const skill of skills) {
      const input: CultivationSkillDraft = new CultivationSkillDraft();
      input.id = skill.groupId; input.groupId = skill.groupId;
      input.label = skill.kind === 'A' ? '普通攻击' : skill.kind === 'E' ? '元素战技' : '元素爆发';
      draft.skills.push(input);
    }
    CultivationDraft.validate(draft);
    return draft;
  }

  static async offlineWeapon(id: number): Promise<CultivationDraft> {
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    const weapon: WikiWeaponMeta | undefined = weapons.find((item: WikiWeaponMeta): boolean => item.id === id);
    if (weapon === undefined) { throw new Error('武器元数据不可用'); }
    const draft: CultivationDraft = new CultivationDraft();
    draft.kind = 'weapon'; draft.itemId = id; draft.name = weapon.name; draft.icon = weapon.icon;
    draft.maxLevel = weapon.rankLevel <= 2 ? 70 : 90; draft.target = draft.maxLevel;
    draft.targetPromote = CultivationDraft.promoteFor(draft.target, draft.maxLevel);
    return draft;
  }

  /** Strict ID merge: changed equipment or missing talents aborts the whole refresh. Targets never move. */
  static mergeCurrent(saved: CultivationDraft, current: CultivationDraft): CultivationDraft {
    CultivationDraft.validate(saved); CultivationDraft.validate(current);
    if (saved.itemId !== current.itemId || saved.kind !== current.kind
      || (saved.sourceUid.length > 0 && saved.sourceUid !== current.sourceUid)) {
      throw new Error('同步角色、装备或 UID 与原计划不符；原目标保持不变');
    }
    const result: CultivationDraft = CultivationDraft.copy(saved);
    result.current = current.current; result.promote = current.promote;
    result.sourceUid = current.sourceUid; result.sourceAt = current.sourceAt;
    for (const skill of result.skills) {
      const latest: CultivationSkillDraft | undefined = current.skills.find((item: CultivationSkillDraft): boolean => item.id === skill.id);
      if (latest === undefined) { throw new Error('同步天赋不完整或映射已变更，未覆盖原计划'); }
      skill.current = latest.current;
    }
    CultivationDraft.validate(result);
    return result;
  }

  static calculatorInputs(drafts: CultivationDraft[], uid: string): CalAvatarDelta[] {
    const deltas: CalAvatarDelta[] = [];
    for (const draft of drafts) {
      CultivationDraft.validate(draft);
      if (draft.kind !== 'avatar' || draft.sourceUid !== uid || uid.length === 0) { continue; }
      const delta: CalAvatarDelta = new CalAvatarDelta();
      delta.avatarId = draft.avatarId; delta.levelCurrent = draft.current;
      delta.levelTarget = Math.max(draft.current, draft.target); delta.avatarPromoteLevel = draft.promote;
      delta.elementAttrId = draft.elementAttrId;
      for (const input of draft.skills) {
        const skill: CalSkillDelta = new CalSkillDelta();
        skill.id = input.groupId; skill.levelCurrent = input.current; skill.levelTarget = Math.max(input.current, input.target);
        delta.skills.push(skill);
      }
      const weapon: CultivationDraft | undefined = drafts.find((item: CultivationDraft): boolean =>
        item.kind === 'weapon' && item.avatarId === draft.avatarId && item.sourceUid === uid);
      if (weapon !== undefined) {
        const target: CalWeaponDelta = new CalWeaponDelta();
        target.id = weapon.itemId; target.levelCurrent = weapon.current;
        target.levelTarget = Math.max(weapon.current, weapon.target); target.weaponPromoteLevel = weapon.promote;
        delta.weapon = target;
      }
      deltas.push(delta);
    }
    if (deltas.length === 0) { throw new Error('当前项目没有此 UID 的完整角色计划；请先从角色页同步并保存目标'); }
    return deltas;
  }

  static async calculate(drafts: CultivationDraft[]): Promise<CultivationPreparedEntry[]> {
    const results: CultivationPreparedEntry[] = [];
    for (const draft of drafts) {
      CultivationDraft.validate(draft);
      const entry: CultivationPreparedEntry = new CultivationPreparedEntry();
      entry.draft = CultivationDraft.copy(draft);
      if (draft.kind === 'weapon') {
        const weapon: CalWeaponDelta = new CalWeaponDelta();
        weapon.id = draft.itemId; weapon.levelCurrent = draft.current;
        weapon.levelTarget = Math.max(draft.current, draft.target);
        weapon.weaponPromoteLevel = draft.promote;
        weapon.weaponTargetPromoteLevel = Math.max(draft.promote, draft.targetPromote);
        const metas: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
        const meta: WikiWeaponMeta | undefined = metas.find((item: WikiWeaponMeta): boolean => item.id === draft.itemId);
        if (meta === undefined) { throw new Error('武器元数据不可用'); }
        entry.items = OfflineCultivationService.weaponItems(weapon, meta);
        const materials = await WikiMetaService.getMaterials();
        for (const item of entry.items) { item.name = materials.get(item.id)?.n ?? `材料 ${item.id}`; item.icon = materials.get(item.id)?.i ?? ''; }
      } else {
        const delta: CalAvatarDelta = new CalAvatarDelta();
        delta.avatarId = draft.itemId; delta.levelCurrent = draft.current;
        delta.levelTarget = Math.max(draft.current, draft.target); delta.elementAttrId = draft.elementAttrId;
        delta.avatarPromoteLevel = draft.promote;
        delta.avatarTargetPromoteLevel = Math.max(draft.promote, draft.targetPromote);
        for (const input of draft.skills) {
          const skill: CalSkillDelta = new CalSkillDelta();
          skill.id = input.id; skill.levelCurrent = input.current; skill.levelTarget = Math.max(input.current, input.target);
          delta.skills.push(skill);
        }
        const result: CalBatchResult = await OfflineCultivationService.batchCompute([delta]);
        if (result.items.length !== 1) { throw new Error('材料结果不完整'); }
        entry.items = result.items[0].avatarConsume.concat(result.items[0].avatarSkillConsume);
      }
      results.push(entry);
    }
    return results;
  }

  static async save(projectId: number, prepared: CultivationPreparedEntry[], overwrite: boolean): Promise<CultivationSaveReport> {
    return CultivationRepo.saveDrafts(projectId, prepared, overwrite);
  }
}
