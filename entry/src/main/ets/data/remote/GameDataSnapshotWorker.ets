import { taskpool } from '@kit.ArkTS';
import { HarmonySnapshotReadIo } from './HarmonySnapshotIo';
import { GameDataSnapshotStore } from './GameDataSnapshotStore';
import { GameDataItem, GameDataManifestPolicy, ItemType } from './GameDataManifestPolicy';

/** Read-only verification. A language read returns one verified file as UTF-8 bytes. */
@Concurrent
export function prepareGameDataSnapshot(filesDir: string, mode: string, id: string, itemText: string = '',
  expectedHash: string = ''): string[] | ArrayBuffer {
  if (taskpool.Task.isCanceled()) { throw new Error('快照校验已取消'); }
  const io: HarmonySnapshotReadIo = new HarmonySnapshotReadIo(filesDir);
  const store: GameDataSnapshotStore = new GameDataSnapshotStore(io.root, io);
  let result: string[] | ArrayBuffer;
  const languageRead: boolean = mode === 'language';
  if (mode === 'file' || languageRead) {
    if (itemText.length > 2048 || expectedHash.length !== 64 || !/^[0-9a-f]{64}$/.test(expectedHash)) { throw new Error('文件校验归属无效'); }
    const raw: Record<string, Object> = GameDataManifestPolicy.object(GameDataManifestPolicy.parseJson(itemText), 'file descriptor');
    const item: GameDataItem = new GameDataItem();
    item.type = GameDataManifestPolicy.text(raw['type'], 'type'); item.path = GameDataManifestPolicy.text(raw['path'], 'path');
    item.size = GameDataManifestPolicy.integer(raw['size'], 'size'); item.sha256 = GameDataManifestPolicy.text(raw['sha256'], 'sha256');
    GameDataManifestPolicy.validatePath(item.path, item.type);
    const languageFile: boolean = GameDataManifestPolicy.isLanguagePath(item.path);
    if (languageRead && (!languageFile || item.size === 0)) { throw new Error('语言文件校验收据无效'); }
    const limit: number = GameDataManifestPolicy.maxFileBytes(item.path);
    if (item.size > limit || (item.size > 0 && (item.sha256.length !== 64 || !/^[0-9a-f]{64}$/.test(item.sha256))) ||
      (item.size === 0 && item.sha256 !== '')) { throw new Error('文件摘要声明无效'); }
    const directory: string = languageRead ? store.snapshotPath(id) : store.stagingPath(id);
    const bytes: Uint8Array = io.read(`${directory}/${item.path}`, item.size > 0 ? item.size : limit);
    const hash: string = io.sha256(bytes); GameDataManifestPolicy.validateBytes(item, bytes, hash);
    if (hash !== expectedHash) { throw new Error('文件摘要与校验任务不一致'); }
    if (languageFile) { GameDataManifestPolicy.validateLanguageText(item.path, io.decode(bytes)); }
    else if (item.type === ItemType.Text) { GameDataManifestPolicy.parseJson(io.decode(bytes)); }
    result = languageRead ? bytes.buffer as ArrayBuffer : ['file', io.root, id, itemText, String(bytes.length), hash];
  } else { result = store.prepare(mode, id); }
  io.verifyUnchanged();
  if (taskpool.Task.isCanceled()) { throw new Error('快照校验已取消'); }
  return result;
}
