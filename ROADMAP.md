# ROADMAP — 未来完善规划

> 基于 2026-09 对 Windows 版（Remastered-latest）的全量功能对齐审计 + 本轮真机验证经验整理。
> 范围护栏（长期不变）：**仅国服**；**不做注入/内存读取类功能**；**不含胡桃云在线服务**（通行证/云备份/云统计/云攻略/云壁纸/反馈）；隐私数据仅存本地。
> 优先级说明：P0 = 稳定与还债（最优先）→ P1 = 功能补全 → P2 = 体验/工程化 → P3 = 平台能力。规模：S（半天内）/ M（1-2 天）/ L（3 天+）。

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
| 风控兜底页复检 | `GeetestVerifyPage` / `RiskVerifyDialog` 仅作兜底保留（AGENTS.md 约定），确认统一浮层主链路覆盖后评估是否可退场 | S |

---

## P1 功能补全（对齐 Windows 的已知剩余项）

| 项 | 说明 | 规模 |
|---|---|---|
| 祈愿「历史记录列表」页签 | Windows 有完整逐条列表（当前用户选择保留总览精简形态）。可做成设置开关「详细历史」，默认关 | M |
| 角色立绘浏览 | 素材缺口：rawfile 目前无 `GachaSplashIcon` 类目。需 `fetch-assets.py` 扩展类目 + Wiki 角色页加 FlipView 立绘浏览器（对齐 Windows 角色详情立绘切换） | L |
| 名片展示页 | `NameCardIcon`/`NameCardPic` 已全部内置，纯 UI 工作：名片网格 + 点开大图（对齐 Windows 名片图鉴） | M |
| 攻略外链 | 角色武器详情页跳米游社攻略 / B站搜索（`router` 外链系统浏览器，对齐 Windows 攻略跳转） | S |
| 应用版本检查 | 现有「检查更新」仅覆盖**元数据热更**（GameDataUpdater）。新增 GitHub Releases API 查询最新 Release tag 与当前 versionName 比对 + About 页展示版本/构建信息 | M |
| 全量本地备份/还原 | 导出账号+祈愿+成就+养成+设置 为单一备份文件、导入还原。UIGF/UIAF 已覆盖祈愿/成就，此项解决换机迁移（Windows 有云备份，鸿蒙做本地等价物） | M |
| 日历/签到细节打磨 | 日历事件详情（跳公告）、签到补签状态反馈统一 | S |
| 深渊数据完整性核对 | 波次/渊月祝福/历史期 chips 已实现；对照 Windows 核对敌人等级、祝福词缀多语言取值细节 | S |

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

- **v1.1**：P0 全清 + P1 的 攻略外链 / 版本检查 / 名片展示（体感提升最直接）
- **v1.2**：P1 剩余（历史列表开关、立绘浏览、本地备份）+ CI/Release 工作流
- **v1.3+**：P2 体验与性能按反馈排期，P3 按平台条件逐个解锁
