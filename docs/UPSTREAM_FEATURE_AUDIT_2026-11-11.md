# Windows 版非注入功能移植审计（2026-11-11）

Windows 对照仓 `Snap.Hutao.Remastered-latest` 更新后仍为 `origin/main` 的 `3b7475ed3eca4aedf9cb81d94741bfbe6fa189f5`（2026-10-23，2.0.2.0）。鸿蒙对照基线为 `2c56f8e`，表中同时记录本轮落地功能。

从 `UI/Xaml/View/MainView.xaml:520–603` 的实际导航、设置页、首页卡片、窗口、托盘入口和任务调度出发，沿命令、ViewModel、服务、持久化追到鸿蒙对应调用。Windows 路径相对 `Snap.Hutao.Remastered-latest/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/`，鸿蒙 ArkTS 路径相对 `entry/src/main/ets/`。**已接通**表示找到入口和对应实现，**部分**表示仍有具体行为差距，**缺失**表示未找到相应可调用实现。结论来自静态源码检查，设备交互和在线接口仍需运行验证。

范围遵循 `AGENTS.md` 的国服、胡桃云和注入约束。官方米游社接口、用户自设 Webhook、用户自设 AI 服务和静态 CDN 在范围内。

## 导航、首页与账号

| 功能 | Windows 源码 | 鸿蒙源码与结论 |
| --- | --- | --- |
| 主导航、首页卡片、当前账号、主题 | `MainView.xaml`、`UI/Xaml/View/Page/AnnouncementPage.xaml`、`ViewModel/Setting/SettingHomeViewModel.cs:72–77`。首页卡片支持配置顺序和显隐 | **已接通**。`pages/Index.ets` 的 `sideNav`、`wideContent`、手机底部页签及首页入口覆盖保留的导航域。`pages/SettingPage.ets` 的 `loadHomeCardRows`、`toggleHomeCard`、`moveHomeCard` 写入设置，首页订阅更新。亮/暗/跟随系统和普通/沉浸光感由 `UiSurface` 与 `EntryAbility` 接通 |
| 游戏公告、详情、活动日历预览、直播兑换码 | `ViewModel/Home/AnnouncementViewModel.cs` 的 `InitializeInGameAnnouncementAsync`、`InitializeMiyoliveCodeAsync`、`InitializeActivityCalendarAsync`、`CopyCodeToClipboardAsync`。应用公告另由 `InitializeHutaoAnnouncementAsync` 请求胡桃服务 | **已接通**国服链。`pages/AnnouncementPage.ets`、`AnnouncementDetailPage.ets`、`service/AnnouncementService.ets`、`service/MiyoliveService.ets` 实现列表、详情和代码复制。首页公告详情、查看全部和兑换码各有独立入口，活动奖励按钮单独打开预览。胡桃在线应用公告沿范围排除。公开公告选区见范围核对 |
| 国服米游社账号和多角色 | `ViewModel/User/UserViewModel.cs` 的 `LoginByQRCodeAsync`、`LoginByMobileCaptchaAsync`、`CopyCookieAsync`、`RefreshCookieTokenAsync` 及 `Service/User/UserInitializationService.cs` | **已接通**。`pages/LoginPage.ets` 的国服扫码、短信、Web/Cookie 登录与 `service/UserService.ets` 相连。`pages/UserPage.ets` 提供多账号切换、删除、刷新角色、默认 UID、复制 Cookie 和刷新凭证。`LoginPage.regionSwitch` 同时暴露 HoYoLAB Web/Cookie 登录，见范围核对 |
| 米游社签到、补签、签到奖励卡 | `ViewModel/Sign/SignInViewModel.cs` 的 `ClaimSignInRewardCommand`、`ClaimResignInRewardCommand`、`ScrollToNextAwardCommand` 与 `UI/Xaml/View/Card/SignInCard.xaml` | **已接通**。`SignInPage`、`SignInViewModel`、`SignInService` 和 `HomeSignInCard` 提供月奖励、签到、补签。首页卡的签到、补签和打开签到页各有独立入口。手动签到失败后打开官方签到页，关闭后重新查询签到状态 |
| 旅行札记 | `ViewModel/TravelersDiary/TravelersDiaryViewModel.cs` 与 `UI/Xaml/View/Card/TravelersDiaryCard.xaml` | **已接通**。`service/LedgerService.ets`、`pages/LedgerPage.ets`、`HomeLedgerCard` 提供月度原石/摩拉、分类与环比。月度、账户隔离及空态已有独立代码 |
| 每周材料日历与生日 | `ViewModel/Calendar/CalendarViewModel.cs` 的 `LoadAsync` 读取项目 `ServerTimeZoneOffset` 或全局时区设置。`CreateWeekDays` 构建材料和角色生日 | **部分**。`CalendarWeekService.loadWeek`、`GameCalendarRules` 与 `HomeCalendarCard` 已有服务器日、星期起始日、材料轮换、生日和项目材料提示。鸿蒙从 UID 地区决定时区，缺 Windows 的手动时区和项目时区继承。国服默认东八区已有等价口径 |
| 新装准备、运行中资源状态与恢复 | `GuideViewModel.DownloadStaticResourceAsync`、`ViewModel/MainViewModel.cs` 和 `MainView.xaml:134–168,305–332` 体现资源下载、初始化进度、离线状态及重连。`Service/Git/RepositoryCatalogService.cs` 支持内置目录回退 | **部分**。`EntryAbility` 初始化资源，默认数据随包，`SettingPage` 提供手动检查、更新状态、取消、回滚、恢复内置。首页缺同等的资源连接/恢复入口。初次必须下载资源与 Windows 全信任组件进度无对应前提 |

## 便笺、定时任务与风控

| 功能 | Windows 源码 | 鸿蒙源码与结论 |
| --- | --- | --- |
| 多 UID 便笺、手动与应用内自动刷新 | `DailyNoteViewModel.RefreshCommand` 调用 `DailyNoteService.PrivateRefreshDailyNotesAsync` 遍历已跟踪条目。`DailyNoteOptions` 的默认开关为关闭，间隔为 4、8、30、40、60 分钟。`DailyNoteCard.xaml` 有翻页与刷新 | **已接通便笺页**。顶栏刷新遍历所有本地账号的已追踪国服角色，按所属账号与 UID 读取凭据、缓存和设置。前台自动刷新默认关闭，启用后默认 30 分钟，已有 5、10、15 分钟选择保留到用户改选。首页当前有账号内翻页和刷新，跨账号接线可复用 `trackedEntries` 和 `refreshTrackedEntry` |
| 阈值、提醒和 Webhook | `DailyNoteNotificationDialog.xaml:43–91` 的两个滑条使用 0 至角色容量上限。`ModifyNotificationCommand`、`Service/DailyNote/NotifySuppression/`、`DailyNoteWebhookOperation.TryPostDailyNoteToWebhook` | **已接通**。`DailyNotePage` 可逐角色设置树脂和宝钱阈值，上限来自便笺。刷新缓存只更新游戏状态字段，设置单独写入。`DailyNoteService` 对追踪角色发送阈值通知和 Webhook，Webhook 载荷为 `x-uid` 请求头和原始便笺 JSON。桌面卡显示当前角色 |
| 系统调度多目标便笺 | `Service/Job/DailyNoteRefreshJobScheduler.cs` 使用统一间隔，`DailyNoteRefreshJob` 调用 `DailyNoteService.RefreshDailyNotesAsync` 刷新满足条件的各档案 | **本轮已接通**。`BackgroundTaskService.executeAll` 遍历已追踪的国服角色，以每个任务类型一个 WorkScheduler 注册和逐角色租约执行。设置显示范围及执行摘要，既有单 UID 授权可在设置扩大。账号变化后撤销旧调度并重新登记 |
| 跨日自动签到全部账号和角色 | `UserInitializationService.cs:231` 启动初始化当前角色。`AutoSignInJobScheduler` 从服务器下一日开始定时，`AutoSignInService.RunForAllUsersAsync` 续签已存凭据并遍历各账号角色 | **本轮已接通**。`AutoSignInService` 保留启动时当前 UID，前台定时及明确开启的系统调度覆盖本地国服角色，共享逐角色租约和服务器日去重。已有凭据过期时通过 `UserService` 非交互续签一次，之后先查服务器签到状态 |
| 极验与自定义接口 | `ViewModel/Setting/SettingGeetestViewModel.cs`、`Service/Geetest/GeetestService.cs` 与请求验证、重放链 | **已接通**。`SettingPage.applyGeetestUrl`、`RiskVerifyService`、`RiskVerifyModal`、`RiskVerifier` 已连接设置、全局验证和业务重放。签到体内验证用回传的 `geetest_challenge` 和 `geetest_validate`，补签 1034 用补签路径。便笺的「验证」打开官方当前角色页面 |

- API 26 的 `@ohos.resourceschedule.workScheduler.d.ts`、`@ohos.WorkSchedulerExtensionAbility.d.ts` 确认 `earliestStartTime` 是相对登记时刻的毫秒数，`stopWork(work, false)` 保留登记。`WorkInfo` 循环周期按官方规则至少 2 小时，每次处理预算为 80 秒，系统回调最长 2 分钟。 [WorkScheduler API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-resourceschedule-workscheduler/) · [延迟任务回调](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-workschedulerextensionability/)
- API 26 的 `@ohos.notificationManager.d.ts` 确认 `isNotificationEnabledSync`、`publish` 和 `SERVICE_INFORMATION`。后台查询已有授权，页面承担授权请求。前台跨日签到随 `EntryAbility` 的 `onForeground`、`onBackground` 和 `onDestroy` 暂停或恢复。 [通知管理](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-notificationmanager/) · [UIAbility 生命周期](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/uiability-lifecycle/)

## 祈愿、成就与角色

| 功能 | Windows 源码 | 鸿蒙源码与结论 |
| --- | --- | --- |
| 祈愿获取、进度、取消、离线档案 | `ViewModel/GachaLog/GachaLogViewModel.cs` 的 `RefreshByWebCacheCommand`、`RefreshBySTokenCommand`、`RefreshByManualInputCommand`、`RemoveArchiveCommand` 与 `Service/GachaLog/GachaLogService.cs` | **已接通**可移植路径。`GachaLogPage` 和 `GachaLogViewModel` 支持账号 AuthKey、手动与剪贴板链接、增量/全量、进度与取消、失败池重试和离线切换。归档菜单有账号洞察及确认后删除当前归档，确认与所选归档绑定。Windows 游戏 WebCache 属桌面游戏目录获取路径 |
| 祈愿总览、历史、统计、倒计时 | `GachaLogPage.xaml:592–848`、`TypedWishSummaryBuilder`、`GachaLogWishCountdownService`、`GachaStatisticsSlimFactory` | **已接通**常规卡池。总览按完整抽取间隔计算均值，界面显示两位小数，UP 样本为空时显示 0.00。第五项倒计时与独立入口共用 `WishHistoryPage` 的 UP 期次。第六项全球祈愿统计保留五星经验分布说明。首页和祈愿页共用武器池五星 80 抽阈值，同总量记录更新时各池摘要重绘 |
| 颂愿模式、专属物品与子池 | `GachaLogPage.xaml:622–632`、`TypedWishSummaryBuilderContext`、`BeyondStandardStatisticsCard.xaml`、`PivotBeyondModeBehavior.cs` | **已接通**。颂愿模式只显示总览。常驻颂愿显示四星均值、四星 90 抽与三星 10 抽阈值、紫蓝品质摘要和其他星级数量。活动颂愿汇总活动子池，显示五星和四星摘要。专属物品通过 `BeyondItem.json` 读取名称和图标 |
| 祈愿显示开关 | `SettingPage.xaml:3161–3259`、`Service/AppOptions.cs:79–85`、`GachaStatisticsFactory` 和 `GachaStatisticsItemCounter`。控制空总览池、空期次、未抽到物品 | **已接通**。设置保存三项偏好，默认均关闭。`GachaLogPage` 读取总览空池开关，`GachaHistoryService.buildHistory` 按历史空期次开关组织期次，`GachaCollectionService.count` 按未获得物品开关生成角色和武器统计 |
| UIGF 导入导出 | `SettingGachaLogViewModel`、`UIGFImportDialog`、`UIGFExportDialog` 与 `Service/UIGF/` | **已接通入口，互通另审**。`GachaLogPage` 有版本选择、按 UID 勾选、预览和写入策略，`UigfCodec`、`UigfExportCodec`、`UigfImportTransfer` 已接线。分别验证 2.2–4.2 字段、颂愿组、时间转换和重复记录语义。Windows 选项无按池或日期范围过滤 |
| 成就、归档、外链与 UIAF | `AchievementViewModel` 有归档、文件/剪贴板 UIAF、未完成优先、委托过滤、名称/描述/ID/版本搜索、复制 ID、米游社/HoYoLAB 搜索 | **已接通**。`AchievementPage` 与 `AchievementService` 提供创建、切换和删除档案，文件及剪贴板 UIAF 导入、导出、汇总、搜索和未完成优先排序。各成就 ID 独立勾选、复制及搜索攻略。宽屏独立分类栏与窄屏分类入口共用筛选，档案或记录变化会刷新首页完成度。委托标记优先用官方 `IsDailyQuest`，旧数据由社区 `commissions` 补齐 |
| 我的角色详情与武器突破 | `AvatarPropertyViewModel.RefreshFromHoyolabGameRecordAsync`、`SummaryAvatarFactory`。详情涵盖武器、面板、命座、技能和圣遗物 | **已接通**。`CharacterViewModel` 与 `CharacterService` 有列表与详情。`PromoteState` 保留未知/未突破/已突破语义，`CalculateService.fillSyncedDetails` 匹配装备并补突破状态 |
| 角色筛选、排序、角色导出与规划 | `AvatarViewFilter` 包括名称、元素、武器、品质。`AvatarPropertySortDescriptions` 包括等级、品质、已激活命座、好感、生命、攻击、防御、精通。`AvatarPropertyViewModel` 有单个/全部文本导出和单个/批量养成 | **已接通**。`CharacterPage` 和 `CharacterViewModel` 提供名称、元素、武器和品质组合筛选，同组可多选。排序覆盖等级、品质、命座、好感和四项面板值，按面板基础值与加成之和比较。当前/全部文本导出、角色和武器规划及批量草稿可由本页进入 |
| 角色评分与离线背包评分 | `AvatarPropertyViewModel.ConfigureScoreCommand`、`AvatarReliquaryScoreSetting`、`BackpackViewModel.ConfigureScoreCommand`、`BackpackReliquaryScoreConfigDialog`、`BackpackSortComparer` | **已接通**。角色可分别选择米游社推荐、五个内置预设或任一已保存配置，已删除的配置回退至推荐。角色和背包共用 `ReliquaryScoreEditor`，确定后提交权重和删除操作。角色总分与导出使用所选算法，离线背包圣遗物可按分升降序排列 |

## 背包、养成、图鉴与挑战

| 功能 | Windows 源码 | 鸿蒙源码与结论 |
| --- | --- | --- |
| 离线背包、武器/圣遗物/材料、归档与筛选 | `BackpackPage.xaml` 和 `ViewModel/Backpack/BackpackViewModel.cs` 的归档、排序、`FilterCommand`。采集命令为 `RefreshByEmbeddedYaeCommand` | **部分**。`BackpackPage`、`BackpackViewModel`、`BackpackService`、`BackpackCatalog` 已有本地归档、筛选、排序、手动添加、UIIF 导入导出和项目库存同步。逐类 Windows 过滤口径和导入字段保真交专项，Yae 采集沿范围排除 |
| 养成计划、在线同步、离线计算、树脂 | `CultivationViewModel` 的 `AddProjectCommand`、`RemoveEntryCommand`、`FinishStateCommand`、`ModifyEntryCommand`、`SyncAvatarInfoByHoyolabGameRecordCommand`、`RefreshStatisticsItemsCommand` | **已接通主体**。`CultivationPage`、`CultivationViewModel`、`CultivationDraftViewModel`、`CultivationService`、`OfflineCultivationService`、`ResinStatisticsService` 支持项目、角色/武器目标、编辑、重新同步当前进度、材料和树脂估算。图鉴可直接创建角色/武器草稿 |
| 养成库存编辑、清空与同步 | `CultivationViewModel` 的 `SaveInventoryItemCommand`、`RefreshInventoryByCalculatorCommand`、`RefreshInventoryByBackpackArchiveCommand`、`ClearInventoryCommand`，`CultivationPage.xaml:948–962` 实际挂清空及同步 | **部分**。`CultivationPage` 有手工数量、导入库存、计算器同步。离线背包从 `BackpackPage.syncMaterials` 可推材料到选中的养成项目。缺确认后清空当前项目库存的直接操作，养成页也无选择背包档案的反向入口 |
| 角色资料、皮肤、资料筛选 | `WikiAvatarPage.xaml`、`WikiAvatarViewModel.CultivateCommand`、`AvatarFilter`（元素、势力、武器、品质、体型和名称） | **已接通**。`WikiAvatarPage` 与 `WikiMetaService` 有角色属性、技能、命座、材料、名片、立绘、皮肤、养成草稿和攻略外链。元素、势力、武器、品质及体型可同组多选，势力取 `FetterInfo.Association`。立绘翻页与筛选结果同步，窄屏返回保留筛选与选中项 |
| 武器与怪物资料 | `WikiWeaponPage.xaml`、`WikiMonsterPage.xaml`、`WeaponFilter`、`MonsterFilter` | **已接通**。武器页提供类型、品质、副属性组合筛选，等级滑条同时计算攻击和副属性。怪物页提供名称筛选、基础数值曲线、抗性、词缀和掉落物。两页窄屏返回保留搜索和选择，宽屏筛选后详情跟随可见条目 |
| 深境螺旋个人战绩 | `SpiralAbyssViewModel.LoadOverrideAsync`、`SpiralAbyssService.GetSpiralAbyssViewCollectionAsync`。`SpiralAbyssRecordPage.xaml:520–533` 分别绑定楼层选择及所选楼层内容 | **已接通**。进页恢复最近存档，手动刷新当期与上期。每期默认显示最高层，可独立选择该期的其他楼层。`TowerMetadataService` 为无本地战绩的期次显示祝福、层间与怪物波次。缓存刷新失败时保留战绩，排行显示出战次数和元素战技 |
| 幻想真境剧诗个人战绩 | `RoleCombatViewModel.LoadOverrideAsync`、`RoleCombatService.GetRoleCombatViewCollectionAsync`、`RoleCombatView.MaxRound`、`RoundView` | **本轮已补期次与字段对齐**。进页恢复本地存档，统一期次入口并显示限定元素、初始和特邀角色。补难度、圣牌计数、圣牌挑战幕、辉彩祝福摘要和各等级效果，显示全部已选卡牌 |
| 幽境危战个人战绩 | `HardChallengeViewModel.LoadOverrideAsync`、`HardChallengeView.Schedule` 与 `DataEntryView.Create` | **本轮已补期次与字段对齐**。增加本地国服 `HardChallengeSchedule.json`，正确换算期数、显示期次名和实际难度。仅有联机战绩时默认显示联机。怪物说明保留每条描述，官方人气角色独立获取 |

三页的 Windows 本地命令为刷新及账号洞察，战绩上传与云统计见范围核对。鸿蒙 `ChallengeSession` 校验当前国服角色及会话，切换后丢弃迟到响应。主机测试覆盖本地优先、未参战期次、刷新失败保留档案、多模式选择及元数据可选回退。 [ArkUI 自定义组件生命周期](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-page-custom-components-lifecycle/)

## 账号洞察、AI 与设置

| 功能 | Windows 源码 | 鸿蒙源码与结论 |
| --- | --- | --- |
| 账号洞察图表和匿名数据复制 | 五个入口调用 `AccountInsightsWindows.OpenAsync()`，窗口绑定当前角色，切换角色关闭。`AccountInsightsHistoryService.cs` 读取本地历史，`AccountInsightsWindow.Charts.cs` 和 `.Api.cs` 展示图表并复制匿名 JSON | **已接通**。`AccountInsightsPage` 固定并显示打开时的当前角色 UID，切换角色时保存会话并关闭。图表汇总该角色的本地祈愿、颂愿、深渊、剧诗和幽战，可独立复制去标识化 JSON。宽屏并列图表和会话，窄屏切换 |
| AI 会话工作区 | `AccountInsightsWindow.xaml:59–107` 挂载设置、生成和 `AgentWorkspaceView`。`MarkdownHelper.cs` 渲染 Markdown。`AgentConversationViewModel` 按会话持有生成命令，`AgentConversationTurnController` 保存会话与检查点 | **已接通**。会话分别保留草稿、流式输出、停止和审批状态，可在其他会话生成时切换并发送。关闭洞察会保存已收到的回复。正文用原生富文本、代码块和表格呈现，提供方返回的可见推理可展开。用户上滚后保持阅读位置。重生成复用最后一条用户消息，删除回选邻近会话 |
| AI 模型管理、实际工具与审批 | `AgentChatClientFactory.cs:28–30` 支持 OpenAI Chat Completions、OpenAI Responses、Anthropic。`AgentSettingsView.xaml` 与 `SettingsModelConfigurationViewModel` 管理多个提供方/模型、模型列表、连接测试、采样和 token 限额等。`AgentService.CreateBuiltInTools` 实际注册 `GetCurrentTime` 和 `ShowSummary`，都经批准 | **已接通**。`AiSettings` 支持三个协议、多提供方和模型、模型列表刷新、连接测试及参数设置。API 密钥由系统安全资产存储保存。`AiWorkspaceService` 支持这两项工具的批准和拒绝，保留端侧分析 |
| UI 语言及元数据文化 | `Service/CultureOptions.cs`、`SettingAppearanceViewModel.SelectedCulture` 和 `Resource/Localization/SH*.resx`（共 15 份）供设置选择及业务格式化 | **部分**。`AppLocaleService` 通过 `helpLocaleVersion` 驱动 `HelpPage`，`CommonOutcomeText` 有本地化子集。主 UI 的 `resources` 只有 `base`、`dark`、`rawfile`，导航与主要页面仍有大量中文硬编码。应从壳层、设置和任务页面接通语言，继续用国服数据端点 |
| 外观、壁纸、本地与官方背景视频 | `SettingAppearanceViewModel`、`BackgroundImageService`、`BackgroundMediaPlayerService`。视频源为本地目录及官方启动器公开源，支持静音和循环 | **已接通主要行为**。`WallpaperLayer`、`BackgroundMediaService.source`、`SettingPage.backgroundMediaSection` 有静态壁纸、背景视频、本地文件导入、官方视频、静音/循环。高级材质映射到 HarmonyOS 沉浸光感；Windows 专用折射和高光参数无直接映射 |
| 数据目录、缓存大小和静态资源重置 | `SettingStorageViewModel`、`SettingFolderViewModel`、`SettingStorageSetDataFolderOperation`。实际操作包括目录打开/迁移、占用、重置 `ImageCache` 和清理服务缓存 | **部分**。`BackupService` 有本地导出、恢复、启动恢复日志；`GameDataService`/`GameDataUpdater` 有完整数据更新与回滚。审计开始时 `SettingPage`/`MediaCacheService` 工作树已有可再生壁纸/远程图像/CDN 图标缓存统计清理。平台对应是沙盒安全的缓存和用户选择的导出/媒体文件；Windows 数据目录迁移和服务缓存按对应用途判断 |
| 应用更新、跳过与分发 | `MainViewModel` 启动检查，`UpdateService.TriggerUpdateAsync` 处理跳过、Store 或桌面更新器和 Mirror 酱源 | **部分**。`UpdatePage`、`UpdateViewModel`、`AppUpdateService` 提供手动检查、稳定/预发布选择、跳过、兼容性信息和打开发布说明。启动检查及自动提醒未接入。Windows 安装器、Microsoft Store 和 Mirror 酱桌面部署链属于平台专用实现 |
| 国服官方网页和分享 | `UserView.xaml:493,727` 旅行工具、`DailyJSBridgeUriSourceProvider` 角色验证、`SignInService.FallbackToWebView2SignInAsync`、`MiHoYoJSBridge`、`BridgeShare.cs:105–106` 和 `AppOptions.BridgeShareSaveType` | **已接通**。`OfficialWebPage` 使用与当前国服角色绑定的无痕 Web，接官方脚本的账号资料、请求头、分享及导航命令。图片 URL、Base64 图片和网页全量截图均按保存的分享方式处理，默认为复制，另存模式直接打开 PNG 文件选择器 |
| 本地帮助和诊断 | `FeedbackViewModel.CopyDeviceIdCommand` 与 `ExceptionWindow` 反馈绑定设备标识及 Sentry；Windows 反馈页也有帮助搜索 | **已接通本地对应**。`HelpPage`、`HelpViewModel`、`DocumentationSearchService` 有本地帮助、诊断预览和复制。`SupportService.previewDiagnostics` 用白名单收集版本/API/设备类型/主题及功能和错误类别。Windows 反馈上传和设备标识沿范围排除，无需据旧文档增加原始日志收集 |

官方网页的入口、无痕 Cookie、JS 权限和整页截图按 API 26 SDK 和华为当前文档核对。另存使用系统文档选择器和 PNG 编码，复制使用系统剪贴板的 PixelMap 类型。 [ArkWeb 控制器](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview-webviewcontroller/) · [无痕 Cookie](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview-webcookiemanager/) · [文件选择器](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-picker/) · [图片编码](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-image-imagepacker/) · [剪贴板](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-pasteboard/)

AI Markdown 使用 Marked 18.0.14 解析并由 ArkUI 渲染。图片转为可点链接，原始 HTML 按文本显示。 [Marked](https://github.com/markedjs/marked/releases/tag/v18.0.14) · [StyledString](https://developer.huawei.com/consumer/en/doc/harmonyos-references/ts-universal-styled-string/) · [Scroll](https://developer.huawei.com/consumer/en/doc/harmonyos-references/ts-container-scroll/)

## 范围核对

- `Service/Hutao`、`HutaoPassportPage`、`FeedbackPage`、`GachaLogHutaoCloudService`、`ViewModel/Complex/Hutao*DatabaseViewModel` 和 `AccountInsightsWindow.Gacha.cs` 的胡桃云登录、备份、统计、反馈、云攻略和战绩上传均排除。旧路线图的 B10 和 U10 混淆了直接外链与胡桃数据服务。鸿蒙 `WikiAvatarPage.openStrategy` 和 `CharacterPage` 已有米游社/B 站外链，`WikiAvatarStrategyComponent` 中用 `AvatarStrategyService` 获取的精确映射属于胡桃服务。
- `LaunchGamePage`、`Service/Game` 的游戏进程/安装/预下载/校验、游戏账号注册表操作、`Service/Yae` 的进程内存采集、`Service/Plugin` 和游戏内覆盖窗沿范围排除。鸿蒙保留 `GameLauncherService` 的系统应用唤起、离线背包和文件导入。
- 托盘与关窗语义、Windows 登录自启动、提权/桌面快捷方式、MS Store/MSIX、全局 Win32 键盘鼠标钩子与连发、`CompactWebView2Window` 独立覆盖窗、托盘里的 `ScriptingViewModel.ExecuteScriptAsync`（Roslyn `CSharpScript`、`AllowUnsafe`、Windows 进程上下文）属平台专用。应用内部焦点、菜单、返回、链接与视图布局仍可按可用交互适配。
- `UserViewModel` 的海外密码和第三方原生登录排除。鸿蒙现有 `LoginPage.regionSwitch` 和 `AnnouncementPage` 的境外公告选项与 `AGENTS.md` 当前国服口径有偏差。收紧可达的网络入口时保留既有本地档案和互通解析，具体数据修订由范围变更落地。
- Windows 一些跨域设置或内容需要分辨用途。`SettingPage` 的全局主/备 `ServerDomainMode` 针对胡桃后端，国服端点和可信静态源沿现有路径。`TestPage` 是开发页面，在 `MainView.xaml` 没有正式导航入口。

## 实施优先级

| 优先级 | 任务及最小落点 | 验收 |
| --- | --- | --- |
| P0 | 先校验数据正确性和既有档案可达。互通集中在 `UigfCodec`、`UigfExportCodec`、`UigfImportTransfer`、`AchievementService`、`UIIFService` 和现有页面入口。单独处理国服网络入口偏差 | 用 Windows 源码约定的实际文件做导入/导出回归。检查退出登录仍可读取档案，账号移除、重试、恢复及关闭功能后状态一致 |
| P1 | 祈愿三项显示偏好由 `PreferencesStore`、`SettingPage`、`GachaLogPage`、`GachaHistoryService` 接通。角色筛选、排序和评分已由 `CharacterPage` 与 `CharacterViewModel` 接通。`CultivationPage`、`CultivationViewModel`、`InventoryRepo` 补确认后清空当前项目 | 默认呈现保持一致。切换偏好影响对应统计和实际页面。确认清空只触及选中项目，计划条目保持可读 |
| P1 | 应用内与系统多目标调度和签到凭据续签已接通 | 主机已覆盖跨日、授权扩展、切号、删除、停用、凭据续签、Webhook、通知和桌面卡归属。真机检查实际系统排队及签到结果 |
| P1 | 账号洞察匿名 JSON 复制、三协议多轮流式、模型管理、工具审批和消息渲染已接通 | 主机覆盖并发会话、关闭保存、账号隔离、停止和重生成、删除回选、模型测试、工具审批、Markdown 及匿名统计。真机检查角色切换、流式滚动、表格和剪贴板 |
| P2 | UI 本地化按已有 Windows 语言资源和 HarmonyOS `AppLocaleService` 分批接页面。设置锚点和可达性、项目库存反向入口、启动应用更新检查和资源重连分别落在已有功能域 | 核查新入口与保存设置确实驱动相应页面或业务路径。验证手机、平板、2in1 的窗口布局和交互。视觉对齐以现有材质、动效和多端断点规范为准 |
