/** Account-page state. Only UserService owns selected account/UID publication. */
import { UserService } from '../service/UserService';
import { RoleProfilePictureService } from '../service/RoleProfilePictureService';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { RegionUtil } from '../common/Constants';

export class UserAccountItem {
  id: number;
  displayName: string;
  avatar: string;
  accountId: string;
  isSelected: boolean;
  isOversea: boolean;
  canSwitch: boolean;
  canMoveUp: boolean;
  canMoveDown: boolean;

  constructor(user: User, selectedId: number, index: number = 0, count: number = 1) {
    this.id = user.id;
    this.displayName = user.displayName || '未命名账号';
    this.avatar = user.avatar;
    this.accountId = user.stuid || user.accountId || user.aid || '—';
    this.isSelected = user.id === selectedId;
    this.isOversea = user.isOversea;
    this.canSwitch = !user.isOversea && user.hasCookie();
    this.canMoveUp = index > 0;
    this.canMoveDown = index < count - 1;
  }

  key(): string {
    return `${this.id}_${this.isSelected}_${this.displayName}_${this.avatar}_${this.accountId}_${this.isOversea}_${this.canSwitch}_${this.canMoveUp}_${this.canMoveDown}`;
  }
}

export class UserRoleItem {
  userId: number;
  gameUid: string;
  nickname: string;
  description: string;
  isDefault: boolean;
  canRefreshAvatar: boolean;
  avatarIcon: string;

  constructor(userId: number, role: UserGameRole) {
    this.userId = userId;
    this.gameUid = role.gameUid;
    this.nickname = role.nickname || `旅行者${role.gameUid}`;
    let server: string = role.region;
    if (role.region === 'cn_gf01') { server = '官服'; }
    else if (role.region === 'cn_qd01') { server = '渠道服'; }
    this.description = `UID ${role.gameUid} · ${server} · Lv.${role.level}`;
    this.isDefault = role.isDefault;
    this.canRefreshAvatar = RegionUtil.isCnUid(role.gameUid) && role.region === RegionUtil.regionOfUid(role.gameUid);
    this.avatarIcon = this.canRefreshAvatar ? RoleProfilePictureService.cachedIcon(role.gameUid) : '';
  }

  key(): string {
    return `${this.userId}_${this.gameUid}_${this.isDefault}_${this.nickname}_${this.description}_${this.avatarIcon}`;
  }
}

@Observed
export class UserViewModel {
  users: UserAccountItem[] = [];
  currentUser: User | undefined = undefined;
  currentAccount: UserAccountItem | undefined = undefined;
  currentUid: string = '';
  roles: UserRoleItem[] = [];
  loaded: boolean = false;
  message: string = '';
  private active: boolean = true;
  private loadRevision: number = 0;
  private readonly autoLoadRoleAvatars: boolean;

  constructor(autoLoadRoleAvatars: boolean = true) {
    this.autoLoadRoleAvatars = autoLoadRoleAvatars;
  }

  activate(): void { this.active = true; }

  dispose(): void {
    this.active = false;
    this.loadRevision++;
  }

  watchSession(listener: () => void): () => void {
    const service: UserService = UserService.getInstance();
    return service.addSessionRevisionListener((): void => {
      if (!service.isSessionTransitionPending()) { listener(); }
    });
  }

  async load(): Promise<void> {
    const service: UserService = UserService.getInstance();
    if (!this.active || service.isSessionTransitionPending()) { return; }
    const request: number = ++this.loadRevision;
    const revision: number = service.sessionRevision();
    this.message = '';
    try {
      const users: User[] = await service.getSavedUsers();
      if (request !== this.loadRevision || revision !== service.sessionRevision()) { return; }
      const current: User | undefined = service.getCurrentUser();
      const selectedId: number = current?.id ?? 0;
      this.currentUser = current;
      this.currentAccount = current === undefined ? undefined : new UserAccountItem(current, selectedId);
      this.currentUid = this.defaultUid(current);
      this.roles = current === undefined ? [] : current.roles.map((role: UserGameRole): UserRoleItem =>
        new UserRoleItem(selectedId, role));
      this.users = users.map((user: User, index: number): UserAccountItem =>
        new UserAccountItem(user, selectedId, index, users.length));
      if (current !== undefined && this.autoLoadRoleAvatars) { this.loadRoleAvatars(selectedId, revision, request); }
    } catch (e) {
      if (request === this.loadRevision && revision === service.sessionRevision()) {
        this.message = (e as Error).message;
      }
    } finally {
      if (request === this.loadRevision && revision === service.sessionRevision()) { this.loaded = true; }
    }
  }

  /** Read-only: displaying an account list never changes global or durable selection. */
  private defaultUid(user: User | undefined): string {
    if (user === undefined) { return ''; }
    for (const role of user.roles) { if (role.isDefault) { return role.gameUid; } }
    return user.roles.length > 0 ? user.roles[0].gameUid : '';
  }

  async switchUser(userId: number): Promise<void> {
    this.loadRevision++;
    await UserService.getInstance().switchUser(userId);
    await this.load();
  }

  async deleteUser(userId: number): Promise<void> {
    this.loadRevision++;
    await UserService.getInstance().deleteUser(userId);
    await this.load();
  }

  async moveUser(userId: number, direction: number): Promise<void> {
    await UserService.getInstance().moveSavedUser(userId, direction);
    await this.load();
  }

  async logout(): Promise<void> {
    this.loadRevision++;
    await UserService.getInstance().logout();
    await this.load();
  }

  private selectedUser(): User {
    const user: User | undefined = UserService.getInstance().getCurrentUser();
    if (user === undefined || user.id !== this.currentUser?.id) { throw new Error('当前账号已变化，请重试'); }
    return user;
  }

  private ownsRole(uid: string, userId: number, revision: number, loadRevision: number): boolean {
    const service: UserService = UserService.getInstance();
    const user: User | undefined = service.getCurrentUser();
    return this.active && this.loadRevision === loadRevision && service.sessionRevision() === revision &&
      user !== undefined && !user.isOversea && user.id === userId && RegionUtil.isCnUid(uid) &&
      user.roles.some((role: UserGameRole): boolean => role.gameUid === uid && role.region === RegionUtil.regionOfUid(uid));
  }

  private publishRoleAvatar(userId: number, uid: string, icon: string): void {
    const row: UserRoleItem | undefined = this.roles.find((role: UserRoleItem): boolean =>
      role.userId === userId && role.gameUid === uid);
    if (row === undefined || row.avatarIcon === icon) { return; }
    row.avatarIcon = icon;
    this.roles = this.roles.slice();
  }

  private async loadRoleAvatars(userId: number, revision: number, loadRevision: number): Promise<void> {
    for (const role of this.roles.slice()) {
      if (!role.canRefreshAvatar || role.avatarIcon.length > 0) { continue; }
      const isCurrent: () => boolean = (): boolean => this.ownsRole(role.gameUid, userId, revision, loadRevision);
      if (!isCurrent()) { return; }
      const icon: string = await RoleProfilePictureService.loadIcon(role.gameUid, false, isCurrent);
      if (!isCurrent()) { return; }
      if (icon.length > 0) { this.publishRoleAvatar(userId, role.gameUid, icon); }
    }
  }

  async refreshRoleAvatar(uid: string, userId: number): Promise<boolean> {
    const revision: number = UserService.getInstance().sessionRevision();
    const loadRevision: number = this.loadRevision;
    const isCurrent: () => boolean = (): boolean => this.ownsRole(uid, userId, revision, loadRevision);
    if (!isCurrent()) { throw new Error('当前账号或角色已变化，请重试'); }
    const icon: string = await RoleProfilePictureService.loadIcon(uid, true, isCurrent);
    if (!isCurrent()) { throw new Error('当前账号或角色已变化，请重试'); }
    if (icon.length === 0) { return false; }
    this.publishRoleAvatar(userId, uid, icon);
    return true;
  }

  canOpenTravelTools(): boolean {
    return this.currentAccount !== undefined && RegionUtil.isCnUid(this.currentUid) &&
      this.roles.some((role: UserRoleItem): boolean => role.isDefault && role.gameUid === this.currentUid);
  }

  cookieForClipboard(): string {
    const user: User = this.selectedUser();
    return user.hasCookie() ? user.fullCookie() : '';
  }

  savedCookieForClipboard(userId: number): Promise<string> {
    return UserService.getInstance().getSavedAccountCookie(userId);
  }

  refreshCredentials(): Promise<boolean> {
    return UserService.getInstance().refreshCookieTokenForced(this.selectedUser());
  }

  async refreshRoles(): Promise<number> {
    this.selectedUser();
    this.loadRevision++;
    const count: number = await UserService.getInstance().refreshRolesOfCurrent();
    await this.load();
    return count;
  }

  async setDefaultUid(uid: string, expectedAccountId: number): Promise<void> {
    const user: User = this.selectedUser();
    if (user.id !== expectedAccountId) { throw new Error('当前账号已变化，请重试'); }
    this.loadRevision++;
    await UserService.getInstance().setDefaultUid(user.id, uid);
    await this.load();
  }
}
