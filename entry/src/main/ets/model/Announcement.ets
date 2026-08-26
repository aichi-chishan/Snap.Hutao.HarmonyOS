/**
 * Announcement.ets
 * 公告分类/条目。
 */

/** 公告类型（对齐 Windows AnnouncementType：getAnnList type_list 元素） */
export class AnnouncementTypeEntry {
  id: number = 0;
  /** 中文名（API name） */
  name: string = '';
  /** 国际化名（mi18n_name，用于页签标题） */
  mi18nName: string = '';
}

/** 按类型分组的公告（对齐 Windows AnnouncementListWrapper：type_id + type_label + list） */
export class AnnouncementGroup {
  typeId: number = 0;
  label: string = '';
  items: Announcement[] = [];
}

export class AnnouncementType {
  static readonly ACTIVITY: number = 1;
  static readonly VERSION: number = 2;
  static readonly NEWS: number = 3;
  static readonly ALL: number = 0;

  static nameOf(type: number): string {
    switch (type) {
      case AnnouncementType.ACTIVITY:
        return '活动';
      case AnnouncementType.VERSION:
        return '版本';
      case AnnouncementType.NEWS:
        return '资讯';
      default:
        return '其他';
    }
  }
}

export class Announcement {
  id: number = 0;
  type: number = 0;
  typeName: string = '';
  title: string = '';
  subtitle: string = '';
  startTime: number = 0;
  url: string = '';
  /** 公告横幅图（米哈游官方 URL） */
  banner: string = '';
  /** 详情 HTML（getAnnContent，可选） */
  content: string = '';

  /** 从 getAnnList 列表项解析 */
  static fromJson(obj: Object): Announcement {
    const item = obj as Record<string, Object>;
    const a: Announcement = new Announcement();
    a.id = Number(item['ann_id'] ?? 0);
    a.type = Number(item['type'] ?? 0);
    a.typeName = AnnouncementType.nameOf(a.type);
    a.title = String(item['title'] ?? '');
    a.subtitle = String(item['subtitle'] ?? '');
    a.startTime = Announcement.parseTime(item['start_time']);
    a.url = String(item['url'] ?? '');
    a.banner = String(item['banner'] ?? '');
    return a;
  }

  /** 解析 start_time：支持 ISO 字符串（yyyy-MM-dd HH:mm:ss）与纯秒时间戳 */
  static parseTime(raw: Object): number {
    if (raw === undefined || raw === null) {
      return 0;
    }
    if (typeof raw === 'number') {
      const n: number = raw as number;
      return Date.parse(new Date(n > 10000000000 ? n : n * 1000).toISOString()) || 0;
    }
    const s: string = String(raw);
    if (s.length === 0) {
      return 0;
    }
    // ISO 'yyyy-MM-dd HH:mm:ss' → 补 T 转 Date.parse
    const normalized: string = s.indexOf('T') >= 0 ? s : s.replace(' ', 'T');
    const parsed: number = Date.parse(normalized);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
}

export class AnnouncementDetail {
  annId: number = 0;
  content: string = '';

  static fromJson(obj: Object): AnnouncementDetail {
    const item = obj as Record<string, Object>;
    const d: AnnouncementDetail = new AnnouncementDetail();
    d.annId = Number(item['ann_id'] ?? 0);
    d.content = String(item['content'] ?? '');
    return d;
  }
}
