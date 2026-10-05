import { LocalePolicy } from './LocalePolicy';

class HelpLabel {
  key: string;
  values: string[];
  constructor(key: string, values: string[]) { this.key = key; this.values = values; }
}

export class HelpText {
  private static readonly rows: HelpLabel[] = [
    new HelpLabel("title", ["帮助与诊断", "Help and diagnostics", "說明與診斷"]),
    new HelpLabel("search", ["搜索问题、功能或文件格式", "Search a problem, feature or file format", "搜尋問題、功能或檔案格式"]),
    new HelpLabel("scope", ["语言仅适用于帮助与已接入的通用提示；其余界面和游戏文本保持原文", "Language applies to help and integrated common messages only. Other UI and game text retain their source language.", "語言僅適用於說明與已接入的通用提示；其餘介面和遊戲文字保留原文"]),
    new HelpLabel("fallback", ["当前系统语言暂不支持，帮助使用英语", "Your system language is not supported yet. Help is shown in English.", "目前系統語言暫不支援，說明使用英語"]),
    new HelpLabel("system", ["跟随系统", "Follow system", "跟隨系統"]),
    new HelpLabel("language", ["帮助语言", "Help language", "說明語言"]),
    new HelpLabel("empty", ["没有找到文章，请尝试功能名称或 UIGF、备份等关键词", "No articles found. Try a feature name or keywords such as UIGF or backup.", "找不到文章，請嘗試功能名稱或 UIGF、備份等關鍵字"]),
    new HelpLabel("choose", ["选择文章查看操作步骤", "Select an article for actionable steps", "選擇文章查看操作步驟"]),
    new HelpLabel("back", ["全部文章", "All articles", "全部文章"]),
    new HelpLabel("open", ["打开相关页面", "Open related page", "開啟相關頁面"]),
    new HelpLabel("diagnostics", ["诊断预览", "Diagnostic preview", "診斷預覽"]),
    new HelpLabel("privacy", ["仅包含允许的固定字段；不读取账号、UID、凭据、剪贴板或日志，不自动上传", "Allowlisted fields only. No account, UID, credential, clipboard or log reads; no automatic upload.", "僅包含允許的固定欄位；不讀取帳號、UID、憑證、剪貼簿或日誌，不自動上傳"]),
    new HelpLabel("environment", ["加入版本、API、设备类别与主题（生成时读取）", "Include version, API, device category and theme (read when generating)", "加入版本、API、裝置類別與主題（產生時讀取）"]),
    new HelpLabel("generate", ["生成诊断预览", "Generate diagnostic preview", "產生診斷預覽"]),
    new HelpLabel("copy", ["复制已检查的预览", "Copy reviewed preview", "複製已檢查的預覽"]),
    new HelpLabel("clear", ["丢弃预览", "Discard preview", "捨棄預覽"]),
    new HelpLabel("problem", ["选择问题类型（不会自动执行修复）", "Select a problem type (no automatic fixes)", "選擇問題類型（不會自動執行修復）"]),
    new HelpLabel("general", ["其他操作失败", "Other operation failure", "其他操作失敗"]),
    new HelpLabel("network", ["网络不可用", "Network unavailable", "網路無法使用"]),
    new HelpLabel("permission", ["权限问题", "Permission issue", "權限問題"]),
    new HelpLabel("file", ["文件无效", "Invalid file", "檔案無效"]),
    new HelpLabel("login", ["登录过期", "Session expired", "登入過期"]),
    new HelpLabel("unsupported", ["操作不可用", "Operation unavailable", "操作無法使用"]),
    new HelpLabel("readFirst", ["预览供你检查；复制会写入系统剪贴板，不会提交反馈", "Review first. Copying writes to the system clipboard; it does not submit feedback.", "預覽供你檢查；複製會寫入系統剪貼簿，不會提交回報"]),
    new HelpLabel("local", ["本机离线帮助 · 无需登录", "Offline help on this device · No sign-in required", "本機離線說明 · 無需登入"]),
  ];
  static text(key: string, locale: string): string {
    const row: HelpLabel | undefined = HelpText.rows.find((value: HelpLabel) => value.key === key);
    if (row === undefined) { return ''; }
    const language: string = LocalePolicy.resourceLocale(locale);
    return row.values[language === 'zh-Hans' ? 0 : language === 'zh-Hant' ? 2 : 1];
  }
}
