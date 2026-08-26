# Feature Specification: Snap.Hutao.HarmonyOS（胡桃工具箱鸿蒙版）

**Created**: 2026-08-20
**Status**: Approved
**Input**: 用户需求 —— 在鸿蒙设备（手机/平板/PC）上实现类似胡桃启动器的应用；剔除注入功能及依赖注入的功能（启动器/DLL注入/内存读写/Overlay/文件解锁等本机操作类）；保留祈愿记录、实时便笺等数据查询类功能；全部采用鸿蒙尽可能新的 API 实现最好的交互效果与 UI。仅支持国服(CN)。

## Overview

在现有 API23（`compatibleSdkVersion 6.1.0(23)`、`targetSdkVersion 26.0.0`、phone/tablet/2in1）空工程基础上，从零构建"胡桃工具箱"鸿蒙版：核心提供米哈游账号登录（内置 WebView 网页登录）、祈愿记录（SToken 自动鉴权拉取 + 本地归档统计）与实时便笺（树脂/派遣/洞天宝钱/参变仪/每日任务/周本折扣 + 阈值通知 + 桌面卡片），并附带签到、活动日历、公告等辅助功能。仅服务国服玩家，采用 ArkUI 声明式 UI 与鸿蒙最新 Kit API，实现手机/平板/PC 自适应。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 用户/账号管理（含 WebView 网页登录）（Priority: P1）

玩家在 App 内置 WebView 中登录米游社账号，App 自动获取并持久化 Cookie（account_id/cookie_token/ltoken/ltuid/stoken/stuid/mid 五件套），可管理多个账号、切换当前账号、选择绑定的游戏角色 UID；账号数据用于晶祈愿与实时便笺等所有米哈游账号功能。

**Why this priority**: 所有账号数据查询类功能（祈愿、便笺、签到、日历）都依赖账号与角色，是本应用的数据基础，必须最先可用。

**Independent Test**: 通过内置 WebView 完成一次真实登录，App 能看到账号昵称/头像/已绑定角色列表并可选中默认 UID；多账号可切换；离线重启后仍保持登录态。

**Acceptance Scenarios**:

1. **Given** 应用首次启动且未登录，**When** 用户在"我的"页点击登录并完成 WebView 网页登录，**Then** 显示读取到的账号信息与绑定角色（UID）列表
2. **Given** 已登录且绑定了角色 UID，**When** 用户重启应用，**Then** 登录态保留，当前默认 UID 可直接用于祈愿/便笺功能
3. **Given** 已存在多个账号，**When** 用户切换账号，**Then** 全局当前账号与默认 UID 同步更新，所有账号功能随之切换
4. **Given** 登录风控或 WebView 被限制，**When** WebView 登录失败，**Then** 提供手动粘贴完整 Cookie 的兜底入口并校验有效性

---

### User Story 2 - 祈愿记录（SToken 自动鉴权 + 统计）（Priority: P1）

已登录并绑定 UID 的玩家一键刷新祈愿记录：App 通过 SToken 调用 genAuthKey 自动生成带 authkey 的请求，分页拉取新手/常驻/角色活动/武器活动/集录各卡池全部历史抽卡数据，本地归档去重、呈现分池统计（总抽数、出金历史、垫数、当期池子信息），支持历史记录浏览与手动粘贴 URL 兜底。

**Why this priority**: 祈愿记录是胡桃工具箱的标志性核心功能，价值最高，须在 P1 交付。

**Independent Test**: 用已登录账号一键刷新祈愿记录，能拉取到与游戏内一致的完整历史并正确统计；重复刷新不产生重复数据；统计数字与真实抽卡一致。

**Acceptance Scenarios**:

1. **Given** 已登录并选中 UID，**When** 用户点击"刷新祈愿记录"，**Then** 自动完成 genAuthKey 鉴权并逐卡池分页拉取完整历史，期间展示进度
2. **Given** 已拉取过历史数据，**When** 再次刷新，**Then** 仅合并新增数据，总数不重复累计
3. **Given** 统计页打开，**When** 查看各卡池，**Then** 展示总抽数、当前池垫数/水位、五星四星出金历史（时间轴形式）
4. **Given** SToken 不可用/鉴权失败，**When** 用户粘贴游戏内祈愿链接（URL），**Then** 自动解析 authkey 完成拉取

---

### User Story 3 - 实时便笺 + 通知（Priority: P1）

已绑定 UID 的玩家查看实时便笺：树脂（当前/上限/恢复时间）、每日委托完成情况、周本折扣剩余、洞天宝钱、派遣任务（角色/倒计时）、参变仪冷却、魔神任务进度；支持阈值本地通知（如树脂满 120/160、派遣完成、每日全完成、参变仪就绪），应用内定时自动刷新。

**Why this priority**: 实时便笺是高频日常工具，与祈愿并列核心，P1 交付；通知与定时刷新是其价值关键。

**Independent Test**: 用真实 UID 查看便笺数据与游戏内一致；设置树脂阈值后达到阈值能收到本地通知；定时刷新间隔生效。

**Acceptance Scenarios**:

1. **Given** 已登录并选中 UID，**When** 用户打开实时便笺页，**Then** 展示树脂环、派遣列表、每日委托、周本折扣、洞天宝钱与刷新时间，蓝色高亮可手动刷新
2. **Given** 开启阈值通知（如树脂≥120），**When** 定时刷新检测到满足阈值，**Then** 系统本地通知提醒，且满足后显示角标
3. **Given** 开启自动刷新，**When** 到设置的间隔，**Then** 便笺数据在后台/前台定时更新进度可见

---

### User Story 4 - 实时便笺桌面卡片/小组件（Priority: P2）

在桌面添加"实时便笺"服务卡片（Form），无需打开 App 即可在桌面查看树脂/派遣/每日摘要，支持 App 内刷新与卡片定时刷新联动。

**Why this priority**: P1 便笺功能稳定后，桌面卡片作为增强体验、降低使用摩擦，排在 P2。

**Independent Test**: 在桌面添加该卡片，显示最后获取的树脂/派遣/每日状态；App 手动刷新后卡片同步更新；卡片按设定周期定时更新。

**Acceptance Scenarios**:

1. **Given** 已登录并开启便笺，**When** 用户在桌面长按添加 2x2/2x4 实时便笺卡片，**Then** 卡片展示树脂数值/派遣进度/每日完成等摘要
2. **Given** 卡片已添加，**When** App 内手动刷新便笺，**Then** 卡片数据同步更新
3. **Given** 卡片存在且数据未过期，**When** 定时刷新周期到达，**Then** 卡片在系统配额内自动更新

---

### User Story 5 - 米游社每日签到（Priority: P3)

已登录的玩家一键执行米游社《原神》每日签到，查看本月签到奖励列表与已签状态，签到失败给出明确原因（已签/风控等）。

**Why this priority**: 签到操作简单、价值低但常见，作为 P3 辅助功能补充完整度。

**Independent Test**: 用已登录账号执行签到，能返回签到结果并展示本月奖励列表；重复签到提示"已签到"。

**Acceptance Scenarios**:

1. **Given** 已登录，**When** 用户点击"立即签到"，**Then** 执行签到并展示成功/失败原因（如已签、风控）
2. **Given** 当前月份，**When** 查看签到页，**Then** 展示本月累计签到天数与每日奖励列表

---

### User Story 6 - 活动日历（Priority: P3）

已登录的玩家查看当前游戏活动日历（活动/卡池/签到等条目）的起止时间与内容摘要。

**Why this priority**: 活动日历信息性强、实现成本低，作为 P3 补充。

**Independent Test**: 用已登录账号拉取活动日历，能线性展示近期活动/卡池条目及其起止时间。

**Acceptance Scenarios**:

1. **Given** 已登录，**When** 用户打开活动日历页，**Then** 展示按时间排序的活动/卡池/签到条目，含起止时间与名称

---

### User Story 7 - 游戏公告（Priority: P3）

玩家在应用内查看官方游戏公告（版本更新/活动/新闻分类），列表可读标题与时间，点击可打开详情（内置 Web 查看）。

**Why this priority**: 公告无需登录即可展示，实现简单，作为 P3 收尾补充首页价值。

**Independent Test**: 打开公告页能加载官方公告列表并按分类/时间展示；点击某条可查看详情内容。

**Acceptance Scenarios**:

1. **Given** 应用联网，**When** 用户打开公告页，**Then** 展示公告分类与列表（标题+时间）
2. **Given** 公告列表已加载，**When** 用户点击某条公告，**Then** 打开详情页展示完整内容

---

### Edge Cases

- 未登录状态：所有账号功能页给出"去登录"引导，不报错崩溃
- SToken 过期/Cookie 失效：统一错误提示并提供重新登录入口
- 风控(1034/验证码)命中：便笺/战绩给出"被风控拦截"提示 + 重试，不深度集成极验
- authkey 超时：祈求愿拉取中断但已拉取数据保留，可续拉
- 网络异常/超时：给出友好错误态，支持重试，不造成 UI 卡死
- 断网离线：已缓存数据可见（便笺、祈愿记录本地库），网络功能禁用并提示
- 多账号 UID 归属：每个归档按 UID 独立，避免混淆
- 卡片空间不足/未授权：添加卡片失败给出提示

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统必须提供内置 WebView 网页登录（米游社），登录成功后自动提取并安全存储 Cookie（stoken/stuid/mid、ltoken/ltuid、account_id/cookie_token）
- **FR-002**: 系统必须支持多账号添加/删除/切换，并持久化"当前账号 + 默认 UID"的全局选中状态
- **FR-003**: 系统必须通过 cookie token 链自动补齐缺失 Token（SToken→LToken→cookie_token），仅国服
- **FR-004**: 系统必须拉取并展示当前账号绑定的游戏角色（UID/昵称/等级/服务器），支持选择默认 UID
- **FR-005**: 系统必须通过 SToken 调用 genAuthKey 自动生成祈愿鉴权 authkey（国服 webview_gacha）
- **FR-006**: 系统必须分页拉取祈愿记录（gacha_type: 100/200/301/302/500；每页 20 条；end_id 游标），并本地归档去重合并
- **FR-007**: 系统必须提供手动粘贴祈愿 URL（含 authkey）的兜底导入
- **FR-008**: 系统必须基于本地归档生成分池统计（总抽数、出金历史、当前垫数/水位），并按 UID 独立
- **FR-009**: 系统必须通过 GameRecord dailyNote API 获取实时便笺（树脂/派遣/每日/周本折扣/洞天宝钱/参变仪/魔神任务）
- **FR-010**: 系统必须支持便笺阈值本地通知（树脂、派遣完成、每日完成、参变仪就绪、洞天宝钱）与可配置自动刷新间隔
- **FR-011**: 系统必须提供实时便笺桌面服务卡片（FormExtensionAbility），支持定时刷新与 App 主动刷新联动
- **FR-012**: 系统必须提供米游社每日签到（Luna 系列 API）与当月奖励/签到状态展示
- **FR-013**: 系统必须提供活动日历（act_calendar）与游戏公告（hk4e-ann）展示
- **FR-014**: 系统必须统一接口封装（retcode/data/message）、统一错误态与加载态，未登录/风控/网络异常均有明确提示
- **FR-015**: 系统必须支持深/浅色主题与 phone/tablet/2in1 三形态自适应；长列表使用 LazyForEach 保证流畅

### Key Entities

- **User/Account**: 米哈游账号，Cookie 五件套（stoken/stuid/mid、ltoken/ltuid、account_id/cookie_token），是否国服，创建时间；一对多角色
- **UserGameRole**: 绑定游戏角色：uid、region、nickname、level；从属某账号
- **GachaArchive**: 祈愿归档：uid、是否选中；一对多 GachaItem
- **GachaItem**: 单条抽卡记录：gacha_type、item_id、count、time、name、item_type、rank_type、id(游标)
- **DailyNote**: 实时便笺快照：current/max_resin、resin_recovery_time、expeditions[]、finished/total_task_num、remain_resin_discount_num、home_coin、transformer、archon_quest_progress、refresh_time；阈值与通知配置
- **SignInInfo**: 签到奖励列表 + 本月签到状态（累计天数）
- **Act**: 活动日历条目：名称、类型（活动/卡池/签到）、起止时间
- **Announcement**: 公告条目：分类、标题、时间、内容

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 从应用启动到完成登录（WebView）+绑定 UID，熟练用户可在 2 分钟内完成
- **SC-002**: 祈愿记录全量拉取的附加延迟（分页间隔受风控约束）不阻塞 UI，进度可视化；统计结果与游戏内一致（抽样比对正确率 100%）
- **SC-003**: 实时便笺从打开页面到展示数据 ≤ 3 秒（正常网络），手动刷新可感知即时
- **SC-004**: 阈值触发后本地通知在便笺刷新成功后的 1 分钟内送达
- **SC-005**: 在手机/平板/2in1 三种形态下，所有页面均可正常操作且深浅色下无文字/图片错版（UI 冒烟验证通过）
- **SC-006**: 应用在调试构建下静态检查（arkts_check）零阻塞性违规、编译构建通过

## Assumptions

- 仅支持国服(CN)，所有米哈游 API 使用国服域名；外服 UID/账号直接提示不支持
- 后台持续刷新受系统配额约束：采用"应用前台定时轮询 + 卡片 form 定时 + WorkScheduler 兜底"，不承诺系统级常驻实时推送
- 风控(1034)本期以提示+重试处理，不深度集成 Geetest 极验
- 登录以内置 WebView 为主、手动粘贴 Cookie 为兜底；不实现扫码/手机验证码登录（本期）
- 祈愿导入以 SToken 自动鉴权为主、手动 URL 为兜底；不做游戏本地 webCaches 读取（鸿蒙沙箱不可行）
- 零三方运行时依赖，网络/JSON/DB/加密/通知/卡片全部使用鸿蒙系统 Kit
- 长列表（祈愿历史）默认渲染近期数据，全量分页加载以保流畅
- 数据全部本地存储（relationalStore SQLite + preferences），不上传任何云端

## Open Questions

- 米哈游 DS 盐值（X4/K2/LK2）与 app_version 常量随时间可能更新，需在 Constants 集中维护并在失效时提示升级 —— 已接受为运维风险，不需本期解决
- 桌面卡片定时刷新的系统最小周期与配额以真机实测为准，须在 Phase 4 验证 —— 已列入验证项
