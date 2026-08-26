/**
 * UserService.ets
 * Cookie 五件套解析→用户建模；Token 链补齐（SToken→LToken→cookie_token）；多账号增删/切换；
 * 角色绑定拉取；全局 AppStorage 状态同步。仅国服。
 * 注：AppStorage 为 ArkUI 全局对象，无需 import。
 */
import { UserRepo } from '../data/repo/UserRepo';
import { ApiClient } from '../data/network/ApiClient';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { DsSigner } from '../data/network/DsSigner';
import { DeviceFpApi } from '../data/network/DeviceFpApi';
import { ApiResponse } from '../model/ApiResponse';
import { AppConstants } from '../common/Constants';
import { User } from '../model/User';
import { UserGameRole } from '../model/UserGameRole';
import { Logger } from '../common/Logger';
import { RetCodes } from '../common/Constants';

const TAG: string = 'UserService';

export class UserService {
  private static instance: UserService = new UserService();

  static getInstance(): UserService {
    return UserService.instance;
  }

  /** 内存缓存当前用户 */
  private currentUser: User | undefined = undefined;

  getCurrentUser(): User | undefined {
    return this.currentUser;
  }

  // ================= 会话恢复 =================

  /** 启动时恢复登录态（EntryAbility 调用）：装载当前用户 + 注入 Cookie + 同步 AppStorage */
  async restoreSession(): Promise<void> {
    try {
      const user: User | undefined = await UserRepo.getCurrentUser();
      if (user !== undefined && user.hasCookie()) {
        this.currentUser = user;
        // 设备指纹必须先就绪：passport 接口（token 交换）需带 x-rpc-device_fp，缺指纹会被米哈游拒绝，
        // 导致 cookie_token/ltoken 补不上 → 战绩接口全部「重新登录」（成功不阻塞）。
        try {
          await this.ensureDeviceFingerprint();
        } catch (e) {
          Logger.warn(TAG, `ensure fingerprint fail ${(e as Error).message}`);
        }
        // 补齐 Token 链（cookie_token/ltoken），确保便笺/签到等可用
        if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
          await this.completeTokenChain(user);
        }
        const uid: string = await this.resolveDefaultUid(user);
        // 历史账号可能缺昵称/头像，启动时补拉（best effort，不阻塞）
        if (user.displayName.length === 0) {
          await this.fetchUserFullInfo(user);
        }
        this.applySessionState(user, uid);
        Logger.info(TAG, `session restored user=${user.id} uid=${uid}`);
      } else {
        this.clearSessionState();
        Logger.info(TAG, 'no saved session');
      }
    } catch (e) {
      Logger.warn(TAG, `restoreSession fail: ${JSON.stringify(e)}`);
      this.clearSessionState();
    }
  }

  private async resolveDefaultUid(user: User): Promise<string> {
    if (user.roles.length > 0) {
      let def: UserGameRole | undefined = undefined;
      for (let i = 0; i < user.roles.length; i++) {
        if (user.roles[i].isDefault) {
          def = user.roles[i];
          break;
        }
      }
      if (def !== undefined) {
        return def.gameUid;
      }
      // 未设置默认且仅有一个角色：自动绑定为默认 UID（对齐 Windows 首次进入即绑定）
      const auto: string = user.roles[0].gameUid;
      try {
        await UserRepo.setDefaultUid(user.id, auto);
        user.roles[0].isDefault = true;
      } catch (e) {
        Logger.warn(TAG, `auto bind default uid fail: ${(e as Error).message}`);
      }
      return auto;
    }
    return '';
  }

  /** 全局 AppStorage 状态同步 */
  private applySessionState(user: User, uid: string): void {
    AppStorage.setOrCreate<boolean>('isLoggedIn', true);
    AppStorage.setOrCreate<number>('currentUserId', user.id);
    AppStorage.setOrCreate<string>('currentUid', uid);
    AppStorage.setOrCreate<string>('currentUserName', user.displayName);
    AppStorage.setOrCreate<string>('currentUserAvatar', user.avatar);
    // 会话级 Cookie 注入
    ApiClient.getInstance().setCookie(user.fullCookie());
  }

  private clearSessionState(): void {
    AppStorage.setOrCreate<boolean>('isLoggedIn', false);
    AppStorage.setOrCreate<number>('currentUserId', 0);
    AppStorage.setOrCreate<string>('currentUid', '');
    AppStorage.setOrCreate<string>('currentUserName', '');
    AppStorage.setOrCreate<string>('currentUserAvatar', '');
    // 清持久化会话标记（杀后台/重启后不再自动恢复）
    PreferencesStore.setCurrentUserId(0);
    PreferencesStore.setCurrentUid('');
    ApiClient.getInstance().setCookie('');
  }

  // ================= Cookie 解析 / 登录 =================

  /** 解析 Cookie 字符串并构造用户（仅解析不落库） */
  parseCookie(raw: string): User {
    const u: User = new User();
    u.applyCookie(raw);
    return u;
  }

  /** 校验 Cookie 基本有效（含 stoken 或 account_id+cookie_token 且存在 stuid/uid） */
  static validateCookie(user: User): boolean {
    if (user.stoken.length > 0 && (user.stuid.length > 0 || user.accountId.length > 0)) {
      return true;
    }
    if (user.accountId.length > 0 && user.cookieToken.length > 0 && user.ltuid.length > 0) {
      return true;
    }
    return false;
  }

  /**
   * 登录：解析→去重(upsert)→Token 链补齐→角色拉取→选中→同步全局态。
   * @param rawCookie WebView 或手动粘贴的完整 Cookie
   * @param displayName 可选昵称
   * @param avatar 可选头像
   */
  async loginWithCookie(rawCookie: string, displayName: string, avatar: string): Promise<User> {
    const parsed: User = new User();
    const hasCookie: boolean = parsed.applyCookie(rawCookie);
    if (!hasCookie) {
      throw new Error('Cookie 中未解析到有效 token，请确认已复制完整 Cookie');
    }
    parsed.displayName = displayName;
    parsed.avatar = avatar;
    parsed.createdAt = Date.now();

    // 去重：优先按 mid / stuid / account_id 匹配
    const existingId: number = await this.findDuplicate(parsed);
    let saved: User = parsed;
    if (existingId > 0) {
      // upsert：复用原账号 id，更新 Cookie/昵称
      const old: User | undefined = await UserRepo.getUserById(existingId);
      if (old !== undefined) {
        saved = old.clone();
        saved.applyCookie(rawCookie);
        saved.displayName = displayName.length > 0 ? displayName : old.displayName;
        saved.avatar = avatar.length > 0 ? avatar : old.avatar;
        await UserRepo.updateUser(saved);
        Logger.info(TAG, `upsert existing user ${existingId}`);
      } else {
        await UserRepo.insertUser(saved);
      }
    } else {
      await UserRepo.insertUser(saved);
    }

    // Cookie 密文落库
    await UserRepo.saveCookieFor(saved.id, rawCookie);

    // 设备指纹必须先就绪：passport 接口（token 交换）需带 x-rpc-device_fp，
    // 缺指纹会被米哈游拒绝 → cookie_token/ltoken 补不上 → 战绩接口全部报「重新登录」
    try {
      await this.ensureDeviceFingerprint();
    } catch (e) {
      Logger.warn(TAG, `ensure fingerprint fail ${e.message}`);
    }

    // 补齐 Token 链（best effort）
    await this.completeTokenChain(saved);

    // 选为当前账号
    await UserRepo.selectUser(saved.id);
    await UserRepo.saveCookieFor(saved.id, saved.fullCookie());

    // 拉取角色绑定
    const roles: UserGameRole[] = await this.fetchAndStoreRoles(saved);
    saved.roles = roles;
    await UserRepo.updateUser(saved);

    // 补充分显示昵称/头像（getUserFullInfo）
    if (saved.displayName.length === 0 || saved.avatar.length === 0) {
      await this.fetchUserFullInfo(saved);
    }

    const uid: string = await this.resolveDefaultUid(saved);
    this.currentUser = saved;
    this.applySessionState(saved, uid);
    Logger.info(TAG, `login ok user=${saved.id} nickname=${saved.displayName} uid=${uid}`);
    return saved;
  }

  /**
   * 由登录会话（扫码/验证码得到的 stuid+stoken+mid）登录，复用 Cookie 链路。
   * @param session 含 stuid/stoken/mid/accountName
   */
  async loginWithSession(stuid: string, stoken: string, mid: string, accountName: string): Promise<User> {
    if (stuid.length === 0 || stoken.length === 0) {
      throw new Error('登录结果缺少关键 token，请重试');
    }
    const pairs: string[] = [];
    pairs.push(`stuid=${stuid}`);
    pairs.push(`stoken=${stoken}`);
    if (mid.length > 0) {
      pairs.push(`mid=${mid}`);
    }
    const rawCookie: string = pairs.join('; ');
    Logger.info(TAG, `loginWithSession stuid=${stuid} hasName=${accountName.length > 0}`);
    return this.loginWithCookie(rawCookie, accountName, '');
  }

  /** 查找重复账号 id（同 mid/stuid/account_id），无则 0 */
  private async findDuplicate(candidate: User): Promise<number> {
    const all: User[] = await UserRepo.getAllUsers();
    for (let i = 0; i < all.length; i++) {
      const u: User = all[i];
      if (u.id === 0) {
        continue;
      }
      if (candidate.mid.length > 0 && u.mid === candidate.mid) {
        return u.id;
      }
      if (candidate.stuid.length > 0 && u.stuid === candidate.stuid) {
        return u.id;
      }
      if (candidate.accountId.length > 0 && u.accountId === candidate.accountId) {
        return u.id;
      }
    }
    return 0;
  }

  /** Token 链补齐：SToken→LToken→cookie_token（best effort，失败仅记录）。
   *  说明：这两个接口需要 DS Gen2/PROD 签名 + 完整 passport(XRpc2) 头；
   *  缺 app_id/game_biz/sdk_version 等头会被米哈游拒绝导致拿不到 cookie_token。 */
  private async completeTokenChain(user: User): Promise<void> {
    if (user.stoken.length === 0 && user.stokenV2.length === 0) {
      return;
    }
    // 兜底：fp 缺失时先取（passport 交换需 x-rpc-device_fp，缺则被拒 → cookie_token 补不上）
    if (PreferencesStore.getDeviceFp().length === 0) {
      try {
        await this.ensureDeviceFingerprint();
      } catch (e) {
        Logger.warn(TAG, 'ensure fp before token chain fail');
      }
    }
    const stokenCookie: string = user.stokenCookie();
    const passportHeaders: Record<string, string> = HoyolabClient.passportHeaders();
    const fullHeaders: Record<string, string> = HoyolabClient.merge(passportHeaders, {
      'Cookie': stokenCookie,
    });
    // 1) 补 cookie_token
    if (user.cookieToken.length === 0) {
      try {
        const dsHeaders: Record<string, string> = await this.buildProdDsHeader();
        fullHeaders['DS'] = dsHeaders['DS'];
        const resp: ApiResponse = await ApiClient.getInstance().get(
          'https://passport-api.mihoyo.com/account/auth/api/getCookieAccountInfoBySToken',
          fullHeaders);
        if (resp.success && resp.data !== undefined) {
          const data = resp.data as Record<string, Object>;
          // 参考项目 UidCookieToken：{ uid, cookie_token }。uid 即 account_id
          const accountId: string = String(data['uid'] ?? data['account_id'] ?? '');
          const cookieToken: string = String(data['cookie_token'] ?? '');
          if (accountId.length > 0 && cookieToken.length > 0) {
            user.accountId = accountId;
            user.cookieToken = cookieToken;
            if (user.aid.length === 0) {
              user.aid = accountId;
            }
          } else {
            Logger.warn(TAG, `getCookieAccountInfo retcode=${resp.retcode} data empty, msg=${resp.message}`);
          }
        } else {
          Logger.warn(TAG, `getCookieAccountInfo fail retcode=${resp.retcode} msg=${resp.message} cookieLen=${stokenCookie.length} fpLen=${PreferencesStore.getDeviceFp().length}`);
        }
      } catch (e) {
        Logger.warn(TAG, 'complete cookie_token fail');
      }
    }
    // 2) 补 ltoken
    if (user.ltoken.length === 0) {
      try {
        const dsHeaders: Record<string, string> = await this.buildProdDsHeader();
        fullHeaders['DS'] = dsHeaders['DS'];
        const resp: ApiResponse = await ApiClient.getInstance().get(
          'https://passport-api.mihoyo.com/account/auth/api/getLTokenBySToken',
          fullHeaders);
        if (resp.success && resp.data !== undefined) {
          const data = resp.data as Record<string, Object>;
          // 参考项目 LTokenWrapper：{ ltoken }。ltuid 复用 stuid（同一账号 ID）
          const ltoken: string = String(data['ltoken'] ?? '');
          if (ltoken.length > 0 && ltoken !== 'undefined' && ltoken !== 'null') {
            user.ltoken = ltoken;
            if (user.ltuid.length === 0) {
              user.ltuid = user.stuid.length > 0 ? user.stuid : user.stuidV2;
            }
          } else {
            Logger.warn(TAG, `getLToken retcode=${resp.retcode} data empty, msg=${resp.message}`);
          }
        } else {
          Logger.warn(TAG, `getLToken fail retcode=${resp.retcode} msg=${resp.message}`);
        }
      } catch (e) {
        Logger.warn(TAG, 'complete ltoken fail');
      }
    }
    await UserRepo.saveCookieFor(user.id, user.fullCookie());
  }

  /** 生成 passport 接口所需 DS Gen2/PROD 头（对齐 Windows PassportClient SignDataAsync(Gen2, PROD, true)：
   *  includeChars=true → r 为 6 位字母+数字；PROD 默认 body='{}'；GET 无 query → q 为空 */
  private async buildProdDsHeader(): Promise<Record<string, string>> {
    const t: number = DsSigner.nowTimestamp();
    const r: string = DsSigner.randomLowerAlphaNumeric();
    const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_PROD, t, r, '{}', '');
    return { 'DS': ds };
  }

  /** 公开封装：补齐当前用户 Token 链（供各 Service 在缺 cookie_token 时调用） */
  async completeTokenChainPublic(user: User): Promise<void> {
    await this.completeTokenChain(user);
    // 同步全局会话 Cookie（含新补的 ltoken/ltoken）
    ApiClient.getInstance().setCookie(user.fullCookie());
  }

  /** 公开封装：确保设备指纹就绪（供各 Service 请求前调用，降风控/保住 token 交换） */
  async ensureDeviceFingerprintPublic(): Promise<void> {
    try {
      await this.ensureDeviceFingerprint();
    } catch (e) {
      Logger.warn(TAG, `ensure fingerprint public fail ${(e as Error).message}`);
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
            Logger.info(TAG, `fetched nickname=${nickname}`);
          }
          if (avatarUrl.length > 0) {
            user.avatar = avatarUrl;
            Logger.info(TAG, `fetched avatar=${avatarUrl}`);
          }
          await UserRepo.updateUser(user);
        }
      }
    } catch (e) {
      Logger.warn(TAG, 'fetch user full info fail');
    }
  }

  // ================= 角色拉取 =================

  /** 通过 SToken → actionTicket → getUserGameRoles 拉取并持久化角色 */
  async fetchAndStoreRoles(user: User): Promise<UserGameRole[]> {
    if (user.stoken.length === 0) {
      Logger.warn(TAG, 'no stoken, skip role fetch');
      return [];
    }
    const stuid: string = user.stuid.length > 0 ? user.stuid : user.aid;
    const ticketResp: ApiResponse = await HoyolabClient.getActionTicket(user.stokenCookie(), user.stoken, stuid);
    if (!ticketResp.success || ticketResp.data === undefined) {
      Logger.warn(TAG, `getActionTicket fail retcode=${ticketResp.retcode} msg=${ticketResp.message}`);
      if (ticketResp.retcode === RetCodes.RISK_CONTROL) {
        throw new Error('获取角色被风控拦截，请稍后重试');
      }
      return [];
    }
    const ticketData = ticketResp.data as Record<string, Object>;
    const ticket: string = String(ticketData['ticket'] ?? '');
    if (ticket.length === 0) {
      Logger.warn(TAG, 'action ticket empty');
      return [];
    }
    const rolesResp: ApiResponse = await HoyolabClient.getUserGameRoles(ticket);
    if (rolesResp.success && rolesResp.data !== undefined) {
      const rolesData = rolesResp.data as Record<string, Object>;
      const list = rolesData['list'] as Array<Object>;
      const roles: UserGameRole[] = [];
      if (list !== undefined && list !== null) {
        for (let i = 0; i < list.length; i++) {
          const item = list[i] as Record<string, Object>;
          const gameUid: string = String(item['game_uid'] ?? '');
          if (gameUid.length === 0) {
            continue;
          }
          const region: string = String(item['region'] ?? 'cn_gf01');
          const nickname: string = String(item['nickname'] ?? '');
          const level: number = Number(item['level'] ?? 0);
          const role: UserGameRole = UserGameRole.of(gameUid, region, nickname, level);
          roles.push(role);
        }
      }
      await UserRepo.upsertRoles(user.id, roles);
      // 回读落库后的角色（带 is_default 标志），保证返回行与 DB 一致
      const stored: UserGameRole[] = await UserRepo.getRolesByUserId(user.id);
      if (stored.length > 0) {
        let hasDefault: boolean = false;
        for (let i = 0; i < stored.length; i++) {
          if (stored[i].isDefault) {
            hasDefault = true;
            break;
          }
        }
        // 未设置默认且仅有一个角色：自动绑定为默认 UID（对齐 Windows 首次进入即绑定）
        if (!hasDefault) {
          await UserRepo.setDefaultUid(user.id, stored[0].gameUid);
          stored[0].isDefault = true;
        }
      }
      Logger.info(TAG, `roles fetched count=${roles.length}`);
      return stored;
    }
    Logger.warn(TAG, `getUserGameRoles fail retcode=${rolesResp.retcode} msg=${rolesResp.message}`);
    if (rolesResp.retcode === RetCodes.RISK_CONTROL) {
      throw new Error('获取角色被风控拦截，请稍后重试');
    }
    return [];
  }

  // ================= 账号管理 =================

  /** 切换账号 */
  async switchUser(userId: number): Promise<void> {
    const user: User | undefined = await UserRepo.getUserById(userId);
    if (user === undefined) {
      throw new Error('账号不存在');
    }
    await UserRepo.selectUser(userId);
    const uid: string = await this.resolveDefaultUid(user);
    this.currentUser = user;
    this.applySessionState(user, uid);
    Logger.info(TAG, `switched to user=${userId} uid=${uid}`);
  }

  /** 删除账号 */
  async deleteUser(userId: number): Promise<void> {
    await UserRepo.deleteUser(userId);
    if (this.currentUser !== undefined && this.currentUser.id === userId) {
      this.currentUser = undefined;
      this.clearSessionState();
    }
  }

  /** 退出登录（清当前态，不清账号数据） */
  async logout(): Promise<void> {
    this.currentUser = undefined;
    this.clearSessionState();
    Logger.info(TAG, 'logged out');
  }

  /** 刷新当前账号角色列表并更新默认 UID */
  async refreshRolesOfCurrent(): Promise<void> {
    const user: User | undefined = this.currentUser;
    if (user === undefined) {
      return;
    }
    const roles: UserGameRole[] = await this.fetchAndStoreRoles(user);
    user.roles = roles;
    await UserRepo.updateUser(user);
    const uid: string = await this.resolveDefaultUid(user);
    AppStorage.setOrCreate<string>('currentUid', uid);
  }

  /** 设置默认 UID */
  async setDefaultUid(userId: number, uid: string): Promise<void> {
    await UserRepo.setDefaultUid(userId, uid);
    const user: User | undefined = this.currentUser;
    if (user !== undefined) {
      user.roles = await UserRepo.getRolesByUserId(userId);
      AppStorage.setOrCreate<string>('currentUid', uid);
    }
  }
}
