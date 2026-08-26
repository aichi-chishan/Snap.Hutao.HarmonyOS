/**
 * UserViewModel.ets
 * 账号管理页状态容器：账号列表、当前账号、角色绑定、切换/删除/刷新命令。
 */
import { UserService } from '../service/UserService';
import { UserRepo } from '../data/repo/UserRepo';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { Logger } from '../common/Logger';

const TAG: string = 'UserViewModel';

@Observed
export class UserViewModel {
  users: User[] = [];
  currentUser: User | undefined = undefined;
  currentUid: string = '';
  loading: boolean = false;
  message: string = '';

  /** 加载账号列表与当前账号 */
  async load(): Promise<void> {
    this.loading = true;
    try {
      this.users = await UserRepo.getAllUsers();
      const cur: User | undefined = this.currentUser;
      if (cur !== undefined) {
        this.currentUser = await UserRepo.getUserById(cur.id);
      } else {
        this.currentUser = await UserRepo.getCurrentUser();
      }
      this.currentUid = this.currentUser !== undefined ? await this.resolveDefaultUid(this.currentUser) : '';
    } catch (e) {
      this.message = (e as Error).message;
    } finally {
      this.loading = false;
    }
  }

  /** 取默认 UID；未设置时自动绑定第一个角色并落库（对齐 Windows 首次进入即绑定） */
  private async resolveDefaultUid(user: User): Promise<string> {
    if (user.roles.length === 0) {
      return '';
    }
    for (let i = 0; i < user.roles.length; i++) {
      if (user.roles[i].isDefault) {
        return user.roles[i].gameUid;
      }
    }
    const auto: string = user.roles[0].gameUid;
    try {
      await UserRepo.setDefaultUid(user.id, auto);
      user.roles[0].isDefault = true;
      AppStorage.setOrCreate<string>('currentUid', auto);
    } catch (e) {
      Logger.warn(TAG, `auto bind default uid fail: ${(e as Error).message}`);
    }
    return auto;
  }

  /** 选中某账号并同步全局态 */
  async switchUser(userId: number): Promise<void> {
    await UserService.getInstance().switchUser(userId);
    this.currentUser = await UserRepo.getUserById(userId);
    this.currentUid = this.currentUser !== undefined ? await this.resolveDefaultUid(this.currentUser) : '';
    await this.load();
  }

  async deleteUser(userId: number): Promise<void> {
    await UserService.getInstance().deleteUser(userId);
    if (this.currentUser !== undefined && this.currentUser.id === userId) {
      this.currentUser = undefined;
      this.currentUid = '';
    }
    await this.load();
  }

  /** 刷新当前账号角色列表，返回拉取到的角色数（供 UI 判断提示） */
  async refreshRoles(): Promise<number> {
    if (this.currentUser === undefined) {
      return 0;
    }
    this.loading = true;
    try {
      const roles: UserGameRole[] = await UserService.getInstance().fetchAndStoreRoles(this.currentUser);
      this.currentUser.roles = roles;
      this.currentUid = await this.resolveDefaultUid(this.currentUser);
      await this.load();
      return roles.length;
    } finally {
      this.loading = false;
    }
  }

  /** 设置默认 UID */
  async setDefaultUid(uid: string): Promise<void> {
    if (this.currentUser === undefined) {
      return;
    }
    await UserService.getInstance().setDefaultUid(this.currentUser.id, uid);
    this.currentUser.roles = await UserRepo.getRolesByUserId(this.currentUser.id);
    this.currentUid = uid;
  }
}
