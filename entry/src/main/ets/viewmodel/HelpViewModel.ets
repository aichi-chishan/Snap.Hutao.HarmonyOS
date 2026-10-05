import { CommonOutcome, CommonOutcomeId } from '../model/CommonOutcome';
import { CommonOutcomeText } from '../model/CommonOutcomeText';
import { DiagnosticPolicy, DiagnosticPreview } from '../model/DiagnosticPolicy';
import { HelpDocument } from '../model/HelpDocument';
import { LocalePolicy } from '../model/LocalePolicy';
import { DocumentationSearchService } from '../service/DocumentationSearchService';
import { SupportService } from '../service/SupportService';

@Observed
export class HelpViewModel {
  locale: string = 'zh-Hans';
  query: string = '';
  documents: HelpDocument[] = [];
  selectedId: string = '';
  includeEnvironment: boolean = false;
  issue: CommonOutcomeId = CommonOutcomeId.Failed;
  preview: DiagnosticPreview | undefined = undefined;
  busy: boolean = false;
  outcome: CommonOutcome = new CommonOutcome();
  private attached: boolean = false;
  private sequence: number = 0;
  private copying: boolean = false;

  /** Search-only activation: no device, account, clipboard, network or diagnostic collection. */
  activate(locale: string): void {
    if (!this.attached) { this.busy = this.copying; }
    this.attached = true;
    this.setLocale(locale);
  }
  invalidate(): void {
    this.attached = false;
    this.clearPreview();
  }
  setLocale(locale: string): void { this.locale = LocalePolicy.resourceLocale(locale); this.refresh(); }
  setQuery(query: string): void { this.query = query.slice(0, DocumentationSearchService.MAX_QUERY); this.refresh(); }
  private refresh(): void {
    this.documents = DocumentationSearchService.search(this.query, this.locale);
    if (this.selectedId.length > 0 && !this.documents.some((doc: HelpDocument) => doc.id === this.selectedId)) {
      this.selectedId = ''; this.clearPreview();
    }
  }
  select(id: string): void {
    const allowed: boolean = this.documents.some((doc: HelpDocument) => doc.id === id);
    const next: string = allowed ? id : '';
    if (this.selectedId !== next) { this.selectedId = next; this.clearPreview(); }
  }
  selected(): HelpDocument | undefined { return DocumentationSearchService.document(this.selectedId, this.locale); }
  route(): string { return DocumentationSearchService.routeFor(this.selectedId); }
  setEnvironment(include: boolean): void {
    if (this.includeEnvironment !== include) { this.includeEnvironment = include; this.clearPreview(); }
  }
  setIssue(id: CommonOutcomeId): void {
    const allowed: CommonOutcomeId[] = [CommonOutcomeId.Failed, CommonOutcomeId.NetworkUnavailable,
      CommonOutcomeId.PermissionRequired, CommonOutcomeId.InvalidFile, CommonOutcomeId.LoginExpired, CommonOutcomeId.Unsupported];
    const next: CommonOutcomeId = allowed.includes(id) ? id : CommonOutcomeId.Failed;
    if (this.issue !== next) { this.issue = next; this.clearPreview(); }
  }
  clearPreview(): void {
    this.sequence++; this.preview = undefined; this.busy = this.copying; this.outcome = new CommonOutcome();
  }
  previewText(): string { return this.preview === undefined ? '' : DiagnosticPolicy.serialize(this.preview); }
  message(): string { return CommonOutcomeText.text(this.outcome, this.locale); }
  advice(): string { return CommonOutcomeText.text(new CommonOutcome(this.issue), this.locale); }
  private current(sequence: number): boolean { return this.attached && sequence === this.sequence; }

  async generatePreview(): Promise<boolean> {
    if (!this.attached || this.busy || this.selected() === undefined) { return false; }
    const sequence: number = ++this.sequence;
    this.busy = true; this.preview = undefined; this.outcome = new CommonOutcome(CommonOutcomeId.Preparing);
    try {
      const result: DiagnosticPreview = await SupportService.previewDiagnostics(this.selectedId, this.issue, this.includeEnvironment);
      if (!this.current(sequence)) { return false; }
      this.preview = DiagnosticPolicy.sanitize(result); this.outcome = new CommonOutcome(CommonOutcomeId.Ready);
      return true;
    } catch (_) {
      if (!this.current(sequence)) { return false; }
      this.outcome = new CommonOutcome(CommonOutcomeId.Failed); return true;
    } finally { if (this.current(sequence)) { this.busy = false; } }
  }
  async copyPreview(): Promise<boolean> {
    if (!this.attached || this.busy || this.copying || this.preview === undefined) { return false; }
    const sequence: number = ++this.sequence;
    const preview: DiagnosticPreview = DiagnosticPolicy.sanitize(this.preview);
    this.busy = true; this.copying = true;
    try {
      await SupportService.copyDiagnosticPreview(preview);
      if (!this.current(sequence)) { return false; }
      this.outcome = new CommonOutcome(CommonOutcomeId.CopyComplete); return true;
    } catch (_) {
      if (!this.current(sequence)) { return false; }
      this.outcome = new CommonOutcome(CommonOutcomeId.CopyFailed); return true;
    } finally {
      this.copying = false;
      if (this.attached) { this.busy = false; }
    }
  }
}
