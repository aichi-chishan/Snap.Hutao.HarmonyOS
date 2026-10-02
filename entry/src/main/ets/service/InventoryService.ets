/** 非注入材料库存：手动数量、明确文件导入、官方养成计算器差额。 */
import { InventoryRepo } from '../data/repo/InventoryRepo';
import { CalBatchResult } from '../model/Calculate';

export class InventoryService {
  private static object(value: Object, label: string): Record<string, Object> {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error(`${label} 必须是对象`);
    }
    return value as Record<string, Object>;
  }

  /**
   * 支持 UIIF v1.0 list[].itemId/material.count，或明确的轻量格式：
   * {"materials":[{"itemId":104003,"count":20}]}。只导入材料，不导入装备/家具。
   */
  static parseInventory(text: string): Map<number, number> {
    const root: Record<string, Object> = InventoryService.object(JSON.parse(text) as Object, '库存文件');
    let entries: Object[];
    let uiif: boolean = false;
    if (root['info'] !== undefined) {
      const info: Record<string, Object> = InventoryService.object(root['info'], 'info');
      if (info['uiif_version'] !== 'v1.0') {
        throw new Error('仅支持 UIIF v1.0 材料库存');
      }
      if (!Array.isArray(root['list'])) {
        throw new Error('UIIF list 必须是数组');
      }
      uiif = true;
      entries = root['list'] as Object[];
    } else {
      if (!Array.isArray(root['materials'])) {
        throw new Error('库存文件需为 UIIF v1.0，或包含 materials 数组（itemId、count）');
      }
      entries = root['materials'] as Object[];
    }
    const inventory: Map<number, number> = new Map<number, number>();
    for (let i: number = 0; i < entries.length; i++) {
      const item: Record<string, Object> = InventoryService.object(entries[i], `第 ${i + 1} 项`);
      if (uiif && (item['material'] === undefined || item['material'] === null)) {
        if (item['equip'] === undefined && item['furniture'] === undefined) {
          throw new Error(`第 ${i + 1} 项缺少 material/equip/furniture`);
        }
        continue;
      }
      const detail: Record<string, Object> = uiif
        ? InventoryService.object(item['material'], `第 ${i + 1} 项 material`) : item;
      if (typeof item['itemId'] !== 'number' || typeof detail['count'] !== 'number') {
        throw new Error(`第 ${i + 1} 项 itemId、count 必须是数字`);
      }
      const itemId: number = item['itemId'] as number;
      const count: number = detail['count'] as number;
      InventoryRepo.validateCount(itemId, count);
      if (inventory.has(itemId)) {
        throw new Error(`材料 ID 重复：${itemId}`);
      }
      inventory.set(itemId, count);
    }
    return inventory;
  }

  /** 默认仅更新文件中出现的材料，未提供的数量仍保持未知或既有值。 */
  static async importInventory(projectId: number, text: string, replace: boolean = false): Promise<number> {
    const incoming: Map<number, number> = InventoryService.parseInventory(text);
    const inventory: Map<number, number> = replace
      ? new Map<number, number>() : await InventoryRepo.getInventory(projectId);
    incoming.forEach((count: number, itemId: number) => inventory.set(itemId, count));
    await InventoryRepo.replaceInventory(projectId, inventory);
    return incoming.size;
  }

  /** 数据缺失拒绝同步，绝不把缺失的 lack_num 当成 0；只更新响应中的材料。 */
  static async syncFromCalculator(projectId: number, result: CalBatchResult): Promise<number> {
    if (!result.hasUserInfo || result.overallConsume.length === 0) {
      throw new Error('计算器未返回账号库存，现有库存未改变');
    }
    const incoming: Map<number, number> = new Map<number, number>();
    for (const item of result.overallConsume) {
      if (!item.hasInventoryData || !Number.isSafeInteger(item.num) || !Number.isSafeInteger(item.lackNum)) {
        throw new Error('计算器库存数据不完整，现有库存未改变');
      }
      // lack_num 可为负（库存超过需求），不可截断后再计算。
      const count: number = item.num - item.lackNum;
      InventoryRepo.validateCount(item.id, count);
      if (incoming.has(item.id)) {
        throw new Error(`计算器返回重复材料：${item.id}`);
      }
      incoming.set(item.id, count);
    }
    const inventory: Map<number, number> = await InventoryRepo.getInventory(projectId);
    incoming.forEach((count: number, itemId: number) => inventory.set(itemId, count));
    await InventoryRepo.replaceInventory(projectId, inventory);
    return incoming.size;
  }
}
