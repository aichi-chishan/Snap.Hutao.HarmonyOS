/**
 * AnnouncementService.ets
 * 官方公告：hk4e-ann-api getAnnList / getAnnContent，无需登录�? */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { Announcement, AnnouncementDetail, AnnouncementType, AnnouncementGroup, AnnouncementTypeEntry } from '../model/Announcement';
import { AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'AnnouncementService';
const ANN_HOST: string = 'https://hk4e-ann-api.mihoyo.com/common/hk4e_cn/announcement/api';

export class AnnouncementService {
  private static instance: AnnouncementService = new AnnouncementService();

  static getInstance(): AnnouncementService {
    return AnnouncementService.instance;
  }

  /** 公告列表（无需登录）。返回按 type 分组的结构（对齐 Windows AnnouncementWrapper: type_list + list[]）。 */
  async fetchGroups(region: string, level: number): Promise<AnnouncementGroup[]> {
    const resp: ApiResponse = await AnnouncementService.getList(region, level);
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const obj = resp.data as Record<string, Object>;
    // type_list：API 提供 id → 名称（Windows 用 mi18n_name 作页签标题）
    const typeNameMap: Map<number, string> = new Map();
    const typeList = obj['type_list'] as Array<Object>;
    if (typeList !== undefined && typeList !== null) {
      for (let i = 0; i < typeList.length; i++) {
        const t = typeList[i] as Record<string, Object>;
        const id: number = Number(t['id'] ?? 0);
        const mi18n: string = String(t['mi18n_name'] ?? '');
        typeNameMap.set(id, mi18n.length > 0 ? mi18n : String(t['name'] ?? ''));
      }
    }
    // list：按 type_id 分组
    const groups: AnnouncementGroup[] = [];
    const list = obj['list'] as Array<Object>;
    if (list !== undefined && list !== null) {
      for (let i = 0; i < list.length; i++) {
        const wrapper = list[i] as Record<string, Object>;
        const typeId: number = Number(wrapper['type_id'] ?? 0);
        const g: AnnouncementGroup = new AnnouncementGroup();
        g.typeId = typeId;
        g.label = typeNameMap.get(typeId) ?? String(wrapper['type_label'] ?? AnnouncementType.nameOf(typeId));
        const inner = wrapper['list'] as Array<Object>;
        if (inner !== undefined && inner !== null) {
          for (let j = 0; j < inner.length; j++) {
            const a: Announcement = Announcement.fromJson(inner[j]);
            if (a.type === 0) {
              a.type = typeId;
            }
            a.typeName = g.label;
            g.items.push(a);
          }
        }
        // 组内按时间倒序
        g.items.sort((a: Announcement, b: Announcement) => b.startTime - a.startTime);
        if (g.items.length > 0) {
          groups.push(g);
        }
      }
    }
    Logger.info(TAG, `announcement groups ${groups.length}`);
    return groups;
  }

  /** 公告列表（无需登录）。平铺全部分组（主页预览用），按时间倒序。 */
  async fetchList(region: string, level: number): Promise<Announcement[]> {
    const groups: AnnouncementGroup[] = await this.fetchGroups(region, level);
    const items: Announcement[] = [];
    for (let i = 0; i < groups.length; i++) {
      for (let j = 0; j < groups[i].items.length; j++) {
        items.push(groups[i].items[j]);
      }
    }
    items.sort((a: Announcement, b: Announcement) => b.startTime - a.startTime);
    Logger.info(TAG, `announcement list ${items.length}`);
    return items;
  }

  private static async getList(region: string, level: number): Promise<ApiResponse> {
    const params: Record<string, string> = {
      'game': 'hk4e',
      'game_biz': 'hk4e_cn',
      'lang': 'zh-cn',
      'bundle_id': 'hk4e_cn',
      'platform': 'pc',
      'region': region.length > 0 ? region : 'cn_gf01',
      'level': `${level}`,
      'uid': '100000000',
    };
    const query: string = AnnouncementService.buildQuery(params);
    const url: string = `${ANN_HOST}/getAnnList?${query}`;
    const headers: Record<string, string> = { 'User-Agent': AppConstants.UA_BBS, 'Accept': 'application/json' };
    return ApiClient.getInstance().get(url, headers);
  }

  /** 公告详情内容（HTML�?*/
  async fetchContent(annId: number, region: string, level: number): Promise<string> {
    const params: Record<string, string> = {
      'game': 'hk4e',
      'game_biz': 'hk4e_cn',
      'lang': 'zh-cn',
      'bundle_id': 'hk4e_cn',
      'platform': 'pc',
      'region': region.length > 0 ? region : 'cn_gf01',
      'level': `${level}`,
      'uid': '100000000',
      'ann_id': `${annId}`,
    };
    const query: string = AnnouncementService.buildQuery(params);
    const url: string = `${ANN_HOST}/getAnnContent?${query}`;
    const headers: Record<string, string> = { 'User-Agent': AppConstants.UA_BBS, 'Accept': 'application/json' };
    const resp: ApiResponse = await ApiClient.getInstance().get(url, headers);
    Logger.info(TAG, `fetchContent ann=${annId} retcode=${resp.retcode}`);
    if (!resp.success || resp.data === undefined) {
      Logger.warn(TAG, `fetchContent fail retcode=${resp.retcode} msg=${resp.message}`);
      return '';
    }
    const obj = resp.data as Record<string, Object>;
    const list = obj['list'] as Array<Object>;
    if (list !== undefined && list !== null && list.length > 0) {
      const content: string = AnnouncementDetail.fromJson(list[0]).content;
      Logger.info(TAG, `fetchContent content len=${content.length}`);
      return content;
    }
    Logger.warn(TAG, 'fetchContent empty list');
    return '';
  }

  static buildQuery(params: Record<string, string>): string {
    const keys: string[] = Object.keys(params).sort();
    let q: string = '';
    for (let i = 0; i < keys.length; i++) {
      if (i > 0) {
        q += '&';
      }
      q += `${keys[i]}=${encodeURIComponent(params[keys[i]])}`;
    }
    return q;
  }
}
