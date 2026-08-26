# UI 复原规划：Snap.Hutao.HarmonyOS 三端还原 Windows 版胡桃

**日期**: 2026-08-23
**目标**: 电脑/平板端基本复原 Windows 版界面（静态风格对齐，动态用鸿蒙 API）；手机端复原功能 + 布局优化。
**剔除**: 胡桃云（保底云统计/成就云/全球统计/通行证/反馈中心）、注入游戏（启动器/Overlay/Yae/文件解锁/插件管理）。

## 一、现状与差距（依据 example/ 截图）

- 当前鸿蒙版（电脑虚拟机主页.png）：**应用 tab 已在左侧竖排**（宽屏已生效），底部是鸿蒙系统任务栏（非应用 tab）。差距在**内容区**：主页只有简单入口列表，无横幅/卡池时间轴/卡片网格/壁纸；导航项多为"新窗口打开"占位，未在内容区渲染。
- Windows 版目标：
  - **主页**：顶部渐变横幅"旅行者，欢迎来到提瓦特大陆！" + 横排卡池时间轴卡 + 活动卡片网格 + 底部功能卡（保底/成就/签到）+ 游戏壁纸背景
  - **祈愿记录**：多列大卡（大数字抽数/星级/日期/五星均抽/最非最欧/角色头像网格带抽数）
  - **实时便笺**：左数据面板 + 右侧立绘背景
- 结论：宽屏侧边栏已对，重点做**内容区接通**与**主页复原**。

## 二、范围

- **P0 宽屏内容区接通**：签到/日历/公告/账号/设置在内容区直接渲染（embedMode，隐藏返回按钮），去掉全屏跳转占位
- **P0 主页复原**：HeroBanner（渐变+胡桃图+欢迎语）+ 卡池时间轴（横向滚动）+ 活动网格 + 快查卡（保底/便笺/签到）+ 壁纸层
- **P1 祈愿池卡增强**（多列/头像占位格/日期范围增强）、设置页分组化
- **P2 手机端布局检查**（双列/单列）、图鉴骨架（可选）

## 三、技术方案（鸿蒙 API）

- 宽屏判定：`display.getDefaultDisplaySync()` 宽度 vp >= 720（aboutToAppear 立即检测，避免首帧闪窄屏）
- `Index.ets`：宽屏 Row{SideNav + Content}；窄屏 HdsTabs 底部
- 各 @Entry 页面加 `@Prop embedMode: boolean = false`；embedMode 隐藏返回按钮与状态栏避让（内容区统一处理），手机端照常 pushUrl
- 主页组件：HomeHeroBanner / GachaTimelineCard / ActCalendarCard / HomeQuickTile / WallpaperLayer（渐变+本地胡桃图+可选模糊/流光）
- 动态：QTapButton（hdsEffect+spring）、animateTo 导航切换、edgeEffect(Spring) 滚动、Grid 入场动画
- 素材：全部本地/占位（角色头像用"首字+星级色"占位），无云依赖

## 四、里程碑（每步 build 验证）

- M1 骨架：isWide 立即检测 + wideContent 内嵌接通 8 页面
- M2 主页复原：HeroBanner + 卡池时间轴 + 活动网格 + 快查卡 + 壁纸层
- M3 页面细节：设置分组化、祈愿多列增强、便笺色块
- M4 动态适配：QTapButton 替换关键位、入场动画、手机端布局检查
- M5 收尾：深浅色复核、构建部署、截图比对

## 五、验证

每里程碑 arkts_check + build；部署 Pura 90 Pro（手机）与宽屏模拟器核对；对照 example/*.png 逐屏比对。
