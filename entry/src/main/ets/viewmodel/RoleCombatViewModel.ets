/**
 * RoleCombatViewModel.ets
 * 幻象真境剧诗页状态容器（含 1034 风控极验重放）。
 */
import { RoleCombatRoot, RoleCombatDataItem, RoleCombatRoundData } from '../model/RoleCombat';
import { RoleCombatService } from '../service/RoleCombatService';
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
