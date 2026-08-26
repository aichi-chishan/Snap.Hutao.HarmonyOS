/**
 * HardChallengeViewModel.ets
 * 强敌挑战页状态容器（含 1034 风控极验重放）。
 * 对齐 Windows DataEntryView：single/mp 各一个 DataEntry（hasData/best/challenges），
 * 仅「单挑/联机」两项切换（Segmented 两项），无难度列表。
 */
import { HardChallengeRoot, HardChallengeDataEntry, HardChallengeChallenge, HardChallengeBest } from '../model/HardChallenge';
import { HardChallengeService } from '../service/HardChallengeService';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';

@Observed
export class HardChallengeViewModel {
  isUnlock: boolean = false;
  /** 单挑 DataEntry */
  single: HardChallengeDataEntry = new HardChallengeDataEntry();
  /** 联机 DataEntry */
  mp: HardChallengeDataEntry = new HardChallengeDataEntry();
  /** 档位：0=单挑 1=联机 */
  modeIndex: number = 0;
  scheduleName: string = '';
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 风控需人机验证（true 时 UI 弹验证窗） */
  needRiskVerify: boolean = false;
  riskGt: string = '';
  riskChallenge: string = '';
  riskPath: string = '';

  async load(uid: string): Promise<void> {
    if (uid.length === 0) {
      this.message = '请先登录并绑定 UID';
      this.loaded = true;
      return;
    }
    this.loading = true;
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      const root: HardChallengeRoot = await HardChallengeService.getInstance().fetch(uid,
        challenge.length > 0 ? challenge : undefined);
      this.isUnlock = root.isUnlock;
      this.single = root.data.single;
      this.mp = root.data.mp;
      if (root.data.schedule.length > 0) {
        this.scheduleName = root.data.schedule[0].name;
      }
      this.message = '';
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

  /** 按档位取 DataEntry（页面 @State modeIndex 驱动） */
  entryOf(mode: number): HardChallengeDataEntry {
    return mode === 0 ? this.single : this.mp;
  }

  /** 兼容旧调用：页面切档 */
  selectMode(index: number): void {
    this.modeIndex = index;
  }

  currentEntry(): HardChallengeDataEntry {
    return this.modeIndex === 0 ? this.single : this.mp;
  }

  currentBest(): HardChallengeBest | undefined {
    const entry: HardChallengeDataEntry = this.currentEntry();
    return entry.hasData ? entry.best : undefined;
  }

  /** 当前档位全部挑战 */
  challenges(): HardChallengeChallenge[] {
    return this.currentEntry().challenges;
  }

  /** 极验完成后由 UI 调用：清除标记并重新加载 */
  resetRiskAndReload(uid: string): void {
    this.needRiskVerify = false;
    this.load(uid).then(() => {
    });
  }
}
