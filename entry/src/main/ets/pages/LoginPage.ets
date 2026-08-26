/**
 * LoginPage.ets（@Entry）
 * 米游社登录（仅国服）：内置 WebView 网页登录 / 扫码登录 / 手机验证码登录 / 手动粘贴 Cookie。
 */
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppConstants } from '../common/Constants';
import { UserService } from '../service/UserService';
import { User } from '../model/User';
import { PassportClient, QrLogin, QrLoginResult, LoginSession, MobileCaptcha } from '../data/network/PassportClient';
import { RetCodes } from '../common/Constants';
import { Logger } from '../common/Logger';
import { QTapButton } from '../components/QTapButton';

const TAG: string = 'LoginPage';

/** 登录方式 */
enum LoginMode {
  Web,
  Qr,
  MobileCaptcha,
  Manual
}

@Entry
@Component
struct LoginPage {
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  @State mode: LoginMode = LoginMode.Qr;
  @State busy: boolean = false;
  @State statusText: string = '';

  // 扫码登录状态
  @State qrUrl: string = '';
  @State qrHint: string = '等待扫码...';
  @State qrRunning: boolean = false;

  // 手机验证码状态
  @State mobileInput: string = '';
  @State captchaInput: string = '';
  @State actionType: string = '';
  @State countdown: number = 0;

  // 手动 Cookie
  @State cookieInput: string = '';

  private qrTicket: string = '';
  private shouldStopQr: boolean = false;

  aboutToDisappear(): void {
    this.shouldStopQr = true;
  }

  // ================= 扫码登录 =================

  async startQr(): Promise<void> {
    if (this.qrRunning) {
      return;
    }
    this.shouldStopQr = false;
    this.qrRunning = true;
    this.qrHint = '正在获取二维码...';
    try {
      const qr: QrLogin = await PassportClient.createQrLogin();
      this.qrUrl = qr.url;
      this.qrTicket = qr.ticket;
      this.qrHint = '请使用米游社 App 扫码登录';
      this.beginQrPolling();
    } catch (e) {
      this.qrHint = (e as Error).message;
      this.qrRunning = false;
    }
  }

  async beginQrPolling(): Promise<void> {
    while (!this.shouldStopQr) {
      await new Promise<void>((resolve) => {
        setTimeout(() => {
          resolve();
        }, 3000);
      });
      if (this.shouldStopQr) {
        break;
      }
      try {
        const result: QrLoginResult = await PassportClient.queryQrLoginStatus(this.qrTicket);
        if (result.status === 'Confirmed') {
          this.qrHint = '已确认，登录中...';
          const session: LoginSession = PassportClient.extractQrSession(result);
          this.shouldStopQr = true;
          await this.completeLoginBySession(session);
          return;
        }
        this.qrHint = '已扫码，等待在手机上确认...';
      } catch (e) {
        const err: Error = e as Error;
        // 二维码过期（-3501）自动刷新
        if (err.message.includes('-3501') || err.message.includes('过期')) {
          this.qrRunning = false;
          await this.startQr();
          return;
        }
        // 其他错误短暂等待继续轮询
        this.qrHint = err.message;
        await new Promise<void>((resolve) => {
          setTimeout(() => {
            resolve();
          }, 1500);
        });
      }
    }
    this.qrRunning = false;
  }

  async refreshQr(): Promise<void> {
    this.shouldStopQr = true;
    this.qrRunning = false;
    this.qrUrl = '';
    this.qrTicket = '';
    await this.startQr();
  }

  // ================= 手机验证码登录 =================

  async sendCaptcha(): Promise<void> {
    const mobile: string = this.mobileInput.trim();
    if (mobile.length !== 11) {
      this.toast('请输入 11 位手机号');
      return;
    }
    if (this.busy || this.countdown > 0) {
      return;
    }
    this.busy = true;
    this.statusText = '正在发送验证码...';
    try {
      const captcha: MobileCaptcha = await PassportClient.createLoginCaptcha(mobile);
      this.actionType = captcha.actionType;
      if (captcha.countdown > 0) {
        this.countdown = captcha.countdown;
      } else {
        this.countdown = 60;
      }
      this.statusText = '验证码已发送，请查收短信';
      this.toast('验证码已发送');
      this.startCountdown();
    } catch (e) {
      this.statusText = (e as Error).message;
      this.toast((e as Error).message);
    } finally {
      this.busy = false;
    }
  }

  startCountdown(): void {
    const timer = setInterval(() => {
      if (this.countdown <= 1) {
        this.countdown = 0;
        clearInterval(timer);
      } else {
        this.countdown -= 1;
      }
    }, 1000);
  }

  async submitCaptcha(): Promise<void> {
    const mobile: string = this.mobileInput.trim();
    const captcha: string = this.captchaInput.trim();
    if (mobile.length !== 11) {
      this.toast('请输入 11 位手机号');
      return;
    }
    if (captcha.length === 0) {
      this.toast('请输入验证码');
      return;
    }
    if (this.actionType.length === 0) {
      this.toast('请先获取验证码');
      return;
    }
    this.busy = true;
    this.statusText = '正在登录...';
    try {
      const session: LoginSession = await PassportClient.loginByMobileCaptcha(mobile, captcha, this.actionType);
      this.statusText = '登录成功，同步账号信息...';
      await this.completeLoginBySession(session);
    } catch (e) {
      this.statusText = '登录失败：' + (e as Error).message;
      this.toast('登录失败');
    } finally {
      this.busy = false;
    }
  }

  // ================= 通用：完成登录 =================

  async completeLoginBySession(session: LoginSession): Promise<void> {
    try {
      this.statusText = '登录中：补齐 Token 并同步角色...';
      const user: User = await UserService.getInstance().loginWithSession(
        session.stuid, session.stoken, session.mid, session.accountName);
      this.statusText = `登录成功：${user.displayName.length > 0 ? user.displayName : '账号'}`;
      Logger.info(TAG, `login success user=${user.id}`);
      this.toast('登录成功');
      setTimeout(() => {
        router.back();
      }, 600);
    } catch (e) {
      this.statusText = '登录失败：' + (e as Error).message;
      this.toast('登录失败');
    }
  }

  // ================= WebView 登录 =================

  /** 从 WebView 读取域 Cookie 并合并 */
  collectWebCookies(): string {
    let parts: string[] = [];
    const domains: string[] = [
      'https://mihoyo.com/',
      'https://www.mihoyo.com/',
      'https://api-takumi.mihoyo.com/',
      'https://act.mihoyo.com/',
      'https://www.miyoushe.com/',
    ];
    for (let i = 0; i < domains.length; i++) {
      try {
        const ck: string = webview.WebCookieManager.fetchCookieSync(domains[i]);
        if (ck.length > 0) {
          parts.push(ck);
        }
      } catch (e) {
        Logger.warn(TAG, `read cookie fail for ${domains[i]}`);
      }
    }
    const merged: Record<string, string> = {};
    for (let i = 0; i < parts.length; i++) {
      const segs: string[] = parts[i].split(';');
      for (let j = 0; j < segs.length; j++) {
        const pair: string = segs[j].trim();
        const idx: number = pair.indexOf('=');
        if (idx <= 0) {
          continue;
        }
        const key: string = pair.substring(0, idx).trim();
        const val: string = pair.substring(idx + 1).trim();
        if (key.length > 0 && merged[key] === undefined) {
          merged[key] = val;
        }
      }
    }
    const out: string[] = [];
    for (const k of Object.keys(merged)) {
      out.push(`${k}=${merged[k]}`);
    }
    return out.join('; ');
  }

  async doLogin(rawCookie: string): Promise<void> {
    if (rawCookie.trim().length === 0) {
      this.toast('未读取到 Cookie，请先完成网页登录');
      return;
    }
    this.busy = true;
    this.statusText = '校验 Cookie 中...';
    try {
      const u: User = UserService.getInstance().parseCookie(rawCookie);
      if (!UserService.validateCookie(u)) {
        this.statusText = 'Cookie 不完整，请重新登录或检查复制的 Cookie';
        this.toast('Cookie 缺少关键字段（stoken/stuid/account_id）');
        this.busy = false;
        return;
      }
      this.statusText = '登录中：补齐 Token 并同步角色...';
      const user: User = await UserService.getInstance().loginWithCookie(rawCookie, '', '');
      this.statusText = `登录成功：${user.displayName.length > 0 ? user.displayName : '账号'}`;
      Logger.info(TAG, `login success user=${user.id}`);
      this.toast('登录成功');
      setTimeout(() => {
        router.back();
      }, 600);
    } catch (e) {
      this.statusText = '登录失败：' + (e as Error).message;
      this.toast('登录失败');
    } finally {
      this.busy = false;
    }
  }

  // ================= UI =================

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  @Builder
  headerBar() {
    Row() {
      Text('✕')
        .fontSize(20)
        .fontColor($r('app.color.text_secondary'))
        .onClick(() => {
          this.shouldStopQr = true;
          router.back();
        })
      Blank()
      Text('米游社登录')
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text('关闭')
        .fontSize(15)
        .fontColor($r('app.color.app_primary'))
        .onClick(() => {
          this.shouldStopQr = true;
          router.back();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topAvoidVp + 8, bottom: 8 })
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  modeTabs() {
    Row() {
      this.modeTab('网页', LoginMode.Web)
      this.modeTab('扫码', LoginMode.Qr)
      this.modeTab('验证码', LoginMode.MobileCaptcha)
      this.modeTab('手动', LoginMode.Manual)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
    .padding({ top: 8, bottom: 8 })
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  modeTab(label: string, target: LoginMode) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(this.mode === target ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.mode === target ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      if (this.mode === target) {
        Divider()
          .color($r('app.color.app_primary'))
          .strokeWidth(2)
          .width('60%')
          .margin({ top: 4 })
      } else {
        Blank()
          .height(6)
      }
    }
    .onClick(() => {
      this.shouldStopQr = true;
      this.mode = target;
      if (target === LoginMode.Qr) {
        this.qrRunning = false;
        this.qrUrl = '';
        this.startQr();
      }
    })
  }

  @Builder
  qrPanel() {
    Column({ space: 14 }) {
      if (this.qrUrl.length === 0) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color($r('app.color.app_primary'))
      } else {
        Stack({ alignContent: Alignment.Top }) {
          QRCode(this.qrUrl)
            .width(200)
            .height(200)
            .color(Color.Black)
            .backgroundColor(Color.White)
          Image($r('app.media.startIcon'))
            .width(40)
            .height(40)
            .borderRadius(6)
            .margin({ top: 80 })
        }
        .width(220)
        .height(220)
        .borderRadius(12)
        .backgroundColor(Color.White)
      }
      Text(this.qrHint)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
      Button('刷新二维码')
        .fontSize(13)
        .height(34)
        .backgroundColor($r('app.color.app_primary_bg'))
        .fontColor($r('app.color.app_primary'))
        .onClick(() => {
          this.refreshQr();
        })
      Text('使用米游社 App「扫一扫」完成登录')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(20)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  captchaPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('+86')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        TextInput({ placeholder: '请输入手机号', text: this.mobileInput })
          .type(InputType.PhoneNumber)
          .maxLength(11)
          .layoutWeight(1)
          .fontSize(15)
          .onChange((value: string) => {
            this.mobileInput = value;
          })
        Button(this.countdown > 0 ? `${this.countdown}s` : '获取验证码')
          .fontSize(13)
          .height(34)
          .backgroundColor($r('app.color.app_primary_bg'))
          .fontColor($r('app.color.app_primary'))
          .enabled(this.countdown === 0 && !this.busy)
          .onClick(() => {
            this.sendCaptcha();
          })
      }
      .width('100%')

      TextInput({ placeholder: '请输入 6 位验证码', text: this.captchaInput })
        .type(InputType.Number)
        .maxLength(6)
        .width('100%')
        .fontSize(15)
        .onChange((value: string) => {
          this.captchaInput = value;
        })

      QTapButton({ label: '登录', capsule: true, primary: true, disabled: this.busy, onTap: () => {
        this.submitCaptcha();
      } })
        .height(40)
      Text('手机验证码登录需要已绑定米游社 App 手机号')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(14)
  }

  @Builder
  manualPanel() {
    Column({ space: 10 }) {
      Text('手动粘贴完整 Cookie（五件套格式）')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextArea({ placeholder: '粘贴形如 account_id=..; cookie_token=..; ltoken=..; ltuid=..; stoken=..; stuid=..; mid=.. 的 Cookie', text: this.cookieInput })
        .height(110)
        .fontSize(13)
        .onChange((value: string) => {
          this.cookieInput = value;
        })
      QTapButton({ label: '解析并登录', capsule: true, primary: true, onTap: () => {
        this.doLogin(this.cookieInput);
      } })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  webPanel(contentHeight: string) {
    Column() {
      Web({ src: AppConstants.LOGIN_URL, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .width('100%')
        .height(contentHeight)
    }
  }

  build() {
    Column() {
      this.headerBar()
      this.modeTabs()
      Scroll() {
        Column() {
          if (this.mode === LoginMode.Web) {
            this.webPanel('300')
          } else if (this.mode === LoginMode.Qr) {
            this.qrPanel()
          } else if (this.mode === LoginMode.MobileCaptcha) {
            this.captchaPanel()
          } else {
            this.manualPanel()
          }
          Text(this.statusText)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 16, right: 16, top: 8 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
