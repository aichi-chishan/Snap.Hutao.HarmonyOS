# UI/UX 调研证据索引（2026-10-02）

配套：[研究结论](UI_UX_RESEARCH_2026-10-02.md) · [视觉与交互规格](UI_UX_SPEC_API24_PLUS.md)。

## 证据使用说明

- 本文源码链接固定到调研基线 SHA，不会随后续 PR 更新而漂移；每个锚点由本地文件中的实际标记定位。
- “已核对”指源码/声明/文档事实；“推断”指根据实现和规则识别的风险；“建议”是未实施的设计方案。
- 没有设备截图、帧率/功耗实测或用户测试。API 声明存在不能证明实际材质渲染成功。
- 华为站点部分页面为动态内容，网页读取出现空壳/超时；相关关键段落补用 DevEco CLI 官方文档包完整读取，没有用论坛或第三方文章代替 API 结论。

## 上游与版本

| 对象 | 链接/版本 |
|---|---|
| 本次鸿蒙代码基线 | [60197a9](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/commit/60197a970d66f38ea4f3211417ff96d745a1d918) |
| Windows 社区源码 | [3f0d1f3](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/commit/3f0d1f363a8226cccd76f0f66f599e729b0f214c) |
| 本轮重查的 latest release | [v1.20.3](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/releases/tag/v1.20.3)，发布时间 2026-09-22 17:19:44 UTC（北京时间 09-23） |
| 官方最终存档 | [e1e3b8d](https://github.com/DGP-Studio/SnapHutaoArchive/commit/e1e3b8d2e25d398443a0a0cc04d4017ec2729d19) |
| 工具链 | CLT 26.0.0.821 / SDK 26.0.0.105 / DevEco CLI 1.3.4；部署记录见 [BUILD_ENVIRONMENT](BUILD_ENVIRONMENT.md) |

## E01

**壳层、导航分组、返回和断点**

已核对：Windows 的菜单分组与账号 PaneFooter；当前鸿蒙 phoneShell 的四页签和 wideContent 的页面索引含义不同。代码推断：同一 currentIndex 跨断点复用存在错页风险；嵌入页销毁可能丢失局部状态，实际恢复程度还需逐页运行验证。Windows 标题返回绑定 Frame.CanGoBack；鸿蒙宽屏没有 router 深层页时返回主页。

- [Windows UI/Xaml/View/MainView.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/MainView.xaml#L77)
- [Windows UI/Xaml/View/MainView.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/MainView.xaml#L273)
- [鸿蒙 pages/Index.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/Index.ets#L462)
- [鸿蒙 pages/Index.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/Index.ets#L485)
- [鸿蒙 pages/Index.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/Index.ets#L808)
- [鸿蒙 pages/Index.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/Index.ets#L1569)

## E02

**祈愿记录的归档与命令组织**

已核对：Windows 有归档选择、获取方式、导入导出/云操作，以及总览、历史、角色、武器、倒计时、统计页签；UIGF 导入对话框显示文件元信息和 UID 选择。鸿蒙已有前五个页签，但 build 按 isLoggedIn 整体分支，loginGuide 只有登录操作。建议：把在线刷新权限与本地记录展示分开；写入影响预览是新增设计建议。

- [Windows UI/Xaml/View/Page/GachaLogPage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/GachaLogPage.xaml#L320)
- [Windows UI/Xaml/View/Dialog/UIGFImportDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/UIGFImportDialog.xaml#L1)
- [Windows UI/Xaml/View/Dialog/GachaLogRefreshProgressDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/GachaLogRefreshProgressDialog.xaml#L1)
- [鸿蒙 pages/GachaLogPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/GachaLogPage.ets#L738)
- [鸿蒙 pages/GachaLogPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/GachaLogPage.ets#L1486)
- [鸿蒙 pages/GachaLogPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/GachaLogPage.ets#L1796)

## E03

**成就分类、命令与导入策略**

已核对：Windows 提供档案管理、导入菜单、未完成优先、仅委托筛选与主从视图。鸿蒙当前已有 UIAF 状态/策略支持和虚拟列表，策略选择常驻 header；标题仍显示“成就”。不能再把这些已经落地的数据功能描述为缺失。

- [Windows UI/Xaml/View/Page/AchievementPage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/AchievementPage.xaml#L273)
- [Windows UI/Xaml/View/Dialog/AchievementImportDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/AchievementImportDialog.xaml#L1)
- [鸿蒙 pages/AchievementPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/AchievementPage.ets#L526)
- [鸿蒙 pages/AchievementPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/AchievementPage.ets#L502)
- [鸿蒙 model/AchievementData.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/model/AchievementData.ets#L1)

## E04

**养成计划、目标编辑与库存**

已核对：Windows 的材料清单、养成物品、材料统计、背包物品页签及目标编辑对话框。鸿蒙已能离线计算和维护项目库存；库存手动输入材料 ID。百科加入计划使用 Lv.1→90，计划数量影响直接添加或选择流程。建议统一目标编辑器，属于后续流程改造，不是本轮实现。

- [Windows UI/Xaml/View/Page/CultivationPage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/CultivationPage.xaml#L616)
- [Windows UI/Xaml/View/Dialog/CultivatePromotionDeltaDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/CultivatePromotionDeltaDialog.xaml#L1)
- [Windows UI/Xaml/View/Dialog/CultivatePromotionDeltaBatchDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/CultivatePromotionDeltaBatchDialog.xaml#L1)
- [鸿蒙 pages/CultivationPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/CultivationPage.ets#L652)
- [鸿蒙 pages/CultivationPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/CultivationPage.ets#L689)
- [鸿蒙 pages/WikiAvatarPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/WikiAvatarPage.ets#L340)
- [鸿蒙 pages/CharacterPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/CharacterPage.ets#L765)

## E05

**我的角色与三类百科**

已核对：Windows 的导出/养成命令、主从视图、角色/武器筛选；鸿蒙已有列表/网格、组合筛选、宽屏详情和目标选择。体型/所属/皮肤、技能映射等缺口已在实施记录中保留；本提案没有用虚构字段补 UI。

- [Windows UI/Xaml/View/Page/AvatarPropertyPage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/AvatarPropertyPage.xaml#L719)
- [Windows UI/Xaml/View/Page/WikiAvatarPage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/WikiAvatarPage.xaml#L1)
- [Windows ViewModel/Wiki/AvatarFilter.cs](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Wiki/AvatarFilter.cs#L1)
- [Windows ViewModel/Wiki/WeaponFilter.cs](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Wiki/WeaponFilter.cs#L1)
- [鸿蒙 pages/CharacterPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/CharacterPage.ets#L1)
- [鸿蒙 pages/WikiAvatarPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/WikiAvatarPage.ets#L135)
- [鸿蒙 pages/WikiWeaponPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/WikiWeaponPage.ets#L1)
- [鸿蒙 pages/WikiMonsterPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/WikiMonsterPage.ets#L1)

## E06

**深渊、剧诗、幽境的期数与统计**

已核对：Windows 的分期详情与本期统计页签、期数 SplitView，以及深渊/剧诗上传命令。鸿蒙已保存按账号/区域/期数归属的历史并显示期次 Chip；云统计在 HutaoCloudPage 通用列表展示。建议将统计按任务归回相应页面；缺少云上传/数据字段的部分不能仅靠 UI 完成。

- [Windows UI/Xaml/View/Page/SpiralAbyssRecordPage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/SpiralAbyssRecordPage.xaml#L329)
- [Windows UI/Xaml/View/Page/RoleCombatPage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/RoleCombatPage.xaml#L279)
- [Windows UI/Xaml/View/Page/HardChallengePage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/HardChallengePage.xaml#L134)
- [鸿蒙 pages/SpiralAbyssPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/SpiralAbyssPage.ets#L420)
- [鸿蒙 pages/RoleCombatPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/RoleCombatPage.ets#L603)
- [鸿蒙 pages/HardChallengePage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/HardChallengePage.ets#L392)
- [鸿蒙 pages/HutaoCloudPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/HutaoCloudPage.ets#L134)

## E07

**便笺、验证与提醒**

已核对：Windows 的刷新、角色验证、追踪与通知设置命令；鸿蒙已有多 UID 设置、系统通知/代理提醒与独立 Webhook。风险：用户需要区分数据采样成功、权限授权和提醒安排成功，不能从单一开关推断系统送达保证。验证浮层的改造必须保留任务等待和取消语义。

- [Windows UI/Xaml/View/Page/DailyNotePage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/DailyNotePage.xaml#L462)
- [Windows UI/Xaml/View/Dialog/DailyNoteNotificationDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/DailyNoteNotificationDialog.xaml#L1)
- [Windows UI/Xaml/View/Dialog/DailyNoteWebhookDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/DailyNoteWebhookDialog.xaml#L1)
- [鸿蒙 pages/DailyNotePage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/DailyNotePage.ets#L675)
- [鸿蒙 service/DailyNoteReminderService.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/service/DailyNoteReminderService.ets#L1)
- [鸿蒙 components/RiskVerifyModal.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/components/RiskVerifyModal.ets#L357)

## E08

**身份与通行证任务**

已核对：Windows 登录、注册、密码重置、邮箱更换/用户名重置和注销分别有对话框；鸿蒙 account() 同时放登录/注册/重置与多种验证码动作，登录后继续显示安全操作。米游社/HoYoLAB 与胡桃云在当前服务层已分离；本提案要求 UI 同样清晰，不能误称为凭据隔离尚未实现。

- [Windows UI/Xaml/View/UserView.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/UserView.xaml#L1)
- [Windows UI/Xaml/View/Dialog/HutaoPassportLoginDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/HutaoPassportLoginDialog.xaml#L1)
- [Windows UI/Xaml/View/Dialog/HutaoPassportRegisterDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/HutaoPassportRegisterDialog.xaml#L1)
- [Windows UI/Xaml/View/Dialog/HutaoPassportResetPasswordDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/HutaoPassportResetPasswordDialog.xaml#L1)
- [Windows UI/Xaml/View/Dialog/HutaoPassportResetUsernameDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/HutaoPassportResetUsernameDialog.xaml#L1)
- [Windows UI/Xaml/View/Dialog/HutaoPassportUnregisterDialog.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Dialog/HutaoPassportUnregisterDialog.xaml#L1)
- [鸿蒙 pages/LoginPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/LoginPage.ets#L331)
- [鸿蒙 pages/UserPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/UserPage.ets#L1)
- [鸿蒙 pages/HutaoCloudPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/HutaoCloudPage.ets#L37)

## E09

**设置、备份与反馈入口**

已核对：Windows 设置由分组卡片/展开器组织外观、背景、主页及数据等；鸿蒙 SettingPage 为长页，已有主题、背景、卡片、备份与诊断入口。本地 v2 备份和事务恢复是现有实现，新增建议集中在用户预览、结果和导航组织。

- [Windows UI/Xaml/View/Page/SettingPage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/SettingPage.xaml#L1)
- [Windows ViewModel/Setting/SettingAppearanceViewModel.cs](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ViewModel/Setting/SettingAppearanceViewModel.cs#L1)
- [鸿蒙 pages/SettingPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/SettingPage.ets#L697)
- [鸿蒙 service/BackupService.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/service/BackupService.ets#L1)
- [鸿蒙 service/SupportService.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/service/SupportService.ets#L1)

## E10

**当前材质门控与实际布局**

已核对：Motion.detectImmersive 只检测 API26；Index.panelMaterial 独立创建；HDS 的 systemMaterialEffect 使用同一 immersive 标记；sideNav 在普通 Scroll 上应用材质。推断：HDS API24 能力可能被过度关闭，普通侧栏材质可能因场景限制被忽略，视觉关闭偏好可能未覆盖所有表面。均需按官方规则和真机再确认实际表现。

- [鸿蒙 common/Motion.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/common/Motion.ets#L14)
- [鸿蒙 common/GuardedMaterialModifier.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/common/GuardedMaterialModifier.ets#L1)
- [鸿蒙 pages/Index.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/Index.ets#L94)
- [鸿蒙 pages/Index.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/Index.ets#L445)
- [鸿蒙 pages/Index.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/Index.ets#L667)
- [鸿蒙 components/RiskVerifyModal.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/components/RiskVerifyModal.ets#L19)
- [鸿蒙 pages/SettingPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/SettingPage.ets#L697)

## E11

**表面、颜色与静态对比度**

已核对：Windows 卡片使用主题资源和 Acrylic 样式；鸿蒙资源提供深浅色，PressCard 使用半径 40 的 backgroundEffect，壁纸单独 blur。对比度仅按实体资源色计算，不等于渲染截图测量。下面提供复算方法。

- [Windows UI/Xaml/Control/Theme/Card.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/Control/Theme/Card.xaml#L42)
- [Windows UI/Xaml/Control/Theme/Color.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/Control/Theme/Color.xaml#L1)
- [Windows UI/Xaml/Control/Theme/CornerRadius.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/Control/Theme/CornerRadius.xaml#L1)
- [鸿蒙 components/PressCard.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/components/PressCard.ets#L63)
- [鸿蒙 components/WallpaperLayer.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/components/WallpaperLayer.ets#L22)

## E12

**动效、键鼠和读屏覆盖**

已核对：Motion 提供 pageSwitch/riseIn/stagger；PressCard 另有按压动画，并记录点击不发光的设计。显式接口扫描不是可访问性评分，也不能替代系统默认语义的运行检查。建议在保留已有动效基础上补焦点、读屏和减少动态效果。

- [鸿蒙 common/Motion.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/common/Motion.ets#L46)
- [鸿蒙 components/PageContainer.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/components/PageContainer.ets#L1)
- [鸿蒙 components/PressCard.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/components/PressCard.ets#L37)
- [鸿蒙 components/AppBackButton.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/components/AppBackButton.ets#L1)
- [鸿蒙 components/BackgroundVideoLayer.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/components/BackgroundVideoLayer.ets#L1)

### 对比度复算

原始配色：[浅色资源](../entry/src/main/resources/base/element/color.json)、[深色资源](../entry/src/main/resources/dark/element/color.json)。判据参考 [W3C Understanding SC 1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)。本文将普通文字 4.5:1 作为项目目标，不宣称已完成 WCAG 审核。

可在任意 Python 3 环境运行以下独立计算；没有修改应用资源：

```python
def luminance(color):
    rgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
    return sum(v * w for v, w in zip(linear, (0.2126, 0.7152, 0.0722)))

for foreground, background in [
    ('#FFFFFF', '#FF6B35'), ('#FFFFFF', '#FF7A45'),
    ('#8A8A90', '#FFFFFF'), ('#8A8A90', '#F5F5F6'),
    ('#A9A9AF', '#1E1E23'),
]:
    low, high = sorted((luminance(foreground), luminance(background)))
    print(foreground, background, (high + 0.05) / (low + 0.05))
```

### 显式交互接口扫描

范围为基线 `entry/src/main/ets/**/*.ets`，按文本出现次数计数；含源码注释的文本匹配不是 AST 分析。实际结果：

| 文本 | 出现次数 | 文件数 |
|---|---:|---:|
| `.onClick(` | 224 | 35 |
| `.accessibilityText(` | 0 | 0 |
| `.focusable(` | 0 | 0 |
| `.keyboardShortcut(` | 0 | 0 |
| `backgroundEffect(` | 4 | 3 |
| `.blur(` | 1 | 1 |
| `.backgroundBlurStyle(` | 1 | 1 |
| `.systemMaterial(` | 1 | 1 |

最后一项集中在 AttributeModifier 中；不意味着只渲染了一个材质实例。相同组件可被多次实例化，API 次数不能直接换算 GPU 负载。

## E13

**官方视觉能力与兼容性证据**

| 资料 | 本轮核对内容 | 获取方式 |
|---|---|---|
| [HDS 沉浸光感](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ui-design-hds-component-material) | 6.1.0(23) 起；标题栏按钮/底栏；系统自适应；定制前查设备能力 | 网页索引 + CLI 全文 + SDK 声明 |
| [HdsTabs](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs) | FloatingStyle 的 systemMaterialEffect 与 API 起点 | 网页索引 + SDK 声明；网页正文读取超时 |
| [开启沉浸光感](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-immersive-light-sense-enable) | target API26、应用元数据、受支持组件范围、关闭语义 | 官方网页检索正文与 SDK |
| [沉浸光感常见问题](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-faq) | HDS/ArkUI 等级与厚薄不同，场景限制，模糊/背景遮盖问题 | CLI 全文，网页读取不完整 |
| [沉浸光感功耗优化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-constraints) | 控制面积、避免嵌套/重复模糊/动态背景采样 | CLI 全文，网页读取为空壳 |
| [沉浸光感简介](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sense-overview) | ArkUI 能力起于 API26 | 官方网页索引 + CLI 检索 |

本轮读取的 CLI document ID（以官方包内容为准，不把搜索摘要冒充全文）：

```text
开发指南/UI_Design_Kit_UI设计套件/沉浸光感/ui-design-hds-component-material
开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/沉浸光感/沉浸光感常见问题/arkts-immersive-light-sense-faq
开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/沉浸光感/沉浸光感功耗优化/arkts-immersive-light-sense-constraints
```

复查命令：`devecocli docs search '沉浸光感'`，再将上面的完整 document ID 作为 `devecocli docs read` 参数。CLI 文档可能更新，因此同时记录下方 SDK 文件摘要。

| SDK 文件（相对 SDK/default） | SHA256 |
|---|---|
| `openharmony/ets/api/@ohos.arkui.uiMaterial.d.ts` | `d609002869f80307090bc11803b91049e86ff301f46e472e72430d954a40fd30` |
| `hms/ets/api/@hms.hds.hdsMaterial.d.ets` | `d030d0b94a65843aba20fdedd1c0f895e959634e79401b375ca0b585ca270be8` |
| `hms/ets/api/@hms.hds.hdsBaseComponent.d.ets` | `d639864237167f06b69454dda91b7f37d993450bda30e1071e6a21aa414498b2` |

声明核对结果：

| 标识符 | 结论 |
|---|---|
| `hdsMaterial.MaterialType` / `MaterialLevel` | HDS API23；提供自适应选项，能力查询为 `getSystemMaterialTypes()` |
| `SystemMaterialParams` / `HdsTabsFloatingStyle.systemMaterialEffect` | HDS API23；不能统一按 ArkUI26 禁用 |
| `uiMaterial` / `ImmersiveMaterial` | API26；所有低版本访问需保护 |
| `isImmersiveMaterialSupported()` | 设备支持情况；有 API 不等于有材质效果 |
| `getGlobalMaterialLevel()` | 只读设备等级，不是应用可写的强制性能档位 |
| `getMaterialInfo()` | 应用配置来源于 module metadata，不是 GPU 渲染状态 |
| `ImmersiveStyle` | 材质厚薄选择；低算力设备不保证各样式有差别 |
| `ImmersiveOptions` | 有 `style/materialColor/colorInvert/applyShadow/interactive/lightEffect`；没有随意添加的“玻璃折射率”参数 |
| `Material.empty` | 关闭组件材质；`undefined` 不能被当作同义关闭 |
| `lightEffect: null` | 关闭光感交互反馈，可保留其他允许的材质表现 |

SDK 只用于核对，没有复制工具链或官方文档全文到仓库。

## E14

**首页、日历、启动与辅助页面**

已核对：首页使用 Windows 的活动、卡池、仪表板和公告层次；鸿蒙已保留七卡及共享顺序、服务器日期规则、原生入口配置和背景视频前后台处理。本次是布局/反馈优化提案，不重新宣称这些基础能力尚不存在。

- [Windows UI/Xaml/View/Page/AnnouncementPage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/AnnouncementPage.xaml#L163)
- [Windows UI/Xaml/View/Page/LaunchGamePage.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Page/LaunchGamePage.xaml#L1)
- [Windows UI/Xaml/View/Card/TravelersDiaryCard.xaml](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/UI/Xaml/View/Card/TravelersDiaryCard.xaml#L1)
- [鸿蒙 pages/Index.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/Index.ets#L1157)
- [鸿蒙 pages/LaunchGamePage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/LaunchGamePage.ets#L1)
- [鸿蒙 service/GameLauncherService.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/service/GameLauncherService.ets#L1)
- [鸿蒙 pages/CalendarPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/CalendarPage.ets#L1)
- [鸿蒙 pages/SignInPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/SignInPage.ets#L1)
- [鸿蒙 pages/LedgerPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/LedgerPage.ets#L1)
- [鸿蒙 pages/AnnouncementDetailPage.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/pages/AnnouncementDetailPage.ets#L1)
- [鸿蒙 components/BackgroundVideoLayer.ets](https://github.com/aichi-chishan/Snap.Hutao.HarmonyOS/blob/60197a970d66f38ea4f3211417ff96d745a1d918/entry/src/main/ets/components/BackgroundVideoLayer.ets#L1)

## 未作为结论依据的材料

搜索中出现的论坛个案和第三方“系统更新后材质失效”文章仅用于发现检索方向；API 结论最终采用官方指南、SDK 与项目源码。没有可用截图时，不把主观观感描述成已观察到的事实。字体大小、触控目标、动效时间、分组选择和性能预算是本次设计建议。

## 本轮文档检查

已核对 123 个本地/源码链接及证据锚点，其中 87 个为固定 SHA 的源码链接；源码路径、行号、18 个优化编号、24 个验收编号、表格列数与代码围栏检查通过，`git diff --check` 通过。文档之外只新增 README 的阅读入口；未改应用源码，没有为纯文档变更重新运行整包构建。此前构建/回归结论仍对应 60197a9，不能当作本提案已实施的证据。
