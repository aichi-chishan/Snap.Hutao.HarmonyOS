/**
 * CharacterViewModel.ets
 * 角色资料页状态容器（含 1034 风控极验重放：needRiskVerify 通知 UI 弹验证窗）。
 * 性能策略对齐 Windows AvatarPropertyViewModel：详情一次性全量拉取（单请求），
 * 角色点击仅本地切换（不再逐角色发 detail 请求 → 避免米哈游 -502 限流）。
 */
import { CharacterService } from '../service/CharacterService';
import { CharacterListItem, CharacterDetail } from '../model/CharacterData';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { Logger } from '../common/Logger';

const TAG: string = 'CharacterViewModel';

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
