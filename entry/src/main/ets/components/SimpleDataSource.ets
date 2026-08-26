/**
 * SimpleDataSource.ets
 * 通用 IDataSource 实现：供 LazyForEach 长列表使用，支持整体刷新通知。
 */
export class SimpleDataSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(initial: T[]) {
    this.items = initial;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /** 整体替换数据并通知刷新 */
  notifyDataReload(items: T[]): void {
    this.items = items;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  getItems(): T[] {
    return this.items;
  }
}
