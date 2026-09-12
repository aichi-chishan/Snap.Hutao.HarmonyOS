/**
 * Constants.ets
 * 全局常量：版本号、DS 盐值、x-rpc 请求头、已知返回码、国服域名与端点。
 * 仅国服(CN)，全部为本文件集中维护，失效时提示升级。
 */

export class AppConstants {
  /** 上报给米哈游的客户端版本号（x-rpc-app_version，对齐 Windows CNVersion；过旧易风控） */
  static readonly APP_VERSION: string = '1.21.0';
  /** 战绩类接口（便笺/角色/深渊/日历/签到）客户端类型：5 = 桌面（对齐 Windows XRpc） */
  static readonly GAMERECORD_CLIENT_TYPE: string = '5';
  /** 客户端类型：2 = android（仅 passport/登录链路用） */
  static readonly X_RPC_CLIENT_TYPE: string = '2';
  /** 语言 */
  static readonly X_RPC_LANGUAGE: string = 'zh-cn';
  /** 战绩类接口 UA（对齐 Windows 桌面 miHoYoBBS；与 client_type=5 自洽，避免移动 UA+桌面 type 自相矛盾触发风控） */
  static readonly UA_GAMERECORD: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1';
  /** User-Agent（WebView 登录页面使用） */
  static readonly UA_MOBILE: string =
    'Mozilla/5.0 (Linux; Android 12; PEEM00 Build/SKQ1.211006.001) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Mobile Safari/537.36 miHoYoBBS/2.95.1';
  /** 米游社 BBS 客户端 UA（passport/登录链路用，对齐参考项目 HoyolabOptions.UserAgent：桌面 miHoYoBBS + CNVersion） */
  static readonly UA_BBS: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) miHoYoBBS/2.95.1';
  /** BBS 移动端 UA（WebView 登录/移动端接口，对齐 MobileUserAgent） */
  static readonly UA_MOBILE_BBS: string =
    'Mozilla/5.0 (Linux; Android 15) Mobile miHoYoBBS/2.95.1';
  /** passport 系接口 app_id / client_type */
  static readonly PASSPORT_APP_ID: string = 'bll8iq97cem8';
  static readonly PASSPORT_CLIENT_TYPE: string = '2';
  static readonly PASSPORT_GAME_BIZ: string = 'bbs_cn';
  static readonly PASSPORT_SDK_VERSION: string = '2.16.0';

  /** DS Gen2 盐值（便笺/日历等战绩接口） */
  static readonly DS_SALT_X4: string = 'xV8v4Qu54lUKrEYFZkJhB8cuOh9Asafs';
  /** DS Gen1 盐值（genAuthKey/actionTicket 等接口） */
  static readonly DS_SALT_K2: string = 'sfYPEgpxkOe1I3XVMLdwp1Lyt9ORgZsq';
  /** DS Gen1 盐值（签到 luna 接口） */
  static readonly DS_SALT_LK2: string = 'sidQFEglajEz7FA0Aj7HQPV88zpf17SO';
  /** DS Gen2 盐值（passport 账号系：验证码登录/Token 交换） */
  static readonly DS_SALT_PROD: string = 'JwYDpKvLj6MrMqqYU6jTKF17KNO2PXoS';

  /** 扫码登录（HoyoPlay 协议，非 BBS） */
  static readonly HYP_USER_AGENT: string = 'HYPContainer/1.1.4.133';
  static readonly HYP_APP_ID: string = 'ddxf5dufpuyo';
  static readonly HYP_CLIENT_TYPE: string = '3';
  /** BBS 账号系 app_id（护照/验证码接口） */
  static readonly BBS_APP_ID: string = 'bll8iq97cem8';

  /** 扫码登录端点 */
  static readonly URL_CREATE_QR_LOGIN: string =
    'https://passport-api.mihoyo.com/account/ma-cn-passport/app/createQRLogin';
  static readonly URL_QUERY_QR_STATUS: string =
    'https://passport-api.mihoyo.com/account/ma-cn-passport/app/queryQRLoginStatus';
  /** 手机验证码端点（国服） */
  static readonly URL_CREATE_LOGIN_CAPTCHA: string =
    'https://passport-api.mihoyo.com/account/ma-cn-verifier/verifier/createLoginCaptcha';
  static readonly URL_LOGIN_BY_MOBILE_CAPTCHA: string =
    'https://passport-api.mihoyo.com/account/ma-cn-passport/app/loginByMobileCaptcha';

  /** 签到活动 ID / 登录落地活动 */
  static readonly SIGN_ACT_ID: string = 'e202311201442471';
  /** 网页登录落地页（米游社原神签到页） */
  static readonly LOGIN_URL: string =
    'https://act.mihoyo.com/bbs/event/signin/hk4e/index.html?act_id=e202311201442471';
  /** 祈愿 auth_appid */
  static readonly GACHA_AUTH_APPID: string = 'webview_gacha';
  /** 游戏 biz */
  static readonly GAME_BIZ: string = 'hk4e_cn';

  /** 各 Cookie 域名（读取 WebView Cookie 用） */
  static readonly COOKIE_DOMAIN_MIHOYO: string = 'mihoyo.com';
  static readonly COOKIE_DOMAIN_MIYOUSHE: string = 'miyoushe.com';
  static readonly COOKIE_DOMAIN_TAKUMI: string = 'api-takumi.mihoyo.com';

  /** 祈愿分页单页条数 */
  static readonly GACHA_PAGE_SIZE: number = 20;
  /** 祈愿分页间防封随机延时上下限（毫秒） */
  static readonly GACHA_DELAY_MIN: number = 1000;
  static readonly GACHA_DELAY_MAX: number = 2000;
  /** authkey 有效期约 24 小时，预留 1 小时阈值 */
  static readonly AUTHKEY_VALID_MS: number = 23 * 60 * 60 * 1000;
  /** 网络超时（毫秒） */
  static readonly NETWORK_TIMEOUT_MS: number = 10000;
}

/** 已知返回码 */
export class RetCodes {
  static readonly OK: number = 0;
  /** Cookie 失效 / 未登录 */
  static readonly COOKIE_EXPIRED: number = -100;
  /** 需要登录（部分接口 10001） */
  static readonly NOT_LOGGED_IN: number = 10001;
  /** 风控 / 验证码拦截 */
  static readonly RISK_CONTROL: number = 1034;
  /** 已签到 */
  static readonly ALREADY_SIGNED: number = -5003;
  /** 未开始（luna 签到活动未开启） */
  static readonly NOT_STARTED: number = -5002;
  /** 每日已签到次数超额（luna） */
  static readonly DAILY_LIMIT: number = -5004;
  /** 实时便笺：当前账号存在风险，暂无数据 */
  static readonly ACCOUNT_RISK: number = 5003;
  /** 实时便笺：账号已被限制/封禁 */
  static readonly NOTE_BANNED: number = 10103;
}

/** 服务器区域工具：仅国服 */
export class RegionUtil {
  /** 根据 UID 首位推断服务器：5 开头为 bilibili(cn_qd01)，其余为官方(cn_gf01) */
  static regionOfUid(uid: string): string {
    if (uid.length > 0 && uid.charAt(0) === '5') {
      return 'cn_qd01';
    }
    return 'cn_gf01';
  }

  /** 判断是否国服 UID（仅允许 1-9 开头，简单校验） */
  static isCnUid(uid: string): boolean {
    if (uid.length === 0) {
      return false;
    }
    const first: string = uid.charAt(0);
    return first >= '1' && first <= '9';
  }
}
