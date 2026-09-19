/**
 * SignInViewModel.ets
 * 签到页状态容器。
 */
import { SignInService, SignInResult, ResignInfo } from '../service/SignInService';
import { SignInInfo } from '../model/SignInInfo';

@Observed
export class SignInViewModel {
  info: SignInInfo | undefined = undefined;
  loading: boolean = false;
  signing: boolean = false;
  /** 补签信息（随 info 一起刷新；失败为 undefined，补签卡不显示） */
  resign: ResignInfo | undefined = undefined;
  /** 补签执行中 */
  resigning: boolean = false;
  message: string = '';
  loaded: boolean = false;

  async load(uid: string): Promise<void> {
    this.loading = true;
    try {
      this.info = await SignInService.getInstance().fetchInfo(uid);
      // 补签信息独立拉取（失败不影响主流程）
      try {
        this.resign = await SignInService.getInstance().fetchResignInfo(uid);
      } catch (e) {
        this.resign = undefined;
      }
    } catch (e) {
      this.message = (e as Error).message;
    } finally {
      this.loading = false;
      this.loaded = true;
    }
  }

  async doSign(uid: string): Promise<SignInResult> {
    if (this.signing) {
      return SignInViewModel.emptyResult();
    }
    this.signing = true;
    try {
      const result: SignInResult = await SignInService.getInstance().sign(uid);
      this.message = result.message;
      // 刷新状态
      await this.refreshAfterAction(uid);
      return result;
    } catch (e) {
      this.message = (e as Error).message;
      return SignInViewModel.emptyResult();
    } finally {
      this.signing = false;
    }
  }

  async doResign(uid: string): Promise<SignInResult> {
    if (this.resigning) {
      return SignInViewModel.emptyResult();
    }
    this.resigning = true;
    try {
      const result: SignInResult = await SignInService.getInstance().resign(uid);
      this.message = result.message;
      await this.refreshAfterAction(uid);
      return result;
    } catch (e) {
      this.message = (e as Error).message;
      return SignInViewModel.emptyResult();
    } finally {
      this.resigning = false;
    }
  }

  /** 签到/补签后刷新状态与补签信息 */
  private async refreshAfterAction(uid: string): Promise<void> {
    try {
      this.info = await SignInService.getInstance().fetchInfo(uid);
    } catch (e) {
      // 忽略刷新失败
    }
    try {
      this.resign = await SignInService.getInstance().fetchResignInfo(uid);
    } catch (e) {
      this.resign = undefined;
    }
  }

  private static emptyResult(): SignInResult {
    const r: SignInResult = new SignInResult();
    r.ok = false;
    r.message = '';
    return r;
  }
}
