/**
 * HardChallengeViewModel.ets
 * 强敌挑战页状态容器（含 1034 风控极验重放）。
 * 对齐 Windows DataEntryView：single/mp 各一个 DataEntry（hasData/best/challenges），
 * 仅「单挑/联机」两项切换（Segmented 两项），无难度列表。
 */
import { HardChallengeRoot, HardChallengeDataEntry, HardChallengeChallenge, HardChallengeBest,
  HardChallengeSimpleAvatar, HardChallengeScheduleItem } from '../model/HardChallenge';
import { HardChallengeService } from '../service/HardChallengeService';
import { HardChallengeRepo, HardChallengeHistoryEntry } from '../data/repo/HardChallengeRepo';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';

@Observed
export class HardChallengeViewModel {
  isUnlock: boolean = false;
  /** 单挑 DataEntry */
  single: HardChallengeDataEntry = new HardChallengeDataEntry();
  /** 联机 DataEntry */
  mp: HardChallengeDataEntry = new HardChallengeDataEntry();
  /** 耀金角色（对齐 Windows BlingAvatarView 列表；本地数据非云） */
  blings: HardChallengeSimpleAvatar[] = [];
  /** 档位：0=单挑 1=联机 */
  modeIndex: number = 0;
  scheduleName: string = '';
  /** 当前期 schedule_id（实时/历史存档均更新；期数 chips 高亮与入库键） */
  scheduleId: number = 0;
  /** 本地累积的期数历史（新期在前） */
  history: HardChallengeHistoryEntry[] = [];
  /** 当前数据是否来自历史存档（false=实时数据） */
  fromHistory: boolean = false;
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
      this.blings = root.data.blings;
      this.scheduleId = 0;
      if (root.data.schedule.length > 0) {
        this.scheduleName = root.data.schedule[0].name;
        this.scheduleId = root.data.schedule[0].scheduleId;
      }
      this.message = '';
      this.fromHistory = false;
      // 期数历史入库（当期一条，按 schedule_id UPSERT，对齐 Windows HardChallengeEntry：
      // 单挑/联机均无数据不入库）
      if (this.scheduleId > 0 && (this.single.hasData || this.mp.hasData)) {
        const s: HardChallengeScheduleItem = root.data.schedule[0];
        await HardChallengeRepo.saveHistory(this.scheduleId, s.startTime * 1000, s.endTime * 1000,
          root.rawJson);
      }
      this.history = await HardChallengeRepo.listHistory();
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

  /** 刷新本地期数历史列表（进页时） */
  async loadHistoryList(): Promise<void> {
    this.history = await HardChallengeRepo.listHistory();
  }

  /** 回看历史期数（本地存档重建，不发网络请求） */
  async loadFromHistory(scheduleId: number): Promise<void> {
    const raw: string = await HardChallengeRepo.getRawJson(scheduleId);
    if (raw.length === 0) {
      return;
    }
    const root: HardChallengeRoot = HardChallengeRoot.fromJson(JSON.parse(raw));
    this.isUnlock = root.isUnlock;
    this.single = root.data.single;
    this.mp = root.data.mp;
    this.blings = root.data.blings;
    this.scheduleId = 0;
    if (root.data.schedule.length > 0) {
      this.scheduleName = root.data.schedule[0].name;
      this.scheduleId = root.data.schedule[0].scheduleId;
    }
    this.fromHistory = true;
    this.message = `历史存档 · 第 ${scheduleId} 期`;
    this.loaded = true;
  }

  /** 回到实时数据（重新拉取） */
  async backToLive(uid: string): Promise<void> {
    this.fromHistory = false;
    await this.load(uid);
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
