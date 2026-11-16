import { GameDataService } from './GameDataService';
import { AppLocaleService } from './AppLocaleService';
import { GameTextCatalog, GameTextTokens } from '../model/GameTextCatalog';
import { Logger } from '../common/Logger';

/** One language in memory; base game data remains pinned by GameDataService for this process. */
export class LocalizedGameDataService {
  private static locale: string = '';
  private static catalog: Promise<GameTextCatalog> | undefined = undefined;
  private static resolved: GameTextCatalog | undefined = undefined;
  private static readonly fallbackTokens: GameTextTokens = new GameTextTokens();

  static current(): string { return AppLocaleService.current(); }

  static textTokens(): GameTextTokens {
    return LocalizedGameDataService.locale === LocalizedGameDataService.current()
      ? LocalizedGameDataService.resolved?.tokens ?? LocalizedGameDataService.fallbackTokens
      : LocalizedGameDataService.fallbackTokens;
  }

  static async names(table: string, locale: string = LocalizedGameDataService.current()): Promise<Map<number, string>> {
    return (await LocalizedGameDataService.load(locale)).names(table);
  }

  private static load(locale: string): Promise<GameTextCatalog> {
    // A superseded page may finish a captured-locale batch; it must not evict the active display catalog.
    if (locale !== LocalizedGameDataService.current()) { return LocalizedGameDataService.readCatalog(locale); }
    if (LocalizedGameDataService.locale !== locale || LocalizedGameDataService.catalog === undefined) {
      LocalizedGameDataService.locale = locale;
      LocalizedGameDataService.resolved = undefined;
      const loading: Promise<GameTextCatalog> = LocalizedGameDataService.readCatalog(locale).then(
        (catalog: GameTextCatalog): GameTextCatalog => {
          if (LocalizedGameDataService.catalog === loading) { LocalizedGameDataService.resolved = catalog; }
          return catalog;
        });
      LocalizedGameDataService.catalog = loading;
    }
    return LocalizedGameDataService.catalog;
  }

  private static async readCatalog(locale: string): Promise<GameTextCatalog> {
    let catalog: GameTextCatalog | undefined = undefined;
    try {
      const layers: string[] = await GameDataService.readLanguageFiles(GameTextCatalog.fileName(locale));
      for (const text of layers) {
        try { catalog = GameTextCatalog.parse(text, locale, catalog); }
        catch (error) { Logger.warn('LocalizedGameData', `language ${locale} invalid: ${(error as Error).message}`); }
      }
    } catch (error) {
      Logger.warn('LocalizedGameData', `language ${locale} unavailable: ${(error as Error).message}`);
    }
    const loaded: GameTextCatalog = catalog ?? new GameTextCatalog();
    return loaded;
  }

  static async readJson(name: string, locale: string = LocalizedGameDataService.current()): Promise<Object> {
    const catalog: Promise<GameTextCatalog> = LocalizedGameDataService.load(locale);
    const text: string = await GameDataService.readMetadataFile(name);
    const document: Object = JSON.parse(text) as Object;
    return (await catalog).apply(name, document);
  }

  /** Use for display parsers; calculations/imports keep GameDataService.readMetadataFile. */
  static async readMetadataFile(name: string, locale: string = LocalizedGameDataService.current()): Promise<string> {
    return JSON.stringify(await LocalizedGameDataService.readJson(name, locale));
  }
}
