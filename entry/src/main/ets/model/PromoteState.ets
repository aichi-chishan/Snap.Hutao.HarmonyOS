/** An explicit API ascension stage, never inferred from a level or a missing field. */
export class PromoteState {
  static parse(raw: Object | undefined | null): number {
    if ((typeof raw !== 'number' && typeof raw !== 'string') || String(raw).trim().length === 0) {
      return -1;
    }
    const value: number = Number(raw);
    return Number.isSafeInteger(value) && value >= 0 && value <= 6 ? value : -1;
  }

  /** A known stage must also be compatible with the observed level and rarity cap. */
  static validWeapon(level: number, promote: number, rarity: number): boolean {
    const caps: number[] = [20, 40, 50, 60, 70, 80, 90];
    const maxPromote: number = rarity >= 1 && rarity <= 2 ? 4 : 6;
    if (!Number.isInteger(level) || level < 1 || !Number.isInteger(promote) || promote < 0 || promote > maxPromote) {
      return false;
    }
    const min: number = promote === 0 ? 1 : caps[promote - 1];
    return level >= min && level <= caps[promote];
  }

  static label(promote: number): string {
    return promote >= 0 && promote <= 6 ? `突破${promote}` : '突破未知';
  }
}
