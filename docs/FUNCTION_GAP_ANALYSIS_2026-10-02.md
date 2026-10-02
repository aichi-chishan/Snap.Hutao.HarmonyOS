# 非注入功能差距与鸿蒙实现方案（2026-10-02 复核）

> 状态：**调研与待实施方案**。本次提交只更新文档，不表示下列缺口已修复。最低设备版本仍为 HarmonyOS 6.1.1（API 24），覆盖手机、平板及 PC/2in1。

当前鸿蒙版已具备主要工具页面，以及账号、祈愿/成就互通、离线养成、挑战历史和胡桃云客户端的一部分闭环，但还不能称为“除注入外全量移植”。本次按 Windows 的实际命令、服务、模型和鸿蒙对应调用链复核，列出 **32 项待处理差距**。优先解决会造成错误结果、数据互通失败或功能无法访问的部分，再补齐业务闭环；后台与游戏管理等平台差异单独验收。

本报告补充此前的 [UI/UX 调研](UI_UX_RESEARCH_2026-10-02.md)，侧重“能做什么、结果是否一致、数据如何流转”。视觉效果及界面布局沿用 [API24+ 交互规格](UI_UX_SPEC_API24_PLUS.md)，不以视觉接近代替业务完成。

## 1. 基线、范围与判断方法

| 项目 | 本次固定基线 | 说明 |
|---|---|---|
| 鸿蒙源码 | [`1a85b1788e61608150c4a3034cc497eae795be40`](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/tree/1a85b1788e61608150c4a3034cc497eae795be40) | `codex/api24-port-2026-10-02`；代码与前一阶段 `60197a9` 相同，上一提交仅增补 UI/UX 文档 |
| Windows 社区维护版 | [`3f0d1f363a8226cccd76f0f66f599e729b0f214c`](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/tree/3f0d1f363a8226cccd76f0f66f599e729b0f214c) | 本次重新查询 GitHub `main` 确认未变；最新发布仍为 [v1.20.3](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/releases/tag/v1.20.3)，发布于 2026-09-22 17:19:44 UTC（北京时间 09-23） |
| 官方最终存档 | [`e1e3b8d2e25d398443a0a0cc04d4017ec2729d19`](https://github.com/DGP-Studio/SnapHutaoArchive/tree/e1e3b8d2e25d398443a0a0cc04d4017ec2729d19) | 用于区分来源；本报告的新增功能对齐对象是上行社区维护版，不能称其为官方最新版 |
| 鸿蒙开发依据 | SDK 26.0.0.105 / API24 最低兼容 | 本次用已部署 SDK 声明、DevEco CLI 官方文档检索复核能力；文末附可重复检索的文档 ID 和声明摘要 |

范围以用户“除了游戏注入功能外”为准，旧 `AGENTS.md` / 旧规划中的“仅国服、排除全部云功能”不作为本轮范围限制。具体边界如下：

- 排除 DLL 注入、游戏进程内存读取/改写、Embedded Yae 直接采集以及依赖该链路的游戏内修改。
- **保留**本地背包展示/筛选/评分、文件导入、材料库存、云服务、插件宿主的非注入能力；不能因为原数据采集依赖注入就连同数据消费功能全部删除。
- Windows 安装包、注册表、任意进程控制不是“游戏注入”，应记录为平台差异并给出替代路径。普通鸿蒙应用没有相同执行环境，不能用一个占位按钮宣称等价完成。
- 不照搬上游已知缺陷。例如颂愿常驻池的无限五星阈值不能直接分配无限数组；后台计划也不应承诺进程终止后的精确联网刷新。

**状态口径**：`部分`＝已有相关代码但缺业务步骤或语义不一致；`缺失`＝本次检查的模型、服务和入口没有相应闭环；`平台替代`＝需使用鸿蒙能力实现相近任务；`外部依赖`＝客户端实现之外还取决于后端/厂商入口；`待验证`＝代码已存在，但无真实设备/账号证据。不同状态不能相加得出一个可靠的完成百分比。

审计从 Windows `UI/Xaml/View/Page`、各 `ViewModel` 的 `[Command]`、`Service`、协议模型出发，对照鸿蒙 `pages → viewmodel → service → data → model`，追到实际读写和请求。下文 `W/H` 链接均锁定上述提交；“未实现”是该基线内的静态源码结论，不等于某类能力在鸿蒙上不可能实现。

## 2. 已有能力与本轮重点

| 业务域 | 已存在的鸿蒙实现，不应再次列为全缺失 | 剩余重点 |
|---|---|---|
| 账号 | 国服扫码/短信；国服与 HoYoLAB 网页、Cookie；区域路由、角色绑定、凭据补全 | 海外原生密码/第三方登录及验证；遗漏的海外札记和公告路由（F01–F02） |
| 祈愿 | 常规池、1000/2000 查询、UID 校验、64 位 ID 字符串、时区换算、增量/全量、取消、UIGF 导入/4.2 导出 | 未登录本地访问、选择性互通、预测模型、UP 历史、颂愿子池/物品元数据（F09–F13） |
| 成就 | 多档案、UIAF 状态/进度/时间、三种导入策略、真实每日委托标记、攻略搜索 | 本轮未发现可据此认定的大块非注入业务缺失；保留多端交互、性能和文件互通验收 |
| 角色 | 列表/详情 UID 缓存、装备/词条/评分、单角色及全部缓存角色文本导出 | 技能 ID/命座加成、准确武器突破、从角色页批量建立可编辑计划（F03–F05） |
| 养成 | 离线等级/天赋/武器计算，95/100 级与低星武器上限；材料事务保存；手动/UIIF/计算器材料库存 | 输入持久化、计划条目修改、实况重新同步、完整背包与评分预设（F06–F08） |
| 挑战 | 三种挑战、多个可返回档期、按 UID/区服/类型/期次保存；幽境官方角色热度 | 全期元数据导航、深渊/剧诗云上传与语义化统计（F14–F15、F18） |
| 胡桃云 | 通行证、验证码/账号操作、兑换、祈愿云上传/取回/删除、15 类统计请求 | 战绩上传、统计实体与同期对比、策略/公告可用性；真实账号协议验收 |
| 日常 | 多 UID 便笺、阈值通知、Webhook、桌面卡片、代理提醒；启动时自动签到 | 挂起/进程终止后的刷新调度与跨日签到（F19–F20） |
| 资料/首页 | 角色/武器/怪物图鉴、材料周历、主页卡组、游戏公告与兑换码 | 服装/体型/所属筛选、攻略映射、国际化、路由状态（F16–F17、F23、F26） |
| 平台/维护 | Want/URI 启动、备份事务与中断恢复、游戏数据更新、GitHub 更新检查、背景视频/壁纸、诊断复制 | 更新完整性、媒体持久缓存、桌面入口/热键、Windows 平台功能替代（F21–F32） |

已有实现的详细交付证据见 [账号](IMPLEMENTED_ACCOUNTS.md)、[数据](IMPLEMENTED_DATA.md)、[挑战](IMPLEMENTED_CHALLENGES.md)、[平台](IMPLEMENTED_UI.md)、[备份格式](BACKUP_FORMAT.md)。这些是历史交付记录；本报告发现的新差异应覆盖其中过宽的“对齐”描述，例如祈愿预测、颂愿子池、札记海外支持。

## 3. 逐项差距与实现方案

优先级：**P0** 为结果/数据/访问正确性；**P1** 为主要业务闭环；**P2** 为完整能力与平台体验；**P3** 为需要独立设计的扩展生态。以下服务名、表名若当前不存在，均为**拟新增**，不是已实现声明。

### F01 · HoYoLAB 原生登录与验证闭环 — 部分 / 外部依赖，P2

- **两端差距**：Windows 有海外密码、第三方登录命令及 `UserVerificationService`；鸿蒙海外入口主要是官方网页和手动 Cookie，国服扫码/短信不能代替海外密码、第三方令牌交换和邮件二次验证。
- **鸿蒙实现**：抽出 `OverseaLoginService` 与有类型的 `LoginState`（输入、等待官方授权、待邮件验证、交换令牌、完成/失败/取消）；对照上游 `HoyoPlayPassportClientOversea` 和验证响应实现。第三方网页使用 ArkWeb/系统官方授权入口，校验回调域、会话关联和超时；凭据继续进现有安全存储，不持久化密码。保留现有网页登录作为正式回退路径。
- **依赖/验收**：需真实协议和可测试账号；覆盖普通登录、验证挑战、拒绝/取消、过期/重复回调及切换账号，失败不能生成半登录状态。网页方式能登录不等于原生命令已移植。
- **源码**：[W · UserViewModel.cs:169](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/User/UserViewModel.cs#L169)；[W · UserVerificationService.cs:11](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/User/UserVerificationService.cs#L11)；[H · LoginPage.ets:222](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/pages/LoginPage.ets#L222)。

### F02 · 海外旅行者札记与游戏公告 — 部分，P0

- **两端差距**：Windows `GameRecordClientOversea.GetLedgerAsync` 使用海外端点/OSX4；`AnnouncementClient` 按区域和语言选端点。鸿蒙 `LedgerService` 固定 `hk4e-api.mihoyo.com`、国服盐及 Referer，`AnnouncementService` 固定 `hk4e_cn` 和 `zh-cn`。因此账号能登录、挑战能读取，并不代表海外札记/公告已贯通。
- **鸿蒙实现**：在 `HoyolabEndpoints` 增加 ledger/announcement 方法，把 `region + accountRegion + language` 显式传入；参照上游端点表构建查询和签名。札记改走区域化公共请求链，重试时重算 DS；公告列表/正文缓存键含区服、语言和公告 ID，避免切服沿用国服内容。
- **依赖/验收**：先做请求契约样例，再用国服/美服/欧服/亚服验证月度统计和公告正文；不能向国服地址重试海外凭据。取消验证保留旧显示并标记过期。旅行者札记跨年长期归档属于另行增强，不能混作本项 Windows 已有功能。
- **源码**：[W · GameRecordClientOversea.cs:47](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hoyolab/Takumi/GameRecord/GameRecordClientOversea.cs#L47)；[W · AnnouncementClient.cs:26](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hoyolab/Hk4e/Common/Announcement/AnnouncementClient.cs#L26)；[H · LedgerService.ets:19](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/LedgerService.ets#L19)；[H · AnnouncementService.ets:11](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/AnnouncementService.ets#L11)；[H · HoyolabEndpoints.ets:4](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/common/HoyolabEndpoints.ets#L4)。

### F03 · 技能 ID、命座额外等级与文本导出精度 — 部分，P0

- **两端差距**：Windows 用 `SkillId` 关联技能等级，并依据技能库、命座 `ExtraLevel` 与特例计算额外等级。鸿蒙 `SkillLevelService` 仍按 A/E/Q 数组顺序配对；精简元数据未保留足够的 ID/GroupId/ExtraLevel。数量相同但顺序变化时仍可能错配，特殊角色可能直接不显示等级。
- **鸿蒙实现**：在独立数据仓库的数据转换流程保留 `avatarId/skillDepotId/skillId/groupId/constellationId/extraLevel`，随版本清单发布扩展元数据；新增 `AvatarSkillResolver` 按 ID 连接，明确“基础可升级等级”和“展示含加成等级”。页面、导出、养成复用同一解析结果；未知映射显示未知，不填 0 或凭位置猜。
- **依赖/验收**：依赖元数据管线 F21；准备乱序技能、旅行者多元素、额外冲刺、命座加成和特殊天赋样例，同一角色的页面/文本/养成输入一致。现有计算器 `skill_list` 已使用实际 ID，不应退回顺序映射。
- **源码**：[W · SummaryAvatarFactory.cs:66](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/AvatarInfo/Factory/SummaryAvatarFactory.cs#L66)；[W · SummaryAvatarFactory.cs:108](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/AvatarInfo/Factory/SummaryAvatarFactory.cs#L108)；[H · SkillLevelService.ets:19](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/SkillLevelService.ets#L19)；[H · CharacterExportService.ets:30](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/CharacterExportService.ets#L30)；[H · CalculateService.ets:131](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/CalculateService.ets#L131)。

### F04 · 已装备武器的准确突破状态 — 部分，P1

- **两端差距**：Windows 将详情武器的 `PromoteLevel` 用于属性和养成。鸿蒙计算器在 20/40/50/60/70/80 等边界缺突破字段时会明确拒绝，这是正确防护，但缺少从角色战绩详情补全的完整链路；另一方面 `CharacterService` 将缺失武器 `promote_level` 经数值工具转成 0，会混淆未知与未突破。
- **鸿蒙实现**：统一 `PromoteState` 的已知/未知表示；以 UID + 角色 ID + 武器 ID 关联准确详情快照，再给 `fillSyncedDetails` 补足武器突破。无可靠值时让用户选择本次计算的突破状态并标记为手动，不覆盖在线原始值。禁止仅按等级反推边界突破。
- **依赖/验收**：F03 的稳定角色标识；分别验证 80 未突破、80 已突破、满级、字段缺失、换武器及过期缓存。缺数据不得生成错误材料或看似准确的武器基础属性。
- **源码**：[W · SummaryAvatarFactory.cs:136](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/AvatarInfo/Factory/SummaryAvatarFactory.cs#L136)；[H · CalculateService.ets:152](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/CalculateService.ets#L152)；[H · CharacterService.ets:342](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/CharacterService.ets#L342)。

### F05 · 从角色页批量规划与先编辑目标 — 部分，P1

- **两端差距**：Windows 角色页有单角色/武器加入计划、临时计算、选中角色批量和全角色批量，并先打开升级目标输入。鸿蒙养成页已有多选计算，但角色页 `addAvatarToPlan` 直接按至少 90 级、天赋 10 建计划；不是相同任务流程，也缺从当前装备直接建立武器计划的完整入口。
- **鸿蒙实现**：新增可复用 `CultivationDraft` 编辑组件和 VM；角色页“所选/全部”生成草稿，允许选择项目、等级/突破/三天赋/武器目标，再走现有离线算法与事务保存。批量操作返回新增、覆盖、跳过、失败四类明细；图鉴入口也复用草稿，保留离线起点。
- **依赖/验收**：F03–F04、F06；勾选两角色时只处理两者，取消不落库，已存在条目明确采用跳过/覆盖策略，武器与角色目标不相互污染。
- **源码**：[W · AvatarPropertyViewModel.cs:309](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/AvatarProperty/AvatarPropertyViewModel.cs#L309)；[W · AvatarPropertyViewModel.cs:273](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/AvatarProperty/AvatarPropertyViewModel.cs#L273)；[H · CharacterViewModel.ets:154](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/viewmodel/CharacterViewModel.ets#L154)；[H · CultivationViewModel.ets:210](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/viewmodel/CultivationViewModel.ets#L210)。

### F06 · 养成条目编辑、当前进度重同步与保存策略 — 部分，P1

- **两端差距**：Windows `ModifyEntryCommand`、`SyncAvatarInfoByHoyolabGameRecordCommand` 基于持久化的 `LevelInformation` 重新计算。鸿蒙主要保存等级区间与计算后的材料，缺三天赋/武器/突破等完整输入，无法可靠回填修改或同步已建立计划；删除再建不能替代编辑。
- **鸿蒙实现**：给 `cultivate_entries` 增加有版本的输入快照（角色/武器、当前/目标等级、准确突破、技能 groupId 与基础等级、来源时间），保留结果材料表；`CultivationService.recalculateEntry` 在单事务内更新输入和结果。同步只改当前进度，保留用户目标；实现 Windows 对应的跳过/覆盖规则，先展示差异再写入。
- **依赖/验收**：F03–F05；旧条目没有输入时标记“需重新确认”，不猜测。验证材料数量变化、完成标记如何保留/重置、部分同步失败及重启回填。项目重命名可另作增强，本次没有把它认定为已证实的 Windows 必需命令。
- **源码**：[W · CultivationViewModel.cs:615](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Cultivation/CultivationViewModel.cs#L615)；[W · CultivationViewModel.cs:359](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Cultivation/CultivationViewModel.cs#L359)；[H · CultivationRepo.ets:174](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/data/repo/CultivationRepo.ets#L174)；[H · RelationalStoreHelper.ets:199](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/data/db/RelationalStoreHelper.ets#L199)。

### F07 · 完整背包档案与非注入数据来源 — 缺失，P1

- **两端差距**：Windows 背包有独立档案、九类物品、筛选排序、装备详情，并可给养成库存供数。鸿蒙 `InventoryService` 只是按养成项目保存材料数量，UIIF 的 equip/furniture 会跳过，不是完整背包。
- **鸿蒙实现**：新增 `BackpackArchive/BackpackItem`、RDB 档案/条目表及页面；装备使用实例标识，不能仅按 itemId 合并重复武器/圣遗物。先提供用户明确选择的 UIIF 装备/材料/家具导入、手工条目和已有合法导出文件转换；以事务预检保存，保留未知字段和来源。将选定背包材料快照同步到养成项目，显式选择合并/替换。
- **边界/验收**：上游背包刷新主入口是 Embedded Yae；本项只对齐其**离线消费能力**，文件导入是鸿蒙替代采集路径，不宣称 Windows 该背包页本来就有 UIIF 导入命令。官方养成接口仅能提供部分材料，不是全背包。验证重复装备、锁定/等级/词条、九类筛选、离线重启与选档同步，不实现内存读取。
- **源码**：[W · BackpackViewModel.cs:39](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Backpack/BackpackViewModel.cs#L39)；[W · BackpackService.cs:45](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Backpack/BackpackService.cs#L45)；[W · UIIFItem.cs:17](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/InterChange/Inventory/UIIFItem.cs#L17)；[W · CultivationViewModel.cs:324](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Cultivation/CultivationViewModel.cs#L324)；[H · InventoryService.ets:15](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/InventoryService.ets#L15)。

### F08 · 背包圣遗物评分预设与排序 — 缺失，P1

- **两端差距**：Windows 背包支持评分配置编辑、多个预设、活动预设保存/删除，包含攻击/生命/防御/精通等方向。鸿蒙角色面板已有基于角色推荐词条的 `ReliquaryScore`，但没有背包评分配置系统；不能把两种评分视为同一功能。
- **鸿蒙实现**：新增 `ReliquaryScoreProfile` 表，存属性权重、预设类型、算法版本和活动配置 ID；将纯计算从页面解耦，分别提供“角色推荐评分”和“背包自定义评分”。更换预设后按稳定的实例 ID 更新和排序，不改原始装备数据。
- **依赖/验收**：F07；对照 Windows 预设与自定义权重样例，验证百分比/固定值的单位、零权重、重启保持、删除活动预设的回退。评分只能作为排序依据，不将未知词条按零分伪装成完整结果。
- **源码**：[W · BackpackViewModel.cs:204](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Backpack/BackpackViewModel.cs#L204)；[W · BackpackService.cs:100](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Backpack/BackpackService.cs#L100)；[H · ReliquaryScore.ets:19](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/common/ReliquaryScore.ets#L19)。

### F09 · 未登录时访问本地祈愿档案 — 部分，P0

- **两端差距**：Windows 本地档案/文件导入与登录刷新分开；鸿蒙主 `build` 在 `!isLoggedIn` 时只显示登录指引，已有本地导入和档案选择代码因此无法正常进入。离线数据功能被账号状态错误阻断。
- **鸿蒙实现**：拆开 `archiveReady`、`gameAccountReady`、`cloudSessionReady`；进入祈愿页总是先读本地档案。无账号可查看/导入/导出/删除明确选中的档案；SToken 刷新和云操作单独检查各自会话。手动 URL 的档案归属继续采用响应 UID，不借用当前账号。
- **依赖/验收**：无网络、无登录、已有两档案时仍能浏览、导出和导入；空档案不创建空 UID；登录后不覆盖离线选档。交互细节见既有 UI/UX 文档。
- **源码**：[W · GachaLogViewModel.cs:120](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/GachaLog/GachaLogViewModel.cs#L120)；[H · GachaLogPage.ets:1801](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/pages/GachaLogPage.ets#L1801)；[H · UigfService.ets:146](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/UigfService.ets#L146)。

### F10 · UIGF 版本选择与选择性导入/导出 — 部分，P1

- **两端差距**：Windows 设置提供 2.2/2.3/2.4/3.0/4.0/4.1/4.2 导出版本及 UID 选择，导入也能选 UID。鸿蒙能解析这些主版本，但导出固定 4.2 全档案，导入预检后按 UID 逐次落库，缺用户选择和跨档案写入失败的统一结果。
- **鸿蒙实现**：`UigfCodec` 负责 parse/normalize/encode，VM 负责版本与 UID 选择；旧版只允许其可表达的数据，包含颂愿时明确阻止有损导出或让用户排除该部分。全文件验证后，选中 UID 在单 RDB 事务中提交，或明确报告已提交/未提交列表；推荐原子事务。
- **依赖/验收**：F09、F13；多 UID 只导入选中档案，2.x/3.0 的单 UID 限制准确，4.2 双分区可往返；64 位 ID、400 原池号、时区不变。跨档案事务是鸿蒙可靠性补强，不声称上游已经实现相同事务机制。
- **源码**：[W · SettingGachaLogViewModel.cs:38](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Setting/SettingGachaLogViewModel.cs#L38)；[W · SettingGachaLogViewModel.cs:77](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Setting/SettingGachaLogViewModel.cs#L77)；[H · UigfService.ets:87](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/UigfService.ets#L87)；[H · UigfService.ets:177](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/UigfService.ets#L177)。

### F11 · 分池保底、抽卡预测语义 — 部分，P0

- **两端差距**：Windows `PullPrediction` 使用云端对应分布及当前垫抽数，输出下一抽概率、预测剩余抽数和该点概率；武器阈值为 80、角色为 90。鸿蒙预测/倒计时复用固定 `ORANGE_GUARANTEE` 和 0.6%/74/90 模型，武器标题虽切换，计算并未换模型；将其注释为“对齐 Windows”不成立。
- **鸿蒙实现**：新增纯逻辑 `GachaPoolRules` 与 `GachaPredictionService`，数据层接现有云分布接口；按分布求条件概率，明确样本时间、池类型、当前垫数。无云权限/无样本时显示不可用；若保留本地理论模拟，则独立命名和说明，不混成 Windows 的经验分布预测。保底卡也读取分池规则。
- **依赖/验收**：F13、F15；同一分布样例与 Windows 算法结果一致；武器 79 抽、角色 89 抽、空分布/零样本、缺历史、未知池均有定义。颂愿常驻池不得照抄 `int.MaxValue` 分配数组，也不能套常规五星模型；“出五星”不等于“出指定 UP”。
- **源码**：[W · PullPrediction.cs:31](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/GachaLog/Factory/PullPrediction.cs#L31)；[W · TypedWishSummaryBuilderContext.cs:65](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/GachaLog/Factory/TypedWishSummaryBuilderContext.cs#L65)；[W · TypedWishSummaryBuilderContext.cs:80](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/GachaLog/Factory/TypedWishSummaryBuilderContext.cs#L80)；[H · GachaLogPage.ets:2246](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/pages/GachaLogPage.ets#L2246)；[H · GachaLogPage.ets:2367](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/pages/GachaLogPage.ets#L2367)。

### F12 · 角色/武器 UP 历史与未复刻时长 — 缺失，P2

- **两端差距**：Windows `WishCountdown` 根据所有已开始的 GachaEvent，按五星/四星角色与武器归集 UP 历史。鸿蒙名为 `countdownSection` 的区域实际是个人距保底抽数；`GachaHistoryService` 是有个人记录的卡池期次汇总，两者都不能替代物品 UP 历史。
- **鸿蒙实现**：新增本地 `WishHistoryService`，以 itemId 聚合 GachaEvent，保留每次开始/结束、版本、池号，忽略尚未开始事件；按 Windows 排除规则输出四类列表及距上次 UP 的时长，关联图鉴详情。不要把历史时长标为未来复刻预测。
- **依赖/验收**：F21 的完整事件元数据；不登录、没有个人抽卡记录仍可用，同期双池不重复计次，未来事件不使“距上次”变负，时间口径明确。
- **源码**：[W · GachaLogWishCountdownService.cs:27](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/GachaLog/GachaLogWishCountdownService.cs#L27)；[H · GachaLogPage.ets:1886](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/pages/GachaLogPage.ets#L1886)；[H · GachaHistoryService.ets:79](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/GachaHistoryService.ets#L79)。

### F13 · 颂愿原始子池、专属物品与云互通 — 部分，P0

- **两端差距**：Windows 枚举除了查询池 1000/2000，还保存活动子池 **20011/20012/20021/20022**，统计时合并活动子池，并有 `BeyondItem` 元数据。鸿蒙 `isBeyond` 仅认 1000/2000，UIGF 会拒绝合法子池，云 `queryType` 只归一化 400，子池上传/取回无法贯通；云物品补全只查角色/武器，未知颂愿物品会整批拒绝。
- **鸿蒙实现**：明确 `rawType` 与 `queryType`：子池保持原值落库/导出，查询和 EndIds 归并到 2000；`isBeyond` 覆盖完整枚举，仓储查询/去重/全量替换边界保持同一规则。发布 BeyondItem 的 ID、名称、品质和图标映射，云恢复使用正确领域的元数据；新物品可保留待解析记录，不能伪造星级。
- **依赖/验收**：F21；构造四个子池 + 1000/2000 混合样例，线上解析、本地统计、UIGF 导入/导出、云序列化全链路不丢原池号。查询仍只需 1000/2000，不能为了修复分类而额外误请求四个子池。该问题比新增统计图优先。
- **源码**：[W · GachaType.cs:36](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hoyolab/Hk4e/Event/GachaInfo/GachaType.cs#L36)；[W · TypedWishSummaryBuilderContext.cs:30](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/GachaLog/Factory/TypedWishSummaryBuilderContext.cs#L30)；[W · GachaStatisticsFactory.cs:143](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/GachaLog/Factory/GachaStatisticsFactory.cs#L143)；[H · GachaType.ets:60](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/model/GachaType.ets#L60)；[H · UigfService.ets:244](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/UigfService.ets#L244)；[H · HutaoCloudGacha.ets:8](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/model/HutaoCloudGacha.ets#L8)；[H · HutaoCloudService.ets:196](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/HutaoCloudService.ets#L196)。

### F14 · 深渊和剧诗战绩云上传 — 缺失 / 外部依赖，P1

- **两端差距**：Windows 两页都有上传命令，分别组装 `SimpleRecord` / `SimpleRoleCombatRecord`；鸿蒙目前只有祈愿云上传，挑战本地历史保存不等于上传至胡桃数据库。
- **鸿蒙实现**：新增 `ChallengeCloudService`，先用正确账号采集玩家信息、对应期挑战及协议需要的角色详情，在设备上构造并验证专用 DTO；预览 UID/区服/期次和上传内容后提交。米哈游 Cookie 只用于米哈游域，胡桃云只收到协议数据及需要的云凭据。记录本地上传结果、时间和内容摘要，便于重复提交判定。
- **依赖/验收**：F03、准确挑战快照、运营方接口；参照 Windows 保留深渊未登录通行证时的分支，但只有后端实际接受匿名上传才展示该选项，不能擅自假定两种上传均要求/均不要求登录。无战绩、采集部分失败、切 UID、重复上传、服务拒绝必须分开反馈。上游 `HardChallengeViewModel` 本次只有刷新命令，不臆造幽境云上传为既有功能。
- **源码**：[W · SpiralAbyssViewModel.cs:156](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/SpiralAbyss/SpiralAbyssViewModel.cs#L156)；[W · RoleCombatViewModel.cs:136](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/RoleCombat/RoleCombatViewModel.cs#L136)；[W · HutaoSpiralAbyssClient.cs:149](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hutao/SpiralAbyss/HutaoSpiralAbyssClient.cs#L149)；[W · HutaoRoleCombatClient.cs:42](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hutao/RoleCombat/HutaoRoleCombatClient.cs#L42)；[H · HutaoCloudService.ets:155](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/HutaoCloudService.ets#L155)。

### F15 · 胡桃统计的实体关联、上期对比和搭配查询 — 部分，P1

- **两端差距**：Windows 有角色出场/使用/持有率、楼层、队伍组合、武器/圣遗物搭配、当前与上期差值及图鉴联动；鸿蒙 15 类统计请求都可进入，但 VM 递归 `flatten` 成字符串路径，丢失可操作的实体结构，不能完成按角色/队伍查搭配、按楼层比较等任务。
- **鸿蒙实现**：分别建立 `AbyssStatistics/RoleCombatStatistics/GachaDistribution` 类型化仓储；同一统计保存本期、上期、期次及采样时间，按稳定 ID 做关联与差值，不能按数组位置连接。为角色/武器图鉴提供搭配查询服务，页面使用真正的排序、筛选、钻取动作。未返回项显示缺失，不补零制造增减。
- **依赖/验收**：F21 的角色/武器/套装元数据，部分祈愿统计需云权益；验证缺失上期、同角色多楼层、队伍顺序规范化、比例单位、接口失效保留最后成功缓存。图表外观由既有 UI/UX 规格约束。
- **源码**：[W · HutaoSpiralAbyssStatisticsCache.cs:115](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Hutao/HutaoSpiralAbyssStatisticsCache.cs#L115)；[W · HutaoSpiralAbyssDatabaseViewModel.cs:43](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Complex/HutaoSpiralAbyssDatabaseViewModel.cs#L43)；[W · WikiWeaponViewModel.cs:102](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Wiki/WikiWeaponViewModel.cs#L102)；[H · HutaoCloudService.ets:211](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/HutaoCloudService.ets#L211)；[H · HutaoCloudViewModel.ets:128](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/viewmodel/HutaoCloudViewModel.ets#L128)。

### F16 · 角色攻略映射与胡桃公告 — 部分 / 外部依赖，P2

- **两端差距**：Windows 依据角色 ID 获取中文/海外攻略 URL，首页另有胡桃公告；鸿蒙角色页主要拼米游社搜索/B站链接，已有的游戏公告不能替代胡桃公告。此前公开探测曾出现攻略 `/strategy/all` 404、公告请求 405，但这是历史响应，不足以宣告服务永久停用或确定新请求方法。
- **鸿蒙实现**：新增有明确来源和缓存期的 `StrategyRepository/HutaoAnnouncementRepository`，按上游当前端点、HTTP 方法、locale 和响应模型核对；仅在得到有效协议后上线。攻略按 avatarId 与语言匹配，失败回退当前搜索入口；公告有已读、空列表、暂不可用状态。公开内容请求不附带游戏 Cookie。
- **依赖/验收**：后端契约/可用性；这次没有反复发邮件、登录或试探写接口。可先用脱敏固定样例完成解析和页面验收，真实在线结果另记。不得猜测 405 的替代方法并把猜测写为已完成。
- **源码**：[W · WikiAvatarStrategyComponent.cs:50](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Wiki/WikiAvatarStrategyComponent.cs#L50)；[W · AnnouncementViewModel.cs:156](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Home/AnnouncementViewModel.cs#L156)；[H · WikiAvatarPage.ets:434](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/pages/WikiAvatarPage.ets#L434)；[H · AnnouncementService.ets:13](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/AnnouncementService.ets#L13)。

### F17 · 图鉴体型、所属与服装信息 — 部分，P2

- **两端差距**：Windows 角色筛选含 `Body/Association`，角色详情有 `CostumesView`；鸿蒙已有元素/武器/品质等组合筛选与基础详情，但精简 `WikiAvatarMeta` 缺这些完整字段和服装集合。料理信息已存在，不能再列为全缺失。
- **鸿蒙实现**：元数据转换保留枚举 ID、所属类型、服装 ID/默认标记/资源名/描述；`WikiViewModel` 增加组合筛选，服装选择仅影响当前详情显示。名称本地化与存储枚举分离，服装图片支持随包/远端缓存并有缺图回退。
- **依赖/验收**：F21、F23；默认服装正确、不同服装切换不改角色 ID、多筛选求交、清除恢复、热更后服装丢失能回到默认，离线详情仍可用。
- **源码**：[W · AvatarFilter.cs:62](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Wiki/AvatarFilter.cs#L62)；[W · AvatarFilter.cs:41](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Wiki/AvatarFilter.cs#L41)；[W · WikiAvatarViewModel.cs:112](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Wiki/WikiAvatarViewModel.cs#L112)；[H · WikiMetaService.ets:28](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/WikiMetaService.ets#L28)。

### F18 · 挑战完整期次导航与空记录状态 — 部分，P1

- **两端差距**：Windows 按各挑战 Schedule 元数据建立期次集合，再合并用户记录；鸿蒙主要列出实际抓取/保存过的历史，幽境无数据档期会跳过保存。用户无法同样查看某个已知期次的“未参与/未抓取/无详情”状态。
- **鸿蒙实现**：将 `ChallengeSchedule` 元数据和 `challenge_records` 分离，左连接按 UID/区服归属的记录，VM 使用明确状态枚举：未解锁、未参与、尚未抓取、仅概要、有详情、读取失败。关联现有敌人/祝福/角色元数据；刷新仅更新 API 能返回的期次，不声称可找回服务器已不提供的历史。
- **依赖/验收**：F21；两个账号在同一期不串档，空期可选，历史断网可读，当前期失败不覆盖上期。旧版无 UID 历史继续保留，归属修复作为文末迁移增强，不能自动指定给当前账号。
- **源码**：[W · RoleCombatService.cs:43](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/RoleCombat/RoleCombatService.cs#L43)；[W · HardChallengeService.cs:44](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/HardChallenge/HardChallengeService.cs#L44)；[H · HardChallengeViewModel.ets:84](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/viewmodel/HardChallengeViewModel.ets#L84)；[H · RelationalStoreHelper.ets:249](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/data/db/RelationalStoreHelper.ets#L249)。

### F19 · 便笺的后台联网刷新 — 部分 / 平台替代，P1

- **两端差距**：Windows 使用 Quartz 日常刷新任务（应用需要运行）；鸿蒙主要靠进程内 `setInterval`、卡片回调与代理提醒。代理提醒已存在，但只依据最近快照估计到点通知，不会获取新树脂/派遣状态，不能算完整后台联网刷新。
- **鸿蒙实现**：新增 `DailyNoteRefreshExtension extends WorkSchedulerExtensionAbility`，注册网络条件下的延迟任务；持久化待刷新 UID、所属账号 ID、最后成功时间、失败原因和下次资格。扩展进程自己初始化仓储/凭据服务，不依赖前台 `AppStorage` 和页面单例；`onWorkStop` 取消请求和安全落盘。继续用 `reminderAgentManager` 做用户开启的到点提醒，回前台立即核实并重排提醒。
- **限制/验收**：官方文档规定延迟任务随活跃分组调度，活跃组最短也为 2 小时、单次回调最多 2 分钟；它不等价于设置中的分钟级刷新。前台用现有频率，后台显示最后刷新时间/估算标识。验证挂起、系统终止、断网、权限拒绝、账号删除、多 UID 配额和任务超时；不能用伪播放维持常驻。
- **源码**：[W · DailyNoteRefreshJobScheduler.cs:10](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Job/DailyNoteRefreshJobScheduler.cs#L10)；[H · DailyNoteService.ets:368](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/DailyNoteService.ets#L368)；[H · DailyNoteReminderService.ets:10](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/DailyNoteReminderService.ets#L10)；平台依据 S01/S02。

### F20 · 自动签到的跨日调度 — 部分 / 平台替代，P1

- **两端差距**：Windows `AutoSignInJobScheduler` 将当前账号签到排到服务器次日零点附近并按日重复；鸿蒙 `AutoSignInService` 的主要触发是应用启动，已有服务器日去重和十分钟失败冷却，但持续打开/长时间不启动时不形成同等调度闭环。
- **鸿蒙实现**：前台增加跨服务器日检查；后台与 F19 共享延迟任务入口，扫描已到签到资格的**用户选择账号**，通过 UID/region/serverDay 唯一任务键去重。无网络等待，风控转为“需用户处理”并通知，不能后台显示验证页面或把风控记成成功。多账号自动签到是可选扩展，Windows 当前任务也只取当前账号。
- **依赖/验收**：F19；跨区服日界线、设备时区改变、当日已签、进程重启和失败冷却都不重复签到；系统不调度时显示未执行，并在下次前台补偿，不承诺准点或必达。
- **源码**：[W · AutoSignInJobScheduler.cs:23](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Job/AutoSignInJobScheduler.cs#L23)；[W · AutoSignInJob.cs:22](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Job/AutoSignInJob.cs#L22)；[H · AutoSignInService.ets:27](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/AutoSignInService.ets#L27)；[H · EntryAbility.ets:214](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/entryability/EntryAbility.ets#L214)。

### F21 · 游戏数据更新的一致性、校验与恢复 — 部分，P0

- **两端差距**：Windows 当前元数据走受仓库版本管理的 `GitRepositoryService`，旧管线也有文件摘要验证。鸿蒙 `GameDataUpdater` 清单只有 path/url/version，逐项下载后删除目标并改名；若后面失败，前面的文件已经替换，版本戳却不变。顶部注释的“全部成功后覆盖”与实际代码不一致，方法名 `downloadWithAgent` 实际仍是普通 HTTP 全缓冲下载。
- **鸿蒙实现**：数据清单 v2 增加 schema、上游 SHA、大小和 SHA256；拒绝绝对路径、`..`、重复路径与越界目标，限制类型/文件大小及下载域策略。整版下载到独立 staging 目录，校验摘要和关联模型（技能/事件/装备）后，原子更新活动版本指针；保留上一成功版本并能回滚。使用 `cryptoFramework` 摘要；大资源用 `request.agent`，记录任务 ID/进度，恢复后重新确认状态。
- **依赖/验收**：需同步调整独立数据仓库，不能只改 APP。中途断网/低空间/损坏文件/崩溃后，重启必须完整使用旧版或新版之一；校验通过前不改变活动缓存版本。版本切换后统一通知各元数据缓存失效。整版快照是鸿蒙的可靠性设计，不声称 Windows Git 管线已提供同样原子保证；摘要校验也不等同于签名认证。
- **源码**：[W · MetadataService.cs:55](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Metadata/MetadataService.cs#L55)；[W · GitRepositoryService.cs:41](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Git/GitRepositoryService.cs#L41)；[W · LegacyMetadataService.cs:99](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Metadata/LegacyMetadataService.cs#L99)；[H · GameDataUpdater.ets:237](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/data/remote/GameDataUpdater.ets#L237)；[H · GameDataUpdater.ets:292](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/data/remote/GameDataUpdater.ets#L292)；[H · GameDataUpdater.ets:304](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/data/remote/GameDataUpdater.ets#L304)；平台依据 S03。

### F22 · 应用版本比较与升级入口 — 部分 / 平台替代，P1

- **两端差距**：Windows 比较版本、检查发布包校验信息并启动自己的 Windows 部署器；鸿蒙只比较 GitHub tag 去掉 v 后是否等于 versionName，不相等就报“发现新版本”，本机比云端新时也会误报。
- **鸿蒙实现**：新增 `AppUpdateService`，统一 versionCode/可比较版本、发布通道、最低 API、更新说明与可信发布链接；优先进入已配置的鸿蒙分发渠道详情页，开发分发保留 GitHub Release。下载若提供包摘要则校验，但安装仍交给合法分发/系统确认流程，不移植 `.exe` 部署器或尝试静默安装其他应用。
- **依赖/验收**：需真实分发配置；相同/较旧/较新/预发布/无 release/网络失败都有正确结果，API24 不被引导至最低版本更高的包，未签名构建不显示为可直接安装的正式更新。
- **源码**：[W · UpdateService.cs:57](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Update/UpdateService.cs#L57)；[H · SettingPage.ets:225](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/pages/SettingPage.ets#L225)。

### F23 · 界面及游戏元数据多语言 — 部分，P2

- **两端差距**：Windows `SupportedCultures` 定义 15 个语言选项，并在元数据路径、公告及文档搜索使用语言；鸿蒙有大量中文直接字符串和中文元数据，海外端点可用不等于国际化完成。
- **鸿蒙实现**：将功能文案、错误提示、数量/日期格式迁入资源，使用 `resourceManager/i18n` 与语言偏好；元数据以 ID 为键、语言作为展示包维度，切换语言不更改档案实体。端点语言通过统一配置传递，服区与 UI 语言独立；先完成框架和中文/英文闭环，再逐个补齐上游其余语言。
- **依赖/验收**：F02、F17、F21；语言切换后搜索、公告、材料名、导出语言说明一致，缺译项有固定回退。英文阶段只能标部分完成，15 项资源与相关数据包均验收才可标语言范围对齐。
- **源码**：[W · SupportedCultures.cs:14](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/SupportedCultures.cs#L14)；[W · MetadataService.cs:86](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Metadata/MetadataService.cs#L86)；[H · SettingPage.ets:215](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/pages/SettingPage.ets#L215)；[H · UigfService.ets:105](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/UigfService.ets#L105)

### F24 · 背景视频离线缓存与媒体管理 — 部分，P2

- **两端差距**：Windows 支持从目录选择本地视频、官方视频缓存及失败流式回退；鸿蒙能选择文件复制到沙盒、播放官方视频、循环/静音/前后台暂停，但官方视频主要直接用 URL，重选本地媒体后缺完整旧文件管理与容量视图。
- **鸿蒙实现**：`BackgroundMediaRepository` 保存来源、文件大小、最后使用和有效性；官方媒体用 `request.agent` 下载并校验后切换，断网优先最后成功缓存。用户选文件/受支持设备上授权目录后建立播放列表，不扫描任意目录；提供删除单项/清理未引用缓存，保留正在播放文件。
- **依赖/验收**：S03 和文件授权；下载取消不切到坏文件、权限失效可重选、离线重启能播、重复导入不无限增大、清理后不破坏备份/业务数据库。媒体处理不构成后台联网保活手段。
- **源码**：[W · BackgroundMediaPlayerService.cs:124](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/BackgroundMediaPlayer/BackgroundMediaPlayerService.cs#L124)；[H · BackgroundMediaService.ets:37](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/BackgroundMediaService.ets#L37)；[H · BackgroundMediaService.ets:57](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/BackgroundMediaService.ets#L57)。

### F25 · 文档检索与可操作诊断 — 部分 / 外部依赖，P2

- **两端差距**：Windows 反馈页含文档搜索、搜索结果跳转和网络信息；鸿蒙 `SupportService` 主要打开 Issue 页面、复制应用/API/设备类型与复现模板，缺直接检索和失败任务诊断入口。
- **鸿蒙实现**：新增 `HelpViewModel/DocumentationSearchService`，按语言查询官方胡桃文档搜索协议，离线提供维护者打包的常见问题索引；诊断仅采集用户选择的错误码、功能、时间、版本与脱敏网络状态，可预览再复制/导出。可选网络信息查询只由用户触发；Windows Loopback 豁免命令不应照搬。
- **依赖/验收**：搜索服务可用性与本项目问题分类；无结果/离线/服务失败可以跳转帮助页，错误报告不含 Cookie、Token、authkey 或原始账号数据库。已有 Issue 外链保留。
- **源码**：[W · FeedbackViewModel.cs:81](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Feedback/FeedbackViewModel.cs#L81)；[W · FeedbackViewModel.cs:57](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Feedback/FeedbackViewModel.cs#L57)；[H · SupportService.ets:7](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/SupportService.ets#L7)。

### F26 · 跨尺寸导航与业务上下文保留 — 部分，P0

- **两端差距**：鸿蒙同一 `currentIndex` 在手机标签与宽屏侧栏映射不同，例如索引 2/3 分别对应不同业务，跨断点可能切到另一功能。宽屏内嵌与路由页面又有两套返回逻辑，角色→图鉴→养成的任务上下文不够稳定。该问题已在 UI/UX 调研指出，也属于功能可达性问题。
- **鸿蒙实现**：用统一 `RouteId + RouteParams` 表示业务位置，手机/宽屏只是不同导航呈现；建立带来源 route 的任务返回栈。页面状态按 route + UID/archiveId/projectId 保存，不按位置编号保存；切账号使用请求版本号阻断迟到结果。
- **依赖/验收**：与 F05/F09 同批先改；窄宽窗口切换后仍为同一业务/档案，返回恢复选中角色、筛选和项目；删除档案时只退出受影响页面。具体导航映射与验收详见 UI/UX 文档。
- **源码**：[W · MainViewModel.cs:34](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/MainViewModel.cs#L34)；[H · Index.ets:86](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/pages/Index.ets#L86)；[H · RouteParams.ets:6](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/model/RouteParams.ets#L6)。

### F27 · 全局热键、应用快捷键与桌面直达 — 缺失 / 平台替代，P2

- **两端差距**：Windows 有 HotKey 设置与创建游戏启动快捷方式；鸿蒙当前没有对应可配置命令系统。不能简单判为“鸿蒙不支持全局热键”：API14 起已有 `inputConsumer` 应用全局快捷键，API24 在设备能力满足时可使用。
- **鸿蒙实现**：新增 `CommandRegistry/ShortcutService`；前台查询、刷新、返回用组件 `keyboardShortcut`，需全局触发的少量动作使用 `inputConsumer.on('hotkeyChange')`，提供冲突查询/修改与退出注销。桌面直达通过 AppGallery Kit `checkPinShortcutPermitted → requestNewPinShortcut` 指向本应用路由，再执行用户配置的游戏启动/祈愿/便笺动作。
- **限制/验收**：桌面快捷方式当前指南限制单应用最多 2 个、需要系统确认且不支持模拟器调试；API24 可用查询/删除接口管理。验证设备无键盘、快捷键冲突、801、重复创建、冷启动路由和安装渠道差异。不使用仅系统应用可用的 shortcutManager 接口冒充普通应用实现。
- **源码**：[W · SettingHotKeyViewModel.cs:12](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Setting/SettingHotKeyViewModel.cs#L12)；[W · SettingViewModel.cs:271](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Setting/SettingViewModel.cs#L271)；[H · EntryAbility.ets:18](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/entryability/EntryAbility.ets#L18)；平台依据 S04/S05。

### F28 · 游戏安装、更新、预下载、校验和修复 — 平台替代 / 外部依赖，P2

- **两端差距**：Windows 有游戏定位和 Sophon 包操作（安装/更新/预下载/校验/修复/渠道转换）；鸿蒙目前只保存公开 Want/URI 后拉起，没有对应原生游戏包管理。
- **鸿蒙实现**：新增 `GameProvider` 能力描述，分别表示“可拉起、可打开商店、可查看版本、厂商是否提供资源管理协议”。默认提供公开入口和厂商/商店下载页；仅厂商明确开放、且用户授权目录可访问时，才设计针对**鸿蒙资源格式**的下载/校验任务。Windows Sophon/EXE 文件不是鸿蒙原生安装包，不作直接移植。
- **依赖/验收**：需要已核实厂商入口/分发协议；未获协议时明确“由游戏/应用市场管理”，不能显示已修复。仅能管理本应用沙盒及用户授权文件，不修改游戏私有目录。安装状态无法查询时保留未知，不把启动错误一律解释为未安装。
- **源码**：[W · GamePackageViewModel.cs:24](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Game/GamePackageViewModel.cs#L24)；[W · GamePackageService.cs:33](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Game/Package/Advanced/GamePackageService.cs#L33)；[H · GameLauncherService.ets:83](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/GameLauncherService.ets#L83)；[H · GameLauncherService.ets:88](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/GameLauncherService.ets#L88)。

### F29 · 游戏账号切换、启动参数和程序联动 — 平台替代 / 外部依赖，P2

- **两端差距**：Windows 读取注册表游戏账号，管理游戏分辨率/窗口等启动参数、结束进程和延迟启动其他程序；这与工具里的米游社账号管理是两回事。鸿蒙没有相应游戏会话切换协议。
- **鸿蒙实现**：仅对厂商公开支持的 URI/Want 参数建有类型的启动预设；账号切换指向游戏公开账号页，缺少协议则提示进入游戏自行切换。工具自身窗口参数使用 Window API；联动其他应用仅用明确公开入口，不执行任意 Windows 程序或跨应用强制结束进程。截图功能可用系统照片/文件选择器读取用户选定截图。
- **依赖/验收**：厂商公开能力决定等价程度；每个预设记录支持平台和来源，旧入口失效可编辑。不得通过猜 bundle、注册表仿造或提升权限承诺跨应用切号。可用外部入口返回正确结果，不支持的操作不给假成功。
- **源码**：[W · GameInRegistryAccountService.cs:15](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Game/Account/GameInRegistryAccountService.cs#L15)；[W · LaunchGameViewModel.cs:499](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Game/LaunchGameViewModel.cs#L499)；[W · LaunchGameViewModel.cs:433](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Game/LaunchGameViewModel.cs#L433)；[H · GameLauncherService.ets:39](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/service/GameLauncherService.ets#L39)。

### F30 · 非注入插件宿主 — 缺失 / 平台替代，P3

- **两端差距**：Windows 插件服务加载 `.hutao` 压缩包、manifest 和 .NET DLL，提供 `PluginContext.ServiceProvider`、启停及配置。插件宿主本身并不等于向游戏注入，不能一概排除；现有 DLL 二进制也不能在 ArkTS 应用直接执行。
- **鸿蒙实现**：先盘点要保留的具体非注入插件，再定义 `HutaoExtension` 能力接口（只读数据转换、导入器、导出器、图鉴附加内容、受控任务）；首版将经过审核的 ArkTS 模块随 APP 构建发布，数据型扩展使用有 schema 的声明文件。配置页面由类型化描述生成；敏感凭据由宿主代理，插件不获得全局服务容器。
- **依赖/验收**：独立扩展协议和分发决策；每个原插件说明“源码重写/只支持数据部分/无法等价”的状态。启停配置可持久化、单插件失败不损坏数据库。该方案是功能重实现，不宣称兼容现有 Windows DLL，也不在本次文档提交时安装插件。
- **源码**：[W · PluginService.cs:252](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Plugin/PluginService.cs#L252)；[W · PluginContext.cs:7](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/API/Model/PluginContext.cs#L7)；鸿蒙扫描范围为 `pages/service/viewmodel`，无对应插件宿主入口。

### F31 · 工具脚本控制台 — 缺失 / 平台替代，P3

- **两端差距**：Windows 托盘可打开脚本窗口，`ScriptingViewModel` 用 Roslyn 执行 C#，`ScriptContext` 暴露 JSON/请求/工具服务；不是自动等同于游戏注入。鸿蒙无该控制台，也没有原生 C# 脚本宿主。
- **鸿蒙实现**：先枚举真实脚本用途，提供 JSON 格式化、脱敏诊断、用户文件转换等内置命令；如确需用户组合任务，设计声明式步骤 DSL 和有限能力列表，执行前展示输入/输出，限制时长、内存、可写文件范围。普通工具命令和游戏注入命令彻底分开。
- **依赖/验收**：依赖 F30 的能力接口；Windows 任意 C# 兼容性保持明确“不支持”。可取消、错误定位到步骤、写入按事务或输出新文件，不能暴露 Token 到任意 URL。只有确认具体脚本需求后才能评价替代方案的覆盖率。
- **源码**：[W · NotifyIconViewModel.cs:271](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/NotifyIconViewModel.cs#L271)；[W · ScriptingViewModel.cs:39](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Scripting/ScriptingViewModel.cs#L39)；[W · ScriptContext.cs:23](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Core/Scripting/ScriptContext.cs#L23)；鸿蒙扫描范围同 F30。

### F32 · 托盘、关闭行为与独立网页工具窗 — 部分 / 平台替代，P2

- **两端差距**：Windows 有 NotifyIcon 菜单、窗口显示/隐藏与关闭行为，以及 `CompactWebView2Window` 的独立网页、上次 URL、置顶和视频快捷控制。它是独立工具窗口，不应与注入式游戏内 Overlay 一并排除。鸿蒙已有自适应窗口、标题按钮避让和便笺卡片，但没有对应网页工具窗闭环。
- **鸿蒙实现**：先对照 `NotifyIconViewModel` 的每条非注入命令映射为应用快捷动作；phone/tablet 用卡片/通知直达以及正常 ArkWeb 页面，PC/2in1 按公开 Window 能力提供 ArkWeb 子窗、URL 恢复和明确的关闭行为。置顶、失焦透明和视频控制分别核对能力，不把 Windows 低级键盘钩子照搬；无法等价时使用窗口内操作和 F27 的受支持热键。状态写入持久层，不把子窗口存在作为进程常驻保证。
- **依赖/验收**：F19/F26/F27；只使用该设备支持的窗口类型和系统能力。关闭主窗、重开网页子窗、从卡片返回同 UID、任务结束清理均验证；缺少同等系统托盘能力时明确采用卡片/快捷入口替代。上游应用截图命令受 Debug/Alpha 条件限制，本轮只作开发工具候选，不计作正式发布版必缺功能。
- **源码**：[W · NotifyIconViewModel.cs:196](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/NotifyIconViewModel.cs#L196)；[W · CompactWebView2Window.xaml.cs:82](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Window/WebView2/CompactWebView2Window.xaml.cs#L82)；[W · LastWindowCloseBehavior.cs:7](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/LastWindowCloseBehavior.cs#L7)；[W · NotifyIconViewModel.cs:311](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/NotifyIconViewModel.cs#L311)；[H · EntryAbility.ets:263](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/entryability/EntryAbility.ets#L263)；[H · DailyNoteFormExtensionAbility.ets:22](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/widgets/DailyNoteFormExtensionAbility.ets#L22)。

## 4. 不能混入“尚未移植”的事项

| 事项 | 本次结论 | 后续处理 |
|---|---|---|
| 真实登录/云通行证/邮件/兑换/祈愿云备份 | 客户端代码已存在，尚无真实账号的完整成功/失败闭环证据 | 建独立在线验收记录；不可将“未测试”改写为“没实现”或“已可用” |
| API24 设备装机、提醒配额、卡片和后台刷新 | 编译与本地样例验证不能证明真机行为 | API24 与较新系统、phone/tablet/2in1 分层验证；S01 调度限制必须进入验收 |
| 海外 SToken 自动获取祈愿 authkey | Windows 相应 provider 本身也有限制；鸿蒙手动 URL/文件入口属于有效回退 | 不把它笼统列为鸿蒙独有缺失；新增方案需官方可用授权依据 |
| 海外活动日历 | Windows 首页收到海外账号时会清空该活动日历 | 不凭“全量海外”猜测上游已支持该接口；先保持明确可用范围 |
| 札记跨年归档、项目改名、加密可携备份 | 值得做，但本次未找到充分的上游同等闭环证据 | 作为产品增强单独排期，不提高移植缺口数量 |
| Windows 数据库一键迁移 | 用户可能需要，但上游已有本地数据库不等于现成跨平台互通格式 | 可做只读导出转换器，导出无凭据 JSON，再用鸿蒙预检/事务导入；不可直接用 Windows DB 覆盖鸿蒙 RDB |
| 鸿蒙旧三张挑战历史表无 UID 的记录 | 当前刻意保留，防止错误归属；没有自动显示并非记录被删 | 另做“旧记录归属修复”向导，用户确认 UID/region 后复制到新表，原件保留；纳入备份格式升级 |
| 深渊个人排名/上传检查 | `HutaoSpiralAbyssClient` 有 `GetRankAsync/CheckRecordUploadedAsync`，但本次在上游 Service/ViewModel/UI 未找到调用点 | 作为**协议储备**，可为 F14 增强；不宣称是当前 Windows 可操作页面，也不把它计入 32 项用户功能缺口 |
| 幽境云上传、自动永久抓全背包、预测未来 UP | 没有相应可核实的非注入完整闭环依据 | 不臆造功能或接口；尤其不可用养成计算器部分库存冒充完整背包 |

补充证据：[W · GachaLogQuerySTokenProvider.cs:30](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/GachaLog/QueryProvider/GachaLogQuerySTokenProvider.cs#L30)；[W · AnnouncementViewModel.cs:93](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Home/AnnouncementViewModel.cs#L93)；[W · TravelersDiaryViewModel.cs:47](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/TravelersDiary/TravelersDiaryViewModel.cs#L47)；[W · HutaoSpiralAbyssClient.cs:32](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hutao/SpiralAbyss/HutaoSpiralAbyssClient.cs#L32)；[W · HutaoSpiralAbyssClient.cs:45](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hutao/SpiralAbyss/HutaoSpiralAbyssClient.cs#L45)；[H · RelationalStoreHelper.ets:176](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/1a85b1788e61608150c4a3034cc497eae795be40/entry/src/main/ets/data/db/RelationalStoreHelper.ets#L176)。

## 5. 可落地的鸿蒙架构与数据变更

以下是后续实施设计，当前提交不修改这些文件。

| 模块 | 建议改动位置 | 数据与 API 方案 | 兼容要求 |
|---|---|---|---|
| 区域网络 | `common/HoyolabEndpoints`、`data/network`、`service/LedgerService/AnnouncementService` | 统一 `AccountContext`（账号 ID、UID、region、locale）；请求前固定上下文，迟到响应不可写到另一个账号 | API24 网络接口；保留现有凭据域隔离和重试上限 |
| 角色/元数据 | `WikiMetaService`、拟新增 `AvatarSkillResolver`；独立数据仓库 | ID 化完整技能/命座/服装/BeyondItem/挑战 Schedule；版本关联 | 原精简数据可回退，但缺字段显示未知 |
| 养成 | `CultivationRepo/ViewModel`、拟新增 `CultivationService` | 输入 schema + 计算结果同事务；同步只变当前值；材料库存按项目明确归属 | 新迁移追加到现有 DB v6 后，不回写历史迁移 |
| 背包 | 拟新增 `BackpackRepo/Service/ViewModel/Page` | `backpack_archives`、`backpack_items`、`reliquary_score_profiles`；实例键、来源、原始载荷、更新时间 | UIIF 导入全量预检；无注入；大文件解析用任务并发能力并有大小上限 |
| 祈愿 | `GachaType/GachaRepo/UigfService/HutaoCloudGacha`、拟新增 `GachaPoolRules` | 原始池号保留，查询池号派生；统一游标/去重；预测规则独立于 View | 修规则不能重写历史池号；先验证迁移样例 |
| 挑战/云 | 拟新增 `ChallengeCloudService`、统计 DTO/Repo | 原始挑战快照与云上传 DTO 分开；`cloud_upload_state` 保存类型/UID/区服/期次/内容摘要/结果，不保存游戏凭据 | 云返回失败不改变本地挑战数据；后端不可用时可读本地 |
| 后台任务 | 拟新增 WorkScheduler 扩展与 `BackgroundJobRepo`，调整便笺/签到服务 | `background_jobs` 记录资格、最后尝试/成功、错误与去重键；扩展独立初始化 | 无 UI 依赖；并发锁防前后台重复提交；调度不保证准时 |
| 更新 | `GameDataUpdater/GameDataService`、拟新增 `AppUpdateService` | 数据 staging + active 版本指针 + 上一版本；HTTP/agent 下载职责分开 | 公共元数据与敏感数据请求隔离，API24 可用；进程终止后恢复 |
| 入口/平台 | `Index/EntryAbility`、拟新增 `CommandRegistry/GameProvider` | 路由 ID、Want 参数、能力描述；窗口、键盘、卡片都调用同一命令 | 按运行时 API/系统能力和设备验证；不要按“PC 就一定支持”分支硬写 |

新增持久表/偏好必须同步更新 `BackupSnapshot/BackupService` 的白名单、外键预检、还原次序与恢复日志。备份格式当前 v2，若增加新的必需结构，应明确升级格式及迁移策略；旧备份不能将新表静默清空。云 Token、设备标识、暂存登录态不进入可携业务备份，保持当前分离设计。新功能仍遵守 `pages → viewmodel → service → repo/network → model`，不得继续把预测算法、协议和数据库写入堆到页面里。

## 6. 实施顺序与完成门槛

| 批次 | 对应事项 | 可审阅交付物 | 退出条件 |
|---|---|---|---|
| A：访问与数据正确性 | F02/F03/F09/F11/F13/F21/F26 | 区域请求表、技能/BeyondItem 元数据转换、祈愿规则、路由修正、更新快照方案 | 无登录本地可用；合法颂愿子池互通；先修分池规则并停用误导预测，云经验预测待 C 批接通；坏更新不影响活动数据 |
| B：角色—养成—背包闭环 | F04–F08、F10、F18 | 新表迁移、统一养成草稿、编辑/同步、完整背包、选择性文件互通、挑战期次 | 重启后输入/结果一致；重复装备不合并丢失；旧备份/数据库升级可恢复 |
| C：云数据闭环 | F14–F16，完成 F11 云预测部分 | 上传 DTO 与预览、统计类型模型、期次对比/搭配；后端契约记录 | 固定样例通过后再进行授权账号验收；不可用端点明确隔离，不报假成功 |
| D：设备和后台 | F19/F20/F22/F27–F29/F32 | 扩展任务、版本服务、命令与厂商能力表、系统入口 | API24 真机挂起/终止/重开/权限拒绝有记录；可替代与不支持能力均可见 |
| E：完整产品范围 | F01/F12/F17/F23–F25 | 海外登录闭环、UP 历史、服装/筛选、多语言、媒体/帮助 | 数据来源与缓存清楚，跨语言/离线/服务失败可以完成核心任务 |
| F：扩展能力重实现 | F30/F31 | 非注入插件清单、ArkTS 扩展协议、内置命令/可选 DSL 设计 | 按每个实际插件/脚本验收，不以“框架存在”替代兼容性 |

这不是日历承诺。F14/F16/F28/F29 的后端或厂商协议存在外部依赖，F19/F20/F27 需真机；应先完成无需外部账号的模型/协议样例/回退实现，再评估剩余工作。后续按一项或一组紧密相关事项提交，PR 引用 F 编号和实际通过的验收，不再使用笼统“全量完成”。

## 7. 验收样例清单

| 编号 | 场景 | 核心预期 | 对应事项 |
|---|---|---|---|
| T01 | 未登录、断网、两份本地祈愿档案 | 能切换、查看、选择性导出，不强制登录 | F09/F10 |
| T02 | API 返回另一 UID，操作中切账号 | 拒绝串档；旧请求结果不更新新账号页面 | F02/F14/F26 |
| T03 | CN/US/EU/AS 札记与公告 | 请求域、签名、语言、缓存键全部匹配 | F02 |
| T04 | 海外邮件验证/第三方取消 | 不残留半会话，可明确重试 | F01 |
| T05 | 技能顺序打乱、命座额外等级 | 页面/文本/养成用同一 ID 关联，基础与额外分开 | F03 |
| T06 | 同武器等级、两种突破状态 | 属性/材料不同且正确，缺值不猜 | F04 |
| T07 | 两角色批量、其中一个已存在 | 用户选择的目标/项目正确，新增与跳过数可解释 | F05 |
| T08 | 编辑旧计划、同步当前等级、重启 | 目标不被覆盖，输入/材料同事务恢复 | F06 |
| T09 | UIIF 同 itemId 的两件圣遗物 | 实例、等级、词条、锁定信息均保留 | F07 |
| T10 | 更换/删除评分预设 | 排序重算可重复，原装备数据不变 | F08 |
| T11 | UIGF 七种目标版本与多 UID | 仅导出可表达数据；旧版限制明确 | F10 |
| T12 | 武器 79、角色 89、无云分布 | 正确池规则；经验预测无数据时不可用 | F11 |
| T13 | 没有个人记录，含未来 GachaEvent | UP 历史可用，未来事件不参与已发生历史 | F12 |
| T14 | 20011/20012/20021/20022 混合记录 | 原池号往返保留，查询归并 2000，统计不漏 | F13 |
| T15 | 新颂愿物品、云恢复只有 itemId | 依据 BeyondItem 补全或标待解析，不伪造品质 | F13 |
| T16 | 深渊/剧诗上传、采集部分失败 | 不提交不完整 DTO；显示真实服务结果 | F14 |
| T17 | 本期/上期角色数组顺序不同 | 按 ID 连接，差值/楼层/搭配正确 | F15 |
| T18 | 攻略404、公告405、统计超时 | 保留可用缓存/搜索回退，失败状态不冒充空数据 | F15/F16 |
| T19 | 默认/替换服装与体型/所属组合筛选 | ID 不变、筛选求交、缺图有回退 | F17 |
| T20 | 空期、仅概要、有详情、多账号历史 | 期次完整且状态可区分，不错属 UID | F18 |
| T21 | 便笺挂起/终止/离线/配额用尽 | 标最后成功与估算；任务取消可恢复，无准点承诺 | F19 |
| T22 | 跨服务器日、重复回调、风控签到 | 同一去重键只成功一次，需验证不会记成功 | F20 |
| T23 | 更新中断、坏摘要、越界路径、低空间 | 活动数据仍为完整旧版；拒绝不合法写入 | F21 |
| T24 | 本地版本高于 release、无发布 | 不误报更新，不引导不兼容安装 | F22 |
| T25 | 中文/英文及剩余语言切换 | UI/搜索/公告语言一致，数据主键不变 | F23 |
| T26 | 视频下载中断、离线重启、清缓存 | 最后成功媒体可用，不删除正在引用文件 | F24 |
| T27 | 复制诊断、搜索离线/无结果 | 有帮助回退；诊断无凭据 | F25 |
| T28 | 手机/宽屏往返、返回原角色计划 | 保留 route 和业务上下文 | F26 |
| T29 | 热键冲突、桌面快捷方式超配额 | 有解释和回退；未获系统确认不报创建成功 | F27 |
| T30 | 游戏未配置/入口失效/无厂商修复协议 | 不猜安装状态、不伪造游戏修复/切号成功 | F28/F29 |
| T31 | 插件/脚本失败、超时、取消 | 局部失败隔离、文件/数据库可恢复 | F30/F31 |
| T32 | 关闭/重开窗口、卡片直达指定 UID | 正确恢复目标上下文，系统能力缺失有替代 | F32 |

每个样例保留“固定输入、环境、实际输出、是否通过”；涉及真实个人数据的样例仅保存脱敏摘要。算法/格式/迁移可做本地自动验证；ArkTS 编译、API24 真机、云后端分别留证据，互不替代。

## 8. 鸿蒙官方 API 依据与复核方式

文档依据来自本次 `devecocli docs search/read` 返回的官方文档正文与已部署 SDK 声明。网页检索对部分华为文档仅能得到标题或超时，因此实现约束以实际读取的官方正文为证，不以第三方转载补全。以下链接便于阅读，文档 ID 便于重复检索。

| 编号 | 官方资料 | 本报告采用的事实 |
|---|---|---|
| S01 | [延迟任务](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/work-scheduler)、[延迟任务回调](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-workschedulerextensionability) | Stage 模型、独立扩展进程；最多 10 个任务，活跃分组最短间隔 2 小时，单次回调最长 2 分钟；系统条件可进一步延迟 |
| S02 | [代理提醒](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder)；SDK `reminderAgentManager`；当前 `DailyNoteReminderService` | 到点提醒与后台联网是两种职责；沿用已有提醒能力，仍需设备上的权限/配额/取消验收 |
| S03 | [上传下载 request](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-request) | SDK `request.agent.create` 从 API10 起提供；API24 可用，需检查 `SystemCapability.Request.FileTransferAgent`，使用合法沙盒路径、任务状态和取消/恢复语义 |
| S04 | [全局快捷键 inputConsumer](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-inputconsumer) | API14 起提供；`hotkeyChange` 为应用快捷键订阅，冲突码 4200002/4200003、能力不足 801；不能把窗口内 `keyPressed` 监听混成同一能力 |
| S05 | [添加桌面快捷方式](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/appgallery-productview-addshortcut)、[查询快捷方式](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/appgallery-productview-getshortcut) | `checkPinShortcutPermitted/requestNewPinShortcut`；系统确认，最多 2 个，不支持模拟器；6.1.1(24) 增加查询/删除入口 |

完整文档 ID（可作为 `devecocli docs read '<ID>'` 参数）：

```text
开发指南/Background_Tasks_Kit_后台任务开发服务/延迟任务_ArkTS/work-scheduler
API参考/Background_Tasks_Kit_后台任务开发服务/ArkTS_API/ohos_WorkSchedulerExtensionAbility_延迟任务调度回调_/js-apis-workschedulerextensionability
API参考/基础功能/Input_Kit_多模输入服务/ArkTS_API/ohos_multimodalInput_inputConsumer_全局快捷键_/js-apis-inputconsumer
开发指南/AppGallery_Kit_应用市场服务/应用市场推荐/应用内快捷方式/添加桌面快捷方式/appgallery-productview-addshortcut
开发指南/AppGallery_Kit_应用市场服务/应用市场推荐/应用内快捷方式/查询应用内快捷方式/appgallery-productview-getshortcut
```

SDK 声明文件相对于 `SDK/default`，本次 SHA256 如下，可复核采用的版本而无需提交 SDK：

| 文件 | SHA256 |
|---|---|
| `openharmony/ets/api/@ohos.resourceschedule.workScheduler.d.ts` | `d748a67e28e93345e2061ad3c5c21c6751719dff28f7bd27e0803c8767e8e0d0` |
| `openharmony/ets/api/@ohos.reminderAgentManager.d.ts` | `88895a70577b688dd5df18a8a594851cde8bcfb5ada29b99ee6a91c59db5f19a` |
| `openharmony/ets/api/@ohos.request.d.ts` | `51e4f373a7f8617c4237decdb14ad9f21db9533a2c925376ada658c62c3d1987` |
| `openharmony/ets/api/@ohos.multimodalInput.inputConsumer.d.ts` | `46265cd28154a9b44ce72b2e51aab999f7e4b5dc1d60a4e11061076526e2a60e` |
| `hms/ets/api/@hms.core.appgalleryservice.productViewManager.d.ts` | `7d943414f5741ddc836b83c4b27ea311c69169b113f469d9492950e1f1fc096a` |

API26 的视觉增强仍按 [UI/UX API 证据](UI_UX_EVIDENCE_2026-10-02.md) 门控；本文业务能力不应依赖仅 API26 可用的调用。声明存在不保证特定设备支持，必须同时满足最低版本、系统能力、授权和实际分发条件。

## 9. 本次交付边界

本次完成两端源码静态复核、上游最新基线复查、鸿蒙 API 可行路径与分批方案；交付为本文和 README 索引。**没有改动应用代码、执行新的功能实现、使用真实账号调用写接口或做设备实测**，也不把上一轮的 HAP 构建成功当成本次 32 项差距已经消除。

实施时优先引用本报告固定 SHA 的行为证据；若上游或服务协议变化，先更新该项差异与样例，再调整实现。达到“非注入功能对齐”需要逐项记录：已等价完成、采用明确平台替代、外部依赖阻塞或经用户决定不做，不能由页面数量或一次编译结果替代。
