export enum CultivationFilterKind {
  Name,
  Target,
  Quality,
  Weapon,
  Element,
}

/** A selected condition for the saved cultivation entries. Values are metadata codes. */
export class CultivationFilterToken {
  static readonly LIMIT: number = 5;
  readonly kind: CultivationFilterKind;
  readonly value: string;

  constructor(kind: CultivationFilterKind, value: string) {
    this.kind = kind;
    this.value = value.trim();
  }

  key(): string {
    const value: string = this.kind === CultivationFilterKind.Name ? this.value.toLocaleLowerCase() : this.value;
    return `${this.kind}:${value}`;
  }

  static options(kind: CultivationFilterKind): string[] {
    switch (kind) {
      case CultivationFilterKind.Target: return ['1', '2'];
      case CultivationFilterKind.Quality: return ['1', '2', '3', '4', '5', '105'];
      case CultivationFilterKind.Weapon: return ['1', '11', '13', '10', '12'];
      case CultivationFilterKind.Element: return ['火', '水', '雷', '草', '冰', '风', '岩'];
      default: return [];
    }
  }
}
