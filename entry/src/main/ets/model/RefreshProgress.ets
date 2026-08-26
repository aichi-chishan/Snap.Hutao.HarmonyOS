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
}
