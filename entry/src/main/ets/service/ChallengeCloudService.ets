import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { ChallengeCloudAbyssRecord, ChallengeCloudRoleRecord, ChallengeCloudPreview, ChallengeCloudReceipt,
  ChallengeCloudResult, ChallengeCloudSchema, ChallengeCloudAvatar } from '../model/ChallengeCloud';
import { ChallengeGameOwner, ChallengeGameRecordClient } from '../data/network/ChallengeGameRecordClient';
import { ChallengeCloudReceiptStore } from '../data/local/ChallengeCloudReceiptStore';
import { HutaoCloudClient } from '../data/network/HutaoCloudClient';
import { HutaoCloudService } from './HutaoCloudService';

class ChallengeCloudPending {
  owner: ChallengeGameOwner;
  preview: ChallengeCloudPreview;
  cloudRevision: number;
  attempted: boolean = false;
  constructor(owner: ChallengeGameOwner, preview: ChallengeCloudPreview, revision: number) {
    this.owner = owner; this.preview = preview; this.cloudRevision = revision;
  }
}

/** Preparation never transmits to Hutao. Only an explicit confirmation consumes a prepared ticket. */
export class ChallengeCloudService {
  private static nextId: number = 0;
  private static submitting: Set<string> = new Set<string>();
  private version: number = 0;
  private pending: ChallengeCloudPending | undefined = undefined;
  cancel(): void { this.version++; this.pending = undefined; }
  private check(version: number, owner: ChallengeGameOwner, cloudRevision: number): void {
    owner.assertCurrent();
    if (this.version !== version) { throw new Error('采集或预览已取消'); }
    if (HutaoCloudService.getInstance().getSessionRevision() !== cloudRevision) { throw new Error('胡桃通行证已变化，请重新预览'); }
  }
  static async digest(body: string): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new util.TextEncoder().encodeInto(body) });
    const digest: cryptoFramework.DataBlob = await md.digest();
    let hex: string = ''; for (const byte of digest.data) { hex += byte.toString(16).padStart(2, '0'); } return hex;
  }
  async prepare(kind: string, uid: string, expectedSchedule: number): Promise<ChallengeCloudPreview> {
    this.cancel(); const version: number = this.version;
    if (kind !== 'abyss' && kind !== 'roleCombat') { throw new Error('此挑战不支持胡桃云上传'); }
    ChallengeCloudSchema.integer(expectedSchedule, '所选期次', 1);
    const owner: ChallengeGameOwner = new ChallengeGameOwner(uid);
    const cloud: HutaoCloudService = HutaoCloudService.getInstance(); const cloudRevision: number = cloud.getSessionRevision();
    await cloud.initialize(); this.check(version, owner, cloudRevision);
    const passport: string = kind === 'abyss' && cloud.isLoggedIn() ? cloud.getUserName() : '';
    if (passport.length > 254) { throw new Error('通行证信息异常，请重新登录'); }
    const active: () => void = (): void => { this.check(version, owner, cloudRevision); };
    const client: ChallengeGameRecordClient = new ChallengeGameRecordClient(owner, active);
    const query: Record<string, string> = { 'role_id': uid, 'server': owner.region };
    ChallengeCloudSchema.player(await client.get('index', query), uid, owner.region); active();
    const preview: ChallengeCloudPreview = new ChallengeCloudPreview();
    preview.id = ++ChallengeCloudService.nextId; preview.kind = kind; preview.uid = uid; preview.region = owner.region;
    preview.scheduleId = expectedSchedule; preview.passport = passport;
    if (kind === 'abyss') {
      const body: Record<string, Object> = { 'role_id': uid, 'server': owner.region, 'sort_type': 1 };
      const ids: number[] = ChallengeCloudSchema.characterIds(await client.post('character/list', body), uid, owner.region); active();
      body['character_ids'] = ids;
      const avatars: ChallengeCloudAvatar[] = ChallengeCloudSchema.avatars(await client.post('character/detail', body), ids, uid, owner.region); active();
      const abyssQuery: Record<string, string> = { 'role_id': uid, 'server': owner.region, 'schedule_type': '1' };
      const raw: Object = await client.get('spiralAbyss', abyssQuery); active();
      const record: ChallengeCloudAbyssRecord = ChallengeCloudSchema.abyss(uid, owner.region, expectedSchedule, raw, avatars, passport.length > 0 ? passport : null);
      preview.body = JSON.stringify(record); preview.endpoint = '/Record/Upload';
      preview.content = `${record.SpiralAbyss.Floors.length} 层战绩、上下半队伍、伤害/承伤统计；全部 ${avatars.length} 位持有角色的 ID、武器 ID、圣遗物套装 ID 和命座`;
    } else {
      const roleQuery: Record<string, string> = { 'role_id': uid, 'server': owner.region, 'need_detail': 'true', 'active': '1' };
      const record: ChallengeCloudRoleRecord = ChallengeCloudSchema.roleCombat(uid, owner.region, expectedSchedule, await client.get('role_combat', roleQuery)); active();
      preview.body = JSON.stringify(record); preview.endpoint = '/RoleCombat/Upload';
      preview.content = `${record.BackupAvatars.length} 位候补角色 ID、当前期次和客户端标识`;
    }
    if (preview.body.length > 512000) { throw new Error('战绩内容过大，已停止上传准备'); }
    preview.digest = await ChallengeCloudService.digest(preview.body); active();
    const receipts: ChallengeCloudReceipt[] = await ChallengeCloudReceiptStore.list(); active();
    preview.duplicate = receipts.some((receipt: ChallengeCloudReceipt): boolean => receipt.uid === uid &&
      receipt.region === owner.region && receipt.kind === kind && receipt.scheduleId === expectedSchedule && receipt.digest === preview.digest);
    preview.preparedAt = Date.now(); preview.expiresAt = preview.preparedAt + 10 * 60 * 1000;
    this.pending = new ChallengeCloudPending(owner, preview, cloudRevision);
    return this.copy(preview);
  }
  private copy(source: ChallengeCloudPreview): ChallengeCloudPreview {
    const result: ChallengeCloudPreview = new ChallengeCloudPreview();
    result.id = source.id; result.kind = source.kind; result.uid = source.uid; result.region = source.region;
    result.scheduleId = source.scheduleId; result.content = source.content; result.body = source.body;
    result.digest = source.digest; result.preparedAt = source.preparedAt; result.expiresAt = source.expiresAt;
    result.endpoint = source.endpoint; result.passport = source.passport; result.duplicate = source.duplicate; return result;
  }
  async confirm(previewId: number): Promise<ChallengeCloudResult> {
    const pending: ChallengeCloudPending | undefined = this.pending;
    if (pending === undefined || pending.preview.id !== previewId || pending.attempted) { throw new Error('请先重新采集并确认上传预览'); }
    const preview: ChallengeCloudPreview = pending.preview;
    const version: number = this.version;
    this.check(version, pending.owner, pending.cloudRevision);
    if (Date.now() > preview.expiresAt) { this.cancel(); throw new Error('预览已过期，请重新采集'); }
    if (preview.duplicate) { throw new Error('相同内容已有本机成功收据，无需重复上传'); }
    const key: string = `${preview.kind}:${preview.region}:${preview.uid}`;
    if (ChallengeCloudService.submitting.has(key)) { throw new Error('此 UID 的战绩正在提交，请勿重复操作'); }
    // Synchronous one-shot latch, before any asynchronous work or HTTP dispatch.
    pending.attempted = true; ChallengeCloudService.submitting.add(key);
    const userId: number = pending.owner.user.id;
    try {
      // A second preview may have been prepared before another instance completed.
      const receipts: ChallengeCloudReceipt[] = await ChallengeCloudReceiptStore.list();
      this.check(version, pending.owner, pending.cloudRevision);
      if (Date.now() > preview.expiresAt) { throw new Error('预览已过期，请重新采集'); }
      if (receipts.some((receipt: ChallengeCloudReceipt): boolean => receipt.uid === preview.uid &&
        receipt.region === preview.region && receipt.kind === preview.kind && receipt.scheduleId === preview.scheduleId &&
        receipt.digest === preview.digest)) { throw new Error('相同内容已有本机成功收据，无需重复上传'); }
      // No Bearer/Cookie. Anonymous behavior is supported by the audited official server source.
      const response: Record<string, Object> = ChallengeCloudSchema.object(
        await HutaoCloudClient.uploadChallenge(preview.endpoint, preview.body), '服务器提交结果');
      if (response['retcode'] !== 0) { throw new Error('服务器未确认提交成功'); }
      const result: ChallengeCloudResult = new ChallengeCloudResult();
      result.message = typeof response['message'] === 'string' ? String(response['message']).substring(0, 240) : '服务器确认提交成功';
      const receipt: ChallengeCloudReceipt = new ChallengeCloudReceipt();
      receipt.userId = userId; receipt.uid = preview.uid; receipt.region = preview.region; receipt.kind = preview.kind;
      receipt.scheduleId = preview.scheduleId; receipt.digest = preview.digest; receipt.uploadedAt = Date.now();
      // An already sent request cannot be recalled. Its successful acknowledgement remains
      // evidence for the ORIGINAL owner even after navigation/switch; never reassign it.
      try { await ChallengeCloudReceiptStore.save(receipt); result.receiptSaved = true; result.receipt = receipt; }
      catch (e) { result.message += '；本机收据保存失败，请勿立即重复提交'; }
      return result;
    } finally { ChallengeCloudService.submitting.delete(key); }
  }
}
