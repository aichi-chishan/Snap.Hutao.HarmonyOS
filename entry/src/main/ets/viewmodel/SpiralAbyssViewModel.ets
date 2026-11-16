/**
 * SpiralAbyssViewModel.ets
 * 深渊页状态容器：当期/上期数据、加载状态（含 1034 风控极验重放）。
 */
import { SpiralAbyssData, SpiralAbyssFloor } from '../model/SpiralAbyss';
import { ChallengePeriod } from '../model/ChallengePeriod';
import { SpiralAbyssService } from '../service/SpiralAbyssService';
import { SpiralAbyssRepo, AbyssHistoryEntry } from '../data/repo/SpiralAbyssRepo';
import { TowerMetadataService } from '../service/TowerMetadataService';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { ChallengeSession, ChallengeVerificationCancelled } from '../service/ChallengeSession';

@Observed
export class SpiralAbyssViewModel {
  private requestVersion: number = 0;
  abyss: SpiralAbyssData | undefined = undefined;
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 1=当期 2=上期 */
  scheduleType: number = 1;
  /** 本地累积的期数历史（新期在前） */
  history: ChallengePeriod[] = [];
  /** 当前 abyss 是否来自历史存档（false=实时数据） */
  fromHistory: boolean = false;
  publishedOnly: boolean = false;
  recordVersion: number = 0;
  floors: SpiralAbyssFloor[] = [];
  selectedFloorIndex: number = 0;
  /** 风控需人机验证（true 时 UI 跳转极验页） */
  needRiskVerify: boolean = false;
  riskGt: string = '';
  riskChallenge: string = '';
  riskPath: string = '';

  invalidate(): void { this.requestVersion++; }

  private current(version: number, session: ChallengeSession): boolean {
    return version === this.requestVersion && session.isCurrent();
  }

  async initialize(uid: string): Promise<void> {
    const session: ChallengeSession | undefined = ChallengeSession.capture(uid);
    if (session === undefined) { this.loaded = true; return; }
    const version: number = ++this.requestVersion;
    this.loading = true;
    try {
      await TowerMetadataService.preload();
      const history: ChallengePeriod[] = await this.timeline(session);
      if (!this.current(version, session)) { return; }
      this.history = history;
      const latest: ChallengePeriod | undefined = history.find((item: ChallengePeriod): boolean => item.hasRecord) ?? history[0];
      if (latest !== undefined) { await this.readHistory(session, version, latest.scheduleId); }
    } catch (e) {
      if (this.current(version, session)) { this.message = '无法读取本地深境螺旋战绩'; }
    } finally {
      if (version === this.requestVersion) { this.loading = false; this.loaded = true; }
    }
  }

  async load(uid: string): Promise<void> {
    const session: ChallengeSession | undefined = ChallengeSession.capture(uid);
    if (session === undefined) {
      this.message = '请先在「账号与数据」选择默认 UID';
      this.loaded = true;
      return;
    }
    const version: number = ++this.requestVersion;
    const selected: number = this.scheduleType;
    this.loading = true;
    this.needRiskVerify = false;
    this.message = '';
    const failures: string[] = [];
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      await TowerMetadataService.preload();
      for (const type of [selected, selected === 1 ? 2 : 1]) {
        if (!this.current(version, session)) { return; }
        try {
          const abyss: SpiralAbyssData = await SpiralAbyssService.getInstance().fetch(uid, type,
            type === selected && challenge.length > 0 ? challenge : undefined);
          if (!this.current(version, session)) { return; }
          await SpiralAbyssRepo.saveHistory(uid, session.region, abyss.scheduleId, abyss.startTime,
            abyss.endTime, abyss.totalStar, abyss.rawJson);
          if (type === selected && this.current(version, session)) {
            this.applyAbyss(abyss, false, false);
          }
        } catch (e) {
          if (!this.current(version, session)) { return; }
          if (e instanceof RiskControlError) {
            this.needRiskVerify = true;
            this.riskGt = e.gt;
            this.riskChallenge = e.challenge;
            this.riskPath = e.path;
            failures.push('需要完成人机验证');
            break;
          }
          failures.push(`${type === 1 ? '当期' : '上期'}刷新失败：${(e as Error).message}`);
          if (e instanceof ChallengeVerificationCancelled) { break; }
        }
      }
      const history: ChallengePeriod[] = await this.timeline(session);
      if (!this.current(version, session)) { return; }
      this.history = history;
      const latest: ChallengePeriod | undefined = history.find((item: ChallengePeriod): boolean => item.hasRecord);
      if (this.abyss === undefined && latest !== undefined) { await this.readHistory(session, version, latest.scheduleId); }
      if (this.current(version, session)) { this.message = failures.join('，'); }
    } catch (e) {
      if (this.current(version, session)) { this.message = (e as Error).message; }
    } finally {
      if (version === this.requestVersion) {
        this.loading = false;
        this.loaded = true;
      }
    }
  }

  /** 切换当期/上期 */
  async switchSchedule(uid: string, type: number): Promise<void> {
    if (this.scheduleType === type && !this.fromHistory) {
      return;
    }
    this.scheduleType = type;
    await this.load(uid);
  }

  /** 回看历史期数（本地存档重建，不发网络请求） */
  async loadFromHistory(uid: string, scheduleId: number): Promise<void> {
    const session: ChallengeSession | undefined = ChallengeSession.capture(uid);
    if (session === undefined) { return; }
    const version: number = ++this.requestVersion;
    this.loading = true;
    try { await this.readHistory(session, version, scheduleId); }
    catch (e) { if (this.current(version, session)) { this.message = '无法读取该期存档'; } }
    finally {
      if (version === this.requestVersion) { this.loading = false; this.loaded = true; }
    }
  }

  private async timeline(session: ChallengeSession): Promise<ChallengePeriod[]> {
    const records: AbyssHistoryEntry[] = await SpiralAbyssRepo.listHistory(session.uid, session.region);
    const periods: ChallengePeriod[] = records.map((entry: AbyssHistoryEntry): ChallengePeriod => {
      const period: ChallengePeriod = ChallengePeriod.recorded(entry.scheduleId, entry.startTime, entry.endTime,
        entry.recordTime, entry.totalStar);
      try {
        period.summary = SpiralAbyssData.fromJson(JSON.parse(entry.rawJson)).maxFloor;
      } catch (_) {}
      return period;
    });
    return ChallengePeriod.merge(periods, TowerMetadataService.publishedPeriods());
  }

  private async readHistory(session: ChallengeSession, version: number, scheduleId: number): Promise<void> {
    const period: ChallengePeriod | undefined = this.history.find((item: ChallengePeriod): boolean => item.scheduleId === scheduleId);
    if (period !== undefined && !period.hasRecord) {
      this.applyAbyss(TowerMetadataService.preview(period), true, true);
    } else {
      const raw: string = await SpiralAbyssRepo.getRawJson(session.uid, session.region, scheduleId);
      if (!this.current(version, session)) { return; }
      if (raw.length === 0) { throw new Error('暂无该期存档'); }
      this.applyAbyss(SpiralAbyssData.fromJson(JSON.parse(raw)), true, false);
    }
    this.message = '';
  }

  private applyAbyss(abyss: SpiralAbyssData, fromHistory: boolean, publishedOnly: boolean): void {
    this.abyss = abyss;
    this.floors = publishedOnly ? abyss.floors : TowerMetadataService.periodFloors(abyss.scheduleId, abyss.floors);
    this.selectedFloorIndex = this.floors[0]?.index ?? 0;
    this.fromHistory = fromHistory;
    this.publishedOnly = publishedOnly;
    this.recordVersion++;
  }

  selectFloor(index: number): void {
    if (this.floors.some((floor: SpiralAbyssFloor): boolean => floor.index === index)) {
      this.selectedFloorIndex = index;
    }
  }

  selectedFloors(): SpiralAbyssFloor[] {
    const selected: SpiralAbyssFloor | undefined =
      this.floors.find((floor: SpiralAbyssFloor): boolean => floor.index === this.selectedFloorIndex);
    return selected === undefined ? [] : [selected];
  }

  backToLive(uid: string): Promise<void> { return this.load(uid); }
}
