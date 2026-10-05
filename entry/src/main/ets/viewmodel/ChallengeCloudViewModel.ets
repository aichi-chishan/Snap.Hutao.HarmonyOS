import { ChallengeCloudPreview, ChallengeCloudResult, ChallengeCloudReceipt } from '../model/ChallengeCloud';
import { ChallengeCloudService } from '../service/ChallengeCloudService';

@Observed
export class ChallengeCloudViewModel {
  preview: ChallengeCloudPreview | undefined = undefined;
  receipt: ChallengeCloudReceipt | undefined = undefined;
  preparing: boolean = false;
  submitting: boolean = false;
  message: string = '';
  private version: number = 0;
  private service: ChallengeCloudService = new ChallengeCloudService();
  cancel(): void {
    this.version++; this.service.cancel(); this.preview = undefined; this.receipt = undefined; this.preparing = false; this.submitting = false; this.message = '';
  }
  async prepare(kind: string, uid: string, scheduleId: number): Promise<void> {
    if (this.preparing || this.submitting) { return; }
    this.cancel(); const version: number = this.version; this.preparing = true;
    try {
      const preview: ChallengeCloudPreview = await this.service.prepare(kind, uid, scheduleId);
      if (version !== this.version) { return; }
      this.preview = preview;
      if (preview.duplicate) { this.message = '此内容已有本机成功上传收据，无需重复上传'; }
    } catch (e) { if (version === this.version) { this.message = (e as Error).message; } }
    finally { if (version === this.version) { this.preparing = false; } }
  }
  async confirm(): Promise<void> {
    if (this.preview === undefined || this.submitting || this.preparing) { return; }
    const id: number = this.preview.id; const version: number = this.version; this.submitting = true;
    try {
      const result: ChallengeCloudResult = await this.service.confirm(id);
      if (version === this.version) { this.message = result.message; this.receipt = result.receipt; }
    } catch (e) {
      if (version === this.version) { this.message = `${(e as Error).message}。未自动重试；网络中断时服务器可能已收到，请核实后重新预览`; }
    } finally {
      if (version === this.version) { this.submitting = false; this.preview = undefined; }
    }
  }
}
