# AGENTS.md — Snap.Hutao.HarmonyOS

这是把 Windows 版胡桃启动器（Snap.Hutao）移植到鸿蒙（HarmonyOS/ArkTS）的项目。开发前请先读本文件，避免踩坑。

## 项目定位
- 移植 Windows 版胡桃工具箱（Snap.Hutao，见 GitHub DGP-Studio/Snap.Hutao）到鸿蒙，PC/Pad 力求还原，手机优化布局。
- **这是 API 23 的鸿蒙 APP**（compatibleSdkVersion = 6.1.0(23)，targetSdkVersion = 26.0.0，runtimeOS = HarmonyOS）。设备类型：phone / tablet / 2in1。
- **不移植**：所有胡桃云服务器功能（通行证/云备份/云统计/云攻略/云壁纸/反馈页）与注入类功能（背包内存读取/插件/游戏内悬浮/注册表切号/启动游戏进程链）。
- 仅国服（米哈游 API 用国服端点）。

## 关键环境与工具（务必利用）
- **35 个鸿蒙开发 skill** 在 `skills/` 目录：`hmos-arkui-develop-skill`、`hmos-arkts-syntax-checker`、`hmos-multidevice-*`、`hmos-arkui-mvvm-pattern`、`hmos-*crash-analysis` 等。改 UI/ArkTS/多设备适配前先查相关 skill。
- **DevEco CLI**：`devecocli`（npm 全局，`PATH` 含 npm 全局目录）。常用：`devecocli build` / `devecocli check lint` / `devecocli emulator list|start|stop` / `devecocli skills list|add`。
- 编译：`hvigorw.bat assembleHap --mode module -p module=entry@default -p product=default --no-daemon`（DevEco Studio 自带，也可 `devecocli build`）。
- 模拟器：`devecocli emulator start "MateBook Pro"`（2in1）；hdc 在 SDK 的 `openharmony/toolchains/hdc.exe`。

## 目录结构
- `entry/src/main/ets/pages/`：页面（ArkTS @Entry/@Component），多数带 `@Prop embedMode`（宽屏内嵌去返回栏）。
- `entry/src/main/ets/service/`：业务逻辑（网络请求、元数据、计算）。命名 `XxxService`，多数单例。
- `entry/src/main/ets/viewmodel/`：页面状态容器（@Observed）。
- `entry/src/main/ets/model/`：数据模型 + `fromJson` 解析。
- `entry/src/main/ets/components/`：复用组件（`MetaIcon`/`PressCard`/`NavIcon`/`WallpaperLayer`/`Home*Card`）。
- `entry/src/main/ets/data/`：`db`（relationalStore SQLite 封装）、`network`（HoyolabClient/ApiClient/DsSigner/RiskVerifier）、`prefs`（PreferencesStore）、`remote`（ResourcePackService 云端资源包）、`repo`（CRUD）。
- `entry/src/main/ets/common/`：常量、日志、工具。
- `entry/src/main/ets/widgets/pages/`：ArkTS 桌面卡片（@ComponentV2，@Local 变量名与 Form 推送键一致，严禁回退 @Entry(storage) 写法）。
- `entry/src/main/resources/rawfile/metadata/`：本地元数据（从 Snap.Metadata 提取：avatar/weapon/monster/material + 曲线表）。
- `entry/src/main/resources/rawfile/icons/{Category}/`：打包图标（AvatarIcon/EquipIcon/MonsterIcon/Skill/Talent/ItemIcon 等，约 108MB）。
- `skills/`：35 个鸿蒙开发 skill（只读，勿改）。
- `example/`：Windows 版界面截图（参考 UI）。
- `PORTING_PLAN.md`：Windows 版对齐方案（导航/主页/背景图/图标/图鉴）。

## 架构与分层规则（重要）
- 严格分层：`pages → viewmodel → service → data(repo/network) → model`。页面不直接发网络请求、不直接拼 SQL；Service 不写 UI。
- 数据流向：`service` 拉取 → `repo` 落库 → `viewmodel` 聚合 → `pages` 渲染。
- 配色用资源色 `$r('app.color.xxx')`（base + dark 双色定义在 `resources/base|dark/element/color.json`）。**禁止用硬编码 hex 颜色字符串**（深浅色切换会失效、可读性差）——文字/背景/边框必须用 `$r`，元素色映射（七元素/品质色）例外。
- 背景：`WallpaperLayer` 支持 none（透传桌面+高级模糊）/local（本地随机）/bing。深色用 `isDarkMode`（AppStorage）实时切换。

## 编码约定
- ArkTS 严格模式：**禁用未类型化的对象字面量**（`{a:1}` 必须对应显式 class/interface）、禁用 `any`、`const`/`let` + 类型注解。
- 若为数组/Map/对象字面量，先声明 class 再 new；`@State` 数组整体赋值触发刷新。
- 颜色组件（文本/图标）注意换行符：部分文件是 **CRLF**，用 `\r\n` 精确匹配，或读后逐行处理。
- 新页面必须在 `resources/base/profile/main_pages.json` 注册 route，并在 `Index.ets` 的 `sideNav()`/`wideContent()` 接线。
- 宽屏/窄屏用 `isWide = width >= 840`（onAreaChange 驱动）。

## 已知坑（Do NOT trip）
- **空 UID 归档坑**：未登录时 `GachaRepo.getOrCreateArchive('')` 会建空归档覆盖默认 UID 逻辑。`HomeViewModel`/`GachaLogViewModel` 已在 uid 为空时跳过创建。改动相关逻辑必须守住这点。
- **主题三态**：跟随系统 = `EntryAbility.onConfigurationUpdate` 监听系统 → 写 `AppStorage.isDarkMode`；设置页 `applyTheme` 需同步 `themeMode` state。三态（浅/深/跟随系统）判定别写死。
- **`@Entry` + `@Prop embedMode`** 编译会有 WARN（非错误），可用。
- **图片资源**：优先 `MetaIcon`（$rawfile 离线）；rawfile 缺失时 `remoteFallback` 走 `ResourcePackService` 云端缓存。勿直接拼不存在的路径。
- **技能/怪物描述**含米哈游富文本 `<color=#>` / `{LINK#}`，用 `WikiMetaService.cleanText()` 清洗后再显示。

## 验证
- 改完 `hvigorw ... assembleHap` 编译通过（`BUILD SUCCESSFUL`）。
- 模拟机装机：`hdc shell bm uninstall -n com.example.snaphutaoharmonyos` → `hdc file send <hap> data/local/tmp/entry.hap` → `hdc shell bm install -p data/local/tmp/entry.hap` → 启动。
- 若报 `install sign info inconsistent`：先卸载旧包再装（旧版本签名不同，系统拒绝覆盖）。

## 命令执行安全原则（务必遵守）
- **执行命令要极其谨慎**：任何可能影响系统/删除/覆盖/关机/安装的命令，先确认其影响范围与证据，再执行。宁可让某些中间文件/原始文件留着占空间，也**不要**执行可能破坏电脑、破坏仓库、误删源码、关机重启之类的危险命令。
- 不主动 `rm -rf`、不批量删除源码或 `entry/src/main/resources` 下的资源；清理仅限明确自己创建的临时物（截图、临时脚本）。
- 不动 `build-profile.json5` 里的签名密钥/密码，不提交 `local.properties`（含本地路径）。
- 不修改 `skills/` 目录内容，不修改 `.zcode/` / `.agents/` 等工具配置。
- 关机、卸载系统组件、修改系统级配置等一律不做；如需用户决策，停下来问，而非擅自执行。
- 模拟器/设备命令（`devecocli emulator stop/shake`、`hdc shell bm uninstall` 等）仅在明确需要时使用，且只影响模拟器不伤宿主机。

## 变更敏感区
- 改导航（Index.ets）/首页卡片/背景/图标资源前，先看 `PORTING_PLAN.md` 了解 Windows 对齐目标。
- 改登录/风控（RiskVerifier/Geetest）前，先读 `data/network/` 下相关文件，别破坏 1034 重放链。
