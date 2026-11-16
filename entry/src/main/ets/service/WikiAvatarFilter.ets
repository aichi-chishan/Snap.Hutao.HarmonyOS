import { CultivationFilterKind, CultivationFilterToken } from '../model/CultivationFilterToken';
import { WikiAvatarMeta } from './WikiMetaService';
import { WikiAvatarFilterVocabulary, WikiAvatarFilterWords } from './WikiAvatarFilterVocabulary';

/** Relative order follows Windows SearchTokenKind for the character Wiki. */
export enum WikiAvatarTokenKind {
  Text,
  Quality,
  Weapon,
  Element,
  Association,
  Body,
  Avatar,
}

export class WikiAvatarToken {
  readonly kind: WikiAvatarTokenKind;
  readonly value: string;
  readonly label: string;
  readonly alias: string;

  constructor(kind: WikiAvatarTokenKind, value: string, label: string, alias: string = '') {
    this.kind = kind;
    this.value = value.trim();
    this.label = label;
    this.alias = alias;
  }

  key(): string {
    const identity: string = this.kind === WikiAvatarTokenKind.Text ? this.value.toLowerCase() : this.value;
    return `${this.kind}:${identity}`;
  }
}

/** Windows AvatarFilter grouping, using metadata identities across language changes. */
export class WikiAvatarFilter {
  static readonly LIMIT: number = CultivationFilterToken.LIMIT;
  private static readonly ELEMENT_ORDER: string[] = ['火', '水', '草', '雷', '风', '冰', '岩'];

  static catalog(avatars: WikiAvatarMeta[], locale: string): WikiAvatarToken[] {
    const words: WikiAvatarFilterWords = WikiAvatarFilterVocabulary.words(locale);
    const canonical: WikiAvatarFilterWords = WikiAvatarFilterVocabulary.words('zh-Hans');
    const result: WikiAvatarToken[] = [];
    const qualities: string[] = CultivationFilterToken.options(CultivationFilterKind.Quality)
      .filter((code: string): boolean => Number(code) >= 4);
    const weapons: string[] = CultivationFilterToken.options(CultivationFilterKind.Weapon)
      .sort((left: string, right: string): number => Number(left) - Number(right));
    const elements: string[] = WikiAvatarFilter.ELEMENT_ORDER.filter((code: string): boolean =>
      CultivationFilterToken.options(CultivationFilterKind.Element).includes(code));
    WikiAvatarFilter.appendChoices(result, WikiAvatarTokenKind.Quality, qualities, words.qualities, canonical.qualities);
    WikiAvatarFilter.appendChoices(result, WikiAvatarTokenKind.Weapon, weapons, words.weapons, canonical.weapons);
    WikiAvatarFilter.appendChoices(result, WikiAvatarTokenKind.Element, elements, words.elements, canonical.elements);
    WikiAvatarFilter.appendChoices(result, WikiAvatarTokenKind.Association,
      Object.keys(words.associations), words.associations, canonical.associations);
    WikiAvatarFilter.appendChoices(result, WikiAvatarTokenKind.Body,
      Object.keys(words.bodies), words.bodies, canonical.bodies);
    const ids: Set<number> = new Set<number>();
    for (const avatar of avatars) {
      if (ids.has(avatar.id) || avatar.id <= 0) { continue; }
      ids.add(avatar.id);
      result.push(new WikiAvatarToken(WikiAvatarTokenKind.Avatar, String(avatar.id), avatar.name,
        avatar.canonicalName || avatar.name));
    }
    return result;
  }

  private static appendChoices(result: WikiAvatarToken[], kind: WikiAvatarTokenKind, codes: string[],
    labels: Record<string, string>, aliases: Record<string, string>): void {
    for (const code of codes) {
      const label: string = labels[code];
      if (!label) { continue; }
      const shared: WikiAvatarToken | undefined = kind === WikiAvatarTokenKind.Association
        ? result.find((token: WikiAvatarToken): boolean => token.kind === kind && token.label === label) : undefined;
      if (shared !== undefined) {
        // Fatui 4/15 share a label in most languages, and represent one displayed choice.
        result[result.indexOf(shared)] = new WikiAvatarToken(kind, `${shared.value},${code}`, label, shared.alias);
      } else {
        result.push(new WikiAvatarToken(kind, code, label, aliases[code] ?? label));
      }
    }
  }

  static suggestions(catalog: WikiAvatarToken[], selected: WikiAvatarToken[], input: string): WikiAvatarToken[] {
    if (selected.length >= WikiAvatarFilter.LIMIT) { return []; }
    const query: string = input.trim().toLowerCase();
    return catalog.filter((token: WikiAvatarToken): boolean => !WikiAvatarFilter.covered(selected, token) &&
      (query.length === 0 || token.label.toLowerCase().includes(query) || token.alias.toLowerCase().includes(query)));
  }

  static fromText(catalog: WikiAvatarToken[], input: string): WikiAvatarToken | undefined {
    const text: string = input.trim();
    if (text.length === 0) { return undefined; }
    const query: string = text.toLowerCase();
    return catalog.find((token: WikiAvatarToken): boolean => token.label.toLowerCase() === query) ??
      catalog.find((token: WikiAvatarToken): boolean => token.alias.toLowerCase() === query) ??
      new WikiAvatarToken(WikiAvatarTokenKind.Text, text, text);
  }

  static add(selected: WikiAvatarToken[], token: WikiAvatarToken): WikiAvatarToken[] {
    if (token.value.length === 0 || selected.length >= WikiAvatarFilter.LIMIT || WikiAvatarFilter.covered(selected, token)) {
      return selected.slice(0, WikiAvatarFilter.LIMIT);
    }
    return selected.concat(token);
  }

  private static covered(selected: WikiAvatarToken[], token: WikiAvatarToken): boolean {
    if (selected.some((entry: WikiAvatarToken): boolean => entry.key() === token.key())) { return true; }
    if (token.kind !== WikiAvatarTokenKind.Association) { return false; }
    return token.value.split(',').every((code: string): boolean => selected.some((entry: WikiAvatarToken): boolean =>
      entry.kind === WikiAvatarTokenKind.Association && entry.value.split(',').includes(code)));
  }

  /** Relabel chips without widening a selection made before the language changed. */
  static relabel(catalog: WikiAvatarToken[], selected: WikiAvatarToken[]): WikiAvatarToken[] {
    return selected.map((token: WikiAvatarToken): WikiAvatarToken => {
      if (token.kind === WikiAvatarTokenKind.Text) { return token; }
      const exact: WikiAvatarToken | undefined = catalog.find((entry: WikiAvatarToken): boolean => entry.key() === token.key());
      if (exact !== undefined) { return exact; }
      if (token.kind !== WikiAvatarTokenKind.Association) { return token; }
      const codes: string[] = token.value.split(',');
      const labels: Set<string> = new Set<string>();
      for (const entry of catalog) {
        if (entry.kind === token.kind && entry.value.split(',').some((code: string): boolean => codes.includes(code))) {
          labels.add(entry.label);
        }
      }
      return labels.size > 0
        ? new WikiAvatarToken(token.kind, token.value, Array.from(labels).join(' / '), token.alias) : token;
    });
  }

  static filter(avatars: WikiAvatarMeta[], selected: WikiAvatarToken[]): WikiAvatarMeta[] {
    const groups: Map<WikiAvatarTokenKind, WikiAvatarToken[]> = new Map<WikiAvatarTokenKind, WikiAvatarToken[]>();
    for (const token of selected) {
      const group: WikiAvatarToken[] = groups.get(token.kind) ?? [];
      group.push(token);
      groups.set(token.kind, group);
    }
    const conditions: WikiAvatarToken[][] = Array.from(groups.values());
    return avatars.filter((avatar: WikiAvatarMeta): boolean => conditions.every((group: WikiAvatarToken[]): boolean =>
      group.some((token: WikiAvatarToken): boolean => WikiAvatarFilter.matches(avatar, token))));
  }

  private static matches(avatar: WikiAvatarMeta, token: WikiAvatarToken): boolean {
    switch (token.kind) {
      case WikiAvatarTokenKind.Text:
        return token.value.length > 0 && (avatar.name.toLowerCase().includes(token.value.toLowerCase()) ||
          (avatar.canonicalName || avatar.name).toLowerCase().includes(token.value.toLowerCase()));
      case WikiAvatarTokenKind.Quality: return avatar.quality === Number(token.value);
      case WikiAvatarTokenKind.Weapon: return avatar.weapon === Number(token.value);
      case WikiAvatarTokenKind.Element: return avatar.vision === token.value;
      case WikiAvatarTokenKind.Association: return token.value.split(',').includes(String(avatar.association));
      case WikiAvatarTokenKind.Body: return avatar.body === Number(token.value);
      case WikiAvatarTokenKind.Avatar: return avatar.id === Number(token.value);
      default: return false;
    }
  }
}
