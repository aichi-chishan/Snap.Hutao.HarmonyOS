# 背景媒体与窗口生命周期修复（2026-11-11）

对照 Remastered `3b7475e` 的 `BackgroundImageService`、`BackgroundMediaPlayerService`、`BackgroundMediaPlaybackController`，并核对华为官方文档与本机 API 26 SDK。

2026-11-12 Windows 视觉基准对齐：已读取用户首页参考以及 `.local/windows-reference-2026-11-12/wish.png`、`wiki-avatar.png`。壁纸移除全图模糊、降饱和与提亮，保留来源、缓存、轮换及亮度透明度；磨砂集中在 `UiSurface.surfaceEffect`，以单一 `backgroundEffect` 包含模糊和资源色，避免预设蒙版与不透明底色重复叠加。Index 的状态栏背景、顶带和侧栏共用轻透 `SHELL_NAV`，两区域不相叠、无接缝阴影，前景仍保留已在平板验证的 `topAvoidVp`。侧栏增加小内边距，中性选中底色保留细强调指示条。

普通动作按钮统一由 `AppButtonModifier.CORNER_RADIUS = 6` 定义圆角，使用独立 borderWidth/borderColor 避免 border 聚合写回覆盖圆角；第四个可选参数 `capsule` 仅供明确的胶囊变体。QTap 移除本地 22/12 圆角覆盖，登录三个主按钮统一 44vp，刷新二维码和获取验证码复用次动作样式；登录事件和禁用行为不变。业务页的筛选 chip、图标、页签由其他负责人保留各自语义。本责任域没有修改首页活动区/仪表卡布局，也没有自行构建或操作设备。

待主对话协调的共享调用：`RiskVerifyModal.ets` 在 `OverlaySurfaceModifier` 后仍有旧 `backgroundBlurStyle` 覆盖，可仅移除该额外材质调用，不改风控逻辑。截图里的方角来自 11-11 22:26 构建产物的 border 覆盖圆角顺序；22:47 源码已有顺序修复，最新单点圆角样式还需统一包真机复验。依据：[背景效果 API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/ts-universal-attributes-background/)、[Button 类型与边框顺序](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-button/)、[系统沉浸材质生效范围](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-image-effect/)。

2026-11-12 便笺真机对齐：`DailyNoteTrackedEntry` 从所属 `UserGameRole` 投影 nickname/region/level，`NoteCardEntry` 保留相同 userId+uid 归属；当前角色也使用该投影，卡头显示“角色昵称 | 天空岛/世界树 | Lv.等级”，缺失信息只回退真实 UID。卡轨宽从固定 300vp 调到 308vp，扣除两侧 padding 8 和边框后仍满足两列派遣的 2×140+6=286vp，窄屏保持一列卡轨及派遣按实测宽度自适应。两种线形进度显式设 `strokeRadius: 4`，避免默认半行高的大圆头；已明确全部完成的任务行填满。追踪添加/移除流程及网络刷新协议未改。

便笺新增 `tests/daily-note-card.cjs` 5 项通过，原 `daily-note-tracking` 3 项及背景任务跨账号归属、首页便笺回归通过。待真机：刷新后检查角色昵称/区服/Lv，五个派遣以 2+2+1 排列，进度底色端部为小圆角。依据：[原生 LinearStyleOptions](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-progress/)。

2026-11-12 魔神任务进度：从指定 Snap.Metadata `fb3e269` 快照生成可选 `Chapter.json`，保留 54 个 AQ 的原始顺序，含空文案的 2015；章节 1705 对应 52/54。`ArchonQuestChapter` 保存接口 ID，并沿用既有 `raw_json` / `archon_json` 读写。ViewModel 经 `LocalizedGameDataService` 读取章节，按首条接口 ID 的真实索引投影进度；接口显式空列表为 54/54，未知 ID、缺 ID 的旧缓存和元数据缺失时保留已有文案并隐藏进度。`hasArchonQuestProgress` 区分未提供数据和已返回列表；无法确认来源的旧空数组保持未知。移除刷新后的 prefs 重复写入，旧 prefs 保留只读兼容。15 个语言包仅增加 Number/Title 覆盖，应用内语言切换重读投影，晚到结果不覆盖当前语言。未增加缓存服务或数据库迁移。

该项主机回归：新增 `daily-note-archon` 8 项通过（真实 52/54、空列表、未知 ID、旧缓存、实际 Repo 持久化往返、旧 prefs、语言切换及晚到结果、元数据缺失）；便笺卡片 5 项、追踪 3 项、首页便笺 5 项及背景任务、后台持久化、UI 平台契约均通过。元数据快照 58 项、语言 24 项及生成一致性检查通过，独立只读复核通过。章节和语言资源合计增加 78,871 字节，原有语言表内容保持不变。原生构建及真机检查仍由主对话统一执行。

语言通知交接：全局系统语言跟随由主对话统一处理；AQ 沿用 `helpLocaleVersion` 通知，不另设系统监听。

2026-11-12 前台便笺自动刷新：`DailyNoteService` 统一复用按所属账号读取的追踪列表，启动、回前台和定时触发都只请求过期或尚无缓存的条目，不再先单独刷新 currentUid，也不新增追踪。缓存年龄按 `(userId, uid)` 区分，单项读取失败记录首个错误并继续其余角色；手动刷新仍强制刷新，自动请求不触发凭据补齐或验证界面。当前角色在身份匹配时使用选中实例，保证数据库重建的账号对象不会阻断桌面卡更新。

`setForeground(false)` 同步清除前台 interval 并递增自动刷新 revision，既有 owner guard 同时检查本批有效性，防止已停止批次继续派发请求、写回或发布结果。手动/自动刷新共用一个结算 Promise；快速回前台等待旧请求退出后补扫，同代重复触发合并。只有实际取得锁并通过会话/备份门控才记为已补扫，主对话已在既有会话完成回调补调 `bootstrapAutoRefresh()`。EntryAbility 在页面和 overlay 加载后启动维护，前台设 true 后 bootstrap，后台/销毁设 false；显式 OS 后台任务继续走独立 `refreshBackground`。

依据：Windows `Service/DailyNote/DailyNoteService.cs` 的首次集合加载按每条 `RefreshTime` 与用户间隔筛选；其 Quartz 周期任务本身是全量强刷，本次按鸿蒙需求将逐条过期判断用于所有自动触发。华为 [UIAbility 生命周期说明](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/uiability-lifecycle/) 要求后台回调保持轻量并释放不再需要的前台资源，本实现只同步停表和失效批次。

本阶段验证冻结：`tests/daily-note-auto-refresh.cjs` 19 项真实服务行为回归通过，涵盖冷启动、晚到后台初始化、多账号同 UID、未追踪当前角色、过期筛选、网络/写入取消、快速重入、手动成功/失败锁释放、门控解除补扫、单缓存失败及 OS 后台独立性。既有后台任务、后台持久化、追踪 3 项、首页便笺 5 项及 UI 平台契约回归通过，独立源码复核通过。公共回归曾因并发语言改动的测试替身缺 `isReady()` 暂停；主对话补齐后已复验通过。AQ 保持前阶段冻结，构建/装机由主对话统一执行。

- `WallpaperLayer`：递归枚举改为异步；图片按轮次取出，耗尽再扫描，新一轮避开上一张；保留五分钟轮换及浅色 `L` / 深色 `1-L` 不透明度。解码、读像素失败也分别等待 PixelMap 与 ImageSource 释放。换来源、换目录和组件退出都会使旧结果失效。本地路径通过 `fileUri.getUriFromPath` 转换；读取原 Picker URI 前检查并激活已有持久只读授权。
- `BackgroundVideoLayer`：每次来源变更创建独立控制器，以请求编号作为 Video 节点键。准备完成、前台、可见三个条件共同控制播放；关闭自动播放，离开时停止旧播放器，旧来源的准备、错误和开始事件不影响当前来源。背景视频延伸至系统安全区。
- `BackgroundMediaService`：保留上游指定活动 WebM 到 MP4 的映射；仅选择国服原神可播放视频。官方视频优先缓存、下载失败回退 HTTPS。本地导入保留 MP4/MKV/TS 扩展名，异步复制并关闭 FD；整批成功才替换列表，失败只清理本批创建的副本。
- `MediaCacheService`、`CachedImageService`、`HutaoDailyImageService`：复用下载逻辑，RCP 直接写暂存文件，关闭请求后发布完整文件。完整 URL 的 SHA-256 避免横幅缓存键冲突；命中时检查文件；同一来源合并并发请求，日图缓存同时保留署名与出处。清理保留既有固定目录白名单、逐文件删除和跳过符号链接的实现；清理前的下载不能重新发布，完成后发出 `mediaCacheVersion`。
- `EntryAbility`：在 `onWindowStageWillDestroy` 中解除本 Ability 的两类窗口监听，移除并 dispose 全局浮层；通过现有 `RiskVerifyService.cancel()` 结束已登记的验证等待及超时。仅拥有活动窗口时取消，首次创建和重复清理不影响新请求。初始化、loadContent、全屏配置的晚到回调检查所属窗口。窗口尺寸直接指定 `PixelUnit.VP`；规避区用当前 UIContext 的 px2vp，标题三键矩形直接使用 SDK 返回的 vp。处理 setWindowLimits 的异步失败，保持不透明窗口底色在全屏布局完成后设置。

`PageBackdrop` 的 embed 模式已经跳过重复壁纸，未改变其接线。本责任域保留账号/后台任务服务、材质和风控服务实现；新增启动失败门控与窗口验证取消见下文。

壁纸出处接口复核：`HutaoDailyImage.sourceUrl` 在网络结果及缓存读写往返中保持原值，包含中文、百分号编码、查询参数和片段的链接已验证。作者/链接缺失、null 或空串不阻断图片；旧缓存缺少或损坏署名 JSON 时继续返回图片，署名及链接为空。媒体服务新增两项回归并加强原有往返用例，相关媒体/壁纸/清理共 21 项通过；服务接口无需修改，设置页直接消费结果即可。

跨模块接线状态：

1. 已接入：`SettingPage.pickBgFolder()` 对 Picker 原始 URI 调用只读 `persistPermission`，成功后保存；失败保留旧持久配置，并提示当前选择只在本次可用。`module.json5` 已声明 `ohos.permission.FILE_ACCESS_PERSIST`，与壁纸读取侧的激活逻辑衔接。
2. 视频选择器：`options.fileSuffixFilters = ['视频|' + BackgroundMediaService.VIDEO_EXTENSIONS.join(',')]`，与服务允许的 `.mp4,.mkv,.ts` 一致。
3. `GachaLogPage`、`WishHistoryPage` 的 `bannerPaths`：观察 `mediaCacheVersion` 后清除保存的本地路径，废弃清理前仍在执行的预加载结果，下次需要横幅时按需读取；清缓存本身不立即重下载。

目录授权的精确调用（设置页使用 Picker 原始 URI，不转换为路径）：

```ts
import { fileShare } from '@kit.CoreFileKit';

const policy: fileShare.PolicyInfo = {
  uri: uris[0],
  operationMode: fileShare.OperationMode.READ_MODE,
};
await fileShare.persistPermission([policy]);
```

`persistPermission` 与 `activatePermission` 均返回 `Promise<void>`；失败通过异常返回。持久授权能力为 `SystemCapability.FileManagement.AppFileService.FolderAuthorization`；选目录能力为 `SystemCapability.FileManagement.UserFileService.FolderSelection`。`module.requestPermissions` 增加 `{ "name": "ohos.permission.FILE_ACCESS_PERSIST" }`。该权限为 system_grant，不在此流程额外弹动态权限申请；不支持或持久化失败时可保留本次临时使用，但提示重新启动后需要重选。壁纸读取侧通过 `checkPersistentPermission([policy]): Promise<boolean[]>` 检查，再按需 `activatePermission([policy])`。

验证：首批壁纸 9、视频组件 3、窗口 3、媒体服务 7 项主机测试，加上已有媒体清理 3 项、UI/祈愿相关 16 项全部通过；既有 `motion-consumers` 回归通过。记录在 `.local/background-window-tests-2026-11-11.log`。上一检查点的联合 HAP 已 `BUILD SUCCESSFUL`，日志 `.local/build-joint-2026-11-11-fixed.log`；当前窗口/启动 UI 检查点等待主对话统一构建调试包。本对话未操作设备。

联合回归后补正 `reduce-motion.cjs` 的冷启动夹具：显式关联活动 WindowStage，并逐次验证页面确实加载，避免用上一轮残留值误判通过；无障碍标签断言同步到本地化资源。窗口、动效、后台设置和数据页的六个相关套件全部通过，日志 `.local/background-window-boundaries-2026-11-11.log`。

窗口验证取消追加 2 项真实服务回归：已显示的 GT 验证关窗立即返回空结果并清除定时器；未挂载浮层时的 aigis 等待也会结束，重建后的新请求不受旧回调或重复清理影响。窗口套件现为 5 项，与风控、减少动态效果、后台设置、数据页、动效消费者六个相关套件全部通过，日志 `.local/background-window-risk-teardown-2026-11-11.log`。

交由主对话处理的服务边界：`verifyGtFull` / `verifyAigis` 尚在 `await tryCustomSolve`、未进入 `show()` 时没有登记 pending，窗口侧一次 `cancel()` 无法使该前置调用失效；晚到结果仍可能继续返回或弹窗。本批按分工未修改 Risk 服务实现。

启动失败 UX：Windows 的 `Core/DependencyInjection/ServiceCollectionExtension.cs` 在数据库迁移失败时显示警告并退出，`Core/LifeCycle/AppActivation.cs` 的核心初始化异常也会显示错误并退出；没有绕过数据库直接使用图鉴的启动路径。鸿蒙增加独立 `StartupErrorPage`：核心初始化或页面加载失败时显示错误与重试，成功后才加载 Index、配置窗口和挂载验证浮层。重试复用原初始化 Promise，由 Ability 的 EventHub 接收；重复点击合并，成功和窗口关闭时解除监听。失败不删除、重建或替换数据库，启动计数移到核心成功路径。正常成功后的内置元数据离线能力保持现有逻辑。

启动错误页已完成接线：`resources/base/profile/main_pages.json` 注册 `pages/StartupErrorPage`；base 与全部现有语言的独立 `startup_strings.json` 提供 `ui_startup_failed_title` 和 `ui_startup_failed_body`，重试/加载中复用 `common_retry` / `common_loading`。不需要导航菜单入口。已有错误页在核心重试失败时保留，仅当首次失败或尝试加载 Index 已替换旧 UI 时重新加载错误页。窗口测试现为 10 项，覆盖错误页门控、重试合并与回收、关闭后晚到结果、偏好未就绪时配置变更、页面加载失败及路由/多语言资源完整性。

USB 平板调试检查点：窗口、壁纸、视频、媒体服务、缓存清理、减少动态效果、后台设置、数据页、风控、动效消费者共 10 个主机套件通过；`git diff --check` 通过。日志 `.local/background-usb-checkpoint-2026-11-11.log`。本责任域的 `.ets`、资源及配置已冻结，待主对话统一构建与设备验证。

真机顶部重叠修复：MatePad Pro 的两张设置页截图中，应用返回/菜单/版本号与系统时钟同处顶部。`EntryAbility` 已启用沉浸式并发布 `TYPE_SYSTEM` 的顶部 vp 高度，但 `Index.wideShell()` 的前景 Column 没有消费该值。现仅给该内容层增加动态顶部 padding，壁纸作为同级背景保持全屏，固定 40vp 标题栏不压缩；共享 `gachaTab` / `noteTab` 只在手机壳自行避让，宽屏由壳层统一处理。没有调整导航或卡片逻辑。窗口/布局 11 项、导航动效和材质回归通过；尚待主对话安装后复拍验证。

复验：在同一横屏设置页确认返回/菜单/版本号均位于系统状态栏下方，再检查竖屏、自由多窗及祈愿/便笺页顶部不重复留白；保留 `EntryAbility` 的 `avoid area top=...` 信息级日志供对照。依据为本机 API 26 `getWindowAvoidArea` / `setWindowLayoutFullScreen` / `UIContext.px2vp` 声明及华为[沉浸式效果开发指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/immersive-window-feature/)、[平板退出自由多窗后重叠排查](https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/arkui-uimana-troubleshooting-0011/)。

数据库失败句柄释放已由数据库负责人补入：`RelationalStoreHelper.open()` 在 `createTables()` 失败时关闭本次尚未发布的 RdbStore，保留原数据库文件。本对话已核对该失败分支，未跨域修改该文件。

备份负责人需接入的重试边界：`BackupService.recoverInterruptedRestore()` 取得 `beginLocalSessionReplacement()` 后，若查询、偏好替换、凭据清理或 journal 落盘失败，不会走到 `reloadLocalSession()`；`replacementRevision` 因而继续阻止下一次初始化。需要根据已有 journal 和原恢复状态允许重入，保持部分恢复期间的数据保护；不能为重试无条件解锁。本批未修改 Backup/User 服务。

监听扫描 `filter_on.py` 在 EntryAbility 中由 2 条降为 0 条。`filter_risk_func.py` 的两条剩余提示未识别带指定回调的 off；源码配对与窗口测试确认了原回调被移除、其他订阅保留。ComponentContent 未释放提示已消除。输出在 `.local/background-window-*-before.json` / `*-after.json`。

平板验收覆盖：带中文、空格和 `#` 的目录及冷启动授权恢复；视频准备期间换源、前后台与路由往返；自由窗口密度变化、三键及系统栏避让、关窗重开。HoyoPlay 实时接口在当前环境不可达，来源选择由上游源码和确定性用例验证。

接口依据：[图片释放](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-image-imagesource/)、[文件授权](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/file-persistpermission/)、[Video](https://developer.huawei.com/consumer/en/doc/harmonyos-references/ts-media-components-video/)、[RCP 下载](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/remote-communication-rcp/)、[窗口销毁时序](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uiability-lifecycle/)、[窗口单位](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-window-i/)、[ComponentContent 释放](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-arkui-componentcontent/)。
