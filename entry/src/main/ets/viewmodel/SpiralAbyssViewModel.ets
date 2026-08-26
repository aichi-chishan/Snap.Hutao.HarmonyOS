/**
 * SpiralAbyssViewModel.ets
 * 深渊页状态容器：当期/上期数据、加载状态（含 1034 风控极验重放）。
 */
import { SpiralAbyssData } from '../model/SpiralAbyss';
import { SpiralAbyssService } from '../service/SpiralAbyssService';
import { RiskControlError } from '../data/network/RiskVerifier';
import { RiskUiHelper } from '../common/RiskUiHelper';

@Observed
export class SpiralAbyssViewModel {
  abyss: SpiralAbyssData | undefined = undefined;
  loading: boolean = false;
  message: string = '';
  loaded: boolean = false;
  /** 1=当期 2=上期 */
  scheduleType: number = 1;
  /** 风控需人机验证（true 时 UI 跳转极验页） */
  needRiskVerify: boolean = false;
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
      this.abyss = await SpiralAbyssService.getInstance().fetch(uid, this.scheduleType,
        challenge.length > 0 ? challenge : undefined);
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
      this.abyss = undefined;
    } finally {
      this.loading = false;
      this.loaded = true;
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

  /** 极验完成后由 UI 调用：清除标记并重新加载 */
  resetRiskAndReload(uid: string): void {
    this.needRiskVerify = false;
    this.load(uid).then(() => {
    });
  }
}
