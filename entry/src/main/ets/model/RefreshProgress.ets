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
}

/** 刷新进度中的单条新记录（头像流条目） */
export class RecentGachaItem {
  name: string = '';
  itemType: string = '';
  rank: number = 0;
  count: number = 1;
}
