# 数据存储与文件互通

本文按 2026-11-16 工作区源码整理，供接手数据层与文件交换功能时定位。格式边界以对应 codec 和服务实现为准；专项文档保留设计与历史验证背景。

## 存储与档案归属

业务主库为 `snap_hutao.db`，当前 schema 为 9，由 [RelationalStoreHelper](../entry/src/main/ets/data/db/RelationalStoreHelper.ets) 顺序迁移。页面经 ViewModel/Service 使用 Repo；新增读取应沿用现有入口，避免在页面另算 SQL、计数或数据身份。

| 数据 | 归属与主要入口 |
| --- | --- |
| 登录账号、绑定角色 | `user_accounts` / `user_game_roles`；当前账号和默认游戏 UID 存在 `PreferencesStore`。凭据经 `TokenVault` 保存，账号切换与异步请求归属由 `UserService` 管理。 |
| 祈愿 | `gacha_archives.uid` 唯一，明细关联 `archive_id`。`GachaRepo` 管理本地档案；离线选档不会切换登录账号或赋予网络鉴权。空 UID 不创建档案。 |
| 成就 | `achievement_archives` 是独立命名档案，不要求绑定游戏 UID；记录按 `archive_id + ach_id` 保存。完成状态、未完成进度和时间分开存储。 |
| 背包 | `backpack_archives` 显式保存名称与 UID，同 UID 可有多个快照；`backpack_items` 按档案与本地实例 ID 保存装备和堆叠物品。 |
| 周期战绩 | `challenge_records` 按 `kind + uid + region + schedule_id` 隔离，保存原始单期 JSON。旧的三类历史表仍保留，无法确认归属的旧记录不自动分配给当前账号。 |
| 养成 | 项目、条目、材料需求与项目库存分别落库；背包材料只有经显式同步才进入项目库存。schema 8 保留编辑输入，schema 9 增加项目服务器时区。 |

偏好存储名为 `snap_hutao_prefs`，入口是 [PreferencesStore](../entry/src/main/ets/data/prefs/PreferencesStore.ets)。不要用“当前账号 UID”替代已经选中的祈愿、成就或背包档案身份。账号会话边界见 [账号请求归属](ACCOUNT_SESSION_OWNERSHIP_2026-10-05.md)。

周期列表的发布期与个人战绩是两类数据。幽境列表按照 Windows `HardChallengeView` 的规则，已知期次用 `HardChallengeSchedule.json` 的 `Begin/End` 展示完整区间；原始 API 时间窗口和存档字段保持原值，未知期次才回退战绩时间。不要通过固定加天数修改日期。

## 祈愿的逻辑记录与刷新

同一 UID 内，逻辑身份是 **普通祈愿或颂愿命名空间 + 精确十进制 `gachaId`**。两命名空间可存在相同 ID；ID 不转换为 JavaScript `number`，前导零按同一十进制值处理。查询池会合并 `301/400` 和活动颂愿子池，但记录中的原始池号保留；同 ID 的不同已知原始池号属于冲突。

[GachaItem.recordIndex/logicalRecords](../entry/src/main/ets/model/GachaItem.ets) 是共用读投影，[GachaRepo](../entry/src/main/ets/data/repo/GachaRepo.ets) 的全档、按池、计数、游标和分页都经此投影。兼容重复行只计一条；历史缺字段在副本中补齐，同已知物品 ID 的展示名称别名可以合并。不同物品 ID、原始池号、时间、数量、星级或期次等内容冲突会带记录 ID、冲突字段和数据库行号报错，导出也不会吞掉冲突。

这个投影不删除或改写 SQLite 原始行。首页、总览、历史、收藏、UIGF 导出和导入预览按逻辑记录条数统计，物品 `count` 保留为数量字段，不乘成抽数。历史列表的 100000 条上限作用于投影后的精确游标倒序结果；完整统计和导出不因列表上限截断。

在线入口在 [GachaLogService](../entry/src/main/ets/service/GachaLogService.ets)：SToken 鉴权或手工祈愿 URL，归档以响应 UID 校验。普通接口每页 20 条，颂愿每页 5 条；增量水位涵盖已存的 `400` 等原始子池。网络类失败每页最多 3 次请求，鉴权和风控错误不按网络错误重试。重复页、交叠记录和写入前均再次核对身份。

默认增量保留已有历史；用户主动选择的全量刷新会先检查冲突，再事务替换已验证响应覆盖的窗口，较早历史保留。失败或取消可保存已经验证的窗口，但结果仍报告未完整完成。读取投影的“不改原行”不应被解释为取消全量刷新或删除档案的既有语义。

## 文件入口与格式边界

| 格式 | 实际页面与服务入口 | 版本与范围 |
| --- | --- | --- |
| UIGF | 祈愿记录工具栏；`GachaLogViewModel.prepareImportFile/confirmImport`、`UigfService.buildExportJson` | 导入 v2.0–v2.4、v3.0、v4.0–v4.2；导出 v2.2–v2.4、v3.0、v4.0–v4.2，默认 v4.2。 |
| UIAF | 成就管理的文件/剪贴板导入与导出；`AchievementService.importUiaf/exportUiaf` | v1.1，写入选定成就档案。 |
| UIIF | 背包物品的导入预览、确认替换与导出；`BackpackViewModel` → `BackpackService` → `UIIFService` | v1.0，武器、圣遗物、材料、摆设。`UIIFService` 是纯 `UIIFCodec` 的导出别名。 |
| 应用完整备份 | 设置的备份/还原；`BackupService.buildBackupJson/restoreFromText` | 应用自有 JSON v2，兼容本应用旧 v1；不是 Windows 数据库导入器。 |

### UIGF

- 原生预览由 [UigfImportJob](../entry/src/main/ets/service/UigfImportJob.ets) 启动 TaskPool：文件读取、UTF-8 解码、全 UID 校验、时间规范化和重复检查在 worker 中完成。主线程分批恢复已验证记录；确认只选择 UID 并提交保留的 preparation，不重新解析文件。所选 UID 在一次同步事务中导入，任一批次失败全部回滚。
- 默认导入仅追加早于各查询池本地最旧 ID 的记录；“补齐缺失记录”可追加其他未见 ID，不覆盖同 ID 冲突。显式空选择或未知 UID 不会退回“全部导入”。
- v2/v3 只能导出单 UID；v4.0/v4.1 不支持颂愿，v4.2 分为 `hk4e` 与 `hk4e_ugc`。仅有颂愿的 UID 仍写 `hk4e` 空列表供 Windows 选择。不能表示的版本、字段或 Windows 数值范围会明确拒绝导出。
- [UigfBounds](../entry/src/main/ets/model/UigfBounds.ets)：文件 32 MiB、文本 32 Mi 字符、原始记录 262144 条、1024 个 UID、32 层嵌套、字段 4096 字符、后台传输 48 Mi 字符、等待 30 秒。原始行上限在去重前检查。
- 时间按文件时区换算为 UID 对应服务器时间；不是保留原时间字符串。导入只保存已支持的原神记录字段，不保存源导出器元信息、其他游戏分区或任意扩展。v4.2 的非单位颂愿 `count` 作为扩展保留，其他消费者可能忽略它。

实现定位：[UigfCodec](../entry/src/main/ets/service/UigfCodec.ets)、[UigfExportCodec](../entry/src/main/ets/service/UigfExportCodec.ets)、[UigfService](../entry/src/main/ets/service/UigfService.ets)。历史协议对照见 [Windows 文件交换](FILE_INTEROP_2026-11-11.md) 与 [后台预检设计](UIGF_BACKGROUND_AND_VERSIONS_2026-10-05.md)。

### UIAF 与 UIIF

UIAF 的 [UiafCodec](../entry/src/main/ets/model/AchievementData.ets) 保留成就 ID、`current`、`status` 和秒级时间，包括未知成就 ID、未完成记录及未知时间哨兵。`status` 为 2/3 才算完成，汇总只统计当前元数据中的成就。Lazy 保留已有 ID，Aggressive 更新同 ID 并保留其他记录，Overwrite 替换选中档案且页面二次确认。重复 ID、坏字段或不支持版本在写入前拒绝。成就页面文件读写上限为 32 MiB，校验完整读写并防止离页后的文件选择结果写入。

UIIF 的 [UIIFCodec](../entry/src/main/ets/model/UIIFCodec.ets) 使用原始 JSON 切片保留未知字段和超出安全整数的扩展数字，不能改成整体 `JSON.parse` 后再 stringify。相同物品 ID 的装备保留为独立实例；无 GUID 的装备不做智能合并。文件存在 UID 扩展时必须匹配目标档案，缺少 GUID、锁定或标记时维持未知。导入是显式快照替换，单事务失败回滚；限制为 16 MiB、50000 项、64 层嵌套。应用侧实例 ID、分类及评分不冒充 UIIF 标准字段。详见 [离线背包档案](BACKPACK_OFFLINE_ARCHIVES_2026-10-05.md) 与 [圣遗物评分](BACKPACK_SCORING_2026-10-05.md)。

## 完整备份与恢复

[BackupSnapshot](../entry/src/main/ets/model/BackupSnapshot.ets) 的 v2 文件包含 `schemaVersion`、白名单业务表、可迁移偏好和独立的 `credentials` 段。它读取物理业务行，保留祈愿原始重复行、背包实例与原始 JSON、未归属旧历史等；不会以 UI 读投影替代备份。凭据段是明文 Cookie，文件应按账号凭据保管。下载资源、本地背景媒体、设备身份、签名材料和后台任务运行库不在此 JSON 内。

恢复先验证格式、完整表清单、字段、引用关系和凭据归属；比本地更新的 schema 会拒绝。随后排空旧账号请求，重映射本地账号 ID，暂存新凭据，并在数据库事务中替换业务行。偏好和安全存储通过恢复日志补偿，不宣称跨存储介质的原生原子事务。中断或提交状态不确定时保留日志，由启动阶段 `recoverInterruptedRestore()` 在恢复会话前处理；不要清库绕过它。

v1 只恢复其实际包含的旧数据域；旧 schema 没有背包段时保留当前背包数据。较新的养成编辑字段、项目时区按 schema 验证。恢复成功后重新加载本地会话，页面提示重启。系统 `EntryBackupAbility` 是独立的系统备份扩展，其恢复回调只重置后台工作与桌面卡片快照，不能替代上述文件恢复流程。协议细节见 [备份格式](BACKUP_FORMAT.md) 和 [后台与恢复集成](BACKGROUND_SETTINGS_INTEGRATION_2026-10-05.md)。

## 游戏元数据与图标更新

应用内置 `rawfile/metadata/` 和 `rawfile/icons/` 提供离线基线。原始读取入口为 [GameDataService](../entry/src/main/ets/service/GameDataService.ets)；显示文本经 `LocalizedGameDataService` 按 ID/匹配键覆盖，保留原始数值、图标和关联关系。不要让页面直接读取旧的逐文件下载目录或偏好版本号来判断“完整更新”。

设置中的游戏数据更新调用 [GameDataUpdater](../entry/src/main/ets/data/remote/GameDataUpdater.ets)。默认 `manifest-hutao.json` 来源为受信任数据仓 `aichi-chishan/snap-hutao-data`，频道 `hutao-cn`。每次操作把分支解析为固定 commit，按清单下载整组元数据与图标，检查路径、字节、SHA-256、JSON/PNG 结构及关联关系后再发布。v1 兼容无发布方散列的清单；本地校验收据不等于发布方签名。

落盘根为 `filesDir/gamedata/cohort-v1/`：独立 `staging/{id}` → `snapshots/{id}`，通过 `active.json` / `active.previous.json` 选择完整快照。启动校验后，**本进程固定使用同一组数据**；更新、回滚或恢复内置都安排下次启动生效，不在运行中混换图鉴、计算表和图标。更新失败/取消不发布部分数据；恢复内置只调整选择指针，不递归删除资源。当前限制为 4 MiB 清单、`locale_*` 语言包 16 MiB、其他单文件 8 MiB、整组 512 MiB、最多 4 个下载任务；其他约束见 [快照更新设计](GAME_DATA_COHORT_RECONSTRUCTION_2026-10-05.md)。

[MetaIcon](../entry/src/main/ets/components/MetaIcon.ets) 对普通图标名优先读取当前快照，再把随包 rawfile 提取到 `cacheDir/rawicons/{安装版本}/{Category}/`；显式 URL/file URI 直接显示。只有启用 `remoteFallback` 才在本地缺失后调用静态 CDN 后备，缓存于 `cacheDir/remote/{Category}/`。角色立绘等页面也可显式使用 `StandardIconService`。`ResourcePackService` 保留兼容后备代码，旧资源包管理入口已退役；这些静态素材与已移除的云账号功能无关。

数据生产仓在工作区的独立 `snap-hutao-data/`：`fetch-assets.py` 更新该仓素材与映射，`gen-manifest.ps1` 扫描 metadata/icons 生成清单，发布前调整 `channelVersion`。APP 包内基线与远端数据仓是两套交付物，修改数据仓不会自动改写 APP 资源目录。语言与技能文本的生成、匹配和回退见 [本地化游戏数据](LOCALIZED_GAME_DATA_2026-11-11.md)。

## 回归定位

- 祈愿：`gacha-logical-records`、`uigf-background`、`uigf-selective-import`、`offline-gacha-access`。
- 成就/背包：`achievement-page`、`uiaf.test.mjs`、`backpack`、`backpack-scoring`。
- 备份：`backup-roundtrip`、`backup-sqlite`；元数据：`game-metadata-localization` 与快照更新专项测试。
- 周期原始字段/展示期：`challenge-period-display`、`scripts/test-challenge-regressions.cjs`。新周期样例使用截图观测值、上游模型字段和真实包内元数据重建，不冒充已抓取的完整账号响应。

执行方式与全量检查入口见 [测试说明](TESTING.md)。
