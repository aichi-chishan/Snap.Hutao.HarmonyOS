# Snap.Hutao.HarmonyOS

胡桃工具箱的 HarmonyOS 移植版。项目使用 ArkTS 和 ArkUI，支持 API 26 起的手机、平板和二合一设备。平板和宽窗口采用侧栏、工具栏与列表详情分栏，手机使用底部页签。Windows 行为对照取自 [Snap.Hutao.Remastered 2.0.2.0](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/tree/3b7475ed3eca4aedf9cb81d94741bfbe6fa189f5)。

## 功能

| 入口 | 可以做什么 |
| --- | --- |
| 主页 | 查看保底计数、成就、实时便笺、旅行者札记、材料周历、签到和游戏公告。卡片顺序与显隐可在设置中调整 |
| 祈愿、成就、背包 | 按本地档案浏览、筛选和统计。祈愿支持增量与全量刷新、历史、常规祈愿和颂愿。通过 UIGF、UIAF、UIIF 交换各自的数据 |
| 我的角色、养成计划 | 查看角色属性、装备、天赋、命座和圣遗物评分，按目标等级计算材料并结合项目库存管理 |
| 周期挑战 | 按期查看深境螺旋、幻想真境剧诗和幽境危战的阵容、战斗与统计，保存并回看已有战绩 |
| 角色、武器、怪物资料 | 离线查找本地游戏资料，比较等级和突破数值、查看天赋、掉落与材料，从图鉴进入养成计划 |
| 账号、便笺、签到 | 使用国服米游社账号管理多个角色，按追踪项刷新便笺、配置提醒和系统后台任务 |
| 设置与数据 | 设置主题、界面材质、壁纸和前景动效，更新游戏数据，备份或恢复业务数据库与偏好 |
| 账号洞察 | 查看本地历史图表，使用已配置的端侧模型或自定义服务进行分析 |

启动游戏使用用户配置的公开启动入口。移植范围排除胡桃云账号服务和注入功能。应用使用的游戏美术、静态 CDN 与第三方库按各自来源和许可使用。

## 从源码开始

1. 安装带 HarmonyOS API 26 SDK 的 DevEco Studio，或配好相同版本的 SDK、OHPM 与 Hvigor。
2. 第一次检出时，将 [无签名工程模板](ci/build-profile.ci.json5) 复制成项目根目录的 `build-profile.json5`。已有本地签名配置的工作区直接沿用它。
3. 在根目录执行 `ohpm install --all`，然后构建 `entry@default`。静态图标与元数据已随源码提供。参考源码仓和数据生成环境用于维护及更新资源。

```sh
hvigorw assembleHap --mode module -p module=entry@default -p product=default --no-daemon
```

Windows 可在 DevEco Studio 终端运行 `hvigorw.bat`。输出目录为 `entry/build/default/outputs/default/`。Node.js 24 主机回归、原生包校验和 CI 配置见[测试说明](docs/TESTING.md)。

## 维护文档

- [工程架构与模块地图](docs/ARCHITECTURE.md) 给出目录、页面入口、状态和持久化归属。
- [数据与文件交换](docs/DATA_AND_INTERCHANGE.md) 说明档案身份、文件格式、备份恢复及游戏数据更新。
- [维护者交接](docs/HANDOFF.md) 收录新环境构建步骤、复测方法和后续验证项。
- [贡献约定](AGENTS.md) 记录 ArkTS、界面材质、资源和仓库操作约定。
- [文档索引](docs/README.md) 收录各领域专项说明和历次移植记录。

账号凭据保存在设备安全存储中。**整库备份包含可恢复的游戏登录凭据**，请自行保管备份文件。签名、个人导出、真机截图及调试日志归入本地目录。

## 来源与许可

应用代码使用 [MIT 许可证](LICENSE)。感谢 [Snap.Hutao](https://github.com/DGP-Studio/Snap.Hutao)、[Snap.Hutao.Remastered](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered)、[Snap.Metadata](https://github.com/SnapHutaoRemasteringProject/Snap.Metadata) 和 [UIGF 组织](https://uigf.org/)。游戏数据更新由[独立数据仓](https://github.com/aichi-chishan/snap-hutao-data)维护。第三方代码许可见 [rawfile/licenses](entry/src/main/resources/rawfile/licenses)，图鉴背景和美术来源记录在 [rawfile/wiki](entry/src/main/resources/rawfile/wiki)。本项目为社区作品，与米哈游和 HoYoverse 无隶属关系。
