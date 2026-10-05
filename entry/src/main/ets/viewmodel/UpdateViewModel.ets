import { common } from '@kit.AbilityKit';
import { AppRelease, AppUpdateResult, UpdateChannel, UpdateClient, UpdateStatus } from '../model/AppUpdate';
import { AppUpdateRequest, AppUpdateService } from '../service/AppUpdateService';

@Observed
export class UpdateViewModel {
  client: UpdateClient = new UpdateClient();
  channel: UpdateChannel = UpdateChannel.Stable;
  result: AppUpdateResult = new AppUpdateResult();
  busy: boolean = false;
  opening: boolean = false;
  openFailed: boolean = false;
  private attached: boolean = false;
  private sequence: number = 0;
  private request: AppUpdateRequest | undefined = undefined;
  private linkInFlight: boolean = false;

  activate(): void {
    if (this.attached) { return; }
    const client: UpdateClient = AppUpdateService.readClient();
    if (client.versionName !== this.client.versionName || client.versionCode !== this.client.versionCode ||
      client.bundleName !== this.client.bundleName || client.api !== this.client.api) { this.result = new AppUpdateResult(); }
    this.attached = true; this.client = client; this.opening = this.linkInFlight;
  }
  invalidate(): void { this.attached = false; this.cancel(); this.openFailed = false; }
  cancel(): void {
    this.sequence++;
    const request: AppUpdateRequest | undefined = this.request; this.request = undefined;
    if (request !== undefined) { request.cancel(); }
    if (this.busy) { this.result = new AppUpdateResult(); this.result.status = UpdateStatus.Cancelled; }
    this.busy = false;
  }
  setChannel(channel: UpdateChannel): void {
    if (!this.attached || channel === this.channel || (channel !== UpdateChannel.Stable && channel !== UpdateChannel.Preview)) { return; }
    this.cancel(); this.channel = channel; this.result = new AppUpdateResult(); this.openFailed = false;
  }
  private current(sequence: number): boolean { return this.attached && sequence === this.sequence; }
  async check(): Promise<void> {
    if (!this.attached || this.busy) { return; }
    const sequence: number = ++this.sequence;
    const request: AppUpdateRequest = new AppUpdateRequest(); this.request = request;
    this.client = AppUpdateService.readClient(); this.busy = true; this.openFailed = false;
    this.result = new AppUpdateResult(); this.result.status = UpdateStatus.Checking;
    try {
      const result: AppUpdateResult = await request.run(this.client, this.channel);
      if (this.current(sequence) && this.request === request) { this.result = result; }
    } catch (_) {
      if (this.current(sequence)) { this.result = new AppUpdateResult(); this.result.status = UpdateStatus.NetworkError; }
    } finally {
      if (this.current(sequence) && this.request === request) { this.request = undefined; this.busy = false; }
    }
  }
  async open(context: common.UIAbilityContext, project: boolean = false): Promise<void> {
    if (!this.attached || this.linkInFlight || this.busy) { return; }
    const release: AppRelease | undefined = this.result.release;
    if (!project && release === undefined) { return; }
    const sequence: number = this.sequence;
    this.opening = true; this.linkInFlight = true; this.openFailed = false;
    try {
      if (project) { await AppUpdateService.openProjectReleases(context); }
      else if (release !== undefined) { await AppUpdateService.openDetails(context, release.url, release.tag); }
    } catch (_) { if (this.current(sequence)) { this.openFailed = true; } }
    finally { this.linkInFlight = false; if (this.attached) { this.opening = false; } }
  }
}
