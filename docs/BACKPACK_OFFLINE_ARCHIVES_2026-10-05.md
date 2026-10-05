# F07：非注入背包档案（2026-10-05）

本次补齐离线数据消费路径，不包含游戏进程读取、Embedded Yae、注入或在线全背包查询。API 24 最低版本和 API 26 目标不变。圣遗物评分预设 F08 另行实现，本页不把未知词条或未计算评分显示成 0 分。

## 已实现的本地闭环

- 显式输入名称与 9/10 位 UID 创建独立档案；不要求登录、不从当前账号暗中推断 UID；同一 UID 可建立多个时间快照
- UIIF 导入先校验整个文件，再确认目标名称/UID、四类条目数量和替换范围；文件若有 UID 扩展必须匹配目标档案
- 保存武器、圣遗物、材料和摆设；装备实例不能以 itemId 去重；相同武器/圣遗物仍为独立记录
- 事务替换、手动新增、材料/摆设数量编辑、单实例移除、档案删除和材料本地分类
- 九类筛选、未知分类、名称/物品 ID/实例 ID 搜索、仅已知锁定筛选，以及 ID/名称/品质/等级/数量排序
- 按 840vp 内容宽度切换列表—详情双栏和手机详情半模态；列表 LazyForEach，不全量渲染；深浅资源色、鼠标悬停、禁用重复动作和可读进度提示
- 显式选择养成项目，确认“合并”或“替换”后同步材料数量；0 为已确认数量，缺失仍为未知；装备与摆设不计作材料
- SQLite v7 档案/条目表；应用备份包含完整原始数据、UID 归属、实例 ID 和本地分类；旧格式备份还原保留原本不存在于其格式中的背包数据

普通 UIIF 没有标准 UID、GUID、锁定和标记字段。缺失时显示“文件未提供/未知”。本地实例 ID 只标识应用数据库中的记录，不伪装成游戏 GUID，也不添加为虚构的标准字段。UIIF 再导入会重新建立无 GUID 的本地实例；应用完整备份保存原实例标识。

## 格式依据与安全约束

依据是 [Windows 社区维护版 UIIF 模型目录](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/tree/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/InterChange/Inventory)。未找到独立权威 UIIF JSON Schema，不能称为“官方 UIGF UIIF schema 校验通过”。这里实现的是固定上游的 Windows UIIF v1.0 兼容契约，另加本地防损坏预检。

支持：

- info.uiif_version 必须为 v1.0；可选、可为 null 的 export_app、export_app_version 和有符号 Int64 export_timestamp
- list[].itemId 与 material.count / furniture.count
- equip.weapon.level、promoteLevel，以及可选/null 的 affixMap
- equip.reliquary.level、mainPropId、appendPropIdList，保留重复的强化记录 ID
- Windows 配置接受的整数数字字符串；未知字段原样保留；未激活的 material/equip/furniture 或 weapon/reliquary 分支允许 null
- 若存在十进制 uint64 guid 扩展，直接从原 JSON 文本提取并作为字符串身份；isLocked/isMarked 布尔扩展在物品层或 equip 层均可读取；冲突值拒绝

额外安全规则：

- 每项恰有一种有效物品分支，装备恰有一种装备分支；ID 必须正整数，数量必须 0…4294967295；必要等级/词条字段缺失时拒绝，不补造数据
- 16 MiB 文件上限、50000 条目上限、64 层嵌套上限；拒绝重复 JSON 键、重复 GUID、同类重复堆叠物品 ID、非整数、超界值和相互冲突的 UID 扩展
- 导入为整个档案的显式快照替换。没有稳定装备实例 ID 的文件不尝试“智能合并”，避免静默丢失重复装备
- 先完成全部验证，再单个同步事务写入；任一批次写入或提交失败全部回滚；材料同步在事务中再次检查档案和项目存在
- 未知对象/数组以及超过 JavaScript 安全整数范围的扩展数字以原始 JSON 切片保存。不会 JSON.parse 后再整体 stringify 导致 uint64 尾数丢失
- 再导出保留原 info 和未知字段，因此时间/来源描述仍是原快照的信息；手动新增档案只写必要的 UIIF v1.0 info，不伪造游戏采集时间
- 本地分类是应用侧状态，随完整备份保存，不冒充 UIIF 标准字段；UIIF 导入后重新按参考元数据分类

等级依据：[IdentityStructs.json](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/IdentityStructs.json)。圣遗物原始 level 1 表示 +0，21 表示 +20；武器精炼索引 0 表示 1 阶，4 表示 5 阶。上游转换器只限制 uint 存储，导入不会擅自丢弃未来数值；展示原始值或原始词条 ID，不推测缺失的词条数值。

## 离线参考元数据与归属

来源：[Snap.Metadata@b3aef3dbe0299e512654bb296930b3b6571fc87f](https://github.com/SnapHutaoRemasteringProject/Snap.Metadata/tree/b3aef3dbe0299e512654bb296930b3b6571fc87f/Genshin/CHS)（2026-09-24）。投影仅保留显示/分类必要字段：

- Material.json：7210 个 ID，MaterialType/Name/Icon/RankLevel
- Reliquary.json：890 组，展开 4320 个唯一 ID，Name/Icon/RankLevel
- Furniture.json：2319 个 ID，Name/ItemIcon 或 Icon/RankLevel；168 个空图标保留为空

合并文件：rawfile/backpack/reference.json，1265694 字节，SHA-256 4173427e185ee984008e119d17710facf7fac05510c8848ae28f182f4055d8b3。上游 MIT LICENSE 原文保存在同目录 LICENSE.txt，Copyright (c) 2022 DGP Studio。

这是应用随包参考数据，直接由 resourceManager 读取；**不属于远程游戏数据更新器的 17 文件 cohort，也未改变其生产者/清单契约**。武器名称沿用现有 WikiMetaService。未匹配 ID 保留原始内容并显示 #ID；材料分类按[固定 Windows 规则](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/Entity/BackpackItemCategoryExtension.cs)，包括上游明确的 ID 区间规则。没有类型映射且不匹配该规则时显示“未分类”。

图片使用已有随包资源，remoteFallback=false；未随包提供的家具/新物品图标显示统一占位，不阻止名称、数量、原始数据的离线访问。没有把文字可用误称为全量图片已下载。

## 验证

执行：NODE_PATH= TYPESCRIPT_PATH="$PWD/ci/node_modules/typescript" node tests/backpack.cjs

生产模型、codec、分类、repo、service 和 viewmodel 在真实 SQLite 上测试：四分支、同 ID 双装备、可空/省略字段、数字字符串、精确 uint64/未知字段往返、畸形/重复/超界输入、64 层与文件/条目边界、九类规则、筛选稳定排序、显式 UID/档案隔离、预检无写入、事务失败回滚、手工装备身份、数量编辑保留扩展、单实例移除、项目合并/替换、离线重读与销毁后的迟到读取。

备份另见 tests/backup-sqlite.cjs：生产 v7 迁移、外键、DDL/写入/提交失败回滚、新备份往返、schema 1–6 与旧版格式保留新背包数据、未知表/坏数据/孤儿关系预检、纯模型严格类型检查。

这些 host 测试不替代 HarmonyOS 编译或设备运行。当前文档不宣称已完成设备上的文件选择、权限失效、横竖屏/窗口缩放、连续取消、手势返回、读屏或大档案性能验收。原生编译、完整 lint 与 HAP 证据由最终集成检查单独记录；已知 SDK lint 内部异常仍应 fail-closed。
