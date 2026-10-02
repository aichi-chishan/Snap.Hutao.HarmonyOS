/**
 * Offline cultivation arithmetic ported from Snap.Hutao.Remastered (MIT).
 * Copyright (c) DGP Studio. Exact tables live in CultivationTables.ets.
 * Local metadata supplies material identities; unavailable metadata fails explicitly.
 */
import { CalAvatarDelta, CalWeaponDelta } from './CalculateService';
import { CalItem, CalAvatarConsume, CalBatchResult } from '../model/Calculate';
import { WikiMetaService, WikiAvatarMeta, WikiWeaponMeta, MetaMaterial } from './WikiMetaService';
import { CultivationTables } from './CultivationTables';

export class OfflineCultivationService {
  static async batchCompute(deltas: CalAvatarDelta[]): Promise<CalBatchResult> {
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    const materials: Map<number, MetaMaterial> = await WikiMetaService.getMaterials();
    const result: CalBatchResult = new CalBatchResult();
    const overall: Map<number, number> = new Map<number, number>();
    for (const delta of deltas) {
      const avatar: WikiAvatarMeta | undefined = avatars.find((item: WikiAvatarMeta): boolean => item.id === delta.avatarId);
      if (avatar === undefined) {
        throw new Error(`角色 ${delta.avatarId} 的养成元数据不可用`);
      }
      const consume: CalAvatarConsume = new CalAvatarConsume();
      consume.avatarConsume = OfflineCultivationService.avatarItems(delta, avatar);
      if (delta.weapon !== undefined) {
        const weaponId: number = delta.weapon.id;
        const weapon: WikiWeaponMeta | undefined = weapons.find((item: WikiWeaponMeta): boolean => item.id === weaponId);
        if (weapon === undefined) {
          throw new Error(`武器 ${weaponId} 的养成元数据不可用`);
        }
        consume.weaponConsume = OfflineCultivationService.weaponItems(delta.weapon, weapon);
      }
      for (const item of consume.avatarConsume.concat(consume.weaponConsume)) {
        OfflineCultivationService.decorate(item, materials);
        OfflineCultivationService.add(overall, item.id, item.num);
      }
      result.items.push(consume);
    }
    result.overallConsume = OfflineCultivationService.toItems(overall);
    for (const item of result.overallConsume) {
      OfflineCultivationService.decorate(item, materials);
    }
    return result;
  }

  static async weaponCompute(weaponId: number, current: number, target: number, promote: number): Promise<CalItem[]> {
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    const weapon: WikiWeaponMeta | undefined = weapons.find((item: WikiWeaponMeta): boolean => item.id === weaponId);
    if (weapon === undefined) {
      throw new Error('缺少武器养成元数据');
    }
    const delta: CalWeaponDelta = new CalWeaponDelta();
    delta.id = weaponId;
    delta.levelCurrent = current;
    delta.levelTarget = Math.min(target, weapon.rankLevel <= 2 ? 70 : 90);
    delta.weaponPromoteLevel = promote;
    const items: CalItem[] = OfflineCultivationService.weaponItems(delta, weapon);
    const materials: Map<number, MetaMaterial> = await WikiMetaService.getMaterials();
    for (const item of items) {
      OfflineCultivationService.decorate(item, materials);
    }
    return items;
  }

  static avatarItems(delta: CalAvatarDelta, avatar: WikiAvatarMeta): CalItem[] {
    OfflineCultivationService.validateLevel(delta.levelCurrent, delta.levelTarget, 100);
    const counts: Map<number, number> = new Map<number, number>();
    if (delta.levelCurrent <= 90 && delta.levelTarget >= 95) {
      OfflineCultivationService.add(counts, 104300, 1);
    }
    if (delta.levelCurrent <= 95 && delta.levelTarget >= 100) {
      OfflineCultivationService.add(counts, 104300, 2);
    }
    // Windows avatar XP table ends at90; higher caps consume Masterless Stella Fortuna.
    const exp: number = OfflineCultivationService.experience(CultivationTables.AvatarExperience,
      Math.min(delta.levelCurrent, 90), Math.min(delta.levelTarget, 90));
    const books: number = Math.ceil(exp / 20000);
    OfflineCultivationService.add(counts, 104003, books);
    OfflineCultivationService.add(counts, 202, books * 4000);
    const ascensions: number[] = OfflineCultivationService.requiredAscensions(delta.levelCurrent,
      delta.levelTarget, delta.avatarPromoteLevel);
    if ((ascensions.length > 0 || delta.skills.length > 0) && avatar.cultivationItems.length < 6) {
      throw new Error(`${avatar.name} 的突破/天赋材料元数据不完整`);
    }
    const gems: Record<string, number> = {
      '火': 104111, '水': 104121, '草': 104131, '雷': 104141,
      '风': 104151, '冰': 104161, '岩': 104171
    };
    for (const index of ascensions) {
      const gem: number = gems[avatar.vision] ?? 0;
      if (gem <= 0) {
        throw new Error(`${avatar.name} 的元素材料未知`);
      }
      OfflineCultivationService.add(counts, 202, CultivationTables.AvatarAscensionMoraCosts[index]);
      OfflineCultivationService.addOffset(counts, gem, CultivationTables.AvatarGemConsumption[index], true);
      OfflineCultivationService.add(counts, avatar.cultivationItems[1], CultivationTables.AvatarBossMaterialCounts[index]);
      OfflineCultivationService.add(counts, avatar.cultivationItems[2], CultivationTables.AvatarSpecialtyCounts[index]);
      OfflineCultivationService.addOffset(counts, avatar.cultivationItems[3], CultivationTables.AvatarMonsterMaterialConsumption[index]);
    }
    for (const skill of delta.skills) {
      OfflineCultivationService.validateLevel(skill.levelCurrent, skill.levelTarget, 10);
      for (let level: number = skill.levelCurrent; level < skill.levelTarget; level++) {
        OfflineCultivationService.add(counts, 202, CultivationTables.TalentMoraCosts[level]);
        OfflineCultivationService.addOffset(counts, avatar.cultivationItems[4], CultivationTables.TalentBookConsumption[level]);
        OfflineCultivationService.addOffset(counts, avatar.cultivationItems[3], CultivationTables.TalentMonsterMaterialConsumption[level]);
        OfflineCultivationService.add(counts, avatar.cultivationItems[5], CultivationTables.WeeklyBossCounts[level]);
        if (level === 9) {
          OfflineCultivationService.add(counts, 104319, 1);
        }
      }
    }
    return OfflineCultivationService.toItems(counts);
  }

  static weaponItems(delta: CalWeaponDelta, weapon: WikiWeaponMeta): CalItem[] {
    const quality: number = Math.min(5, weapon.rankLevel);
    if (quality < 1 || weapon.cultivationItems.length < 3) {
      throw new Error(`${weapon.name} 的养成元数据不完整`);
    }
    OfflineCultivationService.validateLevel(delta.levelCurrent, delta.levelTarget, quality <= 2 ? 70 : 90);
    const counts: Map<number, number> = new Map<number, number>();
    const ore: number = Math.ceil(OfflineCultivationService.experience(CultivationTables.WeaponExperience[quality],
      delta.levelCurrent, delta.levelTarget) / 10000);
    OfflineCultivationService.add(counts, 104013, ore);
    OfflineCultivationService.add(counts, 202, ore * 1000);
    for (const index of OfflineCultivationService.requiredAscensions(delta.levelCurrent,
      delta.levelTarget, delta.weaponPromoteLevel)) {
      OfflineCultivationService.add(counts, 202, CultivationTables.WeaponAscensionMoraCosts[quality][index]);
      OfflineCultivationService.addOffset(counts, weapon.cultivationItems[0], CultivationTables.WeaponMaterialConsumption[quality][index]);
      OfflineCultivationService.addOffset(counts, weapon.cultivationItems[1], CultivationTables.WeaponMonsterMaterialAConsumption[quality][index]);
      OfflineCultivationService.addOffset(counts, weapon.cultivationItems[2], CultivationTables.WeaponMonsterMaterialBConsumption[quality][index]);
    }
    return OfflineCultivationService.toItems(counts);
  }

  /** Same lower/upper-bound semantics as Windows Ascension.cs, including cap-level promotion. */
  static requiredAscensions(current: number, target: number, promote: number): number[] {
    const indices: number[] = [];
    for (let index: number = promote; index < CultivationTables.AscensionLevels.length; index++) {
      const level: number = CultivationTables.AscensionLevels[index];
      if (level >= current && level <= target) {
        indices.push(index);
      }
    }
    return indices;
  }

  private static validateLevel(current: number, target: number, max: number): void {
    if (!Number.isInteger(current) || !Number.isInteger(target) || current < 1 || target < current || target > max) {
      throw new Error(`等级范围必须为 1–${max}，且目标不能低于当前等级`);
    }
  }

  private static experience(table: number[], current: number, target: number): number {
    let sum: number = 0;
    for (let level: number = current; level < target; level++) {
      sum += table[level];
    }
    return sum;
  }

  private static addOffset(counts: Map<number, number>, material: number, pair: number[], positive: boolean = false): void {
    OfflineCultivationService.add(counts, material + (positive ? pair[0] : -pair[0]), pair[1]);
  }

  private static add(counts: Map<number, number>, id: number, count: number): void {
    if (count <= 0) {
      return;
    }
    if (!Number.isInteger(id) || id <= 0 || !Number.isFinite(count)) {
      throw new Error('养成材料数据无效');
    }
    counts.set(id, (counts.get(id) ?? 0) + count);
  }

  private static toItems(counts: Map<number, number>): CalItem[] {
    const items: CalItem[] = [];
    for (const id of counts.keys()) {
      const item: CalItem = new CalItem();
      item.id = id;
      item.num = counts.get(id) ?? 0;
      item.lackNum = item.num;
      items.push(item);
    }
    return items;
  }

  private static decorate(item: CalItem, materials: Map<number, MetaMaterial>): void {
    const material: MetaMaterial | undefined = materials.get(item.id);
    item.name = material?.n ?? `材料 ${item.id}`;
    item.icon = material?.i ?? '';
  }
}
