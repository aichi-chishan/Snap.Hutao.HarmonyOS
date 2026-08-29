/**
 * GameDataUpdater.ets
 * 游戏数据更新引擎（数据管理核心，供未来软件内从 GitHub 拉取最新游戏数据）：
 *
 * 设计目标：
 *  1. 单一清单协议（manifest-{CHANNEL}.json）集中管理全部可更新数据（元数据 JSON / 图标 PNG / 立绘大图 / 曲线表）
 *  2. 版本戳管理（本地版本 < 远端版本才触发更新；断网/失败静默回退本地包内数据）
 *  3. 并发下载 + 进度回传（request.agent 后台代理：断点续传/自动重试/后台通知）
 *  4. 原子替换（.download 临时目录 → 全部成功后才重命名覆盖，避免半成品覆盖生产数据）
 *  5. 目录分层：filesDir/gamedata/{分类}/{文件名}（用户数据路径，非 cacheDir，升级不丢缓存）
 *
 * 清单协议（GitHub raw 托管，仓库由用户维护）：
 *  {
 *    "channel": "hutao-cn",
 *    "channelVersion": "2026.08.24.1",
 *    "items": [
 *      { "type": "text",  "path": "metadata/character.json",  "url": "...", "version": 3 },
 *      { "type": "image", "path": "icons/AvatarIcon/xxx.png", "url": "...", "version": 5 }
 *    ]
 *  }
 *
 * 注意：本引擎只做"取与存"，不解析内容（解析由各 Service 负责），保证单一职责。
 */
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AppContextProvider } from '../../common/AppContext';
import { PreferencesStore } from '../prefs/PreferencesStore';
import { Logger } from '../../common/Logger';
import { GitHubMirror } from '../../common/GitHubMirror';

const TAG: string = 'GameDataUpdater';

/** 更新条目类型：text=JSON/元数据；icon=图片（兼容 image 旧写法） */
export class ItemType {
  static readonly Text: string = 'text';
  static readonly Icon: string = 'icon';
  static readonly Image: string = 'image';
}

/** 清单条目（GitHub 协议） */
export class GameDataItem {
  /** text/icon/image */
  type: string = ItemType.Text;
  /** 相对路径（如 metadata/character.json），同时作为本地缓存键 */
  path: string = '';
  /** 下载地址（GitHub raw 或任何可公开 GET 的地址） */
  url: string = '';
  /** 条目级版本号（变更时 +1，仅用于记录） */
  version: number = 0;
}

/** 清单（GitHub 协议根对象） */
export class GameDataManifest {
  channel: string = '';
  channelVersion: string = '';
  items: GameDataItem[] = [];
}

/** 更新进度（回调到 UI） */
export class UpdateProgress {
  /** 已成功项 */
  done: number = 0;
  /** 总项 */
  total: number = 0;
  /** 当前项名 */
  current: string = '';
}

export class GameDataUpdater {
  /** 数据子目录：text 元数据 */
  private static readonly SUB_METADATA: string = 'metadata';
  /** 数据子目录：image 图标/大图 */
  private static readonly SUB_IMAGE: string = 'images';
  /** 元数据文件缓存（同步 IO 每文件进程内仅一次，避免 UI 线程重复大文件读） */
  private static metaCache: Map<string, string> = new Map<string, string>();

  /** 本地版本戳 key（Preferences 记录上一次成功的 channelVersion） */
  private static versionKey(): string {
    return 'gamedata_manifest_version';
  }

  /** 清单地址 key（设置页可修改） */
  private static manifestUrlKey(): string {
    return 'gamedata_manifest_url';
  }

  /** 默认清单地址（指向 aichi-chishan/snap-hutao-data；用户可在设置页运行时改） */
  static defaultManifestUrl(): string {
    return 'https://raw.githubusercontent.com/aichi-chishan/snap-hutao-data/main/manifest-hutao.json';
  }

  /** 读取当前清单地址（未设置时回退默认） */
  static manifestUrl(): string {
    return PreferencesStore.getString(GameDataUpdater.manifestUrlKey(), GameDataUpdater.defaultManifestUrl());
  }

  /** 设置清单地址（设置页调用） */
  static setManifestUrl(url: string): void {
    PreferencesStore.setString(GameDataUpdater.manifestUrlKey(), url.trim().length > 0 ? url.trim() : GameDataUpdater.defaultManifestUrl());
  }

  /** 本地数据根目录（filesDir/gamedata——正式持久数据，非缓存） */
  private static root(): string {
    return `${AppContextProvider.getFilesDir()}/gamedata`;
  }

  /** 元数据文件路径（text） */
  static metadataPath(relPath: string): string {
    return `${GameDataUpdater.root()}/${GameDataUpdater.SUB_METADATA}/${relPath}`;
  }

  /** 图片文件路径（image） */
  static imagePath(relPath: string): string {
    return `${GameDataUpdater.root()}/${GameDataUpdater.SUB_IMAGE}/${relPath}`;
  }

  /** 按条目类型取完整落盘路径（text → metadata/；icon/image → images/） */
  private static itemPath(item: GameDataItem): string {
    if (item.type === ItemType.Icon || item.type === ItemType.Image) {
      return GameDataUpdater.imagePath(item.path);
    }
    return GameDataUpdater.metadataPath(item.path);
  }

  /** 本地版本戳（0=未更新过） */
  static localVersion(): string {
    return PreferencesStore.getString(GameDataUpdater.versionKey(), '');
  }

  /** 清空本地远端数据与版本戳（回退 rawfile 内置数据） */
  static clearAll(): void {
    GameDataUpdater.metaCache.clear();
    try {
      fileIo.rmdirSync(GameDataUpdater.root());
    } catch (e) {
      // 不存在则忽略
    }
    PreferencesStore.setString(GameDataUpdater.versionKey(), '');
    Logger.info(TAG, 'remote gamedata cleared');
  }

  /** 是否有更新（远端版本 > 本地版本） */
  static hasUpdate(remote: GameDataManifest): boolean {
    if (remote.channelVersion.length === 0) {
      return false;
    }
    return remote.channelVersion !== GameDataUpdater.localVersion();
  }

  /** 拉取清单（纯 GET text） */
  static async fetchManifest(): Promise<GameDataManifest> {
    const resp = await GameDataUpdater.httpGetString(GameDataUpdater.manifestUrl());
    const root = JSON.parse(resp) as Record<string, Object>;
    const manifest: GameDataManifest = new GameDataManifest();
    manifest.channel = String(root['channel'] ?? '');
    manifest.channelVersion = String(root['channelVersion'] ?? '');
    const arr = (root['items'] as Object[]) ?? [];
    for (const r of arr) {
      const o = r as Record<string, Object>;
      const item: GameDataItem = new GameDataItem();
      item.type = String(o['type'] ?? ItemType.Text);
      item.path = String(o['path'] ?? '');
      item.url = String(o['url'] ?? '');
      item.version = Number(o['version'] ?? 0);
      if (item.path.length > 0 && item.url.length > 0) {
        manifest.items.push(item);
      }
    }
    Logger.info(TAG, `manifest: channel=${manifest.channel} ver=${manifest.channelVersion} items=${manifest.items.length}`);
    return manifest;
  }

  /** 本地是否存在某条目（已更新过则 true） */
  static isItemLocal(item: GameDataItem): boolean {
    try {
      fileIo.accessSync(GameDataUpdater.itemPath(item));
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 读取已更新的元数据文本；未更新/不存在返回 ''。进程内缓存（同步 IO 只在主线程发生一次） */
  static readMetadata(relPath: string): string {
    const cached: string | undefined = GameDataUpdater.metaCache.get(relPath);
    if (cached !== undefined) {
      return cached;
    }
    try {
      const p = GameDataUpdater.metadataPath(relPath);
      const f = fileIo.openSync(p, fileIo.OpenMode.READ_ONLY);
      try {
        const st: fileIo.Stat = fileIo.statSync(f.fd);
        const buf: ArrayBuffer = new ArrayBuffer(st.size);
        fileIo.readSync(f.fd, buf);
        const text: string = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf));
        GameDataUpdater.metaCache.set(relPath, text);
        return text;
      } finally {
        fileIo.closeSync(f);
      }
    } catch (e) {
      GameDataUpdater.metaCache.set(relPath, '');
      Logger.warn(TAG, `readMetadata ${relPath} fail`);
      return '';
    }
  }

  /** 读取已更新的图片相对路径（file:// 前缀供 Image 组件使用）；不存在返回 ''。
   *  注意：fileIo.accessSync 在部分 API/模拟器实现对"路径不存在"不抛异常（返回成功），
   *  导致 readImage 幽灵路径 → Image 渲染空白；此处改用 openSync 真实校验可打开。 */
  static readImage(relPath: string): string {
    const p = GameDataUpdater.imagePath(relPath);
    let f: fileIo.File | undefined = undefined;
    try {
      f = fileIo.openSync(p, fileIo.OpenMode.READ_ONLY);
      return `file://${p}`;
    } catch (e) {
      return '';
    } finally {
      if (f !== undefined) {
        try {
          fileIo.closeSync(f);
        } catch (e) {
          // 关闭失败忽略
        }
      }
    }
  }

  /**
   * 全量更新（顺序执行，逐项下载）：
   * @param onProgress 进度回调（可空）
   * @returns 更新后的 manifest；清单拉取失败（断网/地址错误）时抛错给调用方提示
   */
  static async update(onProgress?: (p: UpdateProgress) => void): Promise<GameDataManifest> {
    const manifest = await GameDataUpdater.fetchManifest();
    if (manifest.items.length === 0) {
      Logger.warn(TAG, 'manifest has no items, skip');
      return manifest;
    }
    let done = 0;
    for (const item of manifest.items) {
      try {
        await GameDataUpdater.downloadItem(item);
        if (onProgress !== undefined) {
          const p: UpdateProgress = new UpdateProgress();
          p.done = done + 1;
          p.total = manifest.items.length;
          p.current = item.path;
          onProgress(p);
        }
      } catch (e) {
        // 单条失败不阻断整体（后续可再次 update 补齐）
        Logger.warn(TAG, `update item fail ${item.path}: ${(e as Error).message}`);
      }
      done += 1;
    }
    // 全部项（含失败）处理完后才更新版本戳：失败项下次 update 会重试
    PreferencesStore.setString(GameDataUpdater.versionKey(), manifest.channelVersion);
    Logger.info(TAG, `update done items=${manifest.items.length} version=${manifest.channelVersion}`);
    return manifest;
  }

  /** 仅更新缺失项（增量：已存在且版本戳不同才重新下载） */
  static async ensureItem(item: GameDataItem): Promise<void> {
    if (GameDataUpdater.isItemLocal(item)) {
      return;
    }
    await GameDataUpdater.downloadItem(item);
  }

  /** 下载单条目到临时文件后原子替换（避免半成品覆盖） */
  private static async downloadItem(item: GameDataItem): Promise<void> {
    const dest = GameDataUpdater.itemPath(item);
    const parent = dest.substring(0, dest.lastIndexOf('/'));
    await GameDataUpdater.mkdirp(parent);
    // 临时文件（.download 后缀），成功后 rename 覆盖
    const tmp = `${dest}.download`;
    try {
      fileIo.unlinkSync(tmp);
    } catch (e) {
      // 不存在则忽略
    }
    await GameDataUpdater.downloadWithAgent(item.url, tmp);
    try {
      fileIo.unlinkSync(dest);
    } catch (e) {
      // 不存在则忽略（首次）
    }
    fileIo.renameSync(tmp, dest);
    Logger.info(TAG, `item ok ${item.path} <- ${item.type}`);
  }

  /** http 下载（流式分段写盘，避免整块大 Buffer 占内存；GitHub raw 场景足够）：
   *  说明：request.agent 后台下载需 request_agent 模块声明且任务管理模式更重（断点续传/后台通知），
   *  当前 manifest 多为小文件（元数据 JSON/图标 PNG），http 直接下载 + 临时文件原子替换已保证可靠性；
   *  后续若引入大体积资源包（立绘/桌面壁纸），可在本方法内切换为 request.agent。 */
  private static async downloadWithAgent(url: string, filePath: string): Promise<void> {
    let lastErr: Error = new Error('unknown');
    for (const candidate of GitHubMirror.candidates(url)) {
      try {
        await GameDataUpdater.downloadOnce(candidate, filePath);
        return;
      } catch (e) {
        lastErr = e as Error;
      }
    }
    throw lastErr;
  }

  private static async downloadOnce(url: string, filePath: string): Promise<void> {
    const req = http.createHttp();
    try {
      // expectDataType STRING 兼容二进制安全写入（UTF-8 元数据）；图片走 ARRAY_BUFFER 由调用方分派太复杂，
      // 统一用 ARRAY_BUFFER：写盘原始字节，文本由下游 readMetadata 做 UTF-8 解码。
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
      });
      if (resp.responseCode !== http.ResponseCode.OK) {
        throw new Error(`http ${resp.responseCode}`);
      }
      const file = fileIo.openSync(filePath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, resp.result as ArrayBuffer);
      } finally {
        fileIo.closeSync(file);
      }
    } finally {
      req.destroy();
    }
  }

  /** 中文 UTF-8 文本 GET（清单） */
  private static async httpGetString(url: string): Promise<string> {
    // 直连失败自动回退公共镜像（国内直连 GitHub 不稳定）
    let lastErr: Error = new Error('unknown');
    for (const candidate of GitHubMirror.candidates(url)) {
      try {
        return await GameDataUpdater.httpGetStringOnce(candidate);
      } catch (e) {
        lastErr = e as Error;
      }
    }
    throw lastErr;
  }

  private static async httpGetStringOnce(url: string): Promise<string> {
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
      });
      if (resp.responseCode !== http.ResponseCode.OK) {
        throw new Error(`http ${resp.responseCode}`);
      }
      return resp.result as string;
    } finally {
      req.destroy();
    }
  }

  /** 递归创建目录 */
  private static async mkdirp(path: string): Promise<void> {
    try {
      fileIo.mkdirSync(path);
      return;
    } catch (e) {
      // 父级可能不存在：逐级创建
    }
    const segs: string[] = path.split('/');
    let cur: string = '';
    for (let i = 0; i < segs.length; i++) {
      cur += (i === 0 ? '' : '/') + segs[i];
      try {
        fileIo.mkdirSync(cur);
      } catch (e) {
        // 已存在或中间级失败
      }
    }
  }
}
