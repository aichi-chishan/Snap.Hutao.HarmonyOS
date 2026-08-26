/**
 * CharacterService.ets
 * 角色资料：POST character/list（列表）+ character/detail（详情），DS Gen2/X4，Cookie(cookie_token+ltoken)。
 * 参考 Windows 版 GameRecordClient.GetCharacterListAsync/GetCharacterDetailAsync（CN）。
 */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { DsSigner } from '../data/network/DsSigner';
import { RiskVerifier, RiskControlError } from '../data/network/RiskVerifier';
import { CharacterListItem, CharacterDetail, ListWeapon, DetailedWeapon, Reliquary, Constellation, BaseProperty, RelicProperty, RecommendRelic } from '../model/CharacterData';
import { WikiMetaService } from './WikiMetaService';
import { UserService } from './UserService';
import { RegionUtil, AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';

const TAG: string = 'CharacterService';
const LIST_URL: string = 'https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/character/list';
const DETAIL_URL: string = 'https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/character/detail';
/** -502 限流退避重试次数 */
const RETRY_TIMES: number = 3;

export class CharacterService {
  private static instance: CharacterService = new CharacterService();

  static getInstance(): CharacterService {
    return CharacterService.instance;
  }

  /** 角色列表
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头） */
  async fetchList(uid: string, challenge?: string): Promise<CharacterListItem[]> {
    const body: Record<string, Object> = { 'role_id': uid, 'server': RegionUtil.regionOfUid(uid), 'sort_type': 1 };
    const resp: ApiResponse = await this.postJson(LIST_URL, body, challenge);
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const obj = resp.data as Record<string, Object>;
    const list = obj['list'] as Array<Object>;
    const items: CharacterListItem[] = [];
    if (list !== undefined && list !== null) {
      for (let i = 0; i < list.length; i++) {
        items.push(this.parseListItem(list[i]));
      }
    }
    Logger.info(TAG, `characters count=${items.length}`);
    return items;
  }

  /** 角色详情（批量 ids）
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头）
   *  注意：character_ids 必须是数字数组（JSON 序列化后 [10000130]）；若发字符串 "[..]" 会被米哈游判为非法 → -502 */
  async fetchDetail(uid: string, ids: number[], challenge?: string): Promise<CharacterDetail[]> {
    const body: Record<string, Object> = {
      'role_id': uid,
      'server': RegionUtil.regionOfUid(uid),
      'sort_type': 1,
      'character_ids': ids,
    };
    const resp: ApiResponse = await CharacterService.withBackoff(
      () => this.postJson(DETAIL_URL, body, challenge), RETRY_TIMES);
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const obj = resp.data as Record<string, Object>;
    const list = obj['list'] as Array<Object>;
    const details: CharacterDetail[] = [];
    if (list !== undefined && list !== null) {
      for (let i = 0; i < list.length; i++) {
        details.push(this.parseDetail(list[i]));
      }
    }
    Logger.info(TAG, `characters detail count=${details.length}`);
    return details;
  }

  /** -502/-503 退避重试（米哈游对 detail 接口有瞬时限流，等待后可恢复） */
  private static async withBackoff(task: () => Promise<ApiResponse>, times: number): Promise<ApiResponse> {
    let resp: ApiResponse | undefined = undefined;
    for (let i = 0; i < times; i++) {
      resp = await task();
      if (resp.retcode === -502 || resp.retcode === -503 || resp.retcode === -500) {
        Logger.warn(TAG, `detail retry ${i + 1}/${times} retcode=${resp.retcode}`);
        await new Promise<void>((resolve) => {
          setTimeout(() => resolve(), 2000 * (i + 1));
        });
        continue;
      }
      break;
    }
    return resp ?? new ApiResponse();
  }

  /** POST JSON + DS Gen2/X4 + Cookie（含 1034 风控极验重放链）。
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头） */
  private async postJson(url: string, body: Record<string, Object>, challenge?: string): Promise<ApiResponse> {
    const user = UserService.getInstance().getCurrentUser();
    if (user === undefined || !user.hasCookie()) {
      throw new Error('请先登录');
    }
    // 确保设备指纹就绪（passport token 交换需 x-rpc-device_fp；缺 fp 会补不上 cookie_token → 战绩全挂）
    try {
      await UserService.getInstance().ensureDeviceFingerprintPublic();
    } catch (e) {
      Logger.warn(TAG, 'ensure fp fail on postJson');
    }
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(user);
    }
    const cookie: string = user.gameRecordCookie();
    if (cookie.length === 0) {
      throw new Error('账号缺少 cookie_token，请重新登录');
    }
    const bodyJson: string = JSON.stringify(body);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, t, r, bodyJson, '');
    const headers: Record<string, string> = { 'DS': ds, 'Cookie': cookie };
    if (challenge !== undefined && challenge.length > 0) {
      headers['x-rpc-challenge'] = challenge;
    }
    const resp: ApiResponse = await ApiClient.getInstance().postJson(url, bodyJson,
      HoyolabClient.merge(HoyolabClient.getBaseHeaders(), headers));
    if (resp.isRiskControl()) {
      // 1034：注册极验并抛异常（页面捕获后跳验证页完成；再次调用带 challenge 重放）
      await RiskVerifier.checkForRisk(resp, cookie, url);
    }
    return resp;
  }

  private parseListItem(obj: Object): CharacterListItem {
    const item = obj as Record<string, Object>;
    const c: CharacterListItem = new CharacterListItem();
    c.id = CharacterService.num(item['id']);
    c.name = String(item['name'] ?? '');
    c.element = String(item['element'] ?? '');
    c.fetter = CharacterService.num(item['fetter']);
    c.level = CharacterService.num(item['level']);
    c.rarity = CharacterService.num(item['rarity']);
    c.weaponType = CharacterService.num(item['weapon_type']);
    c.activedConstellationNum = CharacterService.num(item['actived_constellation_num']);
    // 官方头像：接口 avatar_icon 为图标名（UI_AvatarIcon_xxx）；未提供时回退本地元数据 icon（供 MetaIcon rawfile 渲染）
    const iconText: string = String(item['avatar_icon'] ?? '');
    c.icon = CharacterService.iconNameOf(iconText);
    if (c.icon.length === 0) {
      // 注意：Enka CDN 是 UI_AvatarIcon_{名字}.png（非数字 id），数字 id 拼 URL 必然 404 → 一律用本地元数据映射
      c.icon = WikiMetaService.iconOfAvatar(c.id);
    }
    const w = item['weapon'] as Record<string, Object>;
    if (w !== undefined && w !== null) {
      c.weapon.id = CharacterService.num(w['id']);
      c.weapon.type = CharacterService.num(w['type']);
      c.weapon.rarity = CharacterService.num(w['rarity']);
      c.weapon.level = CharacterService.num(w['level']);
      c.weapon.affixLevel = CharacterService.num(w['affix_level']);
    }
    return c;
  }

  /**
   * 提取图标名：`avatar_icon` 可能是 "UI_AvatarIcon_xxx"、"UI_AvatarIcon_xxx.png"、
   * 完整 URL（https://.../UI_AvatarIcon_xxx.png）或相对路径。返回纯名（无扩展名）。
   * 若无法提取（非 UI_AvatarIcon 命名），返回原输入（调用方按 URL 处理）。
   */
  static iconNameOf(v: string): string {
    if (v.length === 0) {
      return '';
    }
    let s: string = v;
    const slash: number = s.lastIndexOf('/');
    if (slash >= 0) {
      s = s.substring(slash + 1);
    }
    if (s.endsWith('.png')) {
      s = s.substring(0, s.length - 4);
    }
    // 以 UI_AvatarIcon 开头视为图标名（rawfile 可用）；否则视为 URL 原样返回
    if (s.startsWith('UI_AvatarIcon_') || s.startsWith('UI_AvatarIconCircle_')) {
      return s;
    }
    return v;
  }

  private parseDetail(obj: Object): CharacterDetail {
    const item = obj as Record<string, Object>;
    const d: CharacterDetail = new CharacterDetail();
    // base 嵌套
    const base = item['base'] as Record<string, Object>;
    if (base !== undefined && base !== null) {
      d.id = CharacterService.num(base['id']);
      d.name = String(base['name'] ?? '');
      d.element = String(base['element'] ?? '');
      d.level = CharacterService.num(base['level']);
      d.rarity = CharacterService.num(base['rarity']);
      d.fetter = CharacterService.num(base['fetter']);
      d.activedConstellationNum = CharacterService.num(base['actived_constellation_num']);
      const detailIcon: string = String(base['avatar_icon'] ?? '');
      d.icon = detailIcon.length > 0 ? CharacterService.iconNameOf(detailIcon)
        : WikiMetaService.iconOfAvatar(d.id);
    } else {
      // 兜底：可能平铺
      d.id = CharacterService.num(item['id']);
      d.name = String(item['name'] ?? '');
      d.element = String(item['element'] ?? '');
      d.level = CharacterService.num(item['level']);
      d.rarity = CharacterService.num(item['rarity']);
    }
    const w = item['weapon'] as Record<string, Object>;
    if (w !== undefined && w !== null) {
      d.weapon.id = CharacterService.num(w['id']);
      d.weapon.type = CharacterService.num(w['type']);
      d.weapon.rarity = CharacterService.num(w['rarity']);
      d.weapon.level = CharacterService.num(w['level']);
      d.weapon.affixLevel = CharacterService.num(w['affix_level']);
      d.weapon.promoteLevel = CharacterService.num(w['promote_level']);
    }
    const relics = item['relics'] as Array<Object>;
    if (relics !== undefined && relics !== null) {
      for (let i = 0; i < relics.length; i++) {
        d.reliquaries.push(this.parseReliquary(relics[i]));
      }
    }
    const cons = item['constellations'] as Array<Object>;
    if (cons !== undefined && cons !== null) {
      for (let i = 0; i < cons.length; i++) {
        const c = cons[i] as Record<string, Object>;
        const cell: Constellation = new Constellation();
        cell.id = CharacterService.num(c['id']);
        cell.name = String(c['name'] ?? '');
        cell.icon = String(c['icon'] ?? '');
        cell.effect = WikiMetaService.cleanText(String(c['effect'] ?? ''));
        cell.isActived = c['is_actived'] === true;
        cell.pos = CharacterService.num(c['pos']);
        d.constellations.push(cell);
      }
    }
    const props = item['selected_properties'] as Array<Object>;
    if (props !== undefined && props !== null) {
      for (let i = 0; i < props.length; i++) {
        const p = props[i] as Record<string, Object>;
        const bp: BaseProperty = new BaseProperty();
        bp.propertyType = String(p['property_type'] ?? '');
        bp.base = String(p['base'] ?? '');
        bp.add = String(p['add'] ?? '');
        bp.final = String(p['final'] ?? '');
        d.selectedProperties.push(bp);
      }
    }
    // 推荐圣遗物词条（Windows 评分权重依据）
    const rec = item['recommend_relic_property'] as Record<string, Object>;
    if (rec !== undefined && rec !== null) {
      const subProps = rec['recommend_properties'] as Record<string, Object>;
      if (subProps !== undefined && subProps !== null) {
        const list = subProps['sub_property_list'] as Array<Object>;
        if (list !== undefined && list !== null) {
          for (let i = 0; i < list.length; i++) {
            d.recommend.subProperties.push(String(list[i]));
          }
        }
      }
      d.recommend.energyType = String(rec['special_energy_type'] ?? 'NONE');
    }
    return d;
  }

  private parseReliquary(obj: Object): Reliquary {
    const item = obj as Record<string, Object>;
    const r: Reliquary = new Reliquary();
    r.id = CharacterService.num(item['id']);
    r.name = String(item['name'] ?? '');
    r.icon = String(item['icon'] ?? '');
    r.pos = CharacterService.num(item['pos']);
    r.rarity = CharacterService.num(item['rarity']);
    r.level = CharacterService.num(item['level']);
    r.posName = String(item['pos_name'] ?? '');
    const main = item['main_property'] as Record<string, Object>;
    if (main !== undefined && main !== null) {
      r.mainProperty.propertyType = String(main['property_type'] ?? '');
      r.mainProperty.value = String(main['value'] ?? '');
    }
    const subs = item['sub_property_list'] as Array<Object>;
    if (subs !== undefined && subs !== null) {
      for (let i = 0; i < subs.length; i++) {
        const s = subs[i] as Record<string, Object>;
        const sp: RelicProperty = new RelicProperty();
        sp.propertyType = String(s['property_type'] ?? '');
        sp.value = String(s['value'] ?? '');
        sp.times = CharacterService.num(s['times']);
        r.subProperties.push(sp);
      }
    }
    return r;
  }

  private static num(v: Object): number {
    if (v === undefined || v === null) {
      return 0;
    }
    const n: number = Number(v);
    return Number.isNaN(n) ? 0 : n;
  }
}
