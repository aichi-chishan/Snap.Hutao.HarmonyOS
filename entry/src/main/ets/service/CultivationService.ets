import { AvatarSkillReference } from '../model/AvatarSkillReference';
import { CultivationBatchField, CultivationBatchTargets, CultivationDraft, CultivationSkillDraft } from '../model/CultivationDraft';
import { CalAvatarDelta, CalSkillDelta, CalWeaponDelta, CalculateInventoryCatalog, CalculateService } from './CalculateService';
import { CharacterDetail, CharacterListItem } from '../model/CharacterData';
import { CharacterService } from './CharacterService';
import { OfflineCultivationService } from './OfflineCultivationService';
import { ResolvedAvatarSkill, SkillLevelService } from './SkillLevelService';
import { WikiMetaService, WikiAvatarMeta, WikiWeaponMeta } from './WikiMetaService';
import { CultivateEntry, CultivationPreparedEntry, CultivationRepo, CultivationSaveReport } from '../data/repo/CultivationRepo';
import { CalBatchResult } from '../model/Calculate';

export class CultivationProgressUpdate {
  entries: CultivationPreparedEntry[] = [];
  skipped: number = 0;
}

export class CultivationEquipmentDrafts {
  drafts: CultivationDraft[] = [];
  skippedNames: string[] = [];
}

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

  /** One verified avatar and its current weapon per role. Batch callers can skip incomplete pairs. */
  static async fromEquippedCharacters(uid: string, characters: CharacterListItem[], skipIncomplete: boolean,
    isCurrent: () => boolean): Promise<CultivationEquipmentDrafts> {
    if (!/^\d{9,10}$/.test(uid) || characters.length === 0) { throw new Error('请先选择角色与 UID'); }
    const byId: Map<number, CharacterListItem> = new Map<number, CharacterListItem>();
    for (const character of characters) { byId.set(character.id, character); }
    const details: Map<number, CharacterDetail> = await CultivationService.fetchProgressDetails(uid, Array.from(byId.keys()), isCurrent);
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    let promotes: Map<number, number> = new Map<number, number>();
    if (Array.from(details.values()).some((detail: CharacterDetail): boolean => detail.promoteLevel < 0)) {
      if (!isCurrent()) { throw new Error('账号已切换，请重新选择角色'); }
      promotes = await CalculateService.getInstance().fetchPromoteLevels(uid);
    }

    const result: CultivationEquipmentDrafts = new CultivationEquipmentDrafts();
    for (const character of byId.values()) {
      try {
        const detail: CharacterDetail | undefined = details.get(character.id);
        const avatar: WikiAvatarMeta | undefined = avatars.find((item: WikiAvatarMeta): boolean => item.id === character.id);
        if (detail === undefined || avatar === undefined || avatar.cultivationItems.length < 6) {
          throw new Error('角色进度或养成元数据不完整');
        }
        if (detail.weapon.equipmentState !== 'equipped' || detail.weapon.id <= 0 ||
          (character.weapon.id > 0 && detail.weapon.id !== character.weapon.id)) {
          throw new Error('当前装备武器未同步或已变化');
        }
        const weapon: WikiWeaponMeta | undefined = weapons.find((item: WikiWeaponMeta): boolean => item.id === detail.weapon.id);
        if (weapon === undefined || weapon.rankLevel < 1) { throw new Error('武器养成元数据不可用'); }
        const promote: number = detail.promoteLevel >= 0 ? detail.promoteLevel : (promotes.get(detail.id) ?? -1);
        const pair: CultivationDraft[] = CultivationService.equipmentDrafts(uid, detail, avatar, weapon, promote);
        for (const draft of pair) { result.drafts.push(draft); }
      } catch (e) {
        if (!skipIncomplete) { throw new Error(`${character.name}：${(e as Error).message}`); }
        result.skippedNames.push(character.name || String(character.id));
      }
    }
    return result;
  }

  private static equipmentDrafts(uid: string, detail: CharacterDetail, avatar: WikiAvatarMeta, weapon: WikiWeaponMeta,
    avatarPromote: number): CultivationDraft[] {
    const role: CultivationDraft = new CultivationDraft();
    role.avatarId = detail.id; role.itemId = detail.id; role.name = avatar.name; role.icon = avatar.icon;
    role.sourceUid = uid; role.sourceAt = Date.now();
    role.current = detail.level; role.promote = avatarPromote; role.target = Math.max(90, role.current);
    role.targetPromote = CultivationDraft.promoteFor(role.target, role.maxLevel);
    role.elementAttrId = CultivationService.elementId(detail.element);
    const skills: ResolvedAvatarSkill[] = SkillLevelService.resolve(detail);
    const kinds: string[] = ['A', 'E', 'Q'];
    const labels: string[] = ['普通攻击', '元素战技', '元素爆发'];
    for (let i: number = 0; i < kinds.length; i++) {
      const resolved: ResolvedAvatarSkill | undefined = skills.find((skill: ResolvedAvatarSkill): boolean => skill.kind === kinds[i]);
      if (resolved === undefined || resolved.baseLevel < 1) { throw new Error('三项天赋的基础等级不完整'); }
      const skill: CultivationSkillDraft = new CultivationSkillDraft();
      skill.id = resolved.groupId; skill.groupId = resolved.groupId; skill.label = labels[i];
      skill.current = resolved.baseLevel;
      role.skills.push(skill);
    }

    const equipped: CultivationDraft = new CultivationDraft();
    equipped.kind = 'weapon'; equipped.avatarId = detail.id; equipped.itemId = weapon.id;
    equipped.name = weapon.name; equipped.icon = weapon.icon; equipped.sourceUid = uid; equipped.sourceAt = role.sourceAt;
    equipped.current = detail.weapon.level; equipped.promote = detail.weapon.promoteLevel;
    equipped.maxLevel = weapon.rankLevel <= 2 ? 70 : 90; equipped.target = equipped.maxLevel;
    equipped.targetPromote = CultivationDraft.promoteFor(equipped.target, equipped.maxLevel);
    CultivationDraft.validate(role);
    CultivationDraft.validate(equipped);
    return [role, equipped];
  }

  static applyBatchTargets(drafts: CultivationDraft[], targets: CultivationBatchTargets): CultivationDraft[] {
    CultivationBatchTargets.validate(targets);
    return drafts.map((draft: CultivationDraft): CultivationDraft => {
      const result: CultivationDraft = CultivationDraft.copy(draft);
      if (result.kind === 'weapon') {
        result.target = Math.min(result.maxLevel, targets.levels[CultivationBatchField.WeaponLevel]);
      } else {
        result.target = targets.levels[CultivationBatchField.AvatarLevel];
        const references: AvatarSkillReference[] = SkillLevelService.referenceSkills(result.avatarId);
        for (const skill of result.skills) {
          const reference: AvatarSkillReference | undefined = references.find((item: AvatarSkillReference): boolean => item.groupId === skill.groupId);
          if (reference === undefined) { throw new Error(`${result.name} 的天赋映射已变更`); }
          if (reference.kind === 'A') { skill.target = targets.levels[CultivationBatchField.SkillA]; }
          else if (reference.kind === 'E') { skill.target = targets.levels[CultivationBatchField.SkillE]; }
          else if (reference.kind === 'Q') { skill.target = targets.levels[CultivationBatchField.SkillQ]; }
          else { throw new Error(`${result.name} 的天赋类型未知`); }
        }
      }
      result.targetPromote = CultivationDraft.promoteFor(result.target, result.maxLevel);
      CultivationDraft.validate(result);
      return result;
    });
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

  /** Refresh current progress for the project's avatar entries from the game record. */
  static async prepareProjectProgress(uid: string, entries: CultivateEntry[]): Promise<CultivationProgressUpdate> {
    if (!/^\d{9,10}$/.test(uid)) { throw new Error('请先登录并选择游戏 UID'); }
    const update: CultivationProgressUpdate = new CultivationProgressUpdate();
    const saved: CultivationDraft[] = [];
    const ids: Set<number> = new Set<number>();
    for (const entry of entries) {
      if (entry.avatarId < 10000000) { continue; }
      try {
        const draft: CultivationDraft = CultivationDraft.decode(entry.inputJson);
        if (draft.kind !== 'avatar' || draft.itemId !== entry.avatarId || draft.avatarId !== entry.avatarId
          || (draft.sourceUid.length > 0 && draft.sourceUid !== uid)) {
          update.skipped++;
          continue;
        }
        draft.entryId = entry.id;
        draft.expectedInput = entry.inputJson;
        saved.push(draft);
        ids.add(draft.avatarId);
      } catch (e) { update.skipped++; }
    }
    const details: Map<number, CharacterDetail> = await CultivationService.fetchProgressDetails(uid, Array.from(ids));
    const changed: CultivationDraft[] = [];
    for (const draft of saved) {
      const detail: CharacterDetail | undefined = details.get(draft.avatarId);
      const next: CultivationDraft | undefined = detail !== undefined
        ? CultivationService.progressFromDetail(draft, detail, uid) : undefined;
      if (next === undefined) { update.skipped++; }
      else { changed.push(next); }
    }
    update.entries = await CultivationService.calculate(changed);
    return update;
  }

  private static async fetchProgressDetails(uid: string, ids: number[], isCurrent?: () => boolean): Promise<Map<number, CharacterDetail>> {
    const details: Map<number, CharacterDetail> = new Map<number, CharacterDetail>();
    const duplicates: Set<number> = new Set<number>();
    for (let i: number = 0; i < ids.length; i += 20) {
      if (isCurrent !== undefined && !isCurrent()) { throw new Error('账号已切换，请重新选择角色'); }
      const batch: number[] = ids.slice(i, i + 20);
      for (const detail of await CharacterService.getInstance().fetchDetail(uid, batch)) {
        if (!batch.includes(detail.id) || duplicates.has(detail.id)) { continue; }
        if (details.has(detail.id)) { details.delete(detail.id); duplicates.add(detail.id); }
        else { details.set(detail.id, detail); }
      }
    }
    return details;
  }

  private static progressFromDetail(saved: CultivationDraft, detail: CharacterDetail, uid: string): CultivationDraft | undefined {
    const next: CultivationDraft = CultivationDraft.copy(saved);
    next.current = detail.level;
    next.promote = detail.promoteLevel;
    const skills: ResolvedAvatarSkill[] = SkillLevelService.resolve(detail);
    let changed: boolean = next.current !== saved.current || next.promote !== saved.promote;
    for (const input of next.skills) {
      const skill: ResolvedAvatarSkill | undefined = skills.find((value: ResolvedAvatarSkill): boolean => value.groupId === input.groupId);
      if (skill === undefined || skill.baseLevel < 1) { return undefined; }
      changed = changed || input.current !== skill.baseLevel;
      input.current = skill.baseLevel;
    }
    if (!changed) { return undefined; }
    next.sourceUid = uid;
    next.sourceAt = Date.now();
    try { CultivationDraft.validate(next); } catch (e) { return undefined; }
    return next;
  }

  /** Use the calculator's available catalog so inventory sync also works with an empty project. */
  static async inventoryCalculatorInputs(catalog: CalculateInventoryCatalog): Promise<CalAvatarDelta[]> {
    const deltas: CalAvatarDelta[] = [];
    for (const avatar of await WikiMetaService.getAvatars()) {
      if (!catalog.avatarIds.includes(avatar.id) || avatar.cultivationItems.length < 6) { continue; }
      const skills: AvatarSkillReference[] = SkillLevelService.referenceSkills(avatar.id);
      if (skills.length !== 3) { continue; }
      const delta: CalAvatarDelta = new CalAvatarDelta();
      delta.avatarId = avatar.id;
      delta.levelCurrent = 1;
      delta.levelTarget = 90;
      for (const reference of skills) {
        const skill: CalSkillDelta = new CalSkillDelta();
        skill.id = reference.groupId;
        skill.levelCurrent = 1;
        skill.levelTarget = 10;
        delta.skills.push(skill);
      }
      deltas.push(delta);
    }
    let weaponIndex: number = 0;
    for (const meta of await WikiMetaService.getWeapons()) {
      if (!catalog.weaponIds.includes(meta.id) || meta.rankLevel < 4 || meta.rankLevel > 5) { continue; }
      const weapon: CalWeaponDelta = new CalWeaponDelta();
      weapon.id = meta.id;
      weapon.levelCurrent = 1;
      weapon.levelTarget = 90;
      if (weaponIndex >= deltas.length) {
        const delta: CalAvatarDelta = new CalAvatarDelta();
        delta.levelTarget = 0;
        deltas.push(delta);
      }
      deltas[weaponIndex].weapon = weapon;
      weaponIndex++;
    }
    if (deltas.length === 0) { throw new Error('没有可用于同步库存的计算器目录'); }
    return deltas;
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

  static async save(projectId: number, prepared: CultivationPreparedEntry[], overwrite: boolean,
    createNew: boolean = false): Promise<CultivationSaveReport> {
    return CultivationRepo.saveDrafts(projectId, prepared, overwrite, createNew);
  }
}
