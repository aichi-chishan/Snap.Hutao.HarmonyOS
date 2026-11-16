# 应用语言覆盖

设置 → 外观 → 语言提供 Windows 的 15 个语言选项。每个 `entry/src/main/resources/<语言>/element/` 中的 `ui_strings.json` 和 `ui_labels.json` 提供同一组 364 个原生字符串键。资源采用 Remastered `3b7475e` 的各语言 `SH*.resx`，并补充鸿蒙专用控件与提示。 [Windows 资源目录](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/tree/3b7475ed3eca4aedf9cb81d94741bfbe6fa189f5/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Resource/Localization) · [鸿蒙资源限定词](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/resource-categories-and-access/)

| 位置 | 已接入 |
| --- | --- |
| 应用壳 | 手机底部页签、宽屏侧栏分组和导航项、主页问候、快捷入口标题及摘要 |
| 设置 | 分组目录、语言与主题、材质、星期、祈愿开关、备份及清空确认、游戏数据和媒体缓存操作 |
| 应用更新 | 首页更新提示、发布说明、检查状态、发布通道、跳过版本及手动检查入口 |
| 账号洞察与 AI | 洞察标题、空状态、匿名 JSON 复制、会话工具栏、消息复制、数据使用说明、工具审批、模型配置表单 |
| 帮助 | 应用语言选择与原有离线本地化目录 |
| 祈愿、图鉴、成就、角色、挑战与公告 | 已有对应 Windows 文案的标题、主要操作、筛选项及部分无障碍描述 |

七类祈愿池的 `ui_gacha_pool_*` 标题沿用 Windows `ServiceGachaLogFactory*WishName` 资源。 [Windows 池标题接线](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3b7475ed3eca4aedf9cb81d94741bfbe6fa189f5/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/GachaLog/Factory/TypedWishSummaryBuilderContext.cs#L55-L87)

页面接线时可将 `$r('app.string.…')` 传给 `PageHeader.title`。页面标题可用 `page_title_login`、`page_title_setting`、`page_title_gacha`、`page_title_note` 和相应的 `ui_nav_*` 键。共享操作可用 `common_refresh`、`common_confirm`、`common_cancel`、`ui_action_import`、`ui_action_export`、`ui_action_save`。

选择具体语言时，鸿蒙按应用语言加载资源。选择跟随系统会清除应用覆盖，鸿蒙在下次冷启动采用系统语言。 [设置应用偏好语言](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-i18n/)

`AppLocaleService.apiLanguageCode()` 提供与 Windows `LocaleNames` 一致的米哈游语言码。Windows 国服 `luna/info` 与 `luna/home` 在查询参数中携带此语言码，`GetCurrentLocaleAsync` 向网页报告该值。 [Windows 语言码](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3b7475ed3eca4aedf9cb81d94741bfbe6fa189f5/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/LocaleNames.cs#L52-L74) · [签到端点](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3b7475ed3eca4aedf9cb81d94741bfbe6fa189f5/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ApiEndpoints.csv#L69-L74)
