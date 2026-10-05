# F12 — 离线祈愿 UP 历史与倒计时

## 范围

新增 `pages/WishHistoryPage`（支持 `embedMode`）。它从已选择的本地游戏数据读取卡池、角色和武器元数据，无需登录、UID、抽卡档案、云统计或在线请求。它描述物品的 UP 历史，不推算未来复刻。

功能：五星角色、四星角色、五星武器、四星武器四个分类；按名称或 ID 搜索；按最近 UP **结束时间**从旧到新排序（相同时间按 ID 稳定排序）；选择物品后查看逐期卡池、版本、上/下半、起止日期与原始池类型。未知物品保留 `#ID`，不制造名称、图标或可用的图鉴详情。

## 上游依据

只读核对 `SnapHutaoRemasteringProject/Snap.Hutao.Remastered` 的提交 `3f0d1f363a8226cccd76f0f66f599e729b0f214c`，不是 DGP-Studio 默认分支。

- [GachaLogWishCountdownService.cs](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/GachaLog/GachaLogWishCountdownService.cs)，blob `7ebeef1ebf2ffa595245518f0ef183e0d3004f7f`：忽略尚未开始的期次，按角色/武器、橙/紫 UP 列表分组
- [Countdown.cs](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/GachaLog/Countdown.cs)，blob `7efae5e21e627469a0e2e99b438fe520adebcfd7`：使用最近期次的 `LastTime`，天数向零截断
- [CountdownHistory.cs](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/GachaLog/CountdownHistory.cs)，blob `60f656537ecb8f4970b4129e5b3e4d4e483e3d03`：`LastTime = gachaEvent.To`
- [AvatarIds.cs](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/Metadata/Avatar/AvatarIds.cs)，blob `e58e72ad6370e7d768ad6c94afd4661bb92a897e`：角色排除名单
- [WeaponIds.cs](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Model/Metadata/Weapon/WeaponIds.cs)，blob `93684deb1c4f3ab0eb1e19b6dd943a6e1f526aa7`：五星武器排除名单；四星武器仍纳入

排除角色：`10000003, 10000016, 10000041, 10000042, 10000035, 10000069, 10000079, 10000109, 10000006, 10000021, 10000015, 10000062`。

排除橙色 UP 武器：`11501, 11502, 12501, 12502, 13502, 13505, 14501, 14502, 15501, 15502, 15515, 15518`。

## 边界与明确适配

- 事件从开始时刻起计入；`now >= to` 视为结束。忽略非有限、零、逆序或越界时间，忽略非五位武器/八位角色整数 ID
- 历史按开始时间倒序，保留最近期次结束时间作为 `LastTime`；列表按 `LastTime` 升序，稳定 ID 次序
- 同一物品在相同 `from/to` 的多个卡池合为一次 UP，但详情保留所有不同池类型、名称、版本和期次；重复元数据行也去重
- Windows 的整数天语义保留；不足一天明确显示“剩余不足 1 天”或“结束不足 1 天”，不会把刚结束的卡池误标为正在 UP
- 重叠期次中仍有有效进行中的卡池时，以进行中的结束时间显示剩余天数；历史 `LastTime` 仍保持 Windows 口径
- 日期固定东八区，不因设备时区或夏令时跨日；该页面没有账号地区，也不暗示国际服时间
- 顶部显示实际本地已开始卡池覆盖范围和忽略项数量。空数据与读取失败给出明确状态，未知名称标为 `#ID`
- 复用 `WikiMetaService` 缓存，不改共享加载器。该加载器将底层读取失败折叠为空数组，因此页面准确描述“为空或无法读取”，不能区分二者。游戏数据换代沿用应用已有下次启动生效约定

## 页面与生命周期

- 内容区宽度 `>=840vp` 为列表/详情双栏；窄屏为列表与详情切换
- 两个列表均使用 `LazyForEach`；原生按钮/搜索/分类触控高度至少 44vp，使用主题资源色与悬停反馈
- 元数据读取按请求序号归属，过期请求的结果、异常和 `finally` 不能覆盖新请求；隐藏/分离页面使旧请求失效
- 每分钟仅在页面可见且无读操作时重新按当前时间投影本地数据；离开后清除定时器，重复挂载不叠加定时器
- 图鉴动作仅限存在于本地元数据中的物品，向 `WikiAvatarPage` 或 `WikiWeaponPage` 传递 `WishHistoryWikiParams { itemId }`。两页已实现参数消费与整数/类型范围校验；未知 ID 显示不可用提示和普通列表，内嵌模式不读取路由。导航壳与路由注册由主集成变更提供，需同批验证

## 验证

`node tests/wish-history.cjs`：15 项通过。测试真实生产规则、ViewModel、页面生命周期方法；仅替换 ArkUI、路由和本地元数据读取边界。包含：

- 四组及全部上游排除 ID；四星武器保留
- 开始/结束瞬间、完整天数、不足一天、重叠期次及固定时区
- 无效/未来事件和 ID、未知物品、名称/ID 搜索与稳定排序
- 双池同时间去重、不同时间不合并、重复行不重复计数
- 包内真实 292 期元数据与独立去重集合逐物品比对
- 加载竞态、取消/隐藏/重新挂载、失效异常/最终状态、过滤器变化、读取失败重试、定时器归属与图鉴参数
- 生产模型/服务/VM 在显式类型边界下进行 strict TypeScript 检查

同一 15 项测试在 `TZ=Pacific/Honolulu` 和 `TZ=Asia/Shanghai` 下分别通过。主机测试不替代 ArkTS 编译、CodeLinter、签名 HAP 或真机/模拟器 UI 验证；原生构建与路由集成由最终聚合检查报告。

`node tests/wiki-route-ownership.cjs`：16 项通过。逐页执行真实路由、元数据加载与生命周期方法，覆盖有效/无参数/非法/未知 ID、窄宽布局、内嵌模式完全不读路由、新旧请求竞争、角色/武器和材料读取的晚成功/晚失败、分离后重新进入、二级资料晚返回以及保留养成编辑器。两页目的数据完全就绪后才统一发布；旧请求的 `finally` 不结束新请求的加载态。

另外重新执行 `tests/cultivation-planning.cjs`（16 项）和 `tests/costume-art-lifecycle.cjs`，均通过。首次聚合主机测试在并行变更中的 `tests/data-port.test.mjs` 停止，原因为新 `./UigfCodec` 依赖缺少 mock；稍后的重跑已通过该处，在并行修改中的 `tests/offline-gacha-access.cjs` 发现 UIGF fixture 的 ID 期望与实际值不一致。两次均不是本功能通过全量检查的证据，须在集成阶段补做。

## 文件

- `entry/src/main/ets/model/WishHistory.ets`
- `entry/src/main/ets/service/WishHistoryService.ets`
- `entry/src/main/ets/viewmodel/WishHistoryViewModel.ets`
- `entry/src/main/ets/pages/WishHistoryPage.ets`
- `entry/src/main/ets/pages/WikiAvatarPage.ets`（仅路由消费与读取归属）
- `entry/src/main/ets/pages/WikiWeaponPage.ets`（仅路由消费与读取归属）
- `tests/wish-history.cjs`
- `tests/wiki-route-ownership.cjs`
- `docs/WISH_HISTORY_OFFLINE_2026-10-05.md`
