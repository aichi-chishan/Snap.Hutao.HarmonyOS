import { fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { ApiClient } from '../data/network/ApiClient';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { AppContextProvider } from '../common/AppContext';
import { Logger } from '../common/Logger';
import { MediaCacheService } from './MediaCacheService';

const TAG: string = 'BackgroundMediaService';
// 对齐 Remastered BackgroundMediaPlayerService 中此活动视频的兼容版本。
const LAUNCHER_WEBM: string = 'https://launcher-webstatic.mihoyo.com/launcher-public/2026/08/05/8e1c78aaa6e33ed60b88e12a461f8ee5_6759941859929004894.webm';
const LAUNCHER_MP4: string = 'https://static.snaphutaorp.org/static/launcher/20260812.mp4';

export class BackgroundMediaService {
  static readonly TYPE_KEY: string = 'background.media.type';
  static readonly FILES_KEY: string = 'background.media.files';
  static readonly MUTED_KEY: string = 'background.media.muted';
  static readonly LOOP_KEY: string = 'background.media.loop';
  /** ArkUI Video 支持的容器格式，文件选择器与导入校验共用。 */
  static readonly VIDEO_EXTENSIONS: string[] = ['.mp4', '.mkv', '.ts'];
  private static readonly OFFICIAL_URL: string = 'https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getAllGameBasicInfo?launcher_id=jGHBHlcOq1&language=zh-cn&game_id=1Z8W5NHUQb';
  private static version: number = 0;
  private static officialGeneration: number = -1;
  private static officialTask: Promise<string> | undefined;
  private static importing: boolean = false;

  static changed(): void {
    AppStorage.setOrCreate('backgroundMediaVersion', ++BackgroundMediaService.version);
  }

  private static extension(name: string): string {
    const dot: number = name.lastIndexOf('.');
    const suffix: string = dot < 0 ? '' : name.substring(dot).toLowerCase();
    return BackgroundMediaService.VIDEO_EXTENSIONS.includes(suffix) ? suffix : '';
  }

  static officialVideo(data: Record<string, Object>): string {
    const list: Object = data['game_info_list'];
    if (!Array.isArray(list)) { return ''; }
    for (const raw of list as Object[]) {
      if (raw === null || typeof raw !== 'object') { continue; }
      const entry: Record<string, Object> = raw as Record<string, Object>;
      const game: Object = entry['game'];
      if (game === null || typeof game !== 'object' || (game as Record<string, Object>)['biz'] !== 'hk4e_cn') { continue; }
      const backgrounds: Object = entry['backgrounds'];
      if (!Array.isArray(backgrounds)) { continue; }
      for (const rawBackground of backgrounds as Object[]) {
        if (rawBackground === null || typeof rawBackground !== 'object') { continue; }
        const background: Record<string, Object> = rawBackground as Record<string, Object>;
        const video: Object = background['video'];
        if (background['type'] !== 'BACKGROUND_TYPE_VIDEO' || video === null || typeof video !== 'object') { continue; }
        const url: Object = (video as Record<string, Object>)['url'];
        if (typeof url !== 'string' || !url.startsWith('https://')) { continue; }
        if (url === LAUNCHER_WEBM) { return LAUNCHER_MP4; }
        if (BackgroundMediaService.extension(url.split(/[?#]/)[0]).length > 0) { return url; }
      }
    }
    return '';
  }

  static async source(): Promise<string> {
    const type: string = PreferencesStore.getString(BackgroundMediaService.TYPE_KEY, 'none');
    if (type === 'official') { return BackgroundMediaService.officialSource(); }
    if (type === 'local') { return BackgroundMediaService.localSource(); }
    return '';
  }

  private static async localSource(): Promise<string> {
    const filesDir: string = AppContextProvider.getFilesDir();
    if (filesDir.length === 0) { return ''; }
    const root: string = `${filesDir}/background-video/`;
    const paths: string[] = PreferencesStore.getString(BackgroundMediaService.FILES_KEY, '').split('\n');
    const available: string[] = [];
    for (const path of paths) {
      if (!path.startsWith(root)) { continue; }
      const name: string = path.substring(root.length);
      if (!/^[a-z0-9_-]+\.[a-z0-9]+$/i.test(name) || BackgroundMediaService.extension(name).length === 0) { continue; }
      if (await MediaCacheService.hasFile(path)) { available.push(path); }
    }
    return available.length > 0 ? fileUri.getUriFromPath(available[Math.floor(Math.random() * available.length)]) : '';
  }

  private static async officialSource(): Promise<string> {
    const generation: number = MediaCacheService.generation();
    if (!MediaCacheService.isCurrent(generation)) { return ''; }
    const pending: Promise<string> | undefined = BackgroundMediaService.officialTask;
    if (pending !== undefined && BackgroundMediaService.officialGeneration === generation) { return pending; }
    const task: Promise<string> = BackgroundMediaService.resolveOfficial(generation);
    BackgroundMediaService.officialTask = task;
    BackgroundMediaService.officialGeneration = generation;
    try {
      return await task;
    } finally {
      if (BackgroundMediaService.officialTask === task) { BackgroundMediaService.officialTask = undefined; }
    }
  }

  private static async resolveOfficial(generation: number): Promise<string> {
    const response = await ApiClient.getInstance().get(BackgroundMediaService.OFFICIAL_URL, {});
    if (!response.success || response.data === undefined || !MediaCacheService.isCurrent(generation)) { return ''; }
    const url: string = BackgroundMediaService.officialVideo(response.data as Record<string, Object>);
    if (url.length === 0) { return ''; }
    try {
      const suffix: string = BackgroundMediaService.extension(url.split(/[?#]/)[0]);
      const name: string = `official_${MediaCacheService.urlHash(url)}${suffix}`;
      const path: string = await MediaCacheService.fetchFile(url, 'wallpaper', name, generation);
      if (path.length > 0 && MediaCacheService.isCurrent(generation)) { return fileUri.getUriFromPath(path); }
    } catch (error) {
      Logger.warn(TAG, `official video cache failed: ${(error as Error).message}`);
    }
    return MediaCacheService.isCurrent(generation) ? url : '';
  }

  /** 将本批选择复制到 filesDir，全部复制完成后才发布新列表。 */
  static async importVideos(uris: string[]): Promise<number> {
    if (uris.length === 0) { return 0; }
    if (BackgroundMediaService.importing) { throw new Error('视频导入正在进行'); }
    BackgroundMediaService.importing = true;
    const paths: string[] = [];
    let published: boolean = false;
    try {
      const filesDir: string = AppContextProvider.getFilesDir();
      if (filesDir.length === 0) { throw new Error('视频存储目录不可用'); }
      const dir: string = `${filesDir}/background-video`;
      try { await fileIo.mkdir(dir); } catch (error) {
        if ((error as BusinessError).code !== 13900015) { throw error as Error; }
      }
      if (!(await fileIo.lstat(dir)).isDirectory()) { throw new Error('视频存储目录不可用'); }

      const batch: string = util.generateRandomUUID();
      const unique: Set<string> = new Set<string>(uris);
      for (const uri of unique) {
        const source: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
        try {
          const suffix: string = BackgroundMediaService.extension(source.name);
          if (suffix.length === 0) { throw new Error('请选择 MP4、MKV 或 TS 视频'); }
          const stat: fileIo.Stat = await fileIo.stat(source.fd);
          if (!stat.isFile() || stat.size === 0) { throw new Error('视频文件为空或无法读取'); }
          const dest: string = `${dir}/${batch}_${paths.length}${suffix}`;
          paths.push(dest);
          await fileIo.copyFile(source.fd, dest);
        } finally {
          await fileIo.close(source);
        }
      }
      PreferencesStore.setString(BackgroundMediaService.FILES_KEY, paths.join('\n'));
      published = true;
      PreferencesStore.setString(BackgroundMediaService.TYPE_KEY, 'local');
      BackgroundMediaService.changed();
      return paths.length;
    } finally {
      if (!published) {
        for (const path of paths) {
          try { await fileIo.unlink(path); } catch (_) { }
        }
      }
      BackgroundMediaService.importing = false;
    }
  }
}
