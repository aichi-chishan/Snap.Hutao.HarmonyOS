/**
 * User.ets
 * 米游社账号实体 + Cookie 五件套（account_id/cookie_token、ltoken/ltuid、stoken/stuid/mid）。
 * 提供 Cookie 字符串解析 / 组装 / 序列化。落库时 Token 部分走 TokenVault 密文存储。
 */
import { UserGameRole } from './UserGameRole';

export class User {
  id: number = 0;
  /** 米游社 mid（用户唯一标识） */
  mid: string = '';
  /** account_id（较短 ID） */
  aid: string = '';

  /* ---- Cookie 五件套原始字段（内存态明文） ---- */
  accountId: string = '';
  cookieToken: string = '';
  ltuid: string = '';
  ltoken: string = '';
  stuid: string = '';
  stoken: string = '';
  /** v2 体系原始键值（2023+ bbs 迁移后 stoken_v2/stuid_v2），交换接口优先使用 */
  stuidV2: string = '';
  stokenV2: string = '';

  displayName: string = '';
  avatar: string = '';
  isSelected: boolean = false;
  createdAt: number = 0;
  roles: UserGameRole[] = [];

  /** 是否已具备有效 Cookie 态 */
  hasCookie(): boolean {
    return this.accountId.length > 0 || this.stuid.length > 0;
  }

  /** 战绩类接口所需 Cookie：对齐 Windows CookieType.Cookie = CookieToken | LToken = account_id+cookie_token+ltuid+ltoken。
   *  注意：account_id 与 cookie_token 必须同组携带，缺失 account_id 时米哈游返回 10001 Please login。 */
  gameRecordCookie(): string {
    const pairs: string[] = [];
    if (this.accountId.length > 0) {
      pairs.push(`account_id=${this.accountId}`);
    }
    if (this.cookieToken.length > 0) {
      pairs.push(`cookie_token=${this.cookieToken}`);
    }
    if (this.ltuid.length > 0) {
      pairs.push(`ltuid=${this.ltuid}`);
    }
    if (this.ltoken.length > 0) {
      pairs.push(`ltoken=${this.ltoken}`);
    }
    if (pairs.length === 0) {
      return '';
    }
    return pairs.join('; ');
  }

  /** SToken 类接口所需 Cookie：stoken=..; stuid=..; mid=..（v2 键存在时优先用 v2 键名；v1 兜底） */
  stokenCookie(): string {
    let s: string = '';
    // 优先使用 v2 键名（2023+ 后 stoken_v2 体系），Windows 参考实现仅 v1 键需在持久化阶段处理，
    // 此处防御式兼容：若来源是 v2（stoken_v2/stuid_v2），交换接口更认 v2 键名
    if (this.stuidV2.length > 0 && this.stokenV2.length > 0) {
      s += `stoken_v2=${this.stokenV2}; stuid_v2=${this.stuidV2}`;
    } else if (this.stoken.length > 0) {
      s += `stoken=${this.stoken}; stuid=${this.stuid}`;
    }
    if (this.mid.length > 0) {
      if (s.length > 0) {
        s += '; ';
      }
      s += `mid=${this.mid}`;
    }
    return s;
  }

  /** 完整 Cookie 串（五件套全量，用于 TokenVault 落库/再解析） */
  fullCookie(): string {
    const pairs: string[] = [];
    if (this.accountId.length > 0) {
      pairs.push(`account_id=${this.accountId}`);
    }
    if (this.cookieToken.length > 0) {
      pairs.push(`cookie_token=${this.cookieToken}`);
    }
    if (this.ltuid.length > 0) {
      pairs.push(`ltuid=${this.ltuid}`);
    }
    if (this.ltoken.length > 0) {
      pairs.push(`ltoken=${this.ltoken}`);
    }
    if (this.stuid.length > 0) {
      pairs.push(`stuid=${this.stuid}`);
    }
    if (this.stoken.length > 0) {
      pairs.push(`stoken=${this.stoken}`);
    }
    if (this.mid.length > 0) {
      pairs.push(`mid=${this.mid}`);
    }
    // v2 原始键值（保留原键名以便重启后 applyCookie 仍能恢复 v2 链路）
    if (this.stuidV2.length > 0) {
      pairs.push(`stuid_v2=${this.stuidV2}`);
    }
    if (this.stokenV2.length > 0) {
      pairs.push(`stoken_v2=${this.stokenV2}`);
    }
    return pairs.join('; ');
  }

  /** 从 Cookie 字符串解析五件套并填充（返回是否解析到关键字段） */
  applyCookie(raw: string): boolean {
    const parts: string[] = raw.split(';');
    const map: Record<string, string> = {};
    for (let i = 0; i < parts.length; i++) {
      const seg: string = parts[i].trim();
      const idx: number = seg.indexOf('=');
      if (idx <= 0) {
        continue;
      }
      const key: string = seg.substring(0, idx).trim();
      let val: string = seg.substring(idx + 1).trim();
      map[key] = val;
    }
    const get = (k: string): string => {
      const v: string = map[k];
      return v === undefined ? '' : v;
    };
    // 优先 v2，其次 v1
    this.accountId = get('account_id').length > 0 ? get('account_id') : get('account_mid_v2');
    this.cookieToken = get('cookie_token').length > 0 ? get('cookie_token') : get('cookie_token_v2');
    this.ltuid = get('ltuid').length > 0 ? get('ltuid') : get('ltmid_v2');
    this.ltoken = get('ltoken').length > 0 ? get('ltoken') : get('ltoken_v2');
    this.stuid = get('stuid').length > 0 ? get('stuid') : get('stuid_v2');
    this.stoken = get('stoken').length > 0 ? get('stoken') : get('stoken_v2');
    // v2 原始键值单独保存（交换接口/某些域可能需要原键名）
    this.stuidV2 = get('stuid_v2');
    this.stokenV2 = get('stoken_v2');
    this.mid = get('mid').length > 0 ? get('mid') : get('mid');
    const stuidRaw: string = get('stuid_v2');
    if (this.stuid.length === 0 && stuidRaw.length > 0) {
      this.stuid = stuidRaw;
    }
    const has: boolean = (this.accountId.length > 0 || this.stuid.length > 0) && this.stoken.length > 0;
    return has;
  }

  /** 由 Cookie 字符串构造 User（用于 WebView/manual 登录） */
  static fromCookie(raw: string, mid: string, aid: string): User {
    const u: User = new User();
    u.applyCookie(raw);
    if (u.mid.length === 0) {
      u.mid = mid;
    }
    u.aid = aid;
    return u;
  }

  /** 拷贝自身（避免引用共享） */
  clone(): User {
    const u: User = new User();
    u.id = this.id;
    u.mid = this.mid;
    u.aid = this.aid;
    u.accountId = this.accountId;
    u.cookieToken = this.cookieToken;
    u.ltuid = this.ltuid;
    u.ltoken = this.ltoken;
    u.stuid = this.stuid;
    u.stoken = this.stoken;
    u.displayName = this.displayName;
    u.avatar = this.avatar;
    u.isSelected = this.isSelected;
    u.createdAt = this.createdAt;
    u.roles = this.roles.slice();
    return u;
  }
}
