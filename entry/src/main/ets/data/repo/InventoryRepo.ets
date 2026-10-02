/** 项目级材料库存。未知库存不落库；显式 0 表示已确认没有该材料。 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';

export class InventoryRepo {
  static validateProject(projectId: number): void {
    if (!Number.isSafeInteger(projectId) || projectId <= 0) {
      throw new Error('请选择有效的养成项目');
    }
  }

  static validateCount(itemId: number, count: number): void {
    if (!Number.isSafeInteger(itemId) || itemId <= 0 || itemId > 4294967295
      || !Number.isSafeInteger(count) || count < 0 || count > 4294967295) {
      throw new Error('材料 ID 必须为正整数，库存必须为 0 到 4294967295 的整数');
    }
  }

  static async getInventory(projectId: number): Promise<Map<number, number>> {
    InventoryRepo.validateProject(projectId);
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_inventory');
    pred.equalTo('project_id', projectId);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const inventory: Map<number, number> = new Map<number, number>();
    try {
      while (rs.goToNextRow()) {
        inventory.set(rs.getLong(rs.getColumnIndex('item_id')), rs.getLong(rs.getColumnIndex('count')));
      }
    } finally {
      rs.close();
    }
    return inventory;
  }

  static async setCount(projectId: number, itemId: number, count: number): Promise<void> {
    InventoryRepo.validateProject(projectId);
    InventoryRepo.validateCount(itemId, count);
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_inventory');
    pred.equalTo('project_id', projectId).and().equalTo('item_id', itemId);
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    const update: relationalStore.ValuesBucket = { 'count': count };
    if (store.updateSync(update, pred) > 0) {
      return;
    }
    const values: relationalStore.ValuesBucket = { 'project_id': projectId, 'item_id': itemId, 'count': count };
    store.insertSync('cultivate_inventory', values);
  }

  /** 在任何写入前验证全部值，单事务替换；同步事务内不穿插其他异步业务。 */
  static async replaceInventory(projectId: number, inventory: Map<number, number>): Promise<void> {
    InventoryRepo.validateProject(projectId);
    const rows: relationalStore.ValuesBucket[] = [];
    inventory.forEach((count: number, itemId: number) => {
      InventoryRepo.validateCount(itemId, count);
      const values: relationalStore.ValuesBucket = { 'project_id': projectId, 'item_id': itemId, 'count': count };
      rows.push(values);
    });
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('cultivate_inventory');
    pred.equalTo('project_id', projectId);
    const store: relationalStore.RdbStore = RelationalStoreHelper.getStore();
    store.beginTransaction();
    try {
      store.deleteSync(pred);
      for (let i: number = 0; i < rows.length; i += 500) {
        const chunk: relationalStore.ValuesBucket[] = rows.slice(i, i + 500);
        if (store.batchInsertSync('cultivate_inventory', chunk) !== chunk.length) {
          throw new Error('库存写入不完整，操作已回滚');
        }
      }
      store.commit();
    } catch (e) {
      store.rollBack();
      throw new Error(e instanceof Error ? e.message : '库存写入失败，已回滚');
    }
  }

  static async clear(projectId: number): Promise<void> {
    await InventoryRepo.replaceInventory(projectId, new Map<number, number>());
  }
}
