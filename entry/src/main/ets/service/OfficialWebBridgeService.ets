import { url } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { AppConstants } from '../common/Constants';
import { PreferencesStore } from '../data/prefs/PreferencesStore';
import { ApiClient } from '../data/network/ApiClient';
import { DsSigner } from '../data/network/DsSigner';
import { HoyolabClient } from '../data/network/HoyolabClient';
import { ApiResponse } from '../model/ApiResponse';
import { User } from '../model/User';
import { AppLocaleService } from './AppLocaleService';
import { ChallengeSession } from './ChallengeSession';
import { UserService } from './UserService';

export enum OfficialWebKind {
  Toolbox = 'toolbox',
  DailyNote = 'daily-note',
  SignIn = 'sign-in',
}

export class OfficialWebShareRequest {
  type: string = '';
  imageUrl: string = '';
  imageBase64: string = '';
}

export interface OfficialWebActions {
  closePage(): void;
  openPage(target: string): void;
  share(request: OfficialWebShareRequest): Promise<boolean>;
}

export class OfficialWebCallback {
  name: string;
  result: string;
  constructor(name: string, result: string) { this.name = name; this.result = result; }
}

class OfficialWebResult {
  retcode: number;
  message: string;
  data: Object | null;
  constructor(retcode: number, message: string, data: Object | null) {
    this.retcode = retcode; this.message = message; this.data = data;
  }
}

export class OfficialWebBridgeService {
  static readonly PROXY: string = 'hutaoOfficialWeb';
  static readonly SCRIPT: string = `if (window.top === window) {
    window.MiHoYoJSInterface = {
      postMessage: function(value) {
        hutaoOfficialWeb.postMessage(typeof value === 'string' ? value : JSON.stringify(value));
      },
      closePage: function() { this.postMessage('{"method":"closePage"}'); }
    };
  }`;
  static readonly PERMISSION: string = '{"javascriptProxyPermission":{"urlPermissionList":[' +
    '{"scheme":"https","host":"webstatic.mihoyo.com","port":"443","path":"bbs/event/e20200511toolbox"},' +
    '{"scheme":"https","host":"webstatic.mihoyo.com","port":"443","path":"app/community-game-records"},' +
    '{"scheme":"https","host":"act.mihoyo.com","port":"443","path":"bbs/event/signin/hk4e"}]}}';
  private static readonly MAX_MESSAGE: number = 16 * 1024 * 1024;
  readonly owner: ChallengeSession;
  readonly kind: OfficialWebKind;
  private messages: Promise<void> = Promise.resolve();

  constructor(kind: OfficialWebKind, uid: string) {
    this.kind = kind;
    this.owner = ChallengeSession.require(uid);
  }

  title(): string {
    if (this.kind === OfficialWebKind.Toolbox) { return '旅行工具'; }
    return this.kind === OfficialWebKind.DailyNote ? '验证当前用户与角色' : '米游社官方签到';
  }

  source(): string {
    if (this.kind === OfficialWebKind.Toolbox) {
      return 'https://webstatic.mihoyo.com/bbs/event/e20200511toolbox/index.html?game_biz=ys_cn';
    }
    if (this.kind === OfficialWebKind.DailyNote) {
      return 'https://webstatic.mihoyo.com/app/community-game-records/index.html?bbs_presentation_style=fullscreen#/ys/daily/' +
        `?role_id=${this.owner.uid}&server=${this.owner.region}`;
    }
    return 'https://act.mihoyo.com/bbs/event/signin/hk4e/index.html?act_id=e202311201442471';
  }

  private static https(value: string): url.URL | undefined {
    try {
      const parsed: url.URL = url.URL.parseURL(value);
      if (parsed.protocol === 'https:' && parsed.username.length === 0 && parsed.password.length === 0 &&
        (parsed.port === '' || parsed.port === '443')) { return parsed; }
    } catch (e) { /* Invalid URL. */ }
    return undefined;
  }

  static allowsPage(value: string): boolean {
    const target: url.URL | undefined = OfficialWebBridgeService.https(value);
    if (target === undefined) { return false; }
    if (target.hostname === 'webstatic.mihoyo.com') {
      return target.pathname.startsWith('/bbs/event/e20200511toolbox/') ||
        target.pathname.startsWith('/app/community-game-records/');
    }
    return target.hostname === 'act.mihoyo.com' && target.pathname.startsWith('/bbs/event/signin/hk4e/');
  }

  static allowsImage(value: string): boolean {
    const target: url.URL | undefined = OfficialWebBridgeService.https(value);
    return target !== undefined && (target.hostname.endsWith('.mihoyo.com') || target.hostname.endsWith('.miyoushe.com'));
  }

  static navigationTarget(value: string): string {
    const wrapper: string = 'mihoyobbs://webview?link=';
    let target: string = value;
    if (value.startsWith(wrapper)) {
      try { target = decodeURIComponent(value.substring(wrapper.length)); } catch (e) { return ''; }
    }
    if (value.startsWith('mihoyobbs://article/')) {
      const id: string = value.substring('mihoyobbs://article/'.length);
      if (/^\d+$/.test(id)) { return `https://m.miyoushe.com/ys/#/article/${id}`; }
    }
    const parsed: url.URL | undefined = OfficialWebBridgeService.https(target);
    if (parsed === undefined) { return ''; }
    if (OfficialWebBridgeService.allowsPage(parsed.href) ||
      (parsed.hostname === 'm.miyoushe.com' && parsed.pathname === '/ys/' && parsed.hash.startsWith('#/article/'))) {
      return parsed.href;
    }
    return '';
  }

  async prepare(active: () => boolean): Promise<void> {
    const user: User = this.owner.user;
    if (user.cookieToken.length === 0 || user.ltoken.length === 0) {
      await UserService.getInstance().refreshCookieTokenForced(user, (): Promise<boolean> => Promise.resolve(active()));
    }
    this.configureCookies(active);
  }

  private configureCookies(active: () => boolean): void {
    if (!active() || !this.owner.isCurrent()) { throw new Error('账号或角色已切换'); }
    const user: User = this.owner.user;
    const cookies: Record<string, string> = {
      'account_id': user.accountId, 'cookie_token': user.cookieToken, 'ltuid': user.ltuid, 'ltoken': user.ltoken,
      'account_id_v2': user.accountIdV2, 'account_mid_v2': user.accountMidV2, 'cookie_token_v2': user.cookieTokenV2,
      'ltuid_v2': user.ltuidV2, 'ltmid_v2': user.ltmidV2, 'ltoken_v2': user.ltokenV2,
    };
    for (const name of Object.keys(cookies)) {
      const value: string = cookies[name];
      if (/^[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]+$/.test(value)) {
        webview.WebCookieManager.configCookieSync(this.source(), `${name}=${value}; Domain=.mihoyo.com; Path=/; Secure; HttpOnly`, true, true);
      }
    }
  }

  receive(raw: string, actions: OfficialWebActions, active: () => boolean): Promise<OfficialWebCallback | undefined> {
    const pending: Promise<OfficialWebCallback | undefined> = this.messages.then(() => this.receiveCurrent(raw, actions, active));
    this.messages = pending.then(() => {}, () => {});
    return pending;
  }

  private async receiveCurrent(raw: string, actions: OfficialWebActions,
    active: () => boolean): Promise<OfficialWebCallback | undefined> {
    if (!active() || !this.owner.isCurrent() || raw.length > OfficialWebBridgeService.MAX_MESSAGE) { return undefined; }
    let message: Record<string, Object>;
    try { message = OfficialWebBridgeService.record(JSON.parse(raw)); } catch (e) { return undefined; }
    const method: string = OfficialWebBridgeService.text(message['method']);
    const callback: string = OfficialWebBridgeService.text(message['callback']);
    const payload: Record<string, Object> = OfficialWebBridgeService.record(message['payload']);
    let result: OfficialWebResult | undefined;
    try { result = await this.dispatch(method, payload, actions, active); }
    catch (e) { result = new OfficialWebResult(-1, '操作未完成', null); }
    if (result === undefined || callback.length === 0 || callback.length > 128 || !active() || !this.owner.isCurrent()) {
      return undefined;
    }
    return new OfficialWebCallback(callback, JSON.stringify(result));
  }

  private async dispatch(method: string, payload: Record<string, Object>, actions: OfficialWebActions,
    active: () => boolean): Promise<OfficialWebResult | undefined> {
    const user: User = this.owner.user;
    switch (method) {
      case 'closePage': actions.closePage(); return undefined;
      case 'pushPage': {
        const target: string = OfficialWebBridgeService.navigationTarget(OfficialWebBridgeService.text(payload['page']));
        if (target.length > 0) { actions.openPage(target); }
        return undefined;
      }
      case 'getCookieInfo':
        return OfficialWebBridgeService.ok({ 'ltuid': user.ltuid || user.ltuidV2, 'ltoken': user.ltoken || user.ltokenV2, 'login_ticket': '' });
      case 'getCookieToken':
        if (payload['forceRefresh'] === true) {
          await UserService.getInstance().refreshCookieTokenForced(user, (): Promise<boolean> => Promise.resolve(active()));
        }
        this.configureCookies(active);
        return OfficialWebBridgeService.ok({ 'cookie_token': user.cookieToken || user.cookieTokenV2 });
      case 'getCurrentLocale': {
        const offset: number = -new Date().getTimezoneOffset() / 60;
        const locale: string = AppLocaleService.current();
        const language: string = locale === 'zh-Hans' ? 'zh-cn' : locale === 'zh-Hant' ? 'zh-tw' : locale.toLowerCase();
        return OfficialWebBridgeService.ok({ 'language': language, 'timeZone': `GMT${offset >= 0 ? '+' : ''}${offset}` });
      }
      case 'getStatusBarHeight': return OfficialWebBridgeService.ok({ 'statusBarHeight': 0 });
      case 'getHTTPRequestHeaders': return OfficialWebBridgeService.ok(this.requestHeaders());
      case 'getDS': {
        const ds: string = await DsSigner.signGen1(AppConstants.DS_SALT_LK2, DsSigner.nowTimestamp(), DsSigner.randomLowerAlphaNumeric());
        return OfficialWebBridgeService.ok({ 'DS': ds });
      }
      case 'getDS2': {
        const query: Record<string, Object> = OfficialWebBridgeService.record(payload['query']);
        const sorted: string = Object.keys(query).sort().map((key: string): string => JSON.stringify(query[key])).join('&');
        const ds: string = await DsSigner.signGen2(AppConstants.DS_SALT_X4, DsSigner.nowTimestamp(), DsSigner.randomNumber(),
          OfficialWebBridgeService.text(payload['body']), sorted);
        return OfficialWebBridgeService.ok({ 'DS': ds });
      }
      case 'getUserInfo': return this.userInfo();
      case 'getActionTicket': return this.actionTicket(OfficialWebBridgeService.text(payload['action_type']));
      case 'share': {
        const share: OfficialWebShareRequest = new OfficialWebShareRequest();
        const content: Record<string, Object> = OfficialWebBridgeService.record(payload['content']);
        share.type = OfficialWebBridgeService.text(payload['type']);
        share.imageUrl = OfficialWebBridgeService.text(content['image_url']);
        share.imageBase64 = OfficialWebBridgeService.text(content['image_base64']);
        if (share.type !== 'image' && share.type !== 'screenshot') { return undefined; }
        return await actions.share(share) ? OfficialWebBridgeService.ok({ 'type': share.type })
          : new OfficialWebResult(-1, '分享未完成', null);
      }
      default: return undefined;
    }
  }

  private requestHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'x-rpc-app_id': AppConstants.PASSPORT_APP_ID,
      'x-rpc-client_type': this.kind === OfficialWebKind.SignIn ? AppConstants.PASSPORT_CLIENT_TYPE : AppConstants.GAMERECORD_CLIENT_TYPE,
      'x-rpc-device_id': PreferencesStore.getDeviceId(),
      'x-rpc-device_fp': PreferencesStore.getDeviceFp(),
      'x-rpc-app_version': AppConstants.APP_VERSION,
      'x-rpc-sdk_version': AppConstants.PASSPORT_SDK_VERSION,
    };
    return headers;
  }

  private async userInfo(): Promise<OfficialWebResult> {
    const user: User = this.owner.user;
    const id: string = user.aid || user.accountId || user.stuid || user.stuidV2;
    if (!/^\d+$/.test(id)) { return new OfficialWebResult(-1, '无法读取账号资料', null); }
    const response: ApiResponse = await ApiClient.getInstance().get(`https://bbs-api.mihoyo.com/user/wapi/getUserFullInfo?uid=${id}&gids=2`,
      { 'Cookie': user.stokenCookie(), 'Referer': 'https://bbs.mihoyo.com/' });
    const info: Record<string, Object> = OfficialWebBridgeService.record(OfficialWebBridgeService.record(response.data)['user_info']);
    return OfficialWebBridgeService.ok({ 'id': info['uid'] ?? id, 'gender': info['gender'] ?? 0,
      'nickname': info['nickname'] ?? user.displayName, 'introduce': info['introduce'] ?? '', 'avatar_url': info['avatar_url'] ?? user.avatar });
  }

  private async actionTicket(type: string): Promise<OfficialWebResult> {
    const user: User = this.owner.user;
    const token: string = user.stokenV2 || user.stoken;
    const id: string = user.stuidV2 || user.stuid || user.aid;
    if (!/^[a-zA-Z0-9_]{1,64}$/.test(type) || token.length === 0 || !/^\d+$/.test(id)) {
      return new OfficialWebResult(-1, '无法获取操作票据', null);
    }
    const response: ApiResponse = await HoyolabClient.getActionTicket(user.stokenCookie(), token, id, type);
    return new OfficialWebResult(response.retcode, response.success ? '' : '无法获取操作票据', response.data ?? null);
  }

  private static ok(data: Record<string, Object>): OfficialWebResult { return new OfficialWebResult(0, '', data); }

  private static record(value: Object | undefined): Record<string, Object> {
    return value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)
      ? value as Record<string, Object> : {};
  }

  private static text(value: Object | undefined): string { return typeof value === 'string' ? value : ''; }
}
