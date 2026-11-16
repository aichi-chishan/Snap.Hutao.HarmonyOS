import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContextProvider } from '../../common/AppContext';
import { PreferencesStore } from '../prefs/PreferencesStore';
import { AiConversation, AiModelProfile, AiProviderProfile, AiWorkspaceSettings } from '../../model/AiWorkspace';

export class AiWorkspaceStore {
  private static migration?: Promise<AiWorkspaceSettings>;

  static newId(): string {
    return util.generateRandomUUID();
  }

  static async loadSettings(): Promise<AiWorkspaceSettings> {
    const path: string = `${AiWorkspaceStore.root()}/settings.json`;
    if (fileIo.accessSync(path)) {
      return JSON.parse(fileIo.readTextSync(path)) as AiWorkspaceSettings;
    }
    if (AiWorkspaceStore.migration === undefined) {
      AiWorkspaceStore.migration = AiWorkspaceStore.migrateSettings();
    }
    try {
      return await AiWorkspaceStore.migration;
    } finally {
      AiWorkspaceStore.migration = undefined;
    }
  }

  private static async migrateSettings(): Promise<AiWorkspaceSettings> {
    const settings: AiWorkspaceSettings = new AiWorkspaceSettings();
    const endpoint: string = PreferencesStore.getString('ai.custom.baseUrl', '').trim();
    const modelName: string = PreferencesStore.getString('ai.custom.model', '').trim();
    const key: string = PreferencesStore.getString('ai.custom.apiKey', '').trim();
    if (endpoint.length === 0 && modelName.length === 0 && key.length === 0) { return settings; }
    const provider: AiProviderProfile = new AiProviderProfile();
    provider.id = AiWorkspaceStore.newId();
    provider.name = '自定义 API';
    provider.endpoint = endpoint;
    if (modelName.length > 0) {
      const model: AiModelProfile = new AiModelProfile();
      model.id = AiWorkspaceStore.newId();
      model.model = modelName;
      provider.models = [model];
      provider.modelId = model.id;
    }
    settings.providers = [provider];
    settings.providerId = provider.id;
    if (key.length > 0) { await AiWorkspaceStore.saveKey(provider.id, key); }
    AiWorkspaceStore.saveSettings(settings);
    if (key.length > 0) { PreferencesStore.setString('ai.custom.apiKey', ''); }
    return settings;
  }

  static saveSettings(settings: AiWorkspaceSettings): void {
    AiWorkspaceStore.writeJson(`${AiWorkspaceStore.root()}/settings.json`, settings);
  }

  static loadConversations(uid: string): AiConversation[] {
    const directory: string = AiWorkspaceStore.accountDirectory(uid);
    if (!fileIo.accessSync(directory)) { return []; }
    const conversations: AiConversation[] = [];
    for (const name of fileIo.listFileSync(directory)) {
      if (!name.endsWith('.json')) { continue; }
      try {
        const conversation: AiConversation = JSON.parse(fileIo.readTextSync(`${directory}/${name}`)) as AiConversation;
        if (conversation.id === name.slice(0, -5) && AiWorkspaceStore.validId(conversation.id) &&
          Array.isArray(conversation.messages)) {
          conversations.push(conversation);
        }
      } catch (_) {
        // One damaged conversation does not hide the rest of the account history.
      }
    }
    return conversations.sort((left: AiConversation, right: AiConversation): number => right.updatedAt - left.updatedAt);
  }

  static saveConversation(uid: string, conversation: AiConversation): void {
    AiWorkspaceStore.writeJson(AiWorkspaceStore.conversationPath(uid, conversation.id), conversation);
  }

  static deleteConversation(uid: string, id: string): void {
    const path: string = AiWorkspaceStore.conversationPath(uid, id);
    if (fileIo.accessSync(path)) { fileIo.unlinkSync(path); }
  }

  private static root(): string {
    return `${AppContextProvider.getFilesDir()}/ai-workspace`;
  }

  private static accountDirectory(uid: string): string {
    if (!/^[1-9][0-9]{8,9}$/.test(uid)) { throw new Error('请选择有效的游戏账号'); }
    return `${AiWorkspaceStore.root()}/accounts/${uid}`;
  }

  private static validId(id: string): boolean {
    return /^[0-9a-f-]{36}$/.test(id);
  }

  private static conversationPath(uid: string, id: string): string {
    if (!AiWorkspaceStore.validId(id)) { throw new Error('会话编号无效'); }
    return `${AiWorkspaceStore.accountDirectory(uid)}/${id}.json`;
  }

  private static writeJson(path: string, value: Object): void {
    const parent: string = path.substring(0, path.lastIndexOf('/'));
    if (!fileIo.accessSync(parent)) { fileIo.mkdirSync(parent, true); }
    const temp: string = `${path}.tmp`;
    const file: fileIo.File = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bytes: Uint8Array = util.TextEncoder.create().encodeInto(JSON.stringify(value));
      if (fileIo.writeSync(file.fd, bytes.buffer as ArrayBuffer) !== bytes.byteLength) { throw new Error('AI 工作区写入不完整'); }
      fileIo.fsyncSync(file.fd);
    } finally {
      fileIo.closeSync(file);
    }
    fileIo.renameSync(temp, path);
  }

  private static alias(id: string): Uint8Array {
    if (!AiWorkspaceStore.validId(id)) { throw new Error('AI 服务商编号无效'); }
    return util.TextEncoder.create().encodeInto(`snap_hutao_ai_${id}`);
  }

  static async saveKey(id: string, key: string): Promise<void> {
    const values: asset.AssetMap = new Map();
    values.set(asset.Tag.ALIAS, AiWorkspaceStore.alias(id));
    values.set(asset.Tag.SECRET, util.TextEncoder.create().encodeInto(key));
    values.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    values.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(values);
  }

  static async loadKey(id: string): Promise<string> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, AiWorkspaceStore.alias(id));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: asset.AssetMap[] = await asset.query(query);
      const secret: Uint8Array | undefined = results[0]?.get(asset.Tag.SECRET) as Uint8Array | undefined;
      return secret === undefined ? '' : util.TextDecoder.create('utf-8').decodeToString(secret);
    } catch (error) {
      if ((error as BusinessError).code === asset.ErrorCode.NOT_FOUND) { return ''; }
      throw new Error('读取 AI API 密钥失败');
    }
  }

  static async deleteKey(id: string): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, AiWorkspaceStore.alias(id));
    try {
      await asset.remove(query);
    } catch (error) {
      if ((error as BusinessError).code !== asset.ErrorCode.NOT_FOUND) { throw new Error('删除 AI API 密钥失败'); }
    }
  }
}
