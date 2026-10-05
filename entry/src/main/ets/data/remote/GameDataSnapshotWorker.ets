import { taskpool } from '@kit.ArkTS';
import { HarmonySnapshotReadIo } from './HarmonySnapshotIo';
import { GameDataSnapshotStore } from './GameDataSnapshotStore';
import { GameDataItem, GameDataManifestPolicy, ItemType } from './GameDataManifestPolicy';

/** Primitive arguments/results only. This worker has no write or publication capability. */
@Concurrent
export function prepareGameDataSnapshot(filesDir: string, mode: string, id: string, itemText: string = '', expectedHash: string = ''): string[] {
  if (taskpool.Task.isCanceled()) { throw new Error('快照校验已取消'); }
  const io: HarmonySnapshotReadIo = new HarmonySnapshotReadIo(filesDir);
  const store: GameDataSnapshotStore = new GameDataSnapshotStore(io.root, io);
  let result: string[];
  if (mode === 'file') {
    if (itemText.length > 2048 || expectedHash.length !== 64 || !/^[0-9a-f]{64}$/.test(expectedHash)) { throw new Error('文件校验归属无效'); }
    const raw: Record<string, Object> = GameDataManifestPolicy.object(GameDataManifestPolicy.parseJson(itemText), 'file descriptor');
    const item: GameDataItem = new GameDataItem();
    item.type = GameDataManifestPolicy.text(raw['type'], 'type'); item.path = GameDataManifestPolicy.text(raw['path'], 'path');
    item.size = GameDataManifestPolicy.integer(raw['size'], 'size'); item.sha256 = GameDataManifestPolicy.text(raw['sha256'], 'sha256');
    GameDataManifestPolicy.validatePath(item.path, item.type);
    if (item.size > GameDataManifestPolicy.MAX_FILE_BYTES || (item.size > 0 && (item.sha256.length !== 64 || !/^[0-9a-f]{64}$/.test(item.sha256))) ||
      (item.size === 0 && item.sha256 !== '')) { throw new Error('文件摘要声明无效'); }
    const bytes: Uint8Array = io.read(`${store.stagingPath(id)}/${item.path}`, item.size > 0 ? item.size : GameDataManifestPolicy.MAX_FILE_BYTES);
    const hash: string = io.sha256(bytes); GameDataManifestPolicy.validateBytes(item, bytes, hash);
    if (hash !== expectedHash) { throw new Error('暂存字节与接收字节不一致'); }
    if (item.type === ItemType.Text) { GameDataManifestPolicy.parseJson(io.decode(bytes)); }
    result = ['file', io.root, id, itemText, String(bytes.length), hash];
  } else { result = store.prepare(mode, id); }
  io.verifyUnchanged();
  if (taskpool.Task.isCanceled()) { throw new Error('快照校验已取消'); }
  return result;
}
