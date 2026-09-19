/**
 * CharacterViewModel.ets
 * 角色资料页状态容器（含 1034 风控极验重放：needRiskVerify 通知 UI 弹验证窗）。
 * 性能策略对齐 Windows AvatarPropertyViewModel：详情一次性全量拉取（单请求），
 * 角色点击仅本地切换（不再逐角色发 detail 请求 → 避免米哈游 -502 限流）。
 */
import { CharacterService } from '../service/CharacterService';
import { CalculateService, CalAvatarDelta } from '../service/CalculateService';
import { WikiMetaService } from '../service/WikiMetaService';
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
  /** 风控需人机验证（true 时 UI 弹验证窗） */
  needRiskVerify: boolean = false;
  /** 极验参数（弹窗用） */
  riskGt: string = '';
  riskChallenge: string = '';
  riskPath: string = '';

  async load(uid: string): Promise<void> {
    if (uid.length === 0) {
      this.message = '请先在「账号与数据」选择默认 UID';
      this.loaded = true;
      return;
    }
    this.loading = true;
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      this.items = await CharacterService.getInstance().fetchList(uid, challenge.length > 0 ? challenge : undefined);
      this.detailMap = new Map();
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
      const cache: Map<number, CharacterDetail> = new Map();
      // 分批拉取（每批 20），失败重试一次，避免整批 -502
      const batchSize: number = 20;
      for (let i = 0; i < ids.length; i += batchSize) {
        const batch: number[] = ids.slice(i, i + batchSize);
        const details: CharacterDetail[] = await CharacterService.getInstance()
          .fetchDetail(uid, batch, challenge.length > 0 ? challenge : undefined);
        for (let j = 0; j < details.length; j++) {
          cache.set(details[j].id, details[j]);
        }
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
   * 重复加入（同项目同角色）返回 ok=false；材料经 batch_compute 计算（角色突破+天赋材料，
   * 详情无技能等级故技能清单为空），计算失败时仍落目标条目（无材料清单）。
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
      // 材料：角色突破+天赋消耗（对齐 Windows SaveAvatarOnlyCultivationAsync 的合并口径）
      const items: CalItem[] = [];
      let computed: boolean = false;
      try {
        const delta: CalAvatarDelta = new CalAvatarDelta();
        delta.avatarId = detail.id;
        delta.levelCurrent = detail.level;
        delta.levelTarget = Math.max(detail.level, 90);
        delta.elementAttrId = CultivationViewModel.elementAttrIdOf(detail.element);
        delta.avatarPromoteLevel = detail.promoteLevel;
        // 技能清单：详情无技能等级数据（batch_compute 允许空 skill_list，与养成页计算口径一致）
        delta.skills = [];
        const result: CalBatchResult = await CalculateService.getInstance().batchCompute([delta]);
        if (result.items.length > 0) {
          const c: CalAvatarConsume = result.items[0];
          for (const it of c.avatarConsume) {
            items.push(it);
          }
          for (const it of c.avatarSkillConsume) {
            items.push(it);
          }
        }
        computed = true;
      } catch (e) {
        Logger.warn(TAG, `addAvatarToPlan compute fail: ${(e as Error).message}`);
      }
      // 条目头像：本地元数据图标名（MetaIcon/AvatarIcon）优先，回退详情自带字段（可能是 http 直图）
      let icon: string = detail.icon;
      const metaIcon: string = WikiMetaService.iconOfAvatar(detail.id);
      if (metaIcon.length > 0) {
        icon = metaIcon;
      }
      await CultivationRepo.addEntry(project.id, detail.id, detail.name, icon,
        detail.level, Math.max(detail.level, 90), items);
      r.ok = true;
      r.message = computed ? `已加入养成计划：${project.name}`
        : `已加入养成计划：${project.name}（材料清单获取失败，仅记录目标）`;
    } catch (e) {
      r.ok = false;
      r.message = `加入失败：${(e as Error).message}`;
      Logger.warn(TAG, `addAvatarToPlan fail: ${r.message}`);
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
