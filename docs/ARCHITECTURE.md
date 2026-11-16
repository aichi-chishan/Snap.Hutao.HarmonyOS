# 工程架构

本文按当前源码说明入口、状态和数据归属，供修改与交接时查找实现。项目使用 HarmonyOS Stage 模型、ArkTS/ArkUI，API 26 起支持 phone、tablet、2in1；Windows 对齐源码位于本机独立仓 `Snap.Hutao.Remastered-latest/`。功能边界和开发约定以 [AGENTS.md](../AGENTS.md) 为准。

## 仓库与应用入口

```text
AppScope/                         应用标识、版本、应用图标
entry/
  build-profile.json5             entry 模块构建设置
  oh-package.json5                模块依赖
  src/main/
    module.json5                  Ability/Extension、设备类型、权限、材质声明
    ets/
      entryability/               主 UIAbility 与窗口生命周期
      entrybackupability/         系统备份扩展
      background/                 WorkScheduler 扩展入口
      pages/                      路由页、宽屏嵌入页
      components/                 页面壳、领域卡片、编辑器、对话框
      viewmodel/                  页面/编辑器的可观察状态与异步编排
      service/                    业务请求、聚合、计算、文件互通
      data/
        db/                       主 SQLite 库初始化与迁移
        repo/                     业务 CRUD、后台任务租约
        prefs/                    应用偏好
        local/                    凭据、AI 会话文件、桌面卡片快照
        network/                  HTTP、签名、登录、风控、AI 协议
        remote/                   元数据快照、更新器、静态图标缓存
        taskpool/                 祈愿统计与 UIGF 导入计算
        help/                     离线帮助目录和各语言正文
        markdown/                 AI 富文本解析
      model/                      数据模型、解析器、筛选/协议/数值规则
      common/                     上下文、端点、日志、日期、动效、材质、评分
      widgets/                    FormExtensionAbility 与桌面卡片页面
    resources/
      base/profile/               路由、备份、桌面卡片配置
      base|dark/element/          界面文案和深浅主题色
      <语言>/element/             界面翻译
      rawfile/                    游戏元数据、图标、图鉴资源及素材来源
  src/test/                       ArkTS 本地测试
  src/ohosTest/                   设备侧测试工程
  src/mock/                       测试替身配置
scripts/                          元数据投影、翻译/数值参考生成、资源获取
tests/                            执行生产逻辑的 Node/SQLite 回归与夹具
ci/                               固定测试编译器、构建基线、工具与产物检查
.github/workflows/ci.yml           主机回归、仓库门禁、原生 lint、HAP 构建
docs/                             架构及专项协议/验证说明
tools/                            离线帮助翻译源与生成工具
hvigor/、hvigorfile.ts             Hvigor 工程配置
oh-package*.json5                 工程依赖与锁定文件
```

本地 `build-profile.json5` 含签名配置，不入库；无签名的可复现基线是 [ci/build-profile.ci.json5](../ci/build-profile.ci.json5)。`.local/`、`.agents/`、参考截图和两个独立源码/数据仓用于开发，不是运行时依赖。

[module.json5](../entry/src/main/module.json5) 注册四个运行入口：

| 入口 | 实现 | 责任 |
| --- | --- | --- |
| 主应用 | `ets/entryability/EntryAbility.ets` | 初始化本地运行环境、加载 `pages/Index`、处理窗口/主题/前后台、挂载全局风控浮层 |
| 系统调度 | `ets/background/HutaoWorkSchedulerExtensionAbility.ets` | 将系统回调交给 `BackgroundTaskService` 执行便笺/签到任务 |
| 桌面卡片 | `ets/widgets/DailyNoteFormExtensionAbility.ets` | 发布已校验归属的缓存快照；处理用户点击刷新 |
| 系统备份 | `ets/entrybackupability/EntryBackupAbility.ets` | 接入系统备份/恢复生命周期 |

`EntryAbility.prepareRuntime()` 依次准备应用上下文、偏好、材质、主库与后台任务库，安装账号失效回调，恢复中断的本地还原，再恢复账号及固定游戏数据快照。`Index` 挂载后才启动 Cookie 维护、通知和前台签到/便笺调度。初始化失败进入 `StartupErrorPage`，重试复用同一初始化链。

## 导航、状态与实际分工

[Index.ets](../entry/src/main/ets/pages/Index.ets) 持有导航索引、首页展示快照和壳层尺寸；宽屏通过 `wideContent()` 嵌入各页，手机通过 `HdsTabs` 与路由页进入功能。`GachaLogPage.ets`、`DailyNotePage.ets` 是被壳层嵌入的组件；可独立路由的页面登记在 [main_pages.json](../entry/src/main/resources/base/profile/main_pages.json)。侧栏底部 `SidebarAccountSwitcher` 复用 `UserViewModel`，完整账号页仍是 `UserPage`。

常用调用链是 `Page/Component → ViewModel → Service → Repo/Network → Model`。各层在当前工程中的具体责任如下：

- `pages/components` 处理布局、交互、Picker、剪贴板、Web、截图等平台 UI；调用业务方法后更新显示。
- `viewmodel` 聚合加载状态、选择、筛选、分页与操作结果。多数使用 `@Observed`，由页面 `@State` 持有。
- `service` 组织网络、数据投影和计算；需要保存的领域调用 `data/repo`。`ApiClient` 管 HTTP，`HoyolabClient`、`DsSigner`、`RiskVerifier` 管米游社协议和重放。
- `model` 同时包含 API/存档模型、`fromJson` 解析和纯规则，例如祈愿池、养成筛选、评分、语言与备份校验。

图鉴三页、成就页和设置页将选择/加载状态直接保存在页面中，并调用对应服务；公告详情也直接使用服务。修改这些页面应沿现有调用链定位，不能假定每页都有独立 ViewModel。桌面卡片使用 `@ComponentV2/@Local`，其余主体页面使用 V1 状态管理。

## 业务模块索引

表内文件名均位于 `entry/src/main/ets/` 的对应目录；正常入口指当前可见导航或菜单。

| 功能与入口 | 展示状态、业务实现 | 数据来源与持久化 |
| --- | --- | --- |
| 首页：侧栏首页/手机首页 | `pages/Index`、`components/Home*Card`、`viewmodel/HomeViewModel` | 先读取祈愿和全部追踪便笺缓存，再独立加载签到、活动、公告；卡片显隐/顺序来自 `PreferencesStore`。公告保留完整分类，活动与复合卡池来自 `CalendarService` |
| 本地账号与登录：侧栏头像/完整账号页 | `UserPage`、`LoginPage`；`UserViewModel`、`LoginViewModel`；`UserService`、`PassportClient`、`RoleProfilePictureService` | `UserRepo` 保存账号/角色资料，`TokenVault` 用 Asset Store 保存 Cookie；当前账号、默认 UID、顺序等存在偏好中。角色头像走本地缓存和独立的公开资料客户端 |
| 风控：需要验证的手动操作 | `RiskVerifyModal`、`RiskVerifyService`；兜底 `GeetestVerifyPage` | `EntryAbility` 挂窗口级浮层，服务等待 Promise；`RiskVerifier`、`RiskUiHelper` 按请求类型重放。验证结果不作为长期用户数据保存 |
| 祈愿/颂愿：侧栏祈愿记录/手机祈愿 | `GachaLogPage`、`GachaLogViewModel`；`GachaLogService`、`GachaHistoryService`、`GachaStatisticsService`、`GachaCollectionService` | `GachaRepo` 保存 UID 归档与记录；URL/账号凭据刷新经 `GachaAuthApi`，统计由本地记录和卡池元数据计算，重计算使用 `data/taskpool/StatsComputer` |
| 祈愿文件互通：祈愿工具菜单 | `GachaLogViewModel`；`UigfService`、`UigfCodec`、`UigfExportCodec`、`UigfImportJob/Transfer` | 文件选择/剪贴板在页面，解析准备与用户选择后写 `GachaRepo`；大文件由 `UigfImportWorker` 处理，保留取消与提交边界 |
| 历史 UP：祈愿菜单 | `WishHistoryPage`、`WishHistoryViewModel`、`WishHistoryService` | 读取 `GachaEvent`、角色/武器本地元数据，查询轮次与历史间隔；与个人祈愿归档分开 |
| 成就：侧栏成就管理/首页卡片 | `AchievementPage` 页面状态、`AchievementService` | `AchievementRepo` 保存多归档、状态/进度/时间；目录来自元数据。UIAF 文件/剪贴板导入导出在本地执行 |
| 实时便笺：侧栏/手机便笺/首页卡片 | `DailyNotePage`、`HomeDailyNoteCard`；`DailyNoteViewModel`、`DailyNoteService`、`DailyNoteReminderService` | `DailyNoteRepo` 按本地账号 ID + UID 保存；偏好保存各账号追踪 UID、刷新间隔、逐 UID 阈值及通知/Webhook 选项；首页与完整页共享追踪记录 |
| 每日签到：首页签到卡/入口 | `SignInPage`、`SignInViewModel`、`SignInService`、`AutoSignInService` | 手动链路捕获账号上下文并支持验证；前台开关、每日运行标记在偏好中，系统任务结果/租约在后台库；官方签到页作为手动兜底 |
| 活动与周历：首页活动/卡池/日历卡 | `CalendarPage`、`CalendarViewModel`；`CalendarService`、`CalendarWeekService`、`GameCalendarRules` | 活动由当前国服角色接口读取；周历结合本地材料轮换/生日与所选服务器时间。页面持有日期选择，周起始日/显示选项存偏好 |
| 公告：首页三分类/公告入口 | `HomeAnnouncementCard`、`AnnouncementPage/DetailPage`、`AnnouncementViewModel`、`AnnouncementService` | 服务按区服/语言/等级缓存列表与正文；详情携带条目自身上下文，不依赖打开详情时的另一个账号 |
| 旅行札记：首页札记卡 | `LedgerPage`、`LedgerViewModel`、`LedgerService` | 国服米游社月度接口；页面持有选中月份及结果 |
| 我的角色：侧栏/首页工具入口 | `CharacterPage`、`CharacterViewModel`、`CharacterFilter`；`CharacterService`、`SkillLevelService`、`common/ReliquaryScore`、`CharacterExportService` | 米游社列表/分批详情，按 UID 缓存到 `PreferencesStore`；本地计算属性和评分，支持筛选、比较、UGC 卡片与数据导出 |
| 离线背包：侧栏背包物品 | `BackpackPage`、`BackpackViewModel`；`BackpackService`、`BackpackScoreService`、`UIIFService` | `BackpackRepo` 保存手动/导入的材料、武器、圣遗物归档；UIIF 由页面预览确认后导入导出，评分配置与选项使用偏好，可向养成库存同步 |
| 养成计划：侧栏/角色或图鉴加入计划 | `CultivationPage`、`CultivationViewModel`、`CultivationDraftViewModel/Editor`；`CultivationService`、`CalculateService`、`OfflineCultivationService`、`ResinStatisticsService` | `CultivationRepo` 保存项目、目标及材料，`InventoryRepo/Service` 保存养成库存；在线计算接口与本地消耗表共用草稿模型，离线背包可作为库存来源 |
| 深境螺旋、幻想真境剧诗、幽境危战：侧栏周期 | `SpiralAbyss/RoleCombat/HardChallengePage` 与同名 `ViewModel`、`Service`；`ChallengePeriodRail`、`TowerMetadataService` | 同名 `Repo` 按 UID/区服/期次存原始 JSON，切期从本地重建详情；网络刷新、期次/难度/层选择、统计与复制由各领域实现 |
| 账号洞察与 AI：祈愿/三挑战工具栏、设置 | `AccountInsightsPage`、`AccountInsightsService`；`AiWorkspace/AiMarkdown`、`AiWorkspaceViewModel`、`AiWorkspaceService`、`AiAnalysisService` | 洞察从祈愿与挑战 Repo 聚合；AI 可用系统端侧模型或用户配置的 API。`AiWorkspaceStore` 按 UID 保存会话 JSON、提供商/模型设置，API Key 存 Asset Store |
| 角色/武器/怪物资料：侧栏数据组 | `WikiAvatar/Weapon/MonsterPage` 页面状态；`WikiMetaService`、`BaseValueService`、`AvatarSkillParameterService`、`WikiAvatarFilter/Guide` | 本地/已验证快照元数据及语言叠加；图标、突破图、立绘共用资源链。图鉴加入计划使用 `CultivationDraftViewModel`；怪物额外掉落使用独立可选表 |
| 国服官方 Web：账号工具箱、便笺/签到入口 | `OfficialWebPage`、`OfficialWebViewModel`、`OfficialWebBridgeService`、`OfficialWebShareService` | 绑定打开时的账号上下文，仅注册指定官方来源/命令；分享图按持久偏好复制或另存，账号切换使旧桥失效 |
| 兑换码：主页浮层、公告页 | `Index`、`AnnouncementPage`、`MiyoliveService` | 读取公开直播活动及兑换码，用户点击复制；列表与加载状态由页面持有 |
| 公开游戏入口：首页/侧栏启动游戏 | `LaunchGamePage`、`HomeLaunchCard`、`GameLauncherService` | 用户配置公开链接或 Bundle/Ability，调用系统启动能力；配置存偏好 |
| 设置与维护：侧栏设置/手机账号页 | `SettingPage`、`AiSettings`、`BackgroundTaskSettingsViewModel`；`BackupService`、`MediaCacheService`、`BackgroundMediaService` | 主题/语言/首页/祈愿/分享偏好、任务开关、媒体导入和可再生缓存管理；本地备份/还原由 `BackupSnapshot/LegacyBackup` 校验并协调各存储 |
| 数据更新、应用更新、帮助：设置菜单 | `GameDataService`；`UpdatePage/UpdateViewModel/AppUpdateService`；`HelpPage/HelpViewModel/DocumentationSearchService/SupportService` | 游戏数据通过快照链更新；应用更新检查后交给公开下载/发布入口；帮助读取 `data/help` 离线目录，诊断摘要由用户预览后复制 |
| 胡桃通行证与云、五星经验分布 | `HutaoCloudPage` 和祈愿页说明占位 | 说明入口；不连接胡桃云账号、备份或统计服务 |

## 数据和运行状态的边界

**账号。** `UserService` 持有已提交的账号对象、当前 UID、会话 revision 和切换事务队列；`AppStorage.currentUserId/currentUid/currentUserName/currentUserAvatar` 是给 UI 的发布值。请求在开始时固定账号/UID/revision，`ChallengeSession`、各 VM 的 generation 或任务 guard 在返回前确认归属。跨账号便笺/签到按记录所属账号执行，不通过切换当前 UI 账号完成。

**持久化。** [RelationalStoreHelper](../entry/src/main/ets/data/db/RelationalStoreHelper.ets) 管 `snap_hutao.db` 及有序迁移，Repo 管业务表；`BackgroundTaskRepo` 单独管理 `hutao_background/snap_hutao_background.db`，保存任务状态、epoch 与操作租约。`PreferencesStore` 使用 `snap_hutao_prefs`，承载设置及部分按 UID 的 JSON 缓存。账号 Cookie 经 `TokenVault` 放入系统 Asset Store。AI 设置/会话在 `filesDir/ai-workspace`，用户导入视频在 `filesDir/background-video`；这些与可清理的 `cacheDir` 图标/媒体缓存分开。签到、活动、公告当前显示由服务/VM 读取，主库仍保留相关历史表结构。

**后台与桌面卡片。** `BackgroundTaskService` 为便笺和签到各维护一种系统调度任务，运行时枚举相应追踪记录/已存国服角色；前台定时器复用服务与按账号/UID 的操作租约。关闭开关、移除账号、还原或切换会话会使旧 guard 失效。`FormSnapshot` 只保存展示字段和所属账号/UID/epoch；`DailyNoteService` 验证后向 `widgets/pages/DailyNoteCard` 推送，卡片本身不持有登录凭据。详细策略见 [后台任务](NATIVE_BACKGROUND_TASKS_2026-10-05.md)。

**文件互通与恢复。** 导入先解析/校验，再由用户选择目标或策略，提交时再校验当前状态；业务数据写入事务由对应 Repo 或 `BackupService` 管理。完整还原同时涉及主库、偏好和 Asset Store，使用恢复日志并在启动时处理未完成操作。参见 [备份格式](BACKUP_FORMAT.md)、[文件互通](FILE_INTEROP_2026-11-11.md)及[账号与数据移植](PORTING_ACCOUNT_DATA_2026-11-11.md)。

## 元数据、图片与本地化

`resources/rawfile/metadata/` 包含角色、武器、怪物、材料、曲线、成就、卡池和挑战期次等基础表；`locale_*.json` 是文字叠加，`avatar_skill_*.json` 是技能等级/参数目录。界面资源语言与游戏文本经 `AppLocaleService`、`LocalePolicy` 对齐，`LocalizedGameDataService` 将 `GameTextCatalog` 叠加在新解析的基础对象上；身份、图标和数值继续来自基础表。`WikiMetaService` 按当前语言缓存投影，切换语言后页面保留选中身份并重读文字。详见 [本地化游戏数据](LOCALIZED_GAME_DATA_2026-11-11.md)。

[GameDataService](../entry/src/main/ets/service/GameDataService.ets) 统一读取当前进程固定的元数据快照，缺少可选表时回退随包文件；`GameDataUpdater`、`GameDataManifestPolicy`、`GameDataSnapshotStore/Worker` 管可信仓库清单、不可变提交、校验、暂存、取消和发布。当前进程保持已选快照，新发布版本在后续启动选择，避免一次计算混用两代基础表。

`MetaIcon` 以 `category/name` 解析图标，先读已更新图标，再读随包 rawfile 并缓存到沙盒；缺图时可显式走静态 CDN。`StandardIconService` 管公共 PNG 缓存与固定来源，`CachedImageService` 管远程横幅图片；大立绘由相应图鉴组件按真实类别读取。`HutaoDailyImageService`、`BackgroundMediaService`、`WallpaperLayer` 管每日壁纸、本地图片/视频和背景生命周期，清理由 `MediaCacheService` 的固定目录白名单执行。

生成链在 `scripts/`：`update-compact-metadata.py` 投影基础数据及怪物 DisplayItem 掉落，`generate-game-locales.py` 生成游戏语言叠加，技能、背包/评分和角色攻略参考各有对应生成脚本，`fetch-metadata-icons.py` 获取真实素材。生成输入是经核实的本地 Snap.Metadata 快照；`tools/help-locales/*.json` 与 `tools/render-help-locales.cjs` 维护离线帮助。资源来源/许可证随专用资源保留，例如 `rawfile/wiki/weapon` 和 `rawfile/wiki/monster`。

## 响应式布局与共用 UI

- `Index` 按窗口宽度 **720vp** 切换侧栏壳与手机页签；内嵌页面按自身内容宽度 **840vp** 切换列表/详情双栏或单栏返回；首页在 **1200vp** 扩展列数。尺寸由各根容器 `onAreaChange` 发布，不拿整屏宽度替代内嵌区宽度。
- `EntryAbility` 管理窗口避让区、系统标题按钮区和 `appForeground`；`Index` 负责嵌入页的统一顶部避让，独立页通过 `PageHeader/PageToolbar` 使用自身返回栏。`embedMode` 决定壳层职责。
- `UiSurface` 定义 `SHELL_NAV`、`FLOATING_BAR`、`OVERLAY_MODAL`、`CONTENT_SURFACE` 槽位；`materialMode/materialLevel` 由偏好发布到 `AppStorage`，组件用 `@StorageProp` 参与刷新。内容卡片用 `CardSurfaceModifier`，普通按钮用 `AppButtonModifier`，原生选择控件使用对应材质 modifier；系统菜单/弹窗参数统一从 `UiSurface` 取值。
- 文字和背景颜色来自资源，深色状态由 `EntryAbility` 发布 `isDarkMode`；动画和减少动态效果走 `Motion`。`QTapButton`、`PageToolbar`、`PageContainer`、`PressCard`、`MetaIcon` 是常用落点。动态文案直接读取组件状态，避免多参数 `@Builder` 造成初始值滞留。

## 验证与继续维护

`tests/run.cjs` 自动发现 `tests/` 下所有 `.cjs/.mjs`，另执行 `scripts/test-challenge-regressions.cjs`；它们转译/加载生产代码，并替换系统边界，部分使用 SQLite 检查实际读写。`entry/src/test`、`entry/src/ohosTest` 是 ArkTS 本地/设备测试入口。新增主机套件无需维护手工总清单。

CI 使用 `ci/package-lock.json` 固定测试编译器；原生 lint 经 `ci/run-native-lint.cjs` 与 `check-lint-report.cjs` 检查完整报告，HAP 经 `check-hap.py` 检查产物，官方工具下载由 `install-clt.sh/verify-clt.py` 校验。原生 lint/构建 job 依赖已配置的工具下载变量。构建、测试命令与设备检查见 [AGENTS.md](../AGENTS.md) 和 [测试说明](TESTING.md)；变更模块时优先运行其领域套件，再进行统一 ArkTS/HAP 编译和实际交互验证。
