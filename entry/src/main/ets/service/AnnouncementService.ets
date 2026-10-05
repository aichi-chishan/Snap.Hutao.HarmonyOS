/** Public announcements, routed by the explicitly selected region and language. No credentials. */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { Announcement, AnnouncementDetail, AnnouncementType, AnnouncementGroup } from '../model/Announcement';
import { AnnouncementContext } from '../model/RegionalContent';
import { AppConstants } from '../common/Constants';
import { HoyolabEndpoints } from '../common/HoyolabEndpoints';

class AnnouncementCache {
  groups: AnnouncementGroup[] = [];
  groupsAt: number = 0;
  contents: Map<number, string> = new Map<number, string>();
  contentsAt: number = 0;
}

export class AnnouncementService {
  private static instance: AnnouncementService = new AnnouncementService();
  private static readonly TTL_MS: number = 30 * 60 * 1000;
  private cache: Map<string, AnnouncementCache> = new Map<string, AnnouncementCache>();
  private lists: Map<string, Promise<AnnouncementGroup[]>> = new Map<string, Promise<AnnouncementGroup[]>>();
  private bodies: Map<string, Promise<Map<number, string>>> = new Map<string, Promise<Map<number, string>>>();

  static getInstance(): AnnouncementService { return AnnouncementService.instance; }

  static query(context: AnnouncementContext): Record<string, string> {
    AnnouncementContext.create(context.region, context.language, context.level);
    const biz: string = HoyolabEndpoints.gameBiz(context.region);
    const params: Record<string, string> = {
      'game': 'hk4e', 'game_biz': biz, 'bundle_id': biz, 'lang': context.language,
      'platform': 'pc', 'region': context.region, 'level': String(context.level), 'uid': '100000000',
    };
    return params;
  }

  static buildQuery(params: Record<string, string>): string {
    return Object.keys(params).sort().map((key: string): string => `${key}=${encodeURIComponent(params[key])}`).join('&');
  }

  private async get(path: string, context: AnnouncementContext): Promise<Record<string, Object>> {
    const url: string = `${HoyolabEndpoints.announcementUrl(path, context.region)}?${AnnouncementService.buildQuery(AnnouncementService.query(context))}`;
    // Empty explicit Cookie suppresses ApiClient's automatic same-region session injection.
    const headers: Record<string, string> = { 'Cookie': '', 'User-Agent': AppConstants.UA_BBS, 'Accept': 'application/json' };
    const response: ApiResponse = await ApiClient.getInstance().get(url, headers);
    if (!response.success || response.data === undefined) { throw new Error(response.userFriendlyMessage()); }
    if (response.data === null || typeof response.data !== 'object' || Array.isArray(response.data)) { throw new Error('公告响应格式无效'); }
    return response.data as Record<string, Object>;
  }

  private entry(key: string): AnnouncementCache {
    let value: AnnouncementCache | undefined = this.cache.get(key);
    if (value !== undefined) { return value; }
    if (this.cache.size >= 8) { this.cache.delete(Array.from(this.cache.keys())[0]); }
    value = new AnnouncementCache(); this.cache.set(key, value); return value;
  }

  private static copy(groups: AnnouncementGroup[]): AnnouncementGroup[] {
    // Announcement models contain only data fields. Callers cannot mutate a cached region/language result.
    return JSON.parse(JSON.stringify(groups)) as AnnouncementGroup[];
  }

  private async loadGroups(context: AnnouncementContext): Promise<AnnouncementGroup[]> {
    const obj: Record<string, Object> = await this.get('getAnnList', context);
    if (!Array.isArray(obj['list'])) { throw new Error('公告列表格式无效'); }
    const typeNames: Map<number, string> = new Map<number, string>();
    if (Array.isArray(obj['type_list'])) {
      for (const entry of obj['type_list'] as Object[]) {
        const type: Record<string, Object> = entry as Record<string, Object>;
        if (type !== null && typeof type === 'object') {
          typeNames.set(Number(type['id']), String(type['mi18n_name'] || type['name'] || ''));
        }
      }
    }
    const groups: AnnouncementGroup[] = [];
    for (const raw of obj['list'] as Object[]) {
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) { throw new Error('公告分组格式无效'); }
      const wrapper: Record<string, Object> = raw as Record<string, Object>;
      if (!Array.isArray(wrapper['list'])) { throw new Error('公告分组缺少列表'); }
      const group: AnnouncementGroup = new AnnouncementGroup();
      group.typeId = Number(wrapper['type_id']);
      group.label = typeNames.get(group.typeId) || String(wrapper['type_label'] ?? AnnouncementType.nameOf(group.typeId));
      for (const record of wrapper['list'] as Object[]) {
        const item: Announcement = Announcement.fromJson(record);
        if (!Number.isSafeInteger(item.id) || item.id < 1) { throw new Error('公告 ID 无效'); }
        if (item.type === 0) { item.type = group.typeId; }
        item.typeName = group.label; item.sourceRegion = context.region;
        item.sourceLanguage = context.language; item.sourceLevel = context.level;
        group.items.push(item);
      }
      group.items.sort((a: Announcement, b: Announcement): number => b.startTime - a.startTime);
      if (group.items.length > 0) { groups.push(group); }
    }
    const cached: AnnouncementCache = this.entry(context.key());
    cached.groups = groups; cached.groupsAt = Date.now();
    return groups;
  }

  async fetchGroups(region: string, level: number = 55, language: string = 'zh-cn', force: boolean = false): Promise<AnnouncementGroup[]> {
    const context: AnnouncementContext = AnnouncementContext.create(region, language, level);
    const key: string = context.key();
    const cached: AnnouncementCache | undefined = this.cache.get(key);
    if (!force && cached !== undefined && cached.groupsAt > 0 && Date.now() - cached.groupsAt < AnnouncementService.TTL_MS) {
      return AnnouncementService.copy(cached.groups);
    }
    const existing: Promise<AnnouncementGroup[]> | undefined = this.lists.get(key);
    let pending: Promise<AnnouncementGroup[]>;
    if (existing === undefined) { pending = this.loadGroups(context); this.lists.set(key, pending); }
    else { pending = existing; }
    try { return AnnouncementService.copy(await pending); }
    finally { if (this.lists.get(key) === pending) { this.lists.delete(key); } }
  }

  async fetchList(region: string, level: number = 55, language: string = 'zh-cn'): Promise<Announcement[]> {
    const groups: AnnouncementGroup[] = await this.fetchGroups(region, level, language);
    const items: Announcement[] = [];
    for (const group of groups) { for (const item of group.items) { items.push(item); } }
    return items.sort((a: Announcement, b: Announcement): number => b.startTime - a.startTime);
  }

  private async loadContents(context: AnnouncementContext): Promise<Map<number, string>> {
    const obj: Record<string, Object> = await this.get('getAnnContent', context);
    if (!Array.isArray(obj['list'])) { throw new Error('公告正文格式无效'); }
    const contents: Map<number, string> = new Map<number, string>();
    let units: number = 0;
    for (const record of obj['list'] as Object[]) {
      if (record === null || typeof record !== 'object' || Array.isArray(record)) { throw new Error('公告正文条目无效'); }
      const detail: AnnouncementDetail = AnnouncementDetail.fromJson(record);
      if (!Number.isSafeInteger(detail.annId) || detail.annId < 1) { throw new Error('公告正文 ID 无效'); }
      if (!contents.has(detail.annId)) { contents.set(detail.annId, detail.content); units += detail.content.length; }
    }
    if (units <= 4 * 1024 * 1024) {
      const cached: AnnouncementCache = this.entry(context.key());
      cached.contents = contents; cached.contentsAt = Date.now();
    }
    return contents;
  }

  async fetchContent(annId: number, region: string, level: number = 55, language: string = 'zh-cn'): Promise<string> {
    if (!Number.isSafeInteger(annId) || annId < 1) { throw new Error('公告 ID 无效'); }
    const context: AnnouncementContext = AnnouncementContext.create(region, language, level);
    const key: string = context.key();
    const cached: AnnouncementCache | undefined = this.cache.get(key);
    if (cached !== undefined && cached.contentsAt > 0 && Date.now() - cached.contentsAt < AnnouncementService.TTL_MS && cached.contents.has(annId)) {
      return cached.contents.get(annId)!;
    }
    const existing: Promise<Map<number, string>> | undefined = this.bodies.get(key);
    let pending: Promise<Map<number, string>>;
    if (existing === undefined) { pending = this.loadContents(context); this.bodies.set(key, pending); }
    else { pending = existing; }
    try {
      const contents: Map<number, string> = await pending;
      const content: string | undefined = contents.get(annId);
      if (content === undefined || content.length === 0) { throw new Error('服务器未返回所选公告的正文'); }
      return content;
    } finally { if (this.bodies.get(key) === pending) { this.bodies.delete(key); } }
  }

  static officialUrl(url: string): string {
    return /^https:\/\/(?:www\.)?(?:miyoushe\.com|hoyolab\.com)\/[^\s]*$/i.test(url) && !url.includes('@') ? url : '';
  }
}
