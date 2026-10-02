# 本次账号与胡桃云实施记录

日期：2026-10-02。用户要求本日停止新增工作并收尾时的状态。本记录不宣称“除注入外全量移植完成”。初始差距和实施顺序见 `audit-accounts.md`。

## 已实现

### HTTP 凭据保护

- `CredentialPolicy.ets`：仅允许明确列出的 HTTPS 米哈游/HoYoLAB API 主机携带 Cookie，拒绝伪后缀、userinfo、非 443 端口及其他服务主机。
- `ApiClient.ets`：国服/海外默认会话 Cookie 分离；第三方 GitHub、胡桃云及公开数据地址不会获得米哈游 Cookie。显式大小写 Cookie 头同样受目标域限制。
- `ApiClient` / `PassportClient` 禁用自动重定向及 HTTP 缓存，避免凭据随跨域重定向转发。`maxRedirects` 在安装的 SDK 声明为 API 23+，覆盖 API 24 基线。
- 统一请求错误日志仅记录不含 query / fragment 的 URL；DS 签名不再打印原始请求体和查询串。

### 米游社 / HoYoLAB

- `User.isOversea` 读写现有数据库 `is_oversea` 列；账号去重包含地区，防止同 ID 的国服/海外账户互相覆盖。
- 保留 `account_id_v2/account_mid_v2/cookie_token_v2/ltuid_v2/ltmid_v2/ltoken_v2/stuid_v2/stoken_v2` 原键；修复 clone 丢失 v2 字段。
- `RegionUtil` 按上游 UID 正则与倒数第 9 位路由 9 / 10 位 UID，支持国服、B 服、美/欧/亚/港澳台。
- 登录页增加地区选择；海外支持手动 Cookie 与官方 HoYoLAB 网页登录状态读取，国内二维码、短信入口保留。
- 海外 SToken 交换使用上游 POST `STokenWrapper`；海外角色列表直接使用 Cookie 端点；账号昵称/头像切换海外源。
- 角色刷新保留默认角色，远端失败保留缓存；非当前账号刷新 Token 不再污染当前默认 HTTP 会话。
- `reloadLocalSession()` 供备份恢复后本地刷新内存账号与 Cookie，不触发联网或补 Token。
- 删除账号时清除此账号的系统便笺提醒。
- `HoyolabEndpoints` 集中路由；`HoyolabClient.getBaseHeaders(region)` 及便笺、活动日历、签到、补签到国服/海外端点和对应参数。海外 SOL 签到不附带国内 DS / x-rpc-signgame。

### 胡桃通行证与云

导航与路由由 UI 子任务接入 `HutaoCloudPage`。

- 明示服务提供方为 Snap.Hutao.Remastered 的 `https://homa.snaphutaorp.org`；不自动跨发行方或备用主机迁移凭据。
- `HutaoCloudClient` 使用独立 HTTP 请求、独立 Bearer Token 与独立设备 ID；不依赖米哈游 ApiClient；无 Cookie、重定向或自动上传。
- 上游通行证公钥从 PKCS#1 无损转换为 SPKI，使用 RSA-2048 OAEP-SHA1 / MGF1-SHA1，与上游协议一致；原始密码不持久化。
- `HutaoCloudVault` 使用独立 AssetStore 命名空间保存云会话，支持会话恢复与访问 Token 过期刷新。
- 页面提供登录、注册、邮件验证、重置密码、更换邮箱、注销、本机/全部设备凭据撤销、本地退出、服务到期状态和兑换码。
- 云祈愿：读取 UID 存档、按服务端 EndIds 增量上传、按本地最早游标下载并合并、删除指定 UID 云存档。上传、云删除、注销、撤销全部设备均需应用内明确确认。
- 祈愿 Int64 ID 无损传输，400 合并到 301 查询游标，包含 1000/2000 颂愿类型；时间按 UID 对应服务器 UTC 偏移转换。
- 下载先完整解析校验，再写入。缺少物品名称/品质元数据时明确失败，不把未知品质作为 0 星悄悄导入。
- 数据库界面提供 15 类统计查询：深渊概览、出场/使用/持有率、角色与武器搭配、队伍、剧诗、当期祈愿，以及角色/武器/常驻/集录/两种颂愿分布。当前为展开后的明细表，不等同 Windows 全部图表和交互。

## 必要验证

通过以下离线契约测试，均使用合成数据，不连接真实账号：

```sh
TYPESCRIPT_PATH=<安装的 TypeScript 目录> node tests/account-protocol.cjs
TYPESCRIPT_PATH=<安装的 TypeScript 目录> node tests/cloud-protocol.cjs
```

- 账号测试：UID 区域、特殊海外端点、v2 Cookie 完整性、跨域/跨地区默认凭据隔离、大小写 Cookie、重定向及缓存配置。
- 云测试：64 位 ID、合并卡池游标、各服务器时间、RSA 公钥可解析及 OAEP 参数/长度、独立 Bearer 传输、错误透传。RSA 运算在测试中由 Node crypto 模拟鸿蒙框架，不能替代设备上的 CryptoArchitectureKit 验证。
- 真实 ArkTS 集成编译由环境子任务执行；本子任务最后修正了云 HTTP 空对象的显式类型与页面 export，最终构建结果以主报告为准。

## 在线验证边界

仅对公开端点执行了不带任何凭据的 GET：

| 端点 | 此次响应 |
|---|---|
| `/Statistics/Overview?Last=false`（Homa） | HTTP 200，retcode 0 |
| `/Announcement/List?locale=zh-CN`（Homa） | HTTP 405 |
| `/strategy/all`（API） | HTTP 404 |

这只能证明该时刻公开深渊统计可用，不能证明通行证登录、注册邮件、云权限、付费服务、上传/下载或兑换可用。没有进行真实用户账号登录或任何真实记录上传/删除。服务端返回 HTTP / retcode 错误时页面显示失败，不伪造成功。

## 尚未完成

1. HoYoLAB 原生密码与第三方 OAuth 登录、x-rpc-verify 邮箱二次验证尚未独立移植；目前海外通过官方网页或手动 Cookie 入口。
2. 海外协议需要 API 24 设备上的真实登录验收，特别是设备指纹、风险验证、Web Cookie 范围与服务端兼容性。多个业务域的端点接入由相应子任务负责。
3. 胡桃云深渊/剧诗记录上传、上传检查和个人排名没有接入本页面；仅提供服务器统计读取。
4. 胡桃云统计尚缺 Windows 图表、排序筛选、队伍图示、角色图标与详细配装交互；当前明细表是可用初版。
5. 公共攻略端点此次返回 404，未实现依赖该端点的角色攻略界面；公告端点 405 未改为猜测方法绕过。
6. 颂愿或新物品若本地元数据缺名称/品质，云下载会明确报错；尚未补齐全部颂愿元数据映射。
7. 云凭据不包含在普通本地账号 JSON 备份中；恢复设备后可重新登录云通行证。
8. 邮件发送、注册、改邮箱、注销、Token 刷新、云权限与商业权益均需要服务端和用户在应用内授权操作后验收；没有使用真实凭据进行测试。
9. 原 Windows 胡桃云与 Remastered 账户是否迁移互通未得到验证，不支持在两个发行方之间自动转换账号。

按本次收尾指示停止新增功能，保留上述差距用于下一轮继续。
