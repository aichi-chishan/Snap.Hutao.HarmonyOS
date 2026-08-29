/**
 * GeetestVerifyPage.ets（@Entry）
 * 人机验证页（通用化）：内嵌极验（gt.0.5.2.js + api.geetest.com），完成验证后
 * 调用 verifyVerification 换取 challenge，写入 AppStorage(replayKey) 供来源页重放。
 * 参数：{ gt, challenge, path?, replayKey? }
 *   path — 触发风控的接口路径（createVerification 阶段已带，这里仅作回显）
 *   replayKey — 完成时写入的 AppStorage 键（默认 pendingRiskChallenge）
 */
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { RiskVerifier, GeetestValidateInput } from '../data/network/RiskVerifier';
import { UserService } from '../service/UserService';
import { AppConstants } from '../common/Constants';
import { Logger } from '../common/Logger';
import { AppBackButton } from '../components/AppBackButton';
import { NavIcon } from '../components/NavIcon';

const TAG: string = 'GeetestVerify';

/** 极验页面参数 */
export interface GeetestVerifyParams {
  gt: string;
  challenge: string;
  /** 触发接口路径（可选，回显） */
  path?: string;
  /** 完成时写入的 AppStorage 键（可选，默认 pendingRiskChallenge） */
  replayKey?: string;
}

/** 极验 JS 桥：接收网页回传的验证结果 */
class GeetestJsProxy {
  private onResult: (json: string) => void = () => {
  };

  constructor(cb: (json: string) => void) {
    this.onResult = cb;
  }

  onValidate(json: string): void {
    this.onResult(json);
  }
}

@Entry
@Component
export struct GeetestVerifyPage {
  @StorageProp('topAvoidVp') topAvoidVp: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  @State statusText: string = '加载人机验证中...';
  @State verifying: boolean = false;
  private gt: string = '';
  private challenge: string = '';
  private replayKey: string = 'pendingRiskChallenge';
  private proxy: GeetestJsProxy = new GeetestJsProxy((json: string) => {
    this.handleValidate(json);
  });

  aboutToAppear(): void {
    const params = router.getParams() as GeetestVerifyParams;
    this.gt = params?.gt ?? '';
    this.challenge = params?.challenge ?? '';
    this.replayKey = params?.replayKey !== undefined && params.replayKey.length > 0
      ? params.replayKey : 'pendingRiskChallenge';
    Logger.info(TAG, `gt=${this.gt.length > 0 ? 'ok' : 'empty'} challenge=${this.challenge.length} key=${this.replayKey}`);
    if (this.gt.length === 0 || this.challenge.length === 0) {
      this.statusText = '验证参数缺失，请返回重试';
      return;
    }
    // 注册 JS 桥后加载内嵌极验页面
    try {
      this.controller.registerJavaScriptProxy(this.proxy, 'hutaoVerifyBridge', ['onValidate']);
    } catch (e) {
      Logger.warn(TAG, `register proxy fail ${(e as BusinessError).message}`);
    }
    this.loadGeetestPage();
  }

  /** 加载极验内嵌页面（与参考项目一致的 gt.0.5.2.js 方案） */
  loadGeetestPage(): void {
    const html: string = this.buildGeetestHtml(this.gt, this.challenge);
    this.controller.loadData(html, 'text/html', 'UTF-8');
    this.statusText = '请完成下方人机验证';
  }

  /** 构造极验 HTML（api.geetest.com 为极验官方域） */
  private buildGeetestHtml(gt: string, challenge: string): string {
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
<script src="https://static.geetest.com/static/js/gt.0.5.2.js"></script>
<script>
function onValidateResult(result) {
  if (window.hutaoVerifyBridge) {
    window.hutaoVerifyBridge.onValidate(JSON.stringify(result));
  }
}
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
    onValidateResult(result);
  });
  captchaObj.onError(function (err) {
    onValidateResult({ error: JSON.stringify(err) });
  });
});
</script>
</body>
</html>`;
  }

  /** 处理网页回传的验证结果：换 challenge → 存 AppStorage → 返回 */
  async handleValidate(json: string): Promise<void> {
    if (this.verifying) {
      return;
    }
    this.verifying = true;
    this.statusText = '验证成功，正在提交...';
    try {
      const obj = JSON.parse(json) as Record<string, Object>;
      const geetestChallenge: string = String(obj['geetest_challenge'] ?? '');
      const geetestValidate: string = String(obj['geetest_validate'] ?? '');
      const geetestSeccode: string = String(obj['geetest_seccode'] ?? '');
      if (geetestValidate.length === 0) {
        this.statusText = '验证失败或已取消，请重试';
        this.verifying = false;
        return;
      }
      const validate: GeetestValidateInput = new GeetestValidateInput();
      validate.geetestChallenge = geetestChallenge;
      validate.geetestValidate = geetestValidate;
      validate.geetestSeccode = geetestSeccode;
      const user = UserService.getInstance().getCurrentUser();
      const cookie: string = user !== undefined ? user.gameRecordCookie() : '';
      const challenge: string = await RiskVerifier.verifyXrpcChallenge(cookie, validate);
      if (challenge.length === 0) {
        this.statusText = '验证提交失败，请重试';
        this.verifying = false;
        return;
      }
      AppStorage.setOrCreate<string>(this.replayKey, challenge);
      this.statusText = '验证完成，返回重试';
      setTimeout(() => {
        router.back();
      }, 500);
    } catch (e) {
      Logger.warn(TAG, `handleValidate fail ${(e as Error).message}`);
      this.statusText = '验证处理失败，请重试';
      this.verifying = false;
    }
  }

  build() {
    Column() {
      Row() {
        AppBackButton()
        Text('人机验证')
          .fontSize($r('app.float.page_title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 10 })
        Blank()
        Text(this.challenge.length > 0 ? '✓ 验证流程就绪' : '待发起验证')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: this.topAvoidVp + 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.card_background'))

      Text(this.statusText)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding(10)

      if (this.gt.length > 0 && this.challenge.length > 0) {
        Web({ src: 'about:blank', controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .width('100%')
          .layoutWeight(1)
          .onPageEnd(() => {
            this.statusText = '请完成下方人机验证';
          })
      } else {
        Column({ space: 10 }) {
          NavIcon({ name: 'Passport', iconSize: 48 })
          Text(this.statusText)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
