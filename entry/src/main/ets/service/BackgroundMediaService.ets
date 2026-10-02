import { fileIo } from '@kit.CoreFileKit';
import { ApiClient } from '../data/network/ApiClient';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { AppContextProvider } from '../common/AppContext';

/** Source contract follows Remastered OfficialLauncherClient, without account credentials. */
export class BackgroundMediaService {
  static readonly TYPE_KEY: string = 'background.media.type';
  static readonly FILES_KEY: string = 'background.media.files';
  static readonly MUTED_KEY: string = 'background.media.muted';
  static readonly LOOP_KEY: string = 'background.media.loop';
  private static readonly OFFICIAL_URL: string = 'https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getAllGameBasicInfo?launcher_id=jGHBHlcOq1&language=zh-cn&game_id=1Z8W5NHUQb';

  static changed(): void {
    AppStorage.setOrCreate('backgroundMediaVersion', Date.now());
  }

  static officialVideo(data: Record<string, Object>): string {
    const list: Object[] = (data['game_info_list'] as Object[]) ?? [];
    for (const raw of list) {
      const entry: Record<string, Object> = raw as Record<string, Object>;
      const game: Record<string, Object> | undefined = entry['game'] as Record<string, Object> | undefined;
      if (game === undefined || game['biz'] !== 'hk4e_cn') { continue; }
      const backgrounds: Object[] = (entry['backgrounds'] as Object[]) ?? [];
      for (const rawBackground of backgrounds) {
        const background: Record<string, Object> = rawBackground as Record<string, Object>;
        const video: Record<string, Object> | undefined = background['video'] as Record<string, Object> | undefined;
        if (background['type'] === 'BACKGROUND_TYPE_VIDEO' && video !== undefined) {
          const url: string = String(video['url'] ?? '');
          if (url.startsWith('https://')) { return url; }
        }
      }
    }
    return '';
  }

  static async source(): Promise<string> {
    const type: string = PreferencesStore.getString(BackgroundMediaService.TYPE_KEY, 'none');
    if (type === 'official') {
      const response = await ApiClient.getInstance().get(BackgroundMediaService.OFFICIAL_URL, {});
      return response.success && response.data !== undefined
        ? BackgroundMediaService.officialVideo(response.data as Record<string, Object>) : '';
    }
    if (type === 'local') {
      const paths: string[] = PreferencesStore.getString(BackgroundMediaService.FILES_KEY, '').split('\n');
      const available: string[] = [];
      const root: string = `${AppContextProvider.getFilesDir()}/background-video/`;
      for (const path of paths) {
        if (path.startsWith(root) && fileIo.accessSync(path)) { available.push(path); }
      }
      return available.length > 0 ? `file://${available[Math.floor(Math.random() * available.length)]}` : '';
    }
    return '';
  }

  /** Copy picker-authorized files to our sandbox, so playback survives picker grant expiry. */
  static async importVideos(uris: string[]): Promise<number> {
    const dir: string = `${AppContextProvider.getFilesDir()}/background-video`;
    try { fileIo.mkdirSync(dir); } catch (_) { /* directory may exist */ }
    const paths: string[] = [];
    const batch: number = Date.now();
    for (let index: number = 0; index < uris.length; index++) {
      const uri: string = uris[index];
      const dest: string = `${dir}/${batch}_${index}.mp4`;
      const source = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        // The player probes the container; it does not rely on our cache file extension.
        await fileIo.copyFile(source.fd, dest);
      } finally {
        fileIo.closeSync(source);
      }
      paths.push(dest);
    }
    if (paths.length > 0) {
      PreferencesStore.setString(BackgroundMediaService.FILES_KEY, paths.join('\n'));
      PreferencesStore.setString(BackgroundMediaService.TYPE_KEY, 'local');
      BackgroundMediaService.changed();
    }
    return paths.length;
  }
}
