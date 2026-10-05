import { CommonOutcome, CommonOutcomeId } from './CommonOutcome';

export class DiagnosticEnvironment {
  appVersion: string = 'unknown';
  api: number = 0;
  deviceType: string = 'unknown';
  theme: string = 'unknown';
}
export class DiagnosticPreview {
  feature: string = 'privacy';
  outcome: CommonOutcomeId = CommonOutcomeId.Failed;
  generatedAt: number = 0;
  environment: DiagnosticEnvironment | undefined = undefined;
}

/** Allowlist reconstruction, not regex redaction of arbitrary logs. No account-bearing input is accepted. */
export class DiagnosticPolicy {
  static feature(value: string): string {
    return ['accounts', 'import', 'data', 'backups', 'daily-note', 'devices', 'privacy'].includes(value) ? value : 'privacy';
  }
  static sanitize(input: DiagnosticPreview): DiagnosticPreview {
    const result: DiagnosticPreview = new DiagnosticPreview();
    result.feature = DiagnosticPolicy.feature(input.feature);
    result.outcome = CommonOutcome.known(input.outcome) ? input.outcome : CommonOutcomeId.Failed;
    result.generatedAt = Number.isSafeInteger(input.generatedAt) && input.generatedAt >= 1577836800000 &&
      input.generatedAt < 4102444800000 ? input.generatedAt : 0;
    if (input.environment !== undefined) {
      const source: DiagnosticEnvironment = input.environment;
      const target: DiagnosticEnvironment = new DiagnosticEnvironment();
      target.appVersion = /^\d{1,3}(?:\.\d{1,3}){1,3}(?:-(?:beta|rc)\d{0,3})?$/.test(source.appVersion) ? source.appVersion : 'unknown';
      target.api = Number.isSafeInteger(source.api) && source.api >= 24 && source.api <= 100 ? source.api : 0;
      target.deviceType = ['phone', 'tablet', '2in1'].includes(source.deviceType) ? source.deviceType : 'unknown';
      target.theme = ['light', 'dark', 'system'].includes(source.theme) ? source.theme : 'unknown';
      result.environment = target;
    }
    return result;
  }
  static serialize(input: DiagnosticPreview): string {
    const value: DiagnosticPreview = DiagnosticPolicy.sanitize(input);
    const lines: string[] = ['Snap.Hutao.HarmonyOS diagnostics v1', `Feature: ${value.feature}`,
      `Outcome: ${value.outcome || 'none'}`,
      `Generated (UTC): ${value.generatedAt > 0 ? new Date(value.generatedAt).toISOString() : 'unknown'}`];
    if (value.environment !== undefined) {
      lines.push(`App version: ${value.environment.appVersion}`, `API: ${value.environment.api || 'unknown'}`,
        `Device category: ${value.environment.deviceType}`, `Theme: ${value.environment.theme}`);
    }
    lines.push('No account data, credentials, UIDs or raw logs included.');
    return lines.join('\n');
  }
}
