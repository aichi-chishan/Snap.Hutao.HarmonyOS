import { preferences } from '@kit.ArkData';
import { AppContextProvider } from '../../common/AppContext';
import { ChallengeCloudReceipt, ChallengeCloudSchema } from '../../model/ChallengeCloud';

/** Device-local submission evidence, intentionally outside portable user-data backups.
 * No Cookie, Passport name/token, player profile or upload body is retained. */
export class ChallengeCloudReceiptStore {
  static readonly STORE: string = 'challenge_cloud_receipts_v1';
  static readonly LIMIT: number = 100;
  private static tail: Promise<void> = Promise.resolve();
  static async list(): Promise<ChallengeCloudReceipt[]> {
    const store: preferences.Preferences = await preferences.getPreferences(AppContextProvider.getAppContext(), ChallengeCloudReceiptStore.STORE);
    const raw: string = store.getSync('success', '[]') as string;
    if (raw.length > 100000) { return []; }
    try {
      const out: ChallengeCloudReceipt[] = [];
      for (const value of ChallengeCloudSchema.array(JSON.parse(raw) as Object, '上传收据', ChallengeCloudReceiptStore.LIMIT)) {
        const item: Record<string, Object> = ChallengeCloudSchema.object(value, '上传收据');
        const receipt: ChallengeCloudReceipt = new ChallengeCloudReceipt();
        receipt.userId = ChallengeCloudSchema.integer(item['userId'], '本地账号', 1);
        receipt.uid = String(item['uid']); receipt.region = String(item['region']); receipt.kind = String(item['kind']);
        receipt.scheduleId = ChallengeCloudSchema.integer(item['scheduleId'], '期次', 1);
        receipt.uploadedAt = ChallengeCloudSchema.integer(item['uploadedAt'], '时间', 1, Number.MAX_SAFE_INTEGER);
        receipt.digest = String(item['digest']);
        if (!/^\d{9,10}$/.test(receipt.uid) || !/^[a-f0-9]{64}$/.test(receipt.digest) ||
          !['abyss', 'roleCombat'].includes(receipt.kind) || item['retcode'] !== 0) { return []; }
        out.push(receipt);
      }
      return out;
    } catch (e) { return []; }
  }
  static async save(receipt: ChallengeCloudReceipt): Promise<void> {
    const operation: () => Promise<void> = async (): Promise<void> => {
      const all: ChallengeCloudReceipt[] = await ChallengeCloudReceiptStore.list();
      const retained: ChallengeCloudReceipt[] = all.filter((row: ChallengeCloudReceipt): boolean =>
        row.uid !== receipt.uid || row.region !== receipt.region || row.kind !== receipt.kind || row.scheduleId !== receipt.scheduleId || row.digest !== receipt.digest);
      retained.unshift(receipt);
      const store: preferences.Preferences = await preferences.getPreferences(AppContextProvider.getAppContext(), ChallengeCloudReceiptStore.STORE);
      store.putSync('success', JSON.stringify(retained.slice(0, ChallengeCloudReceiptStore.LIMIT))); await store.flush();
    };
    const task: Promise<void> = ChallengeCloudReceiptStore.tail.then(operation, operation);
    ChallengeCloudReceiptStore.tail = task.then(() => {}, () => {}); return task;
  }
}
