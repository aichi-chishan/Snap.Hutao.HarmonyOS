# Snap.Hutao.HarmonyOS

> 胡桃工具箱（Snap.Hutao）的鸿蒙（HarmonyOS）移植版 · 原神玩家的一站式工具箱

把 Windows 版 [Snap.Hutao](../../)（胡桃启动器）完整移植到 HarmonyOS（API 23 / HarmonyOS 6.1.0），
PC / 平板 / 手机三端适配，界面与功能对齐 Windows 版，仅保留国服（米哈游国服 API）。

![HarmonyOS](https://img.shields.io/badge/Platform-HarmonyOS%206.1.0-007DFF)
![API](https://img.shields.io/badge/API-23-blue)
![License](https://img.shields.io/badge/License-MIT-green)

---

## ✨ 功能总览

### 主页仪表盘
- **欢迎横幅** + 活动日历（卡池横幅 / 渊月螺旋 / 幽境危战 / 幻想真境剧诗等实时进度）
- **祈愿记录卡**：各池抽数、保底进度、距五星/四星垫数
- **成就管理卡**：完成度环形进度 + 原石获得情况
- **实时便笺卡**：树脂 / 洞天宝钱 / 每日委托 / 周本折扣 / 参变仪
- **每日签到卡**：本月已签天数 + 31 天奖励网格
- **周期挑战卡**：深境螺旋 / 幻想真境剧诗 / 幽境危战三格进度
- **日历卡**：日期事件标记 + 今日材料 + 今日角色生日
- **游戏公告**：活动 / 游戏 / 系统公告预览

### 工具模块
| 功能 | 说明 |
|---|---|
| 🔮 **祈愿记录** | 五池统计（总抽 / 平均抽数 / 最非最欧 / UP 平均）+ 五星头像网格 + 历史列表 + UIGF 导入导出 |
| 🏆 **成就管理** | 73 分类 / 1844 成就，多档案管理、分类筛选、搜索、UIAF v1.1 导入导出、手动勾选 |
| ⏰ **实时便笺** | 树脂 / 宝钱 / 委托 / 折扣 / 参变仪 + 阈值通知 + 自动刷新 |
| 👤 **我的角色** | 81 角色列表 + 详情（武器 / 圣遗物评分 / 面板属性 / 命座） |
| 📈 **养成计划** | 勾选角色 + 目标等级 → 批量计算材料消耗清单 |
| 🎮 **启动游戏** | 一键拉起本机已安装的原神 APP |

### 周期挑战
- **深境螺旋**：总星数 / 最深层 / 层列表 / 六项排行（满星/击败/伤害/承伤/普攻/爆发）
- **幻想真境剧诗**：奖章 / 历战 / 回合详情 / 卡牌
- **幽境危战**：单挑 / 联机切换、最佳队伍、最强一击 / 最高总伤害、怪物与档期

### 数据资料
- **角色资料**：118 角色全量图鉴（简介 / 养成材料 / 天赋 / 命座 / 料理 / 语音 / 故事 / 等级曲线）
- **武器资料**：246 武器（基础数值 / 精炼 1-5 / 养成材料 / 等级滑条）
- **怪物资料**：560 怪物（基础数值 / 8 项抗性 / 掉落物 / 等级曲线）

### 系统
- **账号与数据**：米游社多账号管理、Cookie 五件套自动打桩、绑定角色与默认 UID
- **设置**：主题（浅/深/跟随系统）、氛围光、背景图片（无/本地随机/必应每日一图）、
  游戏数据更新（GitHub 清单 + 一键下载）、深浅色、通知

---

## 🛠 技术架构

```
pages → viewmodel → service → data(repo/network) → model
页面    状态容器       业务逻辑    数据层(DB/网络)     数据模型
```

- **ArkTS 严格模式**：禁止 `any`、未类型化对象字面量，全类型注解
- **数据流向**：`service` 拉取 → `repo` 落库（SQLite）→ `viewmodel` 聚合 → `pages` 渲染
- **网络层**：统一 `ApiClient`（Cookie 注入 / retcode 归一化 / 友好化错误）+ `DsSigner`（DS Gen1/Gen2 签名）
- **风控处理**：1034 风控自动检测 → 极验人机验证 → `x-rpc-challenge` 重放链（对齐 Windows）
- **安全**：Cookie Token 本地加密存储（TokenVault）
- **UI 材质**：HdsTabs 光感材质、PressCard 按压点光源 + 弹性缩放、背景壁纸层（渐变 / 本地图 / 必应）
- **深浅色**：资源色 `$r('app.color.xxx')` base/dark 双色定义，跟随系统 / 手动切换

### 目录结构

```
entry/src/main/ets/
├── pages/          # 页面（@Entry，多数带 @Prop embedMode 宽屏内嵌）
├── viewmodel/      # 页面状态容器（@Observed）
├── service/        # 业务逻辑（单例）
├── components/     # 复用组件（MetaIcon/PressCard/NavIcon/WallpaperLayer/Home*Card）
├── data/
│   ├── db/         # SQLite 封装（snap_hutao.db）
│   ├── network/    # ApiClient/HoyolabClient/DsSigner/RiskVerifier/DeviceFpApi
│   ├── repo/       # CRUD
│   ├── prefs/      # PreferencesStore
│   └── remote/     # GameDataUpdater/ResourcePackService/StandardIconService
├── model/          # 数据模型 + fromJson
└── common/         # 常量/日志/工具
```

---

## 📦 游戏数据来源

游戏元数据（角色/武器/怪物/材料/曲线表）来自 [Snap.Metadata](https://github.com/SnapHutaoRemasteringProject/Snap.Metadata) 公开仓库提取，
打包于 `entry/src/main/resources/rawfile/metadata/`；图标 PNG 打包于 `rawfile/icons/`（约 108MB，离线可用）。

扩展素材（角色立绘 / 名片等大图）通过 **GitHub 清单** 动态拉取：
`rawfile/icons/` 缺失的图标按 `https://api.snaphutaorp.org/static/raw/{Category}/{Name}.png` CDN 规则兜底下载，
或由用户在应用内「设置 → 游戏数据更新 → 立即更新」一键拉取全量数据。

> 数据仓库 `github-data/` 为独立仓库（[aichi-chishan/snap-hutao-data](https://github.com/aichi-chishan/snap-hutao-data)），
> 包含 3055 项图标 + 元数据清单，不随本仓库提交。

---

## 🚀 构建与运行

### 环境要求
- DevEco Studio 5.x（HarmonyOS 6.1.0 SDK，API 23）
- Node.js 18+、hvigor

### 构建 HAP
```bash
# DevEco Studio 自带 hvigor
E:\APP\DevEco Studio\tools\hvigor\bin\hvigorw.bat assembleHap \
  --mode module -p module=entry@default -p product=default --no-daemon
```

签名：克隆后请在 DevEco Studio「File → Project Structure → Signing Configs」中启用自动签名
（存储的签名密钥不随仓库公开）。

### 安装到设备 / 模拟器
```bash
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```
> 若报 `install sign info inconsistent`：先 `hdc uninstall com.example.snaphutaoharmonyos` 再安装
> （旧版本签名不同，系统拒绝覆盖）。

### 模拟器
```bash
devecocli emulator start "MateBook Pro"      # 2in1
hdc list targets
```

---

## 🔐 登录说明

所有战绩数据（角色 / 便笺 / 深渊 / 剧诗 / 幽境 / 签到）都需要米游社账号的 Cookie 五件套。
进入「账号与数据 → 添加账号」通过内置 WebView 登录米游社，或粘贴 Cookie 字符串；
应用自动补齐 Token 链（SToken → LToken → cookie_token）并绑定默认游戏 UID。

> 请使用自己的账号。任何账号数据仅保存在本机 SQLite（Token 加密存储），不上传任何服务器（无胡桃云）。

---

## ❌ 不移植内容

与 Windows 版保持一致，以下功能**不在本移植范围**：

- **胡桃云服务**：通行证 / 云备份 / 云统计 / 云攻略 / 云壁纸 / 反馈中心
- **注入类功能**：背包内存读取 / 插件管理 / 游戏内悬浮窗 / 注册表切号 / 游戏进程链启动
- **国际服**：仅提供国服（米哈游国服 API）

---

## 📄 许可证

MIT License。本项目与米哈游（miHoYo）无关，数据与图标版权归米哈游所有，仅供学习交流使用。

---

## 🙏 致谢

- [Snap.Hutao (Windows 版)](https://github.com/DGP-Studio/Snap.Hutao) —— 原始功能设计与 UI 基准
- [Snap.Metadata](https://github.com/SnapHutaoRemasteringProject/Snap.Metadata) —— 游戏元数据
- [paimon-moe](https://github.com/paimon-moe) —— 成就元数据
- 米哈游游戏社区 —— 接口与资料参考
