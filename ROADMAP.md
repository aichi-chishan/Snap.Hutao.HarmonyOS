# ROADMAP — 未来完善规划

> 基于 2026-09 对 Windows 版（Remastered-latest）的全量功能对齐审计 + 本轮真机验证经验整理。
> 范围护栏（长期不变）：**仅国服**；**不做注入/内存读取类功能**；**不含胡桃云在线服务**（通行证/云备份/云统计/云攻略/云壁纸/反馈）；隐私数据仅存本地。
> 优先级说明：P0 = 稳定与还债（最优先）→ P1 = 功能补全 → P2 = 体验/工程化 → P3 = 平台能力。规模：S（半天内）/ M（1-2 天）/ L（3 天+）。

---

## 本轮（2026-09-10）已修复

| 项 | 根因 | 修复 |
|---|---|---|
| 实时便笺自动刷新后界面数值不变 | 服务层定时器只落库 + 推卡片，从不通知 UI；且定时器只在便笺页被打开时才启动（冷启动后进主页则永不刷新） | 新增 AppStorage 版本戳 `dailyNoteVersion`（服务层刷新成功自增，便笺页/主页 `@Watch` 重读本地缓存）；`EntryAbility` 启动/回前台调用 `DailyNoteService.bootstrapAutoRefresh()`（按偏好起定时器 + 缓存过期即补刷）；服务层加刷新重入保护、失败原因写入 `dailyNoteLastError` 并在便笺页顶部提示 |
| 主页便笺卡数值不刷新（刷新时间变了、树脂没变） | **ArkUI @Builder 传参规则**：`block(category,icon,text,sub,dot,wide)` 六参数按值传递，@Builder 内部 UI 不参与刷新 | 改为常量槽位 `block(slot, wide)` + 渲染期私有方法读组件状态；同类问题一并修 `HomeChallengeCard.slotCell` / `HomeSignInCard.awardCell` / `DailyNotePage.headerIconButton` |
| 桌面卡片无法手动刷新 | 卡片只有静态展示，没有交互入口；`onFormEvent` 未实现 | 卡片标题栏加 ⟳：`postCardAction(message)` → `onFormEvent` → 补齐卡片进程运行时（偏好/DB/会话）→ `DailyNoteService.refreshForCard`（带 15s 超时，避免风控弹窗挂起卡片进程）→ 回推卡片；失败原因写卡片 `tipText` |
| 浅色模式整窗发黄 / 深色遮罩失效 | **8 位色值顺序搞错**：`'#FFFFFF99'` 想表达 60% 白，实际按 `#AARRGGBB` 解析为**不透明 #FFFF99**（淡黄）；`'#00000033'` 被解析为**全透明** | WallpaperLayer 遮罩改资源色 `wallpaper_mask`（浅 `#99FFFFFF` / 深 `#33000000`）；底色统一 `wallpaper_base`（浅 `#F2F0EC` / 深 `#141418`，与窗口底色同色系）；AGENTS.md 记录规则 |
| 便笺「已满还需 1931514天18小时」 | `resin_recovery_time` 是**距回满的秒数**（Windows: `DeserializeTime.AddSeconds`），代码当成时间戳解析 | 按秒数 + 拉取时刻锚点计算剩余时间；从库里读出来同样成立；异常态显示「即将回满」 |
| 便笺页「每日委托 0/0」（主页卡却正常） | 表里没有 daily_task 列，`rowToRecord` 未还原子对象；接口也可能不返回 daily_task | `fromJson` 与 `rowToRecord` 均用顶层 finished/total_task_num 兜底 |
| 风控弹窗可能永久挂起 | `RiskVerifyService.show` 的 Promise 无超时，应用后台/无窗口时永不 resolve，阻塞后续验证 | 加 180s 兜底超时（自动按"取消"结束，调用方已按空结果处理） |

---

## P0 稳定与质量还债

| 项 | 说明 | 规模 |
|---|---|---|
| Lint 告警清零 | 现存 36 条 warning：21 处 `avoid-overusing-custom-component`（复核组件拆分是否过度）、12 处 `no-state-var-access-in-loop`（循环内读状态变量，先取快照）、3 处 `use-reusable-component`（长列表改 `@Reusable`） | M |
| `@Entry` + `@Prop embedMode` 编译 WARN 消除 | 目前所有内嵌页带 WARN（非阻断）。方案：内嵌页改纯 `@Component`，路由入口包一层薄 `@Entry` 壳转发参数 | M |
| HdsSideBar 回归评估 | 真机崩溃根因：V1→V2 组件传 `@Builder` 引用丢失 `this`（编译为 `.bind(this)` 报 undefined）。待 UIDesignKit 修复后重试，或自写 `@ComponentV2` 桥接层。**回退代码保留在 cb3df76**，勿重复踩坑 | S（评估）/ M（重做） |
| 死代码清理 | `ResourcePackService` / `StandardIconService` 已从设置页退役（素材全内置后无用武之地）；`MetaIcon.remoteFallback` 云端兜底链是否保留需决策。删除前确认无隐藏引用 | S |
| DB 迁移框架化 | 目前 `try { ALTER ... } catch(已存在)` 散落在 `RelationalStoreHelper`。改为 user_version 驱动的有序迁移列表，新迁移只追加不改旧 | S |
| 真机回归清单 | 把每轮发版前的手工验证步骤固化成文档：登录/风控/刷新/导入导出/深浅色/三断点（720/840/1200）矩阵，放 `docs/` 或本文件附录 | S |
| @Builder 多参传递全量审计 | 官方规则：@Builder 传两个及以上参数时内部 UI 不随状态刷新。本轮已修便笺链路的 4 处，仍需排查：`SpiralAbyssPage.overviewCell`/`rankRow`、`RoleCombatPage.statCell`/`statValueCell`、`WikiAvatarPage.propCell`、`WikiMonsterPage.monStat`、`GachaLogPage.avatarSection`/`rankGroup`（判据：参数里是否含会变的字段 / ForEach 键值是否含变动字段） | M |
| WallpaperLayer 观感复核 | 修正色值顺序后，浅色遮罩（60% 白）与图片 opacity 0.5 的实际观感需真机确认是否需要下调遮罩强度；`local` 模式未选目录时与 `none` 观感是否一致 | S |
| 风控兜底页复检 | `GeetestVerifyPage` / `RiskVerifyDialog` 仅作兜底保留（AGENTS.md 约定），确认统一浮层主链路覆盖后评估是否可退场 | S |

---

## P1 功能补全（对齐 Windows 的已知剩余项）

| 项 | 说明 | 规模 |
|---|---|---|
| ~~祈愿「历史记录列表」页签~~ ✅ | 已完成（e27abe7）：历史页签顶部期次汇总卡（GachaEvent 期次元数据归桶：版本/池名/UP 五星四星获取数/时间跨度，对齐 HistoryWishBuilder+PivotHistory）；同轮修复五页签在 7994665 被误删的回归 | M |
| ~~角色立绘浏览~~ ✅ | 已完成：WikiAvatarPage 立绘卡（Swiper 翻页切换相邻角色，LazyForEach+cachedCount(1) 按需创建页）。采用 **CDN 按需拉取 + 沙盒缓存**（复用 StandardIconService，`GachaAvatarIcon/UI_Gacha_AvatarIcon_{icon后缀}.png`，118/119 角色可用，旅行者占位），零包体；`fetch-assets.py --bundle-splash` 可选本地打包 | L |
| ~~名片展示~~ ✅ | 已完成（e27abe7）：角色资料页名片区块（胶囊横幅 + 全幅大图 + 名称/描述浮层，描述来自 NameCard.json 入 rawfile） | M |
| ~~攻略外链~~ ✅ | 已完成（e27abe7）：角色资料页攻略区块（米游社搜索 + B站战争百科直达，对齐 WikiAvatarStrategyComponent）；我的角色详情页此前已有 | S |
| ~~应用版本检查~~ ✅ | 已完成（e27abe7）：设置→关于显示版本号 + 「检查应用更新」（GitHub Releases latest 对比 versionName，发现新版跳发布页） | M |
| ~~全量本地备份/还原~~ ✅ | 已完成（e27abe7）：设置→备份与还原（账号凭证+祈愿+成就+偏好 → 单 JSON；覆盖式还原带二次确认；设备指纹类键不备份） | M |
| ~~日历/签到细节打磨~~ ✅ | 已核对（对照 Windows CalendarItem/CalendarViewModel）：Windows 日历仅为数据项+高亮，鸿蒙日历页（状态/头像/描述/版本号）已覆盖且更完整，无实质缺口 | S |
| ~~深渊数据完整性核对~~ ✅ | 已核对：敌人等级（TowerLevel.MonsterLevel → `Lv.x`）、渊月祝福、历史期、波次均已实现并展示；塔元数据 417 条完整；剧诗期次元数据（限定元素/特邀/初始角色）已补齐展示 | S |

---

## P2 体验提升

| 项 | 说明 | 规模 |
|---|---|---|
| 2in1 键盘导航 | 焦点链（Tab/方向键）、Enter 激活、常用快捷键（Ctrl+R 刷新、Esc 关弹层），对齐 PC 桌面应用习惯 | M |
| 无障碍 | 可点元素补 `accessibilityLabel`、朗读顺序、关键页对比度复核（深色品质色映射） | M |
| 动效一致性收尾 | `Motion.ets` 规范（spring 三档/riseIn/pageSwitch）已立，逐页排查遗漏的非规范动画 | S |
| 主题扩展 | 跟随系统三态之外，评估自定义强调色（Windows 主题色概念的鸿蒙化） | M |
| 分屏/自由窗口 | 平板分屏下断点表现验证与最小尺寸兜底 | S |

---

## P2 工程化

| 项 | 说明 | 规模 |
|---|---|---|
| GitHub Actions CI | push/PR 触发：`hvigorw assembleHap`（不签名，仅验证编译）+ `devecocli check lint` 0 error 门禁 | M |
| Release 工作流 | 打 tag → CI 构建 → 自动建 GitHub Release 附变更说明（未签名包 + 自签说明） | M |
| 单元测试 | 现有 test 目录是模板空壳。优先覆盖：`UigfService` 解析/导出（v4.2/v4.0/v3.x）、`DsSigner` 参数拼装、`GachaType` 映射、日期工具 | M |
| README 截图 | 补主页/祈愿/图鉴截图（**脱敏**：用测试账号截，不带真实 UID/昵称）+ CI badge | S |
| 依赖审计 | `oh-package.json5` 依赖最小化复核、lock 跟随提交 | S |

---

## P2 性能与体积

| 项 | 说明 | 规模 |
|---|---|---|
| HAP 瘦身 | rawfile 图标约 108MB（HAP ~179MB）。评估 pngquant 无损/近无损压缩与收益；名片大图等低频资源是否保留内置 | M |
| 图片内存策略 | MetaIcon 增加 LRU 解码缓存、长列表按需解码尺寸（List/Grid 滚动场景） | M |
| 启动性能 | 冷启动耗时打点（启动页→首页可交互），Icon 256² 已达标，排查其余首帧阻塞 | S |

---

## P3 平台能力（需人工/AGC 配合，逐项确认后做）

| 项 | 说明 | 依赖 |
|---|---|---|
| 更多桌面卡片 | 现仅实时便笺卡。增：祈愿保底进度卡 / 活动日历卡（ArkTS 卡片，`@Local` 变量名与 Form 推送键一致，严禁回退 @Entry(storage) 写法） | 无 |
| Push Kit 提醒 | 签到/树脂已满系统通知（本地通知已有）；Push 走云端需要 AGC 开通推送服务，需用户人工配置 | AGC |
| Live View 实况窗 | 长任务（全量刷新/备份导出）进度实况化 | API 门控评估 |

---

## 明确不做（护栏重申）

- 胡桃云全线：通行证、云备份、云统计、云攻略、云壁纸、反馈中心
- 注入类：背包内存读取、插件管理、游戏内悬浮窗、注册表切号、启动游戏进程链
- 外服（B 服 / 国际服）端点与多语言（i18n 暂不做，界面中文）
- 应用市场自动分发（保持 GitHub Release 手动安装路线）

---

## 里程碑建议

- ~~**v1.1**：P0 还债 + P1 主体（期次历史 / 名片 / 攻略外链 / 版本检查 / 立绘浏览 / 备份还原）~~ ✅ 已随 e27abe7 / 0a61a6b / 后续立绘提交落地
- **v1.2**：P2 工程化（GitHub Actions CI / Release 工作流 / 单测）+ P0 lint 还债
- **v1.3+**：P2 体验与性能按反馈排期，P3 按平台条件逐个解锁
