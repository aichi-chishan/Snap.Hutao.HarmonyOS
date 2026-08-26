/**
 * UigfService.ets
 * UIGF 祈愿数据导入导出（对齐 Windows Service\UIGF：导出 v4.0，兼容导入 v4.0 / v3.x 单游戏格式）。
 * 纯本地数据变换 + GachaRepo 落库，无云依赖。
 */
import { GachaRepo } from '../data/repo/GachaRepo';
import { GachaItem } from '../model/GachaItem';
import { GachaType } from '../model/GachaType';
import { Logger } from '../common/Logger';

const TAG: string = 'UigfService';
const UIGF_VERSION: string = 'v4.0';

/** 导入结果 */
export class UigfImportResult {
  ok: boolean = false;
  message: string = '';
  uid: string = '';
  inserted: number = 0;
}

/** UIGF v4.0 单条记录 */
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

/** UIGF v4.0 单存档 */
class UigfEntry {
  uid: number = 0;
  timezone: number = 0;
  lang: string = 'zh-cn';
  list: UigfItem[] = [];
}

/** UIGF v4.0 根 */
class UigfRoot {
  info: UigfInfo = new UigfInfo();
  hk4e: UigfEntry[] = [];
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

  /** 全部归档导出为 UIGF v4.0 JSON */
  async buildExportJson(): Promise<string> {
    const root: UigfRoot = new UigfRoot();
    root.info.export_timestamp = Math.floor(Date.now() / 1000);
    root.info.export_app = 'Snap.Hutao.HarmonyOS';
    root.info.export_app_version = '1.20.0';
    root.info.version = UIGF_VERSION;
    const archives = await GachaRepo.getAllArchives();
    for (const archive of archives) {
      const items: GachaItem[] = await GachaRepo.getItemsByArchive(archive.id);
      if (items.length === 0) {
        continue;
      }
      const entry: UigfEntry = new UigfEntry();
      entry.uid = Number(archive.uid) || 0;
      entry.lang = 'zh-cn';
      for (const it of items) {
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
      root.hk4e.push(entry);
    }
    Logger.info(TAG, `export uigf v4.0: ${root.hk4e.length} archives`);
    return JSON.stringify(root, null, 2);
  }

  /** 解析并导入（v4.0 hk4e / v3.x 单游戏 list），按 gacha_id 去重合并 */
  async importFromText(text: string): Promise<UigfImportResult> {
    const result: UigfImportResult = new UigfImportResult();
    let root: Record<string, Object>;
    try {
      root = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      result.message = 'JSON 解析失败';
      return result;
    }
    // 收集 (uid, items[]) 组：v4.0 → hk4e 数组；v3.x → 根 list + info.uid
    const uidSections: Array<Object> = [];
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

    let totalInserted: number = 0;
    let lastUid: string = '';
    for (const section of uidSections) {
      const sec: Record<string, Object> = section as Record<string, Object>;
      const rawUid: Object | undefined = sec['uid'];
      const uid: string = rawUid !== undefined ? String(rawUid) : '';
      if (uid.length === 0 || uid === '0') {
        continue;
      }
      lastUid = uid;
      const archive = await GachaRepo.getOrCreateArchive(uid);
      // 现有全部游标（去重键）
      const existingIds: Set<string> = new Set<string>();
      for (let i = 0; i < GachaType.QUERY_ORDER.length; i++) {
        const ids: string[] = await GachaRepo.getAllGachaIds(archive.id, GachaType.QUERY_ORDER[i]);
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
        // 池类型：uigf_gacha_type 优先，400(角色活动祈愿-2) 归并为 301
        let gachaType: number = Number(it['uigf_gacha_type'] ?? 0);
        if (!GachaType.isValid(gachaType)) {
          gachaType = Number(it['gacha_type'] ?? 0);
        }
        if (gachaType === 400) {
          gachaType = GachaType.AVATAR_EVENT;
        }
        if (!GachaType.isValid(gachaType)) {
          continue;
        }
        const item: GachaItem = new GachaItem();
        item.archiveId = archive.id;
        item.gachaType = gachaType;
        item.itemId = Number(it['item_id'] ?? 0);
        const cnt: number = Number(it['count'] ?? 1);
        item.count = cnt > 0 ? cnt : 1;
        item.time = UigfService.normalizeTime(String(it['time'] ?? ''));
        item.name = String(it['name'] ?? '');
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
