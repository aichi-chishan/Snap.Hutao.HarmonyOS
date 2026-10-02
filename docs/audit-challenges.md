# 挑战、实时便笺与签到源码对照审计

基线：本次工作区 `upstream`（DGP-Studio/Snap.Hutao）及 `upstream-remastered`。路径中的 `H` 指 `entry/src/main/ets`，`W` 指 `upstream-remastered/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered`。以下行号记录修改前状态。用户本轮“除注入全量”覆盖旧 AGENTS 的云功能排除范围；服务可用性与鸿蒙平台限制须分别验证，不能以页面存在判定功能完成。

## 已确认差距

| 优先级 | 差距与证据 | 上游对应 | 实施/验收 |
|---|---|---|---|
| P0 | 三挑战表只有 `schedule_id` 主键；跨 UID 相互覆盖。`H/data/db/RelationalStoreHelper.ets:90,221,228`，三个 Repo 的 `saveHistory/listHistory/getRawJson` 都无 UID | W/Service/{SpiralAbyss,RoleCombat,HardChallenge} 按 UID 查询缓存与实体 | 新建复合主键记录表，所有读写显式 UID、region；旧表保留且不猜归属；相同期两个 UID/区服互不覆盖 |
| P0 | 深渊保存外层 API envelope，却按 data 对象还原：`H/service/SpiralAbyssService.ets:84`、`H/viewmodel/SpiralAbyssViewModel.ets:86` | W/Model/Entity/SpiralAbyssEntry 保存完整 WebSpiralAbyss | 统一保存 data 对象，读取兼容历史 envelope；回看星数/层/战斗完整 |
| P0 | 幽境只解析 data[0]，其余档期丢失：`H/model/HardChallenge.ets:104-111`，VM 仅保存一期 | W/Service/HardChallenge/HardChallengeService.cs:102-110 遍历全部档期 | 所有档期逐条解析、保存、可选择；新旧对象形态兼容 |
| P0 | 幽境把 `teams` 当 `{avatars:[]}` 数组，实际为角色扁平数组：`H/model/HardChallenge.ets:182-194` | W/Web/Hoyolab/Takumi/GameRecord/HardChallenge/HardChallengeChallenge.cs:19-20 | 兼容扁平及历史嵌套结构，角色等级/命座正确 |
| P0 | 通知先落本次快照再读 prev，所有边沿被抑制：`H/service/DailyNoteService.ets:180,195`；派遣“全部完成”误用派遣人数满额：259-264 | W/Service/DailyNote/DailyNoteNotificationOperation.cs:36，NotifySuppression | 先读旧值再保存；按每个 Expedition 的 Finished 判定；达阈值只发一次，回落再达可再次通知 |
| P0 | 签到今日已签时把实际累计天数抬到今天日号：`H/model/SignInInfo.ets:45-50`；签到/补签在补 token 前读 cookie：`H/service/SignInService.ets:103,172` | W/Web/.../BbsSignReward/SignInRewardInfo 的 TotalSignDay、IsSign 分开 | 保留真实累计/今日标记；缺 token 首次请求也用补齐后的 cookie |
| P1 | 便笺 DB 的 archon_json 恒空；obtained、daily_task.status 不还原，VM 仅手动刷新另存 prefs；自动刷新会丢状态：`H/data/repo/DailyNoteRepo.ets:46,118,152`、`H/viewmodel/DailyNoteViewModel.ets:251` | 上游持久化整个 DailyNote | 完整快照落库并兼容旧列；从服务、卡片、自动刷新获得的数据一致 |
| P1 | 所有追踪 UID 刷新都覆盖所有桌面卡：`H/service/DailyNoteService.ets:193,223`；onUpdateForm 只推旧快照：`H/widgets/DailyNoteFormExtensionAbility.ets:78-83` | 桌面平台能力需鸿蒙等效适配 | 当前 UID 卡不被追踪账号污染；系统卡片回调实际刷新并正确显示失败 |
| P1 | 深渊刷新仅选中当/上期，上游一次刷新两期且先请求 index：`H/viewmodel/SpiralAbyssViewModel.ets:39` | W/Service/SpiralAbyss/SpiralAbyssService.cs:60-71 | 拉取当期与上期；保留已有离线快照，单次失败不清空成功缓存 |
| P1 | 幽境缺人气角色请求 `GetHardChallengePopularityAsync`；本地 blings 不等同人气列表 | W/Service/HardChallenge/HardChallengeService.cs:54-70 | 独立 popularity 接口、错误状态及页面，不伪造统计 |
| P1 | 多账号便笺只刷新当前登录账号的追踪列表，缺 webhook、持久化通知抑制状态；setInterval 无法保证进程回收后的刷新 | W/Service/DailyNote/DailyNoteService.cs:149-179、DailyNoteOptions.cs:45-46 | 多账号任务上下文；用户配置 webhook；API24后台/提醒代理能力需真机验证 |
| P1 | 旅行札记模型及当前/选月查询基本齐全，但无历史持久化、导入导出；`H/service/LedgerService.ets`、`H/pages/LedgerPage.ets` | 上游 TravelersDiaryViewModel 仅当前月在线卡片（不是历史存储） | 属扩展可靠性需求，不能称为已缺失的上游持久化；可做按 UID/region/年月缓存 |
| P0 | 本地“全量备份”仅用户/祈愿/成就，漏挑战、便笺、养成；还原仅校验 app 标记就先删除全部原数据且不校验版本：`H/service/BackupService.ets:86-94,209-227` | 上游整库/云备份覆盖完整数据 | 由主代理统一实现完整表备份与验证、事务/回滚，不在本分支并行改动 |

## 按序实施计划

1. 新增 v6 `challenge_records`，主键 `(kind, uid, region, schedule_id)`；旧历史表原样保留，避免把无法确认所有者的记录静默归入当前账号。
2. 重接三个 Repo、VM 和页面历史入口的身份参数；清除切 UID 的旧内存展示，防止异步响应串号。
3. 修复深渊 envelope、幽境全部档期、扁平队伍解析；保留原始 JSON 以保证未显示字段不丢失。
4. 修复便笺通知顺序、派遣状态、完整快照持久化、当前 UID 桌面快照以及签到事实/凭证错误。
5. 增加针对真实差异的模型/SQLite/服务回归；源码静态检查与可用 SDK 构建分别报告，不能将模型测试等同真机验证。
6. 后续补齐人气接口、双期拉取、导入导出、多账号后台任务、webhook、平台通知能力。每项未实现/未验证继续留在差距表中。

项目 AGENTS 提及的 `skills/` 未随仓库提供；当前可读技能目录亦未检索到 hmos ArkTS skill，按现有源码的严格 ArkTS 类型及 API24约束开发，不假称已执行该技能。
