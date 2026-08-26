/**
 * UserRepo.ets
 * user_accounts / user_game_roles 表 CRUD + 当前账号/默认 UID 读写 + Token 密文存储(TokenVault)。
 */
import { relationalStore } from '@kit.ArkData';
import { RelationalStoreHelper } from '../db/RelationalStoreHelper';
import { PreferencesStore } from '../prefs/PreferencesStore';
import { TokenVault } from '../local/TokenVault';
import { User } from '../../model/User';
import { UserGameRole } from '../../model/UserGameRole';
import { Logger } from '../../common/Logger';

const TAG: string = 'UserRepo';

export class UserRepo {
  // ================= 账号 CRUD =================

  /** 插入账号，返回自增 id */
  static async insertUser(user: User): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'mid': user.mid,
      'aid': user.aid,
      'is_oversea': 0,
      // Token 密文走 TokenVault，表内仅存占位（不明文落库）
      'cookie_account_token': '',
      'cookie_ltoken_ltuid': '',
      'cookie_stoken_stuid': '',
      'display_nickname': user.displayName,
      'avatar': user.avatar,
      'is_selected': user.isSelected ? 1 : 0,
      'created_at': user.createdAt > 0 ? user.createdAt : Date.now(),
    };
    const id: number = await RelationalStoreHelper.insert('user_accounts', values);
    user.id = id;
    return id;
  }

  /** 更新账号展示信息 */
  static async updateUser(user: User): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'mid': user.mid,
      'aid': user.aid,
      'display_nickname': user.displayName,
      'avatar': user.avatar,
      'is_selected': user.isSelected ? 1 : 0,
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_accounts');
    predicates.equalTo('id', user.id);
    await RelationalStoreHelper.update('user_accounts', values, predicates);
  }

  static async deleteUser(id: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_accounts');
    predicates.equalTo('id', id);
    await RelationalStoreHelper.delete('user_accounts', predicates);
    // 级联删除角色
    const rolePred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_game_roles');
    rolePred.equalTo('user_id', id);
    await RelationalStoreHelper.delete('user_game_roles', rolePred);
    await TokenVault.removeCookie(id);
    Logger.info(TAG, `deleted user ${id}`);
    // 若删除的是当前账号，清 prefer
    if (PreferencesStore.getCurrentUserId() === id) {
      PreferencesStore.setCurrentUserId(0);
      PreferencesStore.setCurrentUid('');
    }
  }

  private static rowToUser(rs: relationalStore.ResultSet): User {
    const u: User = new User();
    u.id = rs.getLong(rs.getColumnIndex('id'));
    u.mid = rs.getString(rs.getColumnIndex('mid'));
    u.aid = rs.getString(rs.getColumnIndex('aid'));
    u.displayName = rs.getString(rs.getColumnIndex('display_nickname'));
    u.avatar = rs.getString(rs.getColumnIndex('avatar'));
    u.isSelected = rs.getLong(rs.getColumnIndex('is_selected')) === 1;
    u.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    return u;
  }

  static async getAllUsers(): Promise<User[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_accounts');
    predicates.orderByDesc('created_at');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(predicates);
    const list: User[] = [];
    try {
      while (rs.goToNextRow()) {
        list.push(UserRepo.rowToUser(rs));
      }
    } finally {
      rs.close();
    }
    // 为每个账号装载 Cookie（密文解密）与角色
    for (let i = 0; i < list.length; i++) {
      const cookie: string = await TokenVault.loadCookie(list[i].id);
      list[i].applyCookie(cookie);
      list[i].roles = await UserRepo.getRolesByUserId(list[i].id);
    }
    return list;
  }

  static async getUserById(id: number): Promise<User | undefined> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_accounts');
    predicates.equalTo('id', id);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(predicates);
    let u: User | undefined = undefined;
    try {
      if (rs.goToFirstRow()) {
        u = UserRepo.rowToUser(rs);
      }
    } finally {
      rs.close();
    }
    if (u !== undefined) {
      const cookie: string = await TokenVault.loadCookie(u.id);
      u.applyCookie(cookie);
      u.roles = await UserRepo.getRolesByUserId(u.id);
    }
    return u;
  }

  /** 将某账号设为当前（清除其他账号 is_selected） */
  static async selectUser(id: number): Promise<void> {
    // 先清除所有标记
    const clearValues: relationalStore.ValuesBucket = { 'is_selected': 0 };
    const clearPred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_accounts');
    await RelationalStoreHelper.update('user_accounts', clearValues, clearPred);
    const values: relationalStore.ValuesBucket = { 'is_selected': 1 };
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_accounts');
    pred.equalTo('id', id);
    await RelationalStoreHelper.update('user_accounts', values, pred);
    PreferencesStore.setCurrentUserId(id);
  }

  static async getSelectedUserId(): Promise<number> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_accounts');
    pred.equalTo('is_selected', 1);
    pred.limitAs(1);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let id: number = 0;
    try {
      if (rs.goToFirstRow()) {
        id = rs.getLong(rs.getColumnIndex('id'));
      }
    } finally {
      rs.close();
    }
    if (id === 0) {
      id = PreferencesStore.getCurrentUserId();
    }
    return id;
  }

  // ================= 角色 CRUD =================

  static async upsertRoles(userId: number, roles: UserGameRole[]): Promise<void> {
    // 清除旧角色
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_game_roles');
    pred.equalTo('user_id', userId);
    await RelationalStoreHelper.delete('user_game_roles', pred);
    // 插入新角色
    for (let i = 0; i < roles.length; i++) {
      const role: UserGameRole = roles[i];
      const values: relationalStore.ValuesBucket = {
        'user_id': userId,
        'game_uid': role.gameUid,
        'region': role.region,
        'nickname': role.nickname,
        'level': role.level,
        'is_default': role.isDefault ? 1 : 0,
        'is_chosen': role.isChosen ? 1 : 0,
      };
      await RelationalStoreHelper.insert('user_game_roles', values);
    }
    Logger.info(TAG, `upsert ${roles.length} roles for user ${userId}`);
  }

  static async getRolesByUserId(userId: number): Promise<UserGameRole[]> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_game_roles');
    pred.equalTo('user_id', userId);
    pred.orderByDesc('is_default');
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    const list: UserGameRole[] = [];
    try {
      while (rs.goToNextRow()) {
        const role: UserGameRole = new UserGameRole();
        role.id = rs.getLong(rs.getColumnIndex('id'));
        role.userId = rs.getLong(rs.getColumnIndex('user_id'));
        role.gameUid = rs.getString(rs.getColumnIndex('game_uid'));
        role.region = rs.getString(rs.getColumnIndex('region'));
        role.nickname = rs.getString(rs.getColumnIndex('nickname'));
        role.level = rs.getLong(rs.getColumnIndex('level'));
        role.isDefault = rs.getLong(rs.getColumnIndex('is_default')) === 1;
        role.isChosen = rs.getLong(rs.getColumnIndex('is_chosen')) === 1;
        list.push(role);
      }
    } finally {
      rs.close();
    }
    return list;
  }

  /** 保存默认 UID 到 preferences 并更新角色标记 */
  static async setDefaultUid(userId: number, uid: string): Promise<void> {
    PreferencesStore.setCurrentUid(uid);
    const roles: UserGameRole[] = await UserRepo.getRolesByUserId(userId);
    for (let i = 0; i < roles.length; i++) {
      const role: UserGameRole = roles[i];
      const isDef: boolean = role.gameUid === uid;
      const values: relationalStore.ValuesBucket = { 'is_default': isDef ? 1 : 0, 'is_chosen': isDef ? 1 : 0 };
      const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_game_roles');
      pred.equalTo('id', role.id);
      await RelationalStoreHelper.update('user_game_roles', values, pred);
    }
  }

  static async getDefaultRole(userId: number): Promise<UserGameRole | undefined> {
    const pred: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('user_game_roles');
    pred.equalTo('user_id', userId);
    pred.equalTo('is_default', 1);
    pred.limitAs(1);
    const rs: relationalStore.ResultSet = await RelationalStoreHelper.query(pred);
    let role: UserGameRole | undefined = undefined;
    try {
      if (rs.goToFirstRow()) {
        role = new UserGameRole();
        role.id = rs.getLong(rs.getColumnIndex('id'));
        role.userId = rs.getLong(rs.getColumnIndex('user_id'));
        role.gameUid = rs.getString(rs.getColumnIndex('game_uid'));
        role.region = rs.getString(rs.getColumnIndex('region'));
        role.nickname = rs.getString(rs.getColumnIndex('nickname'));
        role.level = rs.getLong(rs.getColumnIndex('level'));
        role.isDefault = true;
        role.isChosen = true;
      }
    } finally {
      rs.close();
    }
    return role;
  }

  /** 当前已登录用户（Preferences 记录的 id → 装载） */
  static async getCurrentUser(): Promise<User | undefined> {
    const id: number = PreferencesStore.getCurrentUserId();
    if (id <= 0) {
      return undefined;
    }
    return UserRepo.getUserById(id);
  }

  // ================= Token 密文存储 =================

  static async saveCookieFor(userId: number, cookie: string): Promise<void> {
    await TokenVault.saveCookie(userId, cookie);
  }

  static async loadCookieFor(userId: number): Promise<string> {
    return TokenVault.loadCookie(userId);
  }

  static async removeCookieFor(userId: number): Promise<void> {
    await TokenVault.removeCookie(userId);
  }
}
