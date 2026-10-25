/**
 * RefreshProgress.ets
 * 祈愿刷新进度状态（供 Service → ViewModel → UI 传递）。
 */
export class RefreshProgress {
  running: boolean = false;
  currentPoolName: string = '';
  fetchedCount: number = 0;
  reportText: string = '';
  done: boolean = false;
  error: string = '';
  /** 本次刷新新拉取记录的名称（最近 60 条，供 UI 滚动展示） */
  recentNames: string[] = [];
  /** 本次刷新新拉取记录（最近 40 条，供 UI 头像流展示，对齐 Windows） */
  recentItems: RecentGachaItem[] = [];
  /** 本次刷新来源（'SToken 自动鉴权' / '祈愿链接'；结果摘要卡用） */
  sourceText: string = '';
  /** 本次刷新归属 UID（服务端响应校验后回填；结果摘要卡用） */
  uid: string = '';
  /** 各池结果明细（UX07：新增/重复/失败分列，部分成功可见） */
  pools: PoolOutcome[] = [];

  /** 是否有可展示的池级结果（刷新至少开始过一个池） */
  hasPoolResults(): boolean {
    return this.pools.length > 0;
  }
}

/** 单池刷新结果（UX07 闭环明细：新增写入/跳过重复/失败原因） */
export class PoolOutcome {
  gachaType: number = 0;
  name: string = '';
  /** 新写入记录数 */
  inserted: number = 0;
  /** 增量模式下跳过的已有记录数 */
  duplicates: number = 0;
  /** 本池是否失败/取消（后续池未尝试） */
  failed: boolean = false;
  /** 失败/取消原因（failed 时非空） */
  errorText: string = '';
}

/** 刷新进度中的单条新记录（头像流条目） */
export class RecentGachaItem {
  name: string = '';
  itemType: string = '';
  rank: number = 0;
  count: number = 1;
}
