import { http } from '@kit.NetworkKit';
import { AppConstants, RegionUtil } from '../../common/Constants';
import { RoleProfilePicture } from '../../model/RoleProfilePicture';

const PROFILE_ENDPOINT: string = 'https://enka.network/api/uid/';

/** Fetch the public profile through a request isolated from the account transport. */
export class EnkaProfileClient {
  static async fetchPicture(uid: string): Promise<RoleProfilePicture | undefined> {
    if (!RegionUtil.isCnUid(uid)) { return undefined; }
    const request: http.HttpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = { 'Accept': 'application/json' };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: AppConstants.NETWORK_TIMEOUT_MS,
        readTimeout: AppConstants.NETWORK_TIMEOUT_MS,
        maxRedirects: 0,
        usingCache: false,
      };
      const response: http.HttpResponse = await request.request(`${PROFILE_ENDPOINT}${uid}?info`, options);
      if (response.responseCode !== http.ResponseCode.OK || typeof response.result !== 'string') { return undefined; }
      return RoleProfilePicture.fromResponse(response.result);
    } finally {
      request.destroy();
    }
  }
}
