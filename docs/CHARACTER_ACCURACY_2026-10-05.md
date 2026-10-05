# 角色技能与武器状态精度（F03 / F04）

状态：客户端逻辑与离线夹具验证已实现；真实账号、真实设备验收另行进行。最低 API 24、目标 API 26 不变。旅行者及未知技能库保持未知，不能据此声明所有元素变体已齐全。

## 固定依据与数据边界

- Windows 对齐对象为社区维护版 `SnapHutaoRemasteringProject/Snap.Hutao.Remastered@3f0d1f363a8226cccd76f0f66f599e729b0f214c`
- [SummaryAvatarFactory](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/AvatarInfo/Factory/SummaryAvatarFactory.cs)：按技能 ID、命座 ExtraLevel 关联，达达利亚 GroupId 3323 的普通攻击 +1，使用武器实际 PromoteLevel
- [AvatarViewBuilderSkillExtension](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/AvatarInfo/Factory/Builder/AvatarViewBuilderSkillExtension.cs)：战绩详情 level 已含额外等级，基础等级必须减去已知加成，不能再次叠加
- [GroupCalculable](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hoyolab/Takumi/Event/Calculate/GroupCalculable.cs)：计算器响应的 `group_id` 转为升级请求的 `id`，与战绩 `skill_id` 分开
- [SkillDepot](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/Metadata/Avatar/SkillDepot.cs)：可升级技能使用 `Proud.Parameters.Count > 1`，跳过额外冲刺/跳跃后再合入 EnergySkill
- 独立参考表来自 [Snap.Metadata](https://github.com/SnapHutaoRemasteringProject/Snap.Metadata/tree/b3aef3dbe0299e512654bb296930b3b6571fc87f/Genshin/CHS/Avatar) 的 118 个角色文件；`tests/fixtures/character-skill-reference.json` 固定每个源文件的 Git blob SHA、投影字段、元数据与 Windows 提交
- `AvatarSkillReference.ets` 是随应用编译的有限参考，不属于 17 文件在线元数据队列。本次没有改变队列 schema、替换其生成物或放宽更新校验
- 未验证到旅行者完整技能库文件或 SkillDepot ID 映射。10000005/10000007、未知角色、显式未知 skill_depot_id 均不猜测 A/E/Q 身份；新版本需要有来源地扩充参考表
- 可使用 `python scripts/generate-character-skill-reference.py /path/to/Snap.Metadata --check` 对本地固定提交逐文件验证投影与 ArkTS。脚本不联网、不接受不同 HEAD、不读取工作树中可能被修改的元数据

## 实现语义

1. `SkillLevelService.resolve` 按真实 skillId 对齐。乱序、多余冲刺项不会改变映射；重复 ID、缺失或无效等级保持未知
2. `ResolvedAvatarSkill` 分别保留 displayLevel、baseLevel、extraLevel，未知为 -1。命座按元数据 ID 和明确激活标志或已知命座数解析，不按返回数组位置。冲突或未知命座信息不伪造基础等级
3. 页面与文本使用同一格式：例如 `Q Lv.8+3`；无法可靠拆分时显示 `Lv.11（基础/加成未知）`。导出明确标记未知命座、未知映射、未知突破，以及“未装备”和“装备信息未知”的区别
4. 旧压缩元数据把欧洛伦、茜特菈莉的特殊跳跃当 A，导致后续标签错位。展示行通过同一角色的精确名称/图标连接独立参考，使用参考中的类型；不再信任旧位置标签
5. `PromoteState` 只接受明确 0–6 整数，并核验阶段与等级区间及低星上限。20/40/50/60/70/80 两侧状态都可以准确保留。缺失、空串、null、布尔、越界或矛盾值为未知；不会单凭等级推定突破
6. `CalculateService.fillSyncedDetails` 使用计算器明确的 `group_id` 与基础等级，提交 delta 的 `id=group_id`；战绩 `skill_id` 不能当作计算器 ID。武器缺准确突破时，请求同 UID 的新角色详情，严格核对角色 ID、武器 ID、当前等级和阶段，绝不使用旧详情缓存补值。任何部分失败不修改传入 delta
7. 若新详情仍缺值或已换武器，提示在草稿中手动确认本次突破；手动值属于计划输入，不写回在线原始数据

## 验证与限制

- `NODE_PATH= TYPESCRIPT_PATH="$PWD/ci/node_modules/typescript/lib/typescript.js" node --test tests/character-accuracy.cjs tests/character-cache.test.mjs`
- 生产解析器、技能解析、导出与计算器逻辑在网络/系统边界 mock 下执行，覆盖 118 角色参考、乱序/额外技能、C3/C5 普攻/战技/爆发变体、达达利亚、未知与冲突命座、旅行者/未知库拒绝、全部突破边界、低星上限、换武器/等级变化、原子失败保护
- `scripts/test-challenge-regressions.cjs` 在本次修改后通过
- Host 测试不替代官方 ArkTS 编译、真实账号协议或设备 UI 验收；完整构建由汇总流程统一运行
