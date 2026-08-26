/**
 * CalculateService.ets
 * 养成计算：POST batch_compute（登录 cookie + DS Gen2/X4）。
 * avatar/list 为 GET；本工程先以角色接口数据（character/list）提供输入项。
 */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { DsSigner } from '../data/network/DsSigner';
import { CalBatchResult, CalAvatarConsume } from '../model/Calculate';
import { UserService } from './UserService';
import { AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'CalculateService';
const URL_BATCH: string = 'https://api-takumi.mihoyo.com/event/e20200928calculate/v3/batch_compute';

/** 批量计算单个角色的输入（对齐 Windows AvatarPromotionDelta） */
export class CalAvatarDelta {
  avatarId: number = 0;
  /** 当前等级 → 目标等级 */
  levelCurrent: number = 0;
  levelTarget: number = 1;
  /** 元素属性 id（角色接口 element_attr_id） */
  elementAttrId: number = 0;
  /** 技能（技能 id/当前/目标） */
  skills: CalSkillDelta[] = [];
  /** 武器（武器 id/当前/目标/突破） */
  weapon: CalWeaponDelta | undefined = undefined;
  /** 当前突破等级 */
  avatarPromoteLevel: number = 0;
}

/** 单个技能升级请求 */
export class CalSkillDelta {
  id: number = 0;
  levelCurrent: number = 0;
  levelTarget: number = 1;
}

/** 武器升级请求 */
export class CalWeaponDelta {
  id: number = 0;
  levelCurrent: number = 0;
  levelTarget: number = 1;
  /** 武器突破等级 */
  weaponPromoteLevel: number = 0;
}

export class CalculateService {
  private static instance: CalculateService = new CalculateService();

  static getInstance(): CalculateService {
    return CalculateService.instance;
  }

  /** 批量计算养成材料 */
  async batchCompute(deltas: CalAvatarDelta[]): Promise<CalBatchResult> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    const data: string = CalculateService.buildBody(deltas);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const b: string = DsSigner.sortQuery({});
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, data, b);
    const headers: Record<string, string> = {
      'DS': ds,
      'Cookie': user.gameRecordCookie(),
    };
    const resp: ApiResponse = await ApiClient.getInstance().postJson(URL_BATCH, data,
      HoyolabClient.merge(HoyolabClient.getBaseHeaders(), headers));
    if (resp.isRiskControl()) {
      throw new Error('被风控拦截，请稍后再试');
    }
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const result: CalBatchResult = CalBatchResult.fromJson(resp.data);
    Logger.info(TAG, `batchCompute items=${result.items.length} overall=${result.overallConsume.length}`);
    return result;
  }

  /** 构建 batch_compute 请求体 JSON */
  private static buildBody(deltas: CalAvatarDelta[]): string {
    const items: string[] = [];
    for (let i = 0; i < deltas.length; i++) {
      const d: CalAvatarDelta = deltas[i];
      const skills: string[] = [];
      for (let j = 0; j < d.skills.length; j++) {
        const s: CalSkillDelta = d.skills[j];
        skills.push(`{"id":${s.id},"level_current":${s.levelCurrent},"level_target":${s.levelTarget}}`);
      }
      let weapon: string = 'null';
      if (d.weapon !== undefined) {
        const w: CalWeaponDelta = d.weapon;
        weapon = `{"id":${w.id},"level_current":${w.levelCurrent},"level_target":${w.levelTarget},"weapon_promote_level":${w.weaponPromoteLevel}}`;
      }
      items.push('{"avatar_id":' + d.avatarId +
        ',"avatar_level_current":' + d.levelCurrent +
        ',"avatar_level_target":' + d.levelTarget +
        ',"element_attr_id":' + d.elementAttrId +
        ',"skill_list":[' + skills.join(',') + ']' +
        ',"weapon":' + weapon +
        ',"from_user_sync":true' +
        ',"avatar_promote_level":' + d.avatarPromoteLevel + '}');
    }
    return `{"items":[${items.join(',')}]}`;
  }
}
