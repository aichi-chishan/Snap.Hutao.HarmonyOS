/** AvatarProperty SearchTokens and AutoSuggestTokenBox ordering from Remastered 3b7475e. */
export enum CharacterFilterKind {
  Name, Element, Weapon, Quality,
}

export class CharacterFilterToken {
  static readonly LIMIT: number = 5;
  private static nextNameId: number = 0;
  readonly kind: CharacterFilterKind;
  readonly value: string;
  readonly label: string;
  readonly key: string;

  constructor(kind: CharacterFilterKind, value: string, label: string) {
    this.kind = kind;
    this.value = value;
    this.label = label;
    // Windows reuses a preset, but every submitted free-text name is a separate removable chip.
    this.key = kind === CharacterFilterKind.Name ? `name:${++CharacterFilterToken.nextNameId}` : `${kind}:${value}`;
  }

  // Windows orders suggestions by SearchTokenKind, then the preset's numeric Order.
  private static readonly presets: CharacterFilterToken[] = [
    new CharacterFilterToken(CharacterFilterKind.Quality, '4', '四星'),
    new CharacterFilterToken(CharacterFilterKind.Quality, '5', '五星'),
    new CharacterFilterToken(CharacterFilterKind.Quality, '105', '限定五星'),
    new CharacterFilterToken(CharacterFilterKind.Weapon, '1', '单手剑'),
    new CharacterFilterToken(CharacterFilterKind.Weapon, '10', '法器'),
    new CharacterFilterToken(CharacterFilterKind.Weapon, '11', '双手剑'),
    new CharacterFilterToken(CharacterFilterKind.Weapon, '12', '弓'),
    new CharacterFilterToken(CharacterFilterKind.Weapon, '13', '长柄武器'),
    new CharacterFilterToken(CharacterFilterKind.Element, 'Pyro', '火'),
    new CharacterFilterToken(CharacterFilterKind.Element, 'Hydro', '水'),
    new CharacterFilterToken(CharacterFilterKind.Element, 'Dendro', '草'),
    new CharacterFilterToken(CharacterFilterKind.Element, 'Electro', '雷'),
    new CharacterFilterToken(CharacterFilterKind.Element, 'Anemo', '风'),
    new CharacterFilterToken(CharacterFilterKind.Element, 'Cryo', '冰'),
    new CharacterFilterToken(CharacterFilterKind.Element, 'Geo', '岩'),
  ];

  static suggestions(query: string, selected: CharacterFilterToken[]): CharacterFilterToken[] {
    const keyword: string = query.trim().toLowerCase();
    return CharacterFilterToken.presets.filter((preset: CharacterFilterToken): boolean =>
      preset.label.toLowerCase().includes(keyword) &&
      !selected.some((token: CharacterFilterToken): boolean => token.key === preset.key));
  }

  static fromText(text: string): CharacterFilterToken | undefined {
    const label: string = text.trim();
    if (label.length === 0) { return undefined; }
    const preset: CharacterFilterToken | undefined = CharacterFilterToken.presets.find((token: CharacterFilterToken): boolean =>
      token.label.toLowerCase() === label.toLowerCase());
    return preset ?? new CharacterFilterToken(CharacterFilterKind.Name, label, label);
  }
}
