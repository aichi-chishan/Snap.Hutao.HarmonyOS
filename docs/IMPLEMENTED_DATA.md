# 数据域本次交付状态（2026-10-02）

本文件记录用户要求停止新增工作时的真实状态。审计基线与证据见 `audit-data.md`。这是一轮已实现改动的交付记录，不代表“除注入外全量移植”已完成。

## 已落地

| 范围 | 状态 | 实际行为与主要文件 |
|---|---|---|
| UIAF 数据正确性 | done | `AchievementData/Service/Repo` 保留全部 status/current/timestamp，不再将进行中计数误判完成；v1.1 完整结构校验，重复ID/非法数字在写入前拒绝；Lazy/Aggressive/Overwrite 三种策略；事务回滚防止清空后半导入。完成统计与页面仅看 status>=2。 |
| 成就页面补齐 | done，设备未验 | `AchievementPage` 接入导入策略、进行中进度、每日委托筛选、复制ID、米游社/HoYoLAB攻略。官方元数据更新至上游 `b3aef3dbe0299e512654bb296930b3b6571fc87f`（2026-09-24）：1854成就、70个真实 IsDailyQuest 标记、73个分类；保留 Reward 派生字段并支持 FinishReward。 |
| UIGF 互通 | done | `UigfService` 导入前完整解析校验；多UID、4.2仅UGC档案、标准池与UGC同游标分别去重；游标保持十进制字符串；保留原始400池号并导出查询类型301；导入按文件时区/显式ISO偏移转换至UID服务器时区，导出真实时区。 |
| 祈愿归档/统计 | done，在线未验 | `GachaLogService/GachaRepo/GachaLogViewModel` 根据响应UID建档并校验所有返回页，手动URL不借用当前账号UID；301/400联合查询；游标字符串顺序处理同秒十连；五星/四星平均按完成间隔计算，真实卡池时间与物品ID判UP，未知不冒充UP/歪；UP周期包含上次UP后的非UP五星。历史页尊重归档服务器时区。 |
| 刷新操作 | done，在线未验 | 增量遇到旧游标停止；全量原子替换实际返回窗口且保留更早历史；页面切换增量/全量与取消按钮。取消/单池失败保留已验证数据并报告部分结果；UGC失败不会再报告全面成功。海外手动URL路由官方海外端点；与Windows一致，海外SToken自动鉴权明确不支持。 |
| 养成保存 | done | `CultivationRepo.addEntry` 同步事务保存条目及材料，检查短写/失败返回并回滚，不再fire-and-forget，不修改计算输入对象，拒绝无材料空条目。 |
| 离线养成算法 | done，在线进度未验 | `CultivationTables/OfflineCultivationService` 按Windows MIT源码移植等级经验、突破、三天赋、武器材料表，结合本地 cultivationItems；支持90→95→100命星、1/2星武器70级上限。图鉴武器与角色加入计划有真实材料；无登录可从1级规划；已登录通过计算器同步准确当前突破/天赋，材料算法本地运行。缺元数据/缺准确输入时失败，不创建假成功计划。 |
| 养成目标页面 | done，设备未验 | `CultivationPage/ViewModel` 角色目标含95/100，天赋与武器目标独立可选；项目选择持久化并与日历共享 `cultivation.current_project_id`；离线候选角色入口。 |
| 非注入库存 | done，在线未验 | `InventoryRepo/Service` 按项目隔离数量，支持手工编辑、JSON/UIIF文件导入、计算器所选材料库存同步；缺 has_user_info/lack_num 时拒绝将未知库存当0；保留负lack_num表示的库存富余。页面显示库存，树脂扣除确切库存并允许同系列低阶材料按3:1合成抵扣。 |
| 我的角色缓存 | done | `CharacterService/ViewModel` UID隔离持久缓存，成功详情批次按ID合并；远端失败/损坏响应不覆盖有效缓存；未知突破标-1，页面在后续刷新失败时保留可用缓存。 |
| 角色导出/评分 | done，设备未验 | 当前和全部已缓存角色文本导出接线；增加武器主副词条、圣遗物套装名。修正心海ID由错误的10000002为10000054（绫华不再被禁双爆）；评分即使无推荐词条仍按上游权重计算，不漏掉有效充能分。 |

## 验证证据

以下测试执行实际 ETS 生产模型/服务/仓库，使用 Node 24 去类型和内存 SQLite，平台网络/偏好用明确 mock；不是对真实账号结果的声明。

- `node tests/data-port.test.mjs`：11项通过（时区、400往返、多UID、UGC、非法数据不写、离线培养黄金结果、等级上限、计划写失败回滚/短写/不改输入、心海与绫华评分）。
- `node tests/uiaf.test.mjs`：8项通过（全部状态往返、版本结构拒绝、三策略、状态统计、原子回滚、手动勾选进度）。
- `node tests/inventory.test.mjs`：6项通过（材料JSON/UIIF、非法输入、项目隔离、显式零、库存富余、缺字段拒绝、事务回滚）。
- `node tests/character-cache.test.mjs`：5项通过（UID隔离、批次合并、失败保留、损坏恢复、突破未知）。
- `git diff --check` 通过。
- 本轮真实 SDK 编译已检出并修正 `throw` 限制和文件选择器 Context 可空类型；最终全工程编译结果由集成记录统一给出。API24真机、真实Cookie/验证码、系统文件选择器和剪贴板交互仍待验收。

## 数据与备份字段

- `achievement_entries.status INTEGER NOT NULL DEFAULT 3`：旧记录本来只保存完成项，因此迁移默认3；current/time保持原值。
- `cultivate_inventory(project_id,item_id,count)`：项目内唯一材料库存。
- 角色原始响应缓存放偏好 `character.list.<uid>` / `character.details.<uid>`，不包含Cookie。
- 未新增曾讨论的 `cultivate_entries.calculation_input`；编辑完整输入持久化并未实施。

## 未完成或受阻

| 项目 | 状态 | 剩余工作/原因 |
|---|---|---|
| 角色技能ID/命座加成精确呈现 | remaining | root停止前未创建 avatar_extra 侧表，原精简skills仍无id/groupId/ExtraLevel。展示/文本导出仍依既有顺序匹配；材料计算使用计算器精确skill_list，二者要区分。 |
| 我的角色页面直接批量加入计划 | remaining | 养成页已有多选批量计算/保存；角色页仍为单角色加入，尚未完成Windows批量菜单等价操作。 |
| 养成项目条目编辑/改名与完整输入持久化 | remaining | 原数据库只留等级及材料，无完整天赋/武器输入。不能据此可靠重算旧条目。本轮保留删除/重新规划路径，未伪造编辑能力。 |
| 武器卡在突破等级且接口不提供突破状态 | blocked by source data | 计算器同步响应缺 promote_level 时，20/40/50/60/70/80级无法区分突破前后。本轮明确拒绝该同步计算，图鉴1级起点离线计算仍可用；需把战绩武器准确突破状态接入输入。 |
| 完整Windows背包视图 | remaining | 本轮为非注入材料库存；未移植全部武器/圣遗物装备档案、评分编辑器及完整UIIF装备数据浏览。 |
| UIGF所有历史版本与选择性导出UI | remaining | 已支持主要2.x/3.0/4.x解析与4.2导出；未实现上游每种导出版本/逐归档勾选界面。一次多UID导入不是跨全部档案的单事务，数据库错误时已写档案可保留，UI报失败。 |
| 所有地区角色/计算器在线完整等价 | blocked pending credentials | 已路由主要海外战绩/祈愿端点；未进行真实海外账号鉴权、风控和同步验收，不保证服务端当前可用性。 |
| 新刷新全量/取消和库存树脂端到端测试 | remaining | 核心纯逻辑测试已过；全网络分页/取消时机、设备UI联动还需专门契约fixture与设备验收。 |
| 全量业务移植结论 | remaining | 上述未完成项目存在，不能将本轮修复称作“全量移植完成”。遵照用户停止新增指令，剩余事项留待下次明确继续。 |
