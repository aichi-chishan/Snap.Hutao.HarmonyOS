# 数据域移植审计（2026-10-02）

范围：祈愿/UIGF、成就/UIAF、养成、我的角色和非注入背包。审计依据为同级 `upstream`（DGP 官方最终存档）及 `upstream-remastered`（当前社区版本）。下列 Windows 路径以 `upstream-remastered/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/` 为根，鸿蒙路径以 `entry/src/main/ets/` 为根。注入采集排除，手工/文件/米游社计算器途径包含。读取了 AGENTS.md；仓库声明的 `skills/` 目录在本次检出中不存在，使用已存在严格 ArkTS 风格并交由实际 SDK 编译验证。

## 行为差距与实施顺序

| 优先级 | 差距与实际后果 | Windows 证据 | 鸿蒙证据 | 实施 |
|---|---|---|---|---|
| P0 | UIAF 进行中记录只要 current>=1 就被标记完成，导出再变为 current=1/status=3，永久丢失状态及计数 | `Model/InterChange/Achievement/UIAFItem.cs:14-37`; `Model/Entity/Achievement.cs:28-53` | `service/AchievementService.ets:309-310,353-364` | 持久化 status/current/timestamp；严格 status 完成判断；迁移旧记录为3；完整往返 |
| P0 | UIGF timezone 恒0，导入时区直接忽略，ISO字符串去Z并不换算；国服记录导入Windows偏移8小时 | `Service/UIGF/AbstractUIGF40ExportService.cs:71-103`; `AbstractUIGF40ImportService.cs:72-79` | `service/UigfService.ets:51,59,165,240,262` | 按UID服务器时区统一规范时间；导出真实偏移；显式ISO时区正确换算 |
| P0 | 手工URL按页面当前UID建档，不检验接口UID，可能污染别人的归档或建空UID档 | `Service/GachaLog/GachaLogFetchContext.cs:56` | `service/GachaLogService.ets:83-101`; `model/GachaItem.ets:22` | 从响应UID确认目标；期内UID不一致中止；无有效UID不建档 |
| P0 | 在线400记录未纳入301查询池；文件导入把400原始池号丢掉；双角色卡池统计/历史归属错误 | `Model/InterChange/GachaLog/Hk4eItem.cs:48-54`区分GachaType与QueryType | `data/repo/GachaRepo.ets:106,158,171`; `service/UigfService.ets:223-230` | 保留原始gacha_type，查询层合并301/400；uigf_gacha_type只用于查询归类 |
| P0 | 五星UP标记是假设第一个五星UP；平均出金含最后未出金尾巴 | `Service/GachaLog/Factory/HistoryWishBuilder.cs:31-65`; `TypedWishSummaryBuilder.cs:206-208` | `viewmodel/GachaLogViewModel.ets:185,216,235-240` | 按当期事件时间+物品ID判定；未知时不宣称UP；以实际五星间隔求平均 |
| P0 | addEntry返回时材料写入仍未完成，错误只打日志；重新读计划可能空材料 | Windows `Service/Cultivation/CultivationService.cs:170-242` 保存完整实体 | `data/repo/CultivationRepo.ets:197-210` | await全部材料写入，失败清理新条目并向上传播；不修改输入材料对象 |
| P1 | UIAF无版本/结构校验，无激进合并/覆盖策略；导入形同任意list JSON | `ViewModel/Achievement/AchievementImporter.cs:93-112`; `Service/Achievement/AchievementRepositoryOperation.cs:24,95` | `service/AchievementService.ets:326-375` | 预校验后一次写入，默认保守合并并增加策略选择 |
| P1 | UIGF无版本/UID/item_id/time合法性预检，中途失败留半个档；仅UGC根对象被拒绝 | `Service/UIGF/UIGFService.cs:40`; `AbstractUIGF40ImportService.cs:53-57`; `UIGF42ImportService.cs:43-53` | `service/UigfService.ets:143-250` | 导入前完整解析校验、识别4.2 UGC-only、跨UID汇总；保留大整数游标字符串 |
| P1 | 养成当前突破恒0、天赋恒空、武器目标跟角色目标绑定 | `Service/AvatarInfo/AvatarInfoRepositoryOperation.cs:73-81`; `Service/Cultivation/Offline/OfflineCalculator.cs:64-241` | `viewmodel/CultivationViewModel.ets:90,94,186,190`; `viewmodel/CharacterViewModel.ets:164` | 加离线计算器、已知突破与天赋输入；独立角色/武器目标，低品质武器上限 |
| P1 | 图鉴武器加入计划显示成功但材料恒空；角色计算失败也保存空材料“成功” | `Service/Cultivation/Offline/OfflineCalculator.cs:27-30` | `viewmodel/CharacterViewModel.ets:175-190,204-219` | 按上游离线常数和本地cultivationItems算材料；不能计算时错误返回，不创建伪完成条目 |
| P1 | 我的角色仅内存缓存，详情分批失败会丢已成功批次，重启不可离线看 | `Service/AvatarInfo/AvatarInfoService.cs:24`; `AvatarInfoRepositoryOperation.cs:31-94` | `viewmodel/CharacterViewModel.ets:57,93`; `service/CharacterService.ets` | UID隔离持久化缓存；先呈现缓存再刷新，每批合并，不覆盖其他UID |
| P1 | 项目无库存数量，树脂不扣库存/合成低阶材料；手工编辑、计算器库存同步缺失，均不属于注入 | `Service/Inventory/InventoryService.cs:32-47,106-135`; `Service/Cultivation/CultivationService.cs:111-149` | `service/ResinStatisticsService.ets:23-25`; `data/repo/CultivationRepo.ets`无Inventory | 新增项目库存表、编辑/清空/非注入计算器同步、材料缺口聚合和合成折算，再更新树脂 |
| P2 | 无刷新策略、取消与真正增量停止；UGC请求失败最终仍可能报全面成功 | `Service/GachaLog/GachaLogService.cs:73-106`; `GachaLogFetchContext.cs:63,91` | `service/GachaLogService.ets:123-264` | 明确部分失败结果；增加增量/全量策略及取消；保持已收集部分数据 |
| P2 | 成就委托筛选/攻略搜索，角色全部导出/批量养成与项目条目编辑等细节未齐 | `ViewModel/Achievement/AchievementViewModel.cs:82,460,475`; `ViewModel/AvatarProperty/AvatarPropertyViewModel.cs:310,546`; `ViewModel/Cultivation/CultivationViewModel.cs:616` | 对应pages/vm仅子集 | 完成核心数据正确性后逐功能接线，未接线能力不列为完成 |

## 落地阶段与验收

1. 先处理P0数据正确性：UIAF完整往返、UIGF时间/归档、301/400查询合并、真实UP及均值、养成写入一致性。用status=1/current=10、东八/美服/欧服时间、重复ID、双角色卡池同秒记录和写入失败用例回归。
2. 本地养成等价：移植Windows离线经验/突破/天赋表到ArkTS；用已内置avatar/weapon cultivationItems解析材料；角色90→95→100、武器1/2星70级、普通90级和天赋1→10逐项比对。可用米游社计算器同步准确突破，但离线计算不依赖登录。
3. 库存与角色缓存：按项目和UID隔离；数量扣减/合成/树脂联算；手工库存和文件导入不需注入。保留服务端鉴权与风控链，不用伪造样例冒充实际账号结果。
4. 最后补UI入口与批量操作，在API24与高版本门控环境编译/设备验证。无真实账号或设备的链路明确标“未在线/真机验证”。

以上为修改前审计快照，行号随实施会变。完成状态以主实施计划与变更记录为准，不能因已有页面就认定等价移植完成。
