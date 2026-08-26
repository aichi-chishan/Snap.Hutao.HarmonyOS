/**
 * SignInViewModel.ets
 * 签到页状态容器。
 */
import { SignInService, SignInResult } from '../service/SignInService';
import { SignInInfo } from '../model/SignInInfo';

@Observed
export class SignInViewModel {
  info: SignInInfo | undefined = undefined;
  loading: boolean = false;
  signing: boolean = false;
  message: string = '';
  loaded: boolean = false;

  async load(uid: string): Promise<void> {
    this.loading = true;
    try {
      this.info = await SignInService.getInstance().fetchInfo(uid);
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
      try {
        this.info = await SignInService.getInstance().fetchInfo(uid);
      } catch (e) {
        // 忽略刷新失败
      }
      return result;
    } catch (e) {
      this.message = (e as Error).message;
      return SignInViewModel.emptyResult();
    } finally {
      this.signing = false;
    }
  }

  private static emptyResult(): SignInResult {
    const r: SignInResult = new SignInResult();
    r.ok = false;
    r.message = '';
    return r;
  }
}
