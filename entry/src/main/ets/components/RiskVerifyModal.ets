/**
 * RiskVerifyModal.ets
 * 全局人机验证浮层（挂载于 EntryAbility OverlayManager，覆盖所有页面）：
 *   - game_record 1034 / 签到体内极验（kind='gt'）
 *   - passport 登录 aigis 会话（kind='aigis'）
 * 视觉：沉浸光感材质（API 26 门控 systemMaterial，低版本回退 backgroundEffect）、
 *       spring 弹性进出、蒙层渐显、状态呼吸点。结果回传 RiskVerifyService。
 */
import { webview } from '@kit.ArkWeb';
import { curves, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { RiskVerifyService, RiskVerifyRequest, KEY_RISK_SHOW, KEY_RISK_REQ } from '../service/RiskVerifyService';
import { Logger } from '../common/Logger';

const TAG: string = 'RiskVerifyModal';

/** 全局浮层构建入口（EntryAbility 挂载 OverlayManager 用） */
@Builder
export function buildRiskVerifyOverlay() {
  RiskVerifyModal()
}

/** 极验 JS 桥：接收网页回传的验证结果 */
class VerifyJsProxy {
  private onResult: (json: string) => void = () => {
  };

  constructor(cb: (json: string) => void) {
    this.onResult = cb;
  }

  onValidate(json: string): void {
    this.onResult(json);
  }
}

/** API 26 沉浸光感可用性（运行时门控） */
function immersiveAvailable(): boolean {
  try {
    return deviceInfo.apiAvailable('26.0.0');
  } catch (e) {
    return false;
  }
}

@Component
export struct RiskVerifyModal {
  @StorageLink(KEY_RISK_SHOW) isShow: boolean = false;
  @StorageLink(KEY_RISK_REQ) req: RiskVerifyRequest = new RiskVerifyRequest();
  @State statusText: string = '';
  @State panelVisible: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private proxy: VerifyJsProxy = new VerifyJsProxy((json: string) => {
    this.handleValidate(json);
  });
  private material: uiMaterial.Material | undefined = undefined;

  aboutToAppear(): void {
    if (immersiveAvailable()) {
      this.material = new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        applyShadow: true,
      });
    }
  }

  /** 弹出时加载极验页 */
  private loadCaptcha(gt: string, challenge: string): void {
    try {
      this.controller.registerJavaScriptProxy(this.proxy, 'hutaoVerifyBridge', ['onValidate']);
    } catch (e) {
      Logger.warn(TAG, `register proxy fail ${(e as Error).message}`);
    }
    this.controller.loadData(this.buildHtml(gt, challenge), 'text/html', 'UTF-8');
    this.statusText = '请完成下方人机验证';
  }

  /** 处理网页回传：提取 geetest_validate 回传服务层 */
  private handleValidate(json: string): void {
    try {
      const obj = JSON.parse(json) as Record<string, Object>;
      const validate: string = String(obj['geetest_validate'] ?? obj['validate'] ?? '');
      if (validate.length === 0) {
        this.statusText = '验证失败，请重试';
        return;
      }
      this.statusText = '验证成功，正在继续...';
      RiskVerifyService.getInstance().submitValidate(validate);
    } catch (e) {
      Logger.warn(TAG, `handleValidate fail: ${(e as Error).message}`);
      this.statusText = '验证处理失败，请重试';
    }
  }

  private buildHtml(gt: string, challenge: string): string {
    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<style>
  html,body{margin:0;padding:0;height:100%;background:transparent;}
  #captcha{margin-top:12px;display:flex;justify-content:center;}
</style>
</head>
<body>
<div id="captcha"></div>
<script src="https://static.geetest.com/static/js/gt.0.5.2.js"><\/script>
<script>
  initGeetest({
    protocol: 'https://',
    gt: '${gt}',
    challenge: '${challenge}',
    new_captcha: true,
    product: 'bind',
    api_server: 'api.geetest.com'
  }, function (captchaObj) {
    captchaObj.onReady(function () { captchaObj.verify(); });
    captchaObj.onSuccess(function () {
      var result = captchaObj.getValidate();
      if (window.hutaoVerifyBridge) {
        window.hutaoVerifyBridge.onValidate(JSON.stringify(result));
      }
    });
    captchaObj.onError(function () {
      if (window.hutaoVerifyBridge) {
        window.hutaoVerifyBridge.onValidate('{"error":"init_fail"}');
      }
    });
  });
</script>
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
        // 蒙层（点击关闭 → 取消验证）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.mask_scrim'))
          .onClick(() => {
            RiskVerifyService.getInstance().cancel();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))

        Column() {
          // 标题行
          Row({ space: 8 }) {
            Text(this.kindLabel())
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text('✕')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
              .padding(10)
              .borderRadius(12)
              .onClick(() => {
                RiskVerifyService.getInstance().cancel();
              })
          }
          .width('100%')

          // 说明 + 状态（呼吸点）
          Row({ space: 6 }) {
            Circle({ width: 6, height: 6 })
              .fill($r('app.color.app_primary'))
              .opacity(this.statusText.includes('请完成') ? 1 : 0.35)
              .animation({ duration: 700, curve: Curve.EaseInOut, iterations: -1, playMode: PlayMode.Alternate })
            Text(this.statusText.length > 0 ? this.statusText : '正在发起人机验证...')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: 8 })

          // 极验 WebView
          Column() {
            Web({ src: 'about:blank', controller: this.controller })
              .width('100%')
              .height(320)
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .backgroundColor(Color.Transparent)
              .onPageEnd(() => {
                this.statusText = '请完成下方人机验证';
              })
          }
          .width('100%')
          .margin({ top: 10 })
        }
        .width('92%')
        .constraintSize({ maxWidth: 420 })
        .padding({ left: 18, right: 12, top: 16, bottom: 14 })
        .borderRadius(24)
        // API 26+ 沉浸光感材质（低版本自动回退纯色卡面）
        .systemMaterial(this.material)
        .backgroundColor(this.material !== undefined ? Color.Transparent : $r('app.color.card_background'))
        .shadow({ radius: 40, color: 'rgba(0,0,0,0.35)', offsetY: 12 })
        .alignItems(HorizontalAlign.Start)
        .transition(TransitionEffect.asymmetric(
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
        .onAppear(() => {
          this.loadCaptcha(this.req.gt, this.req.challenge);
        })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.isShow ? HitTestMode.Default : HitTestMode.None)
  }
}
