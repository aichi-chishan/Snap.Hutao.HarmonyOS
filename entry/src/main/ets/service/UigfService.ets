/**
 * UigfService.ets
 * UIGF 祈愿数据导入导出（对齐 Windows Service\UIGF：导出 v4.2 含 hk4e_ugc 千星奇域，
 * 兼容导入 v4.2 / v4.0 / v3.x 单游戏格式）。纯本地数据变换 + GachaRepo 落库，无云依赖。
 */
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaItem } from '../model/GachaItem';
import { GachaType } from '../model/GachaType';
import { Logger } from '../common/Logger';
import { AppConstants } from '../common/Constants';

const TAG: string = 'UigfService';
const UIGF_VERSION: string = 'v4.2';

/** 导入结果 */
export class UigfImportResult {
  ok: boolean = false;
  message: string = '';
  uid: string = '';
  inserted: number = 0;
}

/** UIGF v4.x 常规池单条记录 */
class UigfItem {
  gacha_type: string = '';
  uigf_gacha_type: string = '';
  item_id: number = 0;
  count: string = '1';
  time: string = '';
  name: string = '';
  item_type: string = '';
  rank_type: string = '';
  id: string = '';
}

/** UIGF v4.2 千星奇域（hk4e_ugc）单条记录（对齐 Windows Hk4eUGCItem） */
class UigfUgcItem {
  id: string = '';
  schedule_id: number = 0;
  item_type: string = '';
  item_id: number = 0;
  item_name: string = '';
  rank_type: string = '';
  time: string = '';
  op_gacha_type: string = '';
}

/** UIGF 单存档 */
class UigfEntry {
  uid: number = 0;
  timezone: number = 0;
  lang: string = 'zh-cn';
  list: UigfItem[] = [];
}

/** UIGF v4.2 千星奇域单存档 */
class UigfUgcEntry {
  uid: number = 0;
  timezone: number = 0;
  lang: string = 'zh-cn';
  list: UigfUgcItem[] = [];
}

/** UIGF v4.2 根（info + hk4e + hk4e_ugc） */
class UigfRoot {
  info: UigfInfo = new UigfInfo();
  hk4e: UigfEntry[] = [];
  hk4e_ugc: UigfUgcEntry[] = [];
}

class UigfInfo {
  export_timestamp: number = 0;
  export_app: string = '';
  export_app_version: string = '';
  version: string = UIGF_VERSION;
}

export class UigfService {
  private static instance: UigfService = new UigfService();

  static getInstance(): UigfService {
    return UigfService.instance;
  }

  /** 全部归档导出为 UIGF v4.2 JSON（常规池入 hk4e，千星奇域入 hk4e_ugc） */
  async buildExportJson(): Promise<string> {
    const root: UigfRoot = new UigfRoot();
    root.info.export_timestamp = Math.floor(Date.now() / 1000);
    root.info.export_app = 'Snap.Hutao.HarmonyOS';
    root.info.export_app_version = AppConstants.APP_VERSION;
    root.info.version = UIGF_VERSION;
    const archives = await GachaRepo.getAllArchives();
    for (const archive of archives) {
      const items: GachaItem[] = await GachaRepo.getItemsByArchive(archive.id);
      if (items.length === 0) {
        continue;
      }
      const entry: UigfEntry = new UigfEntry();
      const ugcEntry: UigfUgcEntry = new UigfUgcEntry();
      entry.uid = Number(archive.uid) || 0;
      ugcEntry.uid = entry.uid;
      entry.lang = 'zh-cn';
      ugcEntry.lang = 'zh-cn';
      for (const it of items) {
        if (GachaType.isBeyond(it.gachaType)) {
          const u: UigfUgcItem = new UigfUgcItem();
          u.id = it.gachaId;
          u.schedule_id = it.scheduleId;
          u.item_type = it.itemType;
          u.item_id = it.itemId;
          u.item_name = it.name;
          u.rank_type = String(it.rankType);
          u.time = it.time;
          u.op_gacha_type = String(it.gachaType);
          ugcEntry.list.push(u);
        } else {
          const u: UigfItem = new UigfItem();
          const typeStr: string = String(it.gachaType);
          u.gacha_type = typeStr;
          u.uigf_gacha_type = typeStr;
          u.item_id = it.itemId;
          u.count = String(it.count > 0 ? it.count : 1);
          u.time = it.time;
          u.name = it.name;
          u.item_type = it.itemType;
          u.rank_type = String(it.rankType);
          u.id = it.gachaId;
          entry.list.push(u);
        }
      }
      if (entry.list.length > 0) {
        root.hk4e.push(entry);
      }
      if (ugcEntry.list.length > 0) {
        root.hk4e_ugc.push(ugcEntry);
      }
    }
    Logger.info(TAG, `export uigf ${UIGF_VERSION}: hk4e=${root.hk4e.length} hk4e_ugc=${root.hk4e_ugc.length} archives`);
    return JSON.stringify(root, null, 2);
  }

  /** 解析并导入（v4.x hk4e + hk4e_ugc / v3.x 单游戏 list），按 gacha_id 去重合并 */
  async importFromText(text: string): Promise<UigfImportResult> {
    const result: UigfImportResult = new UigfImportResult();
    let root: Record<string, Object>;
    try {
      root = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      result.message = 'JSON 解析失败';
      return result;
    }
    // 收集 (uid, items[], isUgc) 组：v4.x → hk4e / hk4e_ugc 数组；v3.x → 根 list + info.uid
    const uidSections: Array<Object> = [];
    const ugcSections: Array<Object> = [];
    const hk4e: Object | undefined = root['hk4e'];
    if (hk4e !== undefined) {
      const arr = hk4e as Object[];
      for (const e of arr) {
        uidSections.push(e);
      }
    } else if (root['list'] !== undefined) {
      const info: Record<string, Object> = (root['info'] as Record<string, Object>) ?? {};
      const single: Record<string, Object> = {
        'uid': info['uid'] !== undefined ? info['uid'] : 0,
        'timezone': 0,
        'lang': '',
        'list': root['list'],
      };
      uidSections.push(single as Object);
    } else {
      result.message = '未识别的 UIGF 文件（缺少 hk4e/list）';
      return result;
    }
    const hk4eUgc: Object | undefined = root['hk4e_ugc'];
    if (hk4eUgc !== undefined) {
      const arr = hk4eUgc as Object[];
      for (const e of arr) {
        ugcSections.push(e);
      }
    }

    let totalInserted: number = 0;
    let lastUid: string = '';
    for (let s = 0; s < uidSections.length + ugcSections.length; s++) {
      const isUgc: boolean = s >= uidSections.length;
      const section: Object = isUgc ? ugcSections[s - uidSections.length] : uidSections[s];
      const sec: Record<string, Object> = section as Record<string, Object>;
      const rawUid: Object | undefined = sec['uid'];
      const uid: string = rawUid !== undefined ? String(rawUid) : '';
      if (uid.length === 0 || uid === '0') {
        continue;
      }
      lastUid = uid;
      const archive = await GachaRepo.getOrCreateArchive(uid);
      // 现有全部游标（去重键，含颂愿池）
      const existingIds: Set<string> = new Set<string>();
      const allTypes: number[] = GachaType.QUERY_ORDER.concat(GachaType.BEYOND_ORDER);
      for (let i = 0; i < allTypes.length; i++) {
        const ids: string[] = await GachaRepo.getAllGachaIds(archive.id, allTypes[i]);
        for (const id of ids) {
          existingIds.add(id);
        }
      }
      const rawList: Object[] = (sec['list'] as Object[]) ?? [];
      const fresh: GachaItem[] = [];
      for (const rawItem of rawList) {
        const it: Record<string, Object> = rawItem as Record<string, Object>;
        const cursor: string = String(it['id'] ?? '');
        if (cursor.length === 0 || existingIds.has(cursor)) {
          continue;
        }
        const item: GachaItem = new GachaItem();
        item.archiveId = archive.id;
        if (isUgc) {
          // v4.2 hk4e_ugc：op_gacha_type 指明颂愿池（1000/2000）
          item.gachaType = Number(it['op_gacha_type'] ?? 0);
          if (!GachaType.isBeyond(item.gachaType)) {
            continue;
          }
          item.name = String(it['item_name'] ?? '');
          item.scheduleId = Number(it['schedule_id'] ?? 0);
        } else {
          // 常规池：uigf_gacha_type 优先，400(角色活动祈愿-2) 归并为 301
          let gachaType: number = Number(it['uigf_gacha_type'] ?? 0);
          if (!GachaType.isStandard(gachaType)) {
            gachaType = Number(it['gacha_type'] ?? 0);
          }
          if (gachaType === 400) {
            gachaType = GachaType.AVATAR_EVENT;
          }
          if (!GachaType.isStandard(gachaType)) {
            continue;
          }
          item.gachaType = gachaType;
          item.name = String(it['name'] ?? '');
        }
        item.itemId = Number(it['item_id'] ?? 0);
        const cnt: number = Number(it['count'] ?? 1);
        item.count = cnt > 0 ? cnt : 1;
        item.time = UigfService.normalizeTime(String(it['time'] ?? ''));
        item.itemType = String(it['item_type'] ?? '');
        item.rankType = Number(it['rank_type'] ?? 0);
        item.gachaId = cursor;
        existingIds.add(cursor);
        fresh.push(item);
      }
      if (fresh.length > 0) {
        totalInserted += await GachaRepo.insertItems(fresh);
      }
    }
    result.ok = true;
    result.uid = lastUid;
    result.inserted = totalInserted;
    result.message = totalInserted > 0
      ? `导入成功：新增 ${totalInserted} 条（UID ${lastUid}）`
      : '导入完成：没有新增记录（可能已全部存在）';
    Logger.info(TAG, `import uigf: inserted=${totalInserted} uid=${lastUid}`);
    return result;
  }

  /** '2023-01-01T00:00:00Z' → '2023-01-01 00:00:00'（截断毫秒/时区标记） */
  private static normalizeTime(time: string): string {
    let t: string = time.replace('T', ' ');
    const zIdx: number = t.indexOf('Z');
    if (zIdx > 0) {
      t = t.substring(0, zIdx);
    }
    const dotIdx: number = t.indexOf('.');
    if (dotIdx > 0) {
      t = t.substring(0, dotIdx);
    }
    return t;
  }
}
