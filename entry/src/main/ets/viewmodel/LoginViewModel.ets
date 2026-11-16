/** 登录页状态：每次二维码/提交只接受所属请求的结果，离页即停止。 */
import { UserService } from '../service/UserService';
import { User } from '../model/User';
import { QrLogin, QrLoginResult, LoginSession, MobileCaptcha } from '../data/network/PassportClient';

export enum LoginMode {
  Web,
  Qr,
  MobileCaptcha,
  Manual
}

@Observed
export class LoginViewModel {
  mode: LoginMode = LoginMode.Qr;
  busy: boolean = false;
  statusText: string = '';
  qrUrl: string = '';
  qrHint: string = '正在获取二维码...';
  qrRunning: boolean = false;
  mobileInput: string = '';
  captchaInput: string = '';
  cookieInput: string = '';
  countdown: number = 0;

  private active: boolean = false;
  private generation: number = 0;
  private qrTimer: number = -1;
  private countdownTimer: number = -1;
  private countdownEndsAt: number = 0;
  private captchaMobile: string = '';
  private actionType: string = '';
  private loginRevision: number = -1;
  private completed: boolean = false;
  private onLogin: (() => void) | undefined = undefined;

  hasCompleted(): boolean { return this.completed; }

  activate(onLogin: () => void): void {
    if (this.active) { return; }
    this.active = true;
    this.generation++;
    this.onLogin = onLogin;
    this.busy = false;
    this.completed = false;
    this.qrRunning = false;
    this.startCountdown();
    if (this.mode === LoginMode.Qr) { this.refreshQr(); }
  }

  /** Called from aboutToDisappear: invalidate work and clear timers without changing rendered state. */
  deactivate(): void {
    this.active = false;
    this.generation++;
    this.onLogin = undefined;
    this.clearQrTimer();
    this.clearCountdownTimer();
    if (this.loginRevision >= 0) {
      UserService.getInstance().cancelPendingLogin(this.loginRevision);
      this.loginRevision = -1;
    }
  }

  selectMode(mode: LoginMode): void {
    if (!this.active || this.busy || this.completed || this.mode === mode) { return; }
    this.generation++;
    this.clearQrTimer();
    this.qrRunning = false;
    this.statusText = '';
    this.mode = mode;
    if (mode === LoginMode.Qr) { this.refreshQr(); }
  }

  private isCurrent(generation: number): boolean {
    return this.active && this.generation === generation;
  }

  private clearQrTimer(): void {
    if (this.qrTimer >= 0) { clearTimeout(this.qrTimer); this.qrTimer = -1; }
  }

  async refreshQr(): Promise<void> {
    if (!this.active || this.mode !== LoginMode.Qr || this.busy || this.completed) { return; }
    const generation: number = ++this.generation;
    this.clearQrTimer();
    this.qrRunning = true;
    this.qrUrl = '';
    this.statusText = '';
    this.qrHint = '正在获取二维码...';
    try {
      const qr: QrLogin = await UserService.getInstance().createQrLogin();
      if (!this.isCurrent(generation)) { return; }
      this.qrUrl = qr.url;
      this.qrHint = '请使用米游社 App 扫码登录';
      this.scheduleQrPoll(qr.ticket, generation);
    } catch (e) {
      if (!this.isCurrent(generation)) { return; }
      this.qrHint = (e as Error).message;
      this.qrRunning = false;
    }
  }

  private scheduleQrPoll(ticket: string, generation: number): void {
    this.qrTimer = setTimeout(() => {
      this.qrTimer = -1;
      this.pollQr(ticket, generation);
    }, 3000);
  }

  private async pollQr(ticket: string, generation: number): Promise<void> {
    if (!this.isCurrent(generation)) { return; }
    try {
      const result: QrLoginResult = await UserService.getInstance().queryQrLoginStatus(ticket);
      if (!this.isCurrent(generation)) { return; }
      if (result.status === 'Expired') {
        await this.refreshQr();
        return;
      }
      if (result.status === 'Confirmed') {
        this.qrRunning = false;
        this.busy = true;
        this.qrHint = '已确认，登录中...';
        await this.finishLogin(UserService.getInstance().loginWithQrResult(result), generation);
        return;
      }
      this.qrHint = result.status === 'Scanned'
        ? '已扫码，等待在手机上确认...' : '请使用米游社 App 扫码登录';
    } catch (e) {
      if (!this.isCurrent(generation)) { return; }
      this.qrHint = (e as Error).message;
      if (!this.qrRunning) { this.statusText = '登录失败：' + (e as Error).message; }
      this.busy = false;
    }
    if (this.isCurrent(generation) && this.qrRunning) { this.scheduleQrPoll(ticket, generation); }
  }

  updateMobile(mobile: string): void {
    if (this.busy) { return; }
    this.mobileInput = mobile;
    if (mobile.trim() !== this.captchaMobile) {
      this.actionType = '';
      this.captchaInput = '';
    }
  }

  async sendCaptcha(): Promise<void> {
    if (!this.active || this.mode !== LoginMode.MobileCaptcha || this.busy || this.completed || this.countdown > 0) { return; }
    const mobile: string = this.mobileInput.trim();
    if (!/^\d{11}$/.test(mobile)) {
      this.statusText = '请输入 11 位手机号';
      return;
    }
    const generation: number = ++this.generation;
    this.busy = true;
    this.statusText = '正在发送验证码...';
    try {
      const captcha: MobileCaptcha = await UserService.getInstance()
        .createLoginCaptcha(mobile, (): boolean => this.isCurrent(generation));
      if (!this.isCurrent(generation)) { return; }
      this.captchaMobile = mobile;
      this.actionType = captcha.actionType;
      this.countdownEndsAt = Date.now() + (captcha.countdown > 0 ? captcha.countdown : 60) * 1000;
      this.startCountdown();
      this.statusText = '验证码已发送，请查收短信';
    } catch (e) {
      if (this.isCurrent(generation)) { this.statusText = (e as Error).message; }
    } finally {
      if (this.isCurrent(generation)) { this.busy = false; }
    }
  }

  private clearCountdownTimer(): void {
    if (this.countdownTimer >= 0) { clearInterval(this.countdownTimer); this.countdownTimer = -1; }
  }

  private startCountdown(): void {
    this.clearCountdownTimer();
    this.updateCountdown();
    if (this.countdown > 0) {
      this.countdownTimer = setInterval(() => { this.updateCountdown(); }, 1000);
    }
  }

  private updateCountdown(): void {
    this.countdown = Math.max(0, Math.ceil((this.countdownEndsAt - Date.now()) / 1000));
    if (this.countdown === 0) { this.clearCountdownTimer(); }
  }

  async submitCaptcha(): Promise<void> {
    if (!this.active || this.mode !== LoginMode.MobileCaptcha || this.busy || this.completed) { return; }
    const mobile: string = this.mobileInput.trim();
    const captcha: string = this.captchaInput.trim();
    if (!/^\d{11}$/.test(mobile)) { this.statusText = '请输入 11 位手机号'; return; }
    if (captcha.length === 0) { this.statusText = '请输入验证码'; return; }
    if (this.actionType.length === 0 || this.captchaMobile !== mobile) {
      this.statusText = '请先为当前手机号获取验证码';
      return;
    }
    const generation: number = ++this.generation;
    this.busy = true;
    this.statusText = '正在登录...';
    try {
      const session: LoginSession = await UserService.getInstance()
        .requestMobileLogin(mobile, captcha, this.actionType, (): boolean => this.isCurrent(generation));
      if (!this.isCurrent(generation)) { return; }
      await this.finishLogin(UserService.getInstance().loginWithSession(
        session.stuid, session.stoken, session.mid, session.accountName), generation);
    } catch (e) {
      if (this.isCurrent(generation)) { this.statusText = '登录失败：' + (e as Error).message; }
    } finally {
      if (this.isCurrent(generation)) { this.busy = false; }
    }
  }

  async loginWithCookie(cookie: string): Promise<void> {
    if (!this.active || this.busy || this.completed) { return; }
    if (cookie.trim().length === 0) { this.statusText = '未读取到 Cookie，请先完成网页登录或粘贴 Cookie'; return; }
    const generation: number = ++this.generation;
    this.clearQrTimer();
    this.qrRunning = false;
    this.busy = true;
    try {
      await this.finishLogin(UserService.getInstance().loginWithCookie(cookie, '', ''), generation);
    } catch (e) {
      if (this.isCurrent(generation)) { this.statusText = '登录失败：' + (e as Error).message; }
    } finally {
      if (this.isCurrent(generation)) { this.busy = false; }
    }
  }

  private async finishLogin(pending: Promise<User>, generation: number): Promise<void> {
    const revision: number = UserService.getInstance().sessionRevision();
    this.loginRevision = revision;
    this.statusText = '登录中：补齐 Token 并同步角色...';
    try {
      const user: User = await pending;
      if (!this.isCurrent(generation)) { return; }
      this.completed = true;
      this.busy = false;
      this.statusText = `登录成功：${user.displayName || '账号'}`;
      const onLogin: (() => void) | undefined = this.onLogin;
      if (onLogin !== undefined) { onLogin(); }
    } finally {
      if (this.loginRevision === revision) { this.loginRevision = -1; }
    }
  }
}
