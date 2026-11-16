/**
 * CharacterService.ets
 * 角色资料：POST character/list（列表）+ character/detail（详情），DS Gen2/X4，Cookie(cookie_token+ltoken)。
 * 参考 Windows 版 GameRecordClient.GetCharacterListAsync/GetCharacterDetailAsync（CN）。
 */
import { ApiClient } from '../data/network/ApiClient';
import { ApiResponse } from '../model/ApiResponse';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { DsSigner } from '../data/network/DsSigner';
import { RiskVerifier } from '../data/network/RiskVerifier';
import { CharacterListItem, CharacterDetail, ListWeapon, DetailedWeapon, Reliquary, Constellation, BaseProperty, RelicProperty, RecommendRelic, AvatarSkill } from '../model/CharacterData';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { WikiMetaService } from './WikiMetaService';
import { UserService } from './UserService';
import { RegionUtil } from '../common/Constants';
import { HoyolabEndpoints } from '../common/HoyolabEndpoints';
import { Logger } from '../common/Logger';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { PromoteState } from '../model/PromoteState';

const TAG: string = 'CharacterService';
/** -502 限流退避重试次数 */
const RETRY_TIMES: number = 3;
const DETAIL_BATCH_SIZE: number = 20;

class CharacterRequest {
  readonly uid: string;
  readonly region: string;
  readonly user: User;
  readonly isCurrent: () => boolean;

  constructor(uid: string, region: string, user: User, isCurrent: () => boolean) {
    this.uid = uid;
    this.region = region;
    this.user = user;
    this.isCurrent = isCurrent;
  }

  assertCurrent(): void {
    if (!this.isCurrent()) { throw new Error('账号或角色已切换，请重新刷新'); }
  }
}

/** Pending raw entries and IDs already committed by a newer overlapping detail request. */
class CharacterDetailWrite {
  readonly uid: string;
  readonly raw: Map<number, Object> = new Map<number, Object>();
  readonly superseded: Set<number> = new Set<number>();

  constructor(uid: string) { this.uid = uid; }
}

export class CharacterService {
  private static instance: CharacterService = new CharacterService();
  private detailWrites: CharacterDetailWrite[] = [];

  static getInstance(): CharacterService {
    return CharacterService.instance;
  }

  /** 持久缓存按游戏 UID 隔离；保留原始响应以通过同一解析器重建嵌套模型。 */
  getCachedList(uid: string): CharacterListItem[] {
    try {
      const raw: Object[] = this.readCached(uid, false);
      const items: CharacterListItem[] = [];
      for (const item of raw) {
        const parsed: CharacterListItem = this.parseListItem(item);
        if (!Number.isSafeInteger(parsed.id) || parsed.id <= 0) {
          return [];
        }
        items.push(parsed);
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  getCachedDetails(uid: string): CharacterDetail[] {
    try {
      const raw: Object[] = this.readCached(uid, true);
      const items: CharacterDetail[] = [];
      for (const item of raw) {
        const parsed: CharacterDetail = this.parseDetail(item);
        if (!Number.isSafeInteger(parsed.id) || parsed.id <= 0) {
          return [];
        }
        items.push(parsed);
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  private readCached(uid: string, detail: boolean): Object[] {
    if (!/^\d+$/.test(uid)) {
      return [];
    }
    try {
      const key: string = detail ? `character.details.${uid}` : `character.list.${uid}`;
      const parsed: Object = JSON.parse(PreferencesStore.getString(key, '[]')) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const items: Object[] = parsed as Object[];
      for (const item of items) {
        if (item === null || typeof item !== 'object' || Array.isArray(item)) {
          return [];
        }
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  private beginRequest(uid: string, caller?: () => boolean): CharacterRequest {
    const region: string = RegionUtil.regionOfUid(uid);
    if (!/^\d+$/.test(uid) || region.length === 0) { throw new Error('请选择有效的游戏 UID'); }
    const service: UserService = UserService.getInstance();
    const user: User | undefined = service.getCurrentUser();
    if (user === undefined || !user.hasCookie()) { throw new Error('请先登录'); }
    if (!user.roles.some((role: UserGameRole): boolean => role.gameUid === uid && role.region === region)) {
      throw new Error('当前账号未绑定该游戏 UID');
    }
    const revision: number = service.sessionRevision();
    const request: CharacterRequest = new CharacterRequest(uid, region, user, (): boolean =>
      service.sessionRevision() === revision && service.getCurrentUser() === user && (caller?.() ?? true));
    request.assertCurrent();
    return request;
  }

  private beginDetailWrite(uid: string): CharacterDetailWrite {
    const write: CharacterDetailWrite = new CharacterDetailWrite(uid);
    this.detailWrites.push(write);
    return write;
  }

  private finishDetailWrite(request: CharacterRequest, write: CharacterDetailWrite): void {
    const index: number = this.detailWrites.indexOf(write);
    try {
      if (!request.isCurrent()) { return; }
      const accepted: Map<number, Object> = new Map<number, Object>();
      for (const id of write.raw.keys()) {
        const item: Object | undefined = write.raw.get(id);
        if (item !== undefined && !write.superseded.has(id)) { accepted.set(id, item); }
      }
      if (accepted.size === 0) { return; }
      const merged: Map<number, Object> = new Map<number, Object>();
      for (const item of this.readCached(write.uid, true)) {
        try {
          const id: number = this.parseDetail(item).id;
          if (Number.isSafeInteger(id) && id > 0) {
            merged.set(id, item);
          }
        } catch (e) {
          // 损坏的旧条目不阻碍本次成功批次修复缓存。
          continue;
        }
      }
      accepted.forEach((item: Object, id: number): void => { merged.set(id, item); });
      if (!request.isCurrent()) { return; }
      PreferencesStore.setString(`character.details.${write.uid}`, JSON.stringify(Array.from(merged.values())));
      for (let i: number = 0; i < index; i++) {
        const pending: CharacterDetailWrite = this.detailWrites[i];
        if (pending.uid !== write.uid) { continue; }
        for (const id of accepted.keys()) { pending.superseded.add(id); }
      }
    } catch (e) {
      // 缓存不可用不影响本次成功的网络结果，也不清除既有快照。
      Logger.warn(TAG, 'character cache write failed');
    } finally {
      if (index >= 0) { this.detailWrites.splice(index, 1); }
    }
  }

  /** 角色列表
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头） */
  async fetchList(uid: string, challenge?: string, isCurrent?: () => boolean): Promise<CharacterListItem[]> {
    const request: CharacterRequest = this.beginRequest(uid, isCurrent);
    const body: Record<string, Object> = { 'role_id': uid, 'server': request.region, 'sort_type': 1 };
    const resp: ApiResponse = await this.postJson(request, HoyolabEndpoints.gameRecordUrl('character/list', request.region), body, challenge);
    request.assertCurrent();
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const obj = resp.data as Record<string, Object>;
    if (!Array.isArray(obj['list'])) {
      throw new Error('角色列表响应不完整，已保留本地缓存');
    }
    const list: Object[] = obj['list'] as Object[];
    const items: CharacterListItem[] = [];
    if (list !== undefined && list !== null) {
      for (let i = 0; i < list.length; i++) {
        const item: CharacterListItem = this.parseListItem(list[i]);
        if (!Number.isSafeInteger(item.id) || item.id <= 0) {
          throw new Error('角色列表包含无效条目，已保留本地缓存');
        }
        items.push(item);
      }
    }
    Logger.info(TAG, `characters count=${items.length}`);
    request.assertCurrent();
    try { PreferencesStore.setString(`character.list.${uid}`, JSON.stringify(list)); }
    catch (e) { Logger.warn(TAG, 'character cache write failed'); }
    return items;
  }

  /** 角色详情（批量 ids）
   *  @param challenge 可选：极验通过后的 x-rpc-challenge（重放头）
   *  注意：character_ids 必须是数字数组（JSON 序列化后 [10000130]）；若发字符串 "[..]" 会被米哈游判为非法 → -502 */
  async fetchDetail(uid: string, ids: number[], challenge?: string, isCurrent?: () => boolean): Promise<CharacterDetail[]> {
    if (!/^\d+$/.test(uid)) { throw new Error('请选择有效的游戏 UID'); }
    if (ids.length === 0) { return []; }
    const request: CharacterRequest = this.beginRequest(uid, isCurrent);
    const write: CharacterDetailWrite = this.beginDetailWrite(uid);
    try {
      const details: CharacterDetail[] = await this.fetchDetailBatch(request, ids.slice(), write, challenge);
      request.assertCurrent();
      return details;
    } finally {
      this.finishDetailWrite(request, write);
    }
  }

  /** Publish each successful batch, then merge the completed prefix once at the request boundary. */
  async fetchDetailBatches(uid: string, ids: number[], onBatch: (details: CharacterDetail[]) => void,
    isCurrent: () => boolean, challenge?: string): Promise<void> {
    if (!/^\d+$/.test(uid)) { throw new Error('请选择有效的游戏 UID'); }
    if (ids.length === 0) { return; }
    const request: CharacterRequest = this.beginRequest(uid, isCurrent);
    const write: CharacterDetailWrite = this.beginDetailWrite(uid);
    const pendingIds: number[] = ids.slice();
    try {
      for (let i: number = 0; i < pendingIds.length; i += DETAIL_BATCH_SIZE) {
        const details: CharacterDetail[] = await this.fetchDetailBatch(request,
          pendingIds.slice(i, i + DETAIL_BATCH_SIZE), write, challenge);
        request.assertCurrent();
        onBatch(details.filter((detail: CharacterDetail): boolean => !write.superseded.has(detail.id)));
      }
      request.assertCurrent();
    } finally {
      this.finishDetailWrite(request, write);
    }
  }

  private async fetchDetailBatch(request: CharacterRequest, ids: number[], write: CharacterDetailWrite,
    challenge?: string): Promise<CharacterDetail[]> {
    const body: Record<string, Object> = {
      'role_id': request.uid,
      'server': request.region,
      'sort_type': 1,
      'character_ids': ids,
    };
    const url: string = HoyolabEndpoints.gameRecordUrl('character/detail', request.region);
    const resp: ApiResponse = await CharacterService.withBackoff(
      () => this.postJson(request, url, body, challenge), RETRY_TIMES, request);
    request.assertCurrent();
    if (!resp.success || resp.data === undefined) {
      throw new Error(resp.userFriendlyMessage());
    }
    const obj = resp.data as Record<string, Object>;
    if (!Array.isArray(obj['list'])) {
      throw new Error('角色详情响应不完整，已保留本地缓存');
    }
    const list: Object[] = obj['list'] as Object[];
    const details: CharacterDetail[] = [];
    for (const item of list) {
      const detail: CharacterDetail = this.parseDetail(item);
      if (!Number.isSafeInteger(detail.id) || detail.id <= 0 || !ids.includes(detail.id)) {
        throw new Error('角色详情包含无效条目，已保留本地缓存');
      }
      details.push(detail);
    }
    for (let i: number = 0; i < details.length; i++) { write.raw.set(details[i].id, list[i]); }
    Logger.info(TAG, `characters detail count=${details.length}`);
    return details;
  }

  /** -502/-503 退避重试（米哈游对 detail 接口有瞬时限流，等待后可恢复） */
  private static async withBackoff(task: () => Promise<ApiResponse>, times: number, request: CharacterRequest): Promise<ApiResponse> {
    let resp: ApiResponse | undefined = undefined;
    for (let i: number = 0; i < times; i++) {
      request.assertCurrent();
      resp = await task();
      request.assertCurrent();
      if (i + 1 < times && (resp.retcode === -502 || resp.retcode === -503 || resp.retcode === -500)) {
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
  private async postJson(request: CharacterRequest, url: string, body: Record<string, Object>, challenge?: string): Promise<ApiResponse> {
    request.assertCurrent();
    const user: User = request.user;
    // 确保设备指纹就绪（passport token 交换需 x-rpc-device_fp；缺 fp 会补不上 cookie_token → 战绩全挂）
    try {
      await UserService.getInstance().ensureDeviceFingerprintPublic();
    } catch (e) {
      Logger.warn(TAG, 'ensure fp fail on postJson');
    }
    request.assertCurrent();
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(user);
      request.assertCurrent();
    }
    const bodyJson: string = JSON.stringify(body);
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomNumber();
    const ds: string = await DsSigner.signGen2(HoyolabEndpoints.gameRecordSalt(request.region), t, r, bodyJson, '');
    request.assertCurrent();
    const cookie: string = user.gameRecordCookie();
    if (cookie.length === 0) { throw new Error('账号缺少 cookie_token，请重新登录'); }
    const headers: Record<string, string> = { 'DS': ds, 'Cookie': cookie };
    if (challenge !== undefined && challenge.length > 0) {
      headers['x-rpc-challenge'] = challenge;
    }
    const resp0: ApiResponse = await ApiClient.getInstance().postJson(url, bodyJson,
      HoyolabClient.merge(HoyolabClient.getBaseHeaders(request.region), headers));
    request.assertCurrent();
    let resp: ApiResponse = resp0;
    if (resp0.isRiskControl()) {
      // 1034：自动弹统一验证窗，成功后带 challenge 服务内重放一次
      const replayChallenge: string = await RiskVerifier.tryResolveRisk(resp0, cookie, url);
      request.assertCurrent();
      if (replayChallenge.length === 0) {
        throw new Error('人机验证未完成或被取消，请稍后再试');
      }
      headers['x-rpc-challenge'] = replayChallenge;
      resp = await ApiClient.getInstance().postJson(url, bodyJson,
        HoyolabClient.merge(HoyolabClient.getBaseHeaders(request.region), headers));
      request.assertCurrent();
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
    // -1 表示接口未提供突破阶段；等级处于突破边界时不能靠等级推断。
    d.promoteLevel = -1;
    // base 嵌套
    const base = item['base'] as Record<string, Object>;
    if (base !== undefined && base !== null) {
      d.id = CharacterService.num(base['id']);
      d.name = String(base['name'] ?? '');
      d.element = String(base['element'] ?? '');
      d.level = CharacterService.num(base['level']);
      d.promoteLevel = CharacterService.promoteLevelOf(base);
      d.rarity = CharacterService.num(base['rarity']);
      d.fetter = CharacterService.num(base['fetter']);
      d.activedConstellationNum = PromoteState.parse(base['actived_constellation_num']);
      d.skillDepotId = CharacterService.depotIdOf(base['skill_depot_id'] ?? item['skill_depot_id']);
      const detailIcon: string = String(base['avatar_icon'] ?? '');
      d.icon = detailIcon.length > 0 ? CharacterService.iconNameOf(detailIcon)
        : WikiMetaService.iconOfAvatar(d.id);
    } else {
      // 兜底：可能平铺
      d.id = CharacterService.num(item['id']);
      d.name = String(item['name'] ?? '');
      d.element = String(item['element'] ?? '');
      d.level = CharacterService.num(item['level']);
      d.promoteLevel = CharacterService.promoteLevelOf(item);
      d.rarity = CharacterService.num(item['rarity']);
      d.activedConstellationNum = PromoteState.parse(item['actived_constellation_num']);
      d.skillDepotId = CharacterService.depotIdOf(item['skill_depot_id']);
      d.fetter = CharacterService.num(item['fetter']);
    }
    const w = item['weapon'] as Record<string, Object>;
    if (w === null) {
      d.weapon.equipmentState = 'unequipped';
    }
    if (w !== undefined && w !== null) {
      d.weapon.id = CharacterService.num(w['id']);
      d.weapon.type = CharacterService.num(w['type']);
      d.weapon.rarity = CharacterService.num(w['rarity']);
      d.weapon.level = CharacterService.num(w['level']);
      d.weapon.affixLevel = CharacterService.num(w['affix_level']);
      d.weapon.promoteLevel = PromoteState.parse(w['promote_level']);
      d.weapon.equipmentState = d.weapon.id > 0 ? 'equipped' : (w['id'] === 0 ? 'unequipped' : 'unknown');
      if (!PromoteState.validWeapon(d.weapon.level, d.weapon.promoteLevel, d.weapon.rarity)) {
        d.weapon.promoteLevel = -1;
      }
      d.weapon.name = String(w['name'] ?? '');
      const main: Record<string, Object> = w['main_property'] as Record<string, Object>;
      const sub: Record<string, Object> = w['sub_property'] as Record<string, Object>;
      if (main !== undefined && main !== null) {
        d.weapon.mainProperty.propertyType = String(main['property_type'] ?? '');
        d.weapon.mainProperty.value = String(main['value'] ?? '');
      }
      if (sub !== undefined && sub !== null) {
        d.weapon.subProperty.propertyType = String(sub['property_type'] ?? '');
        d.weapon.subProperty.value = String(sub['value'] ?? '');
      }
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
        cell.activationKnown = typeof c['is_actived'] === 'boolean';
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
    // 技能等级（对齐 Windows DetailedCharacter.Skills：skill_id/skill_type/level；
    // skill_type 1=战斗天赋（普攻/战技/爆发），2=固有天赋（level 恒 0））
    const skills = item['skills'] as Array<Object>;
    if (skills !== undefined && skills !== null) {
      for (let i = 0; i < skills.length; i++) {
        const s = skills[i] as Record<string, Object>;
        const sk: AvatarSkill = new AvatarSkill();
        sk.skillId = CharacterService.num(s['skill_id']);
        sk.skillType = CharacterService.num(s['skill_type']);
        const rawLevel: Object = s['level'];
        sk.level = (typeof rawLevel === 'number' || typeof rawLevel === 'string') && String(rawLevel).trim().length > 0
          ? CharacterService.num(rawLevel) : 0;
        d.skills.push(sk);
      }
    }
    // 推荐主属性用于展示，副词条和能量类型仍用于评分。
    const rec = item['recommend_relic_property'] as Record<string, Object>;
    if (rec !== undefined && rec !== null) {
      const props = rec['recommend_properties'] as Record<string, Object>;
      if (props !== undefined && props !== null) {
        d.recommend.sandMainProperties = CharacterService.parseRecommendedMainProperties(props['sand_main_property_list']);
        d.recommend.gobletMainProperties = CharacterService.parseRecommendedMainProperties(props['goblet_main_property_list']);
        d.recommend.circletMainProperties = CharacterService.parseRecommendedMainProperties(props['circlet_main_property_list']);
        const list = props['sub_property_list'] as Array<Object>;
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

  private static parseRecommendedMainProperties(raw: Object): string[] {
    if (!Array.isArray(raw)) { return []; }
    const properties: string[] = [];
    for (const value of raw as Object[]) {
      if (typeof value === 'string' && value.trim().length > 0) {
        properties.push(value.trim());
      } else if (typeof value === 'number' && Number.isSafeInteger(value)) {
        properties.push(String(value));
      }
    }
    return properties;
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
    const set: Record<string, Object> = item['set'] as Record<string, Object>;
    if (set !== undefined && set !== null) {
      const id: number = CharacterService.num(set['id']);
      r.setId = Number.isSafeInteger(id) && id > 0 ? id : 0;
      r.setName = String(set['name'] ?? '');
    }
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

  private static depotIdOf(raw: Object | undefined | null): number {
    if (raw === undefined || raw === null) {
      return 0;
    }
    if ((typeof raw !== 'number' && typeof raw !== 'string') || String(raw).trim().length === 0) {
      return -1;
    }
    const id: number = Number(raw);
    return Number.isSafeInteger(id) && id >= 0 ? id : -1;
  }

  private static promoteLevelOf(item: Record<string, Object>): number {
    const raw: Object = item['promote_level'] ?? item['avatar_promote_level'];
    return PromoteState.parse(raw);
  }
}
