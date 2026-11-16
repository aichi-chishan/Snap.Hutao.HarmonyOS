/**
 * RiskVerifyModal.ets
 * 全局人机验证浮层（挂载于 EntryAbility OverlayManager，覆盖所有页面）：
 *   - game_record 1034 / 签到体内极验（kind='gt'）
 *   - passport 登录 aigis 会话（kind='aigis'）
 * 视觉：统一全局浮层材质、
 *       spring 弹性进出、蒙层渐显、状态呼吸点。结果回传 RiskVerifyService。
 *
 * ⚠ 踩坑记录：
 *   1) 真机（API 24 平板）弹窗出现但"验证图不出现"：WebviewController 未与 Web 组件绑定前
 *      调用 loadData 会抛 17100001（Init error），在 onAppear 里调用存在竞态 →
 *      必须放到 Web 的 onControllerAttached 回调里下发；
 *   2) 3 参 loadData 生成 data: 文档（不透明源），脚本/接口易被跨源策略拦截 →
 *      改用 5 参 loadData 并给 baseUrl/historyUrl（真实 https 源）；
 *   3) 验证图被裁切：极验点选验证码约 344×300 CSS px，固定 340vp 的 WebView 装不下 →
 *      面板/WebView 由窗口尺寸自适应（本文件），页面内再按实际验证码尺寸等比缩放到视口
 *      （HTML 里的 fit()，通过 onFrame 桥回传测量结果）。
 */
import { AppButtonModifier, UiSurface, OverlaySurfaceModifier } from '../common/UiSurface';
import { webview } from '@kit.ArkWeb';
import { curves } from '@kit.ArkUI';
import { RiskVerifyService, RiskVerifyRequest, KEY_RISK_SHOW, KEY_RISK_REQ } from '../service/RiskVerifyService';
import { Logger } from '../common/Logger';
import { NavIcon } from './NavIcon';

const TAG: string = 'RiskVerifyModal';

/** 极验脚本所在域：同时作为 Web 文档的 baseUrl/historyUrl（给页面一个真实 https 源） */
const GEETEST_BASE_URL: string = 'https://static.geetest.com/';
const GEETEST_BRIDGE_PERMISSION: string = '{"javascriptProxyPermission":{"urlPermissionList":' +
  '[{"scheme":"https","host":"static.geetest.com","port":"443","path":""}]}}';
/** 面板留白：左右各 12vp；上下留给标题行+状态行+内边距 */
const PANEL_EDGE: number = 24;
const PANEL_CHROME_H: number = 140;
/** 极验点选验证码的典型占位（CSS px ≈ vp）：宽 344，点选版较高（含头部/底部说明约 420） */
const CAPTCHA_W: number = 344;
const CAPTCHA_H: number = 420;

/** 全局浮层构建入口（EntryAbility 挂载 OverlayManager 用） */
@Builder
export function buildRiskVerifyOverlay() {
  RiskVerifyModal()
}

/** 极验 JS 桥：接收网页回传的验证结果 + 页面侧诊断日志 + 验证码实际尺寸 */
class VerifyJsProxy {
  private resultSink: (json: string) => void = () => {
  };
  private logSink: (msg: string) => void = () => {
  };
  private frameSink: (json: string) => void = () => {
  };

  constructor(result: (json: string) => void, log: (msg: string) => void, frame: (json: string) => void) {
    this.resultSink = result;
    this.logSink = log;
    this.frameSink = frame;
  }

  onValidate(json: string): void {
    this.resultSink(json);
  }

  /** 页面诊断（脚本是否加载 / 是否初始化 / JS 异常） */
  onLog(msg: string): void {
    this.logSink(msg);
  }

  /** 验证码实际尺寸回传（{w,h,scale}），用于面板自适应与日志 */
  onFrame(json: string): void {
    this.frameSink(json);
  }
}

@Component
export struct RiskVerifyModal {
  @StorageProp('materialMode') surfaceMode: number = 0;
  @StorageProp('materialLevel') surfaceLevel: number = -1;
  @StorageProp('reduceMotion') reduceMotion: boolean = false;
  @StorageLink(KEY_RISK_SHOW) @Watch('onVerifyStateChanged') isShow: boolean = false;
  @StorageLink(KEY_RISK_REQ) @Watch('onVerifyStateChanged') req: RiskVerifyRequest = new RiskVerifyRequest();
  @State statusText: string = '';
  /** 加载失败：展示「重新加载」而不是留一块空白 */
  @State loadFailed: boolean = false;
  /** 浮层可用区域（vp）：面板/WebView 据此自适应，避免验证图被裁切 */
  @State availW: number = 0;
  @State availH: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private proxy: VerifyJsProxy = new VerifyJsProxy(
    (json: string): void => {
      this.handleValidate(json);
    },
    (msg: string): void => {
      Logger.info(TAG, `page: ${msg}`);
    },
    (json: string): void => {
      this.handleFrame(json);
    });
  private currentMaterial(): OverlaySurfaceModifier {
    return new OverlaySurfaceModifier(this.surfaceMode, this.surfaceLevel);
  }
  /** Web 组件是否已绑定控制器（未绑定前调用 loadData 会抛 17100001） */
  private webAttached: boolean = false;
  /** 待加载的验证参数（Web 未就绪时先缓存，onControllerAttached 后补发） */
  private gt: string = '';
  private challenge: string = '';
  /** 已成功回传验证结果（避免 onError 二次覆盖） */
  private solved: boolean = false;
  private loadedSequence: number = 0;

  aboutToAppear(): void {
    this.onVerifyStateChanged();
  }

  private onVerifyStateChanged(): void {
    if (!this.isShow || this.req.seq <= 0 || this.req.seq === this.loadedSequence) { return; }
    if (this.loadedSequence > 0) { this.controller = new webview.WebviewController(); }
    this.webAttached = false;
    this.loadedSequence = this.req.seq;
    this.loadCaptcha(this.req.gt, this.req.challenge);
  }

  private ownsRequest(seq: number): boolean { return this.isShow && seq === this.loadedSequence; }

  /** 面板宽度：至少容纳验证码宽度 + 内边距，且不超过可用宽度（小窗自动收窄，页面再等比缩放适配） */
  private panelWidth(): number {
    const need: number = CAPTCHA_W + 42;
    if (this.availW <= 0) {
      return need;
    }
    return Math.max(0, Math.min(480, this.availW - PANEL_EDGE));
  }

  /** WebView 高度：验证区尽量给足（页面透明，多出的空间不可见），只在窗口不够时才收缩 */
  private webHeight(): number {
    if (this.availH <= 0) {
      return CAPTCHA_H + 20;
    }
    return Math.max(260, Math.min(CAPTCHA_H + 40, this.availH - PANEL_CHROME_H));
  }

  /** 验证码尺寸回传：仅记录（缩放已在页面内完成） */
  private handleFrame(json: string): void {
    Logger.info(TAG, `captcha frame ${json}`);
  }

  /** 缓存参数并尝试下发（Web 未就绪时等 onControllerAttached） */
  private loadCaptcha(gt: string, challenge: string): void {
    this.gt = gt;
    this.challenge = challenge;
    this.solved = false;
    this.loadFailed = false;
    if (gt.length === 0 || challenge.length === 0) {
      this.loadFailed = true;
      this.statusText = '验证参数缺失，请关闭后重试';
      return;
    }
    this.statusText = '正在加载验证组件...';
    if (this.webAttached) {
      this.startLoad();
    }
  }

  /** 真正下发到 WebView：仅在控制器已绑定后调用 */
  private startLoad(): void {
    if (this.gt.length === 0 || this.challenge.length === 0) {
      return;
    }
    try {
      this.controller.registerJavaScriptProxy(this.proxy, 'hutaoVerifyBridge',
        ['onValidate', 'onLog', 'onFrame'], [], GEETEST_BRIDGE_PERMISSION);
    } catch (e) {
      Logger.warn(TAG, `register proxy fail ${(e as Error).message}`);
    }
    try {
      // 5 参重载：baseUrl/historyUrl 给出真实 https 源（3 参会退化成 data: 文档，脚本易被拦）
      this.controller.loadData(this.buildHtml(this.gt, this.challenge), 'text/html', 'UTF-8',
        GEETEST_BASE_URL, GEETEST_BASE_URL);
      Logger.info(TAG, `loadData issued gt=${this.gt.length} challenge=${this.challenge.length}`);
    } catch (e) {
      const msg: string = (e as Error).message;
      Logger.error(TAG, `loadData fail ${msg}`);
      this.loadFailed = true;
      this.statusText = `验证组件加载失败：${msg}`;
    }
  }

  /** 处理网页回传：提取 geetest_validate 回传服务层 */
  private handleValidate(json: string): void {
    try {
      const obj = JSON.parse(json) as Record<string, Object>;
      if (!this.isShow || this.solved || Number(obj['request_seq']) !== this.loadedSequence) { return; }
      if (obj['ready'] === true) { this.statusText = '请完成下方人机验证'; return; }
      const err: Object = obj['error'];
      if (err !== undefined && err !== null && String(err).length > 0) {
        this.loadFailed = true;
        this.statusText = '验证组件初始化失败，请点「重新加载」或检查网络';
        return;
      }
      const validate: string = String(obj['geetest_validate'] ?? obj['validate'] ?? '');
      if (validate.length === 0) {
        this.statusText = '验证失败，请重试';
        return;
      }
      this.solved = true;
      this.statusText = '验证成功，正在继续...';
      const challenge: string = String(obj['geetest_challenge'] ?? obj['challenge'] ?? this.challenge);
      RiskVerifyService.getInstance().submitValidate(validate, challenge, this.loadedSequence);
    } catch (e) {
      Logger.warn(TAG, `handleValidate fail: ${(e as Error).message}`);
      this.statusText = '验证处理失败，请重试';
    }
  }

  /** 重新加载验证组件（参数不变，重新走一遍下发） */
  private retry(): void {
    if (this.gt.length === 0 || this.challenge.length === 0) {
      this.statusText = '验证参数缺失，请关闭后重试';
      return;
    }
    this.loadFailed = false;
    this.statusText = '正在重新加载验证组件...';
    this.startLoad();
  }

  private buildHtml(gt: string, challenge: string): string {
    const gtJson: string = JSON.stringify(gt).replace(/</g, '\\u003c');
    const challengeJson: string = JSON.stringify(challenge).replace(/</g, '\\u003c');
    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<style>
  html,body{margin:0;padding:0;height:100%;background:transparent;overflow:hidden;}
  #captcha{margin-top:12px;display:flex;justify-content:center;}
</style>
</head>
<body>
<div id="captcha"></div>
<script>
  function deliver(result) {
    if (!result || !window.hutaoVerifyBridge) { return; }
    result.request_seq = ${this.loadedSequence};
    window.hutaoVerifyBridge.onValidate(JSON.stringify(result));
  }
  // 页面侧诊断回传（脚本加载/初始化/JS 异常都能在宿主状态栏看到，便于真机排查）
  function log(msg) {
    try { if (window.hutaoVerifyBridge && window.hutaoVerifyBridge.onLog) { window.hutaoVerifyBridge.onLog(String(msg)); } } catch (e) {}
  }
  window.onerror = function (msg, src, line) {
    log('JS异常: ' + msg + ' @' + (src || '') + ':' + (line || 0));
    return false;
  };
  log('页面已加载 origin=' + window.location.origin);

  /** 汇总极验自有节点（class 以 gt_ 开头）的可见包围盒 —— 即验证码真实占位。
   *  跳过铺满视口的遮罩/容器（否则永远量到视口尺寸，缩放失效）。 */
  function measure() {
    var vw = window.innerWidth, vh = window.innerHeight;
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    var nodes = document.querySelectorAll('[class^="gt_"],[class*=" gt_"]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var st = window.getComputedStyle(el);
      if (!st || st.display === 'none' || st.visibility === 'hidden' || parseFloat(st.opacity) === 0) continue;
      var r = el.getBoundingClientRect();
      if (r.width < 2 || r.height < 2) continue;
      if (Math.abs(r.width - vw) < 4 && Math.abs(r.height - vh) < 4 &&
          Math.abs(r.left) < 4 && Math.abs(r.top) < 4) continue; // 全屏遮罩层，不能排除超出视口的验证码
      if (r.left < minX) minX = r.left;
      if (r.top < minY) minY = r.top;
      if (r.right > maxX) maxX = r.right;
      if (r.bottom > maxY) maxY = r.bottom;
    }
    if (maxX <= minX || maxY <= minY) return null;
    return { w: Math.ceil(maxX - Math.min(0, minX)), h: Math.ceil(maxY - Math.min(0, minY)) };
  }

  /** 验证码大于视口时等比缩小（zoom 会同步缩放命中区域，点击坐标仍然正确），
   *  再把实际尺寸回传宿主，便于其调整面板大小。 */
  function fit() {
    // 每次按原尺寸重算，窗口重新变宽时也能恢复到 1 倍。
    document.body.style.zoom = '1';
    var m = measure();
    if (!m) return;
    var vw = window.innerWidth, vh = window.innerHeight;
    var k = Math.min(1, (vw - 4) / m.w, (vh - 4) / m.h);
    document.body.style.zoom = String(Math.max(0.1, k));
    try {
      if (window.hutaoVerifyBridge && window.hutaoVerifyBridge.onFrame) {
        window.hutaoVerifyBridge.onFrame(JSON.stringify({ w: m.w, h: m.h, vw: vw, vh: vh }));
      }
    } catch (e) {}
  }

  var fitTimer = null;
  function scheduleFit() {
    if (fitTimer) clearTimeout(fitTimer);
    fitTimer = setTimeout(fit, 120);
  }
  // 极验插入 DOM 的过程是异步多步的：用 MutationObserver 持续跟随，尺寸稳定后自动收敛
  var mo = null;
  try {
    mo = new MutationObserver(function (records) {
      if (records.some(function (record) { return record.target !== document.body; })) scheduleFit();
    });
    mo.observe(document.body, { childList: true, subtree: true, attributes: true });
    // 验证码渲染完成后即可停止观察，避免长尾开销
    setTimeout(function () { try { mo.disconnect(); } catch (e) {} }, 20000);
  } catch (e) {}
  window.addEventListener('resize', scheduleFit);
  setTimeout(function () { fit(); }, 300);
  setTimeout(function () { fit(); }, 900);
  setTimeout(function () { fit(); }, 1800);
  setTimeout(function () { fit(); }, 3000);
<\/script>
<script src="https://static.geetest.com/static/js/gt.0.5.2.js"><\/script>
<script>
  if (typeof initGeetest !== 'function') {
    log('验证脚本未加载(initGeetest 未定义)');
    if (window.hutaoVerifyBridge && window.hutaoVerifyBridge.onValidate) {
      deliver({error: 'script_load_fail'});
    }
  } else {
    try {
      initGeetest({
        protocol: 'https://',
        gt: ${gtJson},
        challenge: ${challengeJson},
        new_captcha: true,
        product: 'bind',
        api_server: 'api.geetest.com'
      }, function (captchaObj) {
        captchaObj.onReady(function () {
          log('验证组件就绪');
          deliver({ready: true});
          captchaObj.verify();
          scheduleFit();
        });
        captchaObj.onSuccess(function () {
          var result = captchaObj.getValidate();
          if (window.hutaoVerifyBridge) {
            deliver(result);
          }
        });
        captchaObj.onError(function (err) {
          log('极验错误: ' + JSON.stringify(err));
          if (window.hutaoVerifyBridge) {
            deliver({error: 'init_fail'});
          }
        });
      });
    } catch (e) {
      log('initGeetest 调用异常: ' + e);
      if (window.hutaoVerifyBridge && window.hutaoVerifyBridge.onValidate) {
        deliver({error: 'init_exception'});
      }
    }
  }
<\/script>
</body>
</html>`;
  }

  private kindLabel(): string {
    if (this.req.kind === 'aigis') {
      return '登录安全验证';
    }
    return '数据访问验证';
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isShow && this.req.seq > 0) {
        ForEach([this.req], (activeReq: RiskVerifyRequest) => {
        // 蒙层（点击关闭 → 取消验证）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.mask_scrim'))
          .onClick(() => {
            RiskVerifyService.getInstance().cancel(activeReq.seq);
          })
          .transition(this.reduceMotion ? TransitionEffect.IDENTITY.animation({ duration: 0 }) :
            TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))

        Scroll() {
        Column() {
          // 标题行
          Row({ space: 8 }) {
            Text(this.kindLabel())
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Button({ type: ButtonType.Normal }) {
              NavIcon({ name: 'Close', iconSize: 16, symbolColor: $r('app.color.text_secondary') })
            }
              .width(44).height(44)
              .backgroundColor(Color.Transparent)
              .borderRadius(12)
              .accessibilityText('取消验证')
              .accessibilityLevel('yes')
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                RiskVerifyService.getInstance().cancel(activeReq.seq);
              })
          }
          .width('100%')

          // 说明 + 状态（呼吸点）
          Row({ space: 6 }) {
            Circle({ width: 6, height: 6 })
              .fill(this.loadFailed ? $r('app.color.danger') : $r('app.color.app_primary'))
              .opacity(this.reduceMotion || this.statusText.includes('请完成') ? 1 : 0.35)
              .animation({ duration: this.reduceMotion ? 0 : 700, curve: Curve.EaseInOut,
                iterations: this.reduceMotion ? 1 : -1, playMode: PlayMode.Alternate })
            Text(this.statusText.length > 0 ? this.statusText : '正在发起人机验证...')
              .fontSize(13)
              .fontColor(this.loadFailed ? $r('app.color.danger') : $r('app.color.text_secondary'))
              .layoutWeight(1)
            if (this.loadFailed) {
              Button('重新加载', { type: ButtonType.Normal })
                .attributeModifier(new AppButtonModifier(this.surfaceMode, this.surfaceLevel, true))
                .fontSize(12)
                .constraintSize({ minHeight: 44 })
                .onClick(() => {
                  if (this.ownsRequest(activeReq.seq)) { this.retry(); }
                })
            }
          }
          .width('100%')
          .margin({ top: 8 })

          // 极验 WebView（尺寸随窗口自适应，保证验证图完整显示）
          Column() {
            Web({ src: 'about:blank', controller: this.controller })
              .width('100%')
              .height(this.webHeight())
              .javaScriptAccess(true)
              .domStorageAccess(true)
              // 验证图/背景图属于在线图片资源，显式放行（默认即 true，防止被误关）
              .imageAccess(true)
              .onlineImageAccess(true)
              .backgroundColor(Color.Transparent)
              .onControllerAttached(() => {
                if (!this.ownsRequest(activeReq.seq)) { return; }
                // 控制器绑定完成才可安全调用 loadData（此前调用会抛 17100001 → 真机白屏）
                this.webAttached = true;
                Logger.info(TAG, 'controller attached, start load');
                this.startLoad();
              })
              .onDisAppear(() => { if (activeReq.seq === this.loadedSequence) { this.webAttached = false; } })
              .onErrorReceive((event: OnErrorReceiveEvent) => {
                if (!this.ownsRequest(activeReq.seq)) { return; }
                const url: string = event.request.getRequestUrl();
                const info: string = event.error.getErrorInfo();
                const mainFrame: boolean = event.request.isMainFrame();
                Logger.warn(TAG, `resource error main=${mainFrame} ${info} ${url}`);
                // 主文档或极验脚本失败才提示（图片等子资源失败不打扰用户）
                if (!this.solved && (mainFrame || url.indexOf('geetest') >= 0)) {
                  this.loadFailed = true;
                  this.statusText = `验证组件加载失败：${info}`;
                }
              })
              .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
                if (!this.ownsRequest(activeReq.seq)) { return; }
                const url: string = event.request.getRequestUrl();
                const code: number = event.response.getResponseCode();
                Logger.warn(TAG, `http error ${code} ${url}`);
                if (!this.solved && url.indexOf('geetest') >= 0) {
                  this.loadFailed = true;
                  this.statusText = `验证组件加载失败：HTTP ${code}`;
                }
              })
              .onConsole((event: OnConsoleEvent) => {
                Logger.info(TAG, `console: ${event.message.getMessage()}`);
                return false;
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width(this.panelWidth())
        .padding({ left: 18, right: 12, top: 16, bottom: 14 })
        .borderRadius(24)
        .attributeModifier(this.currentMaterial())
        .alignItems(HorizontalAlign.Start)
        .transition(this.reduceMotion ? TransitionEffect.IDENTITY.animation({ duration: 0 }) : TransitionEffect.asymmetric(
          // 进场：spring 弹性放大 + 上浮 + 渐显
          TransitionEffect.scale({ x: 0.92, y: 0.92 })
            .combine(TransitionEffect.translate({ y: 36 }))
            .combine(TransitionEffect.OPACITY)
            .animation({ curve: curves.springMotion(0.34, 0.86) }),
          // 出场：轻收 + 渐隐
          TransitionEffect.scale({ x: 0.94, y: 0.94 })
            .combine(TransitionEffect.OPACITY)
            .animation({ curve: curves.springMotion(0.34, 0.9) })
        ))
        }
        .width(this.panelWidth())
        .constraintSize({ maxHeight: this.availH > 0 ? Math.max(0, this.availH - PANEL_EDGE) : undefined })
        .scrollBar(BarState.Auto)
        }, (activeReq: RiskVerifyRequest): string => String(activeReq.seq))
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.isShow ? HitTestMode.Default : HitTestMode.None)
    // 隐藏态彻底脱离渲染树与命中测试（部分版本 OverlayManager 空内容仍参与命中）
    .visibility(this.isShow ? Visibility.Visible : Visibility.None)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      // 浮层即窗口：据此自适应面板宽度/验证区高度（平板/PC 大窗给足，手机小窗自动收窄）
      const w: number = newValue.width as number;
      const h: number = newValue.height as number;
      if (w > 0 && h > 0) {
        this.availW = w;
        this.availH = h;
      }
    })
  }
}
