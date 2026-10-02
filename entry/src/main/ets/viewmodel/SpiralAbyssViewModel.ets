/**
 * SpiralAbyssViewModel.ets
 * 深渊页状态容器：当期/上期数据、加载状态（含 1034 风控极验重放）。
 */
import { SpiralAbyssData } from '../model/SpiralAbyss';
import { SpiralAbyssService } from '../service/SpiralAbyssService';
import { SpiralAbyssRepo, AbyssHistoryEntry } from '../data/repo/SpiralAbyssRepo';
import { TowerMetadataService } from '../service/TowerMetadataService';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';
import { RegionUtil } from '../common/Constants';

@Observed
export class SpiralAbyssViewModel {
  private requestedUid: string = '';
  private requestVersion: number = 0;
  abyss: SpiralAbyssData | undefined = undefined;
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 1=当期 2=上期 */
  scheduleType: number = 1;
  /** 本地累积的期数历史（新期在前） */
  history: AbyssHistoryEntry[] = [];
  /** 当前 abyss 是否来自历史存档（false=实时数据） */
  fromHistory: boolean = false;
  /** 风控需人机验证（true 时 UI 跳转极验页） */
  needRiskVerify: boolean = false;
  riskGt: string = '';
  riskChallenge: string = '';
  riskPath: string = '';

  async load(uid: string): Promise<void> {
    const requestVersion: number = ++this.requestVersion;
    if (this.requestedUid !== uid) {
      this.history = [];
      this.fromHistory = false;
      this.message = '';
      this.clearData();
    }
    this.requestedUid = uid;
    if (uid.length === 0) {
      this.message = '请先在「账号与数据」选择默认 UID';
      this.loaded = true;
      return;
    }
    this.loading = true;
    try {
      const challenge: string = RiskUiHelper.consumePendingChallenge();
      const abyss: SpiralAbyssData = await SpiralAbyssService.getInstance().fetch(uid, this.scheduleType,
        challenge.length > 0 ? challenge : undefined);
      if (requestVersion !== this.requestVersion || uid !== this.requestedUid) {
        return;
      }
      this.abyss = abyss;
      this.fromHistory = false;
      this.message = '';
      // 塔元数据预载（波次/祝福渲染依赖）+ 期数历史入库
      await TowerMetadataService.preload();
      await SpiralAbyssRepo.saveHistory(uid, RegionUtil.regionOfUid(uid), abyss.scheduleId, abyss.startTime,
        abyss.endTime, abyss.totalStar, abyss.rawJson);
      // Windows 一次刷新同时保留当期与上期；失败不丢已成功保存的选中期。
      try {
        const other: SpiralAbyssData = await SpiralAbyssService.getInstance().fetch(uid,
          this.scheduleType === 1 ? 2 : 1);
        await SpiralAbyssRepo.saveHistory(uid, RegionUtil.regionOfUid(uid), other.scheduleId,
          other.startTime, other.endTime, other.totalStar, other.rawJson);
      } catch (e) {
        if (requestVersion === this.requestVersion && uid === this.requestedUid) {
          this.message = `当前选中期已更新，另一档期刷新失败：${(e as Error).message}`;
        }
      }
      const history: AbyssHistoryEntry[] = await SpiralAbyssRepo.listHistory(uid, RegionUtil.regionOfUid(uid));
      if (uid === this.requestedUid) {
        this.history = history;
      }
    } catch (e) {
      if (requestVersion !== this.requestVersion || uid !== this.requestedUid) {
        return;
      }
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
      if (requestVersion === this.requestVersion && uid === this.requestedUid) {
        this.loading = false;
        this.loaded = true;
      }
    }
  }

  /** 切换当期/上期 */
  async switchSchedule(uid: string, type: number): Promise<void> {
    if (this.scheduleType === type) {
      return;
    }
    this.scheduleType = type;
    await this.load(uid);
  }

  /** 刷新本地期数历史列表（进页时） */
  async loadHistoryList(uid: string): Promise<void> {
    await TowerMetadataService.preload();
    const history: AbyssHistoryEntry[] = await SpiralAbyssRepo.listHistory(uid, RegionUtil.regionOfUid(uid));
      if (uid === this.requestedUid) {
        this.history = history;
      }
  }

  /** 回看历史期数（本地存档重建，不发网络请求） */
  async loadFromHistory(uid: string, scheduleId: number): Promise<void> {
    const requestVersion: number = ++this.requestVersion;
    this.requestedUid = uid;
    this.loading = false;
    const raw: string = await SpiralAbyssRepo.getRawJson(uid, RegionUtil.regionOfUid(uid), scheduleId);
    if (raw.length === 0 || requestVersion !== this.requestVersion || uid !== this.requestedUid) {
      return;
    }
    this.abyss = SpiralAbyssData.fromJson(JSON.parse(raw));
    this.fromHistory = true;
    this.message = `历史存档 · 第 ${scheduleId} 期`;
    this.loaded = true;
    await TowerMetadataService.preload();
  }

  /** 回到实时数据（按当前 scheduleType 重新拉取） */
  async backToLive(uid: string): Promise<void> {
    this.fromHistory = false;
    await this.load(uid);
  }

  private clearData(): void {
    this.abyss = undefined;
  }

  /** 极验完成后由 UI 调用：清除标记并重新加载 */
  resetRiskAndReload(uid: string): void {
    this.needRiskVerify = false;
    this.load(uid).then(() => {
    });
  }
}
