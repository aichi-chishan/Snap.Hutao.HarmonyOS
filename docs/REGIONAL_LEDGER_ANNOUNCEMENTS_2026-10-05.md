# F02：区域化旅行者札记与官方公告

日期：2026-10-05。本文记录公共基线重建后的客户端实现与离线请求契约验证，不代表国服/海外真实账号、服务可用性或设备界面已验收。API 24 最低版本与 API 26 目标不变。

## 固定协议依据

对齐 Windows 社区维护版提交 `3f0d1f363a8226cccd76f0f66f599e729b0f214c`：

- [ApiEndpoints.csv](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/ApiEndpoints.csv)
- [GameRecordClientOversea.GetLedgerAsync](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hoyolab/Takumi/GameRecord/GameRecordClientOversea.cs)
- [GameRecordClient.GetLedgerAsync](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hoyolab/Takumi/GameRecord/GameRecordClient.cs)
- [XRpc / XRpc3 headers](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Core/DependencyInjection/ServiceCollectionExtension.HttpClient.cs)
- [AnnouncementClient](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Web/Hoyolab/Hk4e/Common/Announcement/AnnouncementClient.cs)、[上游按区域/语言缓存并按 ann_id 联接正文](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/Announcement/AnnouncementService.cs)
- [15 个 UI 语言](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/SupportedCultures.cs) 与 [游戏语言代码映射](https://github.com/SnapHutaoRemasteringProject/Snap.Hutao.Remastered/blob/3f0d1f363a8226cccd76f0f66f599e729b0f214c/src/Snap.Hutao.Remastered/Snap.Hutao.Remastered/Service/LocaleNames.cs)

札记请求：

- 国服：`https://hk4e-api.mihoyo.com/event/ys_ledger/monthInfo`；month、bind_uid、bind_region、bbs_presentation_style=fullscreen、bbs_auth_required=true、utm_source=bbs、utm_medium=mys、utm_campaign=icon；Gen2/X4；CN headers 与 webstatic Referer
- 海外：`https://sg-hk4e-api.hoyolab.com/event/ysledgeros/month_info`；month、region、uid、lang=zh-cn；Gen2/OSX4；XRpc3 的 OS app version、client_type=5、device_id、language，不携带中国 Referer/device_fp
- Cookie 沿用上游 CookieType.Cookie 语义（gameRecordCookie）；没有 SToken 混入札记请求，没有跨区重试或 Cookie 回退

公告请求：

- 国服：`https://hk4e-ann-api.mihoyo.com/common/hk4e_cn/announcement/api/`
- 海外：`https://sg-hk4e-api.hoyoverse.com/common/hk4e_global/announcement/api/`
- getAnnList 与 getAnnContent 使用一致的区域、语言、game_biz/bundle_id。game=hk4e、platform=pc、公共 UID=100000000；默认 level=55 对齐上游，兼容现有调用方的 1–60 级参数
- getAnnContent 返回多个条目，不通过 ann_id 查询参数假设只有一条；必须选择与请求 ann_id 完全一致的正文
- 明确发送空 Cookie 头以阻止通用 ApiClient 在海外可信 API host 上自动注入登录会话；不发送 DS，不需要登录

## 所有权与请求生命周期

LedgerService 在签名前及每次 await 后验证原 User 对象、账号 ID、国内/海外属性、账号绑定的 UID 和 region。页面/首页卡片的 LedgerViewModel 另以请求 generation、所选账号/UID/月保护返回值；切换月份不会把晚到的上个月内容写入新月份，切换账号立即清除旧数字，页面销毁后不再更新。

每次认证或国服验证重试重新计算 DS。重试是有界的：至多一次强制 Cookie 刷新与一次国服验证，不在失败时自动换服务器。海外 1034 不调用现有仅支持国服的 RiskVerifier，避免将海外 Cookie 送到中国验证端点；明确提示在官方 HoYoLAB 完成验证后重试。该海外人工验证边界尚未被冒充成原生自动验证支持。

服务拒绝不属于当前账号的角色、UID/region 对不上、请求月份与响应月份不一致、错账号响应以及缺失的月度统计。刷新同一 UID/月失败或取消验证时，可保留先前成功结果，并标记“上次数据/本次未刷新”。不会把别的账号或月份作为失败回退。

UserService 的 completeTokenChainPublic 和相邻 refreshCookieTokenForced 仅作窄范围修复：await 前记录原选中账号对象；完成后只有同一选中对象仍有效时才更新会话 Cookie。账号切换、退出或同 ID 被新账号对象复用时，旧刷新不能覆盖新会话。不改变 Token 交换线上协议。

## 公告上下文与缓存

公告浏览提供六区服和上游 15 个游戏语言代码选择，不等于应用 15 语言本地化完成。默认从有效当前 UID 解析区服；未登录或无效 UID 默认国服。公开浏览区域与登录账号独立，选择海外公告不会传送登录凭据。

- Announcement 的 sourceRegion/sourceLanguage/sourceLevel 由请求上下文写入，不信任响应中的同名扩展
- 列表、首页卡片到详情页使用这三个来源字段；详情不再按后来切换的当前账号推断来源
- 列表/正文缓存键包含 region、language、level，正文进一步按 ann_id 匹配；30 分钟 TTL，最多 8 组上下文；列表返回副本，失败刷新不污染之前成功结果
- 同上下文并发请求合并；不同上下文返回值由 ViewModel generation 隔离；迟到的国服兑换码不进入海外公告视图
- 不再把游戏公告 ID 拼成未经证实的米游社文章 ID。仅 API/调用方提供且通过官方链接检查的 HTTPS 原文地址可用
- HTML 正文与官方网页回退分开：正文禁用 JavaScript，增加 CSP，转义标题/横幅属性；正文基址按来源选择，深浅色变更重载已取得正文，不重新跨区域请求

## 已执行验证与剩余验收

`NODE_PATH= TYPESCRIPT_PATH="$PWD/ci/node_modules/typescript" node tests/regional-content.cjs`：15 个确定性 host 测试通过，执行生产 ApiClient、UserService 包装方法、札记/公告服务、ViewModel 和首页札记卡片生命周期方法。覆盖六区服路径/参数/盐/headers、无跨区凭据、重新签名、有界重试、OS 风控不调用 CN、签名/请求/刷新/验证四个等待点的账号切换、UID/月份所有权、退出与同 ID 复用、首页晚到响应、公开公告零凭据、准确正文 ID、缓存与区域/语言竞态、无效 UID 回退、页面销毁和原文链接边界。

既有 account-protocol 与 ui-platform-contracts 测试也已通过。Native ArkTS parser 可解析当前生产源码，但这不替代原生编译、完整 lint 或设备运行。最终集成 HAP 和编译证据由对应提交的集成记录提供。真实国服/美服/欧服/亚服账号月度结果、海外验证入口、文件/网页交互、窄屏布局和服务端各语言可用性仍需后续实际验收；本轮未调用真实账号接口。
