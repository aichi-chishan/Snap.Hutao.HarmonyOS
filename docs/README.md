# 技术文档

| 维护任务 | 从这里开始 |
| --- | --- |
| 找到某项功能的页面、状态、服务和持久化实现 | [工程架构与模块地图](ARCHITECTURE.md) |
| 接手项目、配置环境、复测性能 | [维护者交接](HANDOFF.md) |
| 理解本地档案、导入导出与资源更新 | [数据与文件交换](DATA_AND_INTERCHANGE.md)、[业务备份](BACKUP_FORMAT.md) |
| 执行离线测试与构建 | [测试与验收](TESTING.md)、[CI 配置](../.github/workflows/ci.yml) |
| 更新游戏元数据、语言文本和图标 | [本地化游戏数据](LOCALIZED_GAME_DATA_2026-11-11.md)、[界面语言资源](UI_LOCALE_COVERAGE_2026-11-11.md) |
| 修改账号和后台刷新 | [账号状态归属](ACCOUNT_SESSION_OWNERSHIP_2026-10-05.md)、[后台与窗口修复](BACKGROUND_WINDOW_FIXES_2026-11-11.md) |
| 检查某一具体版本的互通规则 | [文件互通核对](FILE_INTEROP_2026-11-11.md)、[背包与库存档案](BACKPACK_OFFLINE_ARCHIVES_2026-10-05.md) |

## 历史参考

仓库保留了按日期命名的功能审计、性能和构建记录，方便追溯某一改动的依据。Windows 对照见 [11 月 11 日功能审计](UPSTREAM_FEATURE_AUDIT_2026-11-11.md) 和 [10 月移植计划](PORT_ROADMAP_2026-10-25.md)。[Linux 工具链记录](BUILD_ENVIRONMENT.md) 保留了早期 API 24 兼容阶段的环境。当前工程最低及目标版本均为 API 26，以工程模板、实际打包清单和本次回归为准。
