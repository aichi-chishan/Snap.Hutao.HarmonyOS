/** Account-page state. Only UserService owns selected account/UID publication. */
import { UserService } from '../service/UserService';
import { UserRepo } from '../data/repo/UserRepo';
import { User } from '../model/User';

@Observed
export class UserViewModel {
  users: User[] = [];
  currentUser: User | undefined = undefined;
  currentUid: string = '';
  loading: boolean = false;
  message: string = '';
  private loadRevision: number = 0;

  async load(): Promise<void> {
    const request: number = ++this.loadRevision;
    const service: UserService = UserService.getInstance();
    const revision: number = service.sessionRevision();
    this.loading = true;
    try {
      const users: User[] = await UserRepo.getAllUsers();
      if (request !== this.loadRevision || revision !== service.sessionRevision()) { return; }
      this.users = users;
      this.currentUser = service.getCurrentUser();
      this.currentUid = this.defaultUid(this.currentUser);
    } catch (e) {
      if (request === this.loadRevision && revision === service.sessionRevision()) {
        this.message = (e as Error).message;
      }
    } finally {
      if (request === this.loadRevision) { this.loading = false; }
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

  async refreshRoles(): Promise<number> {
    const service: UserService = UserService.getInstance();
    const selected: User | undefined = service.getCurrentUser();
    if (this.currentUser === undefined || selected === undefined || this.currentUser.id !== selected.id) { return 0; }
    const request: number = ++this.loadRevision;
    this.loading = true;
    try {
      await service.refreshRolesOfCurrent();
      await this.load();
      return this.currentUser === undefined ? 0 : this.currentUser.roles.length;
    } finally {
      if (request === this.loadRevision) { this.loading = false; }
    }
  }

  async setDefaultUid(uid: string): Promise<void> {
    const user: User | undefined = this.currentUser;
    if (user === undefined) { return; }
    this.loadRevision++;
    await UserService.getInstance().setDefaultUid(user.id, uid);
    await this.load();
  }
}
