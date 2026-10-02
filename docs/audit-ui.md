# UI、百科、日历与启动能力差距审计

审计日期：2026-10-02。对照本工作区 `upstream`（原官方最终源码）与 `upstream-remastered`（当前 main 快照）。以下路径中的 Windows 根目录为 `upstream-remastered/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/`，Harmony 根目录为 `entry/src/main/ets/`。行号为修改前基线，实施后可能移动。

本次用户明确要求“除了注入外的全量移植”，覆盖旧 `AGENTS.md` / `PORTING_PLAN.md` 中“云服务均不移植”等范围缩减。平台不可实现的能力须单独记录，不能算作已完成。

## 已具备的真实功能

- 三类百科已有离线数据、列表详情、属性等级曲线、技能/命座/语音/故事、武器精炼、怪物抗性/掉落；角色立绘翻页、名片和攻略外链也已实现（旧 PORTING_PLAN 的“未实现”过时）。
- 主页宽屏已有七张仪表板卡、活动区、卡池区、公告；设置已有卡片显隐/顺序、活动显示开关（`pages/Index.ets:1250`、`pages/SettingPage.ets:978`）。
- 角色文本导出已有单角色复制；并非完整 Windows 导出字段或全角色批量导出。

## 可执行缺口清单

| 优先级 | 缺口与证据 | 实施方案与验收 |
|---|---|---|
| P0 | 游戏拉起使用猜测 Android 包名、固定 `EntryAbility`，将查询权限错误一律当未安装：`service/GameLauncherService.ets:35-50,82-98`；manifest 仅申请 INTERNET。 | 删除未经验证的候选包。允许用户填写真实 HarmonyOS Bundle/Ability 或厂商公开 URI；保存选定目标、明确“未配置/无法查询/未安装/拉起失败”。不自动添加未知 scheme、不申请特权包查询权限。按已公开接口启动并展示底层错误码。 |
| P0 | API26 材质对象已门控，但 `.systemMaterial(...)` 调用仍无条件：`pages/Index.ets:701`、`components/RiskVerifyModal.ets:467`。 | 将调用放在 AttributeModifier 的能力分支内；API24 分支只执行已有模糊/主题底色。需 API24 真机/模拟器启动验证，不能只凭构建宣称兼容。 |
| P0 | 首页退出登录/切 UID 后旧数据未清空，旧异步请求还可能覆盖新用户：`viewmodel/HomeViewModel.ets:113-129,143-147,189-234`。 | 请求代数 + 切账号重置 + 完成前检查代数；未绑定 UID 不创建归档。测试 A 请求未完切 B、退出、同 UID 连续刷新。 |
| P1 | 角色百科筛选只有品质和名字，武器只有品质名字：`pages/WikiAvatarPage.ets:495`、`WikiWeaponPage.ets:220`。Windows 角色支持元素/所属/武器/品质/体型，武器支持类型/品质/副属性：`ViewModel/Wiki/AvatarFilter.cs:34-74`、`WeaponFilter.cs:34-59`。 | 增加模型已有字段的组合筛选（角色元素/武器、武器类型/副属性）；体型/所属需补全上游元数据后接线。为列表/网格模式追加持久化设置。 |
| P1 | 周历按设备本地时区而非游戏服务器时间、固定周一、聚合所有养成项目：`service/CalendarWeekService.ets:239-255,305-342`。 | 日期使用明确服务器时区、可配置每周首日；选择当前养成项目后只高亮该项目。 |
| P1 | Remastered 新增角色池开始后七天全部材料开放，Harmony 仍仅周日：`Model/Metadata/GachaEventSchedule.cs:11-34`、`ViewModel/Calendar/CalendarViewModel.cs:212-216`。 | 按 GachaEvent 301/400 的 From 转服务器日期，半开区间 `[start,start+7)`；共用算法供周历/养成材料规划。边界测试第 0/6/7 天、服务器跨日。 |
| P1 | 新版支持背景视频（本地随机/官方启动器、循环、静音）：`ViewModel/Setting/SettingAppearanceViewModel.cs:33-105`、`Service/BackgroundMediaPlayer/BackgroundMediaPlayerService.cs:75-168`。Harmony WallpaperLayer 仅图片。 | 视频源服务 + Video 组件，后台暂停/错误回退、文件授权持久化；官方视频沿 `Web/Hoyolab/HoyoPlay/OfficialLauncherClient.cs:23` 的接口解析，不能猜链接。 |
| P1 | Windows Bing/胡桃每日/官方启动器图片三种远程来源；Harmony 仅胡桃每日：`Service/BackgroundImage/BackgroundImageService.cs:163-170`、`pages/SettingPage.ets:685-729`。 | 使用相同客户端契约统一壁纸服务与缓存，恢复可用源；远端不可用返回显式状态，保留本地缓存。 |
| P1 | 角色只导出当前，字段明确省略武器属性、套装、命座技能加成：`service/CharacterExportService.ets:6-11`；Windows 有全部导出 `ViewModel/AvatarProperty/AvatarPropertyViewModel.cs:528-564`。 | 补 API/元数据字段映射、批量顺序导出与系统分享。不得用不相关套装名称顶替缺字段。图片分享不是当前 Windows VM 的导出命令，不应为对齐虚构能力。 |
| P2 | 窄屏首页仅显示部分卡片且不遵循统一卡片顺序：`pages/Index.ets:909-977` 对照宽屏 `1253-1329`。 | 抽取共享卡片构建器，窄/宽屏消费同一 dashCards；保持各屏幕布局优化。 |
| P2 | 角色皮肤选择及云端搭配统计未等价：Windows `WikiAvatarViewModel.cs:98,103-112`；Harmony 单 icon 立绘遍历整个角色列表。 | 元数据保留 Costumes，角色内切换皮肤；搭配统计接云能力模块，加载失败只影响该区块。 |
| P2 | 全局热键、窗口置顶/关闭行为、托盘、语言/首日/材质细项等设置不齐。 | Harmony 平台支持者做原生替代；桌面常驻/跨应用全局键不能直接按 Win32 翻译。语言包需要资源化全部文本，不能添加空壳选项。 |

## 非注入但无法在普通 HarmonyOS 应用沙盒内等价执行的 Windows 能力

Windows `ViewModel/Game/LaunchGameViewModel.cs` 提供游戏路径选择/服务器转换（278-350）、注册表游戏账号操作（354-430）、打开游戏截图目录（433-449）、杀游戏进程（452）、任意 exe/延迟程序启动（463-618）。还通过 GamePackageViewModel 管理 Windows 游戏资源安装/修复。

这些并不全部属于“注入”，但不能把 Windows exe、注册表、其他应用私有目录、进程控制、图形驱动参数直接搬到 HarmonyOS 普通 HAP。可移植的是用户自愿选择文件后的读取/校验、公开 URI 拉起、应用市场交接、系统文件选择器导入导出；原生游戏安装更新必须由该游戏/应用市场完成。若目标原神未公开 HarmonyOS 可拉起 Ability/URI，应明确待厂商协议，不能伪造 EntryAbility、宣称未安装或回退启动另一个游戏。

胡桃云/账号/统计/反馈不受这一沙盒边界自动排除，应由对应模块审计与接入；插件中纯 UI/数据插件是否可重建需单独区分，Win32/.NET 插件二进制不能运行。

## 官方平台依据

- OpenHarmony 官方 `bundleManager` 文档：查询其他应用 `getBundleInfo` 需要 `GET_BUNDLE_INFO_PRIVILEGED`；普通应用可用 `canOpenLink`，但 scheme 必须在 manifest `querySchemes` 声明；`getLaunchWant()` 只获取本应用入口，不能用于任意其他应用。<https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-ability-kit/js-apis-bundleManager.md>
- 华为官方沉浸光感指南要求 targetSDKVersion >=26.0.0；不能由此推断 API24 上调用 API26 材质类型安全。<https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-immersive-light-sense-enable>

## 实施次序

1. 能力与事实修复：游戏路由、API24门控、首页异步隔离。
2. 可验证纯逻辑：服务器日期/材料窗口、百科组合筛选、导出字段。
3. 外观与内容能力：视频/远程壁纸、皮肤、云搭配、语言与桌面差异。
4. API24 与 API26 各至少一台设备验证；320/720/840/1200vp、深浅主题、离线、无账号、账号切换、失效URI、视频损坏等关键场景。

本文件是审计基线，并非“全量已完成”声明。最终完成情况以提交记录、自动检查与设备验证记录为准。
