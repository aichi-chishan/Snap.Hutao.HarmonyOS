import { Ledger } from '../model/Ledger';
import { LedgerService } from '../service/LedgerService';
import { UserService } from '../service/UserService';

@Observed
export class LedgerViewModel {
  ledger: Ledger | undefined = undefined;
  availableMonths: number[] = [];
  /** 0 由接口选择最新月份。 */
  month: number = 0;
  loading: boolean = false;
  message: string = '';
  stale: boolean = false;
  private generation: number = 0;
  private uid: string = '';
  private ownerId: number = 0;
  private ownerRevision: number = -1;
  private previousQueryMonth: number = 0;
  private active: boolean = true;

  activate(): void { this.active = true; this.loading = false; }
  dispose(): void { this.active = false; this.generation++; }
  clear(): void {
    this.generation++;
    this.ledger = undefined;
    this.availableMonths = [];
    this.month = 0;
    this.message = '';
    this.stale = false;
    this.loading = false;
  }

  private setAvailableMonths(ledger: Ledger): void {
    const choices: number[] = ledger.optionalMonth.length > 0 ? ledger.optionalMonth.slice() : this.availableMonths.slice();
    if (!choices.includes(ledger.month)) { choices.unshift(ledger.month); }
    this.availableMonths = choices;
  }

  async load(uid: string, ownerId: number, isCurrent: () => boolean): Promise<void> {
    if (!this.active || !isCurrent()) { return; }
    const users: UserService = UserService.getInstance();
    const revision: number = users.sessionRevision();
    const month: number = this.month;
    if (uid !== this.uid || ownerId !== this.ownerId || revision !== this.ownerRevision) {
      this.availableMonths = [];
      this.ledger = undefined;
    } else if (month === 0 ? this.previousQueryMonth !== 0 : this.ledger?.month !== month) {
      this.ledger = undefined;
    }
    const generation: number = ++this.generation;
    this.previousQueryMonth = month;
    this.uid = uid;
    this.ownerId = ownerId;
    this.ownerRevision = revision;
    this.loading = true;
    this.message = '';
    this.stale = false;
    const owns: () => boolean = (): boolean => this.active && this.generation === generation &&
      users.sessionRevision() === revision && isCurrent();
    try {
      const ledger: Ledger = await LedgerService.getInstance().fetchMonth(month, uid, owns);
      if (!owns()) { return; }
      this.ledger = ledger;
      this.setAvailableMonths(ledger);
    } catch (e) {
      if (owns()) {
        this.message = (e as Error).message;
        this.stale = this.ledger !== undefined;
      }
    } finally {
      if (this.generation === generation) { this.loading = false; }
    }
  }
}
