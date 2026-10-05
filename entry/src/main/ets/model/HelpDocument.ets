/** Detached app-authored help; stable identities and navigation are independent of display language. */
export class HelpDocument {
  id: string;
  title: string;
  summary: string;
  steps: string[];
  keywords: string;
  route: string;
  constructor(id: string, title: string, summary: string, steps: string[], keywords: string, route: string) {
    this.id = id; this.title = title; this.summary = summary; this.steps = steps.slice();
    this.keywords = keywords; this.route = route;
  }
  copy(): HelpDocument { return new HelpDocument(this.id, this.title, this.summary, this.steps, this.keywords, this.route); }
}
