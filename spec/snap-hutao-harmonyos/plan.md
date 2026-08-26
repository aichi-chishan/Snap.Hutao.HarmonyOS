# Implementation Plan: Snap.Hutao.HarmonyOS（胡桃工具箱鸿蒙版）

**Input**: Feature specification from `spec/snap-hutao-harmonyos/spec.md`

## Summary

在现有 API23 空工程（`compatibleSdkVersion 6.1.0(23)`、`targetSdkVersion 26.0.0`、deviceTypes=phone/tablet/2in1）上，从零实现胡桃工具箱鸿蒙版：内置 WebView 米游社登录 + 多账号/Cookie 管理 + 角色绑定；祈愿记录（SToken 自动 genAuthKey 分页拉取、本地归档统计、手动 URL 兜底）；实时便笺（dailyNote API + 阈值通知 + 定时刷新 + 桌面服务卡片）；以及签到/活动日历/公告。仅国服。零三方依赖，全用鸿蒙系统 Kit (@kit.NetworkKit/@kit.CryptoArchitectureKit/@kit.ArkData/@kit.NotificationKit/@kit.ArkUI+Web/BackgroundTasksKit)。MVVM 架构，State Management V1 + AppStorage 全局态；phone/tablet/2in1 自适应深/浅色 UI。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 23 target 26；@State/@Observed/V1 State 管理；严格模式：禁 any/unknown/as、禁对象字面量类型、Sendable 跨线程约束）
**Primary Dependencies**: 零三方运行时依赖；系统 Kit —— @ohos.net.http（网络）、@ohos.security.cryptoFramework（MD5/DS 签名）、@ohos.data.relationalStore（本地库）、@ohos.data.preferences（设置）、@ohos.notificationManager（通知）、@ohos.web.webview + Web 组件（登录）、@ohos.app.form.FormExtensionAbility（卡片）、@ohos.resourceschedule.workScheduler（后台）、@ohos.taskpool（并发）
**State Management**: State Management V1（@State/@Observed/@Link/@Provide/AppStorage）；全局用户态经 AppStorage 同步 + preferences 持久化
**Storage**: relationalStore(SQLite)：users/game_roles/gacha_archives/gacha_items/daily_notes/sign_in_info/acts/announcements；preferences：设置项
**Testing**: 单元目测 + `arkts_check` 静态检查（每个 .ets）+ `build_project` 编译 + `verify_ui` UI 冒烟
**Target Platform**: HarmonyOS NEXT，phone/tablet/2in1（API 23 兼容基线）
**Project Type**: mobile-app（单 entry HAP）
**Performance Goals**: 祈愿历史长列表 60fps 滚动（LazyForEach 分页）；便笺打开→展示 ≤3s；网络/DS/DB 重计算入 TaskPool
**Constraints**: 仅国服；后台刷新受系统配额；零三方依赖；沙箱内不可读游戏缓存；符合 ArkTS 严格模式
**Scale/Scope**: 1 个 HAP；7 个用户故事；40 个左右 ArkTS 源文件

## Project Structure

### Documentation (this feature)

```text
spec/snap-hutao-harmonyos/
├── spec.md              # 需求规格
├── plan.md              # 本文件
└── tasks.md             # 任务分解
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── entryability/EntryAbility.ets        # 改造：初始化 DB/预登录态，加载 Shell
├── common/
│   ├── Constants.ets                    # app_version、盐值(X4/K2/LK2)、x-rpc 常量、错误码
│   ├── Logger.ets                       # hilog 封装
│   └── DateUtil.ets                     # 时间戳/倒计时/恢复时间格式化
├── model/
│   ├── User.ets                         # 账号 + Cookie 五件套 + UserGameRole[]
│   ├── UserGameRole.ets                 # uid/region/nickname/level
│   ├── ApiResponse.ets                  # retcode/message/data 统一封装 + 已知返回码
│   ├── GachaType.ets                    # 100/200/301/302/500 枚举 + 查询映射
│   ├── GachaItem.ets                    # 抽卡记录(含归档字段)
│   ├── GachaArchive.ets                 # uid 归档
│   ├── GachaStatistics.ets              # 分池统计/出金历史/垫数
│   ├── DailyNote.ets                    # 便笺快照 + Expeditions[]/Transformer/DailyTask
│   ├── SignInInfo.ets                   # 签到奖励列表 + 本月状态
│   ├── ActCalendarEntry.ets             # 活动/卡池/签到条目
│   └── Announcement.ets                 # 公告分类/条目
├── data/
│   ├── db/RelationalStoreHelper.ets     # SQLite 建表/升级/CRUD（Sendable 安全封装）
│   ├── prefs/PreferencesStore.ets       # 设置存取(刷新间隔/通知开关/默认UID/主题)
│   ├── repo/UserRepo.ets
│   ├── repo/GameRoleRepo.ets
│   ├── repo/GachaRepo.ets
│   ├── repo/DailyNoteRepo.ets
│   ├── repo/SignInRepo.ets / CalendarRepo.ets / AnnouncementRepo.ets
│   └── network/
│       ├── DsSigner.ets                 # DS Gen1/Gen2 签名（MD5 @cryptoFramework）
│       ├── ApiClient.ets                # @ohos.net.http 封装：GET/POST/header/超时/Cookie 注入/retcode 解析
│       ├── HoyolabClient.ets            # 按 host 注入 x-rpc 头/UA
│       ├── GachaAuthApi.ets             # genAuthKey (DS Gen1/K2)
│       └── RiskGuard.ets                # 1034/风控与重试提示
├── service/
│   ├── UserService.ets                  # WebView Cookie 解析/Token 链补齐/多账号/角色绑定
│   ├── GachaLogService.ets              # genAuthKey→分页拉取→去重→归档→统计
│   ├── DailyNoteService.ets             # 便笺刷新/阈值判定/通知分发/定时器
│   ├── SignInService.ets                # Luna 签到
│   ├── CalendarService.ets              # act_calendar
│   └── AnnouncementService.ets          # hk4e-ann
├── viewmodel/                           # @Observed 状态容器：页面数据 + 命令
│   ├── UserViewModel.ets
│   ├── GachaLogViewModel.ets
│   ├── DailyNoteViewModel.ets
│   ├── SignInViewModel.ets
│   ├── CalendarViewModel.ets
│   └── AnnouncementViewModel.ets
├── pages/                               # Navigation/Tabs 承载页面
│   ├── Index.ets                        # 改造为 Shell（Tabs + Navigation + 自适应）
│   ├── LoginPage.ets                    # WebView 登录 + 手动 Cookie 兜底
│   ├── UserPage.ets                     # 账号列表/切换/绑定角色
│   ├── GachaLogPage.ets                 # 祈愿：总览/分池/历史/统计
│   ├── DailyNotePage.ets                # 实时便笺
│   ├── SignInPage.ets
│   ├── CalendarPage.ets
│   ├── AnnouncementPage.ets
│   ├── AnnouncementDetailPage.ets       # Web 查看详情
│   └── SettingPage.ets                  # 刷新间隔/通知开关/数据管理
├── components/                          # 可复用 UI：ResinCircle/Countdown/EmptyState/Loading
├── widgets/
│   ├── DailyNoteFormExtensionAbility.ets
│   └── pages/DailyNoteCard.ets          # 卡片 rootId: DailyNoteCard
└── resources（entry/src/main/resources/）  # element(颜色/字符串/浮点) + media + profile(form_config.json、main_pages.json)
```

**Structure Decision**: 本项目为从零开始（0-to-1）的 HarmonyOS 应用，选择 **MVVM 责任分层**（pages/views + viewmodel + model + service + data + common）。触发 MVVM 的理由：多页面（≥9 个页面）、本地持久化（relationalStore/preferences）、跨页面共享登录态（AppStorage）、网络+签名+业务算法（服务层）、复杂表单（登录/设置）。按"最小拆分"原则把相关模型/服务按功能聚合（qida/data 目录内按 repo 划分），避免一概念一文件过度拆分；预计 40 个左右 ArkTS 源文件，符合该复杂度的合理文件量。State Management V1（@State/@Observed）+ AppStorage 全局态（greenfield 但考虑与 Form 卡片及简单性，采用 V1 而非 V2 —— 记录于本节：本项目选择 V1 一致性，所有页面统一）。

## Complexity Tracking

> 无超出「单 HAP + MVVM」的必要违规；40 个左右文件由 7 个用户故事 × 平均 6 文件决定，属必要拆分，非膨胀。

## Research & Decisions

- **Decision**: DS 签名算法按参考项目实现：Gen1=`md5("salt=%s&t=%d&r=%s")`，Gen2 追加 `&b={body}&q={排序query}`，输出 `"{t},{r},{md5}"` 到 `DS` 请求头
  - **Rationale**: 与 Snap Hutao `DataSignAlgorithm.cs` 完全一致，Gen2 额外拼 body/query 用于便笺/日历等 POST/GET 战绩接口
  - **Alternatives considered**: 无；官方各接口所需 DS 版本（便笺 Gen2/X4、genAuthKey Gen1/K2、签到 Gen1/LK2）已从参考项目确认
- **Decision**: 登录用内置 Web 组件加载米游社签到/登录落地页，登录成功后用 WebCookieManager 读取域 Cookie 解析五件套
  - **Rationale**: 鸿蒙 Web 组件 API23 成熟；无需自研登录窗；与用户选择"内置 WebView 网页登录"一致
  - **Alternatives considered**: 扫码登录（需额外轮询/设备绑定，本期不做）；手机验证码（需 RSA/验证，本期不做）
- **Decision**: 祈愿导入以 SToken → genAuthKey 自动鉴权为主，手动 URL 兜底
  - **Rationale**: 用户明确选择 SToken 自动生成；手动 URL 为低级兜底保证可用性
  - **Alternatives considered**: webCaches 读取（鸿蒙沙箱不可行，已排除）
- **Decision**: 本地存储用 relationalStore(SQLite) + preferences；Token 加解密存储采用系统本地加密能力
  - **Rationale**: SQLite 结构化适合海量祈愿记录；零三方依赖；relationalStore 线程安全（查询为异步方法无需子线程）
  - **Alternatives considered**: KV 存储不适合 gacha_items 海量查询/聚合
- **Decision**: 后台刷新三层策略：应用前台轮询 + 卡片 form 定时 + WorkScheduler 兜底；不承诺常驻实时推送
  - **Rationale**: 鸿蒙系统对后台并发与卡片刷新有配额管控（文档已确认），常驻实时不可行
  - **Alternatives considered**: 常驻长时任务（过度且受系统限制）
- **Decision**: 风控(1034)以提示+重试处理，不集成 Geetest 极验
  - **Rationale**: 极验需 Web 手势交互/验证码桥，复杂度高；本期以错误态兜底
  - **Alternatives considered**: 深度集成 Geetest（后期增量）
- **Decision**: 并发用 TaskPool（网络与重计算），跨线程传 Sendable 兼容原始字段 DTO；relationalStore 实例不跨线程，DB 操作在调用侧异步执行
  - **Rationale**: 文档确认 relationalStore 不支持 Worker/TaskPool 跨实例；query 为异步方法无需子线程
  - **Alternatives considered**: Worker（过重，TaskPool 足够）

## Data Model

### user_accounts
| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | |
| mid | TEXT | 米游社 mid |
| aid | TEXT | account_id |
| is_oversea | INTEGER | 恒 0（仅国服） |
| cookie_account/token | TEXT | account_id=..; cookie_token=..（加密） |
| cookie_ltoken/ltuid | TEXT | ltoken=..; ltuid=..（加密） |
| cookie_stoken/stuid | TEXT | stoken=..; stuid=..（加密） |
| display_nickname | TEXT | 账号昵称 |
| avatar | TEXT | 头像 URL |
| is_selected | INTEGER | 当前账号标记 |
| created_at | INTEGER | |

### user_game_roles
| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | |
| user_id | INTEGER FK | |
| game_uid | TEXT | 游戏 UID |
| region | TEXT | cn_gf01/cn_qd01 |
| nickname | TEXT | 角色昵称 |
| level | INTEGER | |
| is_default | INTEGER | 默认 UID |
| is_chosen | INTEGER | |

### gacha_archives
| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | |
| uid | TEXT | 归档所属 UID（唯一） |
| is_selected | INTEGER | |

### gacha_items
| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | |
| archive_id | INTEGER FK | |
| gacha_type | INTEGER | 100/200/301/302/500 |
| item_id | INTEGER | |
| count | INTEGER | 恒 1 |
| time | TEXT | ISO 时间 |
| name | TEXT | 名称 |
| item_type | TEXT | 角色/武器 |
| rank_type | INTEGER | 5/4/3 |
| gacha_id | TEXT | 服务端游标 id（用于去重/end_id） |

### daily_notes
| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | |
| user_id | INTEGER FK | |
| uid | TEXT | |
| current_resin/max_resin | INTEGER | |
| resin_recovery_time | TEXT | 恢复完成时间 |
| finished_task_num/total_task_num | INTEGER | |
| is_extra_task_reward_received | INTEGER | |
| remain_resin_discount_num/limit | INTEGER | 周本折扣 |
| current_home_coin/max_home_coin | INTEGER | |
| home_coin_recovery_time | TEXT | |
| current_expedition_num/max_expedition_num | INTEGER | |
| expeditions_json | TEXT | 派遣列表 JSON |
| transformer_json | TEXT | 参变仪 JSON |
| archon_json | TEXT | 魔神任务 JSON |
| resin_notify_threshold | INTEGER | 默认 120 |
| home_coin_notify_threshold | INTEGER | 默认 1800 |
| notify_flags | INTEGER | 通知开关位（树脂/派遣/每日/参变仪/洞天宝钱） |
| refresh_time | INTEGER | 上次刷新时间戳 |

### sign_in / acts / announcements（轻量缓存表）
- sign_in_info: user_id、act_id、month、signed_days、rewards_json、updated_at
- act_calendar_entries: uid、type、name、start_time、end_time、extra_json
- announcements: category、title、time、url、content_json、updated_at

### preferences keys
- app.current_user_id、app.current_uid
- dailynote.refresh_interval_minutes、dailynote.auto_refresh_enabled、theme.mode
- (各通知阈值存 daily_notes 表行内)

## Contracts & Interfaces

### 对外 HTTP 接口（全部国服 CN）
| 用途 | 方法/URL | 鉴权 | DS |
|---|---|---|---|
| 网页登录落地 | `https://act.mihoyo.com/bbs/event/signin/hk4e/index.html?act_id=e202311201442471` | 浏览器 Cookie | - |
| genAuthKey | POST `https://api-takumi.mihoyo.com/binding/api/genAuthKey`，body `{auth_appid:"webview_gacha",game_biz:"hk4e_cn",game_uid,region}` | SToken Cookie | Gen1/K2 |
| actionTicket | POST `https://api-takumi.mihoyo.com/binding/api/getActionTicketBySToken?action_type=game_role` | SToken | Gen1/K2 |
| 角色列表 | GET `https://api-takumi.mihoyo.com/binding/api/getUserGameRoles?action_ticket=..&game_biz=hk4e_cn` | action_ticket | - |
| 祈愿记录 | GET `https://public-operation-hk4e.mihoyo.com/gacha_info/api/getGachaLog?lang=..&auth_appid=webview_gacha&authkey=..&authkey_ver=1&sign_type=2&gacha_type=..&size=20&end_id=..` | authkey(query) | 无 |
| 实时便笺 | GET `https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/dailyNote?role_id={uid}&server={region}` | Cookie`account_id/cookie_token` | Gen2/X4 |
| 每日签到 | POST `https://api-takumi.mihoyo.com/event/luna/sign`，body `{act_id:"e202311201442471",region}`；奖励/状态 GET `event/luna/home` | Cookie | Gen1/LK2 |
| 活动日历 | GET `https://api-takumi-record.mihoyo.com/game_record/app/genshin/api/act_calendar?uid={uid}&region={region}` | Cookie | Gen2/X4 |
| 公告列表 | GET `https://hk4e-ann-api.mihoyo.com/common/hk4e_cn/announcement/api/getAnnList?...` | 无 | 无 |

### 关键内部接口（ArkTS 签名目标）

```ts
// DsSigner
class DsSigner {
  signGen1(salt: string, t: number, r: string): string;  // "t,r,md5"
  signGen2(salt: string, t: number, r: string, body: string, querySorted: string): string;
}

// ApiClient
class ApiClient {
  get<T>(url: string, headers: Record<string,string>): Promise<T>;
  postJson<T>(url: string, body: Record<string,string>, headers: Record<string,string>): Promise<T>;
  setCookie(cookie: string): void;   // 按当前账号注入
}

// UserService
class UserService {
  parseCookiesFromWebView(raw: string): UserLogined;      // 解析五件套
  completeTokenChain(stoken: SToken): Promise<void>;      // 补 ltoken/cookie_token
  fetchGameRoles(userId: number): Promise<UserGameRole[]>;
  switchUser(userId: number): Promise<void>;
}

// GachaLogService
class GachaLogService {
  refreshByStoken(uid: string): Promise<RefreshProgress>; // genAuthKey→逐池分页→去重入库→统计
  importByUrl(url: string): Promise<RefreshProgress>;     // 手动 URL 兜底
  statistics(uid: string): Promise<GachaStatistics>;
}

// DailyNoteService
class DailyNoteService {
  refresh(uid: string): Promise<DailyNote>;
  evalAndNotify(note: DailyNote): void;                   // 阈值→通知
  startAutoRefresh(intervalMin: number): void; stopAutoRefresh(): void;
}

// Form 卡片
class DailyNoteFormExtensionAbility extends FormExtensionAbility {
  onAddForm / onUpdateForm / onFormEvent(...);            // 读最新便笺渲染 + updateForm
}
```

### UI/状态契约
- 全局状态（AppStorage）：`currentUser`(User)、`currentUid`(string)、`isLoggedIn`(boolean)
- 页面路由：`pages/Index`(Shell) → `pages/Login/User/GachaLog/DailyNote/SignIn/Calendar/Announcement(Detail)/Setting`
- 服务卡片 rootId：`DailyNoteCard`；form_config.json 声明 2x2/2x4，`updateEnabled: true` + `scheduledUpdateTime`
