import { RegionUtil } from '../common/Constants';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { UserService } from './UserService';

export class ChallengeVerificationCancelled extends Error {
  constructor() { super('人机验证未完成或被取消，请稍后再试'); }
}

/** The selected role and its owning session at the start of a challenge request. */
export class ChallengeSession {
  readonly user: User;
  readonly uid: string;
  readonly region: string;
  private readonly revision: number;

  private constructor(user: User, uid: string, region: string, revision: number) {
    this.user = user;
    this.uid = uid;
    this.region = region;
    this.revision = revision;
  }

  static capture(uid: string): ChallengeSession | undefined {
    const service: UserService = UserService.getInstance();
    const user: User | undefined = service.getCurrentUser();
    const region: string = RegionUtil.regionOfUid(uid);
    if (user === undefined || user.isOversea || !RegionUtil.isCnUid(uid) || PreferencesStore.getCurrentUid() !== uid ||
      !user.roles.some((role: UserGameRole): boolean => role.gameUid === uid && role.region === region)) {
      return undefined;
    }
    return new ChallengeSession(user, uid, region, service.sessionRevision());
  }

  static require(uid: string): ChallengeSession {
    const session: ChallengeSession | undefined = ChallengeSession.capture(uid);
    if (session === undefined || !session.user.hasCookie()) { throw new Error('请先登录并选择国服角色'); }
    return session;
  }

  isCurrent(): boolean {
    const service: UserService = UserService.getInstance();
    return service.sessionRevision() === this.revision && service.getCurrentUser() === this.user &&
      PreferencesStore.getCurrentUid() === this.uid;
  }

  assertCurrent(): void {
    if (!this.isCurrent()) { throw new Error('账号或角色已切换'); }
  }

  async gameRecordCookie(): Promise<string> {
    if (this.user.cookieToken.length === 0 || this.user.ltoken.length === 0) {
      await UserService.getInstance().completeTokenChainPublic(this.user);
    }
    this.assertCurrent();
    const cookie: string = this.user.gameRecordCookie();
    if (cookie.length === 0) { throw new Error('账号缺少 cookie_token，请重新登录'); }
    return cookie;
  }
}
