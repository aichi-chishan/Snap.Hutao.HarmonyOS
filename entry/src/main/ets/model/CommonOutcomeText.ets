import { CommonOutcome, CommonOutcomeId } from './CommonOutcome';
import { LocalePolicy } from './LocalePolicy';

class OutcomeTranslation {
  id: CommonOutcomeId;
  values: string[];
  constructor(id: CommonOutcomeId, values: string[]) { this.id = id; this.values = values; }
}

/** Translate only explicit typed app outcomes. Raw exception/server messages are never guessed or exposed. */
export class CommonOutcomeText {
  private static readonly rows: OutcomeTranslation[] = [
    new OutcomeTranslation(CommonOutcomeId.None, ["", "", ""]),
    new OutcomeTranslation(CommonOutcomeId.Preparing, ["正在准备，请稍候", "Preparing. Please wait.", "正在準備，請稍候"]),
    new OutcomeTranslation(CommonOutcomeId.Ready, ["准备完成，请检查预览后继续", "Ready. Review the preview before continuing.", "準備完成，請檢查預覽後繼續"]),
    new OutcomeTranslation(CommonOutcomeId.Cancelled, ["已取消；请检查当前页面状态后重试", "Cancelled. Check the current page state before retrying.", "已取消；請檢查目前頁面狀態後重試"]),
    new OutcomeTranslation(CommonOutcomeId.InvalidFile, ["文件无效或不受支持，请检查格式、大小与导出版本", "Invalid or unsupported file. Check its format, size and export version.", "檔案無效或不受支援，請檢查格式、大小與匯出版本"]),
    new OutcomeTranslation(CommonOutcomeId.ImportFailed, ["导入未完成，请检查文件与目标归档后重试", "Import did not complete. Check the file and destination archive before retrying.", "匯入未完成，請檢查檔案與目標歸檔後重試"]),
    new OutcomeTranslation(CommonOutcomeId.ImportComplete, ["导入完成，新增 {count} 条记录", "Import complete: {count} records added.", "匯入完成，新增 {count} 筆紀錄"]),
    new OutcomeTranslation(CommonOutcomeId.ExportFailed, ["导出未完成，请检查目标位置的写入权限后重试", "Export did not complete. Check write access to the destination and retry.", "匯出未完成，請檢查目標位置的寫入權限後重試"]),
    new OutcomeTranslation(CommonOutcomeId.ExportComplete, ["导出完成，请安全保存文件", "Export complete. Keep the file secure.", "匯出完成，請安全儲存檔案"]),
    new OutcomeTranslation(CommonOutcomeId.Busy, ["已有操作正在进行，请等待完成或先取消", "An operation is in progress. Wait for it to finish or cancel it first.", "已有操作正在進行，請等待完成或先取消"]),
    new OutcomeTranslation(CommonOutcomeId.NetworkUnavailable, ["网络暂时不可用，请检查连接后手动重试", "Network unavailable. Check your connection and retry manually.", "網路暫時無法使用，請檢查連線後手動重試"]),
    new OutcomeTranslation(CommonOutcomeId.PermissionRequired, ["需要系统权限，请查看系统提示并自行决定是否授权", "System permission is required. Review the prompt and decide whether to allow it.", "需要系統權限，請查看系統提示並自行決定是否授權"]),
    new OutcomeTranslation(CommonOutcomeId.LoginExpired, ["登录可能已过期，请核对账号与服务器后重新登录", "The session may have expired. Check the account and server, then sign in again.", "登入可能已過期，請核對帳號與伺服器後重新登入"]),
    new OutcomeTranslation(CommonOutcomeId.Unsupported, ["此操作当前不可用，请查看设备限制与帮助", "This operation is currently unavailable. Check device limits and help.", "此操作目前無法使用，請查看裝置限制與說明"]),
    new OutcomeTranslation(CommonOutcomeId.CopyComplete, ["已复制；分享前请再次检查内容", "Copied. Review the content again before sharing.", "已複製；分享前請再次檢查內容"]),
    new OutcomeTranslation(CommonOutcomeId.CopyFailed, ["无法复制，请检查系统剪贴板权限后重试", "Could not copy. Check system clipboard access and retry.", "無法複製，請檢查系統剪貼簿權限後重試"]),
    new OutcomeTranslation(CommonOutcomeId.Failed, ["操作未完成，请查看相关帮助并手动重试", "The operation did not complete. Check the related help and retry manually.", "操作未完成，請查看相關說明並手動重試"]),
    new OutcomeTranslation(CommonOutcomeId.LocaleFailed, ["语言设置未应用，请稍后重试", "The language setting was not applied. Please try again later.", "語言設定未套用，請稍後重試"]),
  ];
  static text(outcome: CommonOutcome, locale: string): string {
    const key: string = LocalePolicy.resourceLocale(locale);
    const id: CommonOutcomeId = CommonOutcome.known(outcome.id) ? outcome.id : CommonOutcomeId.Failed;
    const row: OutcomeTranslation | undefined = CommonOutcomeText.rows.find((value: OutcomeTranslation) => value.id === id);
    if (row === undefined) { return ''; }
    const index: number = key === 'zh-Hans' ? 0 : key === 'zh-Hant' ? 2 : 1;
    const count: number = new CommonOutcome(id, outcome.count).count;
    return row.values[index].replace('{count}', String(count));
  }
}
