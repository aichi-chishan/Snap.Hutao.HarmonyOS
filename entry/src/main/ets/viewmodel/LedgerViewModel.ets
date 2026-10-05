import { Ledger } from '../model/Ledger';
import { LedgerService } from '../service/LedgerService';

@Observed
export class LedgerViewModel {
  ledger: Ledger | undefined = undefined;
  month: number = 0;
  loading: boolean = false;
  message: string = '';
  stale: boolean = false;
  private generation: number = 0;
  private uid: string = '';
  private ownerId: number = 0;
  private active: boolean = true;

  activate(): void { this.active = true; }
  dispose(): void { this.active = false; this.generation++; this.loading = false; }
  clear(): void { this.generation++; this.ledger = undefined; this.month = 0; this.message = ''; this.stale = false; this.loading = false; }

  async load(uid: string, ownerId: number, isCurrent: () => boolean): Promise<void> {
    if (!this.active) { return; }
    const generation: number = ++this.generation;
    const month: number = this.month;
    if (uid !== this.uid || ownerId !== this.ownerId || (month !== 0 && this.ledger?.month !== month)) { this.ledger = undefined; }
    this.uid = uid; this.ownerId = ownerId; this.loading = true; this.message = ''; this.stale = false;
    const owns: () => boolean = (): boolean => this.active && this.generation === generation && isCurrent();
    try {
      const ledger: Ledger = await LedgerService.getInstance().fetchMonth(month, uid, owns);
      if (!owns()) { return; }
      this.ledger = ledger; this.month = ledger.month;
    } catch (e) {
      if (owns()) { this.message = (e as Error).message; this.stale = this.ledger !== undefined; }
    } finally { if (owns()) { this.loading = false; } }
  }
}
