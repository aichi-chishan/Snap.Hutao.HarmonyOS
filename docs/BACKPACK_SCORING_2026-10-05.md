# 背包圣遗物评分预设（F08）

状态：原生客户端与离线生产代码回归已实现；真实设备的交互、持久化与重启验收待做。F07 的无损 UIIF 档案不改变，F03/F04 与角色推荐评分代码不改。最低 API 24，目标 API 26。

## 固定上游

Windows 基线：`SnapHutaoRemasteringProject/Snap.Hutao.Remastered@3f0d1f363a8226cccd76f0f66f599e729b0f214c`。

- [ReliquaryScoreCalculator](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/AvatarInfo/Factory/ReliquaryScoreCalculator.cs)，blob `25488177ce2766e3ec142c3b4666b4b9af49dd2f`：背包原始百分比先乘 100，七项系数分别为 2、1、1.33、1.1979、0.33、1.33、1.06
- [BackpackReliquaryScoreConfig](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/Entity/BackpackReliquaryScoreConfig.cs)，blob `d8b793651efde272c6a5c31ee0c7235ca42484ee`：七个权重，固定生命/攻击/防御权重恒为零
- [BackpackService](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Backpack/BackpackService.cs)，blob `6c02f0e80eaabf8fb71a8606627c842fabc603fc`：默认、攻击、生命、防御、精通预设与活动配置
- [编辑对话框](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/BackpackReliquaryScoreConfigDialog.xaml)，blob `45003f8696867dcc0de580edbacab4e0d42b8e9e`：0–1、步长 0.1，保存/自定义/删除
- [BackpackReliquaryItemView](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Backpack/BackpackReliquaryItemView.cs)，blob `db0c5c28006602d1aed93343dab8936a36c1c5d2`：按附加词条 ID 找值，同属性的首项是初始条目，后续重复项是强化；值累加，次数为记录数减一
- [BackpackSortComparer](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Backpack/BackpackSortComparer.cs)，blob `1c4503d7b0c00e76a3a0ae8a190c8a63489d82a4`：评分排序；本次保留原有实例 ID 平局规则

词条参考来自 [Snap.Metadata/ReliquarySubAffix.json](https://github.com/SnapHutaoRemasteringProject/Snap.Metadata/blob/b3aef3dbe0299e512654bb296930b3b6571fc87f/Genshin/CHS/ReliquarySubAffix.json)，固定提交 `b3aef3dbe0299e512654bb296930b3b6571fc87f`、Git blob `c4e65e91229f84014003703837faddb668a4c3be`，350 个 ID。纯数值投影 `ReliquaryAffixReference.ets` 独立随包编译，不改变 17 文件热更新队列。可用 `python scripts/generate-reliquary-affix-reference.py /path/to/Snap.Metadata --check` 离线复核来源。

## 实现

- 五个内置预设、自定义命名、修改现有配置、另存新配置、删除已保存配置
- 默认权重顺序为暴击、暴伤、攻击%、充能、精通、生命%、防御%：`[1, 1, .2, .2, .2, 0, 0]`
- 攻击/生命/防御/精通预设保留双爆权重 1，将对应收益项设为 1，其他副收益权重归零。精通预设不会擅自清除双爆
- 所有档案共享活动配置；编辑器固定打开时的档案与请求代次，切档、重载、关闭页面或配置已被更新后，旧保存/删除不能生效
- `app.backpack.score_profiles.v1` 存有版本与修订号的本地非敏感设置；单次写入包含全部配置与活动 ID，复用现有 PreferencesStore；`app.*` 属于现有便携备份范围，无数据库迁移
- 删除活动配置回到内置默认；合法零分显示 `0.0`；未知词条或无副词条记录显示“评分不可用”，已识别部分仍可查看，但不伪装完整总分
- “圣遗物评分”排序将完整评分放前，未知置后，平局按物品与实例 ID；其他分类、关键字和锁定筛选保持可组合
- 原始 UIIF 文本、64 位标识、重复强化记录和材料库存都不写入评分派生值
- 原生页面展示已解析的副词条值与强化次数；本次未扩展主词条成长值与套装描述，也未宣称已覆盖 Windows 的多排序令牌 UI
- 损坏或未来版本的配置只回退显示默认并提示，保存/删除被阻止，原设置不静默覆盖

## 验证

命令：`NODE_PATH= TYPESCRIPT_PATH="$PWD/ci/node_modules/typescript/lib/typescript.js" node tests/backpack-scoring.cjs`

覆盖生产逻辑：五个预设、百分比/固定值单位、重复 ID 累计、全零权重、未知 ID、非有限/越界配置、保存/重载/删除活动预设、损坏配置保留、稳定评分排序与筛选、取消不保存、跨档/重载/退出/过期修订拦截、原始 UIIF 不变。F07 的 `tests/backpack.cjs` 与 `tests/backup-sqlite.cjs` 也通过，后者加入新纯模型依赖并继续严格类型检查。

Host 测试不等同于官方 ArkTS 构建或真实设备验收；完整原生构建由汇总检查统一执行。PreferencesStore 延续既有异步 flush 机制，设备低空间/进程终止的耐久性需要实机验证。
