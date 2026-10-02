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
import { RiskVerifier } from '../data/network/RiskVerifier';
import { AppConstants, RegionUtil } from '../common/Constants';
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
    const resp0: ApiResponse = await ApiClient.getInstance().postJson(URL_BATCH, data,
      HoyolabClient.merge(HoyolabClient.getBaseHeaders(), headers));
    let resp: ApiResponse = resp0;
    if (resp0.isRiskControl()) {
      // 1034：自动弹统一验证窗，成功后带 challenge 服务内重放一次
      const replayChallenge: string = await RiskVerifier.tryResolveRisk(resp0, user.gameRecordCookie(), URL_BATCH);
      if (replayChallenge.length === 0) {
        throw new Error('人机验证未完成或被取消，请稍后再试');
      }
      headers['x-rpc-challenge'] = replayChallenge;
      resp = await ApiClient.getInstance().postJson(URL_BATCH, data,
        HoyolabClient.merge(HoyolabClient.getBaseHeaders(), headers));
    }
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const result: CalBatchResult = CalBatchResult.fromJson(resp.data);
    Logger.info(TAG, `batchCompute items=${result.items.length} overall=${result.overallConsume.length}`);
    return result;
  }

  /** 计算器补充战绩接口缺失的准确突破等级，绝不把未知突破当0。 */
  async fetchPromoteLevels(uid: string): Promise<Map<number, number>> {
    const levels: Map<number, number> = new Map<number, number>();
    for (let page: number = 1; page <= 50; page++) {
      const body: Record<string, Object> = {
        'uid': uid, 'region': RegionUtil.regionOfUid(uid), 'page': page, 'size': 20,
        'element_attr_ids': [], 'weapon_cat_ids': []
      };
      const data: Record<string, Object> = await this.requestCalculator('/v1/sync/avatar/list', JSON.stringify(body));
      const list: Record<string, Object>[] = (data['list'] as Record<string, Object>[]) ?? [];
      for (const item of list) {
        const promote: number = Number(item['promote_level']);
        const id: number = Number(item['id']);
        if (Number.isSafeInteger(id) && id > 0 && Number.isInteger(promote) && promote >= 0 && promote <= 6) {
          levels.set(id, promote);
        }
      }
      if (list.length < 20) {
        return levels;
      }
    }
    throw new Error('计算器角色分页超出限制');
  }

  /** 使用计算器技能ID及不含命座加成的等级，避免按数组位置猜测天赋。 */
  async fillSyncedDetails(uid: string, delta: CalAvatarDelta, skillTarget: number,
    weaponTarget: number = 0): Promise<void> {
    const path: string = `/v1/sync/avatar/detail?avatar_id=${delta.avatarId}&uid=${uid}&region=${RegionUtil.regionOfUid(uid)}`;
    const data: Record<string, Object> = await this.requestCalculator(path);
    const raw: Record<string, Object>[] = (data['skill_list'] as Record<string, Object>[]) ?? [];
    delta.skills = [];
    for (const item of raw) {
      const current: number = Number(item['level_current']);
      if (!Number.isInteger(current) || current < 1 || current > 10) {
        continue;
      }
      const skill: CalSkillDelta = new CalSkillDelta();
      skill.id = Number(item['id']);
      skill.levelCurrent = current;
      skill.levelTarget = Math.max(current, skillTarget);
      delta.skills.push(skill);
    }
    if (skillTarget > 0 && delta.skills.length === 0) {
      throw new Error('未能取得准确天赋等级，未计算不完整的养成材料');
    }
    if (weaponTarget > 0) {
      const weapon: Record<string, Object> = data['weapon'] as Record<string, Object>;
      if (weapon !== undefined && weapon !== null) {
        const item: CalWeaponDelta = new CalWeaponDelta();
        item.id = Number(weapon['id']);
        item.levelCurrent = Number(weapon['level_current']);
        const maxLevel: number = Number(weapon['max_level'] ?? 90);
        item.levelTarget = Math.max(item.levelCurrent, Math.min(weaponTarget, maxLevel));
        // 同等级卡在突破关口时，API无promote_level则要求上游详情提供，不臆造已突破。
        const rawPromote: Object | undefined = weapon['promote_level'];
        if (rawPromote !== undefined) {
          item.weaponPromoteLevel = Number(rawPromote);
        } else if ([20, 40, 50, 60, 70, 80].indexOf(item.levelCurrent) >= 0) {
          throw new Error('武器正处于突破等级，但接口未提供突破状态；请在图鉴单独计算该武器');
        } else {
          item.weaponPromoteLevel = [20, 40, 50, 60, 70, 80]
            .filter((level: number): boolean => level < item.levelCurrent).length;
        }
        delta.weapon = item;
      }
    }
  }

  private async requestCalculator(path: string, body?: string): Promise<Record<string, Object>> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('同步养成等级需要登录');
    }
    const host: string = user.isOversea ? 'https://sg-public-api.hoyolab.com/event/e20200928calculate'
      : 'https://api-takumi.mihoyo.com/event/e20200928calculate';
    const url: string = host + path;
    const headers: Record<string, string> = HoyolabClient.merge(HoyolabClient.getBaseHeaders(), {
      'Cookie': user.gameRecordCookie(),
      'Referer': user.isOversea ? 'https://act.hoyolab.com/' : 'https://webstatic.mihoyo.com/'
    });
    let response: ApiResponse = body === undefined ? await ApiClient.getInstance().get(url, headers)
      : await ApiClient.getInstance().postJson(url, body, headers);
    if (response.isRiskControl()) {
      const challenge: string = await RiskVerifier.tryResolveRisk(response, user.gameRecordCookie(), url);
      if (challenge.length === 0) {
        throw new Error('人机验证未完成');
      }
      headers['x-rpc-challenge'] = challenge;
      response = body === undefined ? await ApiClient.getInstance().get(url, headers)
        : await ApiClient.getInstance().postJson(url, body, headers);
    }
    if (!response.success || response.data === undefined) {
      throw new Error(response.userFriendlyMessage());
    }
    return response.data as Record<string, Object>;
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
