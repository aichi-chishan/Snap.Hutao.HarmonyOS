/**
 * RoleCombatViewModel.ets
 * 幻象真境剧诗页状态容器（含 1034 风控极验重放）。
 */
import { RoleCombatRoot, RoleCombatDataItem, RoleCombatRoundData } from '../model/RoleCombat';
import { RoleCombatService } from '../service/RoleCombatService';
import { RoleCombatRepo, RoleCombatHistoryEntry } from '../data/repo/RoleCombatRepo';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';

@Observed
export class RoleCombatViewModel {
  /** 有数据的档期 */
  dataItems: RoleCombatDataItem[] = [];
  /** 当前选中档期索引 */
  currentIndex: number = 0;
  isUnlock: boolean = false;
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 本地累积的期数历史（新期在前） */
  history: RoleCombatHistoryEntry[] = [];
  /** 当前数据是否来自历史存档（false=实时数据） */
  fromHistory: boolean = false;
  /** 风控需人机验证（true 时 UI 跳转极验页） */
  needRiskVerify: boolean = false;
  riskGt: string = '';
  riskChallenge: string = '';
  riskPath: string = '';

  current(): RoleCombatDataItem | undefined {
    if (this.currentIndex >= 0 && this.currentIndex < this.dataItems.length) {
      return this.dataItems[this.currentIndex];
    }
    return undefined;
  }

  async load(uid: string): Promise<void> {
    if (uid.length === 0) {
      this.message = '请先登录并绑定 UID';
      this.loaded = true;
      return;
    }
    this.loading = true;
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      const root: RoleCombatRoot = await RoleCombatService.getInstance().fetch(uid,
        challenge.length > 0 ? challenge : undefined);
      this.isUnlock = root.isUnlock;
      this.dataItems = root.data.filter((d: RoleCombatDataItem) => d.hasData);
      if (this.dataItems.length > 0 && this.currentIndex >= this.dataItems.length) {
        this.currentIndex = 0;
      }
      this.fromHistory = false;
      this.message = '';
      // 期数历史入库（每期一条，按 schedule_id UPSERT，对齐 Windows RoleCombatEntry）
      for (let i = 0; i < root.data.length; i++) {
        const item: RoleCombatDataItem = root.data[i];
        if (!item.hasData || item.schedule.scheduleId <= 0) {
          continue;
        }
        const raw: string = i < root.itemRawJson.length ? root.itemRawJson[i] : '';
        await RoleCombatRepo.saveHistory(item.schedule.scheduleId, item.schedule.startTime * 1000,
          item.schedule.endTime * 1000, raw);
      }
      this.history = await RoleCombatRepo.listHistory();
    } catch (e) {
      if (e instanceof RiskControlError) {
        this.needRiskVerify = true;
        this.riskGt = e.gt;
        this.riskChallenge = e.challenge;
        this.riskPath = e.path;
        this.message = '需要完成人机验证';
      } else {
        this.message = (e as Error).message;
      }
    } finally {
      this.loading = false;
      this.loaded = true;
    }
  }

  select(index: number): void {
    this.currentIndex = index;
  }

  /** 刷新本地期数历史列表（进页时） */
  async loadHistoryList(): Promise<void> {
    this.history = await RoleCombatRepo.listHistory();
  }

  /** 回看历史期数（本地存档重建，不发网络请求） */
  async loadFromHistory(scheduleId: number): Promise<void> {
    const raw: string = await RoleCombatRepo.getRawJson(scheduleId);
    if (raw.length === 0) {
      return;
    }
    const item: RoleCombatDataItem = RoleCombatRoot.dataItemFromJson(JSON.parse(raw));
    if (!item.hasData) {
      return;
    }
    this.dataItems = [item];
    this.currentIndex = 0;
    this.isUnlock = true;
    this.fromHistory = true;
    this.message = `历史存档 · 第 ${scheduleId} 期`;
    this.loaded = true;
  }

  /** 回到实时数据（重新拉取） */
  async backToLive(uid: string): Promise<void> {
    this.fromHistory = false;
    await this.load(uid);
  }

  /** 当前档期回合数列表（有回合数据的） */
  rounds(): RoleCombatRoundData[] {
    const cur = this.current();
    if (cur === undefined) {
      return [];
    }
    return cur.detail.roundsData;
  }

  /** 极验完成后由 UI 调用：清除标记并重新加载 */
  resetRiskAndReload(uid: string): void {
    this.needRiskVerify = false;
    this.load(uid).then(() => {
    });
  }
}
