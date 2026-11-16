/** 米游社登录：网页、扫码、手机验证码与 Cookie 导入。 */
import { webview } from '@kit.ArkWeb';
import { AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';
import { LoginMode, LoginViewModel } from '../viewmodel/LoginViewModel';
import { QTapButton } from '../components/QTapButton';
import { NavIcon } from '../components/NavIcon';
import { PageBackdrop } from '../components/PageBackdrop';
import { AppButtonModifier, CardSurfaceModifier, UiSurface } from '../common/UiSurface';

const TAG: string = 'LoginPage';

@Entry
@Component
struct LoginPage {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  @State vm: LoginViewModel = new LoginViewModel();
  private controller: webview.WebviewController = new webview.WebviewController();
  private pageVisible: boolean = false;

  aboutToAppear(): void {
    this.vm.activate(() => { this.returnAfterLogin(); });
  }

  onPageShow(): void {
    this.pageVisible = true;
    if (this.vm.hasCompleted()) { this.returnAfterLogin(); }
  }

  onPageHide(): void {
    // 切到米游社扫码时保留请求；回来后才操作登录页自己的路由。
    this.pageVisible = false;
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.vm.deactivate();
  }

  private returnAfterLogin(): void {
    if (!this.pageVisible) { return; }
    this.toast('登录成功');
    this.getUIContext().getRouter().back();
  }

  onBackPress(): boolean {
    this.vm.deactivate();
    return false;
  }

  private close(): void {
    this.vm.deactivate();
    this.getUIContext().getRouter().back();
  }

  /** 从 WebView 读取域 Cookie 并合并 */
  collectWebCookies(): string {
    const parts: string[] = [];
    const domains: string[] = [
      'https://mihoyo.com/',
      'https://www.mihoyo.com/',
      'https://api-takumi.mihoyo.com/',
      'https://act.mihoyo.com/',
      'https://www.miyoushe.com/',
    ];
    for (let i: number = 0; i < domains.length; i++) {
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
    for (let i: number = 0; i < parts.length; i++) {
      const segs: string[] = parts[i].split(';');
      for (let j: number = 0; j < segs.length; j++) {
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

  // ================= UI =================

  toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ systemMaterial: UiSurface.dialogMaterial(), message: msg, duration: 2000 });
  }

  @Builder
  headerBar() {
    Row() {
      NavIcon({ name: 'Close', iconSize: 20, symbolColor: $r('app.color.text_secondary') })
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('关闭登录页')
        .accessibilityLevel('yes')
        .onClick(() => {
          this.close();
        })
      Blank()
      Text($r('app.string.page_title_login'))
        .fontSize($r('app.float.subtitle_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text($r('app.string.ui_exception_close'))
        .fontSize(15)
        .fontColor($r('app.color.app_primary_text'))
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityText('关闭登录页')
        .onClick(() => {
          this.close();
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
      Text('登录米游社账号')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('同步便笺、祈愿与战绩')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 18, bottom: 14 })
  }

  /** 登录方式分段器（对齐 Windows 对话框式登录入口的页签形态） */
  @Builder
  modeTabs() {
    Row() {
      this.modeTab('网页登录', LoginMode.Web)
      this.modeTab('扫码登录', LoginMode.Qr)
      this.modeTab('手机验证码', LoginMode.MobileCaptcha)
      this.modeTab('Cookie 导入', LoginMode.Manual)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
    .padding({ top: 8, bottom: 8 })
    .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_stroke') })
  }

  @Builder
  modeTab(label: string, target: LoginMode) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(this.vm.mode === target ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.vm.mode === target ? $r('app.color.app_primary') : $r('app.color.text_secondary'))
      if (this.vm.mode === target) {
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
    .enabled(!this.vm.busy)
    .accessibilityText(`切换到${label}`)
    .onClick(() => {
      this.vm.selectMode(target);
    })
  }

  @Builder
  qrPanel() {
    Column({ space: 14 }) {
      if (this.vm.qrUrl.length === 0) {
        if (this.vm.qrRunning) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('app.color.app_primary'))
        }
      } else {
        Stack({ alignContent: Alignment.Top }) {
          QRCode(this.vm.qrUrl)
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
      Text(this.vm.qrHint)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
      Button('刷新二维码')
        .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
        .constraintSize({ minHeight: 44 })
        .enabled(!this.vm.busy)
        .accessibilityText('刷新登录二维码')
        .onClick(() => {
          this.vm.refreshQr();
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
        TextInput({ placeholder: '请输入手机号', text: this.vm.mobileInput })
          .type(InputType.PhoneNumber)
          .maxLength(11)
          .enabled(!this.vm.busy)
          .layoutWeight(1)
          .fontSize(15)
          .backgroundColor($r('app.color.card_inner_tint'))
          .onChange((value: string) => {
            this.vm.updateMobile(value);
          })
        Button(this.vm.countdown > 0 ? `${this.vm.countdown}s` : $r('app.string.ui_hutao_passport_verify_code_action'))
          .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel))
          .constraintSize({ minHeight: 44 })
          .enabled(this.vm.countdown === 0 && !this.vm.busy)
          .onClick(() => {
            this.vm.sendCaptcha();
          })
      }
      .width('100%')

      TextInput({ placeholder: '请输入 6 位验证码', text: this.vm.captchaInput })
        .type(InputType.Number)
        .maxLength(6)
        .enabled(!this.vm.busy)
        .width('100%')
        .fontSize(15)
        .backgroundColor($r('app.color.card_inner_tint'))
        .enterKeyType(EnterKeyType.Done)
        .onChange((value: string) => {
          this.vm.captchaInput = value;
        })
        .onSubmit(() => {
          this.vm.submitCaptcha();
        })

      QTapButton({ label: $r('app.string.page_title_login'), primary: true, disabled: this.vm.busy, onTap: () => {
        this.vm.submitCaptcha();
      } })
        .height(44)
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
      Text('粘贴包含 stoken 和 stuid（或 account_id）的完整 Cookie；也可使用扫码或手机验证码登录')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      TextArea({ placeholder: '粘贴形如 account_id=..; cookie_token=..; ltoken=..; ltuid=..; stoken=..; stuid=..; mid=.. 的 Cookie', text: this.vm.cookieInput })
        .height(110)
        .enabled(!this.vm.busy)
        .fontSize(13)
        .backgroundColor($r('app.color.card_inner_tint'))
        .onChange((value: string) => {
          this.vm.cookieInput = value;
        })
      QTapButton({ label: $r('app.string.page_title_login'), primary: true, disabled: this.vm.busy, onTap: () => {
        this.vm.loginWithCookie(this.vm.cookieInput);
      } })
        .height(44)
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  webPanel(contentHeight: string) {
    Column({ space: 10 }) {
      Web({ src: AppConstants.LOGIN_URL, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .width('100%')
        .height(contentHeight)
        .borderRadius(12)
        .clip(true)
      QTapButton({ label: '已完成网页登录，读取登录状态', primary: true, disabled: this.vm.busy, onTap: () => {
        this.vm.loginWithCookie(this.collectWebCookies());
      } })
        .height(44)
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
            this.modeTabs()

            // 内容卡：各登录方式共享同一张卡片容器（对齐 Windows ContentDialog 卡面）
            Column({ space: 10 }) {
              if (this.vm.mode === LoginMode.Web) {
                this.webPanel('320')
              } else if (this.vm.mode === LoginMode.Qr) {
                this.qrPanel()
              } else if (this.vm.mode === LoginMode.MobileCaptcha) {
                this.captchaPanel()
              } else {
                this.manualPanel()
              }
            }
            .width('100%')
            .padding({ left: 4, right: 4, top: 4, bottom: 14 })
            .borderRadius($r('app.float.card_radius'))
            .attributeModifier(new CardSurfaceModifier(this.surfaceMode, this.surfaceLevel))
            .border({ width: 1, color: $r('app.color.card_stroke') })

            if (this.vm.statusText.length > 0) {
              Text(this.vm.statusText)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
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
