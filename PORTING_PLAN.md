# Windows 版对齐移植方案（源码分析结论）

> 依据：Windows 版 Snap.Hutao（DGP-Studio/Snap.Hutao）源码分析 + 鸿蒙项目现状排查。
> 排除项不变：胡桃云功能服务（通行证/云备份/云统计/云攻略/云壁纸 API）与注入类功能不移植。

---

## 一、侧边导航对齐（Index.ets sideNav）

Windows 版 MainView.xaml 真实分组（中文文案取自 SH.resx）：

| 组 | 导航项 | 图标(Resource/Navigation) | 鸿蒙现状 | 动作 |
|---|---|---|---|---|
| 置顶（无组头） | 主页 | **Announcement.png（彩色 PNG）** | 用了 LaunchGame 图标 | **换 nav_Announcement 图标**，保持普通样式（Windows 主页项与其他项同构，仅置顶） |
| 置顶 | 胡桃通行证/反馈中心/插件管理 | — | 无 | 不移植（云/注入） |
| 工具 | 启动游戏 | LaunchGame.png | 无 | 不移植（进程/注入链） |
| 工具 | 祈愿记录 | GachaLog.png | ✓ 工具组 | 保留 |
| 工具 | **成就管理** | Achievement.png | "成就"在数据组 | **移到工具组，改名"成就管理"** |
| 工具 | 实时便笺 | DailyNote.png | ✓ 工具组 | 保留 |
| 工具 | 我的角色 | AvatarProperty.png | ✓ 工具组 | 保留 |
| 工具 | 背包物品 | Backpack.png | 无 | 不移植（Yae 内存读取） |
| 工具 | 养成计划 | Cultivation.png | 数据组 | **移到工具组** |
| 周期 | 深境螺旋 | SpiralAbyss.png | ✓ | 保留 |
| 周期 | **幻想真境剧诗** | RoleCombat.png | "幻象真境剧诗"（错字） | **改名"幻想真境剧诗"**（页面标题同步） |
| 周期 | 幽境危战 | HardChallenge.png | ✓ | 保留 |
| 数据 | **角色资料** | WikiAvatar.png | 在"图鉴"组 | **移入数据组，页面改名"角色资料"** |
| 数据 | **武器资料** | WikiWeapon.png | 在"图鉴"组 | **移入数据组，页面改名"武器资料"** |
| 数据 | **怪物资料** | WikiMonster.png | 在"图鉴"组 | **移入数据组，页面改名"怪物资料"** |
| — | 每日签到/活动日历/游戏公告 | — | 在数据组 | **从导航移除，融合进主页**（页面保留，由主页卡进入）；我的页入口保留 |
| 底部 | 用户区（UserView 头像） | — | 设置/账号在组内 | 可选：账号项沉底模拟 PaneFooter |

目标结构（鸿蒙 sideNav）：
```
主页                    (nav_Announcement)
──工具──
祈愿记录 (GachaLog)     成就管理 (Achievement)     实时便笺 (DailyNote)
我的角色 (AvatarProperty)  养成计划 (Cultivation)
──周期──
深境螺旋  幻想真境剧诗  幽境危战
──数据──
角色资料 (WikiAvatar)   武器资料 (WikiWeapon)   怪物资料 (WikiMonster)
──系统──
账号与数据  设置
```

选中态对齐：Windows 为左侧强调色圆角指示条 + 轻微背景高亮 → 鸿蒙 navItem 增加 4px 左侧圆角指示条（app_primary）+ app_primary_bg。

## 二、主页（homeTabWide）融合签到/日历/公告

Windows 主页纵向流（AnnouncementPage.xaml）：
1. 问候卡（"旅行者，欢迎来到提瓦特大陆！" + 兑换码按钮——兑换码属云，跳过）
2. 胡桃公告 InfoBar（云，跳过）
3. **活动日历区**（左=卡池列表[版本徽章+40×40物品图标+倒计时+起止时间]，右=活动卡片网格[签到状态/双倍/历练/历战/剧诗/幽战模板]）
4. **仪表板卡片**（UniformPanel minWidth=300、卡高 204、Acrylic+阴影）：启动游戏(跳过)→祈愿记录→成就管理→实时便笺→日历→签到
5. **游戏公告 Pivot**（3 页签：活动公告/游戏公告/系统公告；卡片=1080:390 横幅图+副标题+标题+时间角标）

鸿蒙动作：
- homeTabWide 重排：欢迎横幅 → 活动日历区（已有 HomeActCard 网格，补卡池横幅列=HomeGachaCard 已有可复用）→ 卡片区（祈愿/成就[新 HomeAchievementCard：完成度环形]/便笺/签到）→ 公告区（HomeAnnouncementCard 扩成三分类页签）
- 签到/日历/公告完整页面保留（router 可达），仅从导航移除
- 新增 HomeAchievementCard（读 AchievementService 统计）

## 三、深浅色修复（137 处硬编码排查结论）

已有完整清单（详见会话记录）。实施：
1. **新增资源色**（base/dark）：
   | 资源 | base | dark |
   |---|---|---|
   | mask_scrim | #33F1F3F5 | #33111113 |
   | nav_scrim | #33000000 | #66000000 |
   | nav_border | #22000000 | #22FFFFFF |
   | text_tertiary | #3A3A3A | #C8C8CD |
   | text_hint | #B0B0B6 | #7A7A80 |
   | ambient_gradient_start/mid/end | #FFF3E8/#F7E8DC/#FFFFFF | #14110D/#2A2118/#1C1C1E |
2. **高优先修复 13 处**：DailyNoteCard 小组件 11 处（整卡浅色写死，换 $r 资源）+ EntryAbility 状态栏图标色（按 isDarkMode 分支 #FFFFFF/#1A1A1A，主题切换时重调）+ Index 底栏遮罩
3. **中优先 13 处**：sideNav 蒙层/边框、弹窗按钮 8 处（$r danger/text_secondary/app_primary）、DailyNote 氛围渐变
4. 低优先 23 处（元素色映射/二维码黑白色等）保持不动

## 四、背景图选项（SettingPage 外观区 + WallpaperLayer 重构）

Windows 五选项及可移植性：
| 选项 | Windows 实现 | 结论 |
|---|---|---|
| 无背景图片 | 主题纯色底 | ✅ 移植（渐变/纯色） |
| 本地随机图片 | 用户目录递归扫描 8 种格式，随机取 1（短期不重复），5 分钟轮换 | ✅ 移植（DocumentViewPicker 选目录 + fs.listFile 递归 + Random） |
| 必应每日一图 | **胡桃云中转** api.snaphutaorp.org/wallpaper/bing | ⚠️ 云依赖；**等效替代**：直连 `https://cn.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1` 取 images[0].url（前缀 https://cn.bing.com），SHA1 文件名落盘缓存（对齐 Windows ImageCache 策略） |
| 胡桃每日一图 | 胡桃云 /wallpaper/today | ❌ 不移植 |
| 官方启动器壁纸 | 胡桃云 /wallpaper/hoyoplay（服务端选图） | ❌ 不移植（客户端无列表逻辑可复用） |

鸿蒙动作：PreferencesStore 新增 backgroundImageType('none'|'local'|'bing') + backgroundImagePath；WallpaperLayer 改造为：none=主题渐变 / local=file:// 随机图 / bing=必应图（http 拉取+cacheDir 缓存，当日同 URL 不重下）；设置页外观区加"背景图片"选择器+文件夹选择+版权信息（bing 返回 copyright 字段）。拉伸 ImageFit.Cover（=UniformToFill）；暗色模式按图片亮度调透明度（可选，先简化为固定遮罩）。

## 五、图片资源：替换 emoji 占位

**来源结论**：Windows 全部图标按 `https://api.snaphutaorp.org/static/raw/{Category}/{IconName}.png` 从胡桃云 CDN 取（Cloudflare，max-age=30 天），本地 SHA1 缓存。**米哈游官方源没有全品类按名取图规则**（仅角色侧脸 upload-bbs 可直取）。

**体量实测**：角色头像 118 张≈9MB；武器 246 张≈15MB；怪物 379 张≈19MB；技能+天赋≈6MB；材料 2640 张≈74MB；立绘/名片 300MB+。

**方案（推荐混合）**：
1. **打包进 rawfile**（用户已认可打包静态资源）：角色头像 + 武器 + 怪物 ≈ **43MB**（技能/材料量大，先运行时按需取）——写脚本从 CDN 批量下载到 `entry/src/main/resources/rawfile/icons/{AvatarIcon|EquipIcon|MonsterIcon}/`，NavIcon/Wiki 页 Image 优先 rawfile（`$rawfile('icons/AvatarIcon/UI_AvatarIcon_Ayaka.png')`），未打包类别回退 CDN+缓存。
2. 元数据 icon name 来源：现鸿蒙 Wiki 用 genshin.jmp.blue（slug 名），与 UI_AvatarIcon_* 名不一致 → 需引入 Snap.Metadata（gitcode/github 公开镜像）的角色/武器/怪物 JSON 提取 icon 字段（见第六节）。
3. 便笺/签到奖励、成就 Goal 图标（~100 张≈4MB）可一并打包（成就图标 UI_AchievementIcon_A001 系列）。

## 六、Wiki 三页功能对齐（阶段二大项）

Windows 结构：CommandBar(列表/网格切换+多条件搜索+加入养成计划) + SplitView 左列表右详情。
- 角色资料详情：简介(元素/武器类型/大头像/称号/生日/所属/命定座/四语CV)、养成材料、**属性基础数值曲线(等级滑条+突破+突破加成属性)**✅已实现、天赋三段+被动、命座 6、料理、语音表、故事 ✅全部已实现（立绘 FlipView/名片/攻略外链未做，属可选增强）
- 武器资料：抽卡头图、描述、属性曲线(90/70)、精炼 1-5、养成材料
- 怪物资料：描述、词缀、数值曲线(110 级)、**8 项抗性**、掉落物
- 数据源：Snap.Metadata 仓库 JSON（Avatar/Avatar.json 散装、Weapon.json、Monster.json、Curve/Promote 曲线表）

鸿蒙动作：从 Snap.Metadata 公开仓库（github.com/SnapHutaoRemasteringProject/Snap.Metadata 或 gitcode 镜像）提取并精简打包：Avatar 精简字段(icon/name/quality/vision/weapon/birth/cv/skills/talents/cultivationItems)、Weapon 全量、Monster 全量(含 SubHurts 抗性/Drops) + 曲线表 → rawfile/metadata/*.json（估 5-15MB）。Wiki 三页改读本地元数据，UI 按 SplitView 结构重写，图片走第五节方案。

## 七、实施顺序

1. 深浅色修复（独立、收益立竿见影）→ 2. 导航重构+改名+主页融合（纯 Index.ets 为主）→ 3. 背景图选项（WallpaperLayer+设置）→ 4. 图标批量下载打包+替换 emoji → 5. Wiki 元数据+页面重写（工作量最大，最后做）
