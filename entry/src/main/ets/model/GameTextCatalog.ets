import { LocalePolicy } from './LocalePolicy';

/** Windows' localized replacements for named placeholders in official game text. */
export class GameTextTokens {
  nickname: string = '旅行者';
  realName: string = '流浪者';
  timeZone: string = '服务器时区';
  heShe: string = '他/她';
  firstPerson: string = '我';
  princePrincess: string = '王子/公主';
}

/** Display-only Snap.Metadata overlays. Identity, icons and numeric data come from the selected cohort. */
export class GameTextCatalog {
  private files: Record<string, Object> = {};
  private fallback: GameTextCatalog | undefined = undefined;
  private nameIndexes: Map<string, Map<number, string>> = new Map<string, Map<number, string>>();
  tokens: GameTextTokens = new GameTextTokens();

  /** ID-based display names for separate inventory/relic catalogs; callers keep their original records. */
  names(table: string): Map<number, string> {
    const cached: Map<number, string> | undefined = this.nameIndexes.get(table);
    if (cached !== undefined) { return cached; }
    const names: Map<number, string> = new Map<number, string>(this.fallback?.names(table));
    for (const row of GameTextCatalog.rows(this.files[table])) {
      const rawName: Object | undefined = row['name'] ?? row['Name'] ?? row['n'] ?? row['Title'];
      if (typeof rawName !== 'string' || rawName.length === 0) { continue; }
      const name: string = rawName;
      if (table === 'Reliquary.json') {
        const ids: number[] = Array.isArray(row['Ids']) ? row['Ids'] as number[] : [];
        for (const id of ids) { if (typeof id === 'number' && Number.isSafeInteger(id)) { names.set(id, name); } }
      } else {
        const id: Object | undefined = row['id'] ?? row['Id'] ?? row['SetId'];
        if (typeof id === 'number' && Number.isSafeInteger(id)) { names.set(id, name); }
      }
    }
    this.nameIndexes.set(table, names);
    return names;
  }

  static fileName(locale: string): string { return `locale_${LocalePolicy.resourceLocale(locale)}.json`; }
  static isFile(name: string): boolean {
    return LocalePolicy.locales().some((locale: string): boolean => GameTextCatalog.fileName(locale) === name);
  }

  static parse(text: string, locale: string, fallback?: GameTextCatalog): GameTextCatalog {
    const raw: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    if (raw['schema'] !== 1 || raw['locale'] !== locale || typeof raw['files'] !== 'object'
      || raw['files'] === null || Array.isArray(raw['files'])) {
      throw new Error('游戏语言数据格式不匹配');
    }
    const result: GameTextCatalog = new GameTextCatalog();
    result.files = raw['files'] as Record<string, Object>;
    for (const name of Object.keys(result.files)) {
      const rows: Object = result.files[name];
      if (!Array.isArray(rows) || (rows as Object[]).some((row: Object): boolean =>
        row === null || typeof row !== 'object' || Array.isArray(row))) {
        throw new Error('游戏语言条目格式不匹配');
      }
    }
    result.fallback = fallback;
    if (fallback !== undefined) {
      result.tokens.nickname = fallback.tokens.nickname;
      result.tokens.realName = fallback.tokens.realName;
      result.tokens.timeZone = fallback.tokens.timeZone;
      result.tokens.heShe = fallback.tokens.heShe;
      result.tokens.firstPerson = fallback.tokens.firstPerson;
      result.tokens.princePrincess = fallback.tokens.princePrincess;
    }
    if (typeof raw['specialNames'] === 'object' && raw['specialNames'] !== null && !Array.isArray(raw['specialNames'])) {
      const names: Record<string, Object> = raw['specialNames'] as Record<string, Object>;
      result.tokens.nickname = GameTextCatalog.token(names, 'nickname', result.tokens.nickname);
      result.tokens.realName = GameTextCatalog.token(names, 'realName', result.tokens.realName);
      result.tokens.timeZone = GameTextCatalog.token(names, 'timeZone', result.tokens.timeZone);
      result.tokens.heShe = GameTextCatalog.token(names, 'heShe', result.tokens.heShe);
      result.tokens.firstPerson = GameTextCatalog.token(names, 'firstPerson', result.tokens.firstPerson);
      result.tokens.princePrincess = GameTextCatalog.token(names, 'princePrincess', result.tokens.princePrincess);
    }
    return result;
  }

  private static token(names: Record<string, Object>, key: string, fallback: string): string {
    const text: Object | undefined = names[key];
    return typeof text === 'string' && text.length > 0 ? text : fallback;
  }

  private static rows(raw: Object | undefined): Record<string, Object>[] {
    if (!Array.isArray(raw)) { return []; }
    return (raw as Object[]).filter((row: Object): boolean =>
      row !== null && typeof row === 'object' && !Array.isArray(row)) as Record<string, Object>[];
  }

  /** Explicit allowlist: a language pack cannot replace IDs, stats, icons or relationship arrays. */
  private static texts(target: Record<string, Object>, source: Record<string, Object>, fields: string[]): void {
    for (const field of fields) {
      const text: Object | undefined = source[field];
      if (typeof text === 'string' && text.length > 0) { target[field] = text; }
    }
  }

  private static textArray(target: Record<string, Object>, source: Record<string, Object>, field: string): void {
    const texts: Object | undefined = source[field];
    if (Array.isArray(texts)) {
      const entries: Object[] = texts as Object[];
      if (entries.length > 0 && entries.every((text: Object): boolean => typeof text === 'string')) {
        const original: string[] = Array.isArray(target[field]) ? target[field] as string[] : [];
        if (field === 'cv' || field === 'affixDesc') {
          // CV language slots and refinement ranks are positional and must keep their original count.
          const length: number = original.length > 0 ? original.length : entries.length;
          const merged: string[] = [];
          for (let index: number = 0; index < length; index++) {
            const candidate: string = String(entries[index] ?? '');
            merged.push(candidate.length > 0 ? candidate : original[index] ?? '');
          }
          target[field] = merged;
        } else { target[field] = entries; }
      }
    }
  }

  private static canonical(target: Record<string, Object>, field: string): void {
    if (target['canonicalName'] === undefined) { target['canonicalName'] = String(target[field] ?? ''); }
  }

  private static key(name: string, row: Record<string, Object>): string {
    if (name === 'monster_meta.json') { return String(row['describeId']); }
    if (name === 'NameCard.json') { return String(row['Icon']); }
    if (name === 'Chapter.json') { return String(row['Id']); }
    if (name === 'GachaEvent.json') {
      return `${row['Type']}|${Date.parse(String(row['From']))}|${Date.parse(String(row['To']))}|${row['Order']}`;
    }
    return String(row['id'] ?? row['Id']);
  }

  private static skills(target: Record<string, Object>, source: Record<string, Object>, field: string): void {
    const translations: Record<string, Object>[] = GameTextCatalog.rows(source[field]);
    for (const skill of GameTextCatalog.rows(target[field])) {
      GameTextCatalog.canonical(skill, 'n');
      const translated: Record<string, Object> | undefined = translations.find(
        (entry: Record<string, Object>): boolean => entry['i'] === skill['i']);
      if (translated !== undefined) { GameTextCatalog.texts(skill, translated, ['n', 'd']); }
    }
  }

  private static stories(target: Record<string, Object>, source: Record<string, Object>, field: string): void {
    const translations: Record<string, Object>[] = GameTextCatalog.rows(source[field]);
    const original: Record<string, Object>[] = GameTextCatalog.rows(target[field]);
    for (let index: number = 0; index < original.length; index++) {
      const translated: Record<string, Object> | undefined = translations.find(
        (entry: Record<string, Object>): boolean => entry['id'] === index);
      if (original[index]['canonicalTitle'] === undefined) { original[index]['canonicalTitle'] = original[index]['t']; }
      if (original[index]['canonicalContext'] === undefined) { original[index]['canonicalContext'] = original[index]['c']; }
      // These source records have no ID. Never apply an old positional translation to a new chapter.
      if (translated !== undefined && translated['sourceTitle'] === original[index]['canonicalTitle']
        && (translated['sourceContext'] === undefined || translated['sourceContext'] === original[index]['canonicalContext'])) {
        GameTextCatalog.texts(original[index], translated, ['t', 'c']);
      }
    }
  }

  private static avatar(target: Record<string, Object>, source: Record<string, Object>): void {
    GameTextCatalog.texts(target, source, ['name', 'title', 'detail', 'native', 'constellation']);
    // Synthesized travelers can explicitly leave official profile fields blank instead of retaining Chinese text.
    if (target['id'] === 10000005 || target['id'] === 10000007) {
      for (const field of ['title', 'native']) {
        if (source[field] === '') { target[field] = ''; }
      }
    }
    // Existing consumers use vision as an element key and birth as M/D, not presentation text.
    if (typeof source['vision'] === 'string' && String(source['vision']).length > 0) {
      target['visionName'] = source['vision'];
    }
    if (typeof source['birth'] === 'string' && String(source['birth']).length > 0) {
      target['birthText'] = source['birth'];
    }
    GameTextCatalog.textArray(target, source, 'cv');
    GameTextCatalog.skills(target, source, 'skills');
    GameTextCatalog.skills(target, source, 'talents');
    GameTextCatalog.stories(target, source, 'fetters');
    GameTextCatalog.stories(target, source, 'stories');
    const costumes: Record<string, Object>[] = GameTextCatalog.rows(source['costumes']);
    for (const costume of GameTextCatalog.rows(target['costumes'])) {
      GameTextCatalog.canonical(costume, 'name');
      const translated: Record<string, Object> | undefined = costumes.find(
        (entry: Record<string, Object>): boolean => entry['id'] === costume['id']);
      if (translated !== undefined) { GameTextCatalog.texts(costume, translated, ['name', 'description']); }
    }
  }

  private static row(name: string, target: Record<string, Object>, source: Record<string, Object>): void {
    switch (name) {
      case 'avatar_meta.json': GameTextCatalog.avatar(target, source); break;
      case 'weapon_meta.json':
        GameTextCatalog.texts(target, source, ['name', 'description', 'affixName']);
        GameTextCatalog.textArray(target, source, 'affixDesc'); break;
      case 'monster_meta.json':
        GameTextCatalog.texts(target, source, ['name', 'title', 'description']);
        GameTextCatalog.textArray(target, source, 'affixes'); break;
      case 'material_meta.json': GameTextCatalog.texts(target, source, ['n']); break;
      case 'Achievement.json': GameTextCatalog.texts(target, source, ['Title', 'Description']); break;
      case 'Chapter.json': GameTextCatalog.texts(target, source, ['Number', 'Title']); break;
      case 'AchievementGoal.json':
      case 'ProfilePicture.json':
      case 'BeyondItem.json':
      case 'GachaEvent.json':
      case 'HardChallengeSchedule.json': GameTextCatalog.texts(target, source, ['Name']); break;
      case 'NameCard.json': GameTextCatalog.texts(target, source, ['Name', 'Description']); break;
      case 'TowerSchedule.json':
        GameTextCatalog.texts(target, source, ['BuffName']);
        GameTextCatalog.textArray(target, source, 'Descriptions'); break;
      case 'TowerFloor.json': GameTextCatalog.textArray(target, source, 'Descriptions'); break;
    }
  }

  /** Mutates a freshly parsed base document, never the cached language pack. */
  apply(name: string, document: Object): Object {
    if (this.fallback !== undefined) { this.fallback.apply(name, document); }
    const translations: Map<string, Record<string, Object>> = new Map<string, Record<string, Object>>();
    for (const row of GameTextCatalog.rows(this.files[name])) {
      translations.set(GameTextCatalog.key(name, row), row);
    }
    if (name === 'material_meta.json') {
      const materials: Record<string, Object> = document as Record<string, Object>;
      for (const id of Object.keys(materials)) {
        const material: Record<string, Object> = materials[id] as Record<string, Object>;
        GameTextCatalog.canonical(material, 'n');
        const translated: Record<string, Object> | undefined = translations.get(id);
        if (translated !== undefined) { GameTextCatalog.row(name, material, translated); }
      }
      return document;
    }
    for (const row of GameTextCatalog.rows(document)) {
      if (name !== 'Chapter.json') {
        if (row['name'] !== undefined) { GameTextCatalog.canonical(row, 'name'); }
        else if (row['Name'] !== undefined) { GameTextCatalog.canonical(row, 'Name'); }
        else if (row['Title'] !== undefined) { GameTextCatalog.canonical(row, 'Title'); }
      }
      const translated: Record<string, Object> | undefined = translations.get(GameTextCatalog.key(name, row));
      if (translated !== undefined) { GameTextCatalog.row(name, row, translated); }
    }
    return document;
  }
}
