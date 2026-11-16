/**
 * HardChallengeViewModel.ets
 * 强敌挑战页状态容器（含 1034 风控极验重放）。
 * 对齐 Windows DataEntryView：single/mp 各一个 DataEntry（hasData/best/challenges），
 * 仅「单挑/联机」两项切换（Segmented 两项），无难度列表。
 */
import { HardChallengeRoot, HardChallengeData, HardChallengeDataEntry, HardChallengeChallenge, HardChallengeBest,
  HardChallengeSimpleAvatar, HardChallengeScheduleItem } from '../model/HardChallenge';
import { ChallengePeriod } from '../model/ChallengePeriod';
import { HardChallengeService } from '../service/HardChallengeService';
import { HardChallengeRepo, HardChallengeHistoryEntry } from '../data/repo/HardChallengeRepo';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { ChallengeSession } from '../service/ChallengeSession';

@Observed
export class HardChallengeViewModel {
  private requestVersion: number = 0;
  private popularityVersion: number = 0;
  isUnlock: boolean = false;
  /** 单挑 DataEntry */
  single: HardChallengeDataEntry = new HardChallengeDataEntry();
  /** 联机 DataEntry */
  mp: HardChallengeDataEntry = new HardChallengeDataEntry();
  /** 耀金角色（对齐 Windows BlingAvatarView 列表；本地数据非云） */
  blings: HardChallengeSimpleAvatar[] = [];
  popularity: HardChallengeSimpleAvatar[] = [];
  popularityLoading: boolean = false;
  popularityError: string = '';
  /** 档位：0=单挑 1=联机 */
  modeIndex: number = 0;
  scheduleName: string = '';
  /** 当前期 schedule_id（实时/历史存档均更新；期数 chips 高亮与入库键） */
  scheduleId: number = 0;
  /** 本地累积的期数历史（新期在前） */
  history: ChallengePeriod[] = [];
  /** 当前数据是否来自历史存档（false=实时数据） */
  fromHistory: boolean = false;
  recordVersion: number = 0;
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 风控需人机验证（true 时 UI 弹验证窗） */
  needRiskVerify: boolean = false;
  riskGt: string = '';
  riskChallenge: string = '';
  riskPath: string = '';

  invalidate(): void { this.requestVersion++; this.popularityVersion++; }

  private valid(version: number, session: ChallengeSession): boolean {
    return version === this.requestVersion && session.isCurrent();
  }

  async initialize(uid: string): Promise<void> {
    const session: ChallengeSession | undefined = ChallengeSession.capture(uid);
    if (session === undefined) { this.loaded = true; return; }
    const version: number = ++this.requestVersion;
    this.loading = true;
    try {
      const history: ChallengePeriod[] = await this.timeline(session);
      if (!this.valid(version, session)) { return; }
      this.history = history;
      const latest: ChallengePeriod | undefined = history.find((item: ChallengePeriod): boolean => item.hasRecord) ?? history[0];
      if (latest !== undefined) { await this.readHistory(session, version, latest.scheduleId); }
    } catch (e) {
      if (this.valid(version, session)) { this.message = '无法读取本地幽境危战战绩'; }
    } finally {
      if (version === this.requestVersion) { this.loading = false; this.loaded = true; }
    }
    if (this.valid(version, session)) { this.loadPopularity(uid); }
  }

  async load(uid: string): Promise<void> {
    const session: ChallengeSession | undefined = ChallengeSession.capture(uid);
    if (session === undefined) {
      this.message = '请先登录并绑定 UID';
      this.loaded = true;
      return;
    }
    const version: number = ++this.requestVersion;
    this.loading = true;
    this.needRiskVerify = false;
    this.message = '';
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      const root: HardChallengeRoot = await HardChallengeService.getInstance().fetch(uid,
        challenge.length > 0 ? challenge : undefined);
      if (!this.valid(version, session)) { return; }
      const newest: HardChallengeData | undefined = root.periods
        .filter((period: HardChallengeData): boolean => period.schedule.length > 0 && (period.single.hasData || period.mp.hasData))
        .sort((a: HardChallengeData, b: HardChallengeData): number => b.schedule[0].scheduleId - a.schedule[0].scheduleId)[0];
      if (newest !== undefined || !this.fromHistory) {
        this.applyPeriod(newest ?? root.data, root.isUnlock, false);
      }
      // 官方一次返回多期；逐期保存，不能将整个响应归到首期。
      for (let i: number = 0; i < root.periods.length; i++) {
        if (!this.valid(version, session)) { return; }
        const period = root.periods[i];
        if (period.schedule.length === 0 || (!period.single.hasData && !period.mp.hasData)) {
          continue;
        }
        const schedule: HardChallengeScheduleItem = period.schedule[0];
        await HardChallengeRepo.saveHistory(uid, session.region, schedule.scheduleId,
          schedule.startTime * 1000, schedule.endTime * 1000, root.itemRawJson[i]);
      }
      const history: ChallengePeriod[] = await this.timeline(session);
      if (this.valid(version, session)) { this.history = history; }
    } catch (e) {
      if (!this.valid(version, session)) { return; }
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
      if (version === this.requestVersion) {
        this.loading = false;
        this.loaded = true;
      }
    }
  }

  async loadPopularity(uid: string): Promise<void> {
    const session: ChallengeSession | undefined = ChallengeSession.capture(uid);
    if (session === undefined) { return; }
    const version: number = ++this.popularityVersion;
    this.popularityLoading = true;
    this.popularityError = '';
    try {
      const result: HardChallengeSimpleAvatar[] = await HardChallengeService.getInstance().fetchPopularity(uid);
      if (version === this.popularityVersion && session.isCurrent()) { this.popularity = result; }
    } catch (e) {
      if (version === this.popularityVersion && session.isCurrent()) { this.popularityError = (e as Error).message; }
    } finally {
      if (version === this.popularityVersion) { this.popularityLoading = false; }
    }
  }

  /** 按档位取 DataEntry（页面 @State modeIndex 驱动） */
  entryOf(mode: number): HardChallengeDataEntry {
    return mode === 0 ? this.single : this.mp;
  }

  /** 回看历史期数（本地存档重建，不发网络请求） */
  async loadFromHistory(uid: string, scheduleId: number): Promise<void> {
    const session: ChallengeSession | undefined = ChallengeSession.capture(uid);
    if (session === undefined) { return; }
    const version: number = ++this.requestVersion;
    this.loading = true;
    try { await this.readHistory(session, version, scheduleId); }
    catch (e) { if (this.valid(version, session)) { this.message = '无法读取该期存档'; } }
    finally {
      if (version === this.requestVersion) { this.loading = false; this.loaded = true; }
    }
  }

  private async timeline(session: ChallengeSession): Promise<ChallengePeriod[]> {
    const records: HardChallengeHistoryEntry[] = await HardChallengeRepo.listHistory(session.uid, session.region);
    const metadata: ChallengePeriod[] = await HardChallengeService.publishedPeriods();
    const periods: ChallengePeriod[] = records.map((entry: HardChallengeHistoryEntry): ChallengePeriod => {
      // Windows HardChallengeView.FormattedTime 始终使用发布期次 Begin/End，
      // 不把战绩响应中的时间窗口当作完整展示期；原始 API 与存档时间保持不变。
      const published: ChallengePeriod | undefined = metadata.find(
        (item: ChallengePeriod): boolean => item.scheduleId === entry.scheduleId);
      let start: number = entry.startTime;
      let end: number = entry.endTime;
      if (published !== undefined && Number.isFinite(published.startTime) && Number.isFinite(published.endTime) &&
        published.startTime > 0 && published.endTime >= published.startTime) {
        start = published.startTime;
        end = published.endTime;
      }
      const period: ChallengePeriod = ChallengePeriod.recorded(entry.scheduleId, start, end, entry.recordTime);
      try {
        const data: HardChallengeData = HardChallengeRoot.fromJson(JSON.parse(entry.rawJson)).data;
        period.name = data.schedule[0]?.name ?? '';
        const single: HardChallengeBest | undefined = data.single.hasData ? data.single.best : undefined;
        const multi: HardChallengeBest | undefined = data.mp.hasData ? data.mp.best : undefined;
        const best: HardChallengeBest | undefined =
          (multi?.difficulty ?? 0) > (single?.difficulty ?? 0) ? multi : single ?? multi;
        period.summary = best?.difficultyLabel() ?? '';
      } catch (_) {}
      return period;
    });
    return ChallengePeriod.merge(periods, metadata);
  }

  private async readHistory(session: ChallengeSession, version: number, scheduleId: number): Promise<void> {
    const period: ChallengePeriod | undefined = this.history.find((entry: ChallengePeriod): boolean => entry.scheduleId === scheduleId);
    if (period !== undefined && !period.hasRecord) {
      const data: HardChallengeData = new HardChallengeData();
      const schedule: HardChallengeScheduleItem = new HardChallengeScheduleItem();
      schedule.scheduleId = period.scheduleId;
      schedule.name = period.name;
      data.schedule = [schedule];
      this.applyPeriod(data, false, true);
    } else {
      const raw: string = await HardChallengeRepo.getRawJson(session.uid, session.region, scheduleId);
      if (!this.valid(version, session)) { return; }
      if (raw.length === 0) { throw new Error('暂无该期存档'); }
      const root: HardChallengeRoot = HardChallengeRoot.fromJson(JSON.parse(raw));
      this.applyPeriod(root.data, root.isUnlock, true);
    }
    this.message = '';
  }

  private applyPeriod(period: HardChallengeData, isUnlock: boolean, fromHistory: boolean): void {
    this.isUnlock = isUnlock;
    this.single = period.single;
    this.mp = period.mp;
    this.blings = period.blings;
    this.scheduleId = period.schedule[0]?.scheduleId ?? 0;
    this.scheduleName = period.schedule[0]?.name ?? '';
    this.modeIndex = !period.single.hasData && period.mp.hasData ? 1 : 0;
    this.fromHistory = fromHistory;
    this.recordVersion++;
  }

  backToLive(uid: string): Promise<void> { return this.load(uid); }

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

}
