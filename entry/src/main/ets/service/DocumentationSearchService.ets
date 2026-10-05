import { HelpDocument } from '../model/HelpDocument';
import { LocalePolicy } from '../model/LocalePolicy';
import { OfflineHelpCatalog } from '../data/help/OfflineHelpCatalog';

class HelpSearchEntry {
  document: HelpDocument;
  text: string;
  constructor(document: HelpDocument, text: string) { this.document = document; this.text = text; }
}

/** At most fifteen normalized packaged indexes. Search performs no IO and every public result is detached. */
export class DocumentationSearchService {
  static readonly MAX_QUERY: number = 120;
  static readonly MAX_TERMS: number = 12;
  private static indexes: Map<string, HelpSearchEntry[]> = new Map<string, HelpSearchEntry[]>();
  private static common: Map<string, string> = new Map<string, string>();
  /** Search-only folding; never alter displayed text, archive identities or exported data. */
  private static normalize(text: string): string {
    return text.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/đ/g, 'd').replace(/ı/g, 'i').replace(/ß/g, 'ss').replace(/œ/g, 'oe').replace(/æ/g, 'ae').replace(/ł/g, 'l');
  }
  private static documentText(doc: HelpDocument): string {
    return DocumentationSearchService.normalize(`${doc.id} ${doc.title} ${doc.summary} ${doc.keywords} ${doc.steps.join(' ')}`);
  }
  private static commonText(id: string): string {
    const cached: string | undefined = DocumentationSearchService.common.get(id);
    if (cached !== undefined) { return cached; }
    const parts: string[] = [];
    for (const locale of LocalePolicy.locales()) {
      const article: HelpDocument | undefined = OfflineHelpCatalog.articles(locale).find((doc: HelpDocument) => doc.id === id);
      if (article !== undefined) { parts.push(DocumentationSearchService.documentText(article)); }
    }
    const text: string = parts.join(' ');
    DocumentationSearchService.common.set(id, text);
    return text;
  }
  private static index(locale: string): HelpSearchEntry[] {
    const key: string = LocalePolicy.resourceLocale(locale);
    const cached: HelpSearchEntry[] | undefined = DocumentationSearchService.indexes.get(key);
    if (cached !== undefined) { return cached; }
    const entries: HelpSearchEntry[] = OfflineHelpCatalog.articles(key).map((doc: HelpDocument): HelpSearchEntry =>
      new HelpSearchEntry(doc, DocumentationSearchService.commonText(doc.id)));
    DocumentationSearchService.indexes.set(key, entries);
    return entries;
  }
  static documents(locale: string = 'zh-Hans'): HelpDocument[] {
    return DocumentationSearchService.index(locale).map((entry: HelpSearchEntry) => entry.document.copy());
  }
  static search(query: string, locale: string = 'zh-Hans'): HelpDocument[] {
    const terms: string[] = DocumentationSearchService.normalize(query.slice(0, DocumentationSearchService.MAX_QUERY).trim())
      .split(/\s+/).filter((term: string) => term.length > 0).slice(0, DocumentationSearchService.MAX_TERMS);
    return DocumentationSearchService.index(locale).filter((entry: HelpSearchEntry) =>
      terms.every((term: string) => entry.text.includes(term))).map((entry: HelpSearchEntry) => entry.document.copy());
  }
  static document(id: string, locale: string): HelpDocument | undefined {
    return DocumentationSearchService.index(locale).find((entry: HelpSearchEntry) => entry.document.id === id)?.document.copy();
  }
  /** Resolve canonical routes, never accept a route from a caller-mutated search result or text input. */
  static routeFor(id: string): string {
    const document: HelpDocument | undefined = DocumentationSearchService.document(id, 'en');
    return document?.route ?? '';
  }
}
