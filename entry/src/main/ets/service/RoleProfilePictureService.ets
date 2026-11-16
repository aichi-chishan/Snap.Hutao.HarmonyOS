import { RegionUtil } from '../common/Constants';
import { EnkaProfileClient } from '../data/network/EnkaProfileClient';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { RoleProfileIcon, RoleProfilePicture } from '../model/RoleProfilePicture';
import { GameDataService } from './GameDataService';

class CachedRoleProfilePicture {
  icon: string = '';
  fetchedAt: number = 0;
}

const CACHE_AGE_MS: number = 15 * 24 * 60 * 60 * 1000;

export class RoleProfilePictureService {
  private static inFlight: Map<string, Promise<RoleProfilePicture | undefined>> = new Map<string, Promise<RoleProfilePicture | undefined>>();

  private static cacheKey(uid: string): string {
    return `role_profile_picture.${uid}`;
  }

  static cachedIcon(uid: string): string {
    if (!RegionUtil.isCnUid(uid)) { return ''; }
    try {
      const text: string = PreferencesStore.getString(RoleProfilePictureService.cacheKey(uid), '');
      if (text.length === 0) { return ''; }
      const cache: CachedRoleProfilePicture = JSON.parse(text) as CachedRoleProfilePicture;
      const age: number = Date.now() - cache.fetchedAt;
      if (typeof cache.icon === 'string' && RoleProfilePicture.validIcon(cache.icon) &&
        Number.isSafeInteger(cache.fetchedAt) && age >= 0 && age < CACHE_AGE_MS) {
        return cache.icon;
      }
    } catch (e) { /* A missing or unreadable local cache can be refreshed. */ }
    return '';
  }

  static async loadIcon(uid: string, force: boolean, isCurrent: () => boolean): Promise<string> {
    if (!RegionUtil.isCnUid(uid) || !isCurrent()) { return ''; }
    const cached: string = force ? '' : RoleProfilePictureService.cachedIcon(uid);
    if (cached.length > 0) { return cached; }
    let request: Promise<RoleProfilePicture | undefined> | undefined = undefined;
    try {
      const raw: string = await GameDataService.readMetadataFile('ProfilePicture.json');
      if (!isCurrent()) { return ''; }
      const catalog: RoleProfileIcon[] = RoleProfilePicture.readCatalog(raw);
      if (catalog.length === 0) { return ''; }
      request = RoleProfilePictureService.inFlight.get(uid);
      if (request === undefined) {
        request = EnkaProfileClient.fetchPicture(uid);
        RoleProfilePictureService.inFlight.set(uid, request);
      }
      const activeRequest: Promise<RoleProfilePicture | undefined> = request;
      const picture: RoleProfilePicture | undefined = await activeRequest;
      if (!isCurrent() || picture === undefined) { return ''; }
      const icon: string = picture.resolveIcon(catalog);
      if (icon.length === 0) { return ''; }
      const entry: CachedRoleProfilePicture = new CachedRoleProfilePicture();
      entry.icon = icon;
      entry.fetchedAt = Date.now();
      try {
        PreferencesStore.setString(RoleProfilePictureService.cacheKey(uid), JSON.stringify(entry));
      } catch (e) { /* A live avatar can still be shown if local cache storage is unavailable. */ }
      return icon;
    } catch (e) {
      return '';
    } finally {
      if (request !== undefined && RoleProfilePictureService.inFlight.get(uid) === request) {
        RoleProfilePictureService.inFlight.delete(uid);
      }
    }
  }
}
