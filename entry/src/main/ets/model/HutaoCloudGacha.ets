import { RegionUtil } from '../common/Constants';
import { GachaItem } from './GachaItem';
import { HutaoCloudJson } from './HutaoCloud';

export class HutaoCloudGacha {
  static readonly TYPES: number[] = [100, 200, 301, 302, 500, 1000, 2000];

  static queryType(type: number): number { return type === 400 ? 301 : type; }

  static offset(uid: string): number {
    const region: string = RegionUtil.regionOfUid(uid);
    if (region === 'os_usa') { return -5; }
    return region === 'os_euro' ? 1 : 8;
  }

  static isoTime(time: string, uid: string): string {
    if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(time)) {
      throw new Error('祈愿时间格式无效');
    }
    const offset: number = HutaoCloudGacha.offset(uid);
    const suffix: string = offset < 0 ? '-05:00' : (offset === 1 ? '+01:00' : '+08:00');
    return time.replace(' ', 'T') + suffix;
  }

  static localTime(iso: string, uid: string): string {
    const stamp: number = Date.parse(iso);
    if (!Number.isFinite(stamp)) { throw new Error('云祈愿时间无效'); }
    return new Date(stamp + HutaoCloudGacha.offset(uid) * 3600000).toISOString().substring(0, 19).replace('T', ' ');
  }

  static endIds(items: GachaItem[]): Record<string, string> {
    const ids: Record<string, string> = {};
    for (const type of HutaoCloudGacha.TYPES) { ids[String(type)] = '0'; }
    for (const item of items) {
      const type: string = String(HutaoCloudGacha.queryType(item.gachaType));
      if (!HutaoCloudJson.validId(item.gachaId) || ids[type] === undefined) { continue; }
      if (ids[type] === '0' || HutaoCloudJson.compareIds(item.gachaId, ids[type]) < 0) { ids[type] = item.gachaId; }
    }
    return ids;
  }

  static retrieveBody(uid: string, items: GachaItem[]): string {
    const ids: Record<string, string> = HutaoCloudGacha.endIds(items);
    const entries: string[] = [];
    for (const type of HutaoCloudGacha.TYPES) { entries.push(`"${type}":${ids[String(type)]}`); }
    return `{"Uid":${JSON.stringify(uid)},"EndIds":{${entries.join(',')}}}`;
  }

  static uploadBody(uid: string, items: GachaItem[]): string {
    const serialized: string[] = [];
    for (const item of items) {
      const queryType: number = HutaoCloudGacha.queryType(item.gachaType);
      if (!HutaoCloudJson.validId(item.gachaId) || HutaoCloudGacha.TYPES.indexOf(queryType) < 0 ||
        !Number.isInteger(item.itemId) || item.itemId <= 0) {
        throw new Error('祈愿包含无效 ID、卡池或物品编号，已取消上传');
      }
      serialized.push(`{"GachaType":${item.gachaType},"QueryType":${queryType},"ItemId":${item.itemId},` +
        `"Time":${JSON.stringify(HutaoCloudGacha.isoTime(item.time, uid))},"Id":${item.gachaId}}`);
    }
    return `{"Uid":${JSON.stringify(uid)},"Items":[${serialized.join(',')}]}`;
  }

  static parseItem(raw: Object, uid: string): GachaItem {
    const data: Record<string, Object> = raw as Record<string, Object>;
    const item: GachaItem = new GachaItem();
    item.uid = uid;
    item.gachaId = String(HutaoCloudJson.field(data, 'Id') ?? '');
    item.gachaType = Number(HutaoCloudJson.field(data, 'GachaType') ?? 0);
    item.itemId = Number(HutaoCloudJson.field(data, 'ItemId') ?? 0);
    item.time = HutaoCloudGacha.localTime(String(HutaoCloudJson.field(data, 'Time') ?? ''), uid);
    if (!HutaoCloudJson.validId(item.gachaId) || item.itemId <= 0 ||
      HutaoCloudGacha.TYPES.indexOf(HutaoCloudGacha.queryType(item.gachaType)) < 0) {
      throw new Error('云祈愿数据结构无效，未写入本地');
    }
    return item;
  }
}
