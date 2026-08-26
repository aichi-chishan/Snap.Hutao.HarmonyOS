/**
 * RouteParams.ets
 * 页面路由参数（跨页共享，避免重复声明）。
 */

export interface AnnouncementDetailParams {
  /** 公告 id（优先用于拼米哈游官方详情页） */
  annId: number;
  /** 标题 */
  title: string;
  /** 备用外链（有则直接用，无则用 annId 拼官方页） */
  url?: string;
}
