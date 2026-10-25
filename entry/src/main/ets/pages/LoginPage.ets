/**
 * LoginPage.ets（@Entry）
 * 米游社 / HoYoLAB 登录：内置 WebView 网页登录 / 扫码登录 / 手机验证码登录 / 手动粘贴 Cookie。
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
import { NavIcon } from '../components/NavIcon';
import { PageBackdrop } from '../components/PageBackdrop';

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
  @State isOversea: boolean = false;
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
    const domains: string[] = this.isOversea ? [
      'https://www.hoyolab.com/', 'https://hoyolab.com/',
      'https://account.hoyoverse.com/', 'https://api-account-os.hoyoverse.com/',
    ] : [
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
      const u: User = UserService.getInstance().parseCookie(rawCookie, this.isOversea);
      if (!UserService.validateCookie(u)) {
        this.statusText = 'Cookie 不完整，请重新登录或检查复制的 Cookie';
        this.toast('Cookie 缺少关键字段（stoken/stuid/account_id）');
        this.busy = false;
        return;
      }
      this.statusText = '登录中：补齐 Token 并同步角色...';
      const user: User = await UserService.getInstance().loginWithCookie(rawCookie, '', '', this.isOversea);
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
      NavIcon({ name: 'Close', iconSize: 20, symbolColor: $r('app.color.text_secondary') })
        .accessibilityText('关闭登录页')
        .accessibilityLevel('yes')
        .onClick(() => {
          this.shouldStopQr = true;
          router.back();
        })
      Blank()
      Text(this.isOversea ? 'HoYoLAB 账号登录' : '米游社账号登录')
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text('关闭')
        .fontSize(15)
        .fontColor($r('app.color.app_primary_text'))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('关闭登录页')
        .onClick(() => {
          this.shouldStopQr = true;
          router.back();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topAvoidVp + 8, bottom: 8 })
  }

  /** 品牌区（对齐 Windows 启动器登录入口的观感：居中 Logo + 标题 + 副标） */
  @Builder
  brandHeader() {
    Column({ space: 8 }) {
      Image($r('app.media.startIcon'))
        .width(72)
        .height(72)
        .borderRadius(18)
        .shadow({ radius: 12, color: $r('app.color.nav_border'), offsetY: 4 })
      Text('登录胡桃账号服务')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(this.isOversea
        ? '使用 HoYoLAB 账号同步便笺、祈愿与战绩'
        : '使用米游社账号同步便笺、祈愿与战绩')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 18, bottom: 14 })
  }

  /** 账号地区切换（胶囊二选一，对齐 Windows 登录窗口的地区选择） */
  @Builder
  regionToggle() {
    Row({ space: 0 }) {
      Text('国服 · 米游社')
        .fontSize(12)
        .fontColor(!this.isOversea ? $r('app.color.app_primary_text') : $r('app.color.text_secondary'))
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .backgroundColor(!this.isOversea ? $r('app.color.app_primary_bg') : Color.Transparent)
        .borderRadius({ topLeft: 16, bottomLeft: 16 })
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('切换为国服米游社')
        .onClick(() => {
          if (this.isOversea && !this.busy) {
            this.shouldStopQr = true;
            this.qrRunning = false;
            this.isOversea = false;
            this.cookieInput = '';
            this.statusText = '';
            this.mode = LoginMode.Manual;
          }
        })
      Text('国际服 · HoYoLAB')
        .fontSize(12)
        .fontColor(this.isOversea ? $r('app.color.app_primary_text') : $r('app.color.text_secondary'))
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .backgroundColor(this.isOversea ? $r('app.color.app_primary_bg') : Color.Transparent)
        .borderRadius({ topRight: 16, bottomRight: 16 })
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('切换为国际服 HoYoLAB')
        .onClick(() => {
          if (!this.isOversea && !this.busy) {
            this.shouldStopQr = true;
            this.qrRunning = false;
            this.isOversea = true;
            this.cookieInput = '';
            this.statusText = '';
            this.mode = LoginMode.Manual;
          }
        })
    }
    .borderRadius(16)
    .backgroundColor($r('app.color.card_inner_tint'))
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  /** 登录方式分段器（对齐 Windows 对话框式登录入口的页签形态） */
  @Builder
  modeTabs() {
    Row() {
      this.modeTab('网页登录', LoginMode.Web)
      if (!this.isOversea) {
        this.modeTab('扫码登录', LoginMode.Qr)
        this.modeTab('手机验证码', LoginMode.MobileCaptcha)
      }
      this.modeTab('Cookie 导入', LoginMode.Manual)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
    .padding({ top: 8, bottom: 8 })
    .backgroundColor($r('app.color.card_surface'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  modeTab(label: string, target: LoginMode) {
    Column() {
      Text(label)
        .fontSize(13)
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
    .padding({ left: 6, right: 6 })
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText(`切换到${label}`)
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
            .width(210)
            .height(210)
            .color(Color.Black)
            .backgroundColor(Color.White)
          Image($r('app.media.startIcon'))
            .width(42)
            .height(42)
            .borderRadius(8)
            .margin({ top: 84 })
        }
        .width(234)
        .height(234)
        .borderRadius(14)
        .backgroundColor(Color.White)
        .shadow({ radius: 10, color: $r('app.color.nav_border'), offsetY: 2 })
      }
      Text(this.qrHint)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
      Button('刷新二维码')
        .fontSize(13)
        .height(36)
        .backgroundColor($r('app.color.app_primary_bg'))
        .fontColor($r('app.color.app_primary_text'))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('刷新登录二维码')
        .onClick(() => {
          this.refreshQr();
        })
      Text('打开米游社 App「扫一扫」，扫码并在手机上确认登录')
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
          .backgroundColor($r('app.color.card_inner_tint'))
          .onChange((value: string) => {
            this.mobileInput = value;
          })
        Button(this.countdown > 0 ? `${this.countdown}s` : '获取验证码')
          .fontSize(13)
          .height(36)
          .backgroundColor($r('app.color.app_primary_bg'))
          .fontColor($r('app.color.app_primary_text'))
          .hoverEffect(HoverEffect.Highlight)
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
        .backgroundColor($r('app.color.card_inner_tint'))
        .onChange((value: string) => {
          this.captchaInput = value;
        })

      QTapButton({ label: '登录', capsule: true, primary: true, disabled: this.busy, onTap: () => {
        this.submitCaptcha();
      } })
        .height(42)
      Text('手机验证码登录需要已绑定米游社 App 手机号；触发人机验证时会弹出统一验证窗')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  manualPanel() {
    Column({ space: 10 }) {
      Text('粘贴完整 Cookie（含 account_id / cookie_token / ltoken / stoken 等字段）')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextArea({ placeholder: '粘贴形如 account_id=..; cookie_token=..; ltoken=..; ltuid=..; stoken=..; stuid=..; mid=.. 的 Cookie', text: this.cookieInput })
        .height(110)
        .fontSize(13)
        .backgroundColor($r('app.color.card_inner_tint'))
        .onChange((value: string) => {
          this.cookieInput = value;
        })
      QTapButton({ label: '解析并登录', capsule: true, primary: true, onTap: () => {
        this.doLogin(this.cookieInput);
      } })
        .height(42)
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  webPanel(contentHeight: string) {
    Column({ space: 10 }) {
      Web({ src: this.isOversea ? 'https://www.hoyolab.com/' : AppConstants.LOGIN_URL, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .width('100%')
        .height(contentHeight)
        .borderRadius(12)
        .clip(true)
      QTapButton({ label: '已完成网页登录，读取登录状态', primary: true, disabled: this.busy, onTap: () => {
        this.doLogin(this.collectWebCookies());
      } })
        .height(42)
    }
    .width('100%')
  }

  build() {
    Stack() {
      PageBackdrop({ embedMode: false })
      Column() {
        this.headerBar()
        Scroll() {
          Column({ space: 12 }) {
            this.brandHeader()
            this.regionToggle()
            this.modeTabs()

            // 内容卡：各登录方式共享同一张卡片容器（对齐 Windows ContentDialog 卡面）
            Column({ space: 10 }) {
              if (this.mode === LoginMode.Web) {
                this.webPanel('320')
              } else if (this.mode === LoginMode.Qr) {
                this.qrPanel()
              } else if (this.mode === LoginMode.MobileCaptcha) {
                this.captchaPanel()
              } else {
                this.manualPanel()
              }
            }
            .width('100%')
            .padding({ left: 4, right: 4, top: 4, bottom: 14 })
            .borderRadius($r('app.float.card_radius'))
            .backgroundColor($r('app.color.card_surface'))
            .border({ width: 1, color: $r('app.color.card_stroke') })

            if (this.statusText.length > 0) {
              Text(this.statusText)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 16, right: 16 })
            }
            Text('凭据仅保存在本机设备，不会上传到任何第三方服务器')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .padding({ bottom: 16 })
          }
          .width('100%')
          .constraintSize({ maxWidth: 480 })
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .align(Alignment.Top)
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
