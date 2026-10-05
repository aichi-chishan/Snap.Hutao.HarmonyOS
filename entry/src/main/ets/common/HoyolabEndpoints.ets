import { AppConstants, RegionUtil } from './Constants';

/** Protocol routing from upstream ApiEndpoints.csv; account and game regions stay explicit. */
export class HoyolabEndpoints {
  static readonly REGIONS: string[] = ['cn_gf01', 'cn_qd01', 'os_usa', 'os_euro', 'os_asia', 'os_cht'];

  static requireRegion(region: string): void {
    if (!HoyolabEndpoints.REGIONS.includes(region)) { throw new Error('请选择有效的游戏区服'); }
  }

  static ledgerUrl(region: string): string {
    HoyolabEndpoints.requireRegion(region);
    return HoyolabEndpoints.isOverseaRegion(region)
      ? 'https://sg-hk4e-api.hoyolab.com/event/ysledgeros/month_info'
      : 'https://hk4e-api.mihoyo.com/event/ys_ledger/monthInfo';
  }

  static announcementUrl(path: string, region: string): string {
    HoyolabEndpoints.requireRegion(region);
    if (path !== 'getAnnList' && path !== 'getAnnContent') { throw new Error('公告接口无效'); }
    return HoyolabEndpoints.isOverseaRegion(region)
      ? `https://sg-hk4e-api.hoyoverse.com/common/hk4e_global/announcement/api/${path}`
      : `https://hk4e-ann-api.mihoyo.com/common/hk4e_cn/announcement/api/${path}`;
  }

  static isOverseaRegion(region: string): boolean {
    return RegionUtil.isOverseaRegion(region);
  }

  static gameBiz(region: string): string {
    return HoyolabEndpoints.isOverseaRegion(region) ? 'hk4e_global' : 'hk4e_cn';
  }

  static gameRecordUrl(path: string, region: string): string {
    if (HoyolabEndpoints.isOverseaRegion(region)) {
      if (path.startsWith('role_combat') || path.startsWith('hard_challenge')) {
        return `https://sg-public-api.hoyolab.com/event/game_record/genshin/api/${path}`;
      }
      return `https://bbs-api-os.hoyolab.com/game_record/app/genshin/api/${path}`;
    }
    return `https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/${path}`;
  }

  static gameRecordSalt(region: string): string {
    return HoyolabEndpoints.isOverseaRegion(region) ? AppConstants.DS_SALT_OS_X4 : AppConstants.DS_SALT_X4;
  }

  static signActId(region: string): string {
    return HoyolabEndpoints.isOverseaRegion(region) ? 'e202102251931481' : AppConstants.SIGN_ACT_ID;
  }

  static signUrl(path: string, region: string): string {
    return HoyolabEndpoints.isOverseaRegion(region)
      ? `https://sg-hk4e-api.hoyoverse.com/event/sol/${path}`
      : `https://api-takumi.mihoyo.com/event/luna/${path}`;
  }

  static signSalt(region: string): string {
    return HoyolabEndpoints.isOverseaRegion(region) ? AppConstants.DS_SALT_OS_LK2 : AppConstants.DS_SALT_LK2;
  }
}
