/**
 * GachaHistoryService.ets
 * 祈愿「历史记录」期次汇总（对齐 Windows HistoryWishBuilder + PivotHistory）：
 * 用本地 GachaEvent 期次元数据（版本/池名/UP 列表/起止时间）按 From<=time<=To 归桶用户抽卡，
 * 统计各期总抽数与 UP 五星/四星获取数。
 * 说明：UIGF v4.x 导入会把 400（角色活动祈愿-2）归并为 301，该部分数据按时间落入 301 期次，
 * 期次归属可能与卡池名有偏差（总量正确）；服务端直拉的数据保留 400 原型，归属准确。
 */
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaItem } from '../model/GachaItem';
import { GachaType } from '../model/GachaType';
import { GachaEventMeta, WikiMetaService, WikiAvatarMeta, WikiWeaponMeta } from './WikiMetaService';
import { Logger } from '../common/Logger';

const TAG: string = 'GachaHistoryService';

/** 期次内单个 UP 条目（头像/武器图标 + 获取数） */
export class HistoryUpItem {
  itemId: number = 0;
  name: string = '';
  /** MetaIcon 图标名（AvatarIcon/EquipIcon 文件名） */
  icon: string = '';
  /** MetaIcon 类目目录名 */
  category: string = 'AvatarIcon';
  count: number = 0;
}

/** 单个卡池期次汇总（对齐 Windows HistoryWish 视图字段） */
export class HistoryWishView {
  version: string = '';
  name: string = '';
  type: number = 0;
  totalCount: number = 0;
  /** 起止 epoch ms */
  from: number = 0;
  to: number = 0;
  orangeUps: HistoryUpItem[] = [];
  purpleUps: HistoryUpItem[] = [];
}

export class GachaHistoryService {
  private static instance: GachaHistoryService = new GachaHistoryService();

  static getInstance(): GachaHistoryService {
    return GachaHistoryService.instance;
  }

  /** id → 角色/武器 名称与图标（仅 UP 条目需要，走已缓存的元数据列表） */
  private async metaLookupMaps(): Promise<Map<number, HistoryUpItem>> {
    const map: Map<number, HistoryUpItem> = new Map<number, HistoryUpItem>();
    const avatars: WikiAvatarMeta[] = await WikiMetaService.getAvatars();
    for (const a of avatars) {
      const it: HistoryUpItem = new HistoryUpItem();
      it.itemId = a.id;
      it.name = a.name;
      it.icon = a.icon;
      it.category = 'AvatarIcon';
      map.set(a.id, it);
    }
    const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
    for (const w of weapons) {
      const it: HistoryUpItem = new HistoryUpItem();
      it.itemId = w.id;
      it.name = w.name;
      it.icon = w.icon;
      it.category = 'EquipIcon';
      map.set(w.id, it);
    }
    return map;
  }

  /**
   * 构建全部期次汇总（常规池 301/400/302/500；按开始时间倒序返回）。
   * 无归档数据时返回空数组。
   */
  async buildHistory(archiveId: number): Promise<HistoryWishView[]> {
    if (archiveId <= 0) {
      return [];
    }
    const events: GachaEventMeta[] = await WikiMetaService.getGachaEvents();
    if (events.length === 0) {
      return [];
    }
    const items: GachaItem[] = await GachaRepo.getItemsByArchive(archiveId);
    if (items.length === 0) {
      return [];
    }
    // 按池类型分桶（只参与常规祈愿期次；新手/常驻无期次元数据）
    const buckets: Map<number, GachaItem[]> = new Map<number, GachaItem[]>();
    for (const it of items) {
      const t: number = it.gachaType;
      if (t === GachaType.AVATAR_EVENT || t === 400 || t === GachaType.WEAPON_EVENT ||
        t === GachaType.CHRONICLE) {
        const arr: GachaItem[] | undefined = buckets.get(t);
        if (arr === undefined) {
          buckets.set(t, [it]);
        } else {
          arr.push(it);
        }
      }
    }
    const metaMap: Map<number, HistoryUpItem> = await this.metaLookupMaps();
    // 期次时间字符串 → ms 已在元数据加载完成；条目时间为 "yyyy-MM-dd HH:mm:ss"（服务器时区=东八）
    const views: HistoryWishView[] = [];
    for (const ev of events) {
      // 400 期次匹配 gachaType=400 的条目；UIGF 导入合并为 301 的部分由 301 期次按时间兜住
      const bucket: GachaItem[] | undefined = buckets.get(ev.type);
      if (bucket === undefined) {
        continue;
      }
      const view: HistoryWishView = new HistoryWishView();
      view.version = ev.version;
      view.name = ev.name;
      view.type = ev.type;
      view.from = ev.from;
      view.to = ev.to;
      const upIndex: Map<number, HistoryUpItem> = new Map<number, HistoryUpItem>();
      const upByName: Map<string, HistoryUpItem> = new Map<string, HistoryUpItem>();
      const registerUp = (id: number, list: HistoryUpItem[]): void => {
        const meta: HistoryUpItem | undefined = metaMap.get(id);
        const up: HistoryUpItem = new HistoryUpItem();
        up.itemId = id;
        up.name = meta !== undefined ? meta.name : `${id}`;
        up.icon = meta !== undefined ? meta.icon : '';
        up.category = meta !== undefined ? meta.category : 'AvatarIcon';
        list.push(up);
        upIndex.set(id, up);
        upByName.set(up.name, up);
      };
      for (const id of ev.upOrange) {
        registerUp(id, view.orangeUps);
      }
      for (const id of ev.upPurple) {
        registerUp(id, view.purpleUps);
      }
      for (const it of bucket) {
        const t: number = GachaHistoryService.itemTimeMs(it.time);
        if (t < ev.from || t > ev.to) {
          continue;
        }
        view.totalCount++;
        // item_id 优先（服务端新数据），0 时按名称兜底（老记录/UIGF v3.x 导入）
        const up: HistoryUpItem | undefined = it.itemId > 0
          ? upIndex.get(it.itemId)
          : upByName.get(it.name);
        if (up !== undefined) {
          up.count++;
        }
      }
      // 无任何抽卡记录的期次不展示（对齐 Windows HistoryWishBuilder.IsEmpty）
      if (view.totalCount > 0) {
        views.push(view);
      }
    }
    views.sort((a: HistoryWishView, b: HistoryWishView) => b.from - a.from);
    Logger.info(TAG, `history wishes built: ${views.length}`);
    return views;
  }

  /** "yyyy-MM-dd HH:mm:ss" → epoch ms（按东八区，与服务器口径一致） */
  private static itemTimeMs(time: string): number {
    if (time.length < 19) {
      return 0;
    }
    // Date.parse("yyyy-MM-ddTHH:mm:ss+08:00")
    return Date.parse(`${time.substring(0, 10)}T${time.substring(11, 19)}+08:00`);
  }
}
