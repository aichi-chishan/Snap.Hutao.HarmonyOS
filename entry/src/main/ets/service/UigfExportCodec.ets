/** Version-aware projection of local records. Unsupported semantics cause an explicit refusal. */
import { GachaItem } from '../model/GachaItem';
import { GachaType } from '../model/GachaType';
import { UigfBounds } from '../model/UigfBounds';
import { UigfCodec } from './UigfCodec';

/** UIGF v4.x 常规池单条记录 */
class UigfItem {
  gacha_type: string = '';
  uigf_gacha_type: string = '';
  item_id: string = '';
  count: string = '1';
  time: string = '';
  name: string = '';
  item_type: string = '';
  rank_type: string = '';
  id: string = '';
}

/** UIGF v4.2 千星奇域（hk4e_ugc）单条记录（对齐 Windows Hk4eUGCItem） */
class UigfUgcItem {
  /** Keep non-unit quantities as an extension understood by the importer. */
  count: string = '1';
  id: string = '';
  schedule_id: string = '';
  item_type: string = '';
  item_id: string = '';
  item_name: string = '';
  rank_type: string = '';
  time: string = '';
  op_gacha_type: string = '';
}

/** UIGF 单存档 */
class UigfEntry {
  uid: number = 0;
  timezone: number = 0;
  lang?: string;
  list: UigfItem[] = [];
}

/** UIGF v4.2 千星奇域单存档 */
class UigfUgcEntry {
  uid: number = 0;
  timezone: number = 0;
  lang?: string;
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
  version: string = 'v4.2';
}

export class UigfExportCodec {
  /** Explicit version projection of already selected normalized local archives. */
  static build(archives: Map<string, GachaItem[]>, version: string, appVersion: string): string {
    if (UigfCodec.VERSIONS.indexOf(version) < 0) { throw new Error('不支持的 UIGF 导出版本'); }
    const legacy: boolean = !version.startsWith('v4.');
    if (archives.size === 0) { throw new Error('请至少选择一个 UID'); }
    if (archives.size > UigfBounds.MAX_ARCHIVES) { throw new Error('UIGF 最多导出 1024 个归档'); }
    if (legacy && archives.size !== 1) { throw new Error(`${version} 只能保存单个 UID，请只选择一个归档或使用 v4.2`); }
    let total: number = 0;
    const root: UigfRoot = new UigfRoot();
    root.info.export_timestamp = Math.floor(Date.now() / 1000);
    root.info.export_app = 'Snap.Hutao.HarmonyOS';
    root.info.export_app_version = appVersion;
    root.info.version = version;
    for (const uid of archives.keys()) {
      if (!/^[1-9][0-9]{8,9}$/.test(uid)) { throw new Error('无效的导出 UID'); }
      const items: GachaItem[] = archives.get(uid) ?? [];
      total += items.length;
      if (total > UigfBounds.MAX_ROWS) { throw new Error('UIGF 导出超过 262144 条记录限制'); }
      const entry: UigfEntry = new UigfEntry();
      const ugcEntry: UigfUgcEntry = new UigfUgcEntry();
      entry.uid = Number(uid) || 0;
      ugcEntry.uid = entry.uid;
      entry.timezone = UigfCodec.timezoneOfUid(uid);
      ugcEntry.timezone = entry.timezone;
      for (const it of items) {
        UigfExportCodec.checkRepresentable(it, version);
        if (it.uid.length > 0 && it.uid !== uid) { throw new Error('记录 UID 与导出归档不一致'); }
        if (UigfCodec.normalizeTime(it.time, entry.timezone, entry.timezone) !== it.time) { throw new Error('导出时间不是归档服务器的标准本地时间，不能保真导出'); }
        if (GachaType.isBeyond(it.gachaType)) {
          const u: UigfUgcItem = new UigfUgcItem();
          u.count = String(it.count);
          u.id = it.gachaId;
          u.schedule_id = String(it.scheduleId);
          u.item_type = it.itemType;
          u.item_id = String(it.itemId);
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
          u.item_id = String(it.itemId);
          u.count = String(it.count > 0 ? it.count : 1);
          u.time = it.time;
          u.name = it.name;
          u.item_type = it.itemType;
          u.rank_type = String(it.rankType);
          u.id = it.gachaId;
          entry.list.push(u);
        }
      }
      if (entry.list.length > 0 || items.length === 0) {
        root.hk4e.push(entry);
      }
      if (ugcEntry.list.length > 0) {
        root.hk4e_ugc.push(ugcEntry);
      }
    }
    if (legacy) {
      const single: UigfEntry = root.hk4e[0];
      const info: Record<string, Object> = {
        'uid': String(single.uid), 'uigf_version': version,
        'export_timestamp': root.info.export_timestamp,
        'export_time': UigfCodec.normalizeTime(new Date(root.info.export_timestamp * 1000).toISOString(), 0, single.timezone),
        'export_app': root.info.export_app, 'export_app_version': root.info.export_app_version
      };
      // v2.4 first introduced explicit timezone. Older formats infer it from UID.
      if (version === 'v2.4' || version === 'v3.0') { info['region_time_zone'] = single.timezone; }
      const legacyRoot: Record<string, Object> = { 'info': info, 'list': single.list };
      return UigfExportCodec.stringify(legacyRoot);
    }
    // hk4e_ugc is a v4.2 field even if its array is empty.
    const modernRoot: Record<string, Object> = { 'info': root.info, 'hk4e': root.hk4e };
    if (version === 'v4.2') { modernRoot['hk4e_ugc'] = root.hk4e_ugc; }
    return UigfExportCodec.stringify(modernRoot);
  }

  private static checkRepresentable(item: GachaItem, version: string): void {
    UigfCodec.validateItem(item);
    const allowed: string[] = ['id', 'archiveId', 'uid', 'gachaId', 'gachaType', 'itemId', 'count', 'time', 'name', 'itemType', 'rankType', 'scheduleId'];
    for (const key of Object.keys(item)) {
      if (allowed.indexOf(key) < 0) { throw new Error('记录包含未支持字段，无法保证无损导出'); }
    }
    if (item.name.length > UigfBounds.MAX_FIELD_UNITS || item.itemType.length > UigfBounds.MAX_FIELD_UNITS ||
      item.gachaId.length > UigfBounds.MAX_FIELD_UNITS) { throw new Error('UIGF 导出字段超过 4096 字符限制'); }
    if (version.startsWith('v4.') && item.gachaId.length > 19) { throw new Error(`${version} 标准记录 ID 最多 19 位，不能截断导出`); }
    if (GachaType.isBeyond(item.gachaType) && version !== 'v4.2') { throw new Error(`${version} 不支持颂愿记录，请使用 v4.2`); }
    if (!GachaType.isBeyond(item.gachaType) && item.scheduleId !== 0) { throw new Error('常规祈愿包含非零期次字段，UIGF 常规分区无法保留，已停止导出'); }
    if (version.startsWith('v2.') && item.gachaType === 500) { throw new Error(`${version} 不支持集录祈愿，请使用 v3.0 或以上版本`); }
    if (version === 'v2.2' && ((item.itemType !== '角色' && item.itemType !== '武器') || /[A-Za-z]/.test(item.name))) {
      throw new Error('v2.2 仅支持已知中文物品文本，无法确认此记录语言，请使用 v2.3 或以上版本');
    }
  }

  private static stringify(root: Record<string, Object>): string {
    const text: string = JSON.stringify(root, null, 2);
    if (text.length > UigfBounds.MAX_TEXT_UNITS) { throw new Error('UIGF 导出超过 32 Mi 字符限制'); }
    return text;
  }
}
