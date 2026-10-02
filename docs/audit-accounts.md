# 账号、服务与设置差距审计（2026-10-02）

基线：当前 `upstream`（DGP-Studio 原版）和 `upstream-remastered` 的源码；用户本轮“API 24+、除注入外全量移植”覆盖旧 AGENTS.md 的“仅国服 / 不移植云功能”范围限制。以下状态为实施前静态审计；没有读取或使用真实账号凭据。

## 已实现与缺口

| 范围 | Harmony 当前情况 | Windows 依据 / 缺口 |
|---|---|---|
| 米游社登录 | LoginPage 支持二维码、短信、网页与手动 Cookie | Remastered `ViewModel/User/UserViewModel.cs:155-297` 另有 HoYoLAB 手动、密码、第三方登录；Harmony 没有服务器选择 |
| 海外账号模型 | `model/User.ets:8-30` 没有账号区域；`data/repo/UserRepo.ets:23` 恒写 is_oversea=0，69-78 不读取 | 必须持久化账号区域，去重须包含区域；不能让同号海外账号覆盖国服 |
| UID 区域 | `common/Constants.ets:118-132` 除 5 开头均 cn_gf01，isCnUid 接受 1-9 | 对照上游 `Web/Hoyolab/PlayerUid.cs` / `Region.cs` 支持美/欧/亚/港澳台；须同步 10 位 UID 规则 |
| 海外 HTTP | `HoyolabClient.ets:85-220` 和多处业务服务硬编码国内主机、盐值、签到 act_id | 上游 `ApiEndpoints.csv:9-10,47-61,81-84` 提供独立海外端点；`PassportClientOversea.cs:26-61` 海外 Token 交换使用 POST STokenWrapper；`BindingClient.cs:26-43` 海外直接 Cookie 拉角色，国内走 action_ticket |
| Cookie 隔离 | `ApiClient.ets:30-38` 对任何 URL 默认附带全量当前 Cookie；`pages/SettingPage.ets:194` 使用此客户端访问 GitHub | P0：移除无限制自动注入，按 HTTPS 精确域名和账号区域限定，显式 Cookie 也不允许发往第三方；公有数据客户端不得携带账号凭据 |
| 日志敏感信息 | `ApiClient.ets:97,106` 记录完整 URL；`HoyolabClient.ets:199-210` URL 含 stoken / action ticket | P0：统一去除 URL 查询参数、片段和 userinfo，禁止响应错误文本回显令牌 |
| 胡桃通行证 | 无页面 / 服务 / Token 仓储 | Remastered `Web/Hutao/HutaoPassportClient.cs:37-248` 包含验证邮件、注册、注销、改邮箱、重置密码、登录、UserInfo、刷新和吊销 Token；RSA OAEP-SHA1，与米哈游 RSA 协议不可混用 |
| 胡桃云祈愿 | 无 | `Web/Hutao/GachaLog/HomaGachaLogClient.cs:24-123`：Entries、EndIds、Retrieve、Upload、Delete、当期统计及分布；需要独立 Bearer Token，按 UID 增量同步，删除须明确交互确认 |
| 云统计 | 无胡桃深渊 / 幻想真境统计 | `Web/Endpoint/Hutao/IHomaSpiralAbyssEndpoints.cs:8-50` 与 `IHomaRoleCombatEndpoints.cs:8-15`：记录上传/检查/排名、持有率/使用率/搭配/队伍统计；须明确用户触发上传 |
| 云攻略 / 壁纸 | `HutaoDailyImageService` 已有公开每日壁纸，旧范围声明并不反映实际实现 | `IInfrastructureStrategyEndpoints.cs:10-17`：全角色 / 单角色攻略；壁纸收藏/多来源与 Windows 设置仍须逐项核对 |
| 反馈 | 无反馈页面 | `ViewModel/Feedback/FeedbackViewModel.cs:51-123`：文档搜索、IP 信息、诊断信息、打开反馈渠道；Windows Loopback 例外须转鸿蒙可用诊断，不可伪造实现 |
| 全量备份 | 仅账号/祈愿/成就及少数偏好，明文 JSON 包含 Cookie | `BackupService.ets:86-94,181-190` 漏养成计划、挑战缓存、首页布局、自动签到等；`restoreFromText:209-227` 未校验版本/schema 即删除原数据，且 275 行遍历未填充 bu.roles，默认 UID 丢失 |
| 设置 | 已有主题、背景、首页排列、自动签到、资源更新、极验、备份、祈愿删除 | Remastered SettingGachaLogViewModel:37-38 提供 UIGF 2.2—4.2；SettingStorageViewModel:80-146 有缓存重置；SettingAppearanceViewModel 有语言、背景视频；SettingHotKeyViewModel 为桌面键盘；应逐项映射到鸿蒙设备能力 |

## 分阶段实施计划

1. **P0 凭据与数据完整性**：ApiClient 域隔离及查询日志脱敏；TokenVault 写失败显式失败；备份预检 schema/version、事务恢复、完整偏好与业务数据（备份由主代理实施）。对普通域、后缀伪造、URL userinfo、HTTP、大小写 Cookie 做单元验证。
2. **P1 国服 / 海外基础协议**：User.isOversea 保存读取 / 备份；完整 v2 Cookie 字段和 clone；RegionUtil 采用上游 UID 规则；独立 HoyolabEndpoints；手动 / 官方 Web 登录增加地区选择，海外 Cookie Token 链用上游 POST，角色用 Cookie；国服现有风控重放保持。
3. **P2 海外业务闭环**：便笺、角色、深渊、幻想真境、幽境、日历、札记、签到、祈愿分别接入海外端点/盐/请求体；国内特有补签和风控接口不向海外盲发。凭据缺失时可做请求构造和 fixture 验证，在线成功仍需设备上的真实登录验收。
4. **P3 独立胡桃云模块**：HutaoResponse / RSA OAEP-SHA1 / Bearer Token 安全仓储 / 会话刷新；通行证 UI；云祈愿增量同步；统计、攻略、反馈与导航。不与米哈游 ApiClient.currentCookie 共享凭据。
5. **P4 设置与设备验收**：备份还原、缓存重置、诊断反馈、快捷键与背景媒体等映射；API 24/25/26 三档，手机/平板/二合一；SDK 编译和模拟器截图，不能将仅静态检查宣称装机通过。

## 服务与凭据边界

- 公开源码足以实现请求协议，但不能证明远端生产端点当前开放或允许新的客户端。云通行证注册/登录、验证码、订阅/兑换状态须依赖真实服务，不能虚构成功状态。
- 米哈游登录/第三方授权/风控须用户在应用内完成。无需把真实 Cookie 提供给开发代理；不得在测试 fixture、日志、文档、Git 中保存令牌。
- Remastered 使用 `Web/ServerDomain.cs` 选择 Homa/API 域；原版与 Remastered 账户/服务可能不互通，必须显式选择服务来源，不把凭据自动发送到另一个发行方。
- 鸿蒙本地开发 skill 目录 `harmony/skills/` 在此次仓库克隆中缺失；遵循项目显式 ArkTS 约束，使用已安装 SDK/检查器可验证部分，并记录实际构建边界。
