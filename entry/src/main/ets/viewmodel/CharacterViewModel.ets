/**
 * CharacterViewModel.ets
 * 角色资料页状态容器（含 1034 风控极验重放：needRiskVerify 通知 UI 弹验证窗）。
 * 性能策略对齐 Windows AvatarPropertyViewModel：详情一次性全量拉取（单请求），
 * 角色点击仅本地切换（不再逐角色发 detail 请求 → 避免米哈游 -502 限流）。
 */
import { CharacterService } from '../service/CharacterService';
import { CalculateService, CalAvatarDelta, CalSkillDelta } from '../service/CalculateService';
import { OfflineCultivationService } from '../service/OfflineCultivationService';
import { WikiMetaService, WikiWeaponMeta } from '../service/WikiMetaService';
import { CharacterListItem, CharacterDetail } from '../model/CharacterData';
import { CalBatchResult, CalAvatarConsume, CalItem } from '../model/Calculate';
import { CultivationRepo, CultivateProject, CultivateEntry } from '../data/repo/CultivationRepo';
import { CultivationViewModel } from './CultivationViewModel';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { Logger } from '../common/Logger';

const TAG: string = 'CharacterViewModel';

/** 加入养成计划结果（对齐 Windows ConsumptionSaveResultKind 的页面提示口径） */
export class AddPlanResult {
  ok: boolean = false;
  message: string = '';
}

@Observed
export class CharacterViewModel {
  items: CharacterListItem[] = [];
  /** 详情全量缓存（id → detail），一次拉取后本地切换 */
  detailMap: Map<number, CharacterDetail> = new Map();
  detail: CharacterDetail | undefined = undefined;
  loading: boolean = false;
  loadingDetail: boolean = false;
  detailLoading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 当前选中的角色 id */
  selectedId: number = 0;
  private currentUid: string = '';
  /** 风控需人机验证（true 时 UI 弹验证窗） */
  needRiskVerify: boolean = false;
  /** 极验参数（弹窗用） */
  riskGt: string = '';
  riskChallenge: string = '';
  riskPath: string = '';

  async load(uid: string): Promise<void> {
    this.currentUid = uid;
    if (uid.length === 0) {
      this.message = '请先在「账号与数据」选择默认 UID';
      this.loaded = true;
      return;
    }
    this.items = CharacterService.getInstance().getCachedList(uid);
    this.detailMap = new Map<number, CharacterDetail>();
    for (const detail of CharacterService.getInstance().getCachedDetails(uid)) {
      this.detailMap.set(detail.id, detail);
    }
    if (this.items.length > 0) {
      this.selectedId = this.items[0].id;
      this.syncCurrentDetail();
    }
    this.loading = true;
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      this.items = await CharacterService.getInstance().fetchList(uid, challenge.length > 0 ? challenge : undefined);

      if (this.items.length > 0) {
        this.selectedId = this.items[0].id;
        await this.loadAllDetails(uid);
      }
      this.message = '';
    } catch (e) {
      this.handleError(e);
    } finally {
      this.loading = false;
      this.loaded = true;
    }
  }

  /** 全量预加载所有角色详情（单请求；失败时保留已拉取的，标记消息） */
  async loadAllDetails(uid: string): Promise<void> {
    if (this.items.length === 0) {
      return;
    }
    this.detailLoading = true;
    try {
      const ids: number[] = [];
      for (let i = 0; i < this.items.length; i++) {
        ids.push(this.items[i].id);
      }
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      const cache: Map<number, CharacterDetail> = new Map(this.detailMap);
      // 分批拉取（每批 20），失败重试一次，避免整批 -502
      const batchSize: number = 20;
      for (let i = 0; i < ids.length; i += batchSize) {
        const batch: number[] = ids.slice(i, i + batchSize);
        const details: CharacterDetail[] = await CharacterService.getInstance()
          .fetchDetail(uid, batch, challenge.length > 0 ? challenge : undefined);
        for (let j = 0; j < details.length; j++) {
          cache.set(details[j].id, details[j]);
        }
        this.detailMap = new Map(cache);
        this.syncCurrentDetail();
      }
      this.detailMap = cache;
      this.syncCurrentDetail();
      this.message = '';
    } catch (e) {
      this.handleError(e);
    } finally {
      this.detailLoading = false;
    }
  }

  /** 点击角色：仅切换（详情已缓存） */
  async select(uid: string, id: number): Promise<void> {
    this.selectedId = id;
    this.syncCurrentDetail();
    // 若该角色详情未缓存（部分失败），按需拉取
    if (!this.detailMap.has(id)) {
      this.loadingDetail = true;
      try {
        const challenge: string = RiskUiHelper.consumePendingChallenge();
        const details: CharacterDetail[] = await CharacterService.getInstance()
          .fetchDetail(uid, [id], challenge.length > 0 ? challenge : undefined);
        if (details.length > 0) {
          this.detailMap.set(id, details[0]);
          this.syncCurrentDetail();
        }
      } catch (e) {
        this.handleError(e);
      } finally {
        this.loadingDetail = false;
      }
    }
  }

  /** 兼容旧调用：加载选中角色详情（点击时由 UI 调用） */
  async loadDetail(uid: string, id: number): Promise<void> {
    await this.select(uid, id);
  }

  /** 当前选中角色的详情（页面调用后回填 @State） */
  detailOfSelected(): CharacterDetail | undefined {
    return this.detailMap.get(this.selectedId);
  }

  /**
   * 加入养成计划（对齐 Windows AvatarPropertyViewModel.AddAvatarToPlanCommand：仅角色侧，不含武器）。
   * 重复加入（同项目同角色）返回 ok=false；材料使用准确的同步进度与本地算法计算，失败时不创建空材料条目。
   */
  async addAvatarToPlan(detail: CharacterDetail, project: CultivateProject): Promise<AddPlanResult> {
    const r: AddPlanResult = new AddPlanResult();
    try {
      const entries: CultivateEntry[] = await CultivationRepo.getEntries(project.id);
      for (const e of entries) {
        if (e.avatarId === detail.id) {
          r.ok = false;
          r.message = `该角色已在养成计划「${project.name}」中`;
          return r;
        }
      }
      const delta: CalAvatarDelta = new CalAvatarDelta();
      delta.avatarId = detail.id;
      delta.levelCurrent = detail.level;
      delta.levelTarget = Math.max(detail.level, 90);
      delta.elementAttrId = CultivationViewModel.elementAttrIdOf(detail.element);
      if (this.currentUid.length > 0) {
        const promotes: Map<number, number> = await CalculateService.getInstance().fetchPromoteLevels(this.currentUid);
        if (!promotes.has(detail.id)) {
          throw new Error('当前角色突破等级未同步');
        }
        delta.avatarPromoteLevel = promotes.get(detail.id) ?? 0;
        await CalculateService.getInstance().fillSyncedDetails(this.currentUid, delta, 10);
      } else {
        // 图鉴入口明确从1级开始，离线计算无需账号；不把未知实况当作1级。
        if (detail.level !== 1) {
          throw new Error('未关联角色 UID，无法确认当前养成进度');
        }
        for (let index: number = 0; index < 3; index++) {
          const skill: CalSkillDelta = new CalSkillDelta();
          skill.id = index + 1;
          skill.levelCurrent = 1;
          skill.levelTarget = 10;
          delta.skills.push(skill);
        }
      }
      const result: CalBatchResult = await OfflineCultivationService.batchCompute([delta]);
      const items: CalItem[] = result.items[0].avatarConsume;
      // 条目头像：本地元数据图标名（MetaIcon/AvatarIcon）优先，回退详情自带字段（可能是 http 直图）
      let icon: string = detail.icon;
      const metaIcon: string = WikiMetaService.iconOfAvatar(detail.id);
      if (metaIcon.length > 0) {
        icon = metaIcon;
      }
      await CultivationRepo.addEntry(project.id, detail.id, detail.name, icon,
        detail.level, Math.max(detail.level, 90), items);
      r.ok = true;
      r.message = `已加入养成计划：${project.name}（等级、突破与天赋材料）`;
    } catch (e) {
      r.ok = false;
      r.message = `加入失败：${(e as Error).message}`;
      Logger.warn(TAG, `addAvatarToPlan fail: ${r.message}`);
    }
    return r;
  }

  /**
   * 图鉴武器加入养成计划（对齐 Windows WikiWeaponViewModel.CultivateCommand）：
   * 重复加入（同项目同武器）返回 ok=false；条目 level/targetLevel 固定 1→90。
   * 按上游离线经验与突破表计算完整材料；1/2星武器上限70级，其余90级。
   */
  async addWeaponToPlan(weaponId: number, weaponName: string, project: CultivateProject): Promise<AddPlanResult> {
    const r: AddPlanResult = new AddPlanResult();
    try {
      const entries: CultivateEntry[] = await CultivationRepo.getEntries(project.id);
      for (const e of entries) {
        if (e.avatarId === weaponId) {
          r.ok = false;
          r.message = `该武器已在养成计划「${project.name}」中`;
          return r;
        }
      }
      const weapons: WikiWeaponMeta[] = await WikiMetaService.getWeapons();
      const meta: WikiWeaponMeta | undefined = weapons.find((weapon: WikiWeaponMeta): boolean => weapon.id === weaponId);
      const target: number = meta !== undefined && meta.rankLevel <= 2 ? 70 : 90;
      const items: CalItem[] = await OfflineCultivationService.weaponCompute(weaponId, 1, target, 0);
      await CultivationRepo.addEntry(project.id, weaponId, weaponName, meta?.icon ?? '', 1, target, items);
      r.ok = true;
      r.message = `已加入养成计划：${project.name}`;
    } catch (e) {
      r.ok = false;
      r.message = `加入失败：${(e as Error).message}`;
      Logger.warn(TAG, `addWeaponToPlan fail: ${r.message}`);
    }
    return r;
  }

  private syncCurrentDetail(): void {
    const d: CharacterDetail | undefined = this.detailMap.get(this.selectedId);
    this.detail = d;
  }

  private handleError(e: Error): void {
    if (e instanceof RiskControlError) {
      this.needRiskVerify = true;
      this.riskGt = e.gt;
      this.riskChallenge = e.challenge;
      this.riskPath = e.path;
      this.message = '需要完成人机验证';
    } else {
      this.message = (e as Error).message;
      Logger.warn(TAG, `load fail: ${this.message}`);
    }
  }

  /** 极验完成后由 UI 调用：清除标记并重新加载 */
  resetRiskAndReload(uid: string): void {
    this.needRiskVerify = false;
    this.load(uid).then(() => {
    });
  }
}
