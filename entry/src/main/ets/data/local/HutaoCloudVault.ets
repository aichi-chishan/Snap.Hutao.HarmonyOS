import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { HutaoCloudSession } from '../../model/HutaoCloud';

/** Separate asset namespace; cloud bearer tokens never enter the miHoYo Cookie vault. */
export class HutaoCloudVault {
  private static bytes(value: string): Uint8Array {
    return new util.TextEncoder().encodeInto(value);
  }

  private static alias(): Uint8Array {
    return HutaoCloudVault.bytes('snap_hutao_cloud_remastered_primary_v1');
  }

  static async save(session: HutaoCloudSession): Promise<void> {
    const values: asset.AssetMap = new Map();
    values.set(asset.Tag.ALIAS, HutaoCloudVault.alias());
    values.set(asset.Tag.SECRET, HutaoCloudVault.bytes(JSON.stringify(session)));
    values.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    values.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(values);
  }

  static async load(): Promise<HutaoCloudSession> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, HutaoCloudVault.alias());
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows: asset.AssetMap[] = await asset.query(query);
      if (rows.length === 0) { return new HutaoCloudSession(); }
      const secret: Uint8Array = rows[0].get(asset.Tag.SECRET) as Uint8Array;
      const object: Record<string, Object> = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(secret)) as Record<string, Object>;
      const session: HutaoCloudSession = new HutaoCloudSession();
      session.userName = String(object['userName'] ?? '');
      session.accessToken = String(object['accessToken'] ?? '');
      session.refreshToken = String(object['refreshToken'] ?? '');
      session.expiresAt = Number(object['expiresAt'] ?? 0);
      return session;
    } catch (error) {
      return new HutaoCloudSession();
    }
  }

  static async clear(): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, HutaoCloudVault.alias());
    await asset.remove(query);
  }
}
