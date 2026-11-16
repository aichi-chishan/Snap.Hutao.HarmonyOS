/**
 * RoleCombatViewModel.ets
 * 幻象真境剧诗页状态容器（含 1034 风控极验重放）。
 */
import { RoleCombatRoot, RoleCombatDataItem, RoleCombatRoundData, RoleCombatAvatar } from '../model/RoleCombat';
import { ChallengePeriod } from '../model/ChallengePeriod';
import { RoleCombatService } from '../service/RoleCombatService';
import { WikiMetaService, RoleCombatScheduleMeta } from '../service/WikiMetaService';
import { RoleCombatRepo, RoleCombatHistoryEntry } from '../data/repo/RoleCombatRepo';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { ChallengeSession } from '../service/ChallengeSession';

@Observed
export class RoleCombatViewModel {
  private requestVersion: number = 0;
  /** 有数据的档期 */
  dataItems: RoleCombatDataItem[] = [];
  isUnlock: boolean = false;
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 本地累积的期数历史（新期在前） */
  history: ChallengePeriod[] = [];
  recordVersion: number = 0;
  /** 当前数据是否来自历史存档（false=实时数据） */
  fromHistory: boolean = false;
  /** 风控需人机验证（true 时 UI 跳转极验页） */
  needRiskVerify: boolean = false;
  riskGt: string = '';
  riskChallenge: string = '';
  riskPath: string = '';

  current(): RoleCombatDataItem | undefined {
    return this.dataItems[0];
  }

  invalidate(): void { this.requestVersion++; }

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
      if (this.valid(version, session)) { this.message = '无法读取本地幻想真境剧诗战绩'; }
    } finally {
      if (version === this.requestVersion) { this.loading = false; this.loaded = true; }
    }
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
      const root: RoleCombatRoot = await RoleCombatService.getInstance().fetch(uid,
        challenge.length > 0 ? challenge : undefined);
      if (!this.valid(version, session)) { return; }
      const items: RoleCombatDataItem[] = root.data.filter((d: RoleCombatDataItem) => d.hasData)
        .sort((a: RoleCombatDataItem, b: RoleCombatDataItem): number => b.schedule.scheduleId - a.schedule.scheduleId);
      for (const item of items) { RoleCombatViewModel.sortBackupAvatars(item); }
      if (items.length > 0 || !this.fromHistory) {
        this.isUnlock = root.isUnlock;
        this.dataItems = items;
        this.fromHistory = false;
        this.recordVersion++;
      }
      // 期数历史入库（每期一条，按 schedule_id UPSERT，对齐 Windows RoleCombatEntry）
      for (let i = 0; i < root.data.length; i++) {
        if (!this.valid(version, session)) { return; }
        const item: RoleCombatDataItem = root.data[i];
        if (!item.hasData || item.schedule.scheduleId <= 0) {
          continue;
        }
        const raw: string = i < root.itemRawJson.length ? root.itemRawJson[i] : '';
        await RoleCombatRepo.saveHistory(uid, session.region, item.schedule.scheduleId, item.schedule.startTime * 1000,
          item.schedule.endTime * 1000, raw);
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
    const records: RoleCombatHistoryEntry[] = await RoleCombatRepo.listHistory(session.uid, session.region);
    const metadata: RoleCombatScheduleMeta[] = await WikiMetaService.getRoleCombatSchedules();
    const periods: ChallengePeriod[] = records.map((entry: RoleCombatHistoryEntry): ChallengePeriod => {
      const period: ChallengePeriod = ChallengePeriod.recorded(entry.scheduleId, entry.startTime, entry.endTime, entry.recordTime);
      try {
        const item: RoleCombatDataItem = RoleCombatRoot.dataItemFromJson(JSON.parse(entry.rawJson));
        if (item.hasData && item.stat.maxRoundId > 0) {
          const tarot: string = item.stat.tarotFinishedCount > 0 ? ` 圣牌 ${item.stat.tarotFinishedCount}` : '';
          period.summary = `第 ${item.stat.maxRoundId} 幕${tarot}`;
        }
      } catch (_) {}
      return period;
    });
    return ChallengePeriod.merge(periods,
      metadata.map((entry: RoleCombatScheduleMeta): ChallengePeriod => new ChallengePeriod(entry.id, entry.begin, entry.end)));
  }

  private async readHistory(session: ChallengeSession, version: number, scheduleId: number): Promise<void> {
    const period: ChallengePeriod | undefined = this.history.find((entry: ChallengePeriod): boolean => entry.scheduleId === scheduleId);
    let item: RoleCombatDataItem;
    if (period !== undefined && !period.hasRecord) {
      item = new RoleCombatDataItem();
      item.schedule.scheduleId = period.scheduleId;
      item.schedule.startTime = period.startTime / 1000;
      item.schedule.endTime = period.endTime / 1000;
    } else {
      const raw: string = await RoleCombatRepo.getRawJson(session.uid, session.region, scheduleId);
      if (!this.valid(version, session)) { return; }
      if (raw.length === 0) { throw new Error('暂无该期存档'); }
      item = RoleCombatRoot.dataItemFromJson(JSON.parse(raw));
      if (!item.hasData) { throw new Error('暂无该期战绩'); }
    }
    RoleCombatViewModel.sortBackupAvatars(item);
    this.dataItems = [item];
    this.isUnlock = true;
    this.fromHistory = true;
    this.recordVersion++;
    this.message = '';
  }

  backToLive(uid: string): Promise<void> { return this.load(uid); }

  /** Windows RoleCombatView：借用/试用优先，其次品质、ElementName 枚举值和角色 ID。 */
  private static sortBackupAvatars(item: RoleCombatDataItem): void {
    const elements: string[] = ['None', 'Pyro', 'Hydro', 'Dendro', 'Electro', 'Cryo', '', 'Anemo', 'Geo'];
    item.detail.backupAvatars = item.detail.backupAvatars.slice().sort((left: RoleCombatAvatar, right: RoleCombatAvatar): number =>
      right.avatarType - left.avatarType || right.rarity - left.rarity ||
      elements.indexOf(right.element) - elements.indexOf(left.element) || right.avatarId - left.avatarId);
  }

  /** 当前档期回合数列表（有回合数据的） */
  rounds(): RoleCombatRoundData[] {
    const cur = this.current();
    if (cur === undefined) {
      return [];
    }
    return cur.detail.roundsData;
  }

}
