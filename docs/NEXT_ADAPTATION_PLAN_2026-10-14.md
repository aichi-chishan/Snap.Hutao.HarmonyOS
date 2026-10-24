# 下一步适配计划（2026-10-14 复核）

> **2026-10-24 注记**：上游基线已推进到 Remastered main `3b7475e`（2.0.2.0）；本文档的 G1-G8/U1-U4（P0/P1 批次）已完成，剩余项已并入 [GAP_2026-10-24.md](GAP_2026-10-24.md) 统一排期（G9→7B、G11→7A、G10/G12/LiveView/Push 不做）。compatibleSdkVersion 已升 26.0.0（API 24 兼容基线废止，见 docs/BUILD_ENVIRONMENT.md 顶部注记）。

> 本计划基于对当前 HEAD `88bc804` 的代码复核 + 构建/lint/主机测试实测，聚焦**与 Windows 版（Remastered `3f0d1f3` / v1.20.3）对齐的缺陷与 UI/UX 差距**。
> 范围护栏不变：仅国服；不做注入/内存读取；不含胡桃云在线服务。**不新增与 Windows 对齐无关的功能。**

## 0. 实测基线（本轮亲自复现）

| 项 | 结果 |
|---|---|
| `hvigorw assembleHap` | **BUILD SUCCESSFUL**（12s，全部 UP-TO-DATE） |
| `devecocli check lint` | 51 issues / **0 errors** / 47 warnings / 4 suggestions（28 files） |
| 主机回归 `node tests/run.cjs`（pinned TS 5.9.3） | **6/43 套件在 Windows 失败**，全部为**路径分隔符**artifact（`path.relative` 在 Windows 返回 `\`，测试按 `/` 断言）；已在上一提交 `1e0ab36` 的工作树上复现同样 6 条失败 ⇒ **非本轮回归** |
| HAP 体积 | 244.7 MB（rawfile 231.9 MB，其中 icons 224.1 MB） |
| 模拟器 | MateBook Pro 24（2in1 / API 24）可用；当前无设备连接（hdc targets 空） |
| 上游基线 | Remastered main 仍为 `3f0d1f363a8226cccd76f0f66f599e729b0f214c`（v1.20.3，2026-09-22） |

失败套件（Windows 专用 artifact）：`game-data-cohort`、`snapshot-quota-traversal`、`standard-icon-cache`、`regional-content`、`reduce-motion`、`lint-report-gate`。

---

## 0.1 执行结果（本轮已完成）

| 批次 | 状态 | 交付证据 |
|---|---|---|
| **P0-1 壳层语义路由** | ✅ | `Index.ets` 新增独立 `phoneTab` + `phoneTabToIndex`/`indexToPhoneTab`/`syncPhoneTabForCurrentPage`/`switchPhoneTab`；手机页签与宽屏页标识解耦，跨 720vp 断点不再错页；`switchTo` 保持原签名与刷新语义（`motion-consumers` 断言不变） |
| **P0-2 @Builder 多参刷新** | ✅ | 修复 `WikiAvatarPage.propCell`、`WikiMonsterPage.monStat`、`GachaLogPage.avatarSection` 三处「参数含会变字段」→ 改常量槽位 + 渲染期读状态 |
| **P0-3 可读性（对比度）** | ✅ | 新增 `app_primary_text`/`on_accent`/`image_scrim`/`image_scrim_soft`（base+dark 成对）；123 处 `fontColor(app_primary)` → `app_primary_text`；36+11 处白字落品牌填充 → `on_accent`；`text_secondary` 3.43→5.27；4 处硬编码遮罩 hex 改资源色 |
| **P0-3 图标去 emoji** | ✅ | `NavIcon` 新增 `sys.symbol.*` 通道（`SymbolGlyph`，跟随主题色）：Setting/Menu/Delete/Close/Check/Airplane/Calendar；替换 `⚙️`×3、`☰`、`🗑`、`✕`×3、`⚙`×2、`✈`、顶栏勾选 |
| **P0-4 无障碍** | ✅ | 10+ 处自绘控件补 `accessibilityText`+`accessibilityLevel`（壳层返回/折叠、风控取消、登录关闭、便笺移除/设置、养成新建/删除、公告返回） |
| **P1-1 图标与列表性能** | ✅ | `MetaIcon` `RAW_CACHE` 加 512 条有界 LRU；`BackpackPage`/`WishHistoryPage` 长列表补 `cachedCount(5)`；`WikiAvatarPage` Swiper 加 `onAnimationStart` 预载（对齐 Windows 相邻立绘预取） |
| **P1-2 lint 还债** | ✅ | 循环内状态读写全部改局部快照：**51 → 26 issues**（`no-state-var-access-in-loop` 21→0，`use-reusable-component`/`cachedCount` 等一并收敛），**Errors 始终为 0** |
| **P1-3 本地可验证性** | ✅ | 6 个 Windows 失败套件全部修复：**39/39 主机套件本地通过**（原 33/39）。根因均为路径分隔符 artifact，非产品缺陷 |
| **U2/U3 Windows 导航对齐** | ✅ | 手机「我的」由平铺 19 项改为 **工具/周期/数据/日常/系统** 分组（对齐 Windows NavigationView），补回缺失的「旅行者札记」；术语「强敌挑战」→「幽境危战」与侧栏/页面标题统一 |
| **U4 设置页分组** | ✅ | 按 Windows `SettingPage.xaml` 分组名对齐：**外观 / 存储 / 极验验证 / 账号 / 主页 / 其它**（Windows 为 应用行为→极验验证→外观→网络→存储→快捷键→主页→游戏→祈愿记录） |

**验证（本轮实测）**：`hvigorw assembleHap` BUILD SUCCESSFUL；`devecocli check lint` Errors **0**；`node tests/run.cjs` **39/39 通过**。

**跳过的用例均显式声明原因**（不计为通过）：主机禁用文件符号链接（Windows 需提权/开发者模式；目录用 junction 已验证）、无 bash / 无 python3（CI 在 Linux 执行）。

**未改动**（复核后判定无需改）：17 条 `avoid-overusing-custom-component` 是共享组件（`PageHeader`/`NavIcon`/`EmptyState` 等）的架构性提示，改 `@Builder` 会破坏 `@Prop` 状态语义；`AnnouncementService` 的 `JSON.parse(JSON.stringify)` 是缓存防御性拷贝（ArkTS 无 `structuredClone`）；`WallpaperLayer` effectKit 建议涉及大面渲染路径，保持现状。

---

## 1. 功能缺失（对齐 Windows，按证据排序）

| ID | 缺口 | 证据（当前代码） | Windows 对应 | 批次 |
|---|---|---|---|---|
| G1 | **跨断点错页**：手机与宽屏共用同一个数字 `currentIndex`，但语义不同（手机 2=便笺/3=我的；宽屏 2=成就管理/3=实时便笺） | `Index.ets:91,534,831-910` | NavigationView 页面标识与窗口尺寸无关 | **P0-1** |
| G2 | **`@Builder` 多参不刷新**：全仓 38 个 ≥2 参 `@Builder`，ArkUI 规则「多参 @Builder 内部 UI 不随状态刷新」 | `GachaLogPage:907/967/1182/1193/2127/2374/2399`、`RoleCombatPage:153/265/276`、`WikiAvatarPage`×4、`SpiralAbyssPage`×3、`Index:781/918/1449`、`CharacterPage`×2、`CultivationPage`×2 等 | —（ArkUI 平台约束） | **P0-2** |
| G3 | **可读性不达标**：浅色主色 `#FF6B35` 上白字 2.84:1；辅助字 `#8A8A90`/白 3.43:1（W3C 普通文字目标 4.5:1） | `resources/base/element/color.json` | Windows 有独立 accent/on-accent/次要文字角色 | **P0-3** |
| G4 | **无障碍缺失**：267 处 `.onClick`，显式 `accessibilityText` 仅 30 处/13 文件；`focusable`/`keyboardShortcut`/`inputConsumer` **全仓 0**；自绘 Row/Text 无名称/角色 | 全仓 grep | Windows 有键盘可达 + AutomationProperties | **P0-4** |
| G5 | **emoji 当图标**：188 行/62 文件使用 emoji 或符号字符（`⚙️``☰``★``◆``✓` 等）作图标/指示 | `Index:640,714,1151,1665`、`DailyNotePage:205,558,665`、`GachaLogPage:1232,1546,2426` 等 | Windows 用 `SymbolIcon`/素材 PNG | **P0-3** |
| G6 | **图标缓存无界**：`RAW_CACHE` 是无限增长 `Map`，无 LRU/上限 | `MetaIcon.ets:20,148-208` | — | P1-1 |
| G7 | **长列表未复用**：`@Reusable` 全仓 0；lint 7 处 `use-reusable-component` | lint 报告 | — | P1-1 |
| G8 | **循环内读状态变量**：lint 21 处 `no-state-var-access-in-loop` | lint 报告 | — | P1-2 |
| G9 | 服装/体型筛选（F17） | 元数据无 `costume`/`bodyType` 字段（`avatar_meta.json` 119 条仅有 name/icon/quality/…） | WikiAvatar 服装/体型筛选 | P2（需数据仓库） |
| G10 | 海外原生登录/验证闭环（F01） | 仅网页+Cookie；无密码/第三方/邮件二次验证 | `HoyoPlayPassportClientOversea` | P2（外部依赖） |
| G11 | UP 历史缺"未复刻时长"以外的期次导航（F18） | 仅当期/上期 chip | 完整期次列表 | P2 |
| G12 | 无 Release 工作流 | `.github/workflows/` 仅 `ci.yml` | — | P2 |

**已确认不再是缺口**（本轮核实）：云服务实现已移除且无残留引用；`MetaIcon` rawfile 动态路径已修复；`HomeDailyNoteCard` emoji 已改素材；成就页 `Scroll` 套 `List` 卡死已修；`GachaPredictionService` 已随云功能按范围移除（占位页已声明不做）。

---

## 2. UI/UX 差距（对齐 docs/UI_UX_SPEC_API24_PLUS.md 与 Windows）

| ID | 差距 | 现状证据 | 目标 |
|---|---|---|---|
| U1 | 跨断点状态丢失（=G1） | 同上 | 便笺在 719↔720vp 切换仍是便笺 |
| U2 | 手机缺统一「全部功能」目录 | `mineTab` 是长 `entryCard` 列表（19 项），无分组工具目录 | 手机也按 Windows「工具/周期/数据」分组可达 |
| U3 | 术语不一致 | 导航「幽境危战」vs 手机卡「强敌挑战」；`entryCard('HardChallenge','强敌挑战')` | 全站同名 |
| U4 | 设置页无分组索引 | `SettingPage` 使用 15 个 `sectionTitle` 线性排列，无宽屏分组索引 | 宽屏分组定位 |
| U5 | 图标混用 emoji | 同 G5 | 系统符号/素材 |
| U6 | 点击目标与焦点 | 自绘控件无最小 44vp 保证与焦点环 | 44×44vp + focus |
| U7 | 返回栈语义 | 手机 `router.pushUrl`、宽屏 `switchTo` 两套；`Index:627-631` 手写 back 判定 | 统一返回规则 |
| U8 | 大字/长内容固定卡高 | 主页卡固定 204vp | 最小高度，不裁关键操作 |

---

## 3. 执行批次

### P0-1 壳层语义路由（修复 G1/U1/U2/U3/U7）
以**语义路由 id** 取代共享数字索引，宽窄切换不改变业务页面。
1. `Index.ets`：新增 `@State route: string`，保留 `currentIndex` 仅作呈现层派生。
2. `navItem`/`bottomTab`/`entryTile`/`entryCard` 接受 route id；高亮判定改 `this.route === id`。
3. `wideContent()` 改按 route id 分支；`switchTo(route)` 统一入口。
4. 手机 `HdsTabs` 用 `HdsTabsController.changeIndex()` 由 route 反查并同步（`HdsTabsController extends TabsController`，已核实 SDK 声明）。
5. 手机补分组工具目录（U2），术语统一（U3）。

### P0-2 `@Builder` 多参刷新审计（G2）
逐处判定「参数是否含会变字段 / ForEach 键是否含变动字段」；命中则改常量槽位 + 渲染期私有方法读状态，或把变动字段并入 ForEach key。

### P0-3 可读性与图标（G3/G5/U5）
1. 拆色角色：`accent_fill`/`on_accent`/`accent_text`/`text_secondary`，成对维护 base+dark；主按钮文字与链接改达标前景。
2. `⚙️``☰` 等 emoji 图标改系统 Symbol 或已有 `NavIcon` 素材；星级/元素符号保留但补文本/图形。

### P0-4 无障碍与键鼠（G4/U6）
可点自绘控件补 `accessibilityText`/`accessibilityLevel`；补齐键盘焦点（`focusable`/`defaultFocus`）与 Escape 关弹层；关键命令不依赖长按/悬停。

### P1-1 图标与列表性能（G6/G7）
`MetaIcon` RAW_CACHE 加 LRU 上限；长列表补 `cachedCount`/`@Reusable`。

### P1-2 lint 还债（G8）
21 处循环内状态读取先取快照；17 处过度自定义组件复核。

### P1-3 恢复本地可验证性
主机套件改分隔符无关（`path.sep` 归一化），不改断言强度 —— 让 Windows 本地能跑出与 CI 相同结论。

### P2（按需/受限）
G9 服装体型（需数据仓库）、G10 海外原生登录（外部依赖）、G11 期次导航、G12 Release 工作流、LiveView、Push（需 AGC）。

---

## 4. 每批验收

- `hvigorw assembleHap ... --no-daemon` → `BUILD SUCCESSFUL`
- `devecocli check lint` → Errors 保持 0，warnings 不增加
- 主机回归：P1-3 完成后 Windows 本地应全绿（43/43）
- 模拟器 MateBook Pro 24 装机：跨 720vp 切换页面不错页；主页/图鉴/祈愿卡片正常刷新
- 不引入新的硬编码 hex、`any`、匿名对象字面量；颜色一律 `$r('app.color.*')`