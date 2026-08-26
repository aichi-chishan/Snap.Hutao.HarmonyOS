/**
 * RiskVerifyDialog.ets
 * 风控验证弹出窗（对齐 Windows 验证小窗：遇到 1034 时当前页自动弹出极验，完成后自动重放）。
 * 数据源由调用方传入（gt/challenge/path + 回调），内部复用 GeetestVerifyPage 的极验 HTML/JS 桥逻辑。
 */
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { RiskVerifier, GeetestValidateInput } from '../data/network/RiskVerifier';
import { UserService } from '../service/UserService';
import { Logger } from '../common/Logger';

const TAG: string = 'RiskVerifyDialog';

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

@Component
export struct RiskVerifyDialog {
  /** 显示开关（父组件控制） */
  @Link isShow: boolean;
  /** 极验 gt */
  @Prop gt: string = '';
  /** 极验 challenge（初始） */
  @Prop challenge: string = '';
  /** 触发风控的 path（回显/日志用） */
  @Prop path: string = '';
  /** 验证完成回调（父组件重放原请求） */
  onDone: (challenge: string) => void = () => {
  };

  @State statusText: string = '加载人机验证中...';
  @State verifying: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private proxy: VerifyJsProxy = new VerifyJsProxy((json: string) => {
    this.handleValidate(json);
  });

  cancel(): void {
    this.isShow = false;
  }

  /** 验证结果：verifyXrpcChallenge → 成功回调 onDone（父组件重放）；失败保持弹窗 */
  async handleValidate(json: string): Promise<void> {
    if (this.verifying) {
      return;
    }
    this.verifying = true;
    this.statusText = '验证成功，正在提交...';
    try {
      const obj: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      const validate: string = String(obj['validate'] ?? '');
      const geetestChallenge: string = String(obj['challenge'] ?? this.challenge);
      const seccode: string = String(obj['seccode'] ?? '');
      if (validate.length === 0) {
        throw new Error('验证结果为空');
      }
      const input: GeetestValidateInput = {
        geetestChallenge: geetestChallenge,
        geetestValidate: validate,
        geetestSeccode: seccode,
      };
      const user = UserService.getInstance().getCurrentUser();
      const cookie: string = user !== undefined ? user.stokenCookie() : '';
      const challenge: string = await RiskVerifier.verifyXrpcChallenge(cookie, input);
      if (challenge.length === 0) {
        this.statusText = '换 challenge 失败，请重试';
        this.verifying = false;
        return;
      }
      Logger.info(TAG, `verify ok, challenge=${challenge.substring(0, 8)}...`);
      this.statusText = '验证完成';
      this.isShow = false;
      this.onDone(challenge);
    } catch (e) {
      Logger.warn(TAG, `handleValidate fail: ${(e as Error).message}`);
      this.statusText = '验证处理失败，请重试';
    }
    this.verifying = false;
  }

  private buildHtml(gt: string, challenge: string): string {
    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<style>
  html,body{margin:0;padding:0;height:100%;background:#FFFFFF;}
  #captcha{margin-top:16px;display:flex;justify-content:center;}
</style>
</head>
<body>
<div id="captcha"></div>
<script src="https://static.geetest.com/static/tools/gt.0.5.2.js"></script>
<script>
  function initGeetest() {
    if (typeof initGeetestFallback === 'function') { return; }
  }
  window.onload = function() {
    try {
      var gt = '${gt}';
      var challenge = '${challenge}';
      if (typeof initGeetest !== 'undefined') {
        initGeetest({
          gt: gt,
          challenge: challenge,
          offline: false,
          new_captcha: true,
          product: 'popup',
          width: 300,
        }, function(captchaObj) {
          captchaObj.appendTo('#captcha');
          captchaObj.onReady(function() {
            captchaObj.show();
          });
          captchaObj.onSuccess(function() {
            var result = captchaObj.getValidate();
            hutaoVerifyBridge.onValidate(JSON.stringify(result));
          });
          captchaObj.onError(function() {});
        });
      }
    } catch (e) {
      hutaoVerifyBridge.onValidate('{"error":"init_fail"}');
    }
  };
</script>
</body>
</html>`;
  }

  build() {
    Column() {
      Row() {
        Text('人机验证')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('✕')
          .fontSize(18)
          .fontColor($r('app.color.text_secondary'))
          .padding(8)
          .onClick(() => {
            this.cancel();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 14 })

      Text(this.statusText)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })

      Column() {
        Web({ src: '', controller: this.controller })
          .width('100%')
          .height(260)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageEnd(() => {
            this.statusText = '请完成下方人机验证';
          })
      }
      .padding(12)
      .width('100%')
    }
    .width('100%')
    .height(360)
    .backgroundColor($r('app.color.page_background'))
    .onAppear(() => {
      // 注册 JS 桥后加载极验页面
      try {
        this.controller.registerJavaScriptProxy(this.proxy, 'hutaoVerifyBridge', ['onValidate']);
      } catch (e) {
        Logger.warn(TAG, `register proxy fail ${(e as BusinessError).message}`);
      }
      this.controller.loadData(this.buildHtml(this.gt, this.challenge), 'text/html', 'UTF-8');
      this.statusText = '请完成下方人机验证';
    })
  }
}
