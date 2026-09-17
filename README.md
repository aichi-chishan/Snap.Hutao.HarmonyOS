# Snap.Hutao.HarmonyOS

> 胡桃工具箱（Snap.Hutao）的鸿蒙（HarmonyOS）移植版 · 原神玩家的一站式工具箱

把 Windows 版 [Snap.Hutao](https://github.com/DGP-Studio/Snap.Hutao)（胡桃启动器）移植到
HarmonyOS（**compatibleSdkVersion 6.1.1(24)** / targetSdkVersion 26.0.0），手机 / 平板 / PC（2in1）
三端自适应布局，界面与功能对齐 Windows 版，仅支持国服（米哈游国服 API）。

![Platform](https://img.shields.io/badge/Platform-HarmonyOS%206.1.1-007DFF)
![API](https://img.shields.io/badge/API--24-blue)
![License](https://img.shields.io/badge/License-MIT-green)

[![CI](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/actions/workflows/ci.yml/badge.svg)](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/actions/workflows/ci.yml)

> 🗺️ 后续完善计划（功能补全 / 体验优化 / 工程化 / 性能）见 [ROADMAP.md](ROADMAP.md)

> ⚠️ **免责声明**：本项目与米哈游 / HoYoverse 无任何关联，仅供学习交流使用。
> 不包含任何注入、内存读取、进程注入类功能；不包含胡桃云（通行证 / 云备份等）在线服务。

---

## ✨ 功能总览

### 主页（对齐 Windows 仪表板布局）
- **卡池横幅**（左上合框）：角色 UP / 武器 UP 横幅，UP 阵容头像 + 剩余时间 + 起止日期
- **活动与挑战**（右上合框）：渊月螺旋 / 幻想真境剧诗 / 铸境研炼等剩余时间与状态（可在设置隐藏）
- **仪表板卡组**（UniformPanel 语义）：启动游戏 | 祈愿统计（保底进度）| 成就统计 | 实时便笺 | 旅行者札记 | 日历 | 每日签到
  ——列数按内容区宽度自适应（最小列宽 300vp / 间距 12vp），卡片恒高 **204vp**（对齐 Windows `HomeAdaptiveCardHeight`），行内等高
- **胡桃每日一图**：Snap.Hutao 公开壁纸接口，当日缓存；按图片亮度自适应透明度（全量复刻 Windows 合成），亚克力卡片材质（浅/深双主题）
- **游戏公告**：官方封面图 + 标题，点击查看详情；**前瞻直播兑换码**一键查询复制

### 工具
| 模块 | 说明 |
|---|---|
| 启动游戏 | 检测并拉起本机已安装的原神（不做注入 / 进程链 / 切号） |
| 祈愿记录 | 常规五池 + **千星奇域（颂愿）**总览统计（总抽 / 平均 / 最非最欧 / UP 平均）、五星头像网格、SToken 自动重签刷新、**UIGF v4.2** 导入导出（含 hk4e_ugc，兼容 v4.0 / v3.x）、剪贴板 URL 导入 |
| 成就管理 | 73 分类 / 1800+ 成就、多档案、分类筛选搜索、UIAF v1.1 导入导出 |
| 实时便笺 | 树脂 / 派遣 / 每日委托 / 周本折扣 / 洞天宝钱 / 参变仪，阈值系统通知，自动刷新（半屏设置弹窗） |
| 我的角色 | 角色面板 / 圣遗物评分（Windows 加权算法）/ 名片专属背景 / 武器信息 |
| 养成计划 | 养成目标 + 材料清单计算 |
| 深境螺旋 / 幻想真境剧诗 / 幽境危战 | 当期 / 上期战绩、奖章 / 回合统计、敌方阵容真图标 |
| 角色资料 / 武器资料 / 怪物资料 | 本地元数据百科：属性数值曲线滑条、天赋 / 命座 / 精炼 / 抗性 / 掉落，离线可用 |
| 账号与数据 | 扫码 / 验证码登录（极验自动处理）、多账号切换、角色绑定 |

### 风控对抗（对齐 Windows RetryIf1034Async 链路）
- 战记接口 1034 → createVerification → 统一验证浮层（极验）→ challenge 重放
- 登录 aigis 会话（x-rpc-aigis）自动验证重放；签到体内极验 challenge+validate+seccode 重放
- **极验自定义组合接口**（设置 → 无感验证）：配置 `{0}`=gt、`{1}`=challenge 模板后，触发验证时优先自动过验，失败回退弹窗
- SToken 自动生成 authkey（genAuthKey）；GitHub 直连失败自动回退公共镜像

### 多端适配
- 手机：底部 HdsTabs 悬浮页签（沉浸光感材质）
- 平板 / PC：侧边栏导航 + 双栏内容，自由窗口最小尺寸保护，窗口自适应断点（720 / 840 / 1200）
- 沉浸光感（systemMaterial / ImmersiveMaterial，API 26 运行时门控自动回退）

---

## 🧪 质量与自动化

| 项 | 说明 |
|---|---|
| 单元测试 | `entry/src/test`（hypium Local Test，纯逻辑：圣遗物评分 / 祈愿类型 / 富文本清洗 / 日期工具） |
| CI | `.github/workflows/ci.yml`：仓库不变量 + 隐私门禁 + lint（0 error 门禁）+ 无签名 HAP 构建 |
| 回归清单 | [docs/TESTING.md](docs/TESTING.md)（实机验证逐项打勾） |
| 隐私门禁 | CI 自动扫描已跟踪文件中的私人邮箱 / 本机绝对路径，命中即失败 |

CI 的 lint/build job 需要华为 Command Line Tools（无公开直链）：在仓库
Settings → Secrets and variables → Actions → Variables 配置 `DEVECO_CLT_URL` 后自动启用，未配置则跳过。

---

## 🔧 构建要求

| 项 | 版本 |
|---|---|
| [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) | 26.0.0（5.1.x 及以上需自行验证） |
| HarmonyOS SDK | 26.0.0（API 26 编译） |
| compatibleSdkVersion | 6.1.1(24) |
| 真机 / 模拟器 | HarmonyOS 6.1.1(24)+ |

### 步骤

```bash
git clone https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS.git
```

1. 用 DevEco Studio 打开工程
2. `build-profile.json5` **不入库**（含本地签名）：首次构建前在 DevEco 中
   File → Project Structure → Signing Configs 勾选 Automatically generate，并把 compatibleSdkVersion 配为 `6.1.1(24)`
3. 构建：`hvigorw.bat assembleHap --mode module -p module=entry@default -p product=default --no-daemon`
4. 真机安装：`hdc file send entry/build/default/outputs/default/entry-default-signed.hap /data/local/tmp/entry.hap`
   → `hdc shell bm install -p /data/local/tmp/entry.hap`

> 模拟器注意：仅 HarmonyOS 6.1.1(24) 及以上镜像能安装本包（API 23 镜像装不上 compatibleSdkVersion 24 的包）。
> Git Bash 下 `hdc file send` 的源路径须为裸文件名，`bm install` 前加 `MSYS_NO_PATHCONV=1`。

---

## 📦 素材与元数据

- 元数据（角色 / 武器 / 怪物 / 成就 / 曲线，17 个 JSON）与图标（**3754 张 PNG，约 233MB**）**全部内置安装包**，离线可用
- 素材来源：[Snap.Metadata](https://github.com/DGP-Studio/Snap.Metadata)（精简提取）+ 胡桃静态 CDN
- 角色立绘（`GachaAvatarIcon`，58MB / 118 张）虽已内置，但按需场景优先走静态 CDN + 沙盒缓存
- 更新管线：独立数据仓库 [aichi-chishan/snap-hutao-data](https://github.com/aichi-chishan/snap-hutao-data)：`python fetch-assets.py` 增量拉素材 → `gen-manifest.ps1` 重出清单（改 channelVersion）→ push；APP 设置 → 游戏数据更新即热更，**无需整包更新**
- 云端热更：默认清单已指向 `aichi-chishan/snap-hutao-data`，设置页可改数据源地址

---

## 🗂️ 工程结构

```
entry/src/main/ets/
├── pages/        页面（@Entry / 内嵌组件，宽屏 embedMode）
├── viewmodel/    页面状态容器（@Observed）
├── service/      业务逻辑（网络 / 元数据 / 计算）
├── data/         db(SQLite) / network(Hoyolab 客户端+DS 签名) / prefs / repo / remote(数据热更)
├── model/        数据模型 + fromJson
├── components/   复用组件（MetaIcon / PressCard / Home*Card）
├── common/       常量 / 日志 / 动效(Motion) / GitHub 镜像
└── widgets/      桌面卡片（实时便笺）

entry/src/main/resources/
├── base|dark/element/color.json   主题色（深浅双定义，代码一律 $r('app.color.x')）
└── rawfile/
    ├── metadata/   本地元数据（17 个 JSON，远端可热更、rawfile 兜底）
    ├── icons/      游戏素材图标 3754 张（按 Category 分目录）
    └── nav/        导航图标

ci/               CI 专用构建配置（无签名）
docs/             测试与回归清单
.github/workflows CI（不变量 + 隐私门禁 + lint + 构建）
```

分层规则：`pages → viewmodel → service → data(repo/network) → model`，页面不发网络请求、不拼 SQL。

---

## 🔐 隐私

- 所有账号数据（Cookie / SToken）仅存储在**设备本地**数据库与偏好文件中，经加密保存
- 本项目**不包含任何遥测 / 数据上报**；网络请求仅发往米哈游官方 API 与 GitHub 资源源
- 仓库不含任何签名密钥、账号信息与调试产物（详见 .gitignore）
- CI 设有**隐私回归门禁**：自动扫描已跟踪文件中的私人邮箱与本机绝对路径，命中即构建失败
- 提交者身份使用 GitHub noreply 邮箱，不暴露真实邮箱

---

## 🙏 致谢

- [DGP-Studio/Snap.Hutao](https://github.com/DGP-Studio/Snap.Hutao) — Windows 版原项目（MIT）
- [Snap.Metadata](https://github.com/DGP-Studio/Snap.Metadata) — 元数据
- [UIGF 组织](https://uigf.org/) — 统一祈愿/成就交换标准
- [ZCode Weekend Build](https://github.com/zai-org) — AI 结对开发（ZCode）

## 📄 许可证

[MIT](LICENSE)（与上游 Snap.Hutao 一致）
