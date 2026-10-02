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
  archiveCount: number = 0;
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
      entry.timezone = UigfService.timezoneOfUid(archive.uid);
      ugcEntry.timezone = entry.timezone;
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
          u.uigf_gacha_type = it.gachaType === 400 ? '301' : typeStr;
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

  /** 先完整校验文件，再落库；时间统一为UID服务器时区的墙上时间。 */
  async importFromText(text: string): Promise<UigfImportResult> {
    const result: UigfImportResult = new UigfImportResult();
    try {
      const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      if (root === null || typeof root !== 'object' || Array.isArray(root)) {
        throw new Error('UIGF 根节点必须是对象');
      }
      const info: Record<string, Object> = root['info'] as Record<string, Object>;
      if (info === undefined || info === null) {
        throw new Error('UIGF 缺少 info');
      }
      const version: string = String(info['version'] ?? info['uigf_version'] ?? '');
      if (['v2.2', 'v2.3', 'v2.4', 'v3.0', 'v4.0', 'v4.1', 'v4.2'].indexOf(version) < 0) {
        throw new Error(`不支持的 UIGF 版本：${version}`);
      }
      const pending: Map<string, GachaItem[]> = new Map<string, GachaItem[]>();
      if (version.startsWith('v4.')) {
        if (root['hk4e'] === undefined && root['hk4e_ugc'] === undefined) {
          throw new Error('UIGF 缺少 hk4e/hk4e_ugc');
        }
        this.parseSections(root['hk4e'], false, pending);
        this.parseSections(root['hk4e_ugc'], true, pending);
      } else {
        const section: Record<string, Object> = {
          'uid': info['uid'],
          'timezone': info['region_time_zone'] ?? UigfService.timezoneOfUid(String(info['uid'] ?? '')),
          'list': root['list']
        };
        this.parseSections([section], false, pending);
      }
      // 所有条目合法后才允许创建归档；ID以字符串比较，不经过浮点数。
      for (const uid of pending.keys()) {
        const archive = await GachaRepo.getOrCreateArchive(uid);
        const existing: GachaItem[] = await GachaRepo.getItemsByArchive(archive.id);
        const keys: Set<string> = new Set<string>();
        for (const item of existing) {
          keys.add(UigfService.itemKey(item));
        }
        const fresh: GachaItem[] = [];
        const items: GachaItem[] = pending.get(uid) ?? [];
        for (const item of items) {
          const key: string = UigfService.itemKey(item);
          if (!keys.has(key)) {
            item.archiveId = archive.id;
            fresh.push(item);
            keys.add(key);
          }
        }
        result.inserted += await GachaRepo.insertItems(fresh);
        result.uid = uid;
        result.archiveCount++;
      }
      result.ok = true;
      result.message = `导入完成：${result.archiveCount} 个归档，新增 ${result.inserted} 条`;
    } catch (e) {
      result.message = `导入失败：${(e as Error).message}`;
    }
    return result;
  }

  private parseSections(raw: Object | undefined, isUgc: boolean,
    pending: Map<string, GachaItem[]>): void {
    if (raw === undefined) {
      return;
    }
    if (!Array.isArray(raw)) {
      throw new Error('UIGF 归档必须是数组');
    }
    for (const section of raw as Object[]) {
      const sec: Record<string, Object> = section as Record<string, Object>;
      if (sec === null || typeof sec !== 'object') {
        throw new Error('无效的 UIGF 归档');
      }
      const uid: string = String(sec['uid'] ?? '');
      if (!/^[1-9][0-9]{8,9}$/.test(uid)) {
        throw new Error(`无效的 UID：${uid}`);
      }
      const timezone: number = Number(sec['timezone'] ?? UigfService.timezoneOfUid(uid));
      if (!Number.isFinite(timezone) || timezone < -12 || timezone > 14) {
        throw new Error(`UID ${uid} 的时区无效`);
      }
      if (!Array.isArray(sec['list'])) {
        throw new Error(`UID ${uid} 的 list 必须是数组`);
      }
      const items: GachaItem[] = pending.get(uid) ?? [];
      for (const rawItem of sec['list'] as Object[]) {
        const it: Record<string, Object> = rawItem as Record<string, Object>;
        if (it === null || typeof it !== 'object') {
          throw new Error(`UID ${uid} 含无效记录`);
        }
        const cursor: string = String(it['id'] ?? '');
        if (!/^[0-9]+$/.test(cursor) || (typeof it['id'] === 'number' && !Number.isSafeInteger(Number(it['id'])))) {
          throw new Error('祈愿 id 必须是精确的十进制字符串');
        }
        const item: GachaItem = new GachaItem();
        item.uid = uid;
        item.gachaId = cursor;
        item.gachaType = Number(isUgc ? it['op_gacha_type'] : (it['gacha_type'] ?? it['uigf_gacha_type']));
        if (isUgc ? !GachaType.isBeyond(item.gachaType)
          : !(GachaType.isStandard(item.gachaType) || item.gachaType === 400)) {
          throw new Error(`记录 ${cursor} 的卡池类型无效`);
        }
        item.itemId = Number(it['item_id'] ?? 0);
        if (!Number.isSafeInteger(item.itemId) || item.itemId <= 0) {
          throw new Error(`记录 ${cursor} 缺少有效 item_id`);
        }
        item.count = Number(it['count'] ?? 1);
        item.rankType = Number(it['rank_type'] ?? 0);
        if (!Number.isSafeInteger(item.count) || item.count <= 0 || !Number.isInteger(item.rankType)
          || item.rankType < 3 || item.rankType > 5) {
          throw new Error(`记录 ${cursor} 的数量或星级无效`);
        }
        item.time = UigfService.normalizeTime(String(it['time'] ?? ''), timezone,
          UigfService.timezoneOfUid(uid));
        item.name = String((isUgc ? it['item_name'] : it['name']) ?? '');
        item.itemType = String(it['item_type'] ?? '');
        item.scheduleId = Number(it['schedule_id'] ?? 0);
        if (isUgc && (!Number.isSafeInteger(item.scheduleId) || item.scheduleId < 0)) {
          throw new Error(`记录 ${cursor} 的卡池期次无效`);
        }
        items.push(item);
      }
      pending.set(uid, items);
    }
  }

  private static itemKey(item: GachaItem): string {
    return `${GachaType.isBeyond(item.gachaType) ? 'b' : 's'}:${item.gachaId}`;
  }

  /** Windows InferRegionTimeZone：美服UTC-5、欧服UTC+1，其余UTC+8。 */
  static timezoneOfUid(uid: string): number {
    return uid.startsWith('6') ? -5 : (uid.startsWith('7') ? 1 : 8);
  }

  /** UIGF时间为entry.timezone当地时间；显式ISO偏移优先，并换算至归档服务器时区。 */
  static normalizeTime(value: string, sourceTimezone: number, targetTimezone: number): string {
    const match: RegExpMatchArray | null = value.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:?\d{2})?$/);
    if (match === null) {
      throw new Error(`无效的祈愿时间：${value}`);
    }
    const wall: number = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]),
      Number(match[4]), Number(match[5]), Number(match[6]));
    const check: Date = new Date(wall);
    if (check.getUTCFullYear() !== Number(match[1]) || check.getUTCMonth() + 1 !== Number(match[2])
      || check.getUTCDate() !== Number(match[3]) || Number(match[4]) > 23 || Number(match[5]) > 59
      || Number(match[6]) > 59) {
      throw new Error(`无效的祈愿日期：${value}`);
    }
    let offset: number = sourceTimezone;
    const zone: string = match[7] ?? '';
    if (zone === 'Z') {
      offset = 0;
    } else if (zone.length > 0) {
      const z: string = zone.replace(':', '');
      const hours: number = Number(z.substring(1, 3));
      const minutes: number = Number(z.substring(3, 5));
      if (hours > 14 || minutes > 59) {
        throw new Error('无效的ISO时区');
      }
      offset = (hours + minutes / 60) * (zone.startsWith('-') ? -1 : 1);
    }
    return new Date(wall + (targetTimezone - offset) * 3600000).toISOString().substring(0, 19).replace('T', ' ');
  }
}
