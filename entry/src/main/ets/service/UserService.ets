/**
 * UserService.ets
 * Cookie 五件套解析→用户建模；Token 链补齐（SToken→LToken→cookie_token）；多账号增删/切换；
 * 角色绑定拉取；全局 AppStorage 状态同步。仅国服。
 * 注：AppStorage 为 ArkUI 全局对象，无需 import。
 */
import { DailyNoteReminderService } from './DailyNoteReminderService';
import { UserRepo } from '../data/repo/UserRepo';
import { ApiClient } from '../data/network/ApiClient';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { LoginSession, MobileCaptcha, PassportClient, QrLogin, QrLoginResult } from '../data/network/PassportClient';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { DsSigner } from '../data/network/DsSigner';
import { DeviceFpApi } from '../data/network/DeviceFpApi';
import { ApiResponse } from '../model/ApiResponse';
import { AppConstants, RegionUtil } from '../common/Constants';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { Logger } from '../common/Logger';
import { RetCodes } from '../common/Constants';

const TAG: string = 'UserService';
const COOKIE_REFRESH_INTERVAL_MS: number = 24 * 60 * 60 * 1000;

class SelectedTokenCompletion {
  readonly owner: User;
  readonly revision: number;
  readonly refreshDue: boolean;
  readonly result: Promise<void>;

  constructor(owner: User, revision: number, refreshDue: boolean, result: Promise<void>) {
    this.owner = owner;
    this.revision = revision;
    this.refreshDue = refreshDue;
    this.result = result;
  }
}

export class UserService {
  private static instance: UserService = new UserService();

  static getInstance(): UserService {
    return UserService.instance;
  }

  /** The committed object stays private while a replacement is pending. */
  private currentUser: User | undefined = undefined;
  private currentUid: string = '';
  private revision: number = 0;
  private transitionPending: boolean = false;
  private pendingLoginRevision: number = -1;
  private replacementRevision: number = -1;
  private mutationTail: Promise<void> = Promise.resolve();
  private selectedTokenCompletion: SelectedTokenCompletion | undefined = undefined;
  private invalidationHook: ((reason: string) => Promise<boolean>) | undefined = undefined;
  private revisionListeners: Array<(revision: number) => void> = [];

  getCurrentUser(): User | undefined {
    return this.transitionPending ? undefined : this.currentUser;
  }

  async getSavedUsers(): Promise<User[]> {
    await this.mutationTail;
    return this.readSavedUsers();
  }

  private async readSavedUsers(): Promise<User[]> {
    const users: User[] = await UserRepo.getAllUsers();
    const order: number[] = PreferencesStore.getUserOrder();
    if (order.length === 0) { return users; }
    return users.sort((left: User, right: User): number => {
      const leftIndex: number = order.indexOf(left.id);
      const rightIndex: number = order.indexOf(right.id);
      return (leftIndex < 0 ? order.length : leftIndex) - (rightIndex < 0 ? order.length : rightIndex);
    });
  }

  async moveSavedUser(userId: number, direction: number): Promise<void> {
    if (direction !== -1 && direction !== 1) { throw new Error('请选择有效的移动方向'); }
    this.assertAvailable();
    const revision: number = this.revision;
    await this.queueMutation(async () => {
      this.assertRevision(revision);
      const users: User[] = await this.readSavedUsers();
      this.assertRevision(revision);
      const index: number = users.findIndex((user: User): boolean => user.id === userId);
      if (index < 0) { throw new Error('账号不存在'); }
      const target: number = index + direction;
      if (target < 0 || target >= users.length) { return; }
      const order: number[] = users.map((user: User): number => user.id);
      order[index] = order[target];
      order[target] = userId;
      await PreferencesStore.saveUserOrder(order);
    });
  }

  async getSavedAccountCookie(userId: number): Promise<string> {
    this.assertAvailable();
    const revision: number = this.revision;
    await this.mutationTail;
    this.assertRevision(revision);
    const user: User | undefined = await UserRepo.getUserById(userId, true);
    this.assertRevision(revision);
    if (user === undefined) { throw new Error('账号不存在'); }
    if (user.isOversea) { throw new Error('仅支持国服米游社账号'); }
    return user.hasCookie() ? user.fullCookie() : '';
  }

  /** Capture before async work. A switch away and back still changes this value. */
  sessionRevision(): number { return this.revision; }

  isSessionTransitionPending(): boolean { return this.transitionPending; }

  /** Application-owned background fence. The reason contains no identity or credentials. */
  setSessionInvalidationHook(hook: (reason: string) => Promise<boolean>): void {
    this.invalidationHook = hook;
  }

  /** Bounded, synchronous invalidation only; async background fencing uses the hook above. */
  addSessionRevisionListener(listener: (revision: number) => void): () => void {
    if (this.revisionListeners.length >= 16) { throw new Error('会话监听数量超出限制'); }
    this.revisionListeners.push(listener);
    return (): void => {
      const index: number = this.revisionListeners.indexOf(listener);
      if (index >= 0) { this.revisionListeners.splice(index, 1); }
    };
  }

  private advanceRevision(): number {
    this.revision++;
    for (const listener of this.revisionListeners.slice()) {
      try { listener(this.revision); } catch (e) { Logger.warn(TAG, 'session listener failed'); }
    }
    return this.revision;
  }

  private beginChange(): number {
    if (this.replacementRevision >= 0) { throw new Error('本地账号还原正在进行'); }
    this.transitionPending = true;
    return this.advanceRevision();
  }

  private finishChange(revision: number): void {
    if (revision === this.revision) {
      this.transitionPending = false;
      // Work begun while an intent was pending must not acquire the newly committed identity.
      this.advanceRevision();
    }
  }

  private assertRevision(revision: number): void {
    if (revision !== this.revision) { throw new Error('账号状态已变化，请重试'); }
  }

  private assertAvailable(): void {
    if (this.transitionPending) { throw new Error('账号状态正在切换，请稍后重试'); }
  }

  private async prepareChange(reason: string, revision: number): Promise<void> {
    const hook: ((reason: string) => Promise<boolean>) | undefined = this.invalidationHook;
    if (hook !== undefined && !await hook(reason)) { throw new Error('无法确认后台任务已停止，请重试'); }
    this.assertRevision(revision);
  }

  private queueMutation(operation: () => Promise<void>): Promise<void> {
    const task: Promise<void> = this.mutationTail.then(operation, operation);
    this.mutationTail = task.then(() => {}, () => {});
    return task;
  }

  /** User.clone() shares role objects; detach them before changing defaults. */
  private detached(user: User): User {
    const copy: User = user.clone();
    copy.roles = [];
    for (const role of user.roles) {
      const item: UserGameRole = UserGameRole.of(role.gameUid, role.region, role.nickname, role.level);
      item.id = role.id;
      item.userId = role.userId;
      item.isDefault = role.isDefault;
      item.isChosen = role.isChosen;
      copy.roles.push(item);
    }
    return copy;
  }

  /** Called only inside the mutation queue; repairs a select/default write already dispatched. */
  private async repairSelection(): Promise<void> {
    const user: User | undefined = this.currentUser;
    await UserRepo.selectUser(user === undefined ? 0 : user.id);
    PreferencesStore.setCurrentUid(this.currentUid);
  }

  private async selectAndPublish(user: User | undefined, uid: string, revision: number): Promise<void> {
    this.assertRevision(revision);
    try {
      await UserRepo.selectUser(user === undefined ? 0 : user.id);
      this.assertRevision(revision);
    } catch (e) {
      await this.repairSelection();
      if (e instanceof Error) { throw e; } throw new Error('账号操作失败，请重试');
    }
    this.currentUser = user;
    this.currentUid = user === undefined ? '' : uid;
    if (user === undefined) { this.clearSessionState(); }
    else { user.isSelected = true; this.applySessionState(user, uid); }
  }

  /** Fence/drain before BackupService changes account rows or vault entries. */
  async beginLocalSessionReplacement(): Promise<number> {
    const revision: number = this.beginChange();
    this.replacementRevision = revision;
    try {
      await this.prepareChange('localReplacement', revision);
      await this.mutationTail;
      this.assertRevision(revision);
      return revision;
    } catch (e) {
      this.replacementRevision = -1;
      this.finishChange(revision);
      if (e instanceof Error) { throw e; } throw new Error('账号操作失败，请重试');
    }
  }

  /** Only after the backup caller has restored the old database/preferences. */
  cancelLocalSessionReplacement(revision: number): void {
    if (this.replacementRevision !== revision) { return; }
    this.replacementRevision = -1;
    this.finishChange(revision);
  }

  // ================= 会话恢复 =================

  /** 恢复本地会话；联网更新凭据在页面加载后执行。 */
  async restoreSession(): Promise<boolean> {
    const revision: number = this.beginChange();
    try {
      await this.prepareChange('restore', revision);
      await this.mutationTail;
      this.assertRevision(revision);
      const loaded: User | undefined = await UserRepo.getCurrentUser();
      this.assertRevision(revision);
      if (loaded === undefined || loaded.isOversea || !loaded.hasCookie()) {
        await this.queueMutation(async () => { await this.selectAndPublish(undefined, '', revision); });
        return false;
      }
      const user: User = this.detached(loaded);
      const uid: string = this.resolveDefaultUid(user);
      await this.queueMutation(async () => {
        await this.selectAndPublish(user, uid, revision);
      });
      Logger.info(TAG, 'session restored');
      return true;
    } catch (e) {
      // A superseded restore never clears a newer login/logout/switch.
      Logger.warn(TAG, 'session restore did not complete');
      return false;
    } finally { this.finishChange(revision); }
  }

  /** 首屏就绪后更新过期凭据和缺失昵称，不改变当前账号或角色选择。 */
  async refreshSession(): Promise<void> {
    const user: User | undefined = this.getCurrentUser();
    if (user === undefined) { return; }
    const revision: number = this.revision;
    await this.ensureDeviceFingerprintPublic();
    this.assertRevision(revision);
    const refreshDue: boolean = this.cookieExchangeDue(user.id);
    if (refreshDue || !user.hasCookieToken() || !user.hasLToken()) {
      await this.completeSelectedTokenChain(user, user, revision, refreshDue);
    }
    this.assertRevision(revision);
    if (user.displayName.length === 0) {
      await this.fetchUserFullInfo(user);
      this.assertRevision(revision);
      if (this.currentUser === user) { this.applySessionState(user, this.currentUid); }
    }
  }

  /** Local-only completion of a successful backup replacement, or standalone reload. */
  async reloadLocalSession(): Promise<void> {
    const replacing: boolean = this.replacementRevision >= 0;
    const revision: number = replacing ? this.replacementRevision : this.beginChange();
    let readStarted: boolean = false;
    try {
      if (!replacing) { await this.prepareChange('reload', revision); }
      await this.mutationTail;
      this.assertRevision(revision);
      readStarted = true;
      const loaded: User | undefined = await UserRepo.getCurrentUser();
      this.assertRevision(revision);
      const user: User | undefined = loaded !== undefined && !loaded.isOversea && loaded.hasCookie()
        ? this.detached(loaded) : undefined;
      const uid: string = user === undefined ? '' : this.resolveDefaultUid(user);
      await this.queueMutation(async () => { await this.selectAndPublish(user, uid, revision); });
    } catch (e) {
      // The previous object may refer to rows replaced by a committed backup. Never expose it again.
      if (readStarted && revision === this.revision) {
        this.currentUser = undefined;
        this.currentUid = '';
        this.clearSessionState();
        try {
          await this.queueMutation(async () => {
            if (revision === this.revision) { await this.repairSelection(); }
          });
        } catch (repairError) { Logger.warn(TAG, 'local session selection repair failed'); }
      }
      if (e instanceof Error) { throw e; } throw new Error('账号操作失败，请重试');
    } finally {
      if (replacing) { this.replacementRevision = -1; }
      this.finishChange(revision);
    }
  }

  private resolveDefaultUid(user: User): string {
    if (user.roles.length === 0) { return ''; }
    const preferred: UserGameRole = user.roles.find((role: UserGameRole): boolean => role.isDefault) ??
      user.roles.find((role: UserGameRole): boolean => role.isChosen) ?? user.roles[0];
    for (const role of user.roles) {
      role.isDefault = role === preferred;
      role.isChosen = role.isDefault;
    }
    return preferred.gameUid;
  }

  private async storeUserMetadata(user: User, revision: number): Promise<void> {
    this.assertRevision(revision);
    const previous: User | undefined = await UserRepo.getUserById(user.id, true);
    this.assertRevision(revision);
    if (previous === undefined) { throw new Error('账号不存在'); }
    user.isSelected = this.currentUser !== undefined && this.currentUser.id === user.id;
    try {
      await UserRepo.updateUser(user);
      this.assertRevision(revision);
    } catch (e) { await UserRepo.updateUser(previous); if (e instanceof Error) { throw e; } throw new Error('账号操作失败，请重试'); }
  }

  private async storeRoles(user: User, revision: number): Promise<void> {
    this.assertRevision(revision);
    const previous: UserGameRole[] = await UserRepo.getRolesByUserId(user.id);
    this.assertRevision(revision);
    try {
      await UserRepo.upsertRoles(user.id, user.roles);
      this.assertRevision(revision);
    } catch (e) { await UserRepo.upsertRoles(user.id, previous); if (e instanceof Error) { throw e; } throw new Error('账号操作失败，请重试'); }
  }

  private async storeCookie(user: User, revision: number): Promise<void> {
    this.assertRevision(revision);
    const previous: string = await UserRepo.loadCookieFor(user.id);
    this.assertRevision(revision);
    try {
      await UserRepo.saveCookieFor(user.id, user.fullCookie());
      this.assertRevision(revision);
    } catch (e) { await UserRepo.saveCookieFor(user.id, previous); if (e instanceof Error) { throw e; } throw new Error('账号操作失败，请重试'); }
  }

  /** Queue-owned rollback prevents a superseded partial write being adopted by the next intent. */
  private async commitUser(user: User, uid: string, revision: number, details: boolean, select: boolean): Promise<void> {
    this.assertRevision(revision);
    const previous: User | undefined = user.id > 0 ? await UserRepo.getUserById(user.id, true) : undefined;
    this.assertRevision(revision);
    let inserted: boolean = false;
    try {
      if (user.id <= 0) {
        await UserRepo.insertUser(user);
        inserted = true;
        this.assertRevision(revision);
      } else if (previous === undefined) { throw new Error('账号不存在'); }
      if (details) {
        await this.storeCookie(user, revision);
        await this.storeUserMetadata(user, revision);
      }
      await this.storeRoles(user, revision);
      if (select) { await this.selectAndPublish(user, uid, revision); }
    } catch (e) {
      if (inserted) { await UserRepo.deleteUser(user.id); }
      else if (previous !== undefined) {
        if (details) {
          await UserRepo.saveCookieFor(previous.id, previous.fullCookie());
          await UserRepo.updateUser(previous);
        }
        await UserRepo.upsertRoles(previous.id, previous.roles);
      }
      await this.repairSelection();
      if (e instanceof Error) { throw e; } throw new Error('账号操作失败，请重试');
    }
  }

  private applySessionState(user: User, uid: string): void {
    AppStorage.setOrCreate<boolean>('isLoggedIn', true);
    AppStorage.setOrCreate<number>('currentUserId', user.id);
    AppStorage.setOrCreate<string>('currentUid', uid);
    AppStorage.setOrCreate<string>('currentUserName', user.displayName);
    AppStorage.setOrCreate<string>('currentUserAvatar', user.avatar);
    PreferencesStore.setCurrentUserId(user.id);
    PreferencesStore.setCurrentUid(uid);
    ApiClient.getInstance().setCookie(user.fullCookie(), user.isOversea);
  }

  private clearSessionState(): void {
    AppStorage.setOrCreate<boolean>('isLoggedIn', false);
    AppStorage.setOrCreate<number>('currentUserId', 0);
    AppStorage.setOrCreate<string>('currentUid', '');
    AppStorage.setOrCreate<string>('currentUserName', '');
    AppStorage.setOrCreate<string>('currentUserAvatar', '');
    PreferencesStore.setCurrentUserId(0);
    PreferencesStore.setCurrentUid('');
    ApiClient.getInstance().setCookie('');
  }

  // ================= Cookie 解析 / 登录 =================

  createQrLogin(): Promise<QrLogin> {
    return PassportClient.createQrLogin();
  }

  queryQrLoginStatus(ticket: string): Promise<QrLoginResult> {
    return PassportClient.queryQrLoginStatus(ticket);
  }

  createLoginCaptcha(mobile: string, isActive?: () => boolean): Promise<MobileCaptcha> {
    return PassportClient.createLoginCaptcha(mobile, isActive);
  }

  requestMobileLogin(mobile: string, captcha: string, actionType: string, isActive?: () => boolean): Promise<LoginSession> {
    return PassportClient.loginByMobileCaptcha(mobile, captcha, actionType, isActive);
  }

  async loginWithQrResult(result: QrLoginResult): Promise<User> {
    const session: LoginSession = PassportClient.extractQrSession(result);
    return this.loginWithSession(session.stuid, session.stoken, session.mid, session.accountName);
  }

  cancelPendingLogin(revision: number): void {
    if (this.transitionPending && this.revision === revision && this.pendingLoginRevision === revision) {
      this.finishChange(revision);
    }
  }

  /** 解析 Cookie 字符串并构造用户（仅解析不落库） */
  parseCookie(raw: string, isOversea: boolean = false): User {
    const u: User = new User();
    u.isOversea = isOversea;
    u.applyCookie(raw);
    return u;
  }

  /** 国服角色绑定需要 SToken 和账号 ID。 */
  static validateCookie(user: User): boolean {
    return !user.isOversea && user.stoken.length > 0 && (user.stuid.length > 0 || user.accountId.length > 0);
  }

  /**
   * 登录：解析→去重(upsert)→Token 链补齐→角色拉取→选中→同步全局态。
   * @param rawCookie WebView 或手动粘贴的完整 Cookie
   * @param displayName 可选昵称
   * @param avatar 可选头像
   */
  async loginWithCookie(rawCookie: string, displayName: string, avatar: string, isOversea: boolean = false): Promise<User> {
    if (isOversea) { throw new Error('仅支持国服米游社账号'); }
    const revision: number = this.beginChange();
    this.pendingLoginRevision = revision;
    try {
      const parsed: User = new User();
      parsed.isOversea = isOversea;
      if (!parsed.applyCookie(rawCookie) || !UserService.validateCookie(parsed)) {
        throw new Error('Cookie 缺少有效的 SToken 或米游社账号 ID，请重新复制完整 Cookie');
      }
      parsed.displayName = displayName;
      parsed.avatar = avatar;
      parsed.createdAt = Date.now();
      await this.prepareChange('login', revision);
      await this.mutationTail;
      this.assertRevision(revision);
      const existingId: number = await this.findDuplicate(parsed);
      this.assertRevision(revision);
      const old: User | undefined = existingId > 0 ? await UserRepo.getUserById(existingId, true) : undefined;
      this.assertRevision(revision);
      const saved: User = old === undefined ? parsed : this.detached(old);
      if (old !== undefined) {
        saved.applyCookie(rawCookie);
        if (parsed.mid.length > 0 && parsed.mid === old.mid) { this.reuseOmittedTokens(saved, old, rawCookie); }
        if (saved.mid.length === 0) { saved.mid = old.mid; }
        saved.displayName = displayName.length > 0 ? displayName : old.displayName;
        saved.avatar = avatar.length > 0 ? avatar : old.avatar;
      }
      if (saved.stuid.length === 0) { saved.stuid = saved.accountId; }
      try { await this.ensureDeviceFingerprint(); }
      catch (e) { Logger.warn(TAG, 'ensure fingerprint failed'); }
      this.assertRevision(revision);
      const cookieExchanged: boolean = await this.completeTokenChainInner(saved, false, revision, undefined,
        this.cookieExchangeDue(saved.id));
      if (!saved.hasCookieToken() || !saved.hasLToken()) {
        throw new Error('未能取得完整登录凭证，请稍后重试');
      }
      if (saved.aid.length === 0) { saved.aid = saved.stuid; }
      saved.roles = await this.fetchRoles(saved, revision);
      if (saved.roles.length === 0) { throw new Error('该账号没有绑定国服原神角色'); }
      if (saved.displayName.length === 0 || saved.avatar.length === 0) {
        await this.loadUserFullInfo(saved, revision);
      }
      const uid: string = this.resolveDefaultUid(saved);
      await this.queueMutation(async () => {
        await this.commitUser(saved, uid, revision, true, true);
        if (cookieExchanged) { this.markCookieExchanged(saved.id); }
      });
      Logger.info(TAG, 'login completed');
      return saved;
    } finally {
      if (this.pendingLoginRevision === revision) { this.pendingLoginRevision = -1; }
      this.finishChange(revision);
    }
  }

  private reuseOmittedTokens(user: User, previous: User, rawCookie: string): void {
    const keys: string[] = rawCookie.split(';').map((pair: string): string => pair.substring(0, pair.indexOf('=')).trim());
    const cookieFields: string[] = ['account_id', 'cookie_token', 'account_id_v2', 'account_mid_v2', 'cookie_token_v2'];
    const ltokenFields: string[] = ['ltuid', 'ltoken', 'ltuid_v2', 'ltmid_v2', 'ltoken_v2'];
    if (previous.hasCookieToken() && !keys.some((key: string): boolean => cookieFields.includes(key))) {
      user.accountId = previous.accountId;
      user.cookieToken = previous.cookieToken;
      user.accountIdV2 = previous.accountIdV2;
      user.accountMidV2 = previous.accountMidV2;
      user.cookieTokenV2 = previous.cookieTokenV2;
    }
    if (previous.hasLToken() && !keys.some((key: string): boolean => ltokenFields.includes(key))) {
      user.ltuid = previous.ltuid;
      user.ltoken = previous.ltoken;
      user.ltuidV2 = previous.ltuidV2;
      user.ltmidV2 = previous.ltmidV2;
      user.ltokenV2 = previous.ltokenV2;
    }
  }

  private cookieExchangeDue(userId: number): boolean {
    if (userId <= 0) { return true; }
    const previous: number = PreferencesStore.getCookieExchangeTime(userId);
    const now: number = Date.now();
    return previous <= 0 || previous > now || now - previous >= COOKIE_REFRESH_INTERVAL_MS;
  }

  private markCookieExchanged(userId: number): void {
    try { PreferencesStore.setCookieExchangeTime(userId, Date.now()); }
    catch (e) { Logger.warn(TAG, 'cookie exchange time could not be recorded'); }
  }

  /**
   * 由登录会话（扫码/验证码得到的 stuid+stoken+mid）登录，复用 Cookie 链路。
   * @param session 含 stuid/stoken/mid/accountName
   */
  async loginWithSession(stuid: string, stoken: string, mid: string, accountName: string): Promise<User> {
    if (stuid.length === 0 || stoken.length === 0) {
      const revision: number = this.beginChange();
      this.finishChange(revision);
      throw new Error('登录结果缺少关键 token，请重试');
    }
    const pairs: string[] = [];
    pairs.push(`stuid=${stuid}`);
    pairs.push(`stoken=${stoken}`);
    if (mid.length > 0) {
      pairs.push(`mid=${mid}`);
    }
    const rawCookie: string = pairs.join('; ');
    Logger.info(TAG, 'login from session');
    return this.loginWithCookie(rawCookie, accountName, '');
  }

  /** 查找重复账号 id（同 mid/stuid/account_id），无则 0 */
  private async findDuplicate(candidate: User): Promise<number> {
    const all: User[] = await UserRepo.getAllUsers();
    const accountId: string = candidate.stuid || candidate.accountId;
    for (const user of all) {
      if (user.id === 0 || user.isOversea !== candidate.isOversea) { continue; }
      if (candidate.mid.length > 0 && user.mid.length > 0) {
        if (user.mid === candidate.mid) { return user.id; }
      } else if (accountId.length > 0 && (user.stuid === accountId || user.accountId === accountId || user.aid === accountId)) {
        return user.id;
      }
    }
    return 0;
  }

  /** Token 链补齐：SToken→LToken→cookie_token（best effort，失败仅记录）。
   *  说明：这两个接口需要 DS Gen2/PROD 签名 + 完整 passport(XRpc2) 头；
   *  缺 app_id/game_biz/sdk_version 等头会被米哈游拒绝导致拿不到 cookie_token。 */
  /** Refresh detached credentials; publication requires both revision and selected-object ownership. */
  async refreshCookieTokenForced(user: User, isActive?: () => Promise<boolean>): Promise<boolean> {
    this.assertAvailable();
    if (user.isOversea) { return false; }
    const revision: number = this.revision;
    const owner: User | undefined = this.selectedOwner(user);
    if (user.stoken.length === 0 && user.stokenV2.length === 0) { return false; }
    const snapshot: User = this.detached(user);
    if (!await this.completeTokenChainInner(snapshot, true, revision, isActive)) { return false; }
    await this.publishTokens(user, snapshot, owner, revision, true, isActive);
    return true;
  }

  private async assertTokenRefreshActive(isActive?: () => Promise<boolean>): Promise<void> {
    if (isActive !== undefined && !await isActive()) { throw new Error('任务已停止'); }
  }

  private async publishTokens(user: User, snapshot: User, owner: User | undefined, revision: number,
    cookieExchanged: boolean, isActive?: () => Promise<boolean>): Promise<void> {
    await this.queueMutation(async () => {
      this.assertRevision(revision);
      const stored: User | undefined = await UserRepo.getUserById(user.id, true);
      await this.assertTokenRefreshActive(isActive);
      this.assertRevision(revision);
      if (stored === undefined || !this.sameIdentity(stored, user)) { throw new Error('账号状态已变化，请重试'); }
      // A native task's ownership check includes the stored account alias.
      if (isActive !== undefined) { snapshot.aid = stored.aid; }
      const metadataChanged: boolean = snapshot.aid !== stored.aid;
      let metadataWritten: boolean = false;
      try {
        await UserRepo.saveCookieFor(snapshot.id, snapshot.fullCookie());
        await this.assertTokenRefreshActive(isActive);
        this.assertRevision(revision);
        if (metadataChanged) {
          snapshot.isSelected = this.currentUser?.id === snapshot.id;
          metadataWritten = true;
          await UserRepo.updateUser(snapshot);
        }
        this.assertRevision(revision);
      } catch (e) {
        const latest: User | undefined = isActive === undefined ? stored : await UserRepo.getUserById(stored.id, true);
        if (latest === undefined) {
          await UserRepo.removeCookieFor(stored.id);
        } else if (this.sameIdentity(latest, stored)) {
          await UserRepo.saveCookieFor(stored.id, stored.fullCookie());
          if (metadataWritten) { await UserRepo.updateUser(stored); }
        }
        if (e instanceof Error) { throw e; } throw new Error('账号操作失败，请重试');
      }
      user.applyCookie(snapshot.fullCookie());
      user.aid = snapshot.aid;
      if (cookieExchanged) { this.markCookieExchanged(snapshot.id); }
      if (owner !== undefined && this.currentUser === owner) {
        owner.applyCookie(snapshot.fullCookie());
        owner.aid = snapshot.aid;
        ApiClient.getInstance().setCookie(owner.fullCookie(), owner.isOversea);
      }
    });
  }

  private async completeTokenChainInner(user: User, forceRefresh: boolean, revision: number,
    isActive?: () => Promise<boolean>, refreshDue: boolean = false): Promise<boolean> {
    if (user.stoken.length === 0 && user.stokenV2.length === 0) {
      return false;
    }
    await this.assertTokenRefreshActive(isActive);
    this.assertRevision(revision);
    // 兜底：fp 缺失时先取（passport 交换需 x-rpc-device_fp，缺则被拒 → cookie_token 补不上）
    if (PreferencesStore.getDeviceFp().length === 0) {
      try {
        await this.ensureDeviceFingerprint();
      } catch (e) {
        Logger.warn(TAG, 'ensure fp before token chain fail');
      }
      await this.assertTokenRefreshActive(isActive);
    }
    this.assertRevision(revision);
    const stokenCookie: string = user.stokenCookie();
    const passportHeaders: Record<string, string> = HoyolabClient.passportHeaders();
    const fullHeaders: Record<string, string> = HoyolabClient.merge(passportHeaders, {
      'Cookie': stokenCookie,
    });
    let refreshed: boolean = false;
    // 1) 补 cookie_token（forceRefresh=true 时忽略已有值强制换新）
    if (forceRefresh || refreshDue || !user.hasCookieToken()) {
      const resp: ApiResponse = await this.exchangeToken('getCookieAccountInfoBySToken', fullHeaders, revision, isActive);
      this.assertRevision(revision);
      const data: Record<string, Object> | undefined = resp.data as Record<string, Object> | undefined;
      const accountId: string = String(data?.['uid'] ?? data?.['account_id'] ?? '');
      const cookieToken: string = String(data?.['cookie_token'] ?? '');
      if (resp.success && accountId.length > 0 && cookieToken.length > 0) {
        user.accountId = accountId;
        user.cookieToken = cookieToken;
        user.accountIdV2 = '';
        user.accountMidV2 = '';
        user.cookieTokenV2 = '';
        refreshed = true;
        if (user.aid.length === 0) { user.aid = accountId; }
      } else {
        Logger.warn(TAG, `getCookieAccountInfo failed retcode=${resp.retcode}`);
      }
    }
    // 2) 补 ltoken（forceRefresh=true 时同步换新）
    if (forceRefresh || !user.hasLToken()) {
      const resp: ApiResponse = await this.exchangeToken('getLTokenBySToken', fullHeaders, revision, isActive);
      this.assertRevision(revision);
      const data: Record<string, Object> | undefined = resp.data as Record<string, Object> | undefined;
      const ltoken: string = String(data?.['ltoken'] ?? '');
      if (resp.success && ltoken.length > 0 && ltoken !== 'undefined' && ltoken !== 'null') {
        user.ltoken = ltoken;
        user.ltuid = user.stuidV2 || user.stuid || user.accountId || user.aid;
        user.ltuidV2 = '';
        user.ltmidV2 = '';
        user.ltokenV2 = '';
      } else {
        Logger.warn(TAG, `getLToken failed retcode=${resp.retcode}`);
      }
    }
    this.assertRevision(revision);
    return refreshed;
  }

  private async exchangeToken(path: string, headers: Record<string, string>, revision: number,
    isActive?: () => Promise<boolean>): Promise<ApiResponse> {
    let dsHeaders: Record<string, string>;
    try { dsHeaders = await this.buildProdDsHeader(); }
    catch (e) {
      await this.assertTokenRefreshActive(isActive);
      this.assertRevision(revision);
      return ApiResponse.fail(-1, '登录凭证请求签名失败');
    }
    await this.assertTokenRefreshActive(isActive);
    this.assertRevision(revision);
    headers['DS'] = dsHeaders['DS'];
    let response: ApiResponse;
    try {
      response = await ApiClient.getInstance().get(`https://passport-api.mihoyo.com/account/auth/api/${path}`, headers);
    } catch (e) {
      response = ApiResponse.fail(-1, '登录凭证请求失败');
    }
    await this.assertTokenRefreshActive(isActive);
    return response;
  }

  /** 生成 passport 接口所需 DS Gen2/PROD 头（对齐 Windows PassportClient SignDataAsync(Gen2, PROD, true)：
   *  includeChars=true → r 为 6 位字母+数字；PROD 默认 body='{}'；GET 无 query → q 为空 */
  private async buildProdDsHeader(): Promise<Record<string, string>> {
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomLowerAlphaNumeric();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_PROD, t, r, '{}', '');
    return { 'DS': ds };
  }

  /** Cookie 鉴权失效判定（Windows 同款 retcode：-100 / 10001） */
  static isCookieAuthError(resp: ApiResponse): boolean {
    return resp.retcode === RetCodes.COOKIE_EXPIRED || resp.retcode === RetCodes.NOT_LOGGED_IN;
  }

  /** Cookie 鉴权失效时：用 SToken 强制换新 cookie_token/ltoken 并重试一次原请求。
   *  onRetry 由调用方提供（重新执行原 GET）。返回最终响应。 */
  static async retryWithRefreshedCookie(
    user: User, onRetry: () => Promise<ApiResponse>): Promise<ApiResponse> {
    const service: UserService = UserService.getInstance();
    const revision: number = service.sessionRevision();
    const ok: boolean = await service.refreshCookieTokenForced(user);
    service.assertRevision(revision);
    service.assertAvailable();
    if (!ok) {
      const fail: ApiResponse = ApiResponse.fail(RetCodes.COOKIE_EXPIRED,
        '未能刷新登录凭证，请重试或到「账号与数据」重新登录');
      return fail;
    }
    const response: ApiResponse = await onRetry();
    service.assertRevision(revision);
    return response;
  }

  /** 公开封装：补齐当前用户 Token 链（供各 Service 在缺 cookie_token 时调用） */
  async completeTokenChainPublic(user: User): Promise<void> {
    this.assertAvailable();
    if (user.isOversea) { throw new Error('仅支持国服米游社账号'); }
    const revision: number = this.revision;
    const owner: User | undefined = this.selectedOwner(user);
    if (owner !== undefined) {
      await this.completeSelectedTokenChain(user, owner, revision, this.cookieExchangeDue(owner.id));
      return;
    }
    const snapshot: User = this.detached(user);
    const cookieExchanged: boolean = await this.completeTokenChainInner(snapshot, false, revision);
    await this.publishTokens(user, snapshot, undefined, revision, cookieExchanged);
  }

  private async completeSelectedTokenChain(user: User, owner: User, revision: number, refreshDue: boolean): Promise<void> {
    let flight: SelectedTokenCompletion | undefined = this.selectedTokenCompletion;
    if (flight === undefined || flight.revision !== revision || flight.owner !== owner) {
      const result: Promise<void> = this.requestSelectedTokens(owner, revision, refreshDue).finally((): void => {
        if (this.selectedTokenCompletion?.result === result) { this.selectedTokenCompletion = undefined; }
      });
      flight = new SelectedTokenCompletion(owner, revision, refreshDue, result);
      this.selectedTokenCompletion = flight;
    }
    await flight.result;
    this.assertRevision(revision);
    if (this.currentUser !== owner) { throw new Error('账号状态已变化，请重试'); }
    // A Cookie may expire while an earlier request is completing another token group.
    if (refreshDue && !flight.refreshDue && this.cookieExchangeDue(owner.id)) {
      await this.completeSelectedTokenChain(user, owner, revision, true);
      return;
    }
    if (user !== owner) {
      user.applyCookie(owner.fullCookie());
      user.aid = owner.aid;
    }
  }

  private async requestSelectedTokens(owner: User, revision: number, refreshDue: boolean): Promise<void> {
    const snapshot: User = this.detached(owner);
    const cookieExchanged: boolean = await this.completeTokenChainInner(snapshot, false, revision, undefined, refreshDue);
    await this.publishTokens(owner, snapshot, owner, revision, cookieExchanged);
  }

  private sameIdentity(a: User, b: User): boolean {
    return a.id === b.id && a.isOversea === b.isOversea && a.mid === b.mid && a.aid === b.aid;
  }

  private selectedOwner(user: User): User | undefined {
    const selected: User | undefined = this.currentUser;
    return selected !== undefined && this.sameIdentity(selected, user) ? selected : undefined;
  }

  /** 公开封装：确保设备指纹就绪（供各 Service 请求前调用，降风控/保住 token 交换） */
  async ensureDeviceFingerprintPublic(): Promise<void> {
    try {
      await this.ensureDeviceFingerprint();
    } catch (e) {
      Logger.warn(TAG, 'ensure fingerprint public failed');
    }
  }

  /** 确保设备指纹存在（7 天有效），缺失时通过 getFp 接口获取真实指纹 */
  async ensureDeviceFingerprint(): Promise<void> {
    const existing: string = PreferencesStore.getDeviceFp();
    const lastTime: number = PreferencesStore.getDeviceFpTime();
    if (existing.length > 0 && Date.now() - lastTime < 7 * 24 * 60 * 60 * 1000) {
      return;
    }
    const bbsDeviceId: string = PreferencesStore.getDeviceId();
    const fp: string = await DeviceFpApi.fetchFingerprint(bbsDeviceId, existing);
    if (fp.length > 0) {
      PreferencesStore.setDeviceFp(fp);
      Logger.info(TAG, `device fingerprint refreshed len=${fp.length}`);
    }
  }

  /** 拉取账号完整信息（昵称/头像），address 该账号有效 aid；失败仅记录 */
  async fetchUserFullInfo(user: User): Promise<void> {
    this.assertAvailable();
    if (user.isOversea) { throw new Error('仅支持国服米游社账号'); }
    const revision: number = this.revision;
    const snapshot: User = this.detached(user);
    await this.loadUserFullInfo(snapshot, revision);
    await this.queueMutation(async () => {
      await this.storeUserMetadata(snapshot, revision);
      user.displayName = snapshot.displayName;
      user.avatar = snapshot.avatar;
    });
  }

  private async loadUserFullInfo(user: User, revision: number): Promise<void> {
    const id: string = user.aid.length > 0 ? user.aid
      : (user.accountId.length > 0 ? user.accountId
        : (user.stuid.length > 0 ? user.stuid : ''));
    if (id.length === 0) {
      return;
    }
    try {
      const url: string = `https://bbs-api.mihoyo.com/user/wapi/getUserFullInfo?uid=${id}&gids=2`;
      const resp: ApiResponse = await ApiClient.getInstance().get(url, {
        'Cookie': user.stokenCookie(),
        'Referer': 'https://bbs.mihoyo.com/',
      });
      this.assertRevision(revision);
      if (resp.success && resp.data !== undefined) {
        const data = resp.data as Record<string, Object>;
        const info = data['user_info'] as Record<string, Object>;
        if (info !== undefined && info !== null) {
          const nickname: string = String(info['nickname'] ?? '');
          let avatarUrl: string = String(info['avatar_url'] ?? '');
          // 头像 URL 若为相对/数字形式，回退拼默认头像地址（参考项目 AvatarUri 逻辑）
          if (avatarUrl.length === 0 || !avatarUrl.startsWith('http')) {
            const avatarId: string = String(info['avatar'] ?? '');
            const base: string = avatarUrl.length > 0 ? avatarUrl : avatarId;
            avatarUrl = base.length > 0
              ? `https://bbs-static.miyoushe.com/avatar/avatar${base}.png`
              : '';
          }
          if (nickname.length > 0) {
            user.displayName = nickname;
            Logger.info(TAG, 'profile name fetched');
          }
          if (avatarUrl.length > 0) {
            user.avatar = avatarUrl;
            Logger.info(TAG, 'profile avatar fetched');
          }
        }
      }
    } catch (e) {
      this.assertRevision(revision);
      Logger.warn(TAG, 'fetch user full info fail');
    }
  }

  // ================= 角色拉取 =================

  /** 通过 SToken → actionTicket → getUserGameRoles 拉取并持久化角色 */
  async fetchAndStoreRoles(user: User): Promise<UserGameRole[]> {
    this.assertAvailable();
    if (user.isOversea) { throw new Error('仅支持国服米游社账号'); }
    const revision: number = this.revision;
    const snapshot: User = this.detached(user);
    snapshot.roles = await this.fetchRoles(snapshot, revision);
    this.resolveDefaultUid(snapshot);
    await this.queueMutation(async () => { await this.storeRoles(snapshot, revision); });
    this.assertRevision(revision);
    return snapshot.roles;
  }

  private async fetchRoles(user: User, revision: number): Promise<UserGameRole[]> {
    const rolesResp: ApiResponse = await this.fetchChineseRoles(user, revision);
    this.assertRevision(revision);
    if (!rolesResp.success) {
      Logger.warn(TAG, `getUserGameRoles fail retcode=${rolesResp.retcode}`);
      if (UserService.isCookieAuthError(rolesResp)) { throw new Error('登录态已失效，请重新登录'); }
      if (rolesResp.retcode === RetCodes.RISK_CONTROL) { throw new Error('获取角色被风控拦截，请稍后重试'); }
      throw new Error('获取角色列表失败，请稍后重试');
    }
    const rolesData: Record<string, Object> | undefined = rolesResp.data as Record<string, Object> | undefined;
    const list: Object | undefined = rolesData?.['list'];
    if (!Array.isArray(list)) { throw new Error('米游社返回的角色列表无效，请稍后重试'); }
    const previousDefault: string = user.roles.find((role: UserGameRole): boolean => role.isDefault)?.gameUid ?? '';
    const roles: UserGameRole[] = [];
    for (const item of list as Object[]) {
      if (item === null || typeof item !== 'object') { continue; }
      const data: Record<string, Object> = item as Record<string, Object>;
      const gameUid: string = String(data['game_uid'] ?? '');
      const expectedRegion: string = RegionUtil.regionOfUid(gameUid);
      const region: string = String(data['region'] ?? expectedRegion);
      if (!RegionUtil.isCnUid(gameUid) || region !== expectedRegion) { continue; }
      const role: UserGameRole = UserGameRole.of(gameUid, region,
        String(data['nickname'] ?? ''), Number(data['level'] ?? 0));
      role.isDefault = gameUid === previousDefault;
      role.isChosen = data['is_chosen'] === true;
      roles.push(role);
    }
    Logger.info(TAG, `roles fetched count=${roles.length}`);
    return roles;
  }

  private async fetchChineseRoles(user: User, revision: number): Promise<ApiResponse> {
    if (user.stoken.length === 0) {
      throw new Error('账号缺少 SToken，请重新登录');
    }
    const useV2: boolean = user.stokenV2.length > 0 && user.stuidV2.length > 0;
    const stuid: string = useV2 ? user.stuidV2 : (user.stuid || user.aid);
    const stoken: string = useV2 ? user.stokenV2 : user.stoken;
    const ticketResp: ApiResponse = await HoyolabClient.getActionTicket(user.stokenCookie(), stoken, stuid);
    this.assertRevision(revision);
    if (!ticketResp.success || ticketResp.data === undefined) {
      Logger.warn(TAG, `getActionTicket fail retcode=${ticketResp.retcode}`);
      return ApiResponse.fail(ticketResp.success ? -1 : ticketResp.retcode, '无法获取角色凭证');
    }
    const ticketData = ticketResp.data as Record<string, Object>;
    const ticket: string = String(ticketData['ticket'] ?? '');
    if (ticket.length === 0) {
      Logger.warn(TAG, 'action ticket empty');
      return ApiResponse.fail(-1, '无法获取角色凭证');
    }
    return HoyolabClient.getUserGameRoles(ticket);
  }

  // ================= 账号管理 =================

  /** 切换账号。Failed/superseded transitions retain the last committed session. */
  async switchUser(userId: number): Promise<void> {
    const revision: number = this.beginChange();
    try {
      await this.prepareChange('switch', revision);
      await this.mutationTail;
      this.assertRevision(revision);
      const loaded: User | undefined = await UserRepo.getUserById(userId, true);
      this.assertRevision(revision);
      if (loaded === undefined) { throw new Error('账号不存在'); }
      if (loaded.isOversea) { throw new Error('仅支持国服米游社账号'); }
      if (!loaded.hasCookie()) { throw new Error('该账号缺少登录凭证，请重新登录'); }
      const user: User = this.detached(loaded);
      const uid: string = this.resolveDefaultUid(user);
      await this.queueMutation(async () => {
        await this.commitUser(user, uid, revision, false, true);
      });
      Logger.info(TAG, 'account switched');
    } finally { this.finishChange(revision); }
  }

  async deleteUser(userId: number): Promise<void> {
    const revision: number = this.beginChange();
    try {
      await this.prepareChange('delete', revision);
      await DailyNoteReminderService.cancelUser(userId);
      this.assertRevision(revision);
      await this.queueMutation(async () => {
        this.assertRevision(revision);
        const wasSelected: boolean = this.currentUser?.id === userId;
        try {
          await UserRepo.deleteUser(userId);
        } catch (e) {
          if (wasSelected || this.currentUser === undefined) {
            this.currentUser = undefined;
            this.currentUid = '';
            this.clearSessionState();
            await this.repairSelection();
          }
          if (e instanceof Error) { throw e; }
          throw new Error('删除账号失败，请重试');
        }
        if (wasSelected) {
          this.currentUser = undefined;
          this.currentUid = '';
          try {
            this.assertRevision(revision);
            const users: User[] = await this.readSavedUsers();
            this.assertRevision(revision);
            const next: User | undefined = users.find((user: User): boolean => !user.isOversea && user.hasCookie());
            if (next !== undefined) {
              await this.commitUser(next, this.resolveDefaultUid(next), revision, false, true);
            }
          } finally {
            if (this.currentUser === undefined) { this.clearSessionState(); }
          }
        } else if (this.currentUser === undefined) {
          this.clearSessionState();
          await this.repairSelection();
        }
        this.assertRevision(revision);
      });
    } finally { this.finishChange(revision); }
  }

  async logout(): Promise<void> {
    const revision: number = this.beginChange();
    try {
      await this.prepareChange('logout', revision);
      // Clear foreground only after the persistent background fence succeeds.
      this.currentUser = undefined;
      this.currentUid = '';
      this.clearSessionState();
      await this.queueMutation(async () => {
        this.assertRevision(revision);
        await this.selectAndPublish(undefined, '', revision);
      });
      Logger.info(TAG, 'logged out');
    } finally { this.finishChange(revision); }
  }

  async refreshRolesOfCurrent(): Promise<number> {
    this.assertAvailable();
    const selected: User | undefined = this.currentUser;
    if (selected === undefined) { throw new Error('请先登录'); }
    const revision: number = this.beginChange();
    try {
      await this.prepareChange('refreshRoles', revision);
      const user: User = this.detached(selected);
      user.roles = await this.fetchRoles(user, revision);
      const uid: string = this.resolveDefaultUid(user);
      await this.queueMutation(async () => {
        await this.commitUser(user, uid, revision, false, true);
      });
      return user.roles.length;
    } finally { this.finishChange(revision); }
  }

  async setDefaultUid(userId: number, uid: string): Promise<void> {
    const revision: number = this.beginChange();
    try {
      await this.prepareChange('defaultUid', revision);
      await this.mutationTail;
      this.assertRevision(revision);
      const loaded: User | undefined = await UserRepo.getUserById(userId, true);
      this.assertRevision(revision);
      if (loaded === undefined) { throw new Error('账号不存在'); }
      if (loaded.isOversea || !RegionUtil.isCnUid(uid)) { throw new Error('请选择国服角色'); }
      const user: User = this.detached(loaded);
      let found: boolean = false;
      for (const role of user.roles) {
        role.isDefault = role.gameUid === uid;
        role.isChosen = role.isDefault;
        found = found || role.isDefault;
      }
      if (!found) { throw new Error('账号未绑定该角色'); }
      await this.queueMutation(async () => {
        const selected: boolean = this.currentUser !== undefined && this.currentUser.id === userId;
        await this.commitUser(user, uid, revision, false, selected);
      });
    } finally { this.finishChange(revision); }
  }
}
